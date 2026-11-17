"""Ordprøve: tester, om en stemme udtaler enkelte ord, så talegenkendelsen kan genkende dem.

Brug: word_probe.py <ud.json> <ord-eller-ord=stavemåde> ...
  "Chrome"          tester ordet, som det står
  "Chrome=krovm"    tester stavemåden "krovm" og ser, om den høres som "Chrome"

Hvert ord siges i to bæresætninger af Piper og af Apple Sara. Et ord består for en stemme, hvis
talegenkendelsen skriver ordet i mindst én af de to sætninger. Det er et groft mål: talegenkendelsen
gætter ud fra sammenhængen og kan både være for flink og for streng.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
APP = os.path.join(ROOT, "build/Baymow.app/Contents/MacOS/Baymow")
PIPER = os.path.join(ROOT, "Vendor/piper-da-test")
CARRIERS = ["Jeg bruger {} hver dag.", "Har du prøvet {} før?"]
sys.path.insert(0, HERE)
from evaluate import MODEL, load16k  # noqa: E402


def squash(text):
    return re.sub(r"[^a-z0-9æøå]", "", text.lower())


def main():
    out, items = sys.argv[1], sys.argv[2:]
    pairs = [(i.split("=")[0], i.split("=")[-1]) for i in items]  # (ordet, stavemåden der siges)
    work = tempfile.mkdtemp()
    lines = [c.format(spoken) for _, spoken in pairs for c in CARRIERS]
    open(f"{work}/lines.txt", "w").write("\n".join(lines) + "\n")
    # --raw: ingen tekstforberedelse, så stavemåden siges præcis som skrevet.
    subprocess.run([APP, "--synthesize", PIPER, f"{work}/lines.txt", f"{work}/piper", "--raw"], check=True, capture_output=True)
    os.makedirs(f"{work}/apple")
    for n, line in enumerate(lines):
        subprocess.run(["say", "-v", "Sara", "-o", f"{work}/apple/{n:02d}.aiff", line], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", f"{work}/apple/{n:02d}.aiff", f"{work}/apple/{n:02d}.wav"], check=True)

    import mlx_whisper
    results = {}
    for voice in ("piper", "apple"):
        for k, (word, spoken) in enumerate(pairs):
            heard = []
            for c in range(len(CARRIERS)):
                n = k * len(CARRIERS) + c
                text = mlx_whisper.transcribe(load16k(f"{work}/{voice}/{n:02d}.wav"), path_or_hf_repo=MODEL, language="da",
                                              temperature=0.0, condition_on_previous_text=False, verbose=None)["text"].strip()
                heard.append(text)
            ok = any(squash(word) in squash(h) for h in heard)
            results.setdefault(f"{word}={spoken}", {})[voice] = {"ok": ok, "heard": heard}
    json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
    for key, r in results.items():
        print(f"{key:34s} piper {'ok  ' if r['piper']['ok'] else 'FEJL'}  apple {'ok  ' if r['apple']['ok'] else 'FEJL'}"
              + ("" if r["piper"]["ok"] and r["apple"]["ok"] else f"   {r['piper']['heard'][0]} | {r['apple']['heard'][0]}"))


if __name__ == "__main__":
    main()
