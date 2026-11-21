import AppKit
import SwiftUI
import BaymowCore

/// Tilstand for hovedvinduet: tilladelser, optagelse af genvej og stemmeprøver.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var hasPermission = TextCaptureService.hasPermission
    @Published var isRecordingShortcut = false
    @Published var shortcutError: String?
    /// Siden, der vises i hovedvinduet.
    @Published var page: MainPage = .start

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
        let text = voice.language == .danish ? DanishTextNormalizer.normalize(voice.language.sampleText) : voice.language.sampleText
        sampleEngines.first { $0.engineID == voice.engineID }?
            .speak(text, voice: voice, rate: settings.rate) { _ in }
    }

    /// Læser en af Baymows egne forklaringer op med den valgte danske stemme ("Hør"-knappen).
    func speakHelp(_ text: String) {
        sampleEngines.forEach { $0.stop() }
        guard let voice = catalog.voice(for: .danish),
              let engine = sampleEngines.first(where: { $0.engineID == voice.engineID }) else { return }
        engine.speak(DanishTextNormalizer.normalize(text), voice: voice, rate: settings.rate) { _ in }
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

/// Siderne i hovedvinduet: én ting pr. side, hver med sit ikon (designprincip 4).
enum MainPage: String, CaseIterable, Identifiable {
    case start, reading, display, voices, shortcut
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .reading: return "Oplæsning"
        case .display: return "Visning"
        case .voices: return "Stemmer"
        case .shortcut: return "Genvej"
        }
    }

    var symbol: String {
        switch self {
        case .start: return "house.fill"
        case .reading: return "speaker.wave.2.fill"
        case .display: return "eye.fill"
        case .voices: return "person.wave.2.fill"
        case .shortcut: return "keyboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .start: return .blue
        case .reading: return .orange
        case .display: return .purple
        case .voices: return .green
        case .shortcut: return .gray
        }
    }

    /// Én kort sætning under overskriften.
    var subtitle: String {
        switch self {
        case .start: return "Markér tekst, tryk på genvejen, og lyt."
        case .reading: return "Hvor hurtigt og på hvilket sprog."
        case .display: return "Se ordet, der bliver læst."
        case .voices: return "Vælg, hvem der læser for dig."
        case .shortcut: return "Tasterne, der starter oplæsningen."
        }
    }

    /// Det, "Hør"-knappen læser op. Almindeligt dansk uden forkortelser.
    func explanation(shortcut: Shortcut) -> String {
        switch self {
        case .start:
            return "Markér en tekst i et hvilket som helst program. Tryk så på \(shortcut.spokenKeys) på samme tid. Så læser Baymow teksten højt for dig."
        case .reading:
            return "Her vælger du, hvor hurtigt der bliver læst. Skildpadden er langsomt, og haren er hurtigt. Du kan også vælge sproget. Står den på automatisk, finder Baymow selv ud af, om teksten er dansk eller engelsk."
        case .display:
            return "Baymow kan vise dig, hvilket ord der bliver læst lige nu. Enten i et vindue med stor skrift, eller med et gult felt direkte i teksten. Du kan slå dem til og fra hver for sig."
        case .voices:
            return "Her vælger du en stemme til hvert sprog. Tryk på afspil for at høre en stemme. Tryk på vælg for at bruge den."
        case .shortcut:
            return "Genvejen er de taster, du trykker på samtidig for at få den markerede tekst læst op. Du kan skifte til andre taster, hvis du vil."
        }
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
        NavigationSplitView {
            MainSidebar(model: model, needsAttention: needsAttention)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(page: model.page, onListen: { model.speakHelp(model.page.explanation(shortcut: settings.shortcut)) })
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                Form { pageContent }
                    .formStyle(.grouped)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private func needsAttention(_ page: MainPage) -> Bool {
        switch page {
        case .start: return !model.hasPermission
        case .voices: return VoiceLibrary.needsMainVoiceGuide(installed: catalog.voices)
        case .shortcut: return shortcutRegistrationFailed
        case .reading, .display: return false
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .start: startPage
        case .reading: readingPage
        case .display: displayPage
        case .voices: voicesPage
        case .shortcut: shortcutPage
        }
    }

    // MARK: Start

    @ViewBuilder private var startPage: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: model.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(model.hasPermission ? .green : .orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hasPermission ? "Klar til at læse" : "Baymow skal have lov")
                        .font(.title3.weight(.semibold))
                    Text(model.hasPermission ? "Baymow kan se den tekst, du markerer." : "Uden lov kan Baymow ikke se din tekst.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.hasPermission {
                    Button {
                        TextCaptureService.requestPermission()
                        TextCaptureService.openAccessibilitySettings()
                    } label: {
                        Label("Giv lov", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Slå Baymow til under Anonymitet & sikkerhed → Tilgængelighed. Teksten bliver på din Mac.")
                }
            }
            .padding(.vertical, 6)
        }

        Section("Sådan gør du") {
            HStack(alignment: .top, spacing: 0) {
                HowToStep(number: 1, title: "Markér") {
                    Image(systemName: "character.cursor.ibeam").font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.blue)
                }
                arrow
                HowToStep(number: 2, title: "Tryk") { KeyCaps(shortcut: settings.shortcut, size: 30) }
                arrow
                HowToStep(number: 3, title: "Lyt") {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 10)
        }

        if VoiceLibrary.needsMainVoiceGuide(installed: catalog.voices) {
            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "arrow.down", color: .green, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hent den gode danske stemme").font(.headline)
                        Text("Sara (forbedret) er gratis.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.page = .voices } label: { Label("Vis mig", systemImage: "arrow.right") }
                        .controlSize(.large)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.tertiary)
            .frame(maxHeight: 60).accessibilityHidden(true)
    }

    // MARK: Oplæsning

    @ViewBuilder private var readingPage: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Hastighed", systemImage: "gauge.with.dots.needle.50percent").font(.headline)
                    Spacer()
                    Text(rateLabel(settings.rate))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("Hastighed \(String(format: "%.1f", settings.rate))")
                }
                HStack(spacing: 12) {
                    Image(systemName: "tortoise.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                        .help("Langsomt").accessibilityHidden(true)
                    Slider(value: $settings.rate, in: SettingsStore.rateRange, step: 0.1) { Text("Hastighed") }
                        .labelsHidden()
                    Image(systemName: "hare.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                        .help("Hurtigt").accessibilityHidden(true)
                    Button {
                        if let voice = catalog.voice(for: .danish) { model.playSample(voice) }
                    } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Hør hastigheden")
                    .accessibilityLabel("Hør hastigheden")
                }
                HStack(spacing: 8) {
                    ForEach([1.0, 1.5, 2.0, 2.5, 3.0], id: \.self) { preset in
                        let chosen = abs(settings.rate - preset) < 0.05
                        Button(rateLabel(preset)) { settings.rate = preset }
                            .buttonStyle(ChipStyle(chosen: chosen))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 6)
        }

        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sprog", systemImage: "character.bubble.fill").font(.headline)
                Picker("Sprog", selection: $settings.forcedLanguage) {
                    Text("🌐 Automatisk").tag(Language?.none)
                    ForEach(Language.allCases) { Text($0.flagAndName).tag(Language?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Automatisk: Baymow hører selv, om teksten er dansk eller engelsk.")
            }
            .padding(.vertical, 6)
            if settings.forcedLanguage == nil {
                Picker(selection: $settings.preferredLanguage) {
                    ForEach(Language.allCases) { Text($0.flagAndName).tag($0) }
                } label: {
                    Label("Hvis Baymow er i tvivl", systemImage: "questionmark.circle")
                }
                .help("Bruges, når teksten er for kort til at sproget kan genkendes sikkert.")
            }
        }
    }

    // MARK: Visning

    @ViewBuilder private var displayPage: some View {
        Section {
            OptionRow(symbol: "macwindow", color: .purple, title: "Vindue med teksten",
                      subtitle: "Stor skrift. Ordet bliver gult.",
                      help: "Under oplæsningen viser et vindue teksten med stor skrift, og ordet, der læses lige nu, bliver gult. Med stemmer, der kun melder hele sætninger, fremhæves sætningen. Kan også slås til og fra med knappen i afspilleren.",
                      isOn: $settings.showReadingWindow)
            OptionRow(symbol: "highlighter", color: .yellow, title: "Gult felt i teksten",
                      subtitle: "Der, hvor du har markeret.",
                      help: "Et gennemsigtigt gult felt følger ordet, der læses, i det program, du læser i. Virker i fx Noter, TextEdit, Safari og Mail. I Chrome, Word og Claude-appen kan det ikke lade sig gøre – brug vinduet dér.",
                      isOn: $settings.highlightInPlace)
        }
        Section {
            AppSupportRow(symbol: "checkmark.circle.fill", color: .green, apps: "Noter · TextEdit · Safari · Mail",
                          help: "Her virker det gule felt i teksten.")
            AppSupportRow(symbol: "xmark.circle.fill", color: .secondary, apps: "Chrome · Word · Claude",
                          help: "Her kan det gule felt ikke vises. Brug vinduet med teksten.")
        } header: {
            Label("Gult felt i teksten virker i", systemImage: "highlighter")
        }
    }

    // MARK: Stemmer

    @ViewBuilder private var voicesPage: some View {
        ForEach(Language.allCases) { language in
            Section {
                if language == .danish, VoiceLibrary.needsMainVoiceGuide(installed: catalog.voices) {
                    MainVoiceGuide()
                }
                let rows = VoiceLibrary.rows(for: language, installed: catalog.voices, downloadable: DownloadableVoice.catalog,
                                             isDownloaded: { id in downloader.store.isInstalled(id) },
                                             chosenID: catalog.voice(for: language)?.id)
                if rows.isEmpty {
                    Label("Ingen stemmer endnu", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VoiceRowView(row: row, model: model, settings: settings, downloader: downloader)
                }
            } header: {
                Text(language.flagAndName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            }
        }

        Section {
            HStack(spacing: 12) {
                IconTile(symbol: "plus", color: .gray, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flere stemmer").font(.headline)
                    Text("Hentes i Systemindstillinger.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { VoiceLibrary.openVoiceSettings() } label: { Label("Åbn", systemImage: "gearshape") }
                    .help("Flere systemstemmer hentes i \(VoiceLibrary.voiceSettingsPath). De dukker op her, så snart de er hentet.")
            }
            Label("Stemmerne virker uden internet.", systemImage: "wifi.slash")
                .font(.callout).foregroundStyle(.secondary)
                .help("Baymow bruger kun nettet, når du selv trykker Hent.")
        }
    }

    // MARK: Genvej

    @ViewBuilder private var shortcutPage: some View {
        Section {
            VStack(spacing: 16) {
                if model.isRecordingShortcut {
                    Label("Tryk de nye taster nu", systemImage: "keyboard.badge.ellipsis")
                        .font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .frame(height: 48)
                } else {
                    KeyCaps(shortcut: settings.shortcut, size: 48)
                }
                Text(settings.shortcut.spokenKeys).foregroundStyle(.secondary)
                HStack {
                    if model.isRecordingShortcut {
                        Button { model.cancelRecording() } label: { Label("Fortryd", systemImage: "xmark") }
                            .controlSize(.large)
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button { model.beginRecording() } label: { Label("Skift genvej", systemImage: "pencil") }
                            .controlSize(.large)
                            .help("Tryk, og tryk så de nye taster. Esc fortryder.")
                    }
                }
                if let error = model.shortcutError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if shortcutRegistrationFailed {
                    Label("Genvejen virker ikke. Et andet program bruger den måske. Vælg en anden.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }
}

/// Sidebjælken: siderne med farvede ikoner. Et orange mærke viser, hvor noget mangler.
struct MainSidebar: View {
    @ObservedObject var model: MainWindowModel
    let needsAttention: (MainPage) -> Bool

    var body: some View {
        List(MainPage.allCases, selection: Binding(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
            HStack(spacing: 10) {
                IconTile(symbol: page.symbol, color: page.color, size: 26)
                Text(page.title).font(.system(size: 15))
                Spacer(minLength: 0)
                if needsAttention(page) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        .accessibilityLabel("Mangler noget")
                }
            }
            .padding(.vertical, 3)
            .tag(page)
        }
        .listStyle(.sidebar)
    }
}

/// Overskriften øverst på hver side: ikon, titel, én kort sætning og "Hør".
private struct PageHeader: View {
    let page: MainPage
    let onListen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: page.symbol, color: page.color, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.system(size: 26, weight: .bold))
                Text(page.subtitle).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            ListenButton(action: onListen)
        }
    }
}

/// Ét trin i "Sådan gør du": billede, nummer og ét ord.
private struct HowToStep<Picture: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        VStack(spacing: 8) {
            picture().frame(height: 48)
            HStack(spacing: 6) {
                Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Color.accentColor, in: Circle())
                Text(title).font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// En valgmulighed med billede, kort titel og kontakt. Den lange forklaring står i hjælpeteksten.
private struct OptionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.large)
        }
        .padding(.vertical, 6)
        .help(help)
    }
}

/// Én linje i listen over programmer, hvor det gule felt virker eller ikke virker.
private struct AppSupportRow: View {
    let symbol: String
    let color: Color
    let apps: String
    let help: String

    var body: some View {
        Label {
            Text(apps)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .help(help)
    }
}

/// Vejledning, når Baymows danske hovedstemme, Sara (forbedret), ikke er hentet endnu.
private struct MainVoiceGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.down", color: .green, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hent Sara (forbedret)").font(.headline)
                    Text("Den bedste danske stemme. Gratis.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                GuideStep(number: 1, symbol: "gearshape.fill", text: "Tryk på Åbn nedenfor.")
                GuideStep(number: 2, symbol: "list.bullet", text: "Vælg Administrer stemmer…")
                GuideStep(number: 3, symbol: "arrow.down.circle.fill", text: "Find Dansk → Sara (forbedret).")
                GuideStep(number: 4, symbol: "arrow.uturn.backward", text: "Kom tilbage hertil.")
            }
            Button { VoiceLibrary.openVoiceSettings() } label: { Label("Åbn Systemindstillinger", systemImage: "gearshape") }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Vejen er: \(VoiceLibrary.voiceSettingsPath)")
        }
        .padding(.vertical, 6)
    }
}

/// Én stemme i biblioteket: navn, mærke, og knapper med ikoner.
private struct VoiceRowView: View {
    let row: VoiceLibrary.Row
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var downloader: ModelDownloader

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(row.isChosen ? Color.accentColor : Color.secondary.opacity(0.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(row.isChosen ? .semibold : .regular))
                    if row.id == VoiceLibrary.mainDanishVoiceID {
                        Badge(text: "Anbefalet", symbol: "star.fill", color: .green)
                    } else if !row.isApproved {
                        Badge(text: "Ikke anbefalet", symbol: "exclamationmark.triangle.fill", color: .orange)
                    }
                }
                Label(row.details, systemImage: row.kind == .system ? "desktopcomputer" : "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(row.kind.displayName)
                if let entry = row.downloadable, let error = downloader.errors[entry.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let voice = row.installed {
                Button { model.playSample(voice) } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Hør stemmen")
                .accessibilityLabel("Hør \(row.name)")
                Group {
                    if row.isChosen {
                        Text("Valgt").foregroundStyle(.secondary)
                    } else {
                        Button("Vælg") { settings.preferredVoiceIDs[voice.language.rawValue] = voice.id }
                            .help("Brug denne stemme til \(voice.language.displayName.lowercased())")
                    }
                }
                .frame(minWidth: 64)
            }
            if let entry = row.downloadable {
                if let fraction = downloader.progress[entry.id] {
                    ProgressView(value: fraction).frame(width: 90)
                } else if downloader.isInstalled(entry) {
                    Button { downloader.remove(entry) } label: { Image(systemName: "trash") }
                        .help("Fjern stemmen")
                        .accessibilityLabel("Fjern \(row.name)")
                } else {
                    Button { downloader.download(entry) } label: {
                        Label(downloader.errors[entry.id] == nil ? "Hent" : "Prøv igen", systemImage: "arrow.down.circle")
                    }
                    .help("Henter \(entry.sizeMB) MB fra nettet")
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(row.kind.displayName)\(row.isChosen ? ", valgt" : "")")
    }
}
