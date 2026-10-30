#!/usr/bin/env python3
"""Generates tileable detail textures for SUMMIT (snow/rock normals, rock albedo, noise, particles).
Usage: python3 -I gen_textures.py <project_dir>"""
import os
import sys

import numpy as np
from PIL import Image


class PeriodicPerlin:
    def __init__(self, seed, period):
        rng = np.random.default_rng(seed)
        self.period = period
        ang = rng.uniform(0, 2 * np.pi, (period, period))
        self.gx = np.cos(ang)
        self.gy = np.sin(ang)

    def __call__(self, x, y):
        P = self.period
        x0 = np.floor(x).astype(np.int64)
        y0 = np.floor(y).astype(np.int64)
        xf = x - x0
        yf = y - y0
        xi = x0 % P
        yi = y0 % P
        xi1 = (xi + 1) % P
        yi1 = (yi + 1) % P

        def g(ix, iy, dx, dy):
            return self.gx[iy, ix] * dx + self.gy[iy, ix] * dy
        n00 = g(xi, yi, xf, yf)
        n10 = g(xi1, yi, xf - 1, yf)
        n01 = g(xi, yi1, xf, yf - 1)
        n11 = g(xi1, yi1, xf - 1, yf - 1)
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        a = n00 + (n10 - n00) * u
        b = n01 + (n11 - n01) * u
        return (a + (b - a) * v) * 1.414


def fbm(size, base_period, octaves, seed, gain=0.5, ridged=False):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    out = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    period = base_period
    for o in range(octaves):
        p = PeriodicPerlin(seed + o * 17, period)
        n = p(xx / size * period, yy / size * period)
        if ridged:
            n = 1.0 - np.abs(n)
            n = n * n
        out += n * amp
        norm += amp
        amp *= gain
        period *= 2
    return out / norm


def to_normal(h, strength):
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nx = -gx
    ny = -gy
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def save(arr, path, mode):
    Image.fromarray(arr, mode).save(path)
    print("wrote", path)


def main():
    proj = sys.argv[1]
    out = os.path.join(proj, "assets", "textures")
    os.makedirs(out, exist_ok=True)
    S = 512
    # snow: soft wind ripples + fine grain
    ripple = fbm(S, 4, 5, 100)
    yy, xx = np.mgrid[0:S, 0:S] / S
    waves = np.sin((xx * 12 + ripple * 2.2) * 2 * np.pi) * 0.25
    grain = fbm(S, 32, 3, 200)
    snow_h = ripple * 1.0 + waves * 0.35 + grain * 0.25
    save(to_normal(snow_h, 40.0), os.path.join(out, "snow_normal.png"), "RGB")
    # rock: strata + cracks + lumps
    lumps = fbm(S, 4, 6, 300)
    cracks = fbm(S, 8, 4, 400, ridged=True)
    strata = np.sin((yy * 9 + lumps * 1.5) * 2 * np.pi) * 0.5 + 0.5
    rock_h = lumps * 1.0 + cracks * 0.6 + strata * 0.25
    save(to_normal(rock_h, 90.0), os.path.join(out, "rock_normal.png"), "RGB")
    tone = fbm(S, 8, 5, 500)
    base = np.stack([0.50 + 0.08 * tone, 0.47 + 0.07 * tone, 0.44 + 0.06 * tone], axis=-1)
    shade = (0.75 + 0.45 * (lumps - lumps.min()) / (np.ptp(lumps) + 1e-6))[..., None]
    crack_dark = (1.0 - 0.45 * np.clip((cracks - 0.55) * 3.0, 0, 1))[..., None]
    band = (0.92 + 0.12 * strata)[..., None]
    lichen = np.clip((fbm(S, 16, 3, 600) - 0.25) * 4.0, 0, 1)[..., None] * np.array([0.05, 0.03, -0.02])
    rock = np.clip(base * shade * crack_dark * band + lichen, 0, 1)
    save((rock * 255).astype(np.uint8), os.path.join(out, "rock_albedo.png"), "RGB")
    # multi-purpose noise (4 independent channels)
    chans = []
    for i, per in enumerate([4, 8, 16, 32]):
        c = fbm(S, per, 4, 700 + i * 31)
        c = (c - c.min()) / (np.ptp(c) + 1e-6)
        chans.append(c)
    save((np.stack(chans, axis=-1) * 255).astype(np.uint8), os.path.join(out, "noise.png"), "RGBA")
    # bark and needles for trees
    bark = fbm(256, 4, 5, 900)
    stripes = np.sin((np.mgrid[0:256, 0:256][1] / 256 * 24 + bark * 3) * 2 * np.pi) * 0.5 + 0.5
    b = np.stack([0.30 + 0.1 * stripes, 0.22 + 0.07 * stripes, 0.16 + 0.05 * stripes], axis=-1) * (0.8 + 0.3 * bark[..., None])
    save((np.clip(b, 0, 1) * 255).astype(np.uint8), os.path.join(out, "bark.png"), "RGB")
    # soft particle sprite (snow puff)
    r = np.sqrt(((np.mgrid[0:128, 0:128][0] - 63.5) / 63.5) ** 2 + ((np.mgrid[0:128, 0:128][1] - 63.5) / 63.5) ** 2)
    puff_n = fbm(128, 4, 4, 1000)
    alpha = np.clip(1.0 - r, 0, 1) ** 1.6 * (0.75 + 0.5 * puff_n)
    sprite = np.stack([np.ones_like(alpha), np.ones_like(alpha), np.ones_like(alpha), np.clip(alpha, 0, 1)], axis=-1)
    save((sprite * 255).astype(np.uint8), os.path.join(out, "puff.png"), "RGBA")
    # small hard flake
    flake = np.clip(1.0 - r * 1.6, 0, 1) ** 0.8
    fl = np.stack([np.ones_like(flake)] * 3 + [flake], axis=-1)
    save((fl * 255).astype(np.uint8), os.path.join(out, "flake.png"), "RGBA")


if __name__ == "__main__":
    main()
