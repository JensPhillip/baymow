import XCTest
@testable import BaymowKit

/// Samme 36 sætninger som i stemmetesten (tools/stemmetest/sentences.py): skrevet tekst → sagt tekst.
final class DanishTextNormalizerTests: XCTestCase {
    private static let cases: [(written: String, spoken: String)] = [
        ("Ordblindhed handler ikke om intelligens, men om hvordan hjernen afkoder skrevne ord.", "ordblindhed handler ikke om intelligens men om hvordan hjernen afkoder skrevne ord"),
        ("Mange oplever, at en tekst bliver lettere at forstå, når den bliver læst højt i et roligt tempo.", "mange oplever at en tekst bliver lettere at forstå når den bliver læst højt i et roligt tempo"),
        ("Hun cyklede hjem gennem regnen og glemte helt, at hun havde lovet at købe mælk.", "hun cyklede hjem gennem regnen og glemte helt at hun havde lovet at købe mælk"),
        ("Vi skal huske at sende ansøgningen, inden fristen udløber på fredag.", "vi skal huske at sende ansøgningen inden fristen udløber på fredag"),
        ("Er du sikker på, at det er den rigtige vej til stationen?", "er du sikker på at det er den rigtige vej til stationen"),
        ("Bogen handler om en ung kvinde, der flytter fra Aarhus til en lille ø.", "bogen handler om en ung kvinde der flytter fra aarhus til en lille ø"),
        ("Kommunen gav støtte til 1.250 elever.", "kommunen gav støtte til tusind to hundrede og halvtreds elever"),
        ("Der bor 45.000 mennesker i byen.", "der bor femogfyrre tusind mennesker i byen"),
        ("Projektet koster 2.500.000 kroner.", "projektet koster to millioner fem hundrede tusind kroner"),
        ("Hun har 7 æbler og 21 pærer.", "hun har syv æbler og enogtyve pærer"),
        ("Bussen kører 150 gange om ugen.", "bussen kører hundrede og halvtreds gange om ugen"),
        ("Temperaturen steg med 3,5 grader.", "temperaturen steg med tre komma fem grader"),
        ("Renten er nu 4,25 %.", "renten er nu fire komma femogtyve procent"),
        ("Omkring 68 % af eleverne bestod prøven.", "omkring otteogtres procent af eleverne bestod prøven"),
        ("Ordningen fortsætter i 2026.", "ordningen fortsætter i to tusind og seksogtyve"),
        ("Han blev født i 1999.", "han blev født i nitten hundrede og nioghalvfems"),
        ("Mødet er flyttet til torsdag kl. 14.30.", "mødet er flyttet til torsdag klokken fjorten tredive"),
        ("Butikken åbner kl. 9.00 den 3. maj.", "butikken åbner klokken ni den tredje maj"),
        ("Fristen er den 21. juni 2026.", "fristen er den enogtyvende juni to tusind og seksogtyve"),
        ("Toget afgår 07:45 fra spor 4.", "toget afgår syv femogfyrre fra spor fire"),
        ("Billetten koster 249,95 kr.", "billetten koster to hundrede og niogfyrre kroner og femoghalvfems"),
        ("Huslejen er 8.500 kr. om måneden.", "huslejen er otte tusind fem hundrede kroner om måneden"),
        ("Hun løb 21 km på under to timer.", "hun løb enogtyve kilometer på under to timer"),
        ("Pakken vejer 12 kg og er 80 cm lang.", "pakken vejer tolv kilo og er firs centimeter lang"),
        ("Vi mødes ca. en gang om måneden, bl.a. for at planlægge.", "vi mødes cirka en gang om måneden blandt andet for at planlægge"),
        ("Medbring f.eks. pas, kørekort osv.", "medbring for eksempel pas kørekort og så videre"),
        ("Kampen blev aflyst pga. vejret, dvs. den spilles senere.", "kampen blev aflyst på grund af vejret det vil sige den spilles senere"),
        ("Ring evt. på tlf. nr. 12 efter kl. 16.", "ring eventuelt på telefon nummer tolv efter klokken seksten"),
        ("Arbejdsmarkedsuddannelserne skal understøtte kompetenceudviklingen.", "arbejdsmarkedsuddannelserne skal understøtte kompetenceudviklingen"),
        ("Sundhedsstyrelsen anbefaler regelmæssig fysisk aktivitet.", "sundhedsstyrelsen anbefaler regelmæssig fysisk aktivitet"),
        ("Bæredygtighed og klimaforandringer fylder meget i debatten.", "bæredygtighed og klimaforandringer fylder meget i debatten"),
        ("Fysioterapeuten undersøgte patientens skulder grundigt.", "fysioterapeuten undersøgte patientens skulder grundigt"),
        ("Rødgrød med fløde er en klassisk dansk dessert.", "rødgrød med fløde er en klassisk dansk dessert"),
        ("Virksomheden opdaterede sin software og sit website i weekenden.", "virksomheden opdaterede sin software og sit website i weekenden"),
        ("Psykologen talte om selvværd, angst og stress hos unge.", "psykologen talte om selvværd angst og stress hos unge"),
        ("Folketinget vedtog lovforslaget efter tredjebehandlingen.", "folketinget vedtog lovforslaget efter tredjebehandlingen"),
    ]

    /// Små bogstaver uden tegnsætning, så kun ordene sammenlignes.
    private func words(_ text: String) -> String {
        let cleaned = text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    func testTestSentences() {
        for (written, spoken) in Self.cases {
            XCTAssertEqual(words(DanishTextNormalizer.normalize(written)), spoken, written)
        }
    }

    func testNumbers() {
        XCTAssertEqual(DanishTextNormalizer.cardinal(0), "nul")
        XCTAssertEqual(DanishTextNormalizer.cardinal(100), "hundrede")
        XCTAssertEqual(DanishTextNormalizer.cardinal(101), "hundrede og en")
        XCTAssertEqual(DanishTextNormalizer.cardinal(1_000_000), "en million")
        XCTAssertEqual(DanishTextNormalizer.cardinal(21_001), "enogtyve tusind og en")
        XCTAssertEqual(DanishTextNormalizer.ordinal(30), "tredivte")
        XCTAssertEqual(DanishTextNormalizer.year(1864), "atten hundrede og fireogtres")
        XCTAssertEqual(DanishTextNormalizer.year(2000), "to tusind")
    }

    func testKeepsPunctuationAndCapitalisation() {
        XCTAssertEqual(DanishTextNormalizer.normalize("Ca. 3 personer kom, bl.a. Peter."), "Cirka tre personer kom, blandt andet Peter.")
        XCTAssertEqual(DanishTextNormalizer.normalize("Hvad koster det? 20 kr."), "Hvad koster det? tyve kroner")
    }

    func testLeavesPlainTextAlone() {
        let text = "Dette er en helt almindelig sætning uden tal."
        XCTAssertEqual(DanishTextNormalizer.normalize(text), text)
        XCTAssertEqual(DanishTextNormalizer.normalize("  "), "")
    }
}
