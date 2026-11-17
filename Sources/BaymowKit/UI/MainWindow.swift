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
                    let voices = catalog.voices(for: language)
                    if voices.isEmpty {
                        Text("Ingen stemmer installeret til \(language.displayName.lowercased()).").foregroundStyle(.secondary)
                    }
                    let selectedID = catalog.voice(for: language)?.id
                    ForEach(voices) { voice in
                        HStack {
                            Image(systemName: voice.id == selectedID ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(voice.id == selectedID ? Color.accentColor : .secondary)
                            Text(voice.name)
                            Text("\(voice.locale) · \(voice.quality.displayName)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Prøv") { model.playSample(voice) }.controlSize(.small)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { settings.preferredVoiceIDs[language.rawValue] = voice.id }
                        .accessibilityAddTraits(voice.id == selectedID ? .isSelected : [])
                    }
                }
            }

            Section("Hent stemmer") {
                ForEach(DownloadableVoice.catalog) { voice in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(voice.name) · \(voice.language.displayName)")
                            Text(downloader.errors[voice.id] ?? voice.licenseNote)
                                .font(.caption)
                                .foregroundStyle(downloader.errors[voice.id] == nil ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        if let fraction = downloader.progress[voice.id] {
                            ProgressView(value: fraction).frame(width: 120)
                        } else if downloader.isInstalled(voice) {
                            Text("Installeret").font(.caption).foregroundStyle(.secondary)
                            Button("Fjern") { downloader.remove(voice) }.controlSize(.small)
                        } else {
                            Button("Hent (\(voice.sizeMB) MB)") { downloader.download(voice) }.controlSize(.small)
                        }
                    }
                }
                Text("Hentede stemmer virker uden internet. Baymow bruger kun nettet, når du selv trykker Hent.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("Flere og bedre systemstemmer hentes i Systemindstillinger → Tilgængelighed → Oplæst indhold → Systemstemme → Administrer stemmer. De dukker op her, når de er hentet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}
