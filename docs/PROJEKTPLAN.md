# Baymow – projektplan

Version 2 · 16. november 2026. Projektet hed tidligere "Oplæser".

**Ny på projektet? Start her:**

1. Læs afsnit 1–4 i denne plan (ca. 10 minutter).
2. Læs `docs/STATUS.md`: hvad er færdigt, hvad er i gang, hvad venter på brugeren.
3. Kør `./Scripts/fetch-vendor.sh` og derefter `./Scripts/check.sh`. Alt skal være grønt, før du ændrer noget.
4. Tag den arbejdspakke, du har fået – eller den første ledige i tabellen i afsnit 6 – og læs kun den.
5. Løs pakken, kør `./Scripts/check.sh`, skriv en aflevering (afsnit 4), og opdatér `docs/STATUS.md`.

Planen er skrevet, så en udfører kan løse én arbejdspakke uden at kende projektets historie.
Målinger, fund og kilder bag beslutningerne står i `TEKNISK-VURDERING.md`. Ved tvivl gælder
brugerens seneste besked.

---

## 1. Målet

Baymow er en native macOS-app til mennesker med ordblindhed. Brugeren markerer tekst i et
vilkårligt program, trykker en global genvej (⌃⌥S), og teksten bliver læst højt af en stemme, der
er **til at forstå og siger det, der står**.

Prioritering, når hensyn kolliderer (øverst vinder):

1. **Korrekt og forståelig oplæsning.** En flot stemme, der siger noget forkert, er værre end en
   kedelig stemme, der siger det rigtige. Brugeren kan ikke selv kontrollere teksten – det er hele
   grunden til, at de bruger appen.
2. **Pålidelighed.** Genvejen virker hver gang, appen crasher ikke, tilstanden er aldrig uklar.
3. **Hastighed.** Ca. ét sekund fra tastetryk til første lyd for korte tekster.
4. **Privatliv.** Markeret tekst forlader ikke computeren, medmindre brugeren udtrykkeligt har
   valgt en cloud-stemme. Tekst gemmes aldrig på disk og skrives aldrig i logs.
5. **Enkelhed** for brugeren og i koden.

Brugerens seneste retningslinje (16. november 2026): *kernefunktionen skal være meget fleksibel,
men produktet vægter højest.* Fleksibilitet betyder her, at stemmemotoren kan skiftes ud – også
med en cloud-tjeneste – uden at røre resten af appen.

### Ikke en del af MVP'en

Oplæsningskø, ordfremhævning, stavehjælp, opsummeringer, mail/kalender, læsehistorik, login,
synkronisering, App Store, Intel-Macs, automatisk start ved login, pluginsystem.

---

## 2. Hvor projektet står

### Virker og er bekræftet

| Område | Status |
|---|---|
| Global genvej ⌃⌥S | Bekræftet af brugeren |
| Tekstindfangning i Safari og Electron-apps | Bekræftet af brugeren; 10–550 ms |
| Session: start, pause, stop, genstart, erstatning uden overlap | Automatiske tests; grundforløb bekræftet af brugeren |
| Flydende afspiller, menulinje, hovedvindue, indstillinger | Bygget; kun delvist set af brugeren |
| Dansk tekstforberedelse (tal, datoer, klokkeslæt, forkortelser) | 36 testsætninger består |
| Stemme-download med kontrolsum | Kørt for alvor |
| Signering med Apple Development-certifikat, installation i Programmer | Virker |

### Det åbne hovedproblem: der findes endnu ingen dansk stemme, brugeren er tilfreds med

| Stemme | Brugerens dom | Maskinmåling (36 sætninger) | Andet |
|---|---|---|---|
| Apple Sara (kompakt) | "Fin fallback, men ikke menneskelig" | 23 fejlfri, 2,5 % tegnfejl | Øjeblikkelig, ingen licens |
| Piper talesyntese | "For mange fejl, næsten uforståelig" | 26 fejlfri, 1,9 % tegnfejl | Meget hurtig; GPL via espeak-ng |
| Plapre 3 (ONNX) | "God stemme, men fejl og langsom" | 9–15 fejlfri, 10–23 % tegnfejl | Gentager sætningsstumper |
| Røst v3 500m | "Den bedste" | Ikke målt | 2–7× for langsom på M3 |

**Vigtig lære:** Piper bestod maskinmålingen, men brugeren kan næsten ikke forstå den.
Talegenkendelse fanger forkerte og gentagne ord, men ikke om et menneske kan forstå stemmen.
Derfor er maskinmålingen et *nødvendigt* krav, mens brugerens lytning er det *afgørende*.

### Kendte mangler i den nuværende kode

- Chrome, Word, Google Docs og Preview er ikke afprøvet.
- Pause/fortsæt med en backend-stemme er kun afprøvet lydløst (`--player-selftest`), ikke af brugeren.
- Appen er i sin nuværende form bundet af GPL (espeak-ng er linket ind).
- Engelske ord i dansk tekst læses forkert af alle afprøvede lokale stemmer. Omstavning (AP-24) hjalp
  kun lidt; en stemme, der selv kan skifte sprog, er den realistiske løsning.

---

## 3. Arkitektur

Swift-pakke uden eksterne Swift-afhængigheder. `BaymowKit` indeholder al logik og UI;
`Baymow` er en tynd eksekverbar fil; `CSherpaOnnx` gør et C-bibliotek synligt for Swift.

```
Genvej ─▶ TextCaptureService ─▶ ReadingSessionManager ─▶ SpeechEngine ─▶ lyd
                                   │        ▲
                                   │        └── events: started / progress / finished / failed
                                   ├── LanguageDetectionService (dansk/engelsk)
                                   ├── TextChunker (sætningsbidder)
                                   ├── DanishTextNormalizer (tal → ord)
                                   └── VoiceCatalog ◀── SettingsStore, ModelDownloader
FloatingPlayer og MainWindow observerer ReadingSessionManager / SettingsStore.
DiagnosticsService logger hændelser uden tekst.
```

| Mappe | Fil | Ansvar |
|---|---|---|
| `Sources/BaymowCore/` | `ReadingSessionManager.swift` | Den ene aktive session og dens tilstand |
| `Sources/BaymowCore/` | `TextCaptureService.swift` | Markeret tekst via Accessibility, ellers ⌘C med gendannelse |
| `Sources/BaymowCore/` | `GlobalShortcutManager.swift` | Carbon-hotkey |
| `Sources/BaymowCore/` | `SpeechEngine.swift` | Protokollen, alle stemmemotorer opfylder |
| `Sources/BaymowCore/` | `VoiceCatalog.swift` | Installerede stemmer og valg af stemme |
| `Sources/BaymowCore/` | `LanguageDetectionService.swift` | Sproggenkendelse og `TextChunker` |
| `Sources/BaymowCore/` | `DanishTextNormalizer.swift` | Skriver dansk tekst, som den siges |
| `Sources/BaymowCore/` | `SettingsStore.swift`, `Models.swift` | Indstillinger (UserDefaults) og fælles typer |
| `Sources/BaymowCore/` | `DiagnosticsService.swift` | Lokal log uden brugerindhold |
| `Sources/BaymowCore/` | `PronunciationOverrides.swift` | Udskifter ord med en stavemåde, motoren udtaler rigtigt |
| `Sources/BaymowKit/Engines/` | `AppleSpeechEngine.swift` | macOS' egne stemmer |
| `Sources/BaymowKit/Engines/` | `SynthesisBackend.swift` | `SynthesisBackend`, `PCMOutput` og `BackendSpeechEngine` |
| `Sources/BaymowKit/Engines/` | `PCMPlayer.swift` | Fælles lydafspiller for alle backends |
| `Sources/BaymowKit/Engines/` | `PiperBackend.swift` | Piper via sherpa-onnx (laver kun lyd) |
| `Sources/BaymowKit/Engines/` | `ModelDownloader.swift` | Stemmer, der kan hentes; `VoiceStore` |
| `Sources/BaymowKit/UI/` | `AppShell.swift` | Livscyklus, menulinje, kobler tjenesterne sammen |
| `Sources/BaymowKit/UI/` | `FloatingPlayer.swift`, `MainWindow.swift` | Afspiller, beskeder, indstillinger, stemmebibliotek |
| `Sources/BaymowKit/Tools/` | `AccessibilityDiagnostics.swift`, `DeveloperTools.swift`, `LatencyProbe.swift` | Kommandolinjeværktøjer |
| `Sources/BaymowKit/Features/` | (findes ikke endnu) | Fremtidige funktioner, én undermappe pr. funktion |

### Kernen

**Kernen er MVP'en:** genvej → markeret tekst → session → stemme. Den er SwiftPM-målet `BaymowCore`
(`Sources/BaymowCore/`) med testmålet `BaymowCoreTests` (`Tests/BaymowCoreTests/`).

Afhængigheder må kun pege indad:

```
BaymowKit: Tools ─┐
           UI ────┼──▶ Engines ──▶ BaymowCore        Features ──▶ BaymowCore
                  └──────────────▶ BaymowCore        UI ──▶ Features
```

`BaymowCore` afhænger ikke af `BaymowKit`, og **compileren afviser det**: en kernefil, der importerer
`BaymowKit` eller bruger en type derfra, kan ikke bygges. Har kernen brug for noget udefra, defineres en
protokol i kernen, som `BaymowKit` opfylder – sådan som `SpeechEngine` gør for stemmemotorerne.

**Kernekontrakten** er den adfærd, der ikke må ændre sig ved et uheld. Hvert punkt har tests i
`Tests/BaymowCoreTests/` (K7 også i `DanishTextNormalizerTests.swift`):

| # | Kontrakt |
|---|---|
| K1 | Der er højst én session. En ny oplæsning erstatter den gamle uden overlap, og forsinkede events fra den gamle ignoreres |
| K2 | Pause, fortsæt, stop og start forfra virker fra enhver tilstand; efter stop og efter endt oplæsning kan teksten genstartes |
| K3 | Luk frigiver teksten: ingen session, intet sprog, ingen position |
| K4 | Tekst læses i hele sætningsbidder, i rækkefølge, uden at ord går tabt |
| K5 | Hastighed kan ændres undervejs og fortsætter fra det ord eller den sætning, der var nået; hastigheden holdes inden for 0,5–2,0 |
| K6 | Sproget genkendes automatisk, kan tvinges i indstillingerne og kan skiftes for den aktuelle tekst |
| K7 | Dansk tekst forberedes, før den når motoren; engelsk tekst ændres ikke |
| K8 | Kun godkendte stemmer vælges automatisk; brugerens eget valg gælder altid; mangler der en stemme, får brugeren besked |
| K9 | Indstillinger overlever en genstart; standarderne er dansk, automatisk sprog, hastighed 1,0 og ⌃⌥S |
| K10 | Loggen indeholder aldrig oplæst tekst |

Fejler en test i `Tests/BaymowCoreTests/` efter din ændring, er det ændringen, der er forkert. Ret ikke testen.

**Bevidst kerneændring.** Kernen må gerne ændres – men kun med vilje. En ændring i en kernefil
kræver et nyt afsnit i `docs/KERNEAENDRINGER.md` (hvad, hvorfor, hvilke kontrakter, godkendt af).
`Scripts/check.sh` afviser kerneændringer uden sådan et afsnit. En arbejdspakke, der forventes at
røre kernen, siger det udtrykkeligt under "Kerne".

### Sådan tilføjes en ny funktion uden at røre kernen

Brug de faste udvidelsespunkter. Passer funktionen ikke i et af dem, så stop og spørg arkitekten.

| Du vil tilføje | Gør sådan | Rører kernen? |
|---|---|---|
| En ny stemme eller stemmemotor | Ny `SynthesisBackend` (efter AP-10) eller `SpeechEngine` i `Engines/`; registrér den i `AppShell` | Nej |
| En stemme, der kan hentes | Ny post i `DownloadableVoice.catalog` med SHA-256; `isApprovedDefault: false`, indtil stemmeporten er bestået | Nej |
| En cloud-tjeneste | Som stemmemotor, med `requiresNetwork = true`, filen tilføjet til `Scripts/network-allowlist.txt`, slået fra som standard | Nej |
| Noget, der følger oplæsningen (fx ordfremhævning, statistik) | Ny mappe i `Sources/BaymowKit/Features/`, som observerer `ReadingSessionManager`s `@Published`-felter (`state`, `progress`, `language`, `sourceAppName`) | Nej |
| En ny indstilling | Nyt felt i `SettingsStore` med en standardværdi, der giver uændret adfærd | Ja, lille – begrund i `KERNEAENDRINGER.md` |
| Et nyt sprog | Ny `case` i `Language` + regler for stemmevalg; evt. en tekstforberedelse for sproget | Ja – begrund |
| En ny måde at hente tekst på | Ny strategi i `TextCaptureService`, efter de eksisterende | Ja – begrund |
| En ny loghændelse | Ny `case` i `DiagnosticsService.Event`; aldrig en fritekst-parameter | Ja, lille – begrund |
| Noget, der bruger selve teksten (opsummering, stavehjælp) | Ny mappe i `Sources/BaymowKit/Features/`. Teksten må kun hentes fra en ny, udtrykkelig metode på sessionen, og funktionen skal være slået fra som standard | Ja – kræver arkitektens ja |

Tre regler for enhver ny funktion:

1. **Slået fra som standard**, med en indstilling. Med funktionen slået fra opfører appen sig
   nøjagtigt som før – skriv en test, der viser det.
2. **Egen mappe** under `Sources/BaymowKit/Features/` og egne tests. Ingen ændringer i andre funktioners mapper.
3. **Kernekontrakten består uændret.** Hvis den ikke kan det, er det en kerneændring, og så
   gælder afsnittet ovenfor.

### Regler, der ikke må brydes

1. **Ingen events efter stop.** Efter `stop()` eller et nyt `speak()` må en motor ikke sende
   events fra det forrige kald. Det er det, der forhindrer overlap.
2. **Ingen brugertekst uden for hukommelsen.** `DiagnosticsService.record` har med vilje ingen
   fritekst-parameter. Tilføj ikke en. Skriv ikke tekst til disk, `print`, `NSLog` eller `os_log`.
3. **Netværk kun efter et bevidst tryk.** I dag: knappen "Hent". En cloud-stemme er kun tilladt
   som et tilvalg, brugeren selv har slået til, med tydelig mærkning. Aldrig som stille fallback.
4. **Dansk tekst forberedes før motoren.** Al dansk tekst går gennem `DanishTextNormalizer`.
5. **UI kører på hovedtråden; blokerende arbejde gør ikke.** Accessibility-kald, syntese,
   download og udpakning holdes væk fra hovedtråden.
6. **Brugerfladen er på dansk.** Kode, typer og kommentarer følger filens eksisterende stil.
7. **Hold dig til pakken.** Løs det, arbejdspakken beder om – ikke mere. Ser du noget andet, der
   bør rettes, så skriv det under "Fundet undervejs" i afleveringen i stedet for at rette det.

Regel 2 og 3 kontrolleres mekanisk af `Scripts/check.sh` (ingen udskrift eller logning i
app-koden, ingen filskrivning i kernen, netværk kun i filer på `Scripts/network-allowlist.txt`).

### Stemmearkitektur (indført i AP-10)

Der skelnes mellem to slags motorer. Typerne ligger i `Engines/SynthesisBackend.swift` og `Engines/PCMPlayer.swift`:

```swift
/// Laver lyd af tekst. Ved intet om afspilning. Piper, Plapre, Røst og cloud-tjenester.
protocol SynthesisBackend: Sendable {
    var backendID: String { get }
    var requiresNetwork: Bool { get }
    func installedVoices() -> [Voice]
    /// Én sætning ind, mono-PCM ud. Må blokere; kaldes aldrig på hovedtråden.
    func synthesize(_ sentence: String, voice: Voice, rate: Double) throws -> PCMChunk
}

/// Fælles afspiller: kø af PCM-bidder, pause, stop, lydstyrke, events.
@MainActor final class PCMPlayer { … }

/// Gør en SynthesisBackend til en SpeechEngine ved hjælp af PCMPlayer.
@MainActor final class BackendSpeechEngine: SpeechEngine { … }
```

`AppleSpeechEngine` forbliver en selvstændig `SpeechEngine`, fordi systemet selv afspiller.
En ny stemme – lokal eller cloud – er derefter kun en ny `SynthesisBackend` på 50–150 linjer.

---

## 4. Sådan arbejder du

### Byg og test

Xcode er installeret, men ikke valgt i systemet. Sæt derfor altid `DEVELOPER_DIR`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Den samlede kontrol, som **skal** være grøn før enhver aflevering (byg, tests, privatliv, netværk, kerne):

```bash
./Scripts/check.sh
```

Efter en frisk kopi af projektet hentes de færdigbyggede biblioteker (ca. 90 MB) med:

```bash
./Scripts/fetch-vendor.sh
```

Stemmetest (36 sætninger kontrolleret med talegenkendelse) og lyttepakke til brugeren, for Piper
eller en af macOS' stemmer:

```bash
./Scripts/test-voice.sh apple Sara
```

```bash
./Scripts/make-listening-pack.sh apple Sara
```

Byg appen, og læg den i Programmer (genstarter den kørende app):

```bash
./Scripts/build-app.sh --install
```

Nyttige værktøjer i den byggede app (`build/Baymow.app/Contents/MacOS/Baymow`):

| Argument | Gør |
|---|---|
| `--measure-latency` | Lydløs måling af tid til talestart for dansk og engelsk |
| `--synthesize <stemmemappe> <tekstfil> <ud-mappe>` | Én wav pr. linje med Piper og tekstforberedelse |
| `--normalize` | Læser linjer fra stdin, skriver den forberedte tekst |
| `--synthesize-text <stemmemappe> <tekstfil> <ud.wav>` | Hele teksten som én lydfil, som appen ville læse den |
| `--install-voice <id>` | Henter en stemme med samme kode som knappen "Hent" |
| `--player-selftest` | Lydløs kontrol af den rigtige afspiller: events, pause, fortsæt, stop, erstatning |
| `--ax-diagnose <bundle-id>` | Skal startes med `open -n -W build/Baymow.app --args …`; skriver til `~/Library/Logs/Baymow/ax-diagnose.txt` |

Loggen fra brugerens afprøvninger: `~/Library/Logs/Baymow/baymow.log`. Læs den, før du
spørger brugeren om, hvad der skete.

### Definition af færdig

En arbejdspakke er færdig, når **alle** punkter er opfyldt:

- Pakkens acceptkriterier er opfyldt, og du har selv kørt kontrollen, der står under dem.
- `./Scripts/check.sh` slutter med "ALT GRØNT".
- Ny logik har tests. Tests bruger `FakeEngine`-mønstret fra `Tests/BaymowCoreTests/CoreContractTests.swift`, ikke lyd.
- `TEKNISK-VURDERING.md` er opdateret med nye målinger og begrænsninger.
- Der ligger en aflevering i `docs/afleveringer/AP-xx.md` (skabelon: `docs/afleveringer/SKABELON.md`),
  og `docs/STATUS.md` og statuskolonnen i afsnit 6 er opdateret.
- Arbejdet er committet på en gren med navnet `ap-xx-kort-titel`. Flet ikke selv til `main`.

Skriv aldrig, at noget "virker", hvis du kun har set, at det kompilerer. Du kan ikke høre lyd og
ikke se skærmen: alt, der handler om lyd eller udseende, skal enten måles (stemmetesten) eller
overlades til brugeren med en konkret testvejledning. Statusser i denne plan:

| Status | Betyder |
|---|---|
| Ikke startet | Ingen har rørt pakken |
| I gang | En udfører arbejder på den; navn og dato står i `STATUS.md` |
| Afventer bruger | Koden er klar, men brugeren skal lytte, se, oprette konto eller beslutte |
| Færdig | Acceptkriterierne er opfyldt og kontrolleret |
| Opgivet | Sporet er lukket; begrundelsen står i afleveringen |

### Stop og spørg

Stop og spørg arkitekten eller brugeren, når:

- Et acceptkriterium ikke kan opfyldes, eller to krav er i konflikt.
- Løsningen kræver netværk, en ny afhængighed, en download eller en konto.
- Løsningen ændrer en regel i afsnit 3 eller en beslutning i afsnit 5.
- Du er ved at ændre mere end de filer, pakken nævner, for at få den til at lykkes.
- Tests fejler af en grund, du ikke forstår. Ret ikke testen for at få den til at bestå.

Spørg ikke om navne, småstrukturer og andre valg, der er nemme at lave om.

### Roller

- **Bruger:** lytter og bedømmer stemmer, opretter konti, giver tilladelser, træffer
  produktbeslutninger. Kan ikke programmere.
- **Arkitekt:** ejer denne plan og beslutningerne i afsnit 5, gennemgår porte og arkitekturændringer.
- **Udfører:** løser én arbejdspakke ad gangen efter reglerne her.

---

## 5. Beslutninger

| Nr. | Beslutning | Status |
|---|---|---|
| B1 | Swift + SwiftUI/AppKit, ikke sandboxet, minimum macOS 14, kun Apple Silicon | Truffet |
| B2 | Tekst hentes via Accessibility; ⌘C med gendannelse af udklipsholderen er fallback | Truffet |
| B3 | Al dansk tekst forberedes i `DanishTextNormalizer` før enhver motor | Truffet |
| B4 | Apples stemmer er fallback og standard, indtil en bedre stemme har passeret stemmeporten | Truffet |
| B5 | En stemme bliver kun standard gennem stemmeporten (afsnit 7) | Truffet |
| B10 | Kernen (afsnit 3) ændres kun bevidst og med begrundelse; nye funktioner bygges uden om den og er slået fra som standard | Truffet af brugeren 16. november 2026 |
| B6 | Cloud-stemmer laves **ikke nu**. De kan blive en senere forbedring; hvis de kommer, er de et udtrykkeligt tilvalg, aldrig standard eller stille fallback | Truffet af brugeren 17. november 2026. AP-13 og AP-14 er udskudt |
| B7 | Hvilken dansk stemme bliver hovedstemme? | **Åben** – afgøres i fase 1 |
| B8 | Baymow bliver **open source**, med mulighed for at tjene penge senere, og det er en fordel, at koden kan gennemskues udefra. Konkret licens: se "Licens og indtjening" nedenfor | Truffet af brugeren 17. november 2026. Valg af licens afventer brugerens bekræftelse (kræves først før udgivelse) |
| B9 | Appen hedder **Baymow** | Truffet af brugeren 16. november 2026. Bundle-id `dk.baymow.app` er stadig en pladsholder og skal afgøres før AP-52 |

---

### Licens og indtjening (anbefaling til B8)

Arkitektens anbefaling, ikke juridisk rådgivning:

- **GPL-3.0-or-later for hele appen.** Piper bruger espeak-ng, som er GPL-3.0, og så længe Piper er bygget
  ind, skal den færdige app alligevel kunne udgives under GPL. GPL tillader salg, og den forhindrer, at
  andre tager koden og laver en lukket konkurrent. Koden kan læses af alle, som brugeren ønsker.
- **Indtjening, der passer med open source:** salg af den færdige, signerede app (fx i App Store eller fra
  hjemmesiden), mens koden er gratis at bygge selv; frivillige bidrag og sponsorater; betalte tilvalg, der
  kører hos en tjeneste (fx cloud-stemmer senere, jf. B6); support eller licenser til skoler og kommuner.
- **Hold døren åben for dobbeltlicens.** Vil man senere kunne sælge en lukket udgave til en virksomhed,
  skal man eje ophavsretten til al koden. Tager projektet imod bidrag udefra, bør bidragydere derfor
  skrive under på en bidragsaftale (CLA), før deres kode flettes ind.
- Licensfilen (`LICENSE`) og "Om"-siden laves i AP-50, når brugeren har bekræftet licensen.

## 6. Arbejdspakker

Rækkefølgen er: fase 0 → fase 1 (kritisk sti) → resten. Fase 2 og 3 kan køre parallelt med
fase 1, fordi de ikke rører de samme filer – undtagen AP-10, som skal være færdig før AP-13 og AP-14.
To udførere må aldrig arbejde i de samme filer samtidig; se `docs/STATUS.md`, før du starter.

Hver pakke har felterne **Hvorfor**, **Gør**, **Acceptkriterier** og eventuelt **Filer**,
**Kontrol**, **Kerne** (om pakken må røre kernen), **Stop og spørg** og **Faldgrube**. Står der
intet under Kerne, må pakken ikke ændre kernefiler.

| Pakke | Titel | Fase | Udføres af | Afhænger af | Status |
|---|---|---|---|---|---|
| AP-00 | Permanent mappe og versionsstyring | 0 | Arkitekt | – | Færdig |
| AP-01 | Apple som standard igen | 0 | Arkitekt | – | Færdig |
| AP-02 | Reproducerbar stemmetest | 0 | Arkitekt | AP-00 | Færdig |
| AP-03 | Lyttepakke til brugeren | 0 | Arkitekt | AP-02 | Afventer bruger |
| AP-10 | Fælles lydafspiller og `SynthesisBackend` | 1 | Arkitekt | AP-00 | Færdig |
| AP-11 | Apples bedre danske stemmer | 1 | Bruger + udfører | AP-03 | Afventer bruger (målt; lyttepakke sendt) |
| AP-12 | Hvorfor er Piper uforståelig? | 1 | Arkitekt | AP-03 | Færdig |
| AP-13 | Cloud-stemme: Azure | 1 | Udfører + bruger | AP-10, B6 | Udskudt (B6) |
| AP-14 | Cloud-stemme: ElevenLabs | 1 | Udfører + bruger | AP-13 | Udskudt (B6) |
| AP-15 | Plapre: afprøv originalmodellen | 1 | Udfører + bruger | AP-02 | Ikke startet |
| AP-16 | Røst 500m: kan den gøres hurtig nok? | 1 | Arkitekt eller stærk udfører | AP-02 | Ikke startet |
| AP-19 | Stemmeport: vælg hovedstemme | 1 | Arkitekt + bruger | AP-11 til AP-16 | Ikke startet |
| AP-20 | Afspilleren: afprøvning og rettelser | 2 | Udfører + bruger | AP-10 | Ikke startet |
| AP-21 | Lange tekster og programskift | 2 | Udfører | AP-10 | Ikke startet |
| AP-22 | Tekstforberedelse, runde 2 | 2 | Udfører | AP-02 | Færdig |
| AP-23 | Kernen som eget kompileringsmål | 2 | Udfører | AP-10 | Færdig |
| AP-24 | Engelske ord i dansk tekst | 2 | Arkitekt | – | Delvist: mekanismen er bygget, målet ikke nået (se afleveringen) |
| AP-30 | Chrome | 3 | Udfører + bruger | AP-00 | Delvist: brugeren har bekræftet, at genvejen virker (via kopiering, 0,65 s) |
| AP-31 | Word og Preview/PDF | 3 | Udfører + bruger | AP-00 | Ikke startet |
| AP-32 | Google Docs og testmatrix | 3 | Udfører + bruger | AP-30 | Ikke startet |
| AP-40 | Stemmebibliotek færdigt | 4 | Udfører | AP-19 | Ikke startet |
| AP-41 | Førstegangsopsætning | 4 | Udfører + bruger | AP-40 | Ikke startet |
| AP-50 | Licensoprydning | 5 | Arkitekt + udfører | AP-19, B8 | Ikke startet |
| AP-51 | Stabilitet, hukommelse og privatlivskontrol | 5 | Udfører | AP-20 til AP-41 | Ikke startet |
| AP-52 | Developer ID, notarisering og DMG | 5 | Udfører + bruger | AP-50, B9 | Ikke startet |

### Fase 0 – Grundlag

#### AP-00 Permanent mappe og versionsstyring — færdig

Udført af arkitekten 16. november 2026. Projektet ligger i `~/baymow` med git, `.gitignore`,
`Scripts/fetch-vendor.sh` (henter og kontrollerer de to arkiver) og `Scripts/check.sh`.
Projektet er omdøbt til Baymow, og koden er delt i `Core/`, `Engines/`, `UI/` og `Tools/`.
Se `docs/afleveringer/AP-00-01.md`.

#### AP-01 Apple som standard igen — færdig

Udført af arkitekten 16. november 2026. `Voice.isApprovedDefault` og
`DownloadableVoice.isApprovedDefault` styrer, om en stemme må vælges automatisk. Piper er mærket
som forsøgsstemme. To nye kontrakt-tests (K8). Se `docs/afleveringer/AP-00-01.md`.

#### AP-02 Reproducerbar stemmetest

**Hvorfor:** Stemmetesten er det eneste objektive mål for oplæsningsfejl, men dens Python-miljø
findes kun i en midlertidig mappe.
**Gør:** Tilføj `tools/stemmetest/requirements.txt` (mlx-whisper, soundfile, scipy, numpy,
onnxruntime, tokenizers) og `tools/stemmetest/README.md` med opsætning. Tilføj
`tools/stemmetest/run.sh <navn> <mappe-med-00.wav…35.wav>`, der transskriberer og udskriver
"fejlfri x/36, tegnfejl y %" samt alle afvigelser. Tilføj `Scripts/test-voice.sh`, der bruger
appens `--synthesize` og derefter `run.sh`. Lad `sentences.py` være den eneste kilde til
testsætninger, og generér Swift-testens liste fra den med et script i stedet for håndkopiering.
**Acceptkriterier:** På en ren maskine giver `Scripts/test-voice.sh` for Piper 26 ± 2 fejlfri.
Talegenkendelsen kører uden `ffmpeg` (se `load16k` i `bench_eval.py`).
**Stop og spørg:** Download af Whisper-modellen (ca. 1,6 GB) kræver brugerens ja.
**Faldgrube:** espeak-ng fejler, hvis stien til dens data er over ca. 160 tegn.

#### AP-03 Lyttepakke til brugeren

**Hvorfor:** Maskinmålingen fanger ikke forståelighed. Brugeren skal kunne sammenligne stemmer
på ens vilkår, og dommen skal kunne gemmes.
**Gør:** Læg tre faste tekster i `tools/lytteprove/tekster/`: en nyhedsartikel (ca. 120 ord), en
arbejdsmail med dato, klokkeslæt og beløb (ca. 80 ord) og et fagligt afsnit med lange ord
(ca. 100 ord). Skriv dem selv; brug ikke ophavsretsbeskyttet tekst. Lav
`Scripts/make-listening-pack.sh <stemmenavn>`, der lægger tre wav-filer i
`stemmeproever/<stemmenavn>/`. Lav `docs/LYTTESKEMA.md`, hvor brugeren for hver stemme giver
1–5 for forståelighed, naturlighed og fejl, plus fri kommentar.
**Acceptkriterier:** Pakker findes for Apple Sara og Piper. Skemaet er udfyldt for de fire
stemmer, brugeren allerede har hørt, med dommen fra afsnit 2.

### Fase 1 – Stemmen (kritisk sti)

Målet for fasen er at finde mindst én dansk stemme, der består stemmeporten i afsnit 7.
Sporene AP-11 til AP-16 er uafhængige forsøg. De billigste står først. Stop fasen, så snart en
stemme består, og brugeren er tilfreds – de øvrige spor kan vente.

#### AP-10 Fælles lydafspiller og `SynthesisBackend`

**Hvorfor:** Alle nye stemmer leverer rå lyd. I dag er afspilningen bygget ind i
`PiperSpeechEngine`, så hver ny motor ville kopiere 100 linjer med tråd- og annulleringslogik.
**Gør:** Indfør typerne fra "Målarkitektur" i afsnit 3. Flyt `AVAudioEngine`-delen fra
`PiperSpeechEngine` til `PCMPlayer`. Lav `BackendSpeechEngine`, der deler teksten i sætninger,
syntetiserer på en baggrundskø og sender bidder til `PCMPlayer`. Gør Piper til `PiperBackend`.
Understøt forskellige samplerates pr. bid. Lad en fejl i én sætning give `.failed`, ikke crash.
**Filer:** ny `PCMPlayer.swift`, ny `SynthesisBackend.swift`, `PiperSpeechEngine.swift` → `PiperBackend.swift`,
`AppShell.swift`, `LatencyProbe.swift`, `DeveloperTools.swift`, `MainWindow.swift` (alle uden for `Core/`).
**Acceptkriterier:** Reglen "ingen events efter stop" er testet for `BackendSpeechEngine` med en
falsk backend, herunder: stop midt i syntese, nyt `speak` midt i afspilning, pause efterfulgt af
stop, og backend der kaster fejl. `--measure-latency` giver samme størrelsesorden som før
(under 200 ms for Piper). `Scripts/test-voice.sh` giver samme resultat som før.
**Kerne:** Nej. `SynthesisBackend`, `PCMPlayer` og `BackendSpeechEngine` lægges i `Engines/`.
`SpeechEngine`-protokollen i kernen ændres ikke.
**Stop og spørg:** Hvis du mener, protokollen må ændres, så stop – det er en kerneændring.

#### AP-11 Apples bedre danske stemmer

**Hvorfor:** Det billigste forsøg. Brugeren har kun hørt den kompakte Sara. macOS tilbyder
større danske stemmer gratis, og de læser efter regler og digter ikke ord.
**Gør (bruger):** Hent alle danske stemmer i Systemindstillinger → Tilgængelighed → Oplæst
indhold → Systemstemme → Administrer stemmer → Dansk, i den højeste kvalitet, der tilbydes.
**Gør (udfører):** Kontrollér, at de dukker op i appen. Lav lyttepakke og stemmetest for hver
(`say -v <navn> -o` kan bruges til wav-filerne). Notér resultaterne.
**Acceptkriterier:** Skemaet i `LYTTESKEMA.md` er udfyldt af brugeren for hver ny stemme.

#### AP-12 Hvorfor er Piper uforståelig?

**Hvorfor:** Brugeren kommenterede ikke Piper-lydprøven fra Python, men finder appens Piper
næsten uforståelig. Det kan være modellen – eller appens indstillinger.
**Gør:** Lav samme tekst med (a) Python-Piper fra `tools/stemmetest`, (b) appens `--synthesize`,
(c) appen ved hastighed 1,0 afspillet gennem `PCMPlayer` til en fil. Sammenlign samplerate,
lydstyrke, klipning (maks. amplitude), længde og `noise_scale`/`length_scale` mod modellens
`.onnx.json`. Tjek brugerens gemte hastighed i indstillingerne: Piper-hastighed over ca. 1,3
forringer udtalen. Afprøv `num_threads` 1 mod 2.
**Acceptkriterier:** En kort rapport i `TEKNISK-VURDERING.md` med enten en fundet og rettet
fejl og ny lyttepakke til brugeren, eller konklusionen "modellen er grænsen".
**Stop:** Brug højst én arbejdsdag. Piper er ikke målet, hvis fejlen ligger i modellen.

#### AP-13 Cloud-stemme: Azure

**Forudsætning:** Brugeren har bekræftet B6 og oprettet en Azure Speech-ressource i en EU-region.
**Hvorfor:** Azure har danske neurale stemmer af den regelbaserede type til ca. en femtedel af
ElevenLabs' pris, med gratis kvote. Det er den hurtigste vej til en væsentlig bedre stemme.
**Gør:** `AzureBackend: SynthesisBackend` med `requiresNetwork = true`. Nøglen gemmes i macOS
Keychain, aldrig i UserDefaults eller filer. Indstillingsside "Cloud-stemmer" med: forklaring af,
at markeret tekst sendes til Microsoft; en kontakt, der er slået fra som standard; nøglefelt;
region. Cloud-stemmer mærkes med et sky-ikon i afspilleren og stemmelisten. Ved netværksfejl
vises en besked – der skiftes **ikke** stille til en anden stemme midt i en tekst; brugeren
tilbydes at læse videre med den lokale stemme. Timeout 5 sekunder pr. sætning.
**Acceptkriterier:** Uden nøgle eller med kontakten slået fra sker der ingen netværkskald
(test med en falsk `URLProtocol`). Stemmetest og lyttepakke er lavet. Tid til første lyd er målt
og skrevet ned. Loggen indeholder ingen tekst og ingen nøgle.
**Stop og spørg:** Opret ikke selv en konto, og indtast ikke selv en nøgle. Brugeren gør begge dele.

#### AP-14 Cloud-stemme: ElevenLabs

**Forudsætning:** AP-13 er færdig; brugeren ønsker det og har en nøgle.
**Gør:** Som AP-13, som `ElevenLabsBackend`. Mål både Flash- og den bedste flersprogede model.
Afklar og dokumentér dataopbevaring og GDPR-vilkår ud fra ElevenLabs' egne sider.
**Acceptkriterier:** Som AP-13, plus en anslået månedspris ved 30 og 120 minutters daglig brug
ud fra de faktiske priser på måletidspunktet.

#### AP-15 Plapre: afprøv originalmodellen

**Hvorfor:** Plapres egen dokumentation angiver 1,67 % tegnfejl; vi målte 10–23 % med en
tredjeparts ONNX-konvertering. Brugeren kunne lide stemmen. Hvis originalen er god, er Plapre
den bedste lokale kandidat (CC BY 4.0, ingen GPL).
**Forudsætning:** Brugeren accepterer vilkårene for `syvai/plapre-3` på Hugging Face og logger ind.
**Gør:** Kør originalen med `transformers` på CPU/MPS efter "manual path" i modelkortet (det
officielle bibliotek kræver CUDA). Kør de 36 sætninger gennem stemmetesten med Tor og med
`danorm.py` som tekstforberedelse. Sammenlign token for token med `plapre_lib.py` på samme
sætning og samme tilfældighedsfrø.
**Acceptkriterier:** Én af tre konklusioner med tal: (a) originalen gentager også → Plapre
opgives; (b) originalen er god → fejlen ligger i konverteringen, beskriv forskellen og lav en ny
konvertering eller en MLX-udgave; (c) kan ikke afgøres, og hvorfor.
**Kendt:** Vores afvikling er allerede kontrolleret for prompt, tokenisering, stemmedata og
KV-cache uden at finde fejl. Gentag ikke de kontroller.

#### AP-16 Røst 500m: kan den gøres hurtig nok?

**Hvorfor:** Det er den stemme, brugeren bedst kan lide. Med PyTorch er den 2–7× for langsom.
**Gør:** Undersøg i denne rækkefølge, og stop ved første, der virker: (1) findes der en
MLX-udgave af Chatterbox Multilingual, der kan indlæse Røsts vægte? (2) hvor bruges tiden –
sprogmodellen eller lyddekoderen – og kan dekoderens antal trin sænkes? (3) kvantisering.
Mål hastighedsfaktor og tid til første sætning på M3. Mål oplæsningsfejl med stemmetesten.
**Acceptkriterier:** Hastighedsfaktor under 0,7 **og** første sætning klar inden 1,5 s, ellers
opgives sporet med tallene dokumenteret. Licensen (OpenRAIL) og brugen af indtalernes stemmer er
afklaret skriftligt med Alexandra Instituttet, før stemmen kan komme i et udgivet produkt.
**Stop:** Brug højst tre arbejdsdage.

#### AP-19 Stemmeport: vælg hovedstemme

**Gør:** Saml resultaterne fra AP-11 til AP-16 i én tabel. Anvend porten i afsnit 7. Brugeren
vælger. Opdatér B7, sæt `isApprovedDefault` for den valgte stemme, og fjern eller mærk resten.
**Hvis ingen stemme består:** Apple forbliver standard, den bedste cloud-stemme tilbydes som
tilvalg, og arkitekten beskriver et nyt spor (fx træning af en egen regelbaseret stemme på det
frie CoRal-tts-datasæt).

### Fase 2 – Læseoplevelsen

#### AP-20 Afspilleren: afprøvning og rettelser

**Gør:** Lav en testvejledning på ti punkter til brugeren (pause, fortsæt, stop, start forfra,
hastighed op/ned, sprogskift, luk, flyt og genstart appen – står afspilleren samme sted?).
Ret det, brugeren finder. Kendt: ved hastighedsskift med en `SynthesisBackend` læses den
aktuelle sætning forfra; erstat det med `AVAudioUnitTimePitch` i `PCMPlayer`, så hastigheden
ændres uden gentagelse.
**Acceptkriterier:** Brugeren har gennemført vejledningen uden fejl for både Apple og en
backend-stemme.

#### AP-21 Lange tekster og programskift

**Gør:** Test med en tekst på 20.000 tegn: hukommelse før, under og efter; at luk frigiver
teksten; at et nyt tryk på genvejen midt i teksten skifter rent. Sæt en øvre grænse for
tekstlængde (forslag: 200.000 tegn) med en venlig besked. Backends må højst syntetisere to
sætninger forud for afspilningen, så hukommelse og cloud-forbrug ikke løber løbsk ved stop.
**Acceptkriterier:** Hukommelsen efter luk er inden for 10 MB af før start. Tests for grænsen
og for "højst to sætninger forud".

#### AP-22 Tekstforberedelse, runde 2

**Gør:** Udvid `sentences.py` med mindst 40 nye tilfælde fra rigtige tekster: telefonnumre,
CPR-lignende numre (læses ciffer for ciffer), procent med komma, intervaller ("10-15"),
ordenstal uden måned, romertal i navne, URL'er og mailadresser, "kl. 9" uden minutter, valutaer
(EUR, USD, DKK), "nr. 5", paragraffer, brøker, årstal uden kontekstord. Ret `DanishTextNormalizer`.
Ret den kendte fejl, hvor "den" forsvinder efter et helt klokkeslæt ("klokken ni den tredje maj").
Hold `danorm.py` og Swift-udgaven ens, eller fjern Python-udgaven og lad stemmetesten kalde
appens `--normalize`.
**Acceptkriterier:** Alle gamle og nye tilfælde består i Swift-testen. Ingen forberedelse af
engelsk tekst.
**Kerne:** Ja – `DanishTextNormalizer.swift` ligger i kernen. Begrund i `KERNEAENDRINGER.md`;
kontrakt K7 udvides med de nye tilfælde, ingen gamle tilfælde må ændres.
**Stop og spørg:** Hvis en regel kræver, at man kender ordets køn eller betydning, så vælg den
mest almindelige form og notér det – byg ikke en ordbog.

#### AP-23 Kernen som eget kompileringsmål

**Hvorfor:** I dag holdes kernen adskilt af mapper og `check.sh`. Hvis kernen bliver sit eget
SwiftPM-mål (`BaymowCore`), kan compileren selv afvise, at kernen kommer til at afhænge af
motorer, brugerflade eller funktioner.
**Gør:** Opret målet `BaymowCore` med indholdet af `Core/`. `BaymowKit` afhænger af det.
Gør de typer `public`, som resten bruger. `CoreContractTests` flyttes til et testmål, der kun
afhænger af `BaymowCore`. Opdatér stierne i `check.sh`, `KERNEAENDRINGER.md` og denne plan.
**Kerne:** Ja – flytning uden adfærdsændring. Ingen kontrakt-test må ændres i indhold.
**Acceptkriterier:** `BaymowCore` bygger alene (`swift build --target BaymowCore`). En prøve, hvor
en kernefil importerer en type fra `Engines/`, giver en kompileringsfejl. `check.sh` er grøn.

#### AP-24 Engelske ord i dansk tekst

**Hvorfor:** Dansk tekst er fuld af engelske navne og fagord. Både Piper og Apple læser dem forkert
("Chrome" → "krume", "cloud-valg" → "kludval"), og tegnfejlen tredobles på den slags tekst. Det var
sådan tekst, brugeren hørte, da Piper blev dømt "næsten uforståelig".
**Gør:** Vent til hovedstemmen er valgt (AP-19) – løsningen afhænger af motoren. Mål først den valgte
stemme på et nyt sæt med 30 sætninger med engelske ord (`tools/stemmetest/sentences_engelsk.py`).
Vælg derefter den enkleste løsning, der virker: (1) en lille udtaleliste for de 200 mest almindelige
engelske ord i dansk tekst, omskrevet til dansk lydskrift før motoren; eller (2) motorens egne
udtalemærker (SSML/fonemer), hvis den har dem. Byg ikke automatisk sprogskift pr. ord.
**Kerne:** Ja, hvis løsningen lægges i `DanishTextNormalizer`. Begrund i `KERNEAENDRINGER.md`.
**Acceptkriterier:** Tegnfejlen på det engelske sæt er mindst halveret, og de 36 danske sætninger
er uændrede.

### Fase 3 – Tekstindfangning

Fælles for fasen: **Kerne:** Ja – `TextCaptureService.swift` ligger i kernen; begrund hver ændring i
`KERNEAENDRINGER.md`. Løsningen skal være generel. Ingen kode pr. hjemmeside, og så lidt kode pr.
program som muligt. Brug `--ax-diagnose` til at se, hvad programmet udstiller, før du ændrer noget.
Hvert program afsluttes med en række i testmatrixen i `TEKNISK-VURDERING.md`: program, version,
metode, tid, resultat, begrænsninger.

#### AP-30 Chrome

**Kendt:** Chrome udstillede intet webområde og afviste `AXManualAccessibility` og
`AXEnhancedUserInterface`, men Chrome var ikke forrest under forsøget. Fallbacken (⌘C) forventes
at virke, men er ikke afprøvet.
**Gør:** Afprøv med Chrome forrest. Hvis Accessibility kan slås til: mål, om det gør Chrome
langsommere, og slå det kun til, hvis det er uden mærkbare bivirkninger. Ellers accepter ⌘C og
gør den hurtigere: ventetiden på, at genvejens taster slippes, er hovedparten af dens 300–550 ms.
**Acceptkriterier:** Markeret tekst læses i Chrome på en almindelig artikel, i et tekstfelt og i
en PDF vist i Chrome. Udklipsholderens tidligere indhold er uændret bagefter (test med tekst og
med et billede i udklipsholderen).

#### AP-31 Word og Preview/PDF

**Acceptkriterier:** Markeret tekst læses i et Word-dokument, i en tekstbaseret PDF i Preview
og giver en forståelig besked i en indscannet PDF uden tekstlag. Linjeskift og orddeling fra
PDF'er giver ikke pauser midt i sætninger (saml linjer, fjern bindestreg ved linjeskift).

#### AP-32 Google Docs og testmatrix

**Acceptkriterier:** Google Docs virker i Safari og Chrome, eller begrænsningen er dokumenteret.
Matrixen dækker også Mail, Noter, Slack, VS Code og Outlook.

### Fase 4 – Stemmebibliotek og opsætning

#### AP-40 Stemmebibliotek færdigt

**Gør:** Stemmebiblioteket viser for hver stemme: sprog, type (system / hentet / cloud), størrelse,
"Prøv", "Vælg som standard", og "Hent"/"Fjern" hvor det giver mening. Afbrudt download kan
gentages og efterlader ingen halve filer. Diskplads kontrolleres før download.
**Acceptkriterier:** Tests for afbrudt download, forkert kontrolsum og manglende diskplads.

#### AP-41 Førstegangsopsætning

**Gør:** Tre trin ved første start: (1) giv Tilgængelighed-adgang, med knap og automatisk
registrering af, at det er sket; (2) vælg stemme og hør en prøve; (3) prøv genvejen på en
indbygget eksempeltekst. Ingen tekniske ord.
**Acceptkriterier:** En person, der ikke har set appen før, kommer fra første start til første
oplæsning uden hjælp. Brugeren finder testpersonen.

### Fase 5 – Udgivelse

#### AP-50 Licensoprydning

**Gør:** Når B7 og B8 er afgjort: fjern alle motorer og biblioteker, der ikke bruges. Hvis
appen skal være lukket, og espeak-ng stadig er nødvendig, så flyt den til et separat
hjælpeprogram – først efter en juridisk vurdering, som brugeren indhenter. Lav
`docs/LICENSER.md` og en "Om"-side med kreditering af alle modeller og biblioteker.
**Acceptkriterier:** `nm` på den færdige binære fil viser ingen espeak-symboler, hvis appen er lukket.

#### AP-51 Stabilitet, hukommelse og privatlivskontrol

**Gør:** Otte timers kørsel med en oplæsning hvert femte minut. Kontrollér, at loggen aldrig
indeholder tekst (søg efter ord fra testteksterne), at ingen fil under
`~/Library/Application Support/Baymow` eller `~/Library/Caches` indeholder tekst, og at appen
uden cloud-tilvalg ikke åbner netværksforbindelser (mål med `nettop` eller en proxy).
**Acceptkriterier:** Ingen crash, hukommelsen vokser under 20 MB, de tre kontroller er rene.

#### AP-52 Developer ID, notarisering og DMG

**Forudsætning:** B9 er afgjort; brugeren har et Developer ID-certifikat.
**Gør:** Hardened runtime, signering af alle indlejrede binære filer, notarisering, DMG.
Test installation på en Mac, der aldrig har set appen, herunder at Tilgængelighed-tilladelsen
overlever en opdatering.

---

### Fase 6 – Efter MVP: idékatalog

Ikke arbejdspakker endnu. Idéerne er samlet 17. november 2026, inspireret af Speechify, som brugeren ser op
til. Speechify er en cloud-tjeneste med abonnement; Baymows forskel er, at alt sker lokalt, privat, på dansk
og som åben kildekode. En idé bliver først en arbejdspakke, når MVP'en er færdig, og brugeren har valgt den.
Rækkefølgen er arkitektens bud på nytten for en ordblind bruger.

| # | Idé | Værdi for brugeren | Hvor den bygges | Rører kernen? |
|---|---|---|---|---|
| I1 | **Ordfremhævning:** et læsevindue, der viser teksten og fremhæver ordet, der læses | Følge med i teksten, mens den læses – Speechifys kernefunktion | `Features/Highlighting/`, observerer sessionens position. Apple giver ordposition; backends kun sætningsposition | Ja: sessionen skal kunne udlevere teksten til visning (ny, udtrykkelig metode). Kræver arkitektens ja |
| I2 | **Spring en sætning frem eller tilbage** (knapper og genveje) | Høre en sætning igen uden at starte forfra | `ReadingSessionManager` (bidderne findes allerede) + knapper i afspilleren | Ja: udvider K2 |
| I3 | **Højere hastighed**, op til 3–4× | Erfarne lyttere læser hurtigere end de læser selv; Speechify går til 4,5× | Grænsen i `SettingsStore`/sessionen; tjek, at stemmerne kan følge med | Ja: ændrer K5 (0,5–2,0) |
| I4 | **Læs tekst fra skærmen** (OCR med Apples Vision, lokalt) | Billeder, indscannede PDF'er og programmer uden markerbar tekst | Ny strategi i `TextCaptureService`, eller egen genvej i `Features/ScreenText/` | Ja, hvis den lægges i `TextCaptureService` |
| I5 | **Læs en hel fil** (PDF, Word, EPUB) via træk-og-slip på afspilleren | Lange dokumenter uden at markere | `Features/Documents/`, giver teksten til `ReadingSessionManager.start` | Nej |
| I6 | **Gem oplæsning som lydfil** | Lytte på farten, uden computeren | `Features/Export/`, syntetiserer til fil (kun efter brugerens tryk) | Nej |
| I7 | **Diktering** (tale til tekst) | Skrivehjælp – Speechifys nyeste Mac-funktion | Eget modul; macOS har allerede indbygget diktering, så værdien skal afklares først | Nej |
| I8 | **Opsummering og spørgsmål til teksten** | Overblik over lange tekster | Kræver en sprogmodel: lokal, eller cloud (udskudt, B6) | Ja – kræver arkitektens ja og en privatlivsvurdering |

Fælles for alle: slået fra som standard eller uden virkning, før brugeren tager dem i brug; de må ikke gøre
genvejen langsommere; og kernekontrakten skal bestå uændret, medmindre idéen udtrykkeligt ændrer den.

## 7. Stemmeporten

En stemme kan først blive standardstemme, når den består punkt 1–5. Punkt 6 måles og vejes med i valget. Punkt 1–3 måles af
en udfører; punkt 4 er brugerens; punkt 5 er arkitektens.

| # | Krav | Måles med | Grænse |
|---|---|---|---|
| 1 | Siger det, der står | `Scripts/test-voice.sh`, tre kørsler | Højst 3,5 % tegnfejl i gennemsnit, og ingen sætning med gentagne eller manglende ordgrupper |
| 2 | Hurtig start | `--measure-latency` + loggens `speechStarted` | Første lyd inden 1,0 s for en kort sætning; 1,5 s for en cloud-stemme |
| 3 | Holder trit | Stemmetestens tidsmåling | Hastighedsfaktor under 0,7 på M3 |
| 4 | Til at forstå og rar at høre på | `docs/LYTTESKEMA.md` | Brugeren giver mindst 4 af 5 for forståelighed og mindst 3 for naturlighed |
| 5 | Kan udgives | Licens- og vilkårsgennemgang | Forenelig med B8; for cloud: databehandling afklaret |
| 6 | Klarer engelske ord i dansk tekst | `Scripts/test-voice.sh … --set engelsk` + brugerens lytning | Ikke et krav endnu, men måles og oplyses for hver kandidat. Reference: Apple Sara 17–18 af 30 |

Grænsen i punkt 1 blev ændret fra 2,5 % til 3,5 % den 16. november 2026. Talegenkendelsen bidrager
selv med 2–3 % fejl, og målingen svinger ca. ±0,4 procentpoint fra kørsel til kørsel. Referencen
Apple Sara måler 2,7 %, Piper 2,3–2,7 %, mens stemmer, der digter ord, måler 10–23 %. Grænsen skiller
dermed de to slags ad uden at afvise en stemme på grund af målestøj. En ny stemme, der er klart
dårligere end referencen på punkt 1, er ikke et fremskridt, uanset hvor godt den lyder.

---

## 8. Risici

| Risiko | Konsekvens | Modtræk |
|---|---|---|
| Ingen lokal dansk stemme består porten | MVP'en må bruge Apple lokalt og cloud som tilvalg | Fase 1 afprøver cloud tidligt (AP-13), så der er en god stemme uanset |
| Cloud strider mod privatlivsløftet | Tab af tillid | B6: kun som tydeligt tilvalg, mærket i brugerfladen, ingen stille fallback |
| Sprogmodel-stemmer digter ord | Brugeren får forkert indhold læst op | Stemmeportens punkt 1; regelbaserede stemmer foretrækkes ved ligestilling |
| GPL binder hele appen | Lukket distribution umulig | B8 holdes åben; Piper isoleres bag `SynthesisBackend` (AP-10); AP-50 |
| Accessibility virker forskelligt pr. program | Genvejen "virker ikke" for brugeren | ⌘C-fallback, testmatrix, forståelige beskeder |
| En ny funktion ændrer MVP'ens adfærd ved et uheld | Genvejen eller oplæsningen holder op med at virke | Kernekontrakten (K1–K10), `check.sh`, B10: funktioner bygges uden om kernen og er slået fra som standard |
| En udfører mister overblikket eller løser mere end pakken | Halve ændringer på tværs af projektet | Én pakke ad gangen, regel 7, afleveringsskabelon, `STATUS.md` |
| Udførere erklærer noget færdigt uden at have målt | Fejl opdages af en ordblind bruger | Definition af færdig; stemmetest og lytteskema; arkitekten gennemgår porte |

---

## 9. Ordliste

| Ord | Betydning |
|---|---|
| Tekstforberedelse | Omskrivning af tekst til den form, den siges i ("kl. 14.30" → "klokken fjorten tredive") |
| Stemmetest | De 36 sætninger læst af en stemme og kontrolleret med talegenkendelse (`tools/stemmetest`) |
| Tegnfejl | Andel af tegn, der afviger mellem det sagte og det forventede, uden mellemrum |
| Hastighedsfaktor | Syntesetid divideret med lydens længde; under 1 er hurtigere end afspilning |
| Regelbaseret stemme | Stemme, der omsætter tekst til lyde efter faste regler (Apple, Piper) og ikke kan digte ord. Azures almindelige neurale stemmer forventes at høre til her; det skal måles i AP-13 |
| Sprogmodel-stemme | Stemme, der genererer lyd ord for ord som en sprogmodel (Plapre, Røst) og kan gentage eller udelade ord. ElevenLabs forventes at høre til her; det skal måles i AP-14 |
| Backend | En `SynthesisBackend`: kode, der laver lyd af tekst uden selv at afspille den |
| Port | Et punkt, hvor arbejdet stopper, indtil målinger og brugerens dom foreligger |
