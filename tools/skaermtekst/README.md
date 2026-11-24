# Tekst fra skærmen – måling (AP-75)

Måler Macens tekstgenkendelse (Vision, dansk og engelsk) på egne danske tekster – aldrig brugerens skærm.

```bash
./Scripts/build-app.sh
./build/Baymow.app/Contents/MacOS/Baymow --ocr-test tools/skaermtekst/tekster.txt /tmp/ocr.json
```

- `tekster.txt`: 5 afsnit med æ/ø/å, tal, datoer, beløb, en mailadresse og et telefonnummer.
- Hvert afsnit tegnes i seks udgaver: skarp 15 pt, lille 11 pt uden Retina, med fødder 16 pt, lysegrå, mørk tilstand og
  "indscannet" (formindsket, sløret, 1° skæv). Tallet er tegnfejl (Levenshtein / antal tegn) efter æ/ø/å-rettelsen.
- `resultater/ocr.json`: seneste kørsel.
