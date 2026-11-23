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

## Internet-hjælpen (AP-64)

- `svaer.tsv`: 35 sværere sætninger i stil med en arbejdsbesked (rigtige ord brugt forkert, fejl som Macens
  stavekontrol godkender, navne og forkortelser). Skrevet 23. november 2026 efter brugerens eksempel.
- Gennem Baymow: nøglen gives som miljøvariabel, så den ikke står på kommandolinjen.

```bash
BAYMOW_TEST_KEY="$(security find-generic-password -a baymow-test -s baymow-claude -w)" ./build/Baymow.app/Contents/MacOS/Baymow --spell-test tools/stavetest/svaer.tsv /tmp/sky.json --cloud claude
```

- Modellerne alene (uden Baymow): `sammenlign_modeller.py <model> low <filer…>` (nøgler fra nøgleringen,
  `baymow-claude` / `baymow-openai`, konto `baymow-test`) og `sammenlign_ollama.py <model> <filer…>` (lokalt via Ollama).
- `resultater/sky-*.json`: Claude Sonnet 5.5 og GPT-6 Luna gennem vagten.

## Niveauer (AP-68)

- `tegnsaetning.tsv`: 25 sætninger med tegnfejl (startkomma, store bogstaver, spørgsmålstegn).
- `klarhed.tsv`: 8 tunge sætninger til "klarere sætninger" – læses igennem af et menneske; der er ikke ét facit.
- `--level spelling|punctuation|clarity` vælger niveauet; testen skriver også "Tegnsætning: … helt som facit".
- `resultater/niveau-*.json`: GPT-6 Luna på de tre niveauer.
