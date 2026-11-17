import XCTest
@testable import BaymowKit

final class PronunciationOverridesTests: XCTestCase {
    private let list = ["chrome": "krovm", "cloud": "klawd", "login": "log in", "smartphone": "smartfon", "like": "lajk"]

    func testReplacesWholeWordsRegardlessOfCase() {
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "Åbn Chrome og gem i cloud."), "Åbn krovm og gem i klawd.")
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "CHROME"), "krovm")
    }

    func testKeepsEndings() {
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "Chromes faner"), "krovms faner")
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "clouden er nede"), "klawden er nede")
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "Chrome's menu"), "krovms menu")
    }

    func testWorksInsideHyphenatedCompounds() {
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "et cloud-valg"), "et klawd-valg")
    }

    func testDoesNotTouchOtherWords() {
        // "likelihood", "cloudy" og "chromosom" indeholder ordene, men er andre ord.
        let text = "likelihood, cloudy, chromosom og unlike"
        XCTAssertEqual(PronunciationOverrides.apply(list, to: text), text)
        XCTAssertEqual(PronunciationOverrides.apply(list, to: "Helt almindelig dansk tekst."), "Helt almindelig dansk tekst.")
    }

    func testEmptyListChangesNothing() {
        XCTAssertEqual(PronunciationOverrides.apply([:], to: "Chrome"), "Chrome")
    }

    func testShippedListsUseLowercaseKeys() {
        XCTAssertFalse(PiperBackend.danishOverrides.isEmpty)
        for list in [PiperBackend.danishOverrides, AppleSpeechEngine.danishOverrides] {
            for (word, spoken) in list {
                XCTAssertEqual(word, word.lowercased(), "nøgler skal være små bogstaver")
                XCTAssertFalse(spoken.isEmpty)
            }
        }
    }
}
