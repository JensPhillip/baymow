import XCTest
@testable import BaymowKit

/// Samme sætninger som i stemmetesten: skrevet tekst → sagt tekst.
/// Listen genereres fra tools/stemmetest/sentences.py. Ret dér, og kør sync_swift_cases.py.
final class DanishTextNormalizerTests: XCTestCase {
    private static let cases: [(written: String, spoken: String)] = [
        // GENERERET-START (tools/stemmetest/sync_swift_cases.py)
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
        ("Ring på tlf. 28 14 56 90.", "ring på telefon otteogtyve fjorten seksoghalvtreds halvfems"),
        ("Mit nummer er 28145690.", "mit nummer er otteogtyve fjorten seksoghalvtreds halvfems"),
        ("Ring på +45 70 10 20 30.", "ring på plus femogfyrre halvfjerds ti tyve tredive"),
        ("Skriv til 40 05 12 00.", "skriv til fyrre nul fem tolv nul nul"),
        ("Hans CPR-nummer er 010190-1234.", "hans cpr nummer er nul en nul en ni nul en to tre fire"),
        ("Ordrenummeret er 4021875536.", "ordrenummeret er fire nul to en otte syv fem fem tre seks"),
        ("Renten steg til 0,5 %.", "renten steg til nul komma fem procent"),
        ("Ledigheden er 12,75 pct.", "ledigheden er tolv komma femoghalvfjerds procent"),
        ("Kun 2,5 procent svarede.", "kun to komma fem procent svarede"),
        ("Der kommer 10-15 gæster.", "der kommer ti til femten gæster"),
        ("Butikken har åbent kl. 9-16.", "butikken har åbent klokken ni til seksten"),
        ("Mødet varer kl. 10.30-12.00.", "mødet varer klokken ti tredive til tolv"),
        ("Projektet løb i perioden 2020-2024.", "projektet løb i perioden to tusind og tyve til to tusind og fireogtyve"),
        ("Det tager 2–3 uger.", "det tager to til tre uger"),
        ("Prisen er 100-150 kr.", "prisen er hundrede til hundrede og halvtreds kroner"),
        ("Hun kom på 3. pladsen.", "hun kom på tredje pladsen"),
        ("Han går i 1. klasse.", "han går i første klasse"),
        ("Vi bor på 2. sal.", "vi bor på anden sal"),
        ("Det skete i det 19. århundrede.", "det skete i det nittende århundrede"),
        ("Det er hans 25. fødselsdag.", "det er hans femogtyvende fødselsdag"),
        ("Christian IV byggede Rundetårn.", "christian den fjerde byggede rundetårn"),
        ("Dronning Margrethe II holdt nytårstale.", "dronning margrethe den anden holdt nytårstale"),
        ("Frederik IX døde i 1972.", "frederik den niende døde i nitten hundrede og tooghalvfjerds"),
        ("Læs kapitel III til i morgen.", "læs kapitel tre til i morgen"),
        ("Det står i bind II.", "det står i bind to"),
        ("Læs mere på www.dr.dk.", "læs mere på w w w punktum d r punktum d k"),
        ("Gå ind på borger.dk/sundhed.", "gå ind på borger punktum d k skråstreg sundhed"),
        ("Se https://www.sundhed.dk for mere.", "se w w w punktum sundhed punktum d k for mere"),
        ("Skriv til info@baymow.dk.", "skriv til info snabel a baymow punktum d k"),
        ("Kontakt hanne.jensen@firma.com i dag.", "kontakt hanne punktum jensen snabel a firma punktum com i dag"),
        ("Vi ses kl. 9.", "vi ses klokken ni"),
        ("Toget kører kl. 16 i dag.", "toget kører klokken seksten i dag"),
        ("Mødet er kl. 9.00 den 3. maj.", "mødet er klokken ni den tredje maj"),
        ("Billetten koster 25 EUR.", "billetten koster femogtyve euro"),
        ("Den kostede €40.", "den kostede fyrre euro"),
        ("Abonnementet koster $10 om måneden.", "abonnementet koster ti dollar om måneden"),
        ("Det beløber sig til 500 DKK.", "det beløber sig til fem hundrede kroner"),
        ("Prisen er kr. 249,-", "prisen er to hundrede og niogfyrre kroner"),
        ("Han betalte 100 USD.", "han betalte hundrede dollar"),
        ("Bus nr. 5 kører til stationen.", "bus nummer fem kører til stationen"),
        ("Se § 3, stk. 2.", "se paragraf tre stykke to"),
        ("Reglerne står i §§ 4-6.", "reglerne står i paragrafferne fire til seks"),
        ("Køb 5 stk. æbler.", "køb fem stykker æbler"),
        ("Tilsæt 1/2 liter mælk.", "tilsæt en halv liter mælk"),
        ("Hæld 3/4 af vandet ud.", "hæld tre fjerdedele af vandet ud"),
        ("Det tog 1½ time.", "det tog halvanden time"),
        ("Kun 1/3 af eleverne kom.", "kun en tredjedel af eleverne kom"),
        ("Fristen er d. 3/5.", "fristen er den tredje i femte"),
        ("1864 var et skelsår for Danmark.", "atten hundrede og fireogtres var et skelsår for danmark"),
        ("Vinteren 1947 var meget kold.", "vinteren nitten hundrede og syvogfyrre var meget kold"),
        ("Der kom 1500 tilskuere.", "der kom femten hundrede tilskuere"),
        ("Det var -5 grader i nat.", "det var minus fem grader i nat"),
        // GENERERET-SLUT
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

    /// Tilfælde fundet ved afprøvning af almindelige sætninger (AP-22), som ikke hører til i stemmetesten.
    func testEverydayEdgeCases() {
        let cases: [(String, String)] = [
            ("Mødet holdes 2024-11-17 i Aarhus.", "mødet holdes den syttende november to tusind og fireogtyve i aarhus"),
            ("Bogen udkom i 1999-2000.", "bogen udkom i nitten hundrede og nioghalvfems til to tusind"),
            ("Kampen endte 3-1 til Brøndby.", "kampen endte tre en til brøndby"),
            ("Det koster 12,50 €.", "det koster tolv euro og halvtreds cent"),
            ("Billetten koster 50 kr. 3 gange om ugen.", "billetten koster halvtreds kroner tre gange om ugen"),
            ("Temperaturen faldt fra 5 til -3 grader.", "temperaturen faldt fra fem til minus tre grader"),
            ("Vi var 3. Hun kom senere.", "vi var tre hun kom senere"),
            ("Erik og Hans gik en tur. I går regnede det.", "erik og hans gik en tur i går regnede det"),
            ("Mail mig på jens@test.dk, tak.", "mail mig på jens snabel a test punktum d k tak"),
            ("Frederik den Niende og Christian X.", "frederik den niende og christian den tiende"),
        ]
        for (written, spoken) in cases {
            XCTAssertEqual(words(DanishTextNormalizer.normalize(written)), spoken, written)
        }
    }

    func testRomanNumerals() {
        XCTAssertEqual(DanishTextNormalizer.romanValue("IV"), 4)
        XCTAssertEqual(DanishTextNormalizer.romanValue("XIV"), 14)
        XCTAssertNil(DanishTextNormalizer.romanValue("IIII"))
        XCTAssertNil(DanishTextNormalizer.romanValue("VX"))
        // Et engelsk "I" efter et ikke-regentnavn må ikke blive et tal.
        XCTAssertEqual(DanishTextNormalizer.normalize("Han sagde: I am fine."), "Han sagde: I am fine.")
    }

    func testLeavesPlainTextAlone() {
        let text = "Dette er en helt almindelig sætning uden tal."
        XCTAssertEqual(DanishTextNormalizer.normalize(text), text)
        XCTAssertEqual(DanishTextNormalizer.normalize("  "), "")
    }
}
