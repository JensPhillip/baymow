# Status

Opdateres af den, der sidst har arbejdet på projektet. Kort og faktuelt.
Sidst opdateret: 2026-11-21 af udfører (Claude Opus 5.5).

## Lige nu

- **I gang:** intet.
- **Færdige pakker:** AP-00, AP-01, AP-02, AP-10, AP-11, AP-12, AP-19 (hovedstemme: Apple Sara (Enhanced)),
  AP-21, AP-22, AP-23, AP-30, AP-31, AP-40, AP-50, AP-51, AP-60.
- **Venter på brugeren:** AP-20 (testrunde på 10 punkter),
  AP-41 (testperson – udskudt af brugeren 2026-11-18), AP-03 (tal 1–5 i lytteskemaet; ikke afgørende længere).
- **Delvist:** AP-24 – udtalelister pr. motor er bygget, men gav kun lidt (Piper 14 → 18 af 30, Apple uændret).
- **Parkeret eller udskudt:** AP-13/14 (cloud-stemmer, B6), AP-15/16 (Plapre, Røst – hovedstemmen er valgt).
- **Beslutninger:** B6 cloud udskudt · B7 Sara (Enhanced) · B8 GPL-3.0-or-later · B9 Baymow, app-id
  `dk.jpmag.baymow` (21. november; Tilgængelighed givet igen og genvejen bekræftet af brugeren).
- **Kodearkiv:** https://github.com/JensPhillip/baymow (offentligt). Push kun det, der er committet og grønt.
- **AP-52 forberedt:** DMG (`Scripts/make-dmg.sh`) og README. Udgivelse afventer brugerens app-id, Developer ID og kodearkiv.
- **AP-60 færdig (idé I1, ordfremhævning):** tekstvindue og/eller gult felt direkte i teksten, hver sin kontakt i
  "Visning", slået fra som standard. I teksten virker i Noter, TextEdit, Safari og Mail; ikke i Chrome, Word og Claude.
- **Næste ledige pakker:** AP-32 (Google Docs og testmatrix – kræver brugeren). Herefter er MVP'en klar, og
  idékataloget (fase 6) venter på brugerens valg.

## Venter på brugeren

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Hør lyttepakkerne, og udfyld `docs/LYTTESKEMA.md` | Kun brugeren kan afgøre, om en stemme er til at forstå | AP-03, AP-12, AP-19 |
| Gennemfør testrunden for afspilleren (10 punkter i AP-20-afleveringen) | Knapper og lyd kan kun prøves af brugeren | AP-20 |
| Find en testperson til førstegangsopsætningen (udskudt af brugeren 2026-11-18) | Kun et nyt menneske kan vise, om den er til at forstå | AP-41 |
| Meld dig ind i Apple Developer Program (Developer ID og notarisering) | Udgivelse til andre kræver det | AP-52 |
| Acceptér vilkår for `syvai/plapre-3` på Hugging Face | Originalmodellen kræver det | AP-15 |

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
- Word, Google Docs, Preview. (Chrome: genvejen virker ifølge brugeren; tekstfelter, PDF i Chrome og
  gendannelse af udklipsholderen er ikke afprøvet.)

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
