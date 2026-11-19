# Kerneændringer

Kernen er målet `BaymowCore` (`Sources/BaymowCore/`) og dets tests (`Tests/BaymowCoreTests/`).
Indtil 2026-11-17 lå den i `Sources/BaymowKit/Core/`; ældre afsnit nedenfor bruger de gamle stier.
Den bærer MVP'en: genvej → markeret tekst → session → stemme. Nye funktioner bygges uden om den
(se `PROJEKTPLAN.md` afsnit 3). Skal kernen alligevel ændres, skal det være med vilje, og hver
ændring får et afsnit her. `Scripts/check.sh` afviser kerneændringer uden et nyt afsnit.

Skabelon:

```
## ÅÅÅÅ-MM-DD · AP-xx · kort titel
Hvad: hvilke filer og hvilken adfærd ændres.
Hvorfor: hvorfor det ikke kunne løses uden for kernen.
Kontrakt: hvilke kernekontrakt-tests er tilføjet eller ændret, og hvorfor de gamle ikke længere gælder.
Godkendt af: arkitekt / bruger.
```

---

## 2026-11-16 · AP-00/AP-01 · Omdøbning til Baymow, opdeling i mapper, godkendte standardstemmer
Hvad: Projektet er omdøbt fra Oplæser til Baymow. Koden er delt i `Core/`, `Engines/`, `UI/` og
`Tools/`; `AppleSpeechEngine` er flyttet fra `SpeechEngine.swift` til `Engines/`. `Voice` har fået
`isApprovedDefault`, og `VoiceCatalog` vælger kun godkendte stemmer automatisk.
Hvorfor: Brugeren afviste Piper som standardstemme; automatisk valg er kernens ansvar.
Kontrakt: To nye tests (`testUnapprovedVoiceIsNeverChosenAutomatically`,
`testUnapprovedVoiceIsUsedWhenNothingElseExists`). Ingen eksisterende tests er ændret i indhold.
Godkendt af: arkitekt.

## 2026-11-16 · AP-12 · Loggen viser, hvilken stemme der læste
Hvad: `DiagnosticsService.record` har fået parameteren `voice: Voice?`; `speechStarted` logger stemmens
id og sprog. `ReadingSessionManager` sender den aktuelle stemme med.
Hvorfor: Brugeren fandt en oplæsning næsten uforståelig, og loggen kunne ikke vise, hvilken stemme eller
hvilket sprog der var brugt. Parameteren er en `Voice` fra stemmekataloget, ikke fritekst, så reglen om,
at brugertekst ikke kan nå loggen, står uændret.
Kontrakt: K10-testen (`testLogNeverContainsSpokenText`) kontrollerer nu også, at stemme og sprog logges.
Ingen eksisterende påstande er fjernet.
Godkendt af: arkitekt.

## 2026-11-16 · AP-24 · Udtalelister pr. stemmemotor
Hvad: Ny `Core/PronunciationOverrides.swift` (udskifter hele ord med en anden stavemåde, bevarer endelser).
`SpeechEngine` har fået `pronunciationOverrides(for:)` med en tom standardudgave, så eksisterende
motorer er uændrede. `ReadingSessionManager.spokenText` anvender motorens liste på dansk tekst efter
tekstforberedelsen.
Hvorfor: Hvilke engelske ord der udtales forkert, afhænger af motoren, så listen må komme fra motoren,
og udskiftningen må ske dér, hvor teksten gives til motoren – i kernen.
Kontrakt: Ny test `testEngineSpecificPronunciationIsAppliedToDanishOnly` (udvider K7). Ingen
eksisterende tests er ændret. Med tom liste er adfærden uændret.
Godkendt af: arkitekt.

## 2026-11-17 · AP-22 · Tekstforberedelse, runde 2
Hvad: `DanishTextNormalizer` har fået nye regler for webadresser og mail, valuta (kr., DKK, EUR, USD, €, $, £),
"stk.", "§§", "pct.", romertal efter regentnavne og efter kapitel/del/bind, klokkeslæt-intervaller,
ISO-datoer, "den 3/5", CPR- og lange numre, telefonnumre i par, grupper med foranstillet nul, intervaller
("10-15" → "til", men "3-1" → resultat), fortegn, brøker og "½", årstal 1100–1999 uden kontekstord og
ordenstal foran et ord med lille begyndelsesbogstav. Reglerne kører i en fast rækkefølge, med webadresser først.
Hvorfor: Planens AP-22. Tekstforberedelsen er kernens ansvar (regel 4: al dansk tekst forberedes før motoren).
Kontrakt: K7 udvidet med 52 nye tilfælde (`tools/stemmetest/sentences_tekstforberedelse.py`, genereret ind i
`DanishTextNormalizerTests`) og 12 regressionstilfælde. Ingen af de 36 gamle tilfælde er ændret.
Engelsk tekst forberedes fortsat ikke (`testEnglishTextIsNotChanged` uændret).
Godkendt af: udfører efter planens AP-22, hvor kerneændringen er forudset.

## 2026-11-17 · AP-23 · Kernen som eget kompileringsmål
Hvad: `Sources/BaymowKit/Core/` er flyttet til målet `BaymowCore` (`Sources/BaymowCore/`).
`CoreContractTests.swift` og `DanishTextNormalizerTests.swift` er flyttet til testmålet `BaymowCoreTests`,
som kun afhænger af `BaymowCore`. `Language.sampleText` og `TextCaptureService.webAreas` er gjort `public`,
fordi `BaymowKit` bruger dem. Ingen adfærd er ændret.
Hvorfor: Planens AP-23. Compileren afviser nu, at kernen afhænger af motorer, brugerflade eller værktøjer.
Kontrakt: Ingen tests er ændret i indhold – kun flyttet og med `@testable import BaymowCore`.
`DanishTextNormalizerTests` hører nu formelt til kernen (kontrakt K7), så ændringer i testsætningerne,
der genereres ind i den, er kerneændringer og skal begrundes her.
Godkendt af: udfører efter planens AP-23, hvor kerneændringen er forudset.

## 2026-11-17 · AP-21 · Grænse for tekstlængde
Hvad: `ReadingSessionManager.start` afviser tekster over `maxTextLength` (200.000 tegn, ca. fire timers
oplæsning) med den nye besked `Notice.tooLong`. `DiagnosticsService.Event` har fået `textTooLong`.
Hvorfor: Planens AP-21. En markering ved et uheld (fx ⌘A i en hel bog) skal give en venlig besked i stedet
for timevis af oplæsning og en stor tekst i hukommelsen. Sessionen ejer starten, så grænsen hører til i kernen.
Kontrakt: Ny test `testVeryLongTextIsRefusedWithAFriendlyNotice` (udvider K1/K3: ingen session ved afvisning).
Ingen eksisterende tests er ændret.
Godkendt af: udfører efter planens AP-21, hvor grænsen er forudset.

## 2026-11-18 · AP-20 · Hastighedsskift uden at starte forfra
Hvad: `SpeechEngine` har fået `setRate(_:) -> Bool` med en standardudgave, der returnerer `false`.
`ReadingSessionManager.setRate` spørger først motoren; kan den skifte undervejs, fortsætter oplæsningen uden
afbrydelse. Ellers bruges den gamle vej (start igen fra det nåede ord), som Apple-stemmerne fortsat bruger.
Hvorfor: Planens AP-20. Backend-stemmer (Piper) kender kun sætningspositioner, så et hastighedsskift læste
den aktuelle sætning forfra. Kun motoren ved, om den kan skifte undervejs, så spørgsmålet må stilles i kernen.
Kontrakt: K5 udvidet med `testLiveRateChangeContinuesWithoutRestarting` og
`testRateChangeWhenStoppedIsJustRemembered`. Eksisterende K5-tests er uændrede og består (motorer uden
`setRate` opfører sig som før).
Godkendt af: udfører efter planens AP-20, hvor ændringen er forudset.

## 2026-11-18 · Rettelse · Nedbrud ved genvejen, når teksten hentes med kopiering
Hvad: `TextCaptureService.postCopy` og `keyCodeForCopy` er markeret `@MainActor`, og kopierings-reserveløsningen
kalder dem med `await`. Ingen anden adfærd er ændret.
Hvorfor: `keyCodeForCopy` aflæser tastaturlayoutet med `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`,
som på macOS 26 kræver hovedtråden og ellers afbryder appen (`dispatch_assert_queue`). Den blev kaldt fra en
baggrundstråd, så Baymow lukkede, hver gang genvejen brugte reserveløsningen. Fundet af brugeren under AP-20.
`keyCodeForCopy` er gjort `public`, så selvtesten i `BaymowKit` kan kalde den.
Kontrakt: Ingen tests ændret. En almindelig test kan ikke fange fejlen (macOS afbryder kun en kørende app,
ikke et testprogram – afprøvet), så den fanges af selvtesten `--copykey-selftest`, som går ned uden rettelsen
og består med den.
Godkendt af: udfører; fejlrettelse.

## 2026-11-19 · AP-30 · Test af gendannelse af udklipsholderen
Hvad: `TextCaptureService.snapshot(of:)` og `restore(_:to:)` er ændret fra `private` til `internal`, så de kan testes.
Ingen adfærd er ændret.
Hvorfor: Planens AP-30 kræver, at udklipsholderens tidligere indhold er uændret, efter at teksten er hentet med
kopiering – også med et billede. Det kan testes direkte på en separat udklipsholder.
Kontrakt: Nye tests i `Tests/BaymowCoreTests/ClipboardRestoreTests.swift` (tekst, billede og RTF byte for byte,
flere elementer, tom udklipsholder). Ingen eksisterende tests er ændret.
Godkendt af: udfører efter planens AP-30.
