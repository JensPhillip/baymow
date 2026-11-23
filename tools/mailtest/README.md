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
