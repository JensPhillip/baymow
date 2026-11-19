# Licenser

**Baymow** er fri software udgivet under **GNU General Public License version 3 eller senere** (GPL-3.0-or-later).
Den fulde tekst står i `LICENSE`. Besluttet af brugeren 18. november 2026 (B8).

Det betyder kort: alle må bruge, læse, ændre og videregive Baymow – også mod betaling – men den, der videregiver
Baymow eller en ændret udgave, skal give modtageren den samme frihed og kildekoden. Det er ikke juridisk rådgivning.

## Det, der bygges ind i appen

Baymow linker disse biblioteker statisk fra `Vendor/sherpa-onnx/lib` (sherpa-onnx v1.13.8, se `Scripts/fetch-vendor.sh`).
Licenserne er dem, projekterne selv oplyser.

| Del | Bruges til | Licens |
|---|---|---|
| sherpa-onnx | Afvikling af Piper-stemmer | Apache-2.0 (`Vendor/sherpa-onnx/LICENSE`) |
| ONNX Runtime | Kører stemmemodellen | MIT |
| eSpeak NG (inkl. ucd-tools) | Udtale (tekst til lyde) for Piper | GPL-3.0-or-later |
| piper-phonemize | Bindeled mellem eSpeak NG og Piper | MIT |
| Kaldi-komponenter (kaldi-native-fbank, kaldi-decoder, kaldifst) | Hjælpebiblioteker i sherpa-onnx | Apache-2.0 |
| OpenFst | Hjælpebibliotek i sherpa-onnx | Apache-2.0 |
| KISS FFT | Lydberegning i sherpa-onnx | BSD-3-Clause |
| SentencePiece | Hjælpebibliotek i sherpa-onnx | Apache-2.0 |

Alle er forenelige med GPL-3.0. eSpeak NG er grunden til, at Baymow skal være GPL, så længe Piper er bygget ind.

## Det, brugeren selv henter

| Del | Hentes hvor | Licens |
|---|---|---|
| Apples stemmer (Sara m.fl.) | Systemindstillinger, af brugeren | Del af macOS; distribueres ikke af Baymow |
| Piper-stemmen "talesyntese" | Knappen "Hent" i Baymow (fra sherpa-onnx' udgivelser) | Stemmesamlingen er MIT; træningsdata CC0 ifølge modelkortet (kilden er dog anfægtet, se `TEKNISK-VURDERING.md`) |

## Kun i udviklingsværktøjerne (følger ikke med appen)

| Del | Bruges til | Licens |
|---|---|---|
| Whisper large-v3-turbo (mlx-community) og mlx-whisper | Stemmetesten (talegenkendelse) | MIT |
| Python-pakker i `tools/stemmetest/requirements.txt` | Stemmetesten | Hver sin frie licens (MIT/BSD) |

## Før appen udgives (AP-52)

- MIT-, BSD- og Apache-licenserne kræver, at deres licenstekster og ophavsretslinjer følger med den færdige app.
  De skal hentes fra hvert projekt i præcis den version, der er bygget ind, og lægges i appens Resources sammen
  med en henvisning fra "Om Baymow". De står ikke her endnu, fordi de skal tages fra kilden – ikke skrives af hukommelsen.
- Kildekoden skal være tilgængelig for den, der får appen (GPL). Det enkleste er et offentligt kodearkiv og et link i "Om Baymow".
- Tager projektet imod kode fra andre, og skal en lukket udgave kunne sælges senere, kræver det en bidragsaftale (CLA)
  før bidraget flettes ind (se `PROJEKTPLAN.md`, "Licens og indtjening").
