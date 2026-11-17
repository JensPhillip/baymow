import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-19: Sara (Enhanced) er valgt som Baymows danske stemme. Magnus (Enhanced) bestod ikke stemmeporten
/// og må derfor ikke blive valgt automatisk, når begge er installeret.
@MainActor
final class AppleVoiceSelectionTests: XCTestCase {
    func testMagnusIsNotApprovedButOtherVoicesAre() {
        XCTAssertFalse(AppleSpeechEngine.isApprovedDefault("com.apple.voice.enhanced.da-DK.Magnus"))
        XCTAssertTrue(AppleSpeechEngine.isApprovedDefault("com.apple.voice.enhanced.da-DK.Sara"))
        XCTAssertTrue(AppleSpeechEngine.isApprovedDefault("com.apple.voice.compact.da-DK.Sara"))
    }

    func testSaraEnhancedIsChosenOverMagnusAndCompactSara() {
        let voices = [
            Voice(id: "com.apple.voice.enhanced.da-DK.Magnus", name: "Magnus", language: .danish, locale: "da-DK",
                  quality: .enhanced, engineID: "apple", isApprovedDefault: AppleSpeechEngine.isApprovedDefault("com.apple.voice.enhanced.da-DK.Magnus")),
            Voice(id: "com.apple.voice.enhanced.da-DK.Sara", name: "Sara", language: .danish, locale: "da-DK",
                  quality: .enhanced, engineID: "apple", isApprovedDefault: AppleSpeechEngine.isApprovedDefault("com.apple.voice.enhanced.da-DK.Sara")),
            Voice(id: "com.apple.voice.compact.da-DK.Sara", name: "Sara", language: .danish, locale: "da-DK",
                  quality: .standard, engineID: "apple"),
        ]
        let suite = "baymow.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = VoiceCatalog(engines: [FixedVoices(voices: voices)], settings: SettingsStore(defaults: defaults))
        XCTAssertEqual(catalog.voice(for: .danish)?.id, "com.apple.voice.enhanced.da-DK.Sara")
    }
}

@MainActor
private final class FixedVoices: SpeechEngine {
    let engineID = "apple"
    let voices: [Voice]
    init(voices: [Voice]) { self.voices = voices }
    func installedVoices() -> [Voice] { voices }
    func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {}
    func pause() {}
    func resume() {}
    func stop() {}
}
