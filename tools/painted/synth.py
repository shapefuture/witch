#!/usr/bin/env python3
"""Synthesises the toy box's sound effects: tools/painted/synth.py -> assets/painted/sfx/*.wav

    python tools/painted/synth.py [--out assets/painted/sfx]

Every sound is a short numpy recipe (oscillators, noise, envelopes, a one-pole filter), 22.05 kHz mono 16-bit,
seeded by its own name, so running it twice writes identical bytes. Names are the vocabulary of props.json's
"sound" slots (game/world/painted/painted_prop.gd, painted_sfx.gd):

  blip     a tiny two-note question          thunk    a muffled wooden knock
  chime    three glassy bell partials        creak    a pitched, wobbling groan
  rattle   a burst of small clacks           boing    a spring: pitch bends down then back up
  tick     a dry clock click                 sparkle  quick high bells, falling
  ping     the fallback: a soft round blip   whoosh   filtered noise that sweeps up and down
"""
import argparse
import sys
import wave
import zlib
from pathlib import Path

import numpy as np

RATE = 22050
ROOT = Path(__file__).resolve().parents[2]


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(t, attack=0.004, decay=0.1):
    """Linear attack, exponential decay."""
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def lowpass(x, cutoff):
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def sine(freq, t, phase=0.0):
    return np.sin(2.0 * np.pi * freq * t + phase)


def swept(f0, f1, t, curve=1.0):
    """A sine whose frequency glides from f0 to f1 over the whole of t (phase integrated, so no clicks)."""
    u = (t / t[-1]) ** curve
    freq = f0 + (f1 - f0) * u
    return np.sin(2.0 * np.pi * np.cumsum(freq) / RATE)


def blip():
    t = t_axis(0.16)
    first = sine(660, t) * (t < 0.07) * env(t, decay=0.05)
    t2 = np.clip(t - 0.07, 0, None)
    second = sine(990, t2) * (t >= 0.07) * env(t2, decay=0.06)
    return 0.6 * (first + second)


def thunk():
    t = t_axis(0.22)
    body = swept(170, 62, t, 0.5) * env(t, 0.002, 0.06)
    knock = lowpass(rng_for("thunk").standard_normal(t.size), 600) * env(t, 0.001, 0.012)
    return 0.9 * body + 0.35 * knock


def chime():
    t = t_axis(0.7)
    out = np.zeros_like(t)
    for freq, gain, decay in ((880, 1.0, 0.26), (1320, 0.55, 0.2), (2217, 0.3, 0.12)):
        out += gain * sine(freq, t) * env(t, 0.002, decay)
    return 0.4 * out


def creak():
    t = t_axis(0.5)
    wobble = 1.0 + 0.09 * sine(23, t) + 0.05 * sine(7, t)
    freq = (150 + 90 * (t / t[-1])) * wobble
    saw = ((np.cumsum(freq) / RATE) % 1.0) * 2.0 - 1.0
    grit = lowpass(rng_for("creak").standard_normal(t.size), 1200) * 0.2
    shape = np.minimum(t / 0.05, 1.0) * np.minimum((t[-1] - t) / 0.15, 1.0)
    return 0.6 * lowpass(lowpass(saw, 800), 800) * shape + 0.25 * grit * shape


def rattle():
    t = t_axis(0.38)
    rng = rng_for("rattle")
    out = np.zeros_like(t)
    for k in range(9):
        start = 0.012 + k * 0.038 + rng.uniform(-0.006, 0.006)
        tk = np.clip(t - start, 0, None)
        click = lowpass(rng.standard_normal(t.size), rng.uniform(1800, 3200)) * env(tk, 0.0005, 0.008) * (t >= start)
        out += click * (1.0 - 0.07 * k)
    return 0.9 * out


def boing():
    t = t_axis(0.5)
    wob = swept(420, 150, t, 0.4) + 0.0
    bend = 1.0 + 0.5 * np.sin(2.0 * np.pi * 9.0 * t) * np.exp(-t / 0.18)
    freq = (150 + 270 * np.exp(-t / 0.12)) * bend
    tone = np.sin(2.0 * np.pi * np.cumsum(freq) / RATE)
    return 0.6 * tone * env(t, 0.004, 0.2) + 0.1 * wob * env(t, 0.004, 0.08)


def tick():
    t = t_axis(0.07)
    click = lowpass(rng_for("tick").standard_normal(t.size), 4200) * env(t, 0.0004, 0.006)
    return 0.8 * click + 0.4 * sine(1800, t) * env(t, 0.0005, 0.01)


def sparkle():
    t = t_axis(0.55)
    out = np.zeros_like(t)
    for k, freq in enumerate((2093, 2637, 3136, 3951, 3136, 2637)):
        start = k * 0.055
        tk = np.clip(t - start, 0, None)
        out += sine(freq, tk) * env(tk, 0.002, 0.09) * (t >= start) * (1.0 - 0.12 * k)
    return 0.22 * out


def ping():
    t = t_axis(0.2)
    return 0.45 * (sine(740, t) * env(t, 0.003, 0.07) + 0.3 * sine(1480, t) * env(t, 0.003, 0.03))


def whoosh():
    t = t_axis(0.45)
    noise = rng_for("whoosh").standard_normal(t.size)
    sweep = np.sin(np.pi * t / t[-1]) ** 1.5
    cutoffs = (350.0, 900.0, 1800.0, 3200.0)
    bands = [lowpass(noise, c) for c in cutoffs]
    # Crossfade between the fixed filters as the sweep rises and falls: a moving cutoff without filter state resets.
    pos = sweep * (len(cutoffs) - 1)
    out = np.zeros_like(t)
    for i, band in enumerate(bands):
        out += band * np.clip(1.0 - np.abs(pos - i), 0.0, 1.0)
    return 0.9 * out * sweep


RECIPES = {"blip": blip, "thunk": thunk, "chime": chime, "creak": creak, "rattle": rattle, "boing": boing,
           "tick": tick, "sparkle": sparkle, "ping": ping, "whoosh": whoosh}


def to_pcm(x, peak=0.8):
    x = x - x.mean()
    x = x / max(np.abs(x).max(), 1e-6) * peak
    fade = min(int(0.004 * RATE), x.size // 4)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return (x * 32767.0).astype("<i2")


def write_wav(path, pcm):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default=str(ROOT / "assets" / "painted" / "sfx"))
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, recipe in RECIPES.items():
        pcm = to_pcm(recipe())
        write_wav(out / ("%s.wav" % name), pcm)
        total += pcm.nbytes + 44
        print("%-8s %.2f s  %5.1f KB" % (name, pcm.size / RATE, (pcm.nbytes + 44) / 1024))
    print("total %.1f KB" % (total / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
