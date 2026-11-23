import XCTest
import AppKit
@testable import BaymowKit
import BaymowCore

/// AP-68: hvor meget Baymow retter (stavning / tegnsætning / klarere sætninger), og at formateringen bevares.
@MainActor
final class SpellingLevelTests: XCTestCase {
    struct Checker: WordChecker {
        func isMisspelled(_ word: String, language: Language) -> Bool { word.lowercased() == "tit" }
        func guesses(for word: String, language: Language) -> [String] { [] }
    }

    func review(_ sentence: String, _ proposal: String, level: SpellingLevel, trusted: Bool = true) -> String {
        SpellingGuard(checker: Checker(), trusted: trusted, level: level)
            .review(sentence, proposal: proposal, language: .danish).map(\.text).joined()
    }

    func testOnlySpellingKeepsTheUsersPunctuation() {
        XCTAssertEqual(review("jeg tror at han har tit", "Jeg tror, at han har tid.", level: .spelling),
                       "jeg tror at han har tid")
    }

    func testPunctuationLevelAddsCommasCapitalsAndQuestionMarks() {
        XCTAssertEqual(review("jeg tror at han kommer", "Jeg tror, at han kommer.", level: .punctuation),
                       "Jeg tror, at han kommer.")
        XCTAssertEqual(review("Kan du komme i morgen", "Kan du komme i morgen?", level: .punctuation),
                       "Kan du komme i morgen?")
        // Mac-modellen (ikke "trusted") må også sætte kommaer.
        XCTAssertEqual(review("Jeg tror at han kommer.", "Jeg tror, at han kommer.", level: .punctuation, trusted: false),
                       "Jeg tror, at han kommer.")
    }

    func testPunctuationLevelStillDropsAContinuation() {
        XCTAssertEqual(review("Vi ses kl.", "Vi ses kl. 10.", level: .punctuation), "Vi ses kl.")
    }

    func testOnlyPunctuationMayComeFromTheModelBetweenWords() {
        // Et linjeskift eller andre tegn end tegnsætning bruges ikke.
        XCTAssertEqual(review("Hej med dig", "Hej\nmed dig", level: .punctuation), "Hej med dig")
    }

    func testClarityReplacesWholePhrasesAndCanBeUndone() {
        let sentence = "Jeg tænkte på om det måske kunne være en mulighed at vi eventuelt kunne mødes."
        let proposal = "Jeg tænkte på, om vi kunne mødes."
        let segments = SpellingGuard(checker: Checker(), trusted: true, level: .clarity)
            .review(sentence, proposal: proposal, language: .danish)
        XCTAssertEqual(segments.map(\.text).joined(), proposal)
        // Uden internet-hjælpen (ikke "trusted") bliver sætningen ikke skrevet om: svaret ligner for lidt.
        XCTAssertEqual(review(sentence, proposal, level: .clarity, trusted: false), sentence)
        // Hvert ændret stykke kan vælges tilbage til brugerens egne ord.
        var undone = segments
        for i in undone.indices { undone[i].text = undone[i].original }
        XCTAssertEqual(undone.map(\.text).joined(), sentence)
    }

    func testClarityStillIgnoresAnAnswer() {
        XCTAssertEqual(review("Kan du komme i morgen?", "Ja, selvfølgelig kan jeg det.", level: .clarity),
                       "Kan du komme i morgen?")
    }

    // MARK: Formatering

    func segments(_ text: String, _ proposal: String) -> [SpellingSegment] {
        SpellingGuard(checker: Checker(), trusted: true, level: .punctuation).review(text, proposal: proposal, language: .danish)
    }

    func testBoldWordStaysBoldWhenCorrected() throws {
        let bold = NSFont.boldSystemFont(ofSize: 12)
        let rich = NSMutableAttributedString(string: "Jeg har ikke ")
        rich.append(NSAttributedString(string: "tit", attributes: [.font: bold]))
        rich.append(NSAttributedString(string: " i dag"))
        let fixed = try XCTUnwrap(RichReplacement.apply(segments("Jeg har ikke tit i dag", "Jeg har ikke tid i dag."), to: rich))
        XCTAssertEqual(fixed.string, "Jeg har ikke tid i dag.")
        let range = (fixed.string as NSString).range(of: "tid")
        XCTAssertEqual(fixed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont, bold)
    }

    func testBulletsAreKept() throws {
        // Punktform: den formaterede tekst har punkttegn, den rene tekst har kun linjeskift.
        let rich = NSAttributedString(string: "•\tJeg har ikke tit\n•\tVi ses i dag")
        let fixed = try XCTUnwrap(RichReplacement.apply(segments("Jeg har ikke tit\nVi ses i dag", "Jeg har ikke tid\nVi ses i dag"),
                                                        to: rich))
        XCTAssertEqual(fixed.string, "•\tJeg har ikke tid\n•\tVi ses i dag")
    }

    func testFallsBackToPlainTextWhenTheWordsCannotBeFound() {
        let rich = NSAttributedString(string: "Noget helt andet")
        XCTAssertNil(RichReplacement.apply(segments("Jeg har ikke tit", "Jeg har ikke tid"), to: rich))
    }

    func testPasteboardItemHasFormattedAndPlainText() {
        let item = RichReplacement.pasteboardItem(rich: NSAttributedString(string: "Hej"), plain: "Hej")
        XCTAssertNotNil(item.data(forType: .rtf))
        XCTAssertEqual(item.string(forType: .string), "Hej")
        XCTAssertNotNil(item.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
    }
}
