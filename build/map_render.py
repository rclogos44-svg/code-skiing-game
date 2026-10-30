#!/usr/bin/env python3
"""Renders the in-game mountain map (project/world/map.png) from the generated world files, in the
style of a painted winter trail map: blue-shadowed snow relief lit from the north-west, stippled
forest with individual trees, rock strata on steep faces, frozen lakes, contour lines.
Also finds the named summits shown on the map and stores them in layout.json ("peaks").

usage: map_render.py <project dir> [size]
"""
import json
import math
import os
import sys

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image, ImageDraw, ImageFilter

PEAK_NAMES = ["Pic Blanc", "Grand Givre", "Dent du Loup", "Corne Noire", "Tete Rousse", "Pointe Bleue",
              "Le Clocher", "Aiguille Grise", "Mont Sable", "Crete des Aigles"]


def load(proj):
    w = os.path.join(proj, "world")
    lay = json.load(open(os.path.join(w, "layout.json")))
    m = lay["meta"]
    n = int(m["n"])
    raw = np.fromfile(os.path.join(w, "height16.bin"), dtype=">u2").astype(np.float32)
    H = raw.reshape(n, n) * float(m["core_scale"]) + float(m["core_min"])
    surface = np.asarray(Image.open(os.path.join(w, "surface.png")).convert("RGBA"), dtype=np.float32) / 255.0
    bake = np.asarray(Image.open(os.path.join(w, "bake.png")).convert("RGBA"), dtype=np.float32) / 255.0
    trees = np.fromfile(os.path.join(w, "trees.bin"), dtype="<f4").reshape(-1, 4)
    return lay, H, surface, bake, trees


def resize(a, size):
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((size, size), Image.BILINEAR), dtype=np.float32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def max_filter(a, r):
    p = np.pad(a, r, mode="edge")
    rows = sliding_window_view(p, 2 * r + 1, axis=1).max(axis=-1)
    return sliding_window_view(rows, 2 * r + 1, axis=0).max(axis=-1)


def find_peaks(H, world, lay, count=8):
    s = 8
    Hs = H[::s, ::s]
    cell = world / (Hs.shape[0] - 1)
    r = int(round(320.0 / cell))
    mx = max_filter(Hs, r)
    cand = np.argwhere((Hs >= mx - 1e-3))
    # prominence-ish: summit must stand clearly above the ring 300 m around it
    out = []
    ring = int(round(300.0 / cell))
    edge = int(round(220.0 / cell))
    for (i, j) in cand:
        if i < edge or j < edge or i >= Hs.shape[0] - edge or j >= Hs.shape[1] - edge:
            continue
        h = float(Hs[i, j])
        samples = []
        for k in range(16):
            a = k * math.tau / 16
            ii = int(round(i + math.sin(a) * ring))
            jj = int(round(j + math.cos(a) * ring))
            if 0 <= ii < Hs.shape[0] and 0 <= jj < Hs.shape[1]:
                samples.append(float(Hs[ii, jj]))
        if not samples or h - max(samples) < 12.0 or h - float(np.mean(samples)) < 60.0:
            continue
        out.append((h, j * cell, i * cell))
    out.sort(reverse=True)
    peaks = []
    for h, x, z in out:
        if any(math.hypot(x - p["x"], z - p["z"]) < 650.0 for p in peaks):
            continue
        if math.hypot(x - lay["village"]["x"], z - lay["village"]["z"]) < 500.0:
            continue
        peaks.append({"name": PEAK_NAMES[len(peaks)], "x": round(x, 1), "z": round(z, 1), "y": round(h, 1)})
        if len(peaks) >= count:
            break
    return peaks


def hillshade(gx, gz, az_deg, alt_deg):
    az = math.radians(az_deg)
    alt = math.radians(alt_deg)
    # light direction in map space (x right, z down); azimuth measured clockwise from north (-z)
    lx, lz, ly = math.sin(az) * math.cos(alt), -math.cos(az) * math.cos(alt), math.sin(alt)
    nrm = np.sqrt(gx * gx + gz * gz + 1.0)
    return np.clip((-gx * lx - gz * lz + ly) / nrm, 0.0, 1.0)


def render(proj, size=2048):
    lay, H, surface, bake, trees = load(proj)
    world = float(lay["meta"]["world_size"])
    px = world / size
    Hm = resize(H, size)
    gz, gx = np.gradient(Hm, px)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    # exaggerated multi-directional hillshade (classic cartographic NW light)
    ex = 1.35
    shade = (0.55 * hillshade(gx * ex, gz * ex, 315, 40) + 0.25 * hillshade(gx * ex, gz * ex, 275, 50)
             + 0.20 * hillshade(gx * ex, gz * ex, 355, 55))
    shade = np.clip((shade - 0.25) / 0.72, 0.0, 1.0)
    sv = resize(bake[..., 0], size)            # baked sun visibility (long shadows of the game sun)
    ao = resize(bake[..., 1], size)
    rock = resize(bake[..., 2], size)
    lake = np.clip(1.0 - resize(bake[..., 3], size), 0.0, 1.0)
    tree_d = resize(surface[..., 3], size)
    groomed = resize(surface[..., 1], size)
    alt = np.clip((Hm - 350.0) / 1500.0, 0.0, 1.0)

    # --- snow: blue shadows, warm highlights, slightly greyer valley floors
    light = shade * (0.9 + 0.1 * sv) * (0.82 + 0.18 * ao)
    shadow_col = np.array([0.56, 0.66, 0.82])
    mid_col = np.array([0.80, 0.86, 0.93])
    lit_col = np.array([1.00, 0.99, 0.965])
    t = light[..., None]
    snow = np.where(t < 0.55, shadow_col + (mid_col - shadow_col) * (t / 0.55),
                    mid_col + (lit_col - mid_col) * ((t - 0.55) / 0.45))
    valley = np.array([0.86, 0.89, 0.90])
    snow = snow * (0.88 + 0.12 * alt[..., None]) + valley * 0.12 * (1.0 - alt[..., None]) * t
    col = snow

    # --- groomed snow: a touch smoother and brighter
    col = col * (1 - groomed[..., None] * 0.15) + np.array([0.93, 0.96, 1.0]) * groomed[..., None] * 0.15

    # --- rock: warm grey, strata lines that follow the contours on steep faces
    strata = 0.93 + 0.07 * np.sin(Hm / 14.0 * math.tau + np.sin(Hm * 0.031) * 1.5)
    rock_col = np.array([0.66, 0.63, 0.62]) * (0.68 + 0.42 * shade[..., None]) * strata[..., None]
    rk = np.clip(rock * 1.1, 0.0, 0.85) * smoothstep(30.0, 46.0, slope)
    col = col * (1 - rk[..., None]) + rock_col * rk[..., None]

    # --- forest floor tint under the trees
    fl = np.clip(tree_d * 1.4, 0.0, 1.0)[..., None]
    col = col * (1 - fl * 0.45) + np.array([0.48, 0.60, 0.55]) * (0.6 + 0.4 * shade[..., None]) * fl * 0.45

    # --- frozen lakes
    ice = np.array([0.70, 0.85, 0.94])
    lk = smoothstep(0.35, 0.65, lake)[..., None]
    col = col * (1 - lk) + ice * (0.92 + 0.08 * shade[..., None]) * lk
    rim = (smoothstep(0.15, 0.4, lake) - smoothstep(0.4, 0.7, lake))[..., None]
    col = col * (1 - rim * 0.45) + np.array([0.30, 0.50, 0.68]) * rim * 0.45

    # --- contours: 50 m, index every 250 m, anti-aliased by the local gradient
    grad_px = np.hypot(gx, gz) * px + 1e-4
    steep_fade = 1.0 - smoothstep(48.0, 62.0, slope)

    def contour(interval, width):
        f = Hm / interval
        d = np.abs(f - np.round(f)) * interval / grad_px
        return np.clip(1.0 - d / width, 0.0, 1.0) * steep_fade

    c_minor = contour(50.0, 0.7)
    c_index = contour(250.0, 1.1)
    line_col = np.array([0.30, 0.38, 0.52])
    a = (c_minor * 0.2 + c_index * 0.42)[..., None] * (1 - lk)
    col = col * (1 - a) + line_col * a

    img = Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")

    # --- individual trees: drop shadow to the SE, dark crown, lit NW edge (drawn at 2x, then reduced)
    ss = 2
    big = img.resize((size * ss, size * ss), Image.BILINEAR)
    shadow = Image.new("L", big.size, 0)
    crowns = Image.new("L", big.size, 0)
    hl = Image.new("L", big.size, 0)
    ds, dc, dh = ImageDraw.Draw(shadow), ImageDraw.Draw(crowns), ImageDraw.Draw(hl)
    k = ss / px
    for x, z, sc, _r in trees:
        cx, cz = x * k, z * k
        r = (1.5 + 0.6 * sc) * ss
        ds.ellipse([cx - r + 1.2 * ss, cz - r + 1.2 * ss, cx + r + 1.2 * ss, cz + r + 1.2 * ss], fill=110)
        dc.ellipse([cx - r, cz - r, cx + r, cz + r], fill=255)
        rh = r * 0.45
        dh.ellipse([cx - r * 0.35 - rh, cz - r * 0.35 - rh, cx - r * 0.35 + rh, cz - r * 0.35 + rh], fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(ss * 0.8))
    base = np.asarray(big, dtype=np.float32) / 255.0
    sh = np.asarray(shadow, dtype=np.float32)[..., None] / 255.0
    cr = np.asarray(crowns, dtype=np.float32)[..., None] / 255.0
    hh = np.asarray(hl, dtype=np.float32)[..., None] / 255.0
    base = base * (1 - sh * 0.55) + np.array([0.22, 0.30, 0.42]) * sh * 0.55
    base = base * (1 - cr) + np.array([0.13, 0.27, 0.21]) * cr
    base = base * (1 - hh * 0.6) + np.array([0.33, 0.50, 0.38]) * hh * 0.6
    img = Image.fromarray((np.clip(base, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS)

    # --- fine paper grain and a soft frame at the world edge
    rgb = np.asarray(img, dtype=np.float32) / 255.0
    rng = np.random.default_rng(7)
    grain = rng.normal(0.0, 0.012, (size, size, 1)).astype(np.float32)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) * px
    edge_d = np.minimum(np.minimum(xx, world - xx), np.minimum(yy, world - yy))
    frame = 1.0 - 0.18 * (1.0 - smoothstep(0.0, 260.0, edge_d))
    rgb = np.clip((rgb + grain) * frame[..., None], 0, 1)
    out = os.path.join(proj, "world", "map.png")
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").save(out, optimize=True)

    lay["peaks"] = find_peaks(H, world, lay)
    with open(os.path.join(proj, "world", "layout.json"), "w") as f:
        json.dump(lay, f, indent=1)
    return out, lay["peaks"]


if __name__ == "__main__":
    proj = sys.argv[1]
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 2048
    out, peaks = render(proj, size)
    print("map ->", out)
    for p in peaks:
        print("  peak %-16s %6.0f m at (%.0f, %.0f)" % (p["name"], p["y"], p["x"], p["z"]))
