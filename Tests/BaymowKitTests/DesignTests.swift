import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-62: byggeklodserne bag det nye design.
@MainActor
final class DesignTests: XCTestCase {
    func testEveryLanguageHasAFlag() {
        XCTAssertEqual(Language.danish.flag, "🇩🇰")
        XCTAssertEqual(Language.english.flag, "🇬🇧")
        for language in Language.allCases { XCTAssertTrue(language.flagAndName.hasSuffix(language.displayName)) }
    }

    func testRateIsWrittenTheDanishWay() {
        XCTAssertEqual(rateLabel(1.0), "1×")
        XCTAssertEqual(rateLabel(1.5), "1,5×")
        XCTAssertEqual(rateLabel(2.9999999), "3×")
        XCTAssertEqual(rateLabel(0.7000001), "0,7×")
    }

    func testShortcutAsKeysAndWords() {
        XCTAssertEqual(Shortcut.standard.keys, ["⌃", "⌥", "S"])
        XCTAssertEqual(Shortcut.standard.spokenKeys, "Control, Option og S")
        let command = Shortcut(keyCode: 0, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyLabel: "A")
        XCTAssertEqual(command.keys, ["⇧", "⌘", "A"])
        XCTAssertEqual(command.spokenKeys, "Skift, Kommando og A")
    }

    /// Forklaringerne, "Hør"-knapperne læser op, skal være almindeligt dansk, som stemmen kan læse uden omskrivning.
    func testExplanationsArePlainDanish() {
        for page in MainPage.allCases {
            let text = page.explanation(shortcut: .standard)
            XCTAssertEqual(DanishTextNormalizer.normalize(text), text, page.rawValue)
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.subtitle.isEmpty)
        }
    }

    /// Korte overskrifter (designprincip 1): højst tre ord pr. side i sidebjælken.
    func testPageTitlesAreShort() {
        for page in MainPage.allCases { XCTAssertLessThanOrEqual(page.title.split(separator: " ").count, 3, page.title) }
    }
}
