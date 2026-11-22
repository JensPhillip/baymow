# Stavetesten (AP-63)

Måler stavehjælpen med Macens indbyggede sprogmodel og vagten i `Sources/BaymowKit/Features/Spelling/`.
Kun egne testsætninger – aldrig brugerens tekst.

```bash
./Scripts/build-app.sh
./build/Baymow.app/Contents/MacOS/Baymow --spell-test tools/stavetest/saetninger.tsv tools/stavetest/resultater/saetninger.json
./build/Baymow.app/Contents/MacOS/Baymow --spell-test tools/stavetest/kontrol.tsv tools/stavetest/resultater/kontrol.json
```

- `saetninger.tsv`: 50 sætninger (20 uden fejl). Vagten er indstillet på dem.
- `kontrol.tsv`: 30 sætninger (17 uden fejl), skrevet *efter* vagten var indstillet. Det er det ærlige tal.
- Tal: `rettet`, `markeret` ("tjek selv"), `overset`, og vigtigst `forkerte_rettelser` (ord, der hverken stod i teksten
  eller i facit) og `fejlfri_saetninger_aendret`. Tegnsætning tæller ikke med.
- `foerste-vagt.json` er første udgave af vagten, til sammenligning.
