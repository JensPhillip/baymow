"""Tekstforberedelse, runde 2 (AP-22): (kategori, skrevet tekst, tekst som den skal siges).

Holdes adskilt fra sentences.py, så de 36 sætninger i stemmetesten forbliver sammenlignelige med
tidligere målinger. Begge filer skrives ind i Swift-testen af sync_swift_cases.py.

Valg, hvor dansk har flere rigtige former (notér nye valg her):
- Telefonnumre læses i par ("otteogtyve fjorten"); grupper med foranstillet nul ciffer for ciffer ("nul fem").
- Lange tal uden tusindtalspunktum (9 cifre eller flere, CPR-numre) læses ciffer for ciffer.
- Årstal 1100–1999 uden tusindtalspunktum læses som årstal ("atten hundrede og fireogtres"), også
  uden et ord som "i" eller "fra" foran. Det giver "femten hundrede tilskuere" for 1500, som er almindeligt dansk.
- Romertal efter et regentnavn læses som "den Fjerde"; efter kapitel, del, bind o.l. som grundtal.
- Webadresser og mail: "punktum", "skråstreg", "snabel-a". Dele uden vokaler staves ("dk" → "d k").
- Valuta siges efter beløbet: "€40", "kr. 249,-" og "500 DKK" → "fyrre euro", "… kroner".
- "d. 3/5" er en dato ("den tredje i femte"); andre små brøker læses som brøker.
"""
SENTENCES = [
    # Telefonnumre
    ("telefon", "Ring på tlf. 28 14 56 90.", "ring på telefon otteogtyve fjorten seksoghalvtreds halvfems"),
    ("telefon", "Mit nummer er 28145690.", "mit nummer er otteogtyve fjorten seksoghalvtreds halvfems"),
    ("telefon", "Ring på +45 70 10 20 30.", "ring på plus femogfyrre halvfjerds ti tyve tredive"),
    ("telefon", "Skriv til 40 05 12 00.", "skriv til fyrre nul fem tolv nul nul"),
    # Lange numre
    ("lange numre", "Hans CPR-nummer er 010190-1234.", "hans cpr nummer er nul en nul en ni nul en to tre fire"),
    ("lange numre", "Ordrenummeret er 4021875536.", "ordrenummeret er fire nul to en otte syv fem fem tre seks"),
    # Procent med komma
    ("procent", "Renten steg til 0,5 %.", "renten steg til nul komma fem procent"),
    ("procent", "Ledigheden er 12,75 pct.", "ledigheden er tolv komma femoghalvfjerds procent"),
    ("procent", "Kun 2,5 procent svarede.", "kun to komma fem procent svarede"),
    # Intervaller
    ("interval", "Der kommer 10-15 gæster.", "der kommer ti til femten gæster"),
    ("interval", "Butikken har åbent kl. 9-16.", "butikken har åbent klokken ni til seksten"),
    ("interval", "Mødet varer kl. 10.30-12.00.", "mødet varer klokken ti tredive til tolv"),
    ("interval", "Projektet løb i perioden 2020-2024.", "projektet løb i perioden to tusind og tyve til to tusind og fireogtyve"),
    ("interval", "Det tager 2–3 uger.", "det tager to til tre uger"),
    ("interval", "Prisen er 100-150 kr.", "prisen er hundrede til hundrede og halvtreds kroner"),
    # Ordenstal uden måned
    ("ordenstal", "Hun kom på 3. pladsen.", "hun kom på tredje pladsen"),
    ("ordenstal", "Han går i 1. klasse.", "han går i første klasse"),
    ("ordenstal", "Vi bor på 2. sal.", "vi bor på anden sal"),
    ("ordenstal", "Det skete i det 19. århundrede.", "det skete i det nittende århundrede"),
    ("ordenstal", "Det er hans 25. fødselsdag.", "det er hans femogtyvende fødselsdag"),
    # Romertal
    ("romertal", "Christian IV byggede Rundetårn.", "christian den fjerde byggede rundetårn"),
    ("romertal", "Dronning Margrethe II holdt nytårstale.", "dronning margrethe den anden holdt nytårstale"),
    ("romertal", "Frederik IX døde i 1972.", "frederik den niende døde i nitten hundrede og tooghalvfjerds"),
    ("romertal", "Læs kapitel III til i morgen.", "læs kapitel tre til i morgen"),
    ("romertal", "Det står i bind II.", "det står i bind to"),
    # Webadresser og mail
    ("web", "Læs mere på www.dr.dk.", "læs mere på w w w punktum d r punktum d k"),
    ("web", "Gå ind på borger.dk/sundhed.", "gå ind på borger punktum d k skråstreg sundhed"),
    ("web", "Se https://www.sundhed.dk for mere.", "se w w w punktum sundhed punktum d k for mere"),
    ("web", "Skriv til info@baymow.dk.", "skriv til info snabel a baymow punktum d k"),
    ("web", "Kontakt hanne.jensen@firma.com i dag.", "kontakt hanne punktum jensen snabel a firma punktum com i dag"),
    # Klokkeslæt
    ("klokken", "Vi ses kl. 9.", "vi ses klokken ni"),
    ("klokken", "Toget kører kl. 16 i dag.", "toget kører klokken seksten i dag"),
    ("klokken", "Mødet er kl. 9.00 den 3. maj.", "mødet er klokken ni den tredje maj"),
    # Valuta
    ("valuta", "Billetten koster 25 EUR.", "billetten koster femogtyve euro"),
    ("valuta", "Den kostede €40.", "den kostede fyrre euro"),
    ("valuta", "Abonnementet koster $10 om måneden.", "abonnementet koster ti dollar om måneden"),
    ("valuta", "Det beløber sig til 500 DKK.", "det beløber sig til fem hundrede kroner"),
    ("valuta", "Prisen er kr. 249,-", "prisen er to hundrede og niogfyrre kroner"),
    ("valuta", "Han betalte 100 USD.", "han betalte hundrede dollar"),
    # Nummer, paragraf, stykke
    ("paragraf", "Bus nr. 5 kører til stationen.", "bus nummer fem kører til stationen"),
    ("paragraf", "Se § 3, stk. 2.", "se paragraf tre stykke to"),
    ("paragraf", "Reglerne står i §§ 4-6.", "reglerne står i paragrafferne fire til seks"),
    ("paragraf", "Køb 5 stk. æbler.", "køb fem stykker æbler"),
    # Brøker
    ("brøk", "Tilsæt 1/2 liter mælk.", "tilsæt en halv liter mælk"),
    ("brøk", "Hæld 3/4 af vandet ud.", "hæld tre fjerdedele af vandet ud"),
    ("brøk", "Det tog 1½ time.", "det tog halvanden time"),
    ("brøk", "Kun 1/3 af eleverne kom.", "kun en tredjedel af eleverne kom"),
    ("brøk", "Fristen er d. 3/5.", "fristen er den tredje i femte"),
    # Årstal uden kontekstord
    ("årstal", "1864 var et skelsår for Danmark.", "atten hundrede og fireogtres var et skelsår for danmark"),
    ("årstal", "Vinteren 1947 var meget kold.", "vinteren nitten hundrede og syvogfyrre var meget kold"),
    ("årstal", "Der kom 1500 tilskuere.", "der kom femten hundrede tilskuere"),
    # Negative tal
    ("negativ", "Det var -5 grader i nat.", "det var minus fem grader i nat"),
]
