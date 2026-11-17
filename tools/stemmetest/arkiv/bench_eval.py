"""Transskriberer lydprøverne og tæller afvigelser fra den tekst, der skulle siges.
Brug: bench_eval.py <bench-mappe> [betingelser...]"""
import json
import os
import re
import sys

import mlx_whisper

from danorm import normalize
from sentences import SENTENCES

MODEL = "mlx-community/whisper-large-v3-turbo"


def canon(s):
    s = s.lower().replace("å", "aa") if False else s.lower()
    return re.sub(r"\s+", " ", re.sub(r"[^\wæøå ]", " ", s)).strip()


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[-1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def load16k(path):
    """Læser en wav-fil som 16 kHz mono uden ffmpeg."""
    import numpy as np, soundfile as sf
    from scipy.signal import resample_poly
    wav, sr = sf.read(path, dtype="float32")
    wav = wav if wav.ndim == 1 else wav.mean(1)
    return wav if sr == 16000 else resample_poly(wav, 16000, sr).astype(np.float32)


def heard(path):
    result = mlx_whisper.transcribe(load16k(path) if isinstance(path, str) else path, path_or_hf_repo=MODEL, language="da", temperature=0.0,
                                    condition_on_previous_text=False, verbose=None)
    return canon(normalize(result["text"]))


def score(reference, hypothesis):
    """Tegnfejlrate uden mellemrum, så 'to tusind' og 'totusind' tæller ens."""
    r, h = reference.replace(" ", ""), hypothesis.replace(" ", "")
    return edit_distance(r, h) / max(len(r), 1)


if __name__ == "__main__":
    bench = sys.argv[1]
    conditions = sys.argv[2:] or sorted(d for d in os.listdir(bench) if os.path.isdir(f"{bench}/{d}"))
    results = {}
    for cond in conditions:
        rows = []
        for i, (cat, raw, spoken) in enumerate(SENTENCES):
            hyp = heard(f"{bench}/{cond}/{i:02d}.wav")
            rows.append({"i": i, "cat": cat, "ref": spoken, "hyp": hyp, "cer": score(spoken, hyp)})
        results[cond] = rows
        json.dump(results, open(f"{bench}/results.json", "w"), ensure_ascii=False, indent=1)
        print(cond, "færdig", flush=True)
