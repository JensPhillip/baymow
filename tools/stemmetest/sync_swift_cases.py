"""Holder Swift-testens sætninger ens med sentences.py og sentences_tekstforberedelse.py, som er de eneste kilder.

Brug: sync_swift_cases.py          skriver listen ind i Swift-testen
      sync_swift_cases.py --check  afslutter med fejl, hvis de to er ude af trit (bruges af Scripts/check.sh)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TARGET = os.path.join(ROOT, "Tests/BaymowCoreTests/DanishTextNormalizerTests.swift")
START, END = "        // GENERERET-START (tools/stemmetest/sync_swift_cases.py)\n", "        // GENERERET-SLUT\n"

sys.path.insert(0, HERE)
from sentences import SENTENCES as STEMMETEST  # noqa: E402
from sentences_tekstforberedelse import SENTENCES as TEKSTFORBEREDELSE  # noqa: E402

# Swift-testen dækker både stemmetestens 36 sætninger og tekstforberedelsens ekstra tilfælde.
SENTENCES = STEMMETEST + TEKSTFORBEREDELSE


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    block = START + "".join(f'        ("{escape(w)}", "{escape(s)}"),\n' for _, w, s in SENTENCES) + END
    source = open(TARGET, encoding="utf-8").read()
    a, b = source.index(START), source.index(END) + len(END)
    updated = source[:a] + block + source[b:]
    if "--check" in sys.argv:
        if updated != source:
            sys.exit("Swift-testens sætninger afviger fra tools/stemmetest/sentences.py. Kør sync_swift_cases.py.")
        return
    open(TARGET, "w", encoding="utf-8").write(updated)
    print(f"{len(SENTENCES)} sætninger skrevet til {os.path.relpath(TARGET, ROOT)}")


if __name__ == "__main__":
    main()
