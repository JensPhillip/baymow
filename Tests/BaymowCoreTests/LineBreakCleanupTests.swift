import XCTest
@testable import BaymowCore

/// AP-31: linjeskift og orddeling fra PDF'er må ikke give pauser midt i sætninger.
final class LineBreakCleanupTests: XCTestCase {
    func testWordHyphenatedAcrossLinesIsJoined() {
        XCTAssertEqual(LineBreakCleanup.clean("Det handler om ordblind-\nhed og læsning."), "Det handler om ordblindhed og læsning.")
    }

    func testSentenceBrokenAcrossLinesIsJoined() {
        let pdf = """
        Mange oplever, at en tekst bliver lettere at forstå, når den
        bliver læst højt i et roligt tempo. Derfor bruger flere skoler
        oplæsning i undervisningen.
        """
        XCTAssertEqual(LineBreakCleanup.clean(pdf),
                       "Mange oplever, at en tekst bliver lettere at forstå, når den bliver læst højt i et roligt tempo. Derfor bruger flere skoler oplæsning i undervisningen.")
    }

    func testLongLineBeforeAProperNounIsJoined() {
        XCTAssertEqual(LineBreakCleanup.clean("Efter mødet på rådhuset i går gik borgmesteren hen til\nPeter og takkede."),
                       "Efter mødet på rådhuset i går gik borgmesteren hen til Peter og takkede.")
    }

    func testParagraphsHeadingsAndListsAreKept() {
        let text = """
        Indledning
        Ordblindhed er udbredt. Mange får hjælp.

        Sådan gør du:
        - Markér teksten
        - Tryk på genvejen
        1. Første punkt
        """
        XCTAssertEqual(LineBreakCleanup.clean(text), text, "overskrift, afsnit og lister må ikke smelte sammen")
    }

    func testRealHyphensAreKept() {
        // Bindestreg før et ord med stort begyndelsesbogstav er en rigtig bindestreg, ikke orddeling.
        XCTAssertEqual(LineBreakCleanup.clean("Han skrev sit nummer i feltet, der hedder CPR-\nNummer, og trykkede."),
                       "Han skrev sit nummer i feltet, der hedder CPR- Nummer, og trykkede.")
        XCTAssertEqual(LineBreakCleanup.clean("Nord- og Sydjylland"), "Nord- og Sydjylland")
    }

    func testSoftHyphensAndWindowsLineBreaksAreRemoved() {
        XCTAssertEqual(LineBreakCleanup.clean("ordblind\u{00AD}\nhed"), "ordblindhed")
        XCTAssertEqual(LineBreakCleanup.clean("tekst\u{00AD}forberedelse"), "tekstforberedelse")
        XCTAssertEqual(LineBreakCleanup.clean("en lang linje uden punktum der fortsætter\r\npå næste linje."),
                       "en lang linje uden punktum der fortsætter på næste linje.")
    }

    func testParagraphsGluedTogetherGetASpace() {
        // Sådan kom teksten fra Claude-appen 2026-11-21.
        XCTAssertEqual(LineBreakCleanup.clean("Baymow husker størrelsen.Sig til, hvis noget skal ændres."),
                       "Baymow husker størrelsen. Sig til, hvis noget skal ændres.")
        XCTAssertEqual(LineBreakCleanup.clean("Er det klart?Ja!Godt."), "Er det klart? Ja! Godt.")
        XCTAssertEqual(LineBreakCleanup.clean("Han sagde \"Hej.\"Så gik han."), "Han sagde \"Hej.\" Så gik han.")
        XCTAssertEqual(LineBreakCleanup.clean("Sådan gør du:Markér teksten."), "Sådan gør du: Markér teksten.")
    }

    func testOrdinaryPunctuationIsLeftAlone() {
        for text in ["Det koster 249,95 kr.", "Klokken er 14.30 nu.", "Se www.dr.dk for mere.", "iPhone og PowerPoint."] {
            XCTAssertEqual(LineBreakCleanup.clean(text), text)
        }
    }

    func testPlainTextIsUnchanged() {
        let text = "Helt almindelig tekst. Uden linjeskift."
        XCTAssertEqual(LineBreakCleanup.clean(text), text)
    }
}
