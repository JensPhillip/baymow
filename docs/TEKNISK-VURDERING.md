# Baymow – teknisk vurdering og udviklingsplan

Appen hedder **Baymow** (tidligere arbejdstitel: Oplæser). Bundle-id `dk.baymow.app` er en pladsholder.

Dette dokument er projektets logbog over målinger og fund. Den gældende plan står i `PROJEKTPLAN.md`;
udviklingsplanen i afsnit 4 her er historisk.

Status pr. 16. november 2026: prototypen til milepæl 1 er bygget, og dens logik er dækket af
automatiske tests. Tekstindfangning fra andre programmer er **ikke afprøvet endnu**, fordi det
kræver, at Tilgængelighed-tilladelsen gives manuelt på maskinen. Se "Sådan tester du milepæl 1".

## 1. Afklaringer

Ingen uklarheder blokerer milepæl 1–3. Tre punkter kræver en beslutning inden milepæl 4:

1. **Download af stemmer.** Apples systemstemmer kan ikke hentes eller slettes af en
   tredjepartsapp – kun af brugeren selv i Systemindstillinger. Kravet om, at stemmebiblioteket
   selv downloader, verificerer og sletter stemmer, kan derfor kun opfyldes med en ekstra,
   medleveret TTS-motor (se afsnit 3). Indtil da viser biblioteket de installerede systemstemmer
   og forklarer, hvor bedre stemmer hentes.
2. **Dansk stemmekvalitet.** På testmaskinen findes kun den kompakte "Sara". Om den er god nok
   til målgruppen, er en produktbeslutning, der bør træffes ved at lytte – ikke ved at læse om det.
3. **Licens til neurale stemmer.** De realistiske danske alternativer har uafklarede eller
   besværlige vilkår (afsnit 3). Skal appen på sigt sælges som lukket kildekode, bør valget
   vurderes juridisk, før der bygges på det.

Valg truffet uden at spørge, fordi de er nemme at ændre: standardgenvej ⌃⌥S, minimum macOS 14,
brugerflade kun på dansk, hastighed 0,5×–2,0× i trin på 0,1.

## 2. Arkitektur

Én Swift-pakke med et bibliotek (`BaymowKit`) og en tynd eksekverbar fil. Ingen eksterne
afhængigheder.

| Ansvar | Fil | Bemærkning |
|---|---|---|
| AppShell | `AppShell.swift`, `MainWindow.swift` | AppKit-livscyklus, menulinje, SwiftUI-hovedvindue |
| GlobalShortcutManager | `GlobalShortcutManager.swift` | Carbon-hotkey; kræver ingen tilladelse |
| TextCaptureService | `TextCaptureService.swift` | Accessibility først, udklipsholder som fallback |
| LanguageDetectionService | `LanguageDetectionService.swift` | `NLLanguageRecognizer` begrænset til understøttede sprog; indeholder også opdeling i sætningsbidder |
| ReadingSessionManager | `ReadingSessionManager.swift` | Én session ad gangen, tekst kun i hukommelsen |
| SpeechEngine | `SpeechEngine.swift` | Protokol + `AppleSpeechEngine` |
| VoiceManager / VoiceCatalog | `VoiceCatalog.swift` | Samler stemmer på tværs af motorer |
| FloatingPlayer | `FloatingPlayer.swift` | Ikke-aktiverende panel + diskrete beskeder |
| SettingsStore | `SettingsStore.swift` | UserDefaults |
| DiagnosticsService | `DiagnosticsService.swift` | JSON-linjer i `~/Library/Logs/Baymow/` |
| ModelDownloader | – | Bygges først, når der er en motor med egne modeller (milepæl 4) |

Tre designvalg, der bærer de fremtidige udvidelser:

- **Teksten læses i sætningsbidder.** Sessionen ved hele tiden, hvilket ord der læses. Det giver
  hastigheds- og sprogskift midt i en tekst nu, og er grundlaget for ordfremhævning, sprogskift
  undervejs og neurale motorer, der skal kunne starte, før hele teksten er syntetiseret.
- **Motoren må ikke sende events efter stop.** Den regel står i protokollen og er testet; det er
  den, der forhindrer overlap, når en ny oplæsning erstatter en gammel.
- **Fejlloggen har ingen fritekst-parameter.** Den tager kun faste hændelsestyper, bundle-id og
  et tal, så markeret tekst ikke kan havne i loggen ved en programmeringsfejl.

Appen er ikke sandboxet. Det er en forudsætning for at læse markeret tekst i andre programmer og
er foreneligt med den planlagte distribution (signeret og notariseret DMG uden for App Store).

## 3. Tekniske risici

### Tekstindfangning

| Trin | Metode | Forventet dækning |
|---|---|---|
| 1 | `AXSelectedText` på det fokuserede element | Native programmer, Safari, Word, de fleste tekstfelter |
| 2 | `AXSelectedTextMarkerRange` → `AXStringForTextMarkerRange` | WebKit-indhold, hvor trin 1 er tomt |
| 3 | Simuleret ⌘C med gendannelse af udklipsholderen | Chrome uden aktivt tilgængelighedstræ, Google Docs, Preview-PDF'er |

Fund fra første afprøvning (16. november 2026), målt med `--ax-diagnose`:

- **Safari** melder ikke altid et fokuseret element, og sidens webområde har ikke
  `AXSelectedText`. Markeringen kan derimod læses med tekstmarkører direkte på webområdet.
  Indfangningen søger derfor nu efter webområder i det forreste vindue (ca. 20 ms), hvis det
  fokuserede element ikke giver noget. Første afprøvning brugte fallbacken og tog 546 ms til
  indfanget tekst; rettelsen er endnu ikke bekræftet med en ny måling.
- **Chrome** udstillede intet webområde i forsøgene og afviste både `AXManualAccessibility` og
  `AXEnhancedUserInterface`. Chrome var ikke forrest under forsøgene, så det er ikke afgjort, om
  Accessibility kan bruges. Indtil videre hentes tekst i Chrome via fallbacken.
- **Electron-programmer** bygger først deres tilgængelighedstræ efter første forespørgsel:
  første oplæsning brugte fallbacken (371 ms), den næste Accessibility (10 ms).

Kendte begrænsninger ved fallbacken (trin 3):

- Den markerede tekst ligger i udklipsholderen i op til et halvt sekund. Et program, der gemmer
  udklipshistorik, kan nå at opfange den. Det er den eneste kendte vej, hvor tekst kan forlade
  appens hukommelse, og den bør nævnes i privatlivsteksten.
- Er intet markeret, giver nogle programmer en systemlyd ved ⌘C.
- Fallbacken venter på, at genvejens taster slippes, før ⌘C sendes. Det er hovedparten af dens
  300–550 ms.
- Programmer, der spærrer for kopiering (visse DRM-beskyttede PDF'er og e-bogslæsere), og
  indscannede PDF'er uden tekstlag kan ikke understøttes.

### Dansk offline-TTS

Beslutning 16. november 2026: Apples stemmer er ikke gode nok som hovedstemme og beholdes kun
som fallback. Fire alternativer er afprøvet på testmaskinen (M3 Pro) med samme danske tekst.
Lydprøverne ligger i `stemmeproever/`. Lydkvaliteten er ikke bedømt – det skal gøres ved at lytte.

| Fil | Model | Størrelse | Hastighed (syntesetid ÷ lydens længde) | Kort sætning klar efter | Licens |
|---|---|---|---|---|---|
| `1-apple-sara.wav` | Apple Sara (reference) | 0 | øjeblikkelig | ca. 10 ms | Systemstemme |
| `2-piper-talesyntese.wav` | Piper `da_DK-talesyntese-medium` | 63 MB | 0,02 (50× realtid) | 0,05 s | Data CC0 ifølge vedligeholderen, dog med forbehold om kilden. Kræver espeak-ng (GPL-3.0); nyere Piper er selv GPL-3.0 |
| `3-roest-v3-350m.wav` | Røst v3 350m (Alexandra Instituttet) | 4,0 GB | ca. 1,0 | 4,0 s | OpenRAIL |
| `4-roest-v3-500m.wav` | Røst v3 500m | flere GB | 2–6 | 6,6 s | OpenRAIL |
| `5-plapre3-ida.wav`, `5-plapre3-tor.wav` | Plapre 3 (syv.ai), ONNX | 1,9 GB | 0,63 | 2,0 s uden streaming; første sekunds lydtokens efter ca. 0,5 s | CC BY 4.0; dekoder MIT, vocoder Apache-2.0 |

Målingerne for Røst er med PyTorch på Apples GPU (MPS), for Plapre og Piper med ONNX Runtime på CPU.
Røst og Plapre er målt uden optimering; tallene er udgangspunkter, ikke grænser.

Brugerens bedømmelse efter lytning (16. november 2026): Røst v3 500m lyder bedst. Plapres
stemme Tor er god, men havde enkelte fejl og talte for langsomt. Opfølgende forsøg:

| Fil | Hvad er ændret | Resultat |
|---|---|---|
| `6-plapre3-tor-rolig.wav` | Temperatur sænket fra 0,7 til 0,4 for færre tilfældige valg | 26 s i stedet for 28,5 s; om fejlene er væk, skal høres |
| `6-plapre3-tor-rolig-tempo-1.25.wav` | Samme, afspillet 25 % hurtigere med `AVAudioUnitTimePitch` (uændret tonehøjde) | 21 s. Samme teknik kan drive appens hastighedsknap |
| `7-plapre3-med-roest-stemme.wav` | Plapre med en stemme udledt af Røst-prøven (stemmekloning ud fra 19 s lyd, tog 0,8 s) | 21,6 s – tempoet følger stemmen. Ligheden med Røst skal høres |

Røst 500m blev også målt på CPU i stedet for GPU: 4–7 gange langsommere end realtid, altså ikke
bedre. Med PyTorch kan den ikke bruges til direkte oplæsning på denne Mac. En hurtigere udgave
ville kræve en egentlig portering (fx til MLX) med usikkert udfald.

Bemærk om lånt stemme: Røsts stemmer stammer fra CoRal-tts-datasættet (CC0). Før en klonet
stemme udgives i et produkt, bør det afklares med Alexandra Instituttet, at det er i orden.

### Måling af oplæsningsfejl (16. november 2026)

Brugeren hørte, at de naturlige stemmer læser tal og nogle ord forkert. Det er målt: hver
stemme læste 36 sætninger (prosa, tal, datoer og klokkeslæt, penge og enheder, forkortelser,
svære ord), og optagelserne blev transskriberet med Whisper large-v3-turbo og sammenlignet med
den tekst, der skulle siges. Testsæt, scripts og rå resultater ligger i `tools/stemmetest/`.

| Stemme | Sætninger uden afvigelse | Tegnfejl i gennemsnit |
|---|---|---|
| Piper + egen tekstforberedelse | 27 af 36 | 1,0 % |
| Apple Sara (rå tekst) | 23 af 36 | 2,5 % |
| Piper (rå tekst) | 16 af 36 | 7,5 % |
| Plapre 3, Tor, forsigtigst mulig (temperatur 0) | 15 af 36 | 14,3 % |
| Plapre 3 med Røst-stemme, temperatur 0,4 | 14 af 36 | 10,3 % |
| Plapre 3, Tor, temperatur 0,4 | 14 af 36 | 16,3 % |
| Plapre 3, Tor, temperatur 0,7 | 9 af 36 | 22,8 % |

Sådan skal tallene læses:

- Talegenkendelsen laver selv småfejl (fx "afguder" for "afkoder", "pære" for "pærer"), så
  "uden afvigelse" undervurderer alle stemmer. Forskellen mellem stemmerne er det, der tæller.
- **Plapre gentager stumper af sætningen** ("vedtog lovforslaget vedtog lovforslaget") i 9–19
  af de 36 sætninger afhængigt af indstilling. Gentagelserne findes i selve lyden: de berørte
  optagelser er ca. 30 % længere. Det forklarer også, at stemmen virkede langsom.
- Min afvikling af Plapre er kontrolleret mod originalens kode på prompt, tokenisering,
  stemmedata og mellemlager, uden at finde forskelle. Jeg kan ikke afgøre, om fejlen ligger i
  tredjepartens ONNX-konvertering eller i modellen selv. Det kræver originalmodellen, som
  ligger bag en vilkårsaccept på Hugging Face. Modelkortet angiver selv 1,67 % tegnfejl, altså
  langt bedre end målt her.
- **Tekstforberedelsen betyder mest.** Piper gik fra 16 til 27 fejlfri sætninger alene ved, at
  tal, klokkeslæt, datoer, enheder og forkortelser blev skrevet ud som ord først. Uden den læste
  Piper fx "150" som "en komma fem", "bl.a." som "bæl er" og "kl." som "kåreil". Også Apple
  fejler på rå tekst ("07:45" blev til "syv hundrede og femogfyrre").
- `num2words`, som de første Plapre-prøver brugte, skriver dårligt dansk ("ettusinde og
  tohundrede og halvtreds", "en millioner"). Den er erstattet af egen kode (`danorm.py`).
- Røst 500m er ikke målt, fordi den er for langsom til at være relevant. Automatisk kontrol
  med gentagelse er ikke afprøvet: med fejl i hver anden sætning ville den koste for meget ventetid.

Konsekvens: Plapre er sat i bero, indtil originalmodellen kan afprøves. Tekstforberedelsen
skal bygges ind i appen uanset stemmevalg. Piper med tekstforberedelse er den mest pålidelige
kandidat; lydprøve i `stemmeproever/8-piper-med-tekstforberedelse.wav`.

Kendt mangel i `danorm.py`: en forkortelse først i en sætning mister sit store bogstav, og
"et"/"en" foran intetkønsord afgøres ikke.

Vurdering fra før målingen (Plapre-anbefalingen gælder ikke længere):

- **Plapre 3 er den foreløbige hovedkandidat.** Den er hurtigere end realtid på CPU, har fem
  indbyggede stemmer (tor, ida, liv, ask, kaj), ingen GPL-dele, kører i ONNX Runtime (som kan
  bygges ind i en Swift-app) og har ingen fonemiseringsafhængighed. Licensen tillader
  kommerciel brug mod kreditering.
- For at nå ca. ét sekund til første lyd skal lyden afspilles, mens resten genereres
  (streaming). Sprogmodellen leverer det første sekunds lydtokens efter ca. 0,5 s, men
  bidvis dekodning er ikke afprøvet og kan give hørbare overgange.
- Plapres modelkort advarer om, at modellen lejlighedsvis siger et ord forkert, fordi den
  sampler. For et hjælpemiddel til ordblinde er det en reel risiko, som skal vurderes ved
  længere lytning.
- Plapre kan kun dansk. Engelsk kræver en anden motor – Apples stemmer indtil videre.
- Plapres originale modeller på Hugging Face kræver accept af vilkår; ONNX-udgaven, der er
  brugt her, er en tredjeparts konvertering (`elgehelge/plapre-onnx-web`). Før udgivelse bør
  vilkårene for originalen læses, og konverteringen enten verificeres eller laves selv.
- **Piper** er uovertruffen på hastighed og størrelse og en oplagt "hurtig" stemme, hvis
  kvaliteten er god nok og GPL-spørgsmålet kan løses (fx ved at appen udgives som åben kildekode).
  Teknisk note: espeak-ng fejler, hvis stien til dens data er længere end ca. 160 tegn.
- **Røst v3** er for langsom og for stor til direkte oplæsning på denne maskine i den afprøvede form.
- Tal skal skrives ud som ord før syntese (Plapre og Røst). Det er afprøvet med `num2words`
  i Python; i appen skal det laves i Swift (`NumberFormatter` med `.spellOut` og dansk locale).

Kilder: [Plapre 3](https://huggingface.co/syvai/plapre-3),
[Plapre ONNX](https://huggingface.co/elgehelge/plapre-onnx-web),
[Plapre-kode](https://github.com/syv-ai/plapre),
[Røst v3 350m](https://huggingface.co/CoRal-project/roest-v3-chatterbox-350m),
[Røst v3 500m](https://huggingface.co/CoRal-project/roest-v3-chatterbox-500m),
[Piper-modelkort](https://huggingface.co/rhasspy/piper-voices/blob/main/da/da_DK/talesyntese/medium/MODEL_CARD),
[afklaring af Pipers danske datasæt](https://huggingface.co/rhasspy/piper-voices/discussions/12).

### Piper og tekstforberedelse i appen (16. november 2026)

Bygget ind:

- `DanishTextNormalizer.swift`: tekstforberedelsen fra målingen, porteret til Swift. Bruges for
  al dansk tekst, uanset motor. De 36 testsætninger er nu en automatisk test.
- `PiperSpeechEngine.swift`: Piper via sherpa-onnx v1.13.8, linket statisk. Teksten syntetiseres
  sætning for sætning i baggrunden og afspilles, så snart første sætning er klar.
- `ModelDownloader.swift`: henter en stemme fra en fast liste, kontrollerer SHA-256, pakker ud og
  installerer i `~/Library/Application Support/Baymow/Voices/`. Kan også fjerne stemmen igen.
  Det er appens eneste netværksadgang og sker kun, når brugeren trykker "Hent".
- Hentede neurale stemmer vælges frem for Apples, medmindre brugeren har valgt en anden.

Verificeret:

- 25 automatiske tests består.
- Appens egen Piper-oplæsning af de 36 testsætninger, kontrolleret med talegenkendelse:
  26 uden afvigelse, 1,9 % tegnfejl (Python-prototypen: 27 og 1,0 %; Apple på rå tekst: 23 og 2,5 %).
- Syntese: 119 s lyd på 5,2 s. Motoren melder start efter 20–30 ms, når modellen er indlæst
  (160 ms første gang), målt lydløst.
- Download, kontrolsum og udpakning er kørt for alvor mod GitHub.

Ikke verificeret: oplæsning med Piper via genvejen, pause/fortsæt under Piper-afspilning, og
sektionen "Hent stemmer" i vinduet (ikke set på skærmen).

Kendte svagheder:

- "kl. 9.00 den 3. maj" blev hørt som "klokken ni tredive" i begge Piper-målinger. Ordet "den"
  forsvinder efter et helt klokkeslæt.
- Hastigheden ændres ved at syntetisere bidden igen fra den aktuelle sætning, så et par ord kan
  blive gentaget ved hastighedsskift.
- Ordposition findes ikke for Piper (kun sætningsposition). Ordfremhævning kræver mere arbejde.

**Licens – skal afklares før udgivelse.** sherpa-onnx er Apache-2.0, men version 1.x indeholder
espeak-ng (GPL-3.0), som nu er linket ind i appen. Appen kan derfor i sin nuværende form kun
distribueres under GPL. sherpa-onnx 2.x har fjernet espeak-ng fra biblioteket og forventer, at
udtalen leveres udefra; det åbner for at holde GPL-delen i et separat hjælpeprogram. Det er en
juridisk vurdering, som ikke er foretaget her.

Kilder til de vendorerede filer (ligger i `Vendor/`, kontrolsummer SHA-256):

- `sherpa-onnx-v1.13.8-osx-arm64-static-lib.tar.bz2` fra github.com/k2-fsa/sherpa-onnx, release
  v1.13.8: `9091bf160dc7fdacedbc906b212badf53c2993f4e5277a0e03998e96c31d60da`
- `vits-piper-da_DK-talesyntese-medium.tar.bz2`, release `tts-models`:
  `f2e2cbcdb2b21e76f93635b35105d07b37997ace434d7289d04b689a97c19bd0`

### Cloud-stemmer (ElevenLabs m.fl.)

Undersøgt på brugerens ønske. **Dette er et brud med specifikationens principper om offline-first
og privacy-first**: den markerede tekst skal sendes til en ekstern tjeneste. Hvis det tilbydes,
bør det være et tydeligt tilvalg pr. stemme, slået fra som standard, og aldrig en stille fallback.

Priser pr. million tegn, som rapporteret af tredjepartskilder i efteråret 2026 – skal bekræftes
på udbydernes egne prissider:

| Tjeneste | Dansk | Pris pr. 1 mio. tegn | Gratis pr. måned |
|---|---|---|---|
| ElevenLabs Flash v2.5 | Ja | 40 USD | Lille gratisplan |
| ElevenLabs Multilingual v2 / v3 | Ja | 80 USD | Lille gratisplan |
| Azure Speech, neurale stemmer (Christel, Jeppe) | Ja | ca. 15 USD (HD: 22 USD) | 0,5 mio. tegn |
| Google Cloud, Chirp 3 HD | Ikke bekræftet | 30 USD | 1 mio. tegn |
| Amazon Polly, neural (Sofie) | Ja | ca. 16 USD | – |
| OpenAI gpt-4o-mini-tts | Følger Whispers sprog; dansk kvalitet ukendt | Afregnes pr. token | – |

Regneeksempel (egen antagelse: oplæsning ca. 900 tegn i minuttet, 22 dage om måneden):

| Brug | Tegn pr. måned | ElevenLabs Flash | ElevenLabs v3 | Azure neural |
|---|---|---|---|---|
| 30 min. om dagen | ca. 0,6 mio. | 24 USD | 48 USD | 9 USD |
| 2 timer om dagen | ca. 2,4 mio. | 96 USD | 192 USD | 36 USD |

Vurdering:

- **ElevenLabs kan ikke betale sig som standardstemme.** Prisen pr. bruger overstiger, hvad et
  hjælpemiddel realistisk kan koste, og en ordblind bruger læser meget. Som tilvalg med brugerens
  egen API-nøgle er det muligt.
- **Azure er det mest oplagte cloud-valg**, hvis der skal være ét: en fjerdedel til en femtedel
  af ElevenLabs' pris, datacentre i EU, og dets almindelige neurale stemmer er af den regelbaserede
  type, der ikke digter ord. Kvaliteten på dansk er ikke afprøvet her; det kræver en konto.
- Med brugerens egen nøgle gælder gratiskvoterne pr. bruger, så let brug kan være gratis.
- Dataopbevaring og GDPR-vilkår (herunder om ElevenLabs tilbyder nul-opbevaring uden for
  enterprise-aftaler) fandt jeg ikke bekræftet og skal afklares før et valg.
- Arkitekturen kan bære det: en cloud-motor er endnu en `SpeechEngine`, der leverer lyd til samme
  afspiller som Piper. Afspilningsdelen i `PiperSpeechEngine` skal dog først trækkes ud til en
  fælles komponent.

Kilder: [ElevenLabs-priser (modelslab)](https://modelslab.com/elevenlabs-api-pricing),
[ElevenLabs-priser (oakgen)](https://oakgen.ai/blog/elevenlabs-pricing-limits-cost),
[ElevenLabs sprog](https://elevenlabs.io/docs/help-center/other/what-languages-do-you-support),
[Azure-priser](https://texttolab.com/blog/azure-text-to-speech-pricing),
[Azure sprog og stemmer](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support),
[Azure HD-prisændring](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/azure-speech-%E2%80%93-neural-hd-text-to-speech-recent-voice-updates/4505380),
[Google Cloud TTS-priser](https://www.developersdigest.tech/models/speech/google-cloud),
[OpenAI gpt-4o-mini-tts](https://developers.openai.com/api/docs/models/gpt-4o-mini-tts),
[Amazon Polly-omkostninger](https://costbench.com/software/voice-apis/amazon-polly-api/hidden-costs/).

## 4. Udviklingsplan og godkendelse

| Milepæl | Indhold | Godkendes ved |
|---|---|---|
| 1 Teknisk fundament | Genvej, indfangning, lokal TTS, session, tilladelser | Testvejledningen nedenfor |
| 2 Læseoplevelse i Safari | Finpudsning af afspiller og fejlbeskeder efter din afprøvning; test af lange tekster og programskift | Du læser en hel artikel i Safari og bruger alle knapper uden fejl |
| 3 Chrome og bredere indfangning | Aktivering af Chromes tilgængelighedstræ, layout-uafhængig kopiering, test i Mail, Noter, Slack, VS Code | Testmatrix med program × metode × resultat |
| 4 Stemmer, indstillinger, onboarding | Beslutning om ekstra TTS-motor, `ModelDownloader` med kontrolsum, førstegangsguide | En person uden forhåndsviden kommer fra første start til første oplæsning |
| 5 Dokumentprogrammer og PDF | Word, Google Docs i Safari og Chrome, Preview | Testmatrix udvidet; kendte begrænsninger dokumenteret |
| 6 Stabilisering og udgivelse | Hukommelses- og langtidstest, Developer ID-signering, notarisering, DMG | Installation på en ren Mac fra DMG |

Meget af milepæl 2 og dele af milepæl 4 (afspiller, indstillinger, stemmevalg, tilladelsesguide)
findes allerede i prototypen, fordi de var billige at bygge sammen med fundamentet. De er ikke
godkendt, før du har prøvet dem.

## 5. Status for milepæl 1

Verificeret:

- Appen bygger, signeres med et lokalt Apple Development-certifikat og starter.
- Genvejen ⌃⌥S registreres uden fejl.
- 19 automatiske tests består: sproggenkendelse, opdeling i bidder, pause/fortsæt/stop/genstart,
  erstatning af session uden overlap, hastighedsændring fra det aktuelle ord, frigivelse af tekst
  ved lukning, gemte indstillinger, og at loggen ikke indeholder oplæst tekst.
- Apples motor starter dansk og engelsk tale lokalt.

Bekræftet af dig: oplæsning af markeret tekst i Safari med ⌃⌥S virker (546 ms til indfanget
tekst, 605 ms til talestart ifølge loggen).

Ikke verificeret endnu:

- Tekstindfangning i Chrome, Word og Preview.
- At Safari nu bruger Accessibility i stedet for fallbacken.
- Hvordan stemmerne lyder, og den reelle tid fra tastetryk til lyd.
- Afspillerens og beskedernes udseende – de er ikke set på skærmen.
- Offline-brug (forventes at virke, da intet i appen bruger netværk).

## 6. Sådan tester du milepæl 1

Byg og start:

```bash
./Scripts/build-app.sh
```

```bash
open build/Baymow.app
```

1. Klik **Giv adgang…** i vinduet, og slå Baymow til under Tilgængelighed.
2. Markér et afsnit dansk tekst i Safari, og tryk ⌃⌥S. Afspilleren skal dukke op, og teksten læses.
3. Skift til et andet program, mens der læses. Oplæsningen skal fortsætte.
4. Prøv pause, afspil, stop, start forfra, og plus/minus for hastighed.
5. Markér en engelsk tekst, og tryk ⌃⌥S midt i oplæsningen. Den nye tekst skal erstatte den
   gamle med engelsk stemme og uden overlap.
6. Tryk ⌃⌥S uden noget markeret. Der skal komme en kort besked.
7. Luk afspilleren på krydset. Appen skal blive i menulinjen.
8. Gentag trin 2 i Chrome, Word og Preview, og notér, hvad der virker.

Tiderne kan ses bagefter:

```bash
tail -20 ~/Library/Logs/Baymow/baymow.log
```

Se, hvad et program udstiller via Accessibility (roller, fejlkoder og tekstlængder – ingen tekst):

```bash
open -n -W build/Baymow.app --args --ax-diagnose com.apple.Safari && cat ~/Library/Logs/Baymow/ax-diagnose.txt
```

Automatiske tests og lydløs måling af motorens starttid:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```bash
./build/Baymow.app/Contents/MacOS/Baymow --measure-latency
```
