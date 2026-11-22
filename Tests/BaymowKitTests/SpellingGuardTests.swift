import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-63: vagten bag stavehjælpen, prøvet med en falsk stavekontrol og en falsk model (ingen rigtig sprogmodel).
@MainActor
final class SpellingGuardTests: XCTestCase {
    /// Kender en fast ordliste; alt andet er stavet forkert.
    struct FakeChecker: WordChecker {
        var words: Set<String>
        var guesses: [String: [String]] = [:]
        func isMisspelled(_ word: String, language: Language) -> Bool { !words.contains(word.lowercased()) }
        func guesses(for word: String, language: Language) -> [String] { guesses[word.lowercased()] ?? [] }
    }

    /// Svarer med faste rettelser og vælger altid det første ord, der står i `preferred`.
    struct FakeCorrector: SpellingCorrector {
        var answers: [String: String]
        var preferred: [String] = []
        func correct(_ sentence: String, language: Language) async throws -> String { answers[sentence] ?? sentence }
        func choose(in sentence: String, candidates: [String], language: Language) async throws -> String {
            candidates.first { preferred.contains($0) } ?? candidates.last!
        }
    }

    let words: Set<String> = ["jeg", "har", "ikke", "tid", "tit", "til", "at", "skrive", "i", "dag", "kan", "du", "huske",
                              "købe", "mel", "mælk", "mægl", "på", "vej", "hjem", "han", "kom", "tilbage", "bage", "bageri",
                              "fra", "ferie", "går", "ja", "selvfølgelig", "komme", "morgen", "vi", "ses", "kl"]

    func result(_ text: String, answers: [String: String], preferred: [String] = [],
                guesses: [String: [String]] = [:]) async -> SpellingResult {
        let assistant = SpellingAssistant(corrector: FakeCorrector(answers: answers, preferred: preferred),
                                          checker: FakeChecker(words: words, guesses: guesses))
        return await assistant.check(text)
    }

    func testSmallFixIsUsedAndShown() async {
        let r = await result("Jeg har ikke tit til at skrive i dag.",
                             answers: ["Jeg har ikke tit til at skrive i dag.": "Jeg har ikke tid til at skrive i dag."])
        XCTAssertEqual(r.text, "Jeg har ikke tid til at skrive i dag.")
        XCTAssertEqual(r.changes.map(\.original), ["tit"])
        XCTAssertEqual(r.changes.map(\.kind), [.corrected])
    }

    func testRealWordIsNotSwappedForADifferentWord() async {
        // "bage" → "bageri" ændrer meningen og er mere end ét bogstav: bruges ikke.
        let r = await result("Han kom til bage fra ferie.", answers: ["Han kom til bage fra ferie.": "Han kom til bageri fra ferie."])
        XCTAssertEqual(r.text, "Han kom til bage fra ferie.")
        XCTAssertTrue(r.changes.isEmpty)
    }

    func testWordWrittenInTwoPartsIsJoined() async {
        let r = await result("Han kom til bage fra ferie.", answers: ["Han kom til bage fra ferie.": "Han kom tilbage fra ferie."])
        XCTAssertEqual(r.text, "Han kom tilbage fra ferie.")
        XCTAssertEqual(r.changes.first?.original, "til bage")
    }

    func testCloserSpellingSuggestionIsChosenInContext() async {
        // Modellen siger "mel", men stavekontrollen har ord, der ligner "mælg" mere; modellen vælger ud fra sætningen.
        let r = await result("Kan du huske at købe mælg på vej hjem?",
                             answers: ["Kan du huske at købe mælg på vej hjem?": "Kan du huske at købe mel på vej hjem?"],
                             preferred: ["mælk"], guesses: ["mælg": ["mægl", "mælk"]])
        XCTAssertEqual(r.text, "Kan du huske at købe mælk på vej hjem?")
        XCTAssertEqual(r.changes.first?.kind, .corrected)
        XCTAssertEqual(r.changes.first?.suggestions, ["mægl"])
    }

    func testAnswerInsteadOfCorrectionIsIgnored() async {
        let r = await result("Kan du komme i morgen?", answers: ["Kan du komme i morgen?": "Ja, selvfølgelig."])
        XCTAssertEqual(r.text, "Kan du komme i morgen?")
    }

    func testAddedWordsAndContinuationsAreDropped() async {
        let r = await result("Vi ses kl. 10.", answers: ["Vi ses kl.": "Vi ses kl. 10."])
        XCTAssertEqual(r.text, "Vi ses kl. 10.")
    }

    func testUnknownWordWithoutTrustedFixIsMarkedNotChanged() async {
        // Modellen lader ordet stå: Baymow retter ikke selv, men viser forslag.
        let r = await result("Jeg har ikke tidd.", answers: [:], preferred: ["tid"], guesses: ["tidd": ["tid", "tit"]])
        XCTAssertEqual(r.text, "Jeg har ikke tidd.")
        XCTAssertEqual(r.changes.first?.kind, .uncertain)
        XCTAssertEqual(r.changes.first?.suggestions.first, "tid")
    }

    func testWithoutModelOnlyTheSpellCheckerMarksWords() async {
        let assistant = SpellingAssistant(corrector: nil, checker: FakeChecker(words: words, guesses: ["tidd": ["tid"]]))
        let r = await assistant.check("Jeg har ikke tidd.")
        XCTAssertEqual(r.text, "Jeg har ikke tidd.")
        XCTAssertFalse(r.usedModel)
        XCTAssertEqual(r.changes.map(\.suggestions), [["tid"]])
    }

    func testTextBetweenSentencesIsKept() async {
        let text = "Jeg har ikke tit.\n\n  Vi ses i dag. "
        let r = await result(text, answers: ["Jeg har ikke tit.": "Jeg har ikke tid."])
        XCTAssertEqual(r.text, "Jeg har ikke tid.\n\n  Vi ses i dag. ")
    }

    func testDistance() {
        XCTAssertEqual(SpellingGuard.distance("tenge", "tegne"), 1) // ombyttede bogstaver tæller som én fejl
        XCTAssertEqual(SpellingGuard.distance("mælg", "mel"), 2)
        XCTAssertEqual(SpellingGuard.distance("", "abc"), 3)
    }

    func testTokensAlwaysHaveOneMoreSeparatorThanWords() {
        for text in ["", "Hej", "Hej.", " Hej verden ", "...", "kl. 10.", "e-mail'en"] {
            let t = Tokens(text)
            XCTAssertEqual(t.separators.count, t.words.count + 1, text)
            XCTAssertEqual(zip(t.separators, t.words + [""]).map { $0 + $1 }.joined(), text)
        }
    }
}
