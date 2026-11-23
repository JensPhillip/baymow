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
    @MainActor
    func testExplanationsArePlainDanish() {
        let defaults = UserDefaults(suiteName: "baymow-design-test")!
        defaults.removePersistentDomain(forName: "baymow-design-test")
        let spelling = SpellingSettings(defaults: defaults)
        for (enabled, cloud) in [(false, false), (true, false), (true, true)] {
            spelling.isEnabled = enabled
            spelling.cloudEnabled = cloud
            for page in MainPage.allCases {
                let text = page.explanation(shortcut: .standard, spelling: spelling)
                XCTAssertEqual(DanishTextNormalizer.normalize(text), text, page.rawValue)
                XCTAssertFalse(page.title.isEmpty)
                XCTAssertFalse(page.subtitle.isEmpty)
            }
        }
        defaults.removePersistentDomain(forName: "baymow-design-test")
    }

    /// Korte overskrifter (designprincip 1): højst tre ord pr. side i sidebjælken.
    func testPageTitlesAreShort() {
        for page in MainPage.allCases { XCTAssertLessThanOrEqual(page.title.split(separator: " ").count, 3, page.title) }
    }

    /// AP-73: Genveje, Stemmer og AI og nøgler ligger under "Indstillinger" nederst; resten øverst. Ingen side to steder.
    func testSettingsPagesAreGroupedAtTheBottom() {
        XCTAssertEqual(MainPage.settingsPages, [.shortcut, .voices, .ai])
        XCTAssertEqual(MainPage.mainPages, [.start, .reading, .display, .spelling, .mail])
        XCTAssertEqual(Set(MainPage.mainPages + MainPage.settingsPages), Set(MainPage.allCases))
    }

    @MainActor
    func testSettingsButtonReturnsToTheLastSettingsPage() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "baymow-sidebar-test")!)
        let model = MainWindowModel(settings: store, catalog: VoiceCatalog(engines: [], settings: store),
                                    downloader: ModelDownloader(), sampleEngines: [])
        XCTAssertEqual(model.lastSettingsPage, MainPage.shortcut)
        model.page = MainPage.ai
        model.page = MainPage.start
        XCTAssertEqual(model.lastSettingsPage, MainPage.ai)
    }
}
