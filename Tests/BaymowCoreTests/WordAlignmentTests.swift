import XCTest
@testable import BaymowCore

/// I1: det sagte ord kobles til det rigtige sted i den viste tekst.
final class WordAlignmentTests: XCTestCase {
    private func shown(_ original: String, _ spoken: String, _ spokenWord: String, occurrence: Int = 0) -> String? {
        let alignment = WordAlignment(original: original, spoken: spoken)
        var search = NSRange(location: 0, length: (spoken as NSString).length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = (spoken as NSString).range(of: spokenWord, options: [], range: search)
            search = NSRange(location: NSMaxRange(found), length: (spoken as NSString).length - NSMaxRange(found))
        }
        return alignment.originalRange(forSpokenOffset: found.location).map { (original as NSString).substring(with: $0) }
    }

    func testIdenticalTextMapsWordForWord() {
        let text = "Hunden løb over marken."
        XCTAssertEqual(shown(text, text, "løb"), "løb")
        XCTAssertEqual(shown(text, text, "marken"), "marken")
    }

    func testExpandedTimeAndDateMapToTheWrittenForm() {
        let original = "Mødet er kl. 14.30 den 3. maj."
        let spoken = "Mødet er klokken fjorten tredive den tredje maj."
        XCTAssertEqual(shown(original, spoken, "klokken"), "kl. 14.30")
        XCTAssertEqual(shown(original, spoken, "fjorten"), "kl. 14.30")
        XCTAssertEqual(shown(original, spoken, "tredive"), "kl. 14.30")
        XCTAssertEqual(shown(original, spoken, "den"), "den")
        XCTAssertEqual(shown(original, spoken, "tredje"), "3")
        XCTAssertEqual(shown(original, spoken, "maj"), "maj")
    }

    func testNumbersAndAbbreviations() {
        let original = "Billetten koster 249,95 kr. bl.a. i weekenden."
        let spoken = "Billetten koster to hundrede og niogfyrre kroner og femoghalvfems blandt andet i weekenden."
        XCTAssertEqual(shown(original, spoken, "niogfyrre"), "249,95 kr. bl.a")
        XCTAssertEqual(shown(original, spoken, "weekenden"), "weekenden")
    }

    func testSpokenRangeForASentence() {
        let original = "Første sætning. Anden sætning har 3 ord."
        let spoken = "Første sætning. Anden sætning har tre ord."
        let alignment = WordAlignment(original: original, spoken: spoken)
        let second = (spoken as NSString).range(of: "Anden sætning har tre ord.")
        let range = alignment.originalRange(forSpokenRange: second)
        XCTAssertEqual(range.map { (original as NSString).substring(with: $0) }, "Anden sætning har 3 ord")
    }

    func testExtraSpokenWordUsesNeighbour() {
        // Udtalelister kan give ekstra ord ("chat G P T").
        let original = "Jeg spurgte ChatGPT om hjælp."
        let spoken = "Jeg spurgte chat G P T om hjælp."
        XCTAssertEqual(shown(original, spoken, "G"), "ChatGPT")
    }

    func testEmptyTexts() {
        XCTAssertNil(WordAlignment(original: "", spoken: "Hej").originalRange(forSpokenOffset: 0))
        XCTAssertNil(WordAlignment(original: "Hej", spoken: "").originalRange(forSpokenOffset: 0))
    }
}
