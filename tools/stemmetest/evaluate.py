"""Stemmetest: transskriberer en stemmes optagelser af testsætningerne og tæller afvigelser.

Brug: evaluate.py <navn> <mappe med 00.wav …> [--gate]

Måler kun, om stemmen siger det, der står. Den måler IKKE, om et menneske kan forstå stemmen –
det afgør brugeren med lytteskemaet (docs/LYTTESKEMA.md).
"""
import datetime
import json
import os
import re
import subprocess
import sys

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
APP = os.path.join(ROOT, "build/Baymow.app/Contents/MacOS/Baymow")
MODEL = "mlx-community/whisper-large-v3-turbo"
# Stemmeportens krav 1 (docs/PROJEKTPLAN.md afsnit 7). Talegenkendelsen bidrager selv med 2–3 %;
# regelbaserede stemmer måler 2,3–2,7 %, stemmer der digter ord 10–23 %.
MAX_CER = 0.035

sys.path.insert(0, HERE)


def load_sentences():
    """--set <navn> vælger tools/stemmetest/sentences_<navn>.py; uden vælges de 36 danske."""
    import importlib
    name = sys.argv[sys.argv.index("--set") + 1] if "--set" in sys.argv else "dansk"
    return importlib.import_module("sentences" if name == "dansk" else f"sentences_{name}").SENTENCES


def canon(text):
    return re.sub(r"\s+", " ", re.sub(r"[^\wæøå ]", " ", text.lower())).strip()


def prepare(lines):
    """Appens egen tekstforberedelse, så der kun findes én udgave af reglerne."""
    out = subprocess.run([APP, "--normalize"], input="\n".join(lines) + "\n", capture_output=True, text=True, check=True)
    result = out.stdout.split("\n")[: len(lines)]
    assert len(result) == len(lines), "tekstforberedelsen gav et andet antal linjer"
    return result


def load16k(path):
    """Læser en wav-fil som 16 kHz mono uden ffmpeg."""
    wav, rate = sf.read(path, dtype="float32")
    wav = wav if wav.ndim == 1 else wav.mean(1)
    return wav if rate == 16000 else resample_poly(wav, 16000, rate).astype(np.float32)


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[-1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def cer(reference, heard):
    """Tegnfejl uden mellemrum, så 'to tusind' og 'totusind' tæller ens."""
    r, h = reference.replace(" ", ""), heard.replace(" ", "")
    return edit_distance(r, h) / max(len(r), 1)


def has_repeat(reference, heard):
    """Sandt, hvis to ord i træk siges flere gange i det hørte, end de står i teksten
    ("vedtog lovforslaget vedtog lovforslaget"). Det er sprogmodel-stemmers typiske fejl."""
    def pairs(text):
        words = text.split()
        counts = {}
        for pair in zip(words, words[1:]):
            counts[pair] = counts.get(pair, 0) + 1
        return counts
    expected = pairs(reference)
    return any(count > max(expected.get(pair, 0), 1) for pair, count in pairs(heard).items())


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    name, folder, gate = sys.argv[1], sys.argv[2], "--gate" in sys.argv
    if not os.path.exists(APP):
        sys.exit("Byg appen først: ./Scripts/build-app.sh")
    import mlx_whisper

    SENTENCES = load_sentences()
    transcripts = []
    for index in range(len(SENTENCES)):
        path = os.path.join(folder, f"{index:02d}.wav")
        if not os.path.exists(path):
            sys.exit(f"Mangler {path}")
        result = mlx_whisper.transcribe(load16k(path), path_or_hf_repo=MODEL, language="da", temperature=0.0,
                                        condition_on_previous_text=False, verbose=None)
        transcripts.append(result["text"].strip())
    heard = [canon(line) for line in prepare(transcripts)]

    rows = []
    for (category, written, spoken), hyp in zip(SENTENCES, heard):
        rows.append({"cat": category, "written": written, "ref": spoken, "hyp": hyp, "cer": cer(spoken, hyp),
                     "repeats": has_repeat(spoken, hyp), "omits": len(hyp.split()) < 0.7 * len(spoken.split())})

    clean = sum(r["cer"] == 0 for r in rows)
    mean = sum(r["cer"] for r in rows) / len(rows)
    repeats = sum(r["repeats"] for r in rows)
    omits = sum(r["omits"] for r in rows)
    print(f"{name}: fejlfri {clean}/{len(rows)}, tegnfejl {mean * 100:.1f} %, "
          f"sætninger med gentagelser {repeats}, med udeladelser {omits}")
    categories = sorted({r["cat"] for r in rows})
    print("  pr. kategori: " + ", ".join(
        f"{c} {sum(r['cer'] == 0 for r in rows if r['cat'] == c)}/{sum(r['cat'] == c for r in rows)}" for c in categories))
    for index, r in enumerate(rows):
        if r["cer"] > 0:
            flag = " GENTAGELSE" if r["repeats"] else (" UDELADELSE" if r["omits"] else "")
            print(f"  [{index:02d} {r['cer'] * 100:3.0f}%{flag}] hørt:   {r['hyp']}\n               ventet: {r['ref']}")

    os.makedirs(os.path.join(HERE, "resultater"), exist_ok=True)
    out = os.path.join(HERE, "resultater", f"{name}-{datetime.date.today().isoformat()}.json")
    json.dump({"name": name, "clean": clean, "total": len(rows), "cer": mean, "repeats": repeats, "omits": omits,
               "rows": rows}, open(out, "w"), ensure_ascii=False, indent=1)
    print(f"  gemt: {os.path.relpath(out, ROOT)}")

    passed = mean <= MAX_CER and repeats == 0 and omits == 0
    print(f"  stemmeportens krav 1 (højst {MAX_CER * 100:.1f} % tegnfejl, ingen gentagelser eller udeladelser): "
          f"{'BESTÅET' if passed else 'IKKE BESTÅET'}")
    if gate and not passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
