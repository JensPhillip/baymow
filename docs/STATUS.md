# Status

Opdateres af den, der sidst har arbejdet på projektet. Kort og faktuelt.
Sidst opdateret: 2026-11-25 af udfører (Claude Opus 5.5).

## Lige nu

- **AP-72 og AP-73 afprøvet og godkendt af brugeren 24. november** (én gang hilsen over signaturen). Valgfelter som "[passer / passer ikke]" vises nu som knapper i
  mail-svarets vindue; et tryk erstatter feltet i mailen, kun hvis det står uændret (ellers kopieres valget). Brugerens afprøvning samme dag: modellen gættede "13:00 works well" i stedet for
  at give valg; instruktionen kræver nu valg, når personen selv skal sige ja eller nej. Mail-testen (10 tråde): 10 af 10
  i fem kørsler. Afprøvet og godkendt af brugeren 25. november. AP-76 (oprydning 24. november): beskeden ved ingen
  markering nævner "Tekst fra skærmen" (kerneændring), testnøglerne i `baymow-test` er slettet, Outlook og Gmail parkeret som I17. – bygget, afventer brugerens afprøvning. AP-71 er afprøvet af brugeren.
- **AP-77 (knapbjælke, brugerens idé 25. november):** knapper på skærmen som alternativ til genvejene (genvejene bliver),
  valg i velkomsten (knapper / taster / begge). Skitser af fire varianter (altid synlig, prik, logo ved mus, kant) og
  velkomsttrinnet. Brugeren valgte C (logo, der folder sig ud ved musen) som standard, to valg i velkomsten (med eller
  uden knapper; tasterne virker altid) og en knap på Start til siden Knapper. Bygget samme dag: siden Knapper (fire
  måder, hvilke knapper, tasterne kan slås fra, når knapperne er til). Slået fra som standard. Rettet efter brugerens afprøvning samme dag: bjælkens vindue
  var 0 × 0 (usynligt) – nu målt i en test; kontakten "Brug tasterne" står også øverst på siden Genveje. Brugerens ønske samme dag: bløde
  overgange (knapperne glider og toner ind), logoet flytter sig ikke, når bjælken åbner (indholdet er hæftet til logoets
  hjørne; kontrolleret på skærmbilleder i begge størrelser), og forklaringen er lille, kommer efter 3 sekunder og har sin
  egen plads. Derefter: roligere animation uden fjeder, vinduets nye størrelse animeres ikke (logoet
  gled), fanen i kanten bliver stående med knapperne ud ved siden af, mindre skygger. Derefter: knapperne i tre
  størrelser og tekst under dem til/fra (med forhåndsvisning); Genveje skjuler tasterne, når de er slået fra; Start følger
  opsætningen (vejledning til den valgte knapvariant, knap og/eller taster i hvert trin, sparring med). Afventer afprøvning.
- **Mail – plan aftalt 23. november:** 1) sparring på den åbne mail (færdig), 2) Outlook og Gmail – parkeret af brugeren 24. november (I17; nævnes kun ved forslag til forbedringer), 3) senere: proaktiv hjælp med
  app på telefonen, brugerens kontekst og opklarende spørgsmål (I16), og login på kontoen. Proaktiv del venter, til
  mail-svar og sparring virker godt.
- **Mail-svar (I15):** Brugerens svar 23. november: hele tråden som kontekst, udkast/stikord/intet, direkte ind i mailprogrammet, defineret menneskelig og formel tone, alle programmer (først Apple Mail). AP-64 (internet-hjælpen) er godkendt.
- **Færdige pakker:** AP-00, AP-01, AP-02, AP-10, AP-11, AP-12, AP-19 (hovedstemme: Apple Sara (Enhanced)),
  AP-20, AP-21, AP-22, AP-23, AP-30, AP-31, AP-32, AP-40, AP-50, AP-51, AP-60, AP-61, AP-62.
- **Lukket/droppet af brugeren 22. november:** AP-03 (lytteskemaet), AP-15 (Plapre).
- **Venter på brugeren:** afprøvning af AP-70 og AP-76, AP-41 (testperson – udskudt af brugeren 2026-11-18).
- **Delvist:** AP-24 – udtalelister pr. motor er bygget, men gav kun lidt (Piper 14 → 18 af 30, Apple uændret).
- **Parkeret eller udskudt:** AP-13/14 (cloud-stemmer, B6), AP-16 (Røst – hovedstemmen er valgt).
- **Beslutninger:** B6 cloud udskudt · B7 Sara (Enhanced) · B8 GPL-3.0-or-later · B9 Baymow, app-id
  `dk.jpmag.baymow` (21. november; Tilgængelighed givet igen og genvejen bekræftet af brugeren).
- **Kodearkiv:** https://github.com/JensPhillip/baymow (offentligt). Push kun det, der er committet og grønt.
- **AP-52 forberedt:** DMG (`Scripts/make-dmg.sh`) og README. Udgivelse afventer brugerens app-id, Developer ID og kodearkiv.
- **AP-60 færdig (idé I1, ordfremhævning):** tekstvindue og/eller gult felt direkte i teksten, hver sin kontakt i
  "Visning", slået fra som standard. I teksten virker i Noter, TextEdit, Safari og Mail; ikke i Chrome, Word og Claude.
- **AP-61 (idé I3, højere hastighed):** grænsen er 3× (var 2×). Saras tempo følger tallet (målt: 2× = 2,05×,
  3× = 2,98×). Talegenkendelse: 1× 1,7 %, 1,5× 3,5 %, 2× 7,2 % tegnfejl; over 2× kan den ikke følge med, brugeren har lyttet og godkendt 2,5× og 3×.
- **AP-62 (nyt design):** designprincipper i planens afsnit 3. Hovedvinduet har sidebjælke med fem sider, ikoner,
  flag og "Hør"-knapper; velkomsten er tegnet om. Afspilleren er igen lille (én række), efter brugerens ønske.
  Nedbrud ved genvejen (ordkoblingen, fra AP-60) rettet 21. november. Godkendt af brugeren. Skærmbilleder: `Baymow --render-ui <mappe>`.
- **MVP'en er færdig og afprøvet af brugeren** (22. november: afspilleren, Google Docs i Safari/Chrome, Outlook,
  PDF og tekstfelter i Chrome, udklipsholderen, "Hør"-knapperne). Slack er ikke prøvet.
- **AP-63 (idé I12, stavehjælp):** ⌃⌥R på egen markeret tekst. Macens indbyggede sprogmodel + en vagt, der kun lader
  små rettelser igennem; usikre ord markeres "tjek selv". Slået fra som standard (siden "Stavning"). Stavetest
  (`tools/stavetest/`): kontrolsæt 0 forkerte rettelser, 13 af 14 fejl rettet eller markeret, 0,5 s pr. sætning.
  Kernen: `GlobalShortcutManager` kan nu have flere genveje (`--hotkey-selftest`).
- **AP-64 (stavehjælp via internet):** tilvalg på siden "Stavning": Claude (Sonnet 5.5) eller ChatGPT (GPT-6 Luna)
  med brugerens egen nøgle i nøgleringen. Gennem vagten: 63 og 62 af 63 fejl, 0 forkerte rettelser (Macens: 46).
  Uden internet eller med en nøgle, der ikke virker: Macens egen hjælp, og vinduet siger det. Netværkslisten har en ny fil.
- **AP-65 (forbrug):** afsnittet "Forbrug" på siden Stavning: kontroller og skønnet pris pr. firma og måned
  (priser tjekket 23. november: GPT-6 Luna $0,10/$0,50, Sonnet 5.5 $2/$10; kurs 6,45 kr.). ChatGPT er standard.
  Idéer til senere: I13 rigtige priser hentet hos firmaerne, I14 fælles nøgle mod betaling for ikke-tekniske brugere.
- **AP-66 (forbrug over tid):** pris med 4 decimaler; "Vis graf over tid" (lukket som standard) med søjler pr. dag i
  30 dage og tal ved musen. Forbruget gemmes nu også pr. dag; dage før 23. november findes kun som månedstal.
- **AP-67 (genveje og Stop):** begge genveje kan skiftes på siden Genvej (stavegenvejen er nu en indstilling og vises
  ens alle steder); Start viser stavning, når den er slået til; alle "Hør"-knapper bliver til "Stop" under oplæsning.
- **AP-68 (hvor meget Baymow retter):** kun stavning / stavning og tegnsætning (standard) / også klarere sætninger
  (kun via internet). ChatGPT: tegnfejl rettet i 45 af 47 sætninger, Macens model 21 af 21 i tegnsætningstesten.
  "Brug rettelsen" bevarer formateringen (RTF/HTML), når den kan; ellers ren tekst som før.
- **AP-69 (Word):** rettelserne sættes direkte ind i programmets egen RTF, så Word beholder skrifttype og størrelse.
  HTML (Google Docs, Chrome) går stadig gennem macOS; virker skrifttypen forkert dér, er det samme rettelse for HTML.
- **AP-71 (mail-svar, Apple Mail):** stikord øverst i svaret + ⌃⌥M → ChatGPT skriver svaret, der erstatter stikordene;
  signatur og tråd står urørt. [Felter] for det ukendte. Mail-testen: 18 af 18 svar uden problemer (6 tråde × 3).
  Siden "Mail", slået fra som standard. Outlook og Gmail er ikke prøvet.
- **AP-72:** mail-svar kender brugerens navn (opfølgning på egen mail), viser antagelser og skriver aldrig hilsen/navn
  over den faste signatur. Ny side "AI og nøgler": begge nøgler, firma pr. funktion, forbrug pr. funktion med graf.
  Mail-testen: 8 af 8 i tre kørsler.
- **AP-73 (sidebjælken):** øverst Start, Oplæsning, Visning, Stavning, Mail; fast nederst "Indstillinger" med Genveje,
  Stemmer og AI og nøgler (vælger øverst på siden). Start linker til Genveje, Oplæsning til Stemmer.
  Rettet 23. november efter brugerens ønske: "Skift genveje" er en selvstændig knap nederst på Start; "Farverne" står
  lige under "Sådan gør du" på Stavning; overskriften ved fanerne i Indstillinger er fjernet.
- **AP-74 (sparring om mailen):** ⌃⌥K på en åben mail i Apple Mail → vindue med fire faste spørgsmål og eget
  spørgsmål. Sparringstesten: 40 af 40 svar (højst 68 ord, "Det står ikke i mailen" til det ukendte).
  Afprøvet af brugeren 24. november ("virker rigtig fint"); svarene vises nu formateret (fed, punkter).
- **AP-75 (tekst fra skærmen, I4):** ⌃⌥T → træk en firkant → Macens tekstgenkendelse → oplæsning. Målt på egne
  danske tekster: 0 % tegnfejl i fem udgaver af skærmtekst, 1,1 % på "indscannet" (efter æ/ø/å-rettelse; før 1,9 %).
  Kræver tilladelsen Skærmoptagelse og macOS 15.2. Intet netværk.
  Afprøvet af brugeren 24. november ("det virker"). Rettet samme dag: "Giv lov" sætter nu Baymow på listen over
  Skærmoptagelse, og firkanten og sparringsvinduet trækker ikke længere hovedvinduet frem.

## Venter på brugeren

Brugerens samlede tjekliste i almindeligt sprog: `docs/TJEKLISTE.md` (opdatér den, når noget bliver afklaret).

| Hvad | Hvorfor | Blokerer |
|---|---|---|
| Prøv stavehjælpen (⌃⌥R) i et par programmer, og godkend vinduet | Udseende, lyd og indsætning kan kun prøves af brugeren | AP-63 |
| Se afsnittet "Forbrug" på siden Stavning efter et par kontroller | Kun brugeren kan se, om tallene giver mening | AP-65 |
| Find en testperson til førstegangsopsætningen (udskudt af brugeren 2026-11-18) | Kun et nyt menneske kan vise, om den er til at forstå | AP-41 |
| Meld dig ind i Apple Developer Program (Developer ID og notarisering) | Udgivelse til andre kræver det | AP-52 |

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
- Slack (brugeren: antages at virke).

## Kendte fælder

- Kernen ligger i `Sources/BaymowCore/` (ikke længere `Sources/BaymowKit/Core/`). Ældre afleveringer bruger de gamle stier.
- Selvtests, der skal køre som rigtig app, startes med `./Scripts/run-selftest.sh` (tidsgrænse, aldrig efter fejlet bygning).
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
