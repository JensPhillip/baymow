"""Lader hver stemme læse testsættet. Brug: bench_gen.py <ud-mappe> <roest-referencelyd> <espeak-data> [betingelser...]"""
import json, os, subprocess, sys, time, wave
import numpy as np, soundfile as sf
from danorm import normalize
from sentences import SENTENCES

out, ref_wav, espeak = sys.argv[1], sys.argv[2], sys.argv[3]
only = set(sys.argv[4:])
here = os.path.dirname(os.path.abspath(__file__))

def run(name, fn):
    if only and name not in only: return
    d = f"{out}/{name}"; os.makedirs(d, exist_ok=True)
    times = []
    for i, (cat, raw, spoken) in enumerate(SENTENCES):
        t = time.time(); fn(raw, f"{d}/{i:02d}.wav"); times.append(time.time() - t)
    json.dump(times, open(f"{d}/times.json", "w"))
    print(name, f"færdig, {sum(times):.0f}s", flush=True)

def apple(text, path):
    aiff = path[:-4] + ".aiff"
    subprocess.run(["say", "-v", "Sara", "-o", aiff, text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", aiff, path], check=True); os.remove(aiff)
run("apple-sara", apple)

if not only or only & {"piper", "piper-forberedt"}:
    from piper import PiperVoice
    pv = PiperVoice.load(f"{here}/piper-model/da_DK-talesyntese-medium.onnx", espeak_data_dir=espeak)
    def piper(text, path):
        with wave.open(path, "wb") as w: pv.synthesize_wav(text, w)
    run("piper", piper)
    run("piper-forberedt", lambda text, path: piper(normalize(text), path))

if not only or any(o.startswith("plapre") for o in only):
    from plapre_lib import Plapre, SR
    p = Plapre(f"{here}/plapre")
    ref, sr = sf.read(ref_wav, dtype="float32")
    roest = p.clone(ref if ref.ndim == 1 else ref.mean(1))
    json.dump(roest, open(f"{out}/roest-stemme.json", "w"))
    def plapre(speaker, temp):
        def fn(text, path):
            wav, _ = p.synth(normalize(text), speaker, temp, seed=1)
            sf.write(path, wav, SR)
        return fn
    run("plapre-tor-0.7", plapre(p.speakers["tor"], 0.7))
    run("plapre-tor-0.4", plapre(p.speakers["tor"], 0.4))
    run("plapre-tor-0.0", plapre(p.speakers["tor"], 0.0))
    run("plapre-roeststemme-0.4", plapre(roest, 0.4))
