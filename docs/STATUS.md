# Status

Opdateres af den, der sidst har arbejdet på projektet. Kort og faktuelt.
Sidst opdateret: 2026-11-16 af arkitekten.

## Lige nu

- **Færdigt:** AP-00 (permanent mappe, git, omdøbning til Baymow), AP-01 (Apple som standard igen).
- **I gang:** intet.
- **Næste ledige pakker:** AP-02 (reproducerbar stemmetest), AP-10 (fælles lydafspiller), AP-30 (Chrome).
  De rører ikke de samme filer og kan løses hver for sig.

## Venter på brugeren

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Giv Baymow adgang under Tilgængelighed | Appen har fået nyt id og ses som en ny app | Al brug af genvejen |
| Hent Apples større danske stemmer i Systemindstillinger | Billigste forsøg på en bedre stemme | AP-11 |
| Bekræft B6: cloud-stemmer som tydeligt tilvalg | Bryder ellers med privatlivsløftet | AP-13, AP-14 |
| Beslut B8: åben eller lukket kildekode | Piper/espeak-ng er GPL | AP-50 |
| Acceptér vilkår for `syvai/plapre-3` på Hugging Face | Originalmodellen kræver det | AP-15 |

## Senest kontrolleret (2026-11-16)

- `./Scripts/check.sh`: ALT GRØNT, 27 tests.
- Baymow.app er bygget, signeret, installeret i Programmer og startet.
- Automatisk dansk stemme er Apple Sara, selv om Piper er installeret (`--measure-latency`).
- En frisk kopi af arkivet bygger efter `fetch-vendor.sh`: se seneste commit-besked.

## Ikke kontrolleret

- Baymows vindue, menulinje og afspiller er ikke set på skærmen efter omdøbningen.
- Oplæsning via genvejen efter omdøbningen.
- Chrome, Word, Google Docs, Preview.

## Kendte fælder

- Brug altid scripts eller `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` – systemets `swift` er for gammel.
- espeak-ng fejler, hvis stien til dens data er over ca. 160 tegn.
- sherpa-onnx 2.x har fjernet espeak-ng; projektet bruger derfor 1.13.8.
- Bundle-id'et bestemmer Tilgængelighed-tilladelsen. Ændres det, skal brugeren give adgang igen.
- De midlertidige Python-miljøer fra de første stemmetests findes ikke længere; AP-02 genskaber dem.
