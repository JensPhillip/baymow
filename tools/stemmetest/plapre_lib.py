"""Plapre 3 via ONNX Runtime (port af elgehelge/plapre-in-a-browser)."""
import json, time
import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

SR = 24000

class Plapre:
    def __init__(self, root, variant="v3-nano"):
        v = f"{root}/{variant}"
        self.root, self.v = root, v
        self.tok = Tokenizer.from_file(f"{v}/tokenizer.json")
        t = self.tok.token_to_id
        self.TEXT, self.AUDIO, self.A0, self.A1 = t("<text>"), t("<audio>"), t("<audio_0>"), t("<audio_12799>")
        self.stops = {t("<eos>")} | ({t("</audio>")} if t("</audio>") is not None else set())
        self.meta = json.load(open(f"{v}/lm/meta.json"))
        self.speakers = json.load(open(f"{v}/speakers.json"))
        cpu = ["CPUExecutionProvider"]
        self.lm = ort.InferenceSession(f"{v}/lm/model.onnx", providers=cpu)
        self.dec = ort.InferenceSession(f"{root}/kanade_decoder.onnx", providers=cpu)
        self.voc = ort.InferenceSession(f"{root}/hift_vocoder.onnx", providers=cpu)
        self.out_names = [o.name for o in self.lm.get_outputs()]

    def clone(self, wav):
        enc = ort.InferenceSession(f"{self.root}/clone_encoder.onnx", providers=["CPUExecutionProvider"])
        raw = enc.run(None, {"waveform": wav.astype(np.float32)[None]})[0].reshape(-1)
        proj = json.load(open(f"{self.v}/speaker_proj.json"))
        hidden = np.array(proj["weight"], dtype=np.float32) @ raw + np.array(proj["bias"], dtype=np.float32)
        return {"raw": raw.tolist(), "hidden": hidden.tolist()}

    def tokens(self, text, speaker, temperature, rng, top_k=50, top_p=0.95, max_tokens=700):
        m, V = self.meta, ort.OrtValue.ortvalue_from_numpy
        ids = [self.TEXT] + self.tok.encode(text, add_special_tokens=False).ids + [self.AUDIO]
        feeds = {"input_ids": V(np.array(ids, dtype=np.int64)), "prefix_embeds": V(np.array(speaker["hidden"], dtype=np.float32)[None])}
        empty = np.zeros((1, m["kvHeads"], 0, m["headDim"]), dtype=np.float32)
        for i in range(m["numLayers"]):
            for k in ("key", "value"):
                feeds[f"past_key_values.{i}.{k}"] = V(empty)
        no_prefix = V(np.zeros((0, m["hidden"]), dtype=np.float32))
        out = []
        for _ in range(max_tokens):
            outs = dict(zip(self.out_names, self.lm.run_with_ort_values(self.out_names, feeds)))
            logits = outs["logits"].numpy()[0, -1]
            if temperature <= 0:
                token = int(logits.argmax())
            else:
                idx = np.argpartition(logits, -top_k)[-top_k:]
                idx = idx[np.argsort(-logits[idx])]
                p = np.exp((logits[idx] - logits[idx[0]]) / temperature); p /= p.sum()
                keep = int(np.searchsorted(np.cumsum(p), top_p)) + 1
                token = int(rng.choice(idx[:keep], p=p[:keep] / p[:keep].sum()))
            if token in self.stops:
                break
            out.append(token)
            feeds = {"input_ids": V(np.array([token], dtype=np.int64)), "prefix_embeds": no_prefix}
            for i in range(m["numLayers"]):
                for k in ("key", "value"):
                    feeds[f"past_key_values.{i}.{k}"] = outs[f"present.{i}.{k}"]
        return out

    def synth(self, text, speaker, temperature=0.7, seed=0):
        """Returnerer (lyd, sekunder brugt). `text` skal være forberedt (tal skrevet ud)."""
        t0 = time.time()
        toks = self.tokens(text, speaker, temperature, np.random.default_rng(seed))
        kan = np.array([t - self.A0 for t in toks if self.A0 <= t <= self.A1], dtype=np.int64)
        if len(kan) == 0:
            return np.zeros(0, dtype=np.float32), time.time() - t0
        mel = self.dec.run(None, {"content_token_indices": kan, "global_embedding": np.array(speaker["raw"], dtype=np.float32)})[0]
        wav = self.voc.run(None, {"mel": mel[None] if mel.ndim == 2 else mel})[0].reshape(-1)
        return wav, time.time() - t0
