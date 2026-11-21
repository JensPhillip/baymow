// KERNEKONTRAKT. Disse tests beskriver, hvordan MVP'ens kerne skal opføre sig.
// De må kun ændres som en bevidst kerneændring – se docs/PROJEKTPLAN.md afsnit 3 ("Kernen").
// Fejler en af dem efter din ændring, er det din ændring, der er forkert – ikke testen.

import XCTest
@testable import BaymowCore

/// TTS-motor til tests: taler ikke, men husker kald og lader testen styre events.
@MainActor
final class FakeEngine: SpeechEngine {
    let engineID = "fake"
    var spoken: [(text: String, voice: Voice, rate: Double)] = []
    var handler: ((SpeechEvent) -> Void)?
    var stopCount = 0
    var isPaused = false

    lazy var baseVoices: [Voice] = [
        Voice(id: "da-1", name: "Dansk standard", language: .danish, locale: "da-DK", quality: .standard, engineID: engineID),
        Voice(id: "da-2", name: "Dansk forbedret", language: .danish, locale: "da-DK", quality: .enhanced, engineID: engineID),
        Voice(id: "en-1", name: "English", language: .english, locale: "en-US", quality: .standard, engineID: engineID),
    ]
    var extraVoices: [Voice] = []
    var overrides: [String: String] = [:]
    /// Når sat, kan motoren skifte hastighed undervejs, og skiftene huskes her.
    var supportsLiveRate = false
    var liveRates: [Double] = []

    func setRate(_ rate: Double) -> Bool {
        guard supportsLiveRate else { return false }
        liveRates.append(rate)
        return true
    }

    func pronunciationOverrides(for language: Language) -> [String: String] { language == .danish ? overrides : [:] }

    func installedVoices() -> [Voice] { baseVoices + extraVoices }

    func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {
        spoken.append((text, voice, rate))
        handler = onEvent
        isPaused = false
    }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { stopCount += 1; handler = nil }
}

@MainActor
final class CoreContractTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: SettingsStore!
    private var engine: FakeEngine!
    private var catalog: VoiceCatalog!
    private var sessions: ReadingSessionManager!
    private var logDir: URL!
    private var diagnostics: DiagnosticsService!

    private let danish = "Dette er en almindelig dansk sætning om vejret i dag. Den handler også om, hvordan man læser en tekst højt."
    private let english = "This is an ordinary English sentence about the weather today. It is also about reading a text aloud."

    override func setUp() async throws {
        suite = "baymow.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = SettingsStore(defaults: defaults)
        engine = FakeEngine()
        catalog = VoiceCatalog(engines: [engine], settings: settings)
        logDir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        diagnostics = DiagnosticsService(directory: logDir)
        sessions = ReadingSessionManager(catalog: catalog, settings: settings, diagnostics: diagnostics)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: logDir)
    }

    // MARK: Sprog

    func testLanguageDetection() {
        let service = LanguageDetectionService()
        XCTAssertEqual(service.dominantLanguage(of: danish, fallback: .english), .danish)
        XCTAssertEqual(service.dominantLanguage(of: english, fallback: .danish), .english)
        XCTAssertEqual(service.dominantLanguage(of: "12345", fallback: .danish), .danish)
    }

    func testAutomaticLanguagePicksMatchingVoice() {
        sessions.start(text: english)
        XCTAssertEqual(sessions.language, .english)
        XCTAssertEqual(engine.spoken.last?.voice.id, "en-1")
    }

    func testForcedLanguageOverridesDetection() {
        settings.forcedLanguage = .danish
        sessions.start(text: english)
        XCTAssertEqual(sessions.language, .danish)
    }

    func testBestQualityVoiceIsDefaultAndPreferenceWins() {
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "da-2")
        settings.preferredVoiceIDs["da"] = "da-1"
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "da-1")
    }

    func testManualLanguageOverrideRespeaksWithNewVoice() {
        sessions.start(text: danish)
        sessions.setLanguage(.english)
        XCTAssertEqual(sessions.language, .english)
        XCTAssertEqual(engine.spoken.last?.voice.id, "en-1")
        XCTAssertEqual(sessions.state, .speaking)
    }

    func testUnapprovedVoiceIsNeverChosenAutomatically() {
        let experimental = Voice(id: "da-neural", name: "Forsøg", language: .danish, locale: "da-DK", quality: .neural,
                                 engineID: "fake", isApprovedDefault: false)
        engine.extraVoices = [experimental]
        catalog.refresh()
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "da-2", "en ikke-godkendt stemme må ikke blive standard")

        settings.preferredVoiceIDs["da"] = "da-neural"
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "da-neural", "brugerens eget valg gælder altid")
    }

    func testUnapprovedVoiceIsUsedWhenNothingElseExists() {
        let only = Voice(id: "x", name: "Eneste", language: .danish, locale: "da-DK", quality: .neural,
                         engineID: "fake", isApprovedDefault: false)
        engine.baseVoices = []
        engine.extraVoices = [only]
        catalog.refresh()
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "x")
    }

    // MARK: Bidder

    func testChunkerKeepsAllTextAndSplitsOnSentences() {
        let text = String(repeating: danish + " ", count: 20)
        let chunks = TextChunker.chunks(for: text, targetLength: 300)
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 300 })
    }

    func testChunkerIgnoresBlankText() {
        XCTAssertTrue(TextChunker.chunks(for: "  \n ").isEmpty)
    }

    // MARK: Sessioner

    func testPauseResumeStopRestart() {
        sessions.start(text: danish)
        XCTAssertEqual(sessions.state, .speaking)
        sessions.pause()
        XCTAssertEqual(sessions.state, .paused)
        XCTAssertTrue(engine.isPaused)
        sessions.resume()
        XCTAssertEqual(sessions.state, .speaking)
        XCTAssertFalse(engine.isPaused)

        sessions.stop()
        XCTAssertEqual(sessions.state, .stopped)
        XCTAssertTrue(sessions.hasSession, "teksten skal kunne genstartes efter stop")

        sessions.togglePlayPause()
        XCTAssertEqual(sessions.state, .speaking)
        XCTAssertEqual(engine.spoken.count, 2)
        XCTAssertEqual(engine.spoken[0].text, engine.spoken[1].text)
    }

    func testFinishKeepsSessionForRestart() {
        sessions.start(text: danish)
        engine.handler?(.finished)
        XCTAssertEqual(sessions.state, .finished)
        XCTAssertEqual(sessions.progress, 1)
        XCTAssertTrue(sessions.hasSession)
        sessions.restart()
        XCTAssertEqual(sessions.state, .speaking)
    }

    func testChunksAreSpokenInOrder() {
        let text = String(repeating: danish + " ", count: 20)
        sessions.start(text: text)
        var guardCount = 0
        while sessions.state == .speaking, guardCount < 100 {
            engine.handler?(.finished)
            guardCount += 1
        }
        XCTAssertEqual(sessions.state, .finished)
        // Tekstforberedelsen fjerner mellemrum i kanten af hver bid, så ordene sammenlignes.
        let spokenWords = engine.spoken.flatMap { $0.text.split(separator: " ") }
        XCTAssertEqual(spokenWords, text.split(separator: " "))
    }

    func testNewSessionReplacesOldWithoutOverlap() {
        sessions.start(text: danish)
        let oldHandler = engine.handler
        let stopsBefore = engine.stopCount
        sessions.start(text: english)
        XCTAssertGreaterThan(engine.stopCount, stopsBefore, "den gamle oplæsning skal stoppes, før den nye starter")
        XCTAssertEqual(engine.spoken.count, 2)

        // Forsinkede events fra den gamle session må ikke påvirke den nye.
        oldHandler?(.finished)
        XCTAssertEqual(sessions.state, .speaking)
        XCTAssertEqual(sessions.language, .english)
        XCTAssertEqual(engine.spoken.count, 2)
    }

    func testRateChangeContinuesFromCurrentWord() {
        sessions.start(text: danish)
        let offset = (danish as NSString).range(of: "almindelig").location
        engine.handler?(.progress(utf16Offset: offset))
        sessions.setRate(1.5)
        XCTAssertEqual(settings.rate, 1.5)
        XCTAssertEqual(engine.spoken.last?.rate, 1.5)
        XCTAssertTrue(engine.spoken.last?.text.hasPrefix("almindelig") == true)

        // Positionen skal regnes fra den oprindelige tekst, også efter en hastighedsændring.
        let secondOffset = (engine.spoken.last!.text as NSString).range(of: "vejret").location
        engine.handler?(.progress(utf16Offset: secondOffset))
        sessions.setRate(1.6)
        XCTAssertTrue(engine.spoken.last?.text.hasPrefix("vejret") == true)
    }

    func testLiveRateChangeContinuesWithoutRestarting() {
        engine.supportsLiveRate = true
        sessions.start(text: danish)
        sessions.setRate(1.5)
        XCTAssertEqual(engine.liveRates, [1.5])
        XCTAssertEqual(engine.spoken.count, 1, "en motor, der kan skifte undervejs, må ikke starte forfra")
        XCTAssertEqual(sessions.state, .speaking)

        sessions.pause()
        sessions.setRate(0.8)
        XCTAssertEqual(engine.liveRates, [1.5, 0.8])
        sessions.resume()
        XCTAssertEqual(engine.spoken.count, 1, "heller ikke efter pause")
        XCTAssertFalse(engine.isPaused)
    }

    func testRateChangeWhenStoppedIsJustRemembered() {
        engine.supportsLiveRate = true
        sessions.start(text: danish)
        sessions.stop()
        sessions.setRate(1.3)
        XCTAssertEqual(settings.rate, 1.3)
        XCTAssertTrue(engine.liveRates.isEmpty)
        sessions.restart()
        XCTAssertEqual(engine.spoken.last?.rate, 1.3)
    }

    func testRateChangeWhilePausedStaysPausedUntilResume() {
        sessions.start(text: danish)
        sessions.pause()
        sessions.setRate(0.8)
        XCTAssertEqual(sessions.state, .paused)
        XCTAssertEqual(engine.spoken.count, 1)
        sessions.resume()
        XCTAssertEqual(sessions.state, .speaking)
        XCTAssertEqual(engine.spoken.last?.rate, 0.8)
    }

    func testRateIsClamped() {
        sessions.start(text: danish)
        sessions.setRate(9)
        XCTAssertEqual(settings.rate, 2.0)
        sessions.setRate(0)
        XCTAssertEqual(settings.rate, 0.5)
    }

    func testCloseReleasesSession() {
        sessions.start(text: danish)
        sessions.close()
        XCTAssertEqual(sessions.state, .idle)
        XCTAssertFalse(sessions.hasSession)
        XCTAssertNil(sessions.language)
        sessions.togglePlayPause()
        XCTAssertEqual(sessions.state, .idle)
    }

    func testVeryLongTextIsRefusedWithAFriendlyNotice() {
        let tooLong = String(repeating: "Dette er en sætning. ", count: ReadingSessionManager.maxTextLength / 20 + 1)
        XCTAssertGreaterThan(tooLong.count, ReadingSessionManager.maxTextLength)
        XCTAssertEqual(sessions.start(text: tooLong), .tooLong)
        XCTAssertEqual(sessions.state, .idle)
        XCTAssertFalse(sessions.hasSession)
        XCTAssertTrue(engine.spoken.isEmpty)

        let atLimit = String(tooLong.prefix(ReadingSessionManager.maxTextLength))
        XCTAssertNil(sessions.start(text: atLimit), "tekst på præcis grænsen læses op")
        XCTAssertEqual(sessions.state, .speaking)
    }

    func testMissingVoiceGivesNotice() {
        let empty = VoiceCatalog(engines: [], settings: settings)
        let manager = ReadingSessionManager(catalog: empty, settings: settings, diagnostics: diagnostics)
        XCTAssertEqual(manager.start(text: danish), .noVoice(.danish))
        XCTAssertEqual(manager.state, .idle)
    }

    func testDanishTextIsPreparedBeforeSpeaking() {
        sessions.start(text: "Mødet om budgettet og de nye planer for skolen er flyttet til torsdag kl. 14.30.")
        XCTAssertEqual(sessions.language, .danish)
        XCTAssertTrue(engine.spoken.last?.text.contains("klokken fjorten tredive") == true)
    }

    func testEngineSpecificPronunciationIsAppliedToDanishOnly() {
        engine.overrides = ["chrome": "krovm"]
        sessions.start(text: "Jeg åbner Chrome hver morgen, når jeg møder på arbejde og skal læse mine mails.")
        XCTAssertEqual(sessions.language, .danish)
        XCTAssertTrue(engine.spoken.last?.text.contains("krovm") == true)

        sessions.start(text: "I open Chrome every morning when I arrive at work and need to read my mail.")
        XCTAssertEqual(sessions.language, .english)
        XCTAssertTrue(engine.spoken.last?.text.contains("Chrome") == true)
    }

    func testPdfLineBreaksAreJoinedBeforeSpeaking() {
        sessions.start(text: "Ordblindhed handler ikke om intel-\nligens, men om hvordan hjernen\nafkoder skrevne ord.")
        let spoken = engine.spoken.map(\.text).joined()
        XCTAssertTrue(spoken.contains("intelligens"))
        XCTAssertTrue(spoken.contains("hjernen afkoder"))
        XCTAssertFalse(spoken.contains("\n"))
    }

    func testEnglishTextIsNotChanged() {
        let text = "The meeting about the budget has been moved to Thursday at 14.30, said the teacher."
        sessions.start(text: text)
        XCTAssertEqual(sessions.language, .english)
        XCTAssertEqual(engine.spoken.last?.text, text)
    }

    // MARK: Indstillinger og log

    func testSettingsPersist() {
        settings.rate = 1.4
        settings.forcedLanguage = .english
        settings.preferredVoiceIDs["da"] = "da-1"
        settings.shortcut = Shortcut(keyCode: 15, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyLabel: "R")
        settings.playerOrigin = CGPoint(x: 120, y: 340)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.rate, 1.4)
        XCTAssertEqual(reloaded.forcedLanguage, .english)
        XCTAssertEqual(reloaded.preferredVoiceIDs["da"], "da-1")
        XCTAssertEqual(reloaded.shortcut.displayString, "⇧⌘R")
        XCTAssertEqual(reloaded.playerOrigin, CGPoint(x: 120, y: 340))
    }

    func testDefaultsAreDanishAndAutomatic() {
        XCTAssertEqual(settings.preferredLanguage, .danish)
        XCTAssertNil(settings.forcedLanguage)
        XCTAssertEqual(settings.rate, 1.0)
        XCTAssertEqual(settings.shortcut.displayString, "⌃⌥S")
    }

    func testLogNeverContainsSpokenText() throws {
        sessions.start(text: danish, sourceAppName: "Safari", sourceBundleID: "com.apple.Safari", triggeredAt: Date())
        engine.handler?(.started)
        engine.handler?(.failed)
        diagnostics.flush()

        let log = try String(contentsOf: diagnostics.logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("speechStarted"))
        XCTAssertTrue(log.contains("speechFailed"))
        XCTAssertTrue(log.contains("com.apple.Safari"))
        XCTAssertTrue(log.contains("\"voice\":\"da-2\""), "loggen skal vise, hvilken stemme der læste")
        XCTAssertTrue(log.contains("\"language\":\"da\""))
        for word in ["almindelig", "sætning", "vejret"] {
            XCTAssertFalse(log.contains(word))
        }
    }
}
