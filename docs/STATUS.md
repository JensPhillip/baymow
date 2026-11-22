# Status

Opdateres af den, der sidst har arbejdet på projektet. Kort og faktuelt.
Sidst opdateret: 2026-11-22 af udfører (Claude Opus 5.5).

## Lige nu

- **I gang:** AP-63 stavehjælp (I12) – bygget og målt, afventer brugerens afprøvning.
- **Færdige pakker:** AP-00, AP-01, AP-02, AP-10, AP-11, AP-12, AP-19 (hovedstemme: Apple Sara (Enhanced)),
  AP-20, AP-21, AP-22, AP-23, AP-30, AP-31, AP-32, AP-40, AP-50, AP-51, AP-60, AP-61, AP-62.
- **Lukket/droppet af brugeren 22. november:** AP-03 (lytteskemaet), AP-15 (Plapre).
- **Venter på brugeren:** afprøvning af stavehjælpen (AP-63), AP-41 (testperson – udskudt af brugeren 2026-11-18).
- **Delvist:** AP-24 – udtalelister pr. motor er bygget, men gav kun lidt (Piper 14 → 18 af 30, Apple uændret).
- **Parkeret eller udskudt:** AP-13/14 (cloud-stemmer, B6), AP-16 (Røst – hovedstemmen er valgt).
- **Beslutninger:** B6 cloud udskudt · B7 Sara (Enhanced) · B8 GPL-3.0-or-later · B9 Baymow, app-id
  `dk.jpmag.baymow` (21. november; Tilgængelighed givet igen og genvejen bekræftet af brugeren).
- **Kodearkiv:** https://github.com/JensPhillip/baymow (offentligt). Push kun det, der er committet og grønt.
- **AP-52 forberedt:** DMG (`Scripts/make-dmg.sh`) og README. Udgivelse afventer brugerens app-id, Developer ID og kodearkiv.
- **AP-60 færdig (idé I1, ordfremhævning):** tekstvindue og/eller gult felt direkte i teksten, hver sin kontakt i
  "Visning", slået fra som standard. I teksten virker i Noter, TextEdit, Safari og Mail; ikke i Chrome, Word og Claude.
- **AP-61 (idé I3, højere hastighed):** grænsen er 3× (var 2×). Saras tempo følger tallet (målt: 2× = 2,05×,
  3× = 2,98×). Talegenkendelse: 1× 1,7 %, 1,5× 3,5 %, 2× 7,2 % tegnfejl; over 2× kan den ikke følge med, brugeren har lyttet og godkendt 2,5× og 3×.
- **AP-62 (nyt design):** designprincipper i planens afsnit 3. Hovedvinduet har sidebjælke med fem sider, ikoner,
  flag og "Hør"-knapper; velkomsten er tegnet om. Afspilleren er igen lille (én række), efter brugerens ønske.
  Nedbrud ved genvejen (ordkoblingen, fra AP-60) rettet 21. november. Godkendt af brugeren. Skærmbilleder: `Baymow --render-ui <mappe>`.
- **MVP'en er færdig og afprøvet af brugeren** (22. november: afspilleren, Google Docs i Safari/Chrome, Outlook,
  PDF og tekstfelter i Chrome, udklipsholderen, "Hør"-knapperne). Slack er ikke prøvet.
- **AP-63 (idé I12, stavehjælp):** ⌃⌥R på egen markeret tekst. Macens indbyggede sprogmodel + en vagt, der kun lader
  små rettelser igennem; usikre ord markeres "tjek selv". Slået fra som standard (siden "Stavning"). Stavetest
  (`tools/stavetest/`): kontrolsæt 0 forkerte rettelser, 13 af 14 fejl rettet eller markeret, 0,5 s pr. sætning.
  Kernen: `GlobalShortcutManager` kan nu have flere genveje (`--hotkey-selftest`).

## Venter på brugeren

Brugerens samlede tjekliste i almindeligt sprog: `docs/TJEKLISTE.md` (opdatér den, når noget bliver afklaret).

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Prøv stavehjælpen (⌃⌥R) i et par programmer, og godkend vinduet | Udseende, lyd og indsætning kan kun prøves af brugeren | AP-63 |
| Find en testperson til førstegangsopsætningen (udskudt af brugeren 2026-11-18) | Kun et nyt menneske kan vise, om den er til at forstå | AP-41 |
| Meld dig ind i Apple Developer Program (Developer ID og notarisering) | Udgivelse til andre kræver det | AP-52 |

## Senest kontrolleret (2026-11-17)

- `./Scripts/check.sh`: ALT GRØNT, 92 tests.
- `Baymow --memory-selftest apple|piper`: begge bestået (efter luk inden for 10 MB af udgangspunktet).
- `Baymow --player-selftest`: den rigtige afspiller bestod alle fem punkter, lydløst.
- `./Scripts/test-voice.sh`: Piper 28 af 36 (1,4 %), Apple Sara 23 af 36 (2,8 %) efter AP-22.
- Baymow.app er bygget, signeret, installeret i Programmer og startet.
- Automatisk dansk stemme er Apple Sara, selv om Piper er installeret (`--measure-latency`).
- En frisk kopi af arkivet bygger efter `fetch-vendor.sh`: se seneste commit-besked.

## Ikke kontrolleret

- Baymows vindue, menulinje og afspiller er ikke set på skærmen efter omdøbningen.
- Oplæsning via genvejen efter omdøbningen.
- Slack (brugeren: antages at virke).

## Kendte fælder

- Kernen ligger i `Sources/BaymowCore/` (ikke længere `Sources/BaymowKit/Core/`). Ældre afleveringer bruger de gamle stier.
- Selvtests, der skal køre som rigtig app, startes med `./Scripts/run-selftest.sh` (tidsgrænse, aldrig efter fejlet bygning).
- Kald til macOS' tastaturfunktioner (TIS) skal ske på hovedtråden – ellers lukker macOS 26 appen. En almindelig
  test fanger det ikke; `--copykey-selftest` gør.
- `check.sh` kræver siden 2026-11-21, at `swift test` afslutter uden fejl; før kunne en fejlende test give grønt.
- Brug altid scripts eller `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` – systemets `swift` er for gammel.
- espeak-ng fejler, hvis stien til dens data er over ca. 160 tegn.
- sherpa-onnx 2.x har fjernet espeak-ng; projektet bruger derfor 1.13.8.
- Bundle-id'et bestemmer Tilgængelighed-tilladelsen. Ændres det, skal brugeren give adgang igen.
- Flyttes projektmappen med appens egen flytning, følger `.git` og `Vendor/` ikke med. Hent `Vendor/` med `fetch-vendor.sh`.
- Stemmetestens miljø ligger i `tools/stemmetest/env/` (ikke i git); `setup.sh` opretter det.
- "Klokken ni den tredje maj" høres ofte som "klokken ni tredive" af talegenkendelsen. Det er ikke en tekstfejl.
- Piper giver ikke samme lyd to gange, så stemmetesten svinger ±1 sætning. Kør tre gange før en port.
