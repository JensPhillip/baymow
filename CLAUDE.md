# Baymow

Native macOS-app, der læser markeret tekst højt for mennesker med ordblindhed (⌃⌥S).
Swift-pakke: `BaymowCore` (kernen), `BaymowKit` (stemmer, brugerflade, værktøjer), `Baymow` (eksekverbar),
`CSherpaOnnx` (C-header).

## Læs først

1. `docs/PROJEKTPLAN.md` afsnit 1–4, og derefter kun den arbejdspakke (AP-xx), du har fået.
2. `docs/STATUS.md`: hvad er færdigt, i gang, og hvad venter på brugeren.
3. `docs/TEKNISK-VURDERING.md`, når du har brug for målinger, fund eller kilder.

Arbejd på én arbejdspakke ad gangen. Løs det, pakken beder om – ikke mere. Ser du andet, der bør
rettes, så skriv det under "Fundet undervejs" i afleveringen.

## Kommandoer

Xcode er ikke valgt i systemet; scripts sætter selv `DEVELOPER_DIR`. Til direkte `swift`-kald:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

```bash
./Scripts/fetch-vendor.sh
```

Henter de færdigbyggede biblioteker efter en frisk kopi af projektet.

```bash
./Scripts/check.sh
```

Byg, tests, privatliv, netværk og kerne. **Skal slutte med "ALT GRØNT" før enhver aflevering.**

```bash
./Scripts/build-app.sh --install
```

Bygger, signerer, lægger appen i Programmer og genstarter den.

## Kernen må kun ændres med vilje

Kernen er målet `BaymowCore` (`Sources/BaymowCore/`) og dets tests (`Tests/BaymowCoreTests/`). Den er
MVP'en: genvej → markeret tekst → session → stemme.

- Nye funktioner bygges uden om kernen, i `Sources/BaymowKit/Engines/` (stemmer) eller
  `Sources/BaymowKit/Features/<Navn>/` (alt andet),
  er slået fra som standard og bruger udvidelsespunkterne i planens afsnit 3.
- Fejler en test i `Tests/BaymowCoreTests/` efter din ændring, er ændringen forkert. Ret ikke testen.
- Må kernen ændres, kræver det et nyt afsnit i `docs/KERNEAENDRINGER.md`. `check.sh` afviser ellers.
- `BaymowCore` kan ikke se `BaymowKit` – compileren afviser det. Har kernen brug for noget udefra, så lav
  en protokol i kernen, som `BaymowKit` opfylder (som `SpeechEngine`).

## Regler, der ikke må brydes

- Brugerens markerede tekst må aldrig skrives til disk, logs, `print` eller fejlbeskeder.
  `DiagnosticsService.record` har med vilje ingen fritekst-parameter.
- Intet netværk uden et bevidst tryk fra brugeren. Kun filer på `Scripts/network-allowlist.txt` må
  bruge netværk. Cloud-stemmer er et tilvalg, aldrig en stille fallback.
- Efter `stop()` eller et nyt `speak()` må en motor ikke sende flere events fra det forrige kald.
- Al dansk tekst går gennem `DanishTextNormalizer`, før den når en stemmemotor.
- Blokerende arbejde (Accessibility, syntese, download) må ikke køre på hovedtråden.
- Brugerfladen er på dansk.
- Ingen ny afhængighed, download eller konto uden brugerens ja.
- Arbejd på en gren `ap-xx-kort-titel`. Flet ikke selv til `main`, og push ikke.

## Færdig betyder målt

Du kan ikke høre lyd eller se skærmen. Skriv ikke, at noget virker, fordi det kompilerer.

- Logik: tests med `FakeEngine`-mønstret i `Tests/BaymowCoreTests/CoreContractTests.swift`.
- Oplæsningsfejl: stemmetesten i `tools/stemmetest/` (36 sætninger kontrolleret med talegenkendelse).
- Lyd og udseende: giv brugeren en konkret testvejledning, og sæt pakken til "Afventer bruger".
- Brugerens afprøvninger kan ses i `~/Library/Logs/Baymow/baymow.log`.

Aflevér med `docs/afleveringer/SKABELON.md`, og opdatér `docs/STATUS.md`.

## Vigtigt at vide

- Den danske hovedstemme er valgt: Apple Sara (Enhanced) (B7, AP-19). En ny stemme skal stadig gennem
  stemmeporten (planens afsnit 7) og slå hende, før den kan blive standard.
- En stemme, der lyder godt, men siger noget forkert, er en fejl. Rigtig oplæsning går forud for flot stemme.
- En maskinmåling uden fejl betyder ikke, at stemmen er til at forstå. Brugerens lytning afgør det.
- Brugeren er ikke programmør. Skriv til dem på almindeligt sprog uden fagord.
