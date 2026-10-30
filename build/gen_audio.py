#!/usr/bin/env python3
"""Procedural sound effects for SUMMIT (original, generated from noise and oscillators).
Usage: python3 -I gen_audio.py <project_dir>"""
import os
import sys
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(2024)


def write(path, x, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", path, "%.2fs" % (len(x) / SR))


def shaped_noise(seconds, shape):
    """Periodic noise with a spectral shape function shape(freq_hz) -> amplitude (seamless loop)."""
    n = int(seconds * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec *= shape(f)
    return np.fft.irfft(spec, n)


def band(f, lo, hi, slope=2.0):
    return 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** slope) / (1.0 + (f / hi) ** slope)


def periodic_lfo(n, cycles, phase=0.0):
    t = np.arange(n) / n
    return np.sin(2 * np.pi * (cycles * t + phase))


def env(n, a, d, curve=3.0):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4) * curve / 3.0)
    return e


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def tone(freq, seconds, harmonics=(1.0, 0.4, 0.2), decay=1.2):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k, a in enumerate(harmonics):
        x += a * np.sin(2 * np.pi * freq * (k + 1) * t) * np.exp(-t * decay * (1 + k * 0.6))
    return x * np.minimum(t / 0.004, 1.0)


def main():
    out = os.path.join(sys.argv[1], "assets", "audio")
    os.makedirs(out, exist_ok=True)
    # ---------------- loops (FFT-shaped noise is periodic -> seamless)
    n = 6 * SR
    w = shaped_noise(6, lambda f: band(f, 60, 700, 1.5) + 0.25 * band(f, 900, 2500, 2))
    gust = 0.55 + 0.3 * periodic_lfo(n, 2, 0.1) + 0.15 * periodic_lfo(n, 5, 0.6)
    write(os.path.join(out, "wind_loop.wav"), w * gust)
    n = 4 * SR
    s = shaped_noise(4, lambda f: band(f, 1800, 7000, 2.0))
    crackle = 1.0 + 0.25 * shaped_noise(4, lambda f: band(f, 8, 40, 2))
    write(os.path.join(out, "slide_loop.wav"), s * crackle)
    n = 3 * SR
    c = shaped_noise(3, lambda f: band(f, 900, 4500, 3.0) + 0.6 * band(f, 2200, 2900, 6.0))
    chatter = 1.0 + 0.45 * np.abs(shaped_noise(3, lambda f: band(f, 25, 90, 3)))
    write(os.path.join(out, "carve_loop.wav"), c * chatter)
    n = 4 * SR
    p = shaped_noise(4, lambda f: band(f, 120, 900, 2.0))
    write(os.path.join(out, "powder_loop.wav"), p * (0.8 + 0.2 * periodic_lfo(n, 3)))
    n = 3 * SR
    ice = shaped_noise(3, lambda f: band(f, 2500, 9000, 2.0) + 0.5 * band(f, 4000, 4600, 8.0))
    rattle = 1.0 + 0.6 * np.abs(shaped_noise(3, lambda f: band(f, 30, 120, 3)))
    write(os.path.join(out, "ice_loop.wav"), ice * rattle)
    n = 12 * SR
    amb = shaped_noise(12, lambda f: band(f, 40, 400, 1.5)) * (0.6 + 0.4 * periodic_lfo(n, 1, 0.3) * periodic_lfo(n, 3))
    amb += 0.15 * shaped_noise(12, lambda f: band(f, 3000, 9000, 2.0))
    write(os.path.join(out, "ambient_loop.wav"), amb, 0.6)
    # ---------------- one-shots
    def noise(sec):
        return rng.standard_normal(int(sec * SR))
    # jump: short upward whoosh + ski click
    x = lowpass(noise(0.35), 2500) * env(int(0.35 * SR), 0.03, 0.25)
    x[:600] += np.sin(np.arange(600) * 0.9) * np.exp(-np.arange(600) / 120) * 2.0
    write(os.path.join(out, "jump.wav"), x)
    # landings
    for name, sec, thump_f, crunch in (("land_soft", 0.45, 70, 0.6), ("land_hard", 0.7, 55, 1.0)):
        nn = int(sec * SR)
        t = np.arange(nn) / SR
        thump = np.sin(2 * np.pi * thump_f * t * (1 - t * 0.6)) * np.exp(-t * 12)
        cr = lowpass(noise(sec), 3000) * env(nn, 0.005, sec * 0.5) * crunch
        write(os.path.join(out, name + ".wav"), thump * 1.5 + cr)
    # crash: thud + tumbling crunches
    nn = int(1.4 * SR)
    t = np.arange(nn) / SR
    x = np.sin(2 * np.pi * 50 * t) * np.exp(-t * 8) * 1.5
    for k in range(6):
        st = int((0.08 + k * 0.17 + rng.uniform(0, 0.05)) * SR)
        ln = int(0.25 * SR)
        if st + ln < nn:
            x[st:st + ln] += lowpass(noise(0.25), 2200) * env(ln, 0.005, 0.15) * (1.0 - k * 0.12)
    write(os.path.join(out, "crash.wav"), x)
    # tree hit: snow puff + wood knock
    nn = int(0.6 * SR)
    t = np.arange(nn) / SR
    x = lowpass(noise(0.6), 4000) * env(nn, 0.01, 0.35) + np.sin(2 * np.pi * 180 * t) * np.exp(-t * 30) * 0.8
    write(os.path.join(out, "tree_hit.wav"), x)
    # pole plant click
    nn = int(0.12 * SR)
    t = np.arange(nn) / SR
    write(os.path.join(out, "pole.wav"), np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 60) + noise(0.12) * np.exp(-t * 80) * 0.3, 0.5)
    # boot steps in snow: a soft compressive crunch (two variants)
    for k in range(2):
        nn = int(0.22 * SR)
        t = np.arange(nn) / SR
        grit = 1.0 + 0.8 * np.abs(lowpass(noise(0.22), 120)) * 3.0
        x = lowpass(noise(0.22), 2600 + 700 * k) * env(nn, 0.012, 0.16) * grit
        x += np.sin(2 * np.pi * (85 + 10 * k) * t) * np.exp(-t * 35) * 0.5
        write(os.path.join(out, "step%d.wav" % k), x, 0.6)
    # ski binding: metallic clack + spring
    nn = int(0.25 * SR)
    t = np.arange(nn) / SR
    x = np.sin(2 * np.pi * 2300 * t) * np.exp(-t * 90) + np.sin(2 * np.pi * 3700 * t) * np.exp(-t * 120) * 0.6
    x[int(0.07 * SR):] += (np.sin(2 * np.pi * 1900 * t[: nn - int(0.07 * SR)]) * np.exp(-t[: nn - int(0.07 * SR)] * 80))
    write(os.path.join(out, "binding.wav"), x + noise(0.25) * np.exp(-t * 100) * 0.3, 0.55)
    # hockey stop: a hard scrape of edges biting the snow
    nn = int(0.9 * SR)
    t = np.arange(nn) / SR
    x = shaped_noise(0.9, lambda f: band(f, 1500, 6500, 2.0) + 0.5 * band(f, 300, 900, 2.0))[:nn]
    x *= env(nn, 0.03, 0.6, 2.0) * (1.0 + 0.4 * np.abs(lowpass(noise(0.9), 60)) * 4.0)
    write(os.path.join(out, "hockey_stop.wav"), x)
    # ui
    nn = int(0.06 * SR)
    t = np.arange(nn) / SR
    write(os.path.join(out, "ui_click.wav"), np.sin(2 * np.pi * 900 * t) * np.exp(-t * 70), 0.5)
    write(os.path.join(out, "ui_hover.wav"), np.sin(2 * np.pi * 1300 * t) * np.exp(-t * 120), 0.25)
    # chimes
    def chord(freqs, sec, gap=0.0, decay=1.6):
        nn = int((sec + gap * len(freqs)) * SR)
        x = np.zeros(nn)
        for i, f in enumerate(freqs):
            tt = tone(f, sec, (1.0, 0.3, 0.12), decay)
            st = int(i * gap * SR)
            x[st:st + len(tt)] += tt
        return x
    write(os.path.join(out, "checkpoint.wav"), chord([880.0, 1318.5], 0.5, 0.07, 4.0), 0.6)
    write(os.path.join(out, "trick.wav"), chord([659.3, 830.6, 987.8], 0.6, 0.05, 3.0), 0.55)
    write(os.path.join(out, "discovery.wav"), chord([523.3, 659.3, 784.0, 1046.5], 1.4, 0.12, 1.5), 0.6)
    write(os.path.join(out, "medal.wav"), chord([523.3, 659.3, 784.0, 1046.5, 1318.5], 1.6, 0.09, 1.2), 0.7)
    write(os.path.join(out, "fail.wav"), chord([392.0, 311.1], 0.7, 0.18, 2.5), 0.5)
    write(os.path.join(out, "beep.wav"), tone(660, 0.18, (1.0, 0.2), 8.0), 0.5)
    write(os.path.join(out, "go.wav"), tone(1320, 0.35, (1.0, 0.25), 5.0), 0.6)


if __name__ == "__main__":
    main()
