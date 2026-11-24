import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-75: tekst fra skærmen – linjerne sat sammen, æ/ø/å-rettelsen og indstillingerne (ingen skærm, intet billede).
@MainActor
final class ScreenTextTests: XCTestCase {
    /// En linje i Visions koordinater (0–1, origo nederst til venstre).
    func line(_ text: String, x: CGFloat = 0.05, y: CGFloat, height: CGFloat = 0.05) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: x, y: y, width: 0.8, height: height))
    }

    func testLinesAreReadTopDownAndJoinedIntoParagraphs() {
        let lines = [
            line("Anden linje i første afsnit.", y: 0.80),
            line("Første linje i første", y: 0.86),
            line("Andet afsnit.", y: 0.60), // stort mellemrum: nyt afsnit
        ]
        XCTAssertEqual(ScreenTextRecognizer.layout(lines),
                       "Første linje i første Anden linje i første afsnit.\n\nAndet afsnit.")
    }

    func testWordSplitWithHyphenIsJoined() {
        XCTAssertEqual(ScreenTextRecognizer.layout([line("Vi bor i lands-", y: 0.8), line("byen ved Århus.", y: 0.74)]),
                       "Vi bor i landsbyen ved Århus.")
        // Et navn med stort bogstav efter bindestregen bliver ikke slået sammen.
        XCTAssertEqual(ScreenTextRecognizer.layout([line("Mødet med Nord-", y: 0.8), line("Jylland i dag.", y: 0.74)]),
                       "Mødet med Nord- Jylland i dag.")
    }

    func testSameRowIsReadLeftToRight() {
        let lines = [RecognizedLine(text: "Gem", box: CGRect(x: 0.6, y: 0.5, width: 0.1, height: 0.05)),
                     RecognizedLine(text: "Annuller", box: CGRect(x: 0.2, y: 0.5, width: 0.15, height: 0.05))]
        XCTAssertEqual(ScreenTextRecognizer.layout(lines), "Annuller  Gem")
    }

    struct Checker: WordChecker {
        var guesses: [String: [String]]
        func isMisspelled(_ word: String, language: Language) -> Bool { guesses[word] != nil }
        func guesses(for word: String, language: Language) -> [String] { guesses[word] ?? [] }
    }

    func testDanishLettersAreFixedOnlyWhenTheFixIsClear() {
        let checker = Checker(guesses: ["hejt": ["højt", "hest"], "Arhus": ["Århus"], "nedgred": ["rødgrød"],
                                        "bage": ["bæge", "båge"]])
        XCTAssertEqual(DanishLetterFix.apply("tekst hejt for Arhus", checker: checker), "tekst højt for Århus")
        // For langt fra (ikke kun æ/ø/å) eller to mulige bud: ordet står.
        XCTAssertEqual(DanishLetterFix.apply("nedgred og bage", checker: checker), "nedgred og bage")
        // Ord, stavekontrollen kender, og tal røres ikke.
        XCTAssertEqual(DanishLetterFix.apply("Modet kl. 14.30", checker: checker), "Modet kl. 14.30")
    }

    func testScreenTextIsOffByDefaultWithItsOwnShortcut() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "baymow-screentext-test"))
        defaults.removePersistentDomain(forName: "baymow-screentext-test")
        let settings = ScreenTextSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.shortcut, ScreenTextSettings.standardShortcut)
        settings.isEnabled = true
        XCTAssertTrue(ScreenTextSettings(defaults: defaults).isEnabled)
        let all = [Shortcut.standard, ScreenTextSettings.standardShortcut, SpellingSettings.standardShortcut,
                   MailReplySettings.standardShortcut, MailReplySettings.standardSparringShortcut]
        XCTAssertEqual(Set(all.map(\.displayString)).count, 5)
        defaults.removePersistentDomain(forName: "baymow-screentext-test")
    }
}
