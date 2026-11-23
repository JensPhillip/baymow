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

    func testPasteboardItemHasOnlyTheAppsOwnFormatAndPlainText() {
        let rtf = RichReplacement.pasteboardItem(formatted: .rtf(Data("{\\rtf1 Hej}".utf8)), plain: "Hej")
        XCTAssertNotNil(rtf.data(forType: .rtf))
        XCTAssertNil(rtf.data(forType: .html), "Word skal kun have sin egen RTF tilbage")
        XCTAssertEqual(rtf.string(forType: .string), "Hej")
        XCTAssertNotNil(rtf.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
        let plain = RichReplacement.pasteboardItem(formatted: nil, plain: "Hej")
        XCTAssertNil(plain.data(forType: .rtf))
    }

    // MARK: Word's egen RTF (AP-69)

    /// Som Word skriver det: Aptos, størrelse 12 (fs24), fed, æøå som \'xx, en skrifttabel og en generator.
    static let wordRTF = #"{\rtf1\adeflang1025\ansi\ansicpg1252\uc1\deff0{\fonttbl{\f0\froman Times New Roman;}{\f39\fswiss\fcharset0 Aptos;}}{\*\generator Microsoft Word 16.0;}\pard\plain \f39\fs24\lang1030 {\f39\fs24 Jeg har ikke }{\b\f39\fs24 tit}{\f39\fs24  til at k\'f8be m\'e6lg.}\par }"#

    func testWordsFontSizeAndBoldAreUntouched() throws {
        let segs = segments("Jeg har ikke tit til at købe mælg.", "Jeg har ikke tid til at købe mælk.")
        let out = try XCTUnwrap(RTFText.apply(segs, to: Data(Self.wordRTF.utf8)))
        let rtf = String(decoding: out, as: UTF8.self)
        // Kun bogstaverne er ændret: skrifttabel, Aptos og størrelse står som før.
        XCTAssertTrue(rtf.contains("{\\f39\\fswiss\\fcharset0 Aptos;}"))
        XCTAssertTrue(rtf.contains("{\\b\\f39\\fs24 tid}"))
        XCTAssertFalse(rtf.contains("Helvetica"))
        // Og RTF'en kan stadig læses, med den rigtige tekst.
        let read = RTFText.read(Array(out))
        XCTAssertEqual(String(utf16CodeUnits: read.text, count: read.text.count), "Jeg har ikke tid til at købe mælk.\n")
        XCTAssertNotNil(NSAttributedString(rtf: out, documentAttributes: nil))
    }

    func testCommaIsAddedWithTheFormattingOfTheWordBefore() throws {
        let rtf = #"{\rtf1\ansi{\fonttbl{\f0 Aptos;}}\f0\fs24 Jeg tror at han kommer\par}"#
        let out = try XCTUnwrap(RTFText.apply(segments("Jeg tror at han kommer", "Jeg tror, at han kommer."), to: Data(rtf.utf8)))
        let read = RTFText.read(Array(out))
        XCTAssertEqual(String(utf16CodeUnits: read.text, count: read.text.count), "Jeg tror, at han kommer.\n")
        XCTAssertTrue(String(decoding: out, as: UTF8.self).contains("\\f0\\fs24 Jeg tror, at"))
    }

    func testUnicodeAndBulletsInWordsRTF() throws {
        // Punktform: Word skriver punkttegnet i \listtext, som ikke er en del af teksten. \u med reserve-tegn.
        let rtf = #"{\rtf1\ansi\uc1{\fonttbl{\f0 Aptos;}}{\listtext\f3 \u-3913\'b7\tab}\ls1 Jeg har ikke tit\u8230\'85\par{\listtext\f3 \u-3913\'b7\tab}\ls1 Vi ses\par}"#
        let read = RTFText.read(Array(rtf.utf8))
        XCTAssertEqual(String(utf16CodeUnits: read.text, count: read.text.count), "Jeg har ikke tit…\nVi ses\n")
        let out = try XCTUnwrap(RTFText.apply(segments("Jeg har ikke tit…\nVi ses", "Jeg har ikke tid…\nVi ses"), to: Data(rtf.utf8)))
        let fixed = RTFText.read(Array(out))
        XCTAssertEqual(String(utf16CodeUnits: fixed.text, count: fixed.text.count), "Jeg har ikke tid…\nVi ses\n")
        XCTAssertTrue(String(decoding: out, as: UTF8.self).contains("{\\listtext\\f3 \\u-3913\\'b7\\tab}"))
    }

    func testNewSpecialCharactersAreEscaped() {
        XCTAssertEqual(RTFText.escape("æ{"), "{\\uc1\\u230?}\\{")
    }

    func testNotRTFOrMissingWordsGiveNil() {
        XCTAssertNil(RTFText.apply(segments("Jeg har ikke tit", "Jeg har ikke tid"), to: Data("<html>".utf8)))
        XCTAssertNil(RTFText.apply(segments("Jeg har ikke tit", "Jeg har ikke tid"), to: Data(#"{\rtf1 Noget andet}"#.utf8)))
    }
}
