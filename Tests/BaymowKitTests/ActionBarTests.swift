import XCTest
import SwiftUI
@testable import BaymowKit
import BaymowCore

/// AP-77: knapbjælken – indstillinger, tasterne og velkomstens valg (ingen skærm).
@MainActor
final class ActionBarTests: XCTestCase {
    private func freshDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testButtonsAreOffByDefaultAndKeysWork() throws {
        let settings = ActionBarSettings(defaults: try freshDefaults("baymow-actionbar-1"))
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.style, .hover, "brugeren valgte C (logo ved musen) som standard")
        XCTAssertTrue(settings.keysEnabled)
        XCTAssertTrue(settings.keysActive)
        XCTAssertFalse(settings.hasChosen)
    }

    func testKeysCanOnlyBeTurnedOffWhenButtonsAreOn() throws {
        let settings = ActionBarSettings(defaults: try freshDefaults("baymow-actionbar-2"))
        settings.keysEnabled = false
        XCTAssertTrue(settings.keysActive, "uden knapper skal tasterne virke, ellers kan Baymow ikke bruges")
        settings.isEnabled = true
        XCTAssertFalse(settings.keysActive)
        settings.isEnabled = false
        XCTAssertTrue(settings.keysActive)
    }

    func testWelcomeChoiceKeepsTheKeysAndIsSaved() throws {
        let defaults = try freshDefaults("baymow-actionbar-3")
        let settings = ActionBarSettings(defaults: defaults)
        settings.keysEnabled = false
        settings.choose(buttons: true)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.keysEnabled, "tasterne virker også, når man vælger knapper")
        XCTAssertTrue(settings.hasChosen)
        settings.style = .edge
        settings.hiddenButtons = [.spelling]
        let again = ActionBarSettings(defaults: defaults)
        XCTAssertTrue(again.isEnabled)
        XCTAssertTrue(again.hasChosen)
        XCTAssertEqual(again.style, .edge)
        XCTAssertEqual(again.hiddenButtons, [.spelling])
        again.choose(buttons: false)
        XCTAssertFalse(again.isEnabled)
        XCTAssertTrue(again.keysActive)
    }

    func testOnlyEnabledFeaturesBecomeButtons() throws {
        let settings = ActionBarSettings(defaults: try freshDefaults("baymow-actionbar-4"))
        XCTAssertEqual(settings.visibleButtons(available: [.read]), [.read])
        XCTAssertEqual(settings.visibleButtons(available: [.mailReply, .read, .spelling]), [.read, .spelling, .mailReply])
        settings.hiddenButtons = [.spelling]
        XCTAssertEqual(settings.visibleButtons(available: [.read, .spelling]), [.read])
    }

    func testWelcomeAsksAboutButtonsBeforeTheTryStep() {
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: true, skippedVoice: false,
                                              hasChosenControls: false, hasRead: false), .controls)
        XCTAssertEqual(OnboardingStep.current(hasPermission: true, hasMainVoice: true, skippedVoice: false,
                                              hasChosenControls: true, hasRead: false), .tryIt)
        XCTAssertEqual(OnboardingStep.current(hasPermission: false, hasMainVoice: true, skippedVoice: false,
                                              hasChosenControls: false, hasRead: false), .permission)
        XCTAssertEqual(ControlPreference.allCases.count, 2, "kun to valg: med eller uden knapper")
    }

    func testEveryButtonExplainsItselfWithoutAbbreviations() {
        for button in ActionBarButton.allCases {
            XCTAssertFalse(button.help.isEmpty)
            for short in [" fx ", " bl.a. ", " evt. "] { XCTAssertFalse(button.help.contains(short), button.help) }
        }
    }

    /// Brugerens afprøvning 25. november: vinduet var 0 × 0 og derfor usynligt. Størrelsen skal kunne måles.
    func testTheBarWindowHasASize() {
        let model = ActionBarModel()
        model.buttons = [.read, .spelling]
        let hosting = NSHostingView(rootView: ActionBarHost(model: model, onHover: { _ in }, onLogoTap: {}, onDrag: { _ in },
                                                            onButton: { _ in }, onButtonHover: { _ in }, onListen: {}))
        hosting.sizingOptions = ActionBarController.sizingOptions
        let closed = hosting.fittingSize
        XCTAssertGreaterThan(closed.width, 40)
        XCTAssertGreaterThan(closed.height, 40)
        model.expanded = true
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, closed.width + 100, "åben er bredere end logoet alene")
        for style in ActionBarStyle.allCases {
            model.style = style
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 20, style.rawValue)
            XCTAssertGreaterThan(hosting.fittingSize.height, 20, style.rawValue)
        }
    }
}
