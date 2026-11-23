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
                              "fra", "ferie", "går", "ja", "selvfølgelig", "komme", "morgen", "vi", "ses", "kl",
                              "bruge", "ernagien", "energien", "det", "nu", "skal", "vinde", "finde", "en", "løsning"]

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

    // MARK: Internet-hjælpen (AP-64)

    /// Opfører sig som Claude/ChatGPT: svarer med faste rettelser eller fejler som uden internet.
    struct FakeCloud: SpellingCorrector {
        var answers: [String: String] = [:]
        var failure: CloudSpellingError?
        var source: SpellingSource { .cloud(.claude) }
        func correct(_ sentence: String, language: Language) async throws -> String {
            if let failure { throw failure }
            return answers[sentence] ?? sentence
        }
        func choose(in sentence: String, candidates: [String], language: Language) async throws -> String {
            candidates.last!
        }
    }

    func testCloudMayFixARealWordThatIsSpelledWrong() async {
        // Macens stavekontrol godkender "ernagien" (målt). Macens model får ikke lov; internet-modellen gør.
        let sentence = "Vi skal bruge ernagien nu."
        let fix = ["Vi skal bruge ernagien nu.": "Vi skal bruge energien nu."]
        let local = await result(sentence, answers: fix)
        XCTAssertEqual(local.text, sentence)
        let cloud = await SpellingAssistant(corrector: FakeCloud(answers: fix), checker: FakeChecker(words: words)).check(sentence)
        XCTAssertEqual(cloud.text, "Vi skal bruge energien nu.")
        XCTAssertEqual(cloud.source, .cloud(.claude))
    }

    func testCloudStillCannotAnswerTheText() async {
        let cloud = SpellingAssistant(corrector: FakeCloud(answers: ["Kan du komme i morgen?": "Ja, selvfølgelig."]),
                                      checker: FakeChecker(words: words))
        let r = await cloud.check("Kan du komme i morgen?")
        XCTAssertEqual(r.text, "Kan du komme i morgen?")
    }

    func testCloudCannotSwapForADifferentWord() async {
        let cloud = SpellingAssistant(corrector: FakeCloud(answers: ["Han kom til bage fra ferie.": "Han kom til selvfølgelig fra ferie."]),
                                      checker: FakeChecker(words: words))
        let r = await cloud.check("Han kom til bage fra ferie.")
        XCTAssertEqual(r.text, "Han kom til bage fra ferie.")
    }

    func testWithoutInternetTheMacHelpsAndSaysSo() async {
        let local = FakeCorrector(answers: ["Jeg har ikke tit.": "Jeg har ikke tid."])
        let assistant = SpellingAssistant(corrector: FakeCloud(failure: .offline), fallback: local,
                                          checker: FakeChecker(words: words))
        let r = await assistant.check("Jeg har ikke tit.")
        XCTAssertEqual(r.text, "Jeg har ikke tid.")
        XCTAssertEqual(r.source, .mac)
        XCTAssertEqual(r.cloudProblem, .offline)
    }

    func testMacHelpNeverFallsBackToTheInternet() async {
        // Omvendt: fejler Macens egen model, sendes teksten ikke videre.
        struct FailingLocal: SpellingCorrector {
            func correct(_ sentence: String, language: Language) async throws -> String { throw CloudSpellingError.failed }
            func choose(in sentence: String, candidates: [String], language: Language) async throws -> String { "" }
        }
        let assistant = SpellingAssistant(corrector: FailingLocal(), fallback: FakeCloud(answers: ["Jeg har ikke tit.": "Jeg har ikke tid."]),
                                          checker: FakeChecker(words: words))
        let r = await assistant.check("Jeg har ikke tit.")
        XCTAssertEqual(r.text, "Jeg har ikke tit.")
        XCTAssertNil(r.cloudProblem)
    }

    func testAnswersAreReadFromBothCompanies() {
        let claude = #"{"content":[{"type":"text","text":"Jeg har ikke tid."}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(CloudSpellingCorrector.text(from: Data(claude.utf8), provider: .claude), "Jeg har ikke tid.")
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#
        XCTAssertNil(CloudSpellingCorrector.text(from: Data(refusal.utf8), provider: .claude))
        let openai = #"{"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Jeg har ikke tid."}]}]}"#
        XCTAssertEqual(CloudSpellingCorrector.text(from: Data(openai.utf8), provider: .openai), "Jeg har ikke tid.")
        // Nogle modeller gentager opgaven først (målt med GPT-6.1).
        XCTAssertEqual(CloudSpellingCorrector.cleanAnswer("Ret stavningen i denne tekst:\nJeg har ikke tid."), "Jeg har ikke tid.")
    }

    func testKeyGoesInAHeaderAndTextOnlyInTheBody() {
        for provider in CloudProvider.allCases {
            let request = CloudSpellingCorrector.request(provider: provider, key: "TESTKEY", instructions: "i", prompt: "Hemmelig tekst",
                                                         maxTokens: 10)
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertFalse(request.url!.absoluteString.contains("Hemmelig"))
            XCTAssertFalse(request.url!.absoluteString.contains("TESTKEY"))
            XCTAssertTrue((request.allHTTPHeaderFields ?? [:]).values.contains { $0.contains("TESTKEY") })
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains(provider.model))
        }
    }

    // MARK: Forbrug (AP-65)

    func testTokensAreReadFromBothCompanies() {
        let claude = #"{"content":[],"usage":{"input_tokens":120,"output_tokens":15}}"#
        XCTAssertEqual(CloudSpellingCorrector.usage(from: Data(claude.utf8), provider: .claude)?.input, 120)
        let openai = #"{"output":[],"usage":{"input_tokens":160,"output_tokens":40,"total_tokens":200}}"#
        XCTAssertEqual(CloudSpellingCorrector.usage(from: Data(openai.utf8), provider: .openai)?.output, 40)
        XCTAssertNil(CloudSpellingCorrector.usage(from: Data("{}".utf8), provider: .openai))
    }

    func testUsageIsCountedPerMonthAndKeptOnlyAsNumbers() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "baymow-usage-test"))
        defaults.removePersistentDomain(forName: "baymow-usage-test")
        var date = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")!
        let log = CloudUsageLog(defaults: defaults, now: { date })
        log.addCheck(.openai)
        log.addTokens(.openai, input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(log.entry(.openai).checks, 1)
        // GPT-6 Luna: $0,10 + $0,50 = $0,60 for en million af hver.
        XCTAssertEqual(log.kroner(.openai), 0.60 * CloudPricing.kronerPerDollar, accuracy: 0.0001)
        XCTAssertEqual(log.entry(.claude), CloudUsageEntry())

        date = ISO8601DateFormatter().date(from: "2026-12-02T12:00:00Z")!
        log.addCheck(.claude)
        XCTAssertEqual(log.currentMonth, "2026-12")
        XCTAssertEqual(log.earlierMonths, ["2026-11"])
        XCTAssertEqual(CloudUsageLog.monthName("2026-11"), "november 2026")

        // Gemt og læst igen.
        let again = CloudUsageLog(defaults: defaults, now: { date })
        XCTAssertEqual(again.entry(.openai, month: "2026-11").inputTokens, 1_000_000)
        again.reset()
        XCTAssertTrue(CloudUsageLog(defaults: defaults).months.isEmpty)
        defaults.removePersistentDomain(forName: "baymow-usage-test")
    }
}
