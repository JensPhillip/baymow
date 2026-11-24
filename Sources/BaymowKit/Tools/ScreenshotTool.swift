import AppKit
import SwiftUI
import BaymowCore

/// `--render-ui <ud-mappe>`: tegner Baymows vinduer til PNG-filer (lyst og mørkt), så designet kan ses uden en skærm.
/// Bruger en lydløs motor med de rigtige stemmer og egne, midlertidige indstillinger – brugerens indstillinger røres ikke,
/// og der læses ingen brugertekst.
@MainActor
public enum ScreenshotTool {
    static let spellingDemo = "Jeg har ikke tit til at skrive i dag. Kan du huske at købe mælg på vej jem? Jeg glemte at sende rabborten."

    /// Lydløs motor, der låner en rigtig motors navn og stemmer.
    private final class SilentEngine: SpeechEngine {
        let engineID: String
        let voices: [Voice]
        let reportsWordProgress = true
        init(engineID: String, voices: [Voice]) { self.engineID = engineID; self.voices = voices }
        func installedVoices() -> [Voice] { voices }
        func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {
            onEvent(.started)
            onEvent(.progress(utf16Offset: text.utf16.count * 2 / 5))
        }
        func pause() {}
        func resume() {}
        func stop() {}
        func setRate(_ rate: Double) -> Bool { true }
    }

    static let demoText = "Mange oplever, at en tekst bliver lettere at forstå, når den bliver læst højt. Derfor bruger flere skoler oplæsning i undervisningen."

    public static func run(outputDirectory: String) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let suite = "dk.jpmag.baymow.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let demoAI = AIServices(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.rate = 1.5
        settings.hasCompletedOnboarding = false

        let apple = AppleSpeechEngine()
        let store = VoiceStore(directory: temp.appendingPathComponent("voices"))
        let piper = BackendSpeechEngine(backend: PiperBackend(store: store))
        let engines: [SpeechEngine] = [SilentEngine(engineID: apple.engineID, voices: apple.installedVoices()),
                                       SilentEngine(engineID: piper.engineID, voices: piper.installedVoices())]
        let catalog = VoiceCatalog(engines: engines, settings: settings)
        let downloader = ModelDownloader(store: store)
        let sessions = ReadingSessionManager(catalog: catalog, settings: settings,
                                             diagnostics: DiagnosticsService(directory: temp.appendingPathComponent("logs")))
        let model = MainWindowModel(settings: settings, catalog: catalog, downloader: downloader, sampleEngines: [])
        let onboarding = OnboardingModel(settings: settings, catalog: catalog, sampleEngine: engines[0])

        var failures = 0
        func shoot<V: View>(_ name: String, size: NSSize?, _ view: V) {
            for appearance in [("lys", NSAppearance.Name.aqua), ("mørk", NSAppearance.Name.darkAqua)] {
                if !render(view, size: size, appearance: NSAppearance(named: appearance.1)!,
                           to: out.appendingPathComponent("\(name)-\(appearance.0).png")) { failures += 1 }
            }
        }

        for page in MainPage.allCases {
            model.page = page
            shoot("hovedvindue-\(page.rawValue)", size: NSSize(width: 780, height: 600),
                  MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                           spelling: SpellingSettings(defaults: defaults, ai: demoAI), ai: demoAI, mail: MailReplySettings(defaults: defaults), screenText: ScreenTextSettings(defaults: defaults), shortcutRegistrationFailed: false))
        }
        // Siden Stavning med "Bedre hjælp via internet" slået til (AP-64).
        defaults.set(true, forKey: "spellingCloudEnabled")
        defaults.set(true, forKey: "spellingHelpEnabled")
        let demoUsage = demoAI.usage
        demoUsage.reset()
        for _ in 0..<143 { demoUsage.addCheck(.openai) }
        demoUsage.addTokens(.openai, input: 60_000, output: 25_000)
        for _ in 0..<12 { demoUsage.addCheck(.openai, feature: .mail) }
        demoUsage.addTokens(.openai, feature: .mail, input: 30_000, output: 4_000)
        model.page = .spelling
        shoot("hovedvindue-spelling-internet", size: NSSize(width: 780, height: 1250),
              MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                       spelling: SpellingSettings(defaults: defaults, ai: demoAI), ai: demoAI, mail: MailReplySettings(defaults: defaults), screenText: ScreenTextSettings(defaults: defaults), shortcutRegistrationFailed: false))
        defaults.set(false, forKey: "spellingCloudEnabled")
        defaults.set(false, forKey: "spellingHelpEnabled")
        // Start, Oplæsning og Genveje med stavehjælpen og tekst fra skærmen slået til.
        defaults.set(true, forKey: "spellingHelpEnabled")
        defaults.set(true, forKey: "screenTextEnabled")
        for page in [MainPage.start, .reading, .shortcut] {
            model.page = page
            shoot("hovedvindue-\(page.rawValue)-stavning", size: NSSize(width: 780, height: 1000),
                  MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                           spelling: SpellingSettings(defaults: defaults, ai: demoAI), ai: demoAI, mail: MailReplySettings(defaults: defaults), screenText: ScreenTextSettings(defaults: defaults), shortcutRegistrationFailed: false))
        }
        defaults.set(false, forKey: "spellingHelpEnabled")
        defaults.set(false, forKey: "screenTextEnabled")

        // Grafen over forbruget (AP-66) med opdigtede tal for 30 dage og musen over en dag.
        var demoDate = Calendar(identifier: .gregorian).startOfDay(for: Date()).addingTimeInterval(-29 * 86_400 + 43_200)
        let chartLog = CloudUsageLog(defaults: defaults, now: { demoDate })
        chartLog.reset()
        for day in 0..<30 {
            let checks = [0, 3, 8, 5, 0, 0, 12, 6, 4, 9, 2, 0, 7, 11, 5, 3, 0, 0, 6, 14, 8, 4, 10, 3, 0, 5, 9, 13, 7, 6][day]
            for _ in 0..<checks { chartLog.addCheck(.openai) }
            chartLog.addTokens(.openai, input: checks * 420, output: checks * 160)
            if day % 3 == 1 { chartLog.addCheck(.openai, feature: .mail); chartLog.addTokens(.openai, feature: .mail, input: 2_400, output: 300) }
            demoDate = demoDate.addingTimeInterval(86_400)
        }
        demoDate = demoDate.addingTimeInterval(-86_400)
        let selected = chartLog.lastDays(30).max { $0.entry.checks < $1.entry.checks }?.day
        shoot("forbrug-graf", size: NSSize(width: 640, height: 330),
              UsageChart(usage: chartLog, selectedDay: selected).padding(20))
        shoot("forbrug-afsnit", size: NSSize(width: 640, height: 560),
              Form { Section("Forbrug") { UsageView(usage: chartLog, showChart: true) } }.formStyle(.grouped))
        chartLog.reset()
        model.page = .start
        shoot("sidebjaelke", size: NSSize(width: 220, height: 420), MainSidebar(model: model, needsAttention: { $0 == .voices }))
        shoot("velkomst", size: nil, OnboardingView(model: onboarding, settings: settings) {})
        _ = sessions.start(text: demoText, sourceAppName: "Safari")
        shoot("afspiller", size: nil, PlayerView(sessions: sessions, settings: settings) {})
        sessions.togglePlayPause()
        shoot("afspiller-pause", size: nil, PlayerView(sessions: sessions, settings: settings) {})
        sessions.close()

        // Stavehjælpen (AP-63) med egne eksempelsætninger og den rigtige vagt; Macens model, hvis den er klar.
        let spellingModel = SpellingPanelModel(sourceBundleID: nil) { _, _, _ in }
        shoot("stavehjaelp-arbejder", size: nil, SpellingPanelView(model: spellingModel, onApply: {}, onCopy: {}, onClose: {}))
        let assistant = SpellingAssistant(corrector: AppleSpellingModel.makeCorrector(), checker: SystemWordChecker())
        let demoResult = SpellTest.runBlocking { await assistant.check(spellingDemo) }
        spellingModel.load(demoResult)
        shoot("stavehjaelp", size: nil, SpellingPanelView(model: spellingModel, onApply: {}, onCopy: {}, onClose: {}))
        var cloudResult = demoResult
        cloudResult.source = .cloud(.claude)
        let cloudModel = SpellingPanelModel(sourceBundleID: nil) { _, _, _ in }
        cloudModel.load(cloudResult)
        shoot("stavehjaelp-internet", size: nil, SpellingPanelView(model: cloudModel, onApply: {}, onCopy: {}, onClose: {}))
        // "Klarere sætninger" (AP-68) med et fast forslag fra stavetesten, så billedet ikke kræver internet.
        var claritySegments = SpellingGuard(checker: SystemWordChecker(), trusted: true, level: .clarity).review(
            "Jeg tænkte på om det måske kunne være en mulighed at vi eventuelt kunne mødes en dag i næste uge hvis det passer.",
            proposal: "Jeg tænkte på, om vi kunne mødes en dag i næste uge, hvis det passer.", language: .danish)
        for i in claritySegments.indices { claritySegments[i].id = i }
        let clarityModel = SpellingPanelModel(sourceBundleID: nil) { _, _, _ in }
        clarityModel.load(SpellingResult(segments: claritySegments, source: .cloud(.openai), language: .danish))
        shoot("stavehjaelp-klarere", size: nil, SpellingPanelView(model: clarityModel, onApply: {}, onCopy: {}, onClose: {}))
        // Mail-svar (AP-71): siden med mail-svar slået til og vinduet med et svar fra testtrådene.
        defaults.set(true, forKey: "mailReplyEnabled")
        defaults.set(true, forKey: "mailSparringEnabled")
        model.page = .mail
        shoot("hovedvindue-mail", size: NSSize(width: 780, height: 1250),
              MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                       spelling: SpellingSettings(defaults: defaults, ai: demoAI), ai: demoAI, mail: MailReplySettings(defaults: defaults), screenText: ScreenTextSettings(defaults: defaults),
                       shortcutRegistrationFailed: false))
        defaults.set(false, forKey: "mailReplyEnabled")
        defaults.set(false, forKey: "mailSparringEnabled")
        model.page = .start
        let mailModel = MailReplyPanelModel(speak: { _, _, _ in })
        mailModel.inserted = true
        mailModel.state = .done("Hej Peter,\n\nTak for tilbuddet. Vi vil gerne [gå videre / vente]. Licenserne skal leveres [hvornår?].")
        shoot("mailsvar", size: nil, MailReplyPanelView(model: mailModel, onUndo: {}, onClose: {}, onSettings: {}))
        // Sparring (AP-74) med en fast samtale om en af testtrådene.
        let sparringModel = MailSparringModel(
            mail: "Den 20. nov. 2026 kl. 09.12 skrev Peter Nielsen <peter@leverandoer.dk>:\n\nHej\n\nVedhæftet finder du vores tilbud på 120 licenser. Vil I gå videre med det, og hvornår skal de leveres?",
            subject: "Tilbud på licenser", provider: .openai, name: "Jens",
            corrector: CloudSpellingCorrector(provider: .openai, key: "skærmbillede"), speak: { _, _, _ in })
        sparringModel.addForPreview(question: "Hvad vil afsenderen?",
                                    answer: "Peter vil gerne vide to ting:\n- **Videre?** Om I vil gå videre med tilbuddet på 120 licenser.\n- **Levering:** Hvornår licenserne skal leveres.")
        sparringModel.addForPreview(question: "Hvad er prisen?", answer: "Det står ikke i mailen. Prisen står måske i det vedhæftede tilbud.")
        shoot("sparring", size: NSSize(width: 500, height: 560), MailSparringView(model: sparringModel, onSettings: {}))
        let assumedModel = MailReplyPanelModel(speak: { _, _, _ in })
        assumedModel.inserted = true
        assumedModel.followUp = true
        assumedModel.assumptions = ["At du kan holde mødet fredag kl. 13"]
        assumedModel.state = .done("Hej Karin,\n\nFredag kl. 13 passer fint.")
        shoot("mailsvar-antagelse", size: nil, MailReplyPanelView(model: assumedModel, onUndo: {}, onClose: {}, onSettings: {}))
        defaults.set(true, forKey: "spellingCloudEnabled")
        defaults.set(true, forKey: "mailReplyEnabled")
        model.page = .ai
        shoot("hovedvindue-ai", size: NSSize(width: 780, height: 1000),
              MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                       spelling: SpellingSettings(defaults: defaults, ai: demoAI), ai: demoAI, mail: MailReplySettings(defaults: defaults), screenText: ScreenTextSettings(defaults: defaults),
                       shortcutRegistrationFailed: false))
        defaults.set(false, forKey: "spellingCloudEnabled")
        defaults.set(false, forKey: "mailReplyEnabled")
        model.page = .start
        var offlineResult = demoResult
        offlineResult.cloudProblem = .offline
        let offlineModel = SpellingPanelModel(sourceBundleID: nil) { _, _, _ in }
        offlineModel.load(offlineResult)
        shoot("stavehjaelp-uden-internet", size: nil, SpellingPanelView(model: offlineModel, onApply: {}, onCopy: {}, onClose: {}))
        return failures == 0 ? 0 : 1
    }

    /// Tegner én visning i et usynligt vindue og gemmer den som PNG.
    private static func render<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance, to url: URL) -> Bool {
        // Vinduets baggrund tegnes ikke med, når kun indholdet tegnes; læg den bagved.
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let frame = NSRect(origin: .zero, size: size ?? hosting.fittingSize)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        // Skal ligge på skærmen, for at lister bliver tegnet – men usynligt.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSScreen.main?.visibleFrame.origin ?? .zero)
        window.orderFrontRegardless()
        // Lad SwiftUI og AppKit lægge visningen ud og tegne den, også ting der først vises efter en runde.
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }
        defer { window.orderOut(nil) }
        // Hele vinduets indhold (også sidebjælken, der ligger uden for SwiftUI-visningens egne lag).
        let root = window.contentView?.superview ?? hosting
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return false }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
