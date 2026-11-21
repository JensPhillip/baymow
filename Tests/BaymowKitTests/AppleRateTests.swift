import AVFoundation
import XCTest
@testable import BaymowKit
import BaymowCore

/// I3: hastighedsfaktoren omregnes til Apples skala, så 1× er normalt, 3× (det højeste) stadig ligger inden for
/// Apples grænse, og hurtigere altid er hurtigere. Selve tempoet er målt med `Baymow --rate-sweep`.
@MainActor
final class AppleRateTests: XCTestCase {
    func testNormalIsApplesDefault() {
        XCTAssertEqual(AppleSpeechEngine.systemRate(for: 1.0), AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.0001)
    }

    func testHighestRateStaysBelowApplesMaximum() {
        let top = AppleSpeechEngine.systemRate(for: SettingsStore.rateRange.upperBound)
        XCTAssertLessThan(top, AVSpeechUtteranceMaximumSpeechRate)
        XCTAssertEqual(top, 0.84, accuracy: 0.001)
    }

    func testFasterIsAlwaysFaster() {
        let factors = stride(from: SettingsStore.rateRange.lowerBound, through: SettingsStore.rateRange.upperBound, by: 0.1)
        let rates = factors.map { AppleSpeechEngine.systemRate(for: $0) }
        for (slower, faster) in zip(rates, rates.dropFirst()) { XCTAssertLessThan(slower, faster) }
    }
}
