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
                           spelling: SpellingSettings(defaults: defaults), shortcutRegistrationFailed: false))
        }
        // Siden Stavning med "Bedre hjælp via internet" slået til (AP-64).
        defaults.set(true, forKey: "spellingCloudEnabled")
        let demoUsage = CloudUsageLog(defaults: defaults)
        demoUsage.reset()
        for _ in 0..<143 { demoUsage.addCheck(.openai) }
        demoUsage.addTokens(.openai, input: 60_000, output: 25_000)
        for _ in 0..<12 { demoUsage.addCheck(.claude) }
        demoUsage.addTokens(.claude, input: 5_000, output: 700)
        model.page = .spelling
        shoot("hovedvindue-spelling-internet", size: NSSize(width: 780, height: 1250),
              MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                       spelling: SpellingSettings(defaults: defaults), shortcutRegistrationFailed: false))
        defaults.set(false, forKey: "spellingCloudEnabled")
        // Start og Genvej med stavehjælpen slået til.
        defaults.set(true, forKey: "spellingHelpEnabled")
        for page in [MainPage.start, .shortcut] {
            model.page = page
            shoot("hovedvindue-\(page.rawValue)-stavning", size: NSSize(width: 780, height: 760),
                  MainView(model: model, settings: settings, catalog: catalog, downloader: downloader,
                           spelling: SpellingSettings(defaults: defaults), shortcutRegistrationFailed: false))
        }
        defaults.set(false, forKey: "spellingHelpEnabled")

        // Grafen over forbruget (AP-66) med opdigtede tal for 30 dage og musen over en dag.
        var demoDate = Calendar(identifier: .gregorian).startOfDay(for: Date()).addingTimeInterval(-29 * 86_400 + 43_200)
        let chartLog = CloudUsageLog(defaults: defaults, now: { demoDate })
        chartLog.reset()
        for day in 0..<30 {
            let checks = [0, 3, 8, 5, 0, 0, 12, 6, 4, 9, 2, 0, 7, 11, 5, 3, 0, 0, 6, 14, 8, 4, 10, 3, 0, 5, 9, 13, 7, 6][day]
            for _ in 0..<checks { chartLog.addCheck(.openai) }
            chartLog.addTokens(.openai, input: checks * 420, output: checks * 160)
            if day % 6 == 2 { chartLog.addCheck(.claude); chartLog.addTokens(.claude, input: 380, output: 40) }
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
        shoot("sidebjaelke", size: NSSize(width: 220, height: 300), MainSidebar(model: model, needsAttention: { $0 == .voices }))
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
