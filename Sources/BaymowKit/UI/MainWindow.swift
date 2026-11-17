import AppKit
import SwiftUI
import BaymowCore

/// Tilstand for hovedvinduet: tilladelser, optagelse af genvej og stemmeprøver.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var hasPermission = TextCaptureService.hasPermission
    @Published var isRecordingShortcut = false
    @Published var shortcutError: String?

    let settings: SettingsStore
    let catalog: VoiceCatalog
    let downloader: ModelDownloader
    /// Egne motorer til stemmeprøver, så en prøve ikke forstyrrer en igangværende oplæsning.
    private let sampleEngines: [SpeechEngine]
    private var timer: Timer?
    private var keyMonitor: Any?

    init(settings: SettingsStore, catalog: VoiceCatalog, downloader: ModelDownloader, sampleEngines: [SpeechEngine]) {
        self.settings = settings
        self.catalog = catalog
        self.downloader = downloader
        self.sampleEngines = sampleEngines
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        cancelRecording()
        sampleEngines.forEach { $0.stop() }
    }

    private func refresh() {
        let trusted = TextCaptureService.hasPermission
        if trusted != hasPermission { hasPermission = trusted }
        catalog.refresh()
    }

    func playSample(_ voice: Voice) {
        sampleEngines.forEach { $0.stop() }
        sampleEngines.first { $0.engineID == voice.engineID }?
            .speak(voice.language.sampleText, voice: voice, rate: settings.rate) { _ in }
    }

    func beginRecording() {
        cancelRecording()
        isRecordingShortcut = true
        shortcutError = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.cancelRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty,
                  let label = event.charactersIgnoringModifiers?.uppercased(), !label.isEmpty else {
                self.shortcutError = "Genvejen skal indeholde ⌘, ⌥ eller ⌃ sammen med en tast."
                return nil
            }
            self.settings.shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, keyLabel: label)
            self.cancelRecording()
            return nil
        }
    }

    func cancelRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecordingShortcut = false
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var catalog: VoiceCatalog
    @ObservedObject var downloader: ModelDownloader
    /// Sat af AppShell, hvis den valgte genvej ikke kunne registreres.
    let shortcutRegistrationFailed: Bool

    var body: some View {
        Form {
            Section("Kom i gang") {
                HStack {
                    Image(systemName: model.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.hasPermission ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasPermission ? "Baymow har adgang til markeret tekst" : "Baymow skal have lov til at læse markeret tekst")
                        if !model.hasPermission {
                            Text("Slå Baymow til under Anonymitet & sikkerhed → Tilgængelighed. Teksten bliver på din Mac.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !model.hasPermission {
                        Button("Giv adgang…") {
                            TextCaptureService.requestPermission()
                            TextCaptureService.openAccessibilitySettings()
                        }
                    }
                }
                Text("Markér tekst i et program, og tryk \(settings.shortcut.displayString) for at få den læst op.")
                    .foregroundStyle(.secondary)
            }

            Section("Tastaturgenvej") {
                HStack {
                    Text("Læs markeret tekst")
                    Spacer()
                    Text(model.isRecordingShortcut ? "Tryk den nye genvej… (Esc fortryder)" : settings.shortcut.displayString)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(model.isRecordingShortcut ? .secondary : .primary)
                    Button(model.isRecordingShortcut ? "Fortryd" : "Skift…") {
                        model.isRecordingShortcut ? model.cancelRecording() : model.beginRecording()
                    }
                }
                if let error = model.shortcutError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                } else if shortcutRegistrationFailed {
                    Text("Genvejen kunne ikke registreres. Den bruges måske af et andet program – vælg en anden.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Sprog og hastighed") {
                Picker("Oplæsningssprog", selection: $settings.forcedLanguage) {
                    Text("Automatisk").tag(Language?.none)
                    ForEach(Language.allCases) { Text("Altid \($0.displayName.lowercased())").tag(Language?.some($0)) }
                }
                Picker("Foretrukket sprog", selection: $settings.preferredLanguage) {
                    ForEach(Language.allCases) { Text($0.displayName).tag($0) }
                }
                .help("Bruges, når teksten er for kort til at sproget kan genkendes sikkert.")
                HStack {
                    Text("Hastighed")
                    Slider(value: $settings.rate, in: SettingsStore.rateRange, step: 0.1)
                    Text(String(format: "%.1f×", settings.rate)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }

            ForEach(Language.allCases) { language in
                Section("Stemmer – \(language.displayName.lowercased())") {
                    if language == .danish, VoiceLibrary.needsMainVoiceGuide(installed: catalog.voices) {
                        MainVoiceGuide()
                    }
                    let rows = VoiceLibrary.rows(for: language, installed: catalog.voices, downloadable: DownloadableVoice.catalog,
                                                 isDownloaded: { id in downloader.store.isInstalled(id) },
                                                 chosenID: catalog.voice(for: language)?.id)
                    if rows.isEmpty {
                        Text("Ingen stemmer installeret til \(language.displayName.lowercased()).").foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        VoiceRowView(row: row, model: model, settings: settings, downloader: downloader)
                    }
                }
            }

            Section {
                Text("Hentede stemmer virker uden internet. Baymow bruger kun nettet, når du selv trykker Hent.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Flere systemstemmer hentes i \(VoiceLibrary.voiceSettingsPath). De dukker op her, så snart de er hentet.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Åbn Systemindstillinger for flere stemmer") { VoiceLibrary.openVoiceSettings() }
                    .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

/// Vejledning, når Baymows danske hovedstemme, Sara (forbedret), ikke er hentet endnu.
private struct MainVoiceGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hent den anbefalede stemme: Sara (forbedret)", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("Baymow læser dansk bedst med Apples stemme Sara (forbedret). Den er gratis, men skal hentes én gang.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("1. Tryk på knappen nedenfor.")
                Text("2. Ud for Systemstemme: vælg Administrer stemmer… nederst i menuen.")
                Text("3. Find Dansk, og tryk på pilen ud for Sara (forbedret).")
                Text("4. Kom tilbage hertil. Stemmen dukker op af sig selv, når den er hentet.")
            }
            .font(.callout)
            Text("Vejen er: \(VoiceLibrary.voiceSettingsPath)")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Åbn Systemindstillinger") { VoiceLibrary.openVoiceSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

/// Én stemme i biblioteket: navn, type, størrelse og de knapper, der giver mening for den.
private struct VoiceRowView: View {
    let row: VoiceLibrary.Row
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var downloader: ModelDownloader

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: row.isChosen ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(row.isChosen ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                    if row.id == VoiceLibrary.mainDanishVoiceID {
                        Text("Anbefalet").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    } else if !row.isApproved {
                        Text("Ikke anbefalet").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Text("\(row.kind.displayName) · \(row.details)").font(.caption).foregroundStyle(.secondary)
                if let entry = row.downloadable, let error = downloader.errors[entry.id] {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let voice = row.installed {
                Button("Prøv") { model.playSample(voice) }.controlSize(.small)
                if row.isChosen {
                    Text("Valgt").font(.caption).foregroundStyle(.secondary).frame(minWidth: 44)
                } else {
                    Button("Vælg") { settings.preferredVoiceIDs[voice.language.rawValue] = voice.id }
                        .controlSize(.small)
                        .help("Brug denne stemme til \(voice.language.displayName.lowercased())")
                }
            }
            if let entry = row.downloadable {
                if let fraction = downloader.progress[entry.id] {
                    ProgressView(value: fraction).frame(width: 90)
                } else if downloader.isInstalled(entry) {
                    Button("Fjern") { downloader.remove(entry) }.controlSize(.small)
                } else {
                    Button(downloader.errors[entry.id] == nil ? "Hent" : "Prøv igen") { downloader.download(entry) }
                        .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(row.kind.displayName)\(row.isChosen ? ", valgt" : "")")
    }
}
