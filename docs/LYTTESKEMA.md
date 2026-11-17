# Lytteskema

Maskinmålingen viser kun, om en stemme siger de rigtige ord. Om stemmen er til at forstå og rar at
høre på, afgør brugeren her. En stemme kan først blive standard, når den har mindst **4** i
forståelighed og mindst **3** i naturlighed (stemmeporten, `PROJEKTPLAN.md` afsnit 7).

## Sådan gør du

1. Åbn mappen `stemmeproever/<stemmens navn>/`. Der ligger tre lydfiler pr. stemme: en nyhed, en
   mail med dato, klokkeslæt og beløb, og en fagtekst med lange ord.
2. Hør alle tre uden at læse teksten samtidig. (Teksterne ligger i `tools/lytteprove/tekster/`.)
3. Giv 1–5 for hvert punkt, og skriv gerne et par ord.

| Tal | Forståelighed | Naturlighed | Fejl |
|---|---|---|---|
| 5 | Forstår alt uden anstrengelse | Lyder som et menneske | Hørte ingen fejl |
| 4 | Forstår alt, enkelte ord kræver opmærksomhed | Behagelig, men tydeligt en maskine | En enkelt småfejl |
| 3 | Forstår meningen, men mister ord | Til at holde ud | Flere småfejl |
| 2 | Må høre det igen for at forstå | Trættende | Fejl, der ændrer meningen |
| 1 | Kan ikke følge med | Ubehagelig | Mange fejl |

## Bedømmelser

| Stemme | Dato | Forståelighed | Naturlighed | Fejl | Brugerens ord |
|---|---|---|---|---|---|
| Apple Sara (kompakt) – `apple-sara/` | | | | | |
| Apple Sara (Enhanced) – `apple-sara-enhanced/` | | | | | |
| Apple Magnus (Enhanced) – `apple-magnus-enhanced/` | | | | | |
| Piper talesyntese – `piper-talesyntese/` | 2026-11-16 | ikke givet | ikke givet | ikke givet | Til at forstå på almindelig tekst (svar på direkte spørgsmål efter lyttepakken) |

## Tidligere domme (før lyttepakken fandtes)

Disse er givet på andre tekster og uden tal. De står her, så de ikke går tabt; stemmerne bør høres
igen med lyttepakken, hvis de stadig er aktuelle.

| Stemme | Dato | Hørt på | Brugerens ord |
|---|---|---|---|
| Apple Sara (kompakt) | 2026-11-16 | Egne tekster via genvejen | "Kan være en fin fallback, men de lyder ikke så menneskelige og er ikke særlig gode oplæsere" |
| Røst v3 500m | 2026-11-16 | `stemmeproever/4-roest-v3-500m.wav` | "Jeg kunne bedst lide" denne |
| Plapre 3, Tor | 2026-11-16 | `stemmeproever/5-plapre3-tor.wav` | "Stemmen er god, men der var lidt fejl og den taler langsomt" |
| Plapre 3, justeret | 2026-11-16 | `stemmeproever/6-…` og `7-…` | "Det er bedre, men modellerne er ikke så gode til tal eller til nogle ord … sætningen giver ikke altid helt mening" |
| Piper talesyntese | 2026-11-16 | Tekst fra Claude-appen via genvejen (teknisk tekst med engelske ord) | "Ikke helt god nok. Den laver for mange fejl og bliver næsten lidt uforståelig" |
