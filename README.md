# Baymow

Baymow læser markeret tekst højt – i næsten alle programmer på din Mac. Den er lavet til mennesker med
ordblindhed og andre, der har lettere ved at lytte end at læse.

Markér en tekst, tryk **⌃⌥S** (Control, Option og S), og teksten bliver læst op. Oplæsningen fortsætter,
selv om du skifter program, og en lille afspiller lader dig sætte på pause, skifte hastighed og starte forfra.

## Det, Baymow lover

- **Rigtig oplæsning før flot stemme.** Tal, datoer, beløb, forkortelser og webadresser skrives om, så de
  læses, som man siger dem ("kl. 14.30" → "klokken fjorten tredive").
- **Alt sker på din Mac.** Den markerede tekst sendes ingen steder hen og gemmes ikke – heller ikke i logfiler.
  Baymow bruger kun internettet, når du selv trykker "Hent" for at hente en stemme.
- **Dansk og engelsk.** Sproget genkendes af sig selv. Den anbefalede danske stemme er Apples Sara (forbedret).

## Krav

- macOS 14 eller nyere på en Mac med Apple Silicon (M1 eller nyere).
- Tilladelse under Systemindstillinger → Anonymitet & sikkerhed → Tilgængelighed, så Baymow kan se det, du
  markerer. Baymow guider dig, første gang du starter den.

## Byg selv

Kræver Xcode.

```bash
./Scripts/fetch-vendor.sh
```

```bash
./Scripts/check.sh
```

```bash
./Scripts/build-app.sh --install
```

`fetch-vendor.sh` henter de færdigbyggede biblioteker (ca. 90 MB) og kontrollerer deres fingeraftryk.
`check.sh` bygger, kører alle tests og kontrollerer privatlivs- og netværksreglerne. `build-app.sh --install`
lægger appen i Programmer. En installationsfil laves med `./Scripts/make-dmg.sh`.

## Til udviklere og AI-assistenter

Projektplanen, reglerne og status står i `docs/`. Start med `CLAUDE.md` og `docs/PROJEKTPLAN.md` afsnit 1–4.
Kernen (`Sources/BaymowCore`) er MVP'en og ændres kun med vilje – se `docs/KERNEAENDRINGER.md`.

## Licens

Baymow er fri software under **GNU General Public License version 3 eller senere** (`LICENSE`).
Baymow bygger på andre frie projekter; de og deres licenser står i `docs/LICENSER.md` og under "Om Baymow" i appen.
