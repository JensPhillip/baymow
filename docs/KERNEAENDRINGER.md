# Kerneændringer

Kernen er filerne i `Sources/BaymowKit/Core/` og `Tests/BaymowKitTests/CoreContractTests.swift`.
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
