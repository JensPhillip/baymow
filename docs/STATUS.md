# Status

Opdateres af den, der sidst har arbejdet på projektet. Kort og faktuelt.
Sidst opdateret: 2026-11-17 af udfører (Claude Opus 5.5).

## Lige nu

- **Færdigt:** AP-00 (permanent mappe, git, omdøbning til Baymow), AP-01 (Apple som standard igen),
  AP-10 (fælles lydafspiller og `SynthesisBackend`), AP-02 (reproducerbar stemmetest),
  AP-22 (tekstforberedelse, runde 2: 52 nye tilfælde, alle bestået),
  AP-23 (kernen er nu sit eget mål, `BaymowCore`; compileren afviser afhængigheder ud af kernen).
- **AP-12 afsluttet:** brugeren har hørt lyttepakken og bekræftet, at Piper er til at forstå på almindelig
  dansk tekst. Problemet var teksten (engelske ord), ikke appen. Det flytter AP-24 frem.
- **AP-24 delvist:** udtalelister pr. motor er bygget og testet, men gav kun en lille forbedring for Piper
  (14 → 18 af 30) og ingen for Apple. Målet om en halvering blev ikke nået.
- **Hovedstemmen er valgt (AP-11, AP-19):** Apple Sara (Enhanced). Baymow vælger hende nu af sig selv;
  Magnus (Enhanced) bestod ikke stemmeporten og vælges aldrig automatisk. Fase 1 er slut; AP-15 og AP-16 parkeret.
- **Brugerens beslutninger 2026-11-17:** cloud-stemmer udskudt (AP-13/14), open source med mulighed for indtjening
  (licens afventer bekræftelse), Speechify-idéer lagt i planens idékatalog (fase 6).
- **AP-30 delvist:** brugeren har bekræftet, at genvejen virker i Chrome.
- **AP-40 færdig:** stemmebiblioteket med Prøv/Vælg/Hent/Fjern, robust download og vejledning til Sara
  (forbedret). Brugeren har set det og bekræftet, at det ser rigtigt ud, og at knappen til Systemindstillinger
  lander rigtigt.
- **AP-21 færdig:** lange tekster bruger ikke længere hukommelse uden grænse (højst 2 sætninger lyd forud;
  Pipers motor lukkes ned efter 60 s uden brug); tekster over 200.000 tegn afvises med en venlig besked.
- **AP-41 bygget:** velkomstvinduet "Kom i gang med Baymow" med tre trin; vises ved første start og fra
  menulinjen. Brugeren har bekræftet, at trin 3 virker. Afventer en testperson, der ikke har set Baymow før.
- **AP-20 bygget:** hastighedsskift uden at starte forfra (også med Piper) og en Rediger-menu. Under testrunden
  fandt brugeren et nedbrud ved genvejen (kopiering fra baggrundstråd); rettet og bekræftet af brugeren.
  Afventer testrunden på 10 punkter (står i AP-20-afleveringen).
- **Afventer bruger:** AP-20 (testrunde), AP-41 (testperson), AP-03 (tal 1–5 i lytteskemaet mangler stadig for begge stemmer).
- **I gang:** intet.
- **AP-50 færdig:** GPL-3.0-licens, `docs/LICENSER.md` og "Om Baymow".
- **AP-30 færdig.**
- **AP-31 næsten færdig:** Word og Preview virker (loggen). PDF-linjeskift og orddeling samles nu før oplæsning;
  beskederne ved manglende markering er tydeligere. Afventer brugerens test med en PDF.
- **AP-51 færdig:** 8,9 timers kørsel uden nedbrud, hukommelsen stabil (+0,8 MB), ingen netværk, ingen tekst
  i log eller filer.
- **Næste ledige pakker:** AP-51 (stabilitet og privatlivskontrol – kan laves uden brugeren), AP-31 (Word og
  Preview – kræver brugeren) (lange tekster og programskift), AP-20 (afspilleren – kræver en testrunde med brugeren),
  AP-31 (Word og Preview – kræver brugeren).
  De rører ikke de samme filer og kan løses hver for sig.

## Venter på brugeren

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Prøv genvejen ⌃⌥S én gang efter omdøbningen | Den er ikke brugt siden; tilladelsen er bekræftet (2026-11-17) | – |
| Hør lyttepakkerne, og udfyld `docs/LYTTESKEMA.md` | Kun brugeren kan afgøre, om en stemme er til at forstå | AP-03, AP-12, AP-19 |
| Gennemfør testrunden for afspilleren (10 punkter i AP-20-afleveringen) | Knapper og lyd kan kun prøves af brugeren | AP-20 |
| Find en testperson til førstegangsopsætningen (udskudt af brugeren 2026-11-18) | Kun et nyt menneske kan vise, om den er til at forstå | AP-41 |
| Markér et afsnit over flere linjer i en PDF i Preview, og prøv en indscannet side | Kræver brugerens ører | AP-31 |
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
