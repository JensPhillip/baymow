# Mail-testen (AP-71)

Måler mail-svar med egne, opdigtede mailtråde – aldrig brugerens mails.

```bash
./Scripts/build-app.sh
BAYMOW_TEST_KEY="$(security find-generic-password -a baymow-test -s baymow-openai -w)" ./build/Baymow.app/Contents/MacOS/Baymow --mail-test tools/mailtest/traade.json /tmp/mail.json --cloud openai
```

- `traade.json`: 6 tråde (møde med stikord, tilbud uden stikord, pris "vi skal tjekke", en ordre gemt i tråden, engelsk
  tråd, ingen signatur). For hver: ord, der skal og ikke må stå, og om der skal være [felter].
- Testen tjekker også tal i svaret, der hverken står i stikordene eller tråden (opdigtede fakta), og navn til sidst,
  når signaturen findes. Svarene skrives ud, så et menneske kan læse dem.
- `resultater/openai-endelig.json`: GPT-6 Luna, sidste kørsel.

## Sparring (AP-74)

```bash
BAYMOW_TEST_KEY="$(security find-generic-password -a baymow-test -s baymow-openai -w)" ./build/Baymow.app/Contents/MacOS/Baymow --sparring-test tools/mailtest/traade.json /tmp/sparring.json --cloud openai
```

Hver tråd får de fire faste spørgsmål og "Hvad er afsenderens telefonnummer?" (står ingen steder). Tjekker længde,
"står ikke i mailen" og at brugerens egen mail genkendes. `resultater/sparring-openai.json`: GPT-6 Luna, 40 af 40.

> Testnøglerne (konto `baymow-test`) blev slettet 24. november 2026. Skal der måles igen, gemmes de først på ny med
> `security add-generic-password -U -a baymow-test -s <baymow-openai|baymow-claude> -w`.

> Uden `BAYMOW_TEST_KEY` bruger testen den nøgle, der er gemt i Baymow (siden "AI og nøgler").
> 24. november 2026: to nye tråde, hvor svaret skal gives som valg ("[passer / passer ikke]") i stedet for et gæt.
> 10 af 10 i fem kørsler (`resultater/2026-11-24-valg-openai-*.json`).
