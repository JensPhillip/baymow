import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-41: rækkefølgen i førstegangsopsætningen.
final class OnboardingTests: XCTestCase {
    func testStepsInOrder() {
        XCTAssertEqual(OnboardingStep.current(hasPermission: false, hasMainVoice: false, skippedVoice: false, hasRead: false), .permission)
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: false, skippedVoice: false, hasRead: false), .voice)
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: true, skippedVoice: false, hasRead: false), .tryIt)
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: true, skippedVoice: false, hasRead: true), .done)
    }

    func testAlreadyDoneStepsAreSkipped() {
        // En bruger, der allerede har givet adgang og har stemmen, starter ved "Prøv det".
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: true, skippedVoice: false, hasRead: false), .tryIt)
    }

    func testVoiceCanBeSkipped() {
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: false, skippedVoice: true, hasRead: false), .tryIt)
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: false, skippedVoice: true, hasRead: true), .done)
    }

    func testPermissionComesFirstEvenIfEverythingElseIsDone() {
        // Uden adgang kan genvejen ikke virke, så trin 1 skal klares først.
        XCTAssertEqual(OnboardingStep.current(hasPermission: false, hasMainVoice: true, skippedVoice: false, hasRead: true), .permission)
    }

    func testSampleTextIsPlainDanish() {
        XCTAssertEqual(DanishTextNormalizer.normalize(OnboardingModel.sampleText), OnboardingModel.sampleText,
                       "eksempelteksten må ikke indeholde tal eller forkortelser, der ændres")
    }
}
