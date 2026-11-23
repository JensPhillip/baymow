import AppKit
import SwiftUI
import BaymowCore

/// Tilstand for hovedvinduet: tilladelser, optagelse af genvej og stemmeprøver.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var hasPermission = TextCaptureService.hasPermission
    /// Hvilken genvej der optages lige nu (`nil`: ingen).
    @Published var recording: ShortcutTarget?
    @Published var shortcutError: (target: ShortcutTarget, text: String)?
    var isRecordingShortcut: Bool { recording != nil }

    enum ShortcutTarget: Equatable { case read, spelling, mail }
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
        stopSpeaking()
    }

    private func refresh() {
        let trusted = TextCaptureService.hasPermission
        if trusted != hasPermission { hasPermission = trusted }
        catalog.refresh()
    }

    /// Det, der bliver læst op lige nu ("Hør"-knapper og stemmeprøver), så knappen kan vise "Stop".
    @Published private(set) var playing: String?
    private var playToken = 0

    /// Læser op, eller stopper, hvis det samme allerede bliver læst op.
    private func toggle(_ id: String, text: String, voice: Voice) {
        let wasPlaying = playing == id
        stopSpeaking()
        guard !wasPlaying,
              let engine = sampleEngines.first(where: { $0.engineID == voice.engineID }) else { return }
        playToken += 1
        let token = playToken
        playing = id
        engine.speak(text, voice: voice, rate: settings.rate) { [weak self] event in
            switch event {
            case .finished, .failed:
                Task { @MainActor in
                    guard let self, self.playToken == token else { return }
                    self.playing = nil
                }
            default: break
            }
        }
    }

    func stopSpeaking() {
        playToken += 1
        sampleEngines.forEach { $0.stop() }
        playing = nil
    }

    func playSample(_ voice: Voice, id: String? = nil) {
        let text = voice.language == .danish ? DanishTextNormalizer.normalize(voice.language.sampleText) : voice.language.sampleText
        toggle(id ?? "sample:\(voice.id)", text: text, voice: voice)
    }

    /// Læser en af Baymows egne forklaringer op med den valgte danske stemme ("Hør"-knappen). Et tryk mere stopper.
    func speakHelp(_ text: String, id: String = "help") {
        guard let voice = catalog.voice(for: .danish) else { return }
        toggle(id, text: DanishTextNormalizer.normalize(text), voice: voice)
    }

    /// Optager nye taster til en genvej. `apply` gemmer dem, eller returnerer en fejltekst (fx hvis tasterne allerede
    /// bruges af Baymows anden genvej).
    func beginRecording(_ target: ShortcutTarget, apply: @escaping (Shortcut) -> String?) {
        cancelRecording()
        recording = target
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
                self.shortcutError = (target, "Genvejen skal indeholde ⌘, ⌥ eller ⌃ sammen med en tast.")
                return nil
            }
            let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, keyLabel: label)
            if let error = apply(shortcut) {
                self.shortcutError = (target, error)
                return nil
            }
            self.cancelRecording()
            return nil
        }
    }

    func cancelRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = nil
    }
}

/// Siderne i hovedvinduet: én ting pr. side, hver med sit ikon (designprincip 4).
enum MainPage: String, CaseIterable, Identifiable {
    case start, reading, display, voices, spelling, mail, ai, shortcut
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .reading: return "Oplæsning"
        case .display: return "Visning"
        case .voices: return "Stemmer"
        case .spelling: return "Stavning"
        case .mail: return "Mail"
        case .ai: return "AI og nøgler"
        case .shortcut: return "Genvej"
        }
    }

    var symbol: String {
        switch self {
        case .start: return "house.fill"
        case .reading: return "speaker.wave.2.fill"
        case .display: return "eye.fill"
        case .voices: return "person.wave.2.fill"
        case .spelling: return "textformat.abc.dottedunderline"
        case .mail: return "envelope.fill"
        case .ai: return "sparkles"
        case .shortcut: return "keyboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .start: return .blue
        case .reading: return .orange
        case .display: return .purple
        case .voices: return .green
        case .spelling: return .teal
        case .mail: return .indigo
        case .ai: return .pink
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
        case .spelling: return "Få rettet det, du selv skriver."
        case .mail: return "Få et forslag til svar på en mail."
        case .ai: return "Nøgler, firmaer og forbrug."
        case .shortcut: return "Tasterne, der starter Baymow."
        }
    }

    /// Det, "Hør"-knappen læser op. Almindeligt dansk uden forkortelser.
    @MainActor
    func explanation(shortcut: Shortcut, spelling: SpellingSettings, mail: MailReplySettings? = nil) -> String {
        switch self {
        case .start:
            let read = "Markér en tekst i et hvilket som helst program. Tryk så på \(shortcut.spokenKeys) på samme tid. Så læser Baymow teksten højt for dig."
            guard spelling.isEnabled else { return read }
            return read + " Vil du have rettet din egen tekst, så markér den, og tryk på \(spelling.shortcut.spokenKeys)."
        case .reading:
            return "Her vælger du, hvor hurtigt der bliver læst. Skildpadden er langsomt, og haren er hurtigt. Du kan også vælge sproget. Står den på automatisk, finder Baymow selv ud af, om teksten er dansk eller engelsk."
        case .display:
            return "Baymow kan vise dig, hvilket ord der bliver læst lige nu. Enten i et vindue med stor skrift, eller med et gult felt direkte i teksten. Du kan slå dem til og fra hver for sig."
        case .voices:
            return "Her vælger du en stemme til hvert sprog. Tryk på afspil for at høre en stemme. Tryk på vælg for at bruge den."
        case .spelling:
            return "Stavehjælpen retter den tekst, du selv har skrevet. Markér teksten, og tryk på \(spelling.shortcut.spokenKeys) på samme tid. Baymow viser rettelserne med farver. Grøn er rettet. Orange skal du selv tjekke. Tryk på et ord for at vælge det og høre det. Tryk til sidst på Brug rettelsen." + (spelling.cloudEnabled ? " Du har slået bedre hjælp via internet til, så teksten bliver sendt til \(spelling.cloudProvider.title)." : " Din tekst bliver på din Mac.")
        case .mail:
            let keys = (mail?.shortcut ?? MailReplySettings.standardShortcut).spokenKeys
            return "Mail svar skriver et forslag til et svar på en mail. Tryk på Svar i Apple Mail, og skriv nogle stikord øverst. Tryk så på \(keys) med markøren lige efter stikordene. Baymow sender stikordene og mailtråden til \((mail?.provider ?? .openai).title) og sætter svaret ind i stedet for stikordene. Står der noget i firkantede klammer, skal du selv udfylde det. Læs altid svaret igennem, før du sender det."
        case .ai:
            return "Her gemmer du dine nøgler til ChatGPT og Claude. Du vælger, hvilket firma stavning og mail bruger, og du kan se, hvad det har kostet. Prisen er et skøn. Den præcise regning står hos firmaerne."
        case .shortcut:
            return "En genvej er de taster, du trykker på samtidig. Den ene får den markerede tekst læst op. De andre retter stavningen i din egen tekst og skriver svar på mails. Du kan skifte til andre taster, hvis du vil."
        }
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var catalog: VoiceCatalog
    @ObservedObject var downloader: ModelDownloader
    @ObservedObject var spelling: SpellingSettings
    @ObservedObject var ai: AIServices
    @ObservedObject var mail: MailReplySettings
    /// Sat af AppShell, hvis den valgte genvej ikke kunne registreres.
    let shortcutRegistrationFailed: Bool

    var body: some View {
        NavigationSplitView {
            MainSidebar(model: model, needsAttention: needsAttention)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(page: model.page, isPlaying: model.playing == "help:\(model.page.rawValue)", onListen: {
                    model.speakHelp(model.page.explanation(shortcut: settings.shortcut, spelling: spelling, mail: mail),
                                    id: "help:\(model.page.rawValue)")
                })
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
        case .spelling: return spelling.isEnabled && spelling.shortcutFailed
        case .mail: return mail.isEnabled && (mail.shortcutFailed || !ai.savedKeys.contains(mail.provider))
        case .ai: return (spelling.cloudEnabled && !ai.savedKeys.contains(spelling.cloudProvider))
            || (mail.isEnabled && !ai.savedKeys.contains(mail.provider))
        case .reading, .display: return false
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .start: startPage
        case .reading: readingPage
        case .display: displayPage
        case .voices: voicesPage
        case .spelling: SpellingSettingsPage(settings: spelling, speak: { model.speakHelp($0) }, openAIPage: { model.page = .ai })
        case .mail: MailSettingsPage(settings: mail, ai: ai, openAIPage: { model.page = .ai })
        case .ai: AISettingsPage(ai: ai, spelling: spelling, mail: mail)
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

        Section(spelling.isEnabled || mail.isEnabled ? "Læs op" : "Sådan gør du") {
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

        if spelling.isEnabled {
            Section("Ret din egen tekst") {
                HStack(alignment: .top, spacing: 0) {
                    HowToStep(number: 1, title: "Markér") {
                        Image(systemName: "character.cursor.ibeam").font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.teal)
                    }
                    arrow
                    HowToStep(number: 2, title: "Tryk") { KeyCaps(shortcut: spelling.shortcut, size: 30) }
                    arrow
                    HowToStep(number: 3, title: "Ret") {
                        Image(systemName: "textformat.abc.dottedunderline").font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.teal)
                    }
                }
                .padding(.vertical, 10)
            }
        }

        if mail.isEnabled {
            Section("Svar på en mail") {
                HStack(alignment: .top, spacing: 0) {
                    HowToStep(number: 1, title: "Stikord") {
                        Image(systemName: "list.bullet").font(.system(size: 30, weight: .medium)).foregroundStyle(.indigo)
                    }
                    arrow
                    HowToStep(number: 2, title: "Tryk") { KeyCaps(shortcut: mail.shortcut, size: 30) }
                    arrow
                    HowToStep(number: 3, title: "Svar") {
                        Image(systemName: "envelope.fill").font(.system(size: 30, weight: .medium)).foregroundStyle(.indigo)
                    }
                }
                .padding(.vertical, 10)
            }
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
                        if let voice = catalog.voice(for: .danish) { model.playSample(voice, id: "rate") }
                    } label: {
                        Image(systemName: model.playing == "rate" ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(model.playing == "rate" ? "Stop" : "Hør hastigheden")
                    .accessibilityLabel(model.playing == "rate" ? "Stop" : "Hør hastigheden")
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
            shortcutEditor(.read, title: "Læs op", symbol: "speaker.wave.2.fill", color: .blue,
                           shortcut: settings.shortcut, failed: shortcutRegistrationFailed) { new in
                if let taken = taken(new, except: .read) { return taken }
                settings.shortcut = new
                return nil
            }
        }
        Section {
            shortcutEditor(.spelling, title: "Ret stavning", symbol: "textformat.abc.dottedunderline", color: .teal,
                           shortcut: spelling.shortcut, failed: spelling.isEnabled && spelling.shortcutFailed) { new in
                if let taken = taken(new, except: .spelling) { return taken }
                spelling.shortcut = new
                return nil
            }
            if !spelling.isEnabled {
                Label("Stavehjælpen er slået fra. Slå den til på siden Stavning.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            shortcutEditor(.mail, title: "Svar på mail", symbol: "envelope.fill", color: .indigo,
                           shortcut: mail.shortcut, failed: mail.isEnabled && mail.shortcutFailed) { new in
                if let taken = taken(new, except: .mail) { return taken }
                mail.shortcut = new
                return nil
            }
            if !mail.isEnabled {
                Label("Mail-svar er slået fra. Slå det til på siden Mail.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bruges tasterne allerede af en af Baymows andre genveje?
    private func taken(_ shortcut: Shortcut, except target: MainWindowModel.ShortcutTarget) -> String? {
        if target != .read, shortcut == settings.shortcut { return "De taster bruges allerede til at læse op." }
        if target != .spelling, shortcut == spelling.shortcut { return "De taster bruges allerede til at rette stavning." }
        if target != .mail, shortcut == mail.shortcut { return "De taster bruges allerede til mail-svar." }
        return nil
    }

    /// Én genvej: hvad den gør, tasterne, og "Skift genvej".
    private func shortcutEditor(_ target: MainWindowModel.ShortcutTarget, title: String, symbol: String, color: Color,
                                shortcut: Shortcut, failed: Bool,
                                apply: @escaping (Shortcut) -> String?) -> some View {
        let recording = model.recording == target
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(shortcut.spokenKeys).foregroundStyle(.secondary)
                }
                Spacer()
                if recording {
                    Label("Tryk de nye taster nu", systemImage: "keyboard.badge.ellipsis")
                        .font(.headline).foregroundStyle(Color.accentColor)
                } else {
                    KeyCaps(shortcut: shortcut, size: 34)
                }
            }
            HStack {
                Spacer()
                if recording {
                    Button { model.cancelRecording() } label: { Label("Fortryd", systemImage: "xmark") }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button { model.beginRecording(target, apply: apply) } label: { Label("Skift genvej", systemImage: "pencil") }
                        .controlSize(.large)
                        .help("Tryk, og tryk så de nye taster. Esc fortryder.")
                }
            }
            if let error = model.shortcutError, error.target == target {
                Label(error.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if failed {
                Label("Genvejen virker ikke. Et andet program bruger den måske. Vælg en anden.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
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
    let isPlaying: Bool
    let onListen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: page.symbol, color: page.color, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.system(size: 26, weight: .bold))
                Text(page.subtitle).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            ListenButton(isPlaying: isPlaying, action: onListen)
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
struct OptionRow: View {
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
                let isPlaying = model.playing == "sample:\(voice.id)"
                Button { model.playSample(voice) } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(isPlaying ? "Stop" : "Hør stemmen")
                .accessibilityLabel(isPlaying ? "Stop" : "Hør \(row.name)")
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
