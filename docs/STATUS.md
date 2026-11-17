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
- **Afventer bruger:** AP-03 (tal 1–5 i lytteskemaet mangler stadig for begge stemmer).
- **I gang:** intet.
- **Næste ledige pakker:** AP-30 (Chrome – kræver brugeren ved tasterne), AP-11 (Apples større stemmer –
  kræver, at brugeren henter dem), AP-21 (lange tekster og programskift – kan laves uden brugeren).
  De rører ikke de samme filer og kan løses hver for sig.

## Venter på brugeren

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Prøv genvejen ⌃⌥S én gang efter omdøbningen | Den er ikke brugt siden; tilladelsen er bekræftet (2026-11-17) | – |
| Hør lyttepakkerne, og udfyld `docs/LYTTESKEMA.md` | Kun brugeren kan afgøre, om en stemme er til at forstå | AP-03, AP-12, AP-19 |
| Hent Apples større danske stemmer i Systemindstillinger | Billigste forsøg på en bedre stemme | AP-11 |
| Bekræft B6: cloud-stemmer som tydeligt tilvalg | Bryder ellers med privatlivsløftet | AP-13, AP-14 |
| Beslut B8: åben eller lukket kildekode | Piper/espeak-ng er GPL | AP-50 |
| Acceptér vilkår for `syvai/plapre-3` på Hugging Face | Originalmodellen kræver det | AP-15 |

## Senest kontrolleret (2026-11-17)

- `./Scripts/check.sh`: ALT GRØNT, 49 tests.
- `Baymow --player-selftest`: den rigtige afspiller bestod alle fem punkter, lydløst.
- `./Scripts/test-voice.sh`: Piper 28 af 36 (1,4 %), Apple Sara 23 af 36 (2,8 %) efter AP-22.
- Baymow.app er bygget, signeret, installeret i Programmer og startet.
- Automatisk dansk stemme er Apple Sara, selv om Piper er installeret (`--measure-latency`).
- En frisk kopi af arkivet bygger efter `fetch-vendor.sh`: se seneste commit-besked.

## Ikke kontrolleret

- Baymows vindue, menulinje og afspiller er ikke set på skærmen efter omdøbningen.
- Oplæsning via genvejen efter omdøbningen.
- Chrome, Word, Google Docs, Preview.

## Kendte fælder

- Kernen ligger i `Sources/BaymowCore/` (ikke længere `Sources/BaymowKit/Core/`). Ældre afleveringer bruger de gamle stier.
- Brug altid scripts eller `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` – systemets `swift` er for gammel.
- espeak-ng fejler, hvis stien til dens data er over ca. 160 tegn.
- sherpa-onnx 2.x har fjernet espeak-ng; projektet bruger derfor 1.13.8.
- Bundle-id'et bestemmer Tilgængelighed-tilladelsen. Ændres det, skal brugeren give adgang igen.
- Flyttes projektmappen med appens egen flytning, følger `.git` og `Vendor/` ikke med. Hent `Vendor/` med `fetch-vendor.sh`.
- Stemmetestens miljø ligger i `tools/stemmetest/env/` (ikke i git); `setup.sh` opretter det.
- "Klokken ni den tredje maj" høres ofte som "klokken ni tredive" af talegenkendelsen. Det er ikke en tekstfejl.
- Piper giver ikke samme lyd to gange, så stemmetesten svinger ±1 sætning. Kør tre gange før en port.
