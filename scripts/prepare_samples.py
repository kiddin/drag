"""Builds Resources/Samples/<material>.wav from CC0 drag recordings (see Resources/Samples/CREDITS.md).

Keeps only the steady dragging parts of each recording (no pauses, no stray knocks), joins them
with short crossfades, removes rumble below 40 Hz and evens out loudness. The app plays these as
grains at a rate that follows the window speed.

usage: python3 scripts/prepare_samples.py <dir with 48 kHz mono 16-bit wavs> Resources/Samples
"""
import sys, wave, os
import numpy as np

SOURCES = {  # material: (file, max seconds kept)
    "wood": ("wood-furniture", 12),
    "metal": ("metal-stool", 12),
    "stone": ("stone-slab", 12),
    "glass": ("glass-bowl", 12),
    "rubber": ("rubber-box", 12),
}
SR = 48000

def load(p):
    w = wave.open(p)
    assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, p
    return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768

def highpass(x, fc=40.0):
    # 2nd-order Butterworth (RBJ), run forward and backward for zero phase
    w0 = 2 * np.pi * fc / SR; a = np.sin(w0) / (2 * 0.7071); c = np.cos(w0)
    b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b = np.array([b0, b1, b2]) / a0; aa = np.array([a1, a2]) / a0
    def run(s):
        y = np.zeros_like(s); x1 = x2 = y1 = y2 = 0.0
        for i, v in enumerate(s):
            o = b[0] * v + b[1] * x1 + b[2] * x2 - aa[0] * y1 - aa[1] * y2
            x2, x1, y2, y1 = x1, v, y1, o; y[i] = o
        return y
    return run(run(x)[::-1])[::-1]

def steady_runs(x, min_len=0.4):
    hop = SR // 20  # 50 ms frames
    n = len(x) // hop
    db = np.array([10 * np.log10((x[i*hop:(i+1)*hop] ** 2).mean() + 1e-12) for i in range(n)])
    db = np.convolve(db, np.ones(3) / 3, mode="same")
    ref = np.percentile(db, 90)
    on = db > ref - 9
    # a frame much louder than its neighbours is a knock, not dragging
    spike = db > np.convolve(db, np.ones(9) / 9, mode="same") + 8
    on &= ~spike
    runs, start = [], None
    for i, v in enumerate(list(on) + [False]):
        if v and start is None: start = i
        if not v and start is not None:
            if (i - start) * hop >= min_len * SR: runs.append((start * hop, i * hop))
            start = None
    return runs

def main(src, dst):
    fade = int(0.02 * SR)
    credits = []
    for material, (name, cap) in SOURCES.items():
        x = highpass(load(os.path.join(src, name + ".wav")))
        runs = steady_runs(x)
        out = np.zeros(0)
        for a, b in runs:
            seg = x[a:b].copy()
            if len(out) == 0:
                out = seg
            else:
                r = np.linspace(0, 1, fade)
                out = np.concatenate([out[:-fade], out[-fade:] * np.sqrt(1 - r) + seg[:fade] * np.sqrt(r), seg[fade:]])
            if len(out) >= cap * SR: break
        out = out[: cap * SR]
        r = np.linspace(0, 1, fade)
        out[:fade] *= r; out[-fade:] *= r[::-1]
        out *= 10 ** (-20 / 20) / np.sqrt((out ** 2).mean())   # -20 dBFS RMS
        out = np.clip(out, -1, 1)
        with wave.open(os.path.join(dst, material + ".wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((out * 32767).astype("<i2").tobytes())
        print(f"{material:7s} from {name:15s} {len(runs):3d} runs -> {len(out)/SR:5.1f}s  "
              + ", ".join(f"{a/SR:.1f}-{b/SR:.1f}" for a, b in runs[:8]) + (" ..." if len(runs) > 8 else ""))

main(sys.argv[1], sys.argv[2])
