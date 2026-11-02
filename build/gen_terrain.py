#!/usr/bin/env python3
"""SUMMIT terrain generator.

Offline, deterministic generation of the mountain world.  Produces:
  project/world/height.bin      float32 heightmap, N x N, 2 m spacing (core playable area)
  project/world/far.bin         float32 heightmap, FAR_N x FAR_N, 32 m spacing (backdrop ring)
  project/world/normal.png      RGB8 normal map of the core heightmap
  project/world/surface.png     RGBA8: R=powder depth, G=groomed piste, B=ice, A=tree density
  project/world/bake.png        RGBA8: R=sun visibility (baked shadow), G=ambient occlusion, B=rock mask, A=unused
  project/world/trees.bin       float32 [x, z, scale, rot] per tree
  project/world/rocks.bin       float32 [x, z, scale, rot] per rock
  project/world/layout.json     regions, points of interest, routes, lifts
Usage: python3 -I gen_terrain.py <project_dir> [--quick]
"""
import json
import math
import os
import sys
import time
import heapq

import numpy as np
from PIL import Image

WORLD = 6144.0
N = 3073                 # core heightmap samples (2 m spacing)
SP = WORLD / (N - 1)
M = 1537                 # erosion grid (4 m spacing)
SPM = WORLD / (M - 1)
FAR_N = 577              # backdrop grid (32 m spacing)
FAR_SP = 32.0
FAR_ORIGIN = -6144.0     # far grid covers [-6144, 12288]
SUN_DIR = np.array([-0.50, 0.71, 0.50])  # direction TOWARDS the sun (x, y, z) - must match game
SUN_DIR = SUN_DIR / np.linalg.norm(SUN_DIR)

QUICK = "--quick" in sys.argv

import ctypes
_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = ctypes.CDLL(os.path.join(_HERE, ".cache", "libterrain.so"))
_fp = np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS")
_bp = np.ctypeslib.ndpointer(dtype=np.uint8, flags="C_CONTIGUOUS")
_LIB.priority_flood.argtypes = [_fp, ctypes.c_int, ctypes.c_int, ctypes.c_float, _bp, ctypes.c_void_p]
_LIB.spl_run.argtypes = [_fp, _fp, _fp, _fp, ctypes.c_int, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_int, _bp, _fp, _fp]
_LIB.thermal_map.argtypes = [_fp, ctypes.c_int, _fp, ctypes.c_float, ctypes.c_int, ctypes.c_float]
_LIB.erode.argtypes = [_fp, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_int, ctypes.c_int] + [ctypes.c_float] * 7 + [ctypes.c_void_p]
_LIB.thermal.argtypes = [_fp, ctypes.c_int, ctypes.c_float, ctypes.c_int, ctypes.c_float]
_LIB.sun_shadow.argtypes = [_fp, ctypes.c_int, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_int, ctypes.c_float, _fp]


def c_flood(H, eps):
    H = np.ascontiguousarray(H, dtype=np.float32)
    out = np.zeros(H.shape, dtype=np.uint8)
    out[0, :] = out[-1, :] = out[:, 0] = out[:, -1] = 1
    _LIB.priority_flood(H, H.shape[1], H.shape[0], eps, out, None)
    return H


def c_erode(H, droplets, seed, radius=3, steps=64, inertia=0.05, cap_f=4.0, min_cap=0.01, erode_s=0.3,
            depo_s=0.3, evap=0.012, grav=4.0, strength=None):
    H = np.ascontiguousarray(H, dtype=np.float32)
    sp = None
    if strength is not None:
        strength = np.ascontiguousarray(strength, dtype=np.float32)
        sp = strength.ctypes.data_as(ctypes.c_void_p)
    _LIB.erode(H, H.shape[0], droplets, seed, radius, steps, inertia, cap_f, min_cap, erode_s, depo_s, evap, grav, sp)
    return H


def c_thermal_map(H, talus_map, cell, iters, rate=0.5):
    H = np.ascontiguousarray(H, dtype=np.float32)
    _LIB.thermal_map(H, H.shape[0], np.ascontiguousarray(talus_map, dtype=np.float32), cell, iters, rate)
    return H


def c_thermal(H, talus, iters, rate=0.5):
    H = np.ascontiguousarray(H, dtype=np.float32)
    _LIB.thermal(H, H.shape[0], talus, iters, rate)
    return H
T0 = time.time()


def log(msg):
    print("[%6.1fs] %s" % (time.time() - T0, msg), flush=True)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- noise
class Perlin:
    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        p = rng.permutation(256).astype(np.int32)
        self.perm = np.concatenate([p, p])
        ang = rng.uniform(0.0, 2.0 * np.pi, 256)
        self.gx = np.cos(ang).astype(np.float32)
        self.gy = np.sin(ang).astype(np.float32)

    def __call__(self, x, y):
        x0 = np.floor(x)
        y0 = np.floor(y)
        xf = (x - x0).astype(np.float32)
        yf = (y - y0).astype(np.float32)
        xi = x0.astype(np.int64) & 255
        yi = y0.astype(np.int64) & 255
        xi1 = (xi + 1) & 255
        yi1 = (yi + 1) & 255
        p = self.perm
        h00 = p[p[xi] + yi]
        h10 = p[p[xi1] + yi]
        h01 = p[p[xi] + yi1]
        h11 = p[p[xi1] + yi1]
        gx, gy = self.gx, self.gy
        n00 = gx[h00] * xf + gy[h00] * yf
        n10 = gx[h10] * (xf - 1) + gy[h10] * yf
        n01 = gx[h01] * xf + gy[h01] * (yf - 1)
        n11 = gx[h11] * (xf - 1) + gy[h11] * (yf - 1)
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        a = n00 + (n10 - n00) * u
        b = n01 + (n11 - n01) * u
        return (a + (b - a) * v) * 1.4142


class Noise:
    """Octave noise built from several independent Perlin instances."""

    def __init__(self, seed, octaves=8):
        self.layers = [Perlin(seed * 131 + i * 7) for i in range(octaves)]
        rng = np.random.default_rng(seed + 999)
        self.offsets = rng.uniform(-1000, 1000, (octaves, 2))
        self.rot = rng.uniform(0, 2 * np.pi, octaves)

    def _coords(self, i, x, y, f):
        c, s = math.cos(self.rot[i]), math.sin(self.rot[i])
        xr = (x * c - y * s) * f + self.offsets[i, 0]
        yr = (x * s + y * c) * f + self.offsets[i, 1]
        return xr, yr

    def fbm(self, x, y, octaves, lac=2.0, gain=0.5):
        total = np.zeros_like(x, dtype=np.float32)
        amp, f, norm = 1.0, 1.0, 0.0
        for i in range(octaves):
            xr, yr = self._coords(i, x, y, f)
            total += self.layers[i](xr, yr) * amp
            norm += amp
            amp *= gain
            f *= lac
        return total / norm

    def ridged(self, x, y, octaves, lac=2.05, gain=2.2, H=1.0, offset=1.0):
        total = np.zeros_like(x, dtype=np.float32)
        weight = np.ones_like(x, dtype=np.float32)
        f = 1.0
        norm = 0.0
        for i in range(octaves):
            xr, yr = self._coords(i, x, y, f)
            s = offset - np.abs(self.layers[i](xr, yr))
            s = s * s * weight
            weight = np.clip(s * gain, 0.0, 1.0)
            w = f ** (-H)
            total += s * w
            norm += w
            f *= lac
        return total / norm


# ---------------------------------------------------------------- world layout
REGIONS = [
    # name, center x, z, sigma, roughness, terrace, bumps, powder, trees, ice, macro talus (deg), local talus (deg)
    dict(id=0, name="Alpine Summit", x=3050, z=1000, s=900, rough=1.0, terr=0.15, bumps=0.6, powder=0.75, trees=0.0, ice=0.35, mt=33.0, lt=40.0),
    dict(id=1, name="Powder Valley", x=3000, z=3150, s=900, rough=0.32, terr=0.0, bumps=0.25, powder=1.0, trees=0.25, ice=0.05, mt=26.0, lt=33.0),
    dict(id=2, name="Pinewood Forest", x=1250, z=4350, s=900, rough=0.45, terr=0.05, bumps=0.55, powder=0.55, trees=1.0, ice=0.05, mt=27.0, lt=35.0),
    dict(id=3, name="Rocky Ridge", x=950, z=1750, s=850, rough=1.0, terr=0.55, bumps=0.8, powder=0.35, trees=0.15, ice=0.55, mt=34.0, lt=46.0),
    dict(id=4, name="Mountain Resort", x=4600, z=4500, s=900, rough=0.35, terr=0.0, bumps=0.3, powder=0.25, trees=0.55, ice=0.15, mt=25.0, lt=32.0),
    dict(id=5, name="Extreme Backcountry", x=5150, z=1550, s=850, rough=1.0, terr=0.6, bumps=0.7, powder=0.85, trees=0.0, ice=0.3, mt=35.0, lt=48.0),
]


def talus_map(W, key, outside=None, X=None, Z=None, outside_deg=36.0):
    deg = region_param(W, key)
    if outside is not None:
        deg = deg * (1 - outside) + outside_deg * outside
    return np.tan(np.radians(deg)).astype(np.float32)

PEAKS = [
    # x, z, height, radius, sharpness
    (3050, 900, 2650, 1700, 1.6),   # Summit main peak
    (2300, 600, 2250, 1000, 1.5),
    (3850, 550, 2350, 1100, 1.5),
    (2650, 1500, 1950, 650, 1.4),
    (5150, 1150, 2450, 1100, 1.5),  # Backcountry
    (5650, 2150, 2050, 900, 1.4),
    (4550, 1750, 1950, 700, 1.4),
    (650, 850, 2100, 800, 1.5),     # Rocky Ridge chain
    (950, 1450, 2000, 650, 1.4),
    (1250, 2050, 1850, 650, 1.4),
    (1450, 2650, 1600, 650, 1.4),
    (5000, 3100, 1650, 1250, 1.35), # Resort mountain
    (5650, 3700, 1400, 900, 1.35),
    (800, 3500, 1250, 1000, 1.3),   # Pinewood hills
    (1900, 4100, 950, 800, 1.3),
    (100, 4900, 1350, 900, 1.4),
    (3950, 2350, 1600, 650, 1.4),   # ridge between valley and resort
    (2050, 2450, 1500, 600, 1.4),   # ridge between pinewood and valley
]

# drainage valleys (polylines, x/z) with width and depth
VALLEYS = [
    dict(pts=[(3000, 1650), (3080, 2400), (3000, 3300), (2860, 4200), (2900, 5200), (2950, 6144), (2950, 9000)], w=900, d=420),
    dict(pts=[(1750, 2900), (1800, 3600), (1650, 4500), (1500, 5400), (1450, 6144), (1400, 9000)], w=650, d=260),
    dict(pts=[(4400, 2600), (4300, 3600), (4380, 4600), (4450, 5400), (4500, 6144), (4550, 9000)], w=650, d=240),
]


def far_peaks():
    """Backdrop mountains outside the playable area."""
    rng = np.random.default_rng(77)
    pk = []
    for _ in range(90):
        x = rng.uniform(-6000, 12200)
        z = rng.uniform(-6000, 12200)
        if -400 < x < 6544 and -400 < z < 6544:
            continue
        # keep the south valley exit lower
        south_open = 1.0 - 0.55 * math.exp(-((x - 3000) / 2500.0) ** 2) * (1.0 if z > 6000 else 0.0)
        h = rng.uniform(1800, 3300) * south_open
        pk.append((x, z, h, rng.uniform(900, 2200), rng.uniform(1.3, 1.7)))
    # walls framing the core (east / west / north edges)
    for i in range(14):
        t = i / 13.0
        pk.append((-250, t * 6144, 1700 + 500 * math.sin(t * 7.0), 900, 1.4))
        pk.append((6400, t * 6144, 1800 + 450 * math.sin(t * 5.0 + 1), 900, 1.4))
        pk.append((t * 6144, -250, 2300 + 400 * math.sin(t * 6.0 + 2), 900, 1.4))
    return pk


ALL_PEAKS = PEAKS + far_peaks()


def seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / L2, 0.0, 1.0)
    cx = ax + t * dx
    cz = az + t * dz
    return np.sqrt((px - cx) ** 2 + (pz - cz) ** 2)


def region_weights(X, Z):
    ws = []
    for r in REGIONS:
        d2 = (X - r["x"]) ** 2 + (Z - r["z"]) ** 2
        ws.append(np.exp(-d2 / (2.0 * r["s"] ** 2)).astype(np.float32) + 1e-6)
    tot = sum(ws)
    return [w / tot for w in ws]


def region_param(W, key):
    return sum(W[i] * REGIONS[i][key] for i in range(len(REGIONS)))


NZ_WARP = Noise(11, 4)
NZ_RIDGE = Noise(23, 9)
NZ_BASE = Noise(37, 6)
NZ_DETAIL = Noise(53, 6)
NZ_MASK = Noise(71, 5)


def macro_height(X, Z, octaves=9):
    """Designed large-scale relief + ridged noise. X,Z world meters (float32 arrays)."""
    X = X.astype(np.float32)
    Z = Z.astype(np.float32)
    # gentle regional tilt: north high, south low
    v = np.clip(Z / WORLD, -0.5, 1.6)
    base = 300.0 + 1250.0 * (1.0 - smoothstep(-0.1, 1.05, v)) ** 1.3
    # massifs, combined with smooth max
    h = base.copy()
    for (px, pz, ph, pr, ps) in ALL_PEAKS:
        d = np.sqrt((X - px) ** 2 + (Z - pz) ** 2) / pr
        cone = ph * np.clip(1.0 - d, 0.0, 1.0) ** ps
        # smooth max (k = 180 m)
        k = 180.0
        hh = np.clip(0.5 + 0.5 * (cone - h) / k, 0.0, 1.0)
        h = h * (1 - hh) + cone * hh + k * hh * (1 - hh)
    # warp coordinates for organic ridges
    wx = NZ_WARP.fbm(X / 2600.0, Z / 2600.0, 4) * 380.0
    wz = NZ_WARP.fbm(X / 2600.0 + 31.7, Z / 2600.0 - 12.3, 4) * 380.0
    Xw = X + wx
    Zw = Z + wz
    # valleys
    for vl in VALLEYS:
        pts = vl["pts"]
        dmin = np.full(X.shape, 1e9, dtype=np.float32)
        for i in range(len(pts) - 1):
            dmin = np.minimum(dmin, seg_dist(Xw, Zw, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]))
        prof = np.clip(1.0 - (dmin / vl["w"]) ** 2, 0.0, 1.0) ** 1.5
        h = h - vl["d"] * prof * smoothstep(250.0, 900.0, h)
    W = region_weights(X, Z)
    rough = region_param(W, "rough")
    # outside the core: rugged backdrop
    outside = 1.0 - smoothstep(0.0, 300.0, np.minimum(np.minimum(X, Z), np.minimum(WORLD - X, WORLD - Z)) + 300.0)
    rough = np.maximum(rough, outside * 0.9)
    elev = smoothstep(350.0, 2300.0, h)
    rid = NZ_RIDGE.ridged(Xw / 1700.0, Zw / 1700.0, octaves)
    rid = (rid - 0.42) / 0.30
    amp = (110.0 + 520.0 * elev) * (0.30 + 0.70 * rough)
    h = h + rid * amp
    # gentle rolling component everywhere (keeps low valleys interesting)
    h = h + NZ_BASE.fbm(Xw / 900.0, Zw / 900.0, 5) * (45.0 + 60.0 * (1.0 - rough))
    return h.astype(np.float32), W


def terrace(h, step, strength, noise):
    """Cliff bands: pushes heights toward stepped benches."""
    hs = h / step + noise
    fl = np.floor(hs)
    fr = hs - fl
    # steep riser between benches
    shaped = fl + smoothstep(0.55, 1.0, fr)
    return h + (shaped * step - noise * step - h) * strength


# ---------------------------------------------------------------- erosion
def bilinear(H, x, y):
    n = H.shape[0]
    x = np.clip(x, 0, n - 1.001)
    y = np.clip(y, 0, n - 1.001)
    ix = x.astype(np.int64)
    iy = y.astype(np.int64)
    fx = x - ix
    fy = y - iy
    h00 = H[iy, ix]
    h10 = H[iy, ix + 1]
    h01 = H[iy + 1, ix]
    h11 = H[iy + 1, ix + 1]
    h = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
    gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
    gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
    return h, gx, gy


def erode(H, droplets, seed=5, batch=60000, steps=48, radius=3, strength_map=None):
    """Vectorised particle hydraulic erosion. H in cell units (height / spacing)."""
    rng = np.random.default_rng(seed)
    n = H.shape[0]
    inertia, cap_f, min_cap = 0.06, 5.0, 0.01
    erode_s, depo_s, evap, grav = 0.35, 0.25, 0.015, 6.0
    # brush
    offs = []
    for oy in range(-radius, radius + 1):
        for ox in range(-radius, radius + 1):
            d = math.sqrt(ox * ox + oy * oy)
            if d <= radius:
                offs.append((ox, oy, radius - d))
    bw = np.array([o[2] for o in offs], dtype=np.float32)
    bw /= bw.sum()
    box = np.array([o[0] for o in offs])
    boy = np.array([o[1] for o in offs])
    done = 0
    while done < droplets:
        k = min(batch, droplets - done)
        done += k
        px = rng.uniform(radius + 1, n - radius - 2, k)
        py = rng.uniform(radius + 1, n - radius - 2, k)
        dx = np.zeros(k)
        dy = np.zeros(k)
        speed = np.ones(k)
        water = np.ones(k)
        sed = np.zeros(k)
        alive = np.ones(k, dtype=bool)
        for _ in range(steps):
            idx = np.nonzero(alive)[0]
            if idx.size == 0:
                break
            x = px[idx]
            y = py[idx]
            h, gx, gy = bilinear(H, x, y)
            ndx = dx[idx] * inertia - gx * (1 - inertia)
            ndy = dy[idx] * inertia - gy * (1 - inertia)
            ln = np.sqrt(ndx * ndx + ndy * ndy)
            ok = ln > 1e-9
            ndx = np.where(ok, ndx / np.maximum(ln, 1e-9), 0)
            ndy = np.where(ok, ndy / np.maximum(ln, 1e-9), 0)
            nx = x + ndx
            ny = y + ndy
            inb = ok & (nx > radius + 1) & (nx < n - radius - 2) & (ny > radius + 1) & (ny < n - radius - 2)
            nh, _, _ = bilinear(H, nx, ny)
            dh = nh - h
            s = sed[idx]
            w = water[idx]
            sp = speed[idx]
            cap = np.maximum(-dh * sp * w * cap_f, min_cap)
            if strength_map is not None:
                ix0 = x.astype(np.int64)
                iy0 = y.astype(np.int64)
                es = strength_map[iy0, ix0]
            else:
                es = 1.0
            depositing = (s > cap) | (dh > 0)
            amt_dep = np.where(dh > 0, np.minimum(dh, s), (s - cap) * depo_s)
            amt_dep = np.where(depositing, amt_dep, 0.0)
            amt_ero = np.where(depositing, 0.0, np.minimum((cap - s) * erode_s * es, -dh))
            amt_ero = np.maximum(amt_ero, 0.0)
            # deposit bilinearly
            ix = x.astype(np.int64)
            iy = y.astype(np.int64)
            fx = x - ix
            fy = y - iy
            if np.any(amt_dep > 0):
                np.add.at(H, (iy, ix), amt_dep * (1 - fx) * (1 - fy))
                np.add.at(H, (iy, ix + 1), amt_dep * fx * (1 - fy))
                np.add.at(H, (iy + 1, ix), amt_dep * (1 - fx) * fy)
                np.add.at(H, (iy + 1, ix + 1), amt_dep * fx * fy)
            # erode with brush
            if np.any(amt_ero > 0):
                cy = np.round(y).astype(np.int64)
                cx = np.round(x).astype(np.int64)
                for j in range(len(bw)):
                    np.add.at(H, (cy + boy[j], cx + box[j]), -amt_ero * bw[j])
            s = s + amt_ero - amt_dep
            sed[idx] = s
            speed[idx] = np.sqrt(np.maximum(sp * sp + (-dh) * grav, 0.0))
            water[idx] = w * (1 - evap)
            px[idx] = nx
            py[idx] = ny
            dx[idx] = ndx
            dy[idx] = ndy
            alive[idx] = inb
    return H


def thermal(H, talus, iters, rate=0.25):
    """Simple thermal erosion: material slides when the slope exceeds talus (cell units)."""
    for _ in range(iters):
        p = np.pad(H, 1, mode="edge")
        c = p[1:-1, 1:-1]
        moved = np.zeros_like(H)
        for oy, ox in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            nb = p[1 + oy:1 + oy + H.shape[0], 1 + ox:1 + ox + H.shape[1]]
            d = c - nb
            ex = np.maximum(d - talus, 0.0) * rate * 0.25
            moved -= ex
            # receive: shift back
            recv = np.roll(np.roll(ex, oy, axis=0), ox, axis=1)
            moved += recv
        H = H + moved
    return H


def blur(A, r):
    """Separable box blur repeated 3x (approx gaussian), r in cells."""
    if r < 1:
        return A
    out = A.astype(np.float32)
    for _ in range(3):
        for axis in (0, 1):
            c = np.cumsum(np.pad(out, [(r + 1, r) if a == axis else (0, 0) for a in range(2)], mode="edge"), axis=axis, dtype=np.float64)
            if axis == 0:
                out = ((c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)).astype(np.float32)
            else:
                out = ((c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)).astype(np.float32)
    return out


def fill_depressions(H, eps):
    """Priority-flood: every cell gets a monotone path to the border."""
    n0, n1 = H.shape
    out = H.copy()
    closed = np.zeros(H.shape, dtype=bool)
    pq = []
    for i in range(n0):
        for j in (0, n1 - 1):
            heapq.heappush(pq, (float(out[i, j]), i, j))
            closed[i, j] = True
    for j in range(1, n1 - 1):
        for i in (0, n0 - 1):
            heapq.heappush(pq, (float(out[i, j]), i, j))
            closed[i, j] = True
    flat = out.ravel()
    cl = closed.ravel()
    nbr = (-n1 - 1, -n1, -n1 + 1, -1, 1, n1 - 1, n1, n1 + 1)
    push = heapq.heappush
    pop = heapq.heappop
    while pq:
        h, i, j = pop(pq)
        base = i * n1 + j
        for d in nbr:
            k = base + d
            if k < 0 or k >= flat.size or cl[k]:
                continue
            kj = k % n1
            if abs(kj - j) > 1:
                continue
            cl[k] = True
            if flat[k] <= h:
                flat[k] = h + eps
            push(pq, (float(flat[k]), k // n1, kj))
    return flat.reshape(H.shape)


def upsample2(A):
    """2x cubic upsample (n -> 2n-1)."""
    def up_axis(a, axis):
        a = np.moveaxis(a, axis, 0)
        n = a.shape[0]
        out = np.empty((2 * n - 1,) + a.shape[1:], dtype=np.float32)
        out[0::2] = a
        p = np.concatenate([a[:1], a, a[-1:]], axis=0)
        out[1::2] = (-p[0:n - 1] + 9 * p[1:n] + 9 * p[2:n + 1] - p[3:n + 2]) / 16.0
        return np.moveaxis(out, 0, axis)
    return up_axis(up_axis(A, 0), 1)


def normals(H, sp):
    gx = np.zeros_like(H)
    gz = np.zeros_like(H)
    gx[:, 1:-1] = (H[:, 2:] - H[:, :-2]) / (2 * sp)
    gz[1:-1, :] = (H[2:, :] - H[:-2, :]) / (2 * sp)
    gx[:, 0] = gx[:, 1]
    gx[:, -1] = gx[:, -2]
    gz[0, :] = gz[1, :]
    gz[-1, :] = gz[-2, :]
    nx = -gx
    ny = np.ones_like(H)
    nz = -gz
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / ln, ny / ln, nz / ln


# ---------------------------------------------------------------- landscape evolution
def design_field(X, Z):
    """Smooth designed relief (no noise): regional tilt + massifs + drainage valleys."""
    X = X.astype(np.float32)
    Z = Z.astype(np.float32)
    v = np.clip(Z / WORLD, -1.0, 2.0)
    base = 300.0 + 1250.0 * (1.0 - smoothstep(-0.1, 1.05, v)) ** 1.3
    h = base.copy()
    for (px, pz, ph, pr, ps) in ALL_PEAKS:
        d = np.sqrt((X - px) ** 2 + (Z - pz) ** 2) / pr
        cone = ph * np.clip(1.0 - d, 0.0, 1.0) ** ps
        k = 180.0
        hh = np.clip(0.5 + 0.5 * (cone - h) / k, 0.0, 1.0)
        h = h * (1 - hh) + cone * hh + k * hh * (1 - hh)
    wx = NZ_WARP.fbm(X / 2600.0, Z / 2600.0, 4) * 650.0
    wz = NZ_WARP.fbm(X / 2600.0 + 31.7, Z / 2600.0 - 12.3, 4) * 650.0
    for vl in VALLEYS:
        pts = vl["pts"]
        dmin = np.full(X.shape, 1e9, dtype=np.float32)
        for i in range(len(pts) - 1):
            dmin = np.minimum(dmin, seg_dist(X + wx, Z + wz, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]))
        prof = np.clip(1.0 - (dmin / vl["w"]) ** 2, 0.0, 1.0) ** 1.5
        h = h - vl["d"] * prof * smoothstep(250.0, 900.0, h)
    return h


def bicubic(G, x, y):
    """Catmull-Rom sample of grid G at fractional cell coords (x = column, y = row)."""
    n0, n1 = G.shape
    x = np.clip(x, 0, n1 - 1.0001)
    y = np.clip(y, 0, n0 - 1.0001)
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = (x - ix).astype(np.float32)
    fy = (y - iy).astype(np.float32)

    def w(t):
        t2 = t * t
        t3 = t2 * t
        return (-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2)
    wx = w(fx)
    wy = w(fy)
    out = np.zeros(x.shape, dtype=np.float32)
    for j in range(4):
        yy = np.clip(iy + j - 1, 0, n0 - 1)
        row = np.zeros(x.shape, dtype=np.float32)
        for i in range(4):
            xx = np.clip(ix + i - 1, 0, n1 - 1)
            row += G[yy, xx] * wx[i]
        out += row * wy[j]
    return out


SPL_N = 513
SPL_DX = (WORLD * 3.0) / (SPL_N - 1)    # 36 m over [-6144, 12288]


def spl_macro(cache_dir):
    path = os.path.join(cache_dir, "spl_%d.npy" % SPL_N)
    if os.path.exists(path) and "--respl" not in sys.argv:
        log("using cached landscape evolution")
        return np.load(path)
    g = FAR_ORIGIN + np.arange(SPL_N, dtype=np.float32) * SPL_DX
    X, Z = np.meshgrid(g, g)
    D = design_field(X, Z)
    n1 = NZ_MASK.fbm(X / 3000.0, Z / 3000.0, 4) * 0.5 + 0.5
    n2 = NZ_BASE.fbm(X / 1500.0 + 40, Z / 1500.0, 4) * 0.5 + 0.5
    n3 = NZ_DETAIL.fbm(X / 900.0 - 70, Z / 900.0 + 13, 3) * 0.5 + 0.5
    U = (np.clip(D / 2600.0, 0.02, 1.25) ** 1.35) * (0.55 + 0.9 * n1) * (0.8 + 0.4 * n3)
    K = 0.02 * (0.7 + 0.6 * n2)
    W = region_weights(X, Z)
    rough = region_param(W, "rough")
    core = ((X > -500) & (X < WORLD + 500) & (Z > -500) & (Z < WORLD + 500)).astype(np.float32)
    kd = 2.0 + 22.0 * (1.0 - rough) * core
    h = D * 0.04 + (n1 - 0.5) * 60.0 + (n3 - 0.5) * 30.0
    outlet = np.zeros(h.shape, dtype=np.uint8)
    outlet[0, :] = outlet[-1, :] = outlet[:, 0] = outlet[:, -1] = 1
    h = np.ascontiguousarray(h, dtype=np.float32)
    area = np.zeros(h.shape, dtype=np.float32)
    iters = 150 if QUICK else 400
    log("landscape evolution stage 1: %d iterations on %d^2" % (iters, SPL_N))
    outside = 1.0 - core
    Uc = np.ascontiguousarray(U, np.float32)
    Kc = np.ascontiguousarray(K, np.float32)
    kdc = np.ascontiguousarray(kd, np.float32)
    no_talus = np.full(h.shape, 50.0, dtype=np.float32)
    _LIB.spl_run(h, Uc, Kc, kdc, SPL_N, SPL_DX, 10.0, 0.5, iters, outlet, area, no_talus)
    # smooth sub-150 m structure (keeps the valley network), scale to real relief, clip extremes
    ci = (np.abs(X - 3000) < 3100) & (np.abs(Z - 3000) < 3100)
    h = blur(h, 3)
    h = h * (2200.0 / float(h[ci].max()))
    h = np.where(h > 2600.0, 2600.0 + (h - 2600.0) * 0.4, h).astype(np.float32)
    tal = talus_map(W, "mt", outside, outside_deg=38.0)
    # vary the critical angle so relaxed slopes do not become uniform planar facets
    tal = (tal * (1.0 + 0.22 * (n3 - 0.5) * 2.0 + 0.12 * (n2 - 0.5) * 2.0)).astype(np.float32)
    log("macro slope clipping")
    h = c_thermal_map(h, tal, SPL_DX, 220, 0.5)
    # re-incise: rivers breach the dams that smoothing created (no closed basins / big flat lakes)
    log("re-incision")
    zero = np.zeros(h.shape, dtype=np.float32)
    h = np.ascontiguousarray(h, dtype=np.float32)
    _LIB.spl_run(h, zero, Kc, kdc, SPL_N, SPL_DX, 1.5, 0.5, 40, outlet, area, tal)
    h = (150.0 + h).astype(np.float32)
    np.save(path, h.astype(np.float32))
    return h.astype(np.float32)


def core_relief(Hspl, X, Z, octaves=8):
    """Macro relief from landscape evolution + ridged detail, at arbitrary world coords."""
    macro = bicubic(Hspl, (X - FAR_ORIGIN) / SPL_DX, (Z - FAR_ORIGIN) / SPL_DX)
    W = region_weights(X, Z)
    rough = region_param(W, "rough")
    outside = 1.0 - smoothstep(0.0, 300.0, np.minimum(np.minimum(X, Z), np.minimum(WORLD - X, WORLD - Z)) + 300.0)
    rough = np.maximum(rough, outside * 0.9)
    wx = NZ_WARP.fbm(X / 900.0, Z / 900.0, 3) * 120.0
    wz = NZ_WARP.fbm(X / 900.0 + 31.7, Z / 900.0 - 12.3, 3) * 120.0
    elev = smoothstep(500.0, 2400.0, macro)
    rid = NZ_RIDGE.ridged((X + wx) / 650.0, (Z + wz) / 650.0, octaves)
    rid = (rid - 0.42) / 0.30
    amp = (8.0 + 28.0 * elev) * (0.3 + 0.7 * rough)
    h = macro + rid * amp
    h = h + NZ_BASE.fbm((X + wx) / 420.0, (Z + wz) / 420.0, 4) * (10.0 + 18.0 * (1.0 - rough))
    return h.astype(np.float32), W


def main():
    proj = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "../project"
    outdir = os.path.join(proj, "world")
    prevdir = os.path.join(os.path.dirname(os.path.abspath(proj)), "previews")
    cache = os.path.join(_HERE, ".cache")
    os.makedirs(outdir, exist_ok=True)
    os.makedirs(prevdir, exist_ok=True)

    Hspl = spl_macro(cache)
    log("SPL range %.0f .. %.0f" % (Hspl.min(), Hspl.max()))

    # ---- erosion-scale grid (4 m)
    g = np.linspace(0, WORLD, M, dtype=np.float32)
    X, Z = np.meshgrid(g, g)
    log("core relief")
    H, W = core_relief(Hspl, X, Z)
    terr = region_param(W, "terr")
    tn = NZ_MASK.fbm(X / 600.0, Z / 600.0, 3) * 0.35
    H = np.where(terr > 0.3, terrace(H, 36.0, (terr - 0.3) * 1.1 * smoothstep(900, 1500, H), tn), H).astype(np.float32)
    log("height range %.0f .. %.0f" % (H.min(), H.max()))

    rough = region_param(W, "rough")
    strength = (0.5 + 0.5 * rough).astype(np.float32)
    drops = 600000 if QUICK else 3500000
    log("hydraulic erosion (%d droplets)" % drops)
    Hc = c_erode(H / SPM, drops, 7, radius=3, steps=80, strength=strength)
    H = Hc * SPM
    log("thermal erosion")
    H = c_thermal_map(H, talus_map(W, "lt"), SPM, 260, 0.5)
    # snow cover smoothing: snow fills gullies on moderate slopes
    nx, ny, nz = normals(H, SPM)
    slope = np.degrees(np.arccos(np.clip(ny, -1, 1)))
    soft = smoothstep(46.0, 28.0, slope) * (1.0 - 0.55 * rough)
    H = H * (1 - soft * 0.7) + blur(H, 3) * soft * 0.7
    log("depression fill")
    before = H.copy()
    H = c_flood(H, 0.02)
    lake = (H - before) > 0.75
    log("filled lakes: %.2f%% of area, max depth %.1f m" % (100.0 * lake.mean(), float((H - before).max())))

    # ---- full res 2 m
    log("upsample to %d" % N)
    H2 = upsample2(H)
    del H, X, Z
    g2 = np.linspace(0, WORLD, N, dtype=np.float32)
    X2, Z2 = np.meshgrid(g2, g2)
    W2 = region_weights(X2, Z2)
    bumps = region_param(W2, "bumps")
    nx, ny, nz = normals(H2, SP)
    slope2 = np.degrees(np.arccos(np.clip(ny, -1, 1)))
    det = NZ_DETAIL.fbm(X2 / 38.0, Z2 / 38.0, 4) * 1.8 + NZ_DETAIL.fbm(X2 / 9.0 + 50, Z2 / 9.0, 3) * 0.25
    H2 = H2 + det * bumps * smoothstep(5.0, 18.0, slope2 + 4.0)

    layout = build_layout(H2, W2)
    log("pistes and features")
    groomed = apply_pistes(H2, layout)
    apply_kickers(H2, layout)

    # ---- far backdrop (32 m)
    log("far backdrop")
    gf = FAR_ORIGIN + np.arange(FAR_N, dtype=np.float32) * FAR_SP
    XF, ZF = np.meshgrid(gf, gf)
    HF, _ = core_relief(Hspl, XF, ZF, octaves=6)
    inside = (XF >= 0) & (XF <= WORLD) & (ZF >= 0) & (ZF <= WORLD)
    ci = np.clip((ZF / SP).round().astype(int), 0, N - 1)
    cj = np.clip((XF / SP).round().astype(int), 0, N - 1)
    HF = np.where(inside, H2[ci, cj], HF).astype(np.float32)
    # blend core edges toward the far map
    fx = (X2 - FAR_ORIGIN) / FAR_SP
    fz = (Z2 - FAR_ORIGIN) / FAR_SP
    hfar, _, _ = bilinear(HF, fx, fz)
    edge = np.minimum(np.minimum(X2, Z2), np.minimum(WORLD - X2, WORLD - Z2))
    eb = smoothstep(160.0, 32.0, edge)
    H2 = (H2 * (1 - eb) + hfar * eb).astype(np.float32)
    HF = np.where(inside, H2[ci, cj], HF).astype(np.float32)
    del hfar, fx, fz, edge, eb

    finalize_layout(layout, H2)

    log("terrain features")
    sys.path.insert(0, _HERE)
    import features
    feats, marks, fmasks = features.apply_features(sys.modules[__name__], H2, layout, lake)
    layout["features"] = feats
    layout["landmarks"] = marks
    log("features: " + ", ".join("%d %s" % (sum(1 for f in feats if f["type"] == t), t) for t in ("cliff", "lip", "gully", "lake", "moguls", "trail")))

    log("surface maps")
    nx, ny, nz = normals(H2, SP)
    slope2 = np.degrees(np.arccos(np.clip(ny, -1, 1)))
    surface, rockmask = surface_maps(H2, W2, slope2, groomed, X2, Z2, fmasks)
    log("baked lighting")
    sunvis, ao = bake_light(H2)
    farvis = bake_far(HF)

    log("vegetation")
    trees = place_trees(H2, slope2, surface, X2, Z2, layout)
    rocks = place_rocks(H2, slope2, W2, X2, Z2, layout, fmasks)
    log("trees: %d  rocks: %d" % (len(trees), len(rocks)))

    log("writing")
    H2.astype("<f4").tofile(os.path.join(outdir, "height.bin"))
    HF.astype("<f4").tofile(os.path.join(outdir, "far.bin"))
    # cell-centred normal map (3072^2, block-compression friendly)
    cx_ = (nx[:-1, :-1] + nx[1:, :-1] + nx[:-1, 1:] + nx[1:, 1:]) * 0.25
    cy_ = (ny[:-1, :-1] + ny[1:, :-1] + ny[:-1, 1:] + ny[1:, 1:]) * 0.25
    cz_ = (nz[:-1, :-1] + nz[1:, :-1] + nz[:-1, 1:] + nz[1:, 1:]) * 0.25
    ln = np.sqrt(cx_ * cx_ + cy_ * cy_ + cz_ * cz_)
    nrm = np.stack([(cx_ / ln * 0.5 + 0.5), (cz_ / ln * 0.5 + 0.5), (cy_ / ln * 0.5 + 0.5)], axis=-1)
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(outdir, "normal.png"), compress_level=6)
    del nrm, cx_, cy_, cz_, ln
    Image.fromarray(surface, "RGBA").save(os.path.join(outdir, "surface.png"))
    lake4 = (np.clip(1.0 - fmasks["lake"][::2, ::2], 0, 1) * 255).astype(np.uint8)
    bake = np.stack([sunvis, ao, rockmask, lake4], axis=-1).astype(np.uint8)
    Image.fromarray(bake, "RGBA").save(os.path.join(outdir, "bake.png"))
    Image.fromarray(farvis, "L").save(os.path.join(outdir, "far_bake.png"))
    np.array(trees, dtype="<f4").tofile(os.path.join(outdir, "trees.bin"))
    np.array(rocks, dtype="<f4").tofile(os.path.join(outdir, "rocks.bin"))
    meta = dict(world_size=WORLD, n=N, spacing=SP, far_n=FAR_N, far_spacing=FAR_SP, far_origin=FAR_ORIGIN,
                min_h=float(H2.min()), max_h=float(H2.max()), sun_dir=[float(v) for v in SUN_DIR],
                surface_n=int(surface.shape[0]), tree_count=len(trees), rock_count=len(rocks))
    layout["meta"] = meta
    with open(os.path.join(outdir, "layout.json"), "w") as f:
        json.dump(layout, f, indent=1)
    # pack heights as 16-bit RG8 texels (portable to WebGL; CPU decodes the same bytes)
    import subprocess
    subprocess.run([sys.executable, "-I", os.path.join(_HERE, "height16.py"), proj], check=True)
    # trail-map image + named peaks (reads the packed heights and the maps written above)
    subprocess.run([sys.executable, "-I", os.path.join(_HERE, "map_render.py"), proj], check=True)
    previews(H2, nx, ny, nz, surface, sunvis, layout, prevdir, trees)
    log("done. height %.1f .. %.1f m" % (H2.min(), H2.max()))


def blur_outside(HF, inside):
    b = blur(HF, 1)
    return np.where(inside, HF, b).astype(np.float32)


# ---------------------------------------------------------------- layout & features
def sample(H, x, z):
    h, _, _ = bilinear(H, np.array([x / SP]), np.array([z / SP]))
    return float(h[0])


def descend_path(H, x, z, length, step=12.0, momentum=0.75, min_grade=0.0):
    """Follows the fall line with momentum (a believable 'natural route')."""
    pts = [(x, z)]
    dx, dz = 0.0, 0.0
    for _ in range(int(length / step)):
        hx, gx, gz = bilinear(H, np.array([x / SP]), np.array([z / SP]))
        gx = float(gx[0]) / SP
        gz = float(gz[0]) / SP
        ln = math.hypot(gx, gz)
        if ln < 1e-5:
            ndx, ndz = dx, dz
        else:
            ndx, ndz = -gx / ln, -gz / ln
        dx = dx * momentum + ndx * (1 - momentum)
        dz = dz * momentum + ndz * (1 - momentum)
        l2 = math.hypot(dx, dz)
        if l2 < 1e-6:
            break
        dx /= l2
        dz /= l2
        x += dx * step
        z += dz * step
        if not (80 < x < WORLD - 80 and 80 < z < WORLD - 80):
            break
        pts.append((x, z))
    return pts



def route(H, start, goal, target_deg, max_deg, grid=12.0, pad=500.0, uphill_pen=60.0):
    """Slope-aware least-cost descent route (Dijkstra on a coarse grid). Returns [(x,z),...]."""
    x0 = max(min(start[0], goal[0]) - pad, 40.0)
    x1 = min(max(start[0], goal[0]) + pad, WORLD - 40.0)
    z0 = max(min(start[1], goal[1]) - pad, 40.0)
    z1 = min(max(start[1], goal[1]) + pad, WORLD - 40.0)
    nx_ = int((x1 - x0) / grid) + 1
    nz_ = int((z1 - z0) / grid) + 1
    gx = x0 + np.arange(nx_) * grid
    gz = z0 + np.arange(nz_) * grid
    GX, GZ = np.meshgrid(gx, gz)
    hh, ddx, ddz = bilinear(H, GX / SP, GZ / SP)
    sl = np.degrees(np.arctan(np.hypot(ddx, ddz) / SP))
    hl = hh.tolist()
    sll = sl.tolist()
    tgt = math.tan(math.radians(target_deg))
    si = (int(round((start[1] - z0) / grid)), int(round((start[0] - x0) / grid)))
    gi = (int(round((goal[1] - z0) / grid)), int(round((goal[0] - x0) / grid)))
    dist = {si: 0.0}
    prev = {}
    pq = [(0.0, si)]
    nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    best_end, best_d = None, 1e18
    while pq:
        d, (i, j) = heapq.heappop(pq)
        if d > dist.get((i, j), 1e18):
            continue
        rem = math.hypot(i - gi[0], j - gi[1]) * grid
        if rem < 30.0:
            best_end = (i, j)
            break
        for di, dj in nb:
            a, b = i + di, j + dj
            if a < 0 or b < 0 or a >= nz_ or b >= nx_:
                continue
            L = grid * (1.41421356 if di and dj else 1.0)
            grade = (hl[i][j] - hl[a][b]) / L
            c = L
            if grade < -0.03:
                c += L * uphill_pen * (-grade)
            s = sll[a][b]
            if s > max_deg:
                c += L * 4.0 * (s - max_deg)
            c += L * 1.5 * ((grade - tgt) / max(tgt, 0.05)) ** 2
            nd = d + c
            if nd < dist.get((a, b), 1e18):
                dist[(a, b)] = nd
                prev[(a, b)] = (i, j)
                heapq.heappush(pq, (nd, (a, b)))
    if best_end is None:
        return [start, goal]
    path = []
    k = best_end
    while k in prev:
        path.append((x0 + k[1] * grid, z0 + k[0] * grid))
        k = prev[k]
    path.append(start)
    path.reverse()
    # smooth (moving average) and resample
    P = np.array(path)
    for _ in range(4):
        P[1:-1] = (P[:-2] + 2 * P[1:-1] + P[2:]) / 4.0
    return [tuple(p) for p in P]

def slope_at(H, x, z):
    _, gx, gz = bilinear(H, np.array([x / SP]), np.array([z / SP]))
    return math.degrees(math.atan(math.hypot(float(gx[0]), float(gz[0])) / SP))


def skiable_near(H, x, z, radius, lo=14.0, hi=32.0):
    """Highest point near (x, z) whose slope and 80 m runout are skiable."""
    best = None
    for r in np.linspace(10.0, radius, 14):
        for a in np.linspace(0, 2 * math.pi, 24, endpoint=False):
            px = x + math.cos(a) * r
            pz = z + math.sin(a) * r
            if not (150 < px < WORLD - 150 and 150 < pz < WORLD - 150):
                continue
            s = slope_at(H, px, pz)
            if s < lo or s > hi:
                continue
            path = descend_path(H, px, pz, 80, step=10.0)
            if any(slope_at(H, q[0], q[1]) > hi + 6 for q in path):
                continue
            h = sample(H, px, pz)
            if best is None or h > best[0]:
                best = (h, px, pz)
    if best is None:
        return x, z
    return best[1], best[2]


def local_max(H, x, z, radius):
    """Highest point within radius (coarse search)."""
    best = (sample(H, x, z), x, z)
    for r in np.linspace(radius / 6, radius, 6):
        for a in np.linspace(0, 2 * math.pi, 16, endpoint=False):
            px = x + math.cos(a) * r
            pz = z + math.sin(a) * r
            if 100 < px < WORLD - 100 and 100 < pz < WORLD - 100:
                h = sample(H, px, pz)
                if h > best[0]:
                    best = (h, px, pz)
    return best[1], best[2]


def region_at(x, z):
    W = region_weights(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
    return int(np.argmax([w[0] for w in W]))


class Analysis:
    """8 m analysis grid: heights, macro slope, region id."""
    def __init__(self, H):
        self.s = 4
        self.H = H[::4, ::4]
        self.sp = SP * 4
        gz, gx = np.gradient(self.H, self.sp)
        self.slope = np.degrees(np.arctan(np.hypot(gx, gz)))
        n = self.H.shape[0]
        g = np.arange(n, dtype=np.float32) * self.sp
        self.X, self.Z = np.meshgrid(g, g)
        W = region_weights(self.X, self.Z)
        self.region = np.argmax(np.stack(W, 0), axis=0)
        # local prominence: height above the 300 m neighbourhood mean
        self.prom = self.H - blur(self.H, 12)

    def best(self, mask, score):
        sc = np.where(mask, score, -1e9)
        i = int(np.argmax(sc))
        if sc.flat[i] <= -1e8:
            return None
        iz, ix = divmod(i, sc.shape[1])
        return float(self.X[iz, ix]), float(self.Z[iz, ix])


def runout_ok(H, x, z, max_deg, length=120.0, A=None):
    pts = descend_path(H, x, z, length, step=8.0)
    if len(pts) < 4:
        return False
    for q in pts[1:]:
        if A is not None:
            iz = min(max(int(round(q[1] / A.sp)), 0), A.slope.shape[0] - 1)
            ix = min(max(int(round(q[0] / A.sp)), 0), A.slope.shape[1] - 1)
            s = A.slope[iz, ix]
        else:
            s = slope_at(H, q[0], q[1])
        if s > max_deg:
            return False
    return True


def build_layout(H, W):
    lay = {"regions": [dict(id=r["id"], name=r["name"], x=r["x"], z=r["z"], s=r["s"]) for r in REGIONS]}
    A = Analysis(H)
    lay["_analysis"] = A
    # Resort village: flattest low spot near the planned base
    vx, vz = 4420.0, 5400.0
    d = np.hypot(A.X - vx, A.Z - vz)
    spot = A.best((d < 450) & (A.slope < 9.0), -A.slope * 30.0 - A.H * 0.3 - d * 0.05)
    base = spot if spot else (vx, vz)
    lifts = []
    names = ["Summit Express", "Eagle Chair", "Pine Glade Lift"]
    bh = sample(H, base[0], base[1])
    ang = np.degrees(np.arctan2(A.X - base[0], -(A.Z - base[1])))   # 0 = north, + = east
    dd = np.hypot(A.X - base[0], A.Z - base[1])
    cand = (np.abs(ang) < 80) & (dd > 900) & (dd < 2600) & (A.slope > 10) & (A.slope < 30) \
        & (A.X > 480) & (A.X < WORLD - 480) & (A.Z > 480)
    used_angles = []
    for nm in names:
        mask = cand.copy()
        for ua in used_angles:
            mask &= np.abs(ang - ua) > 28.0
        top = A.best(mask, A.H - dd * 0.04)
        if top is None:
            continue
        iz, ix = int(round(top[1] / A.sp)), int(round(top[0] / A.sp))
        used_angles.append(float(ang[iz, ix]))
        tx, tz = top
        dirx, dirz = tx - base[0], tz - base[1]
        ln = math.hypot(dirx, dirz)
        bx, bz = base[0] + dirx / ln * 45.0, base[1] + dirz / ln * 45.0
        lifts.append(dict(name=nm, bottom=[bx, bz], top=[tx, tz]))
        log("lift %s: rise %.0f m over %.0f m" % (nm, sample(H, tx, tz) - bh, ln))
    lay["lifts"] = lifts
    lay["village"] = dict(x=base[0], z=base[1])
    # pistes from each lift top down to the village
    pistes = []
    plan = [(0, -1, "green", 11.0, 22.0, "Meadow Way"), (0, 1, "blue", 16.0, 28.0, "Express Run"),
            (1, -1, "red", 21.0, 34.0, "Eagle Ridge"), (1, 1, "black", 27.0, 42.0, "Black Diamond"),
            (2, -1, "blue", 15.0, 28.0, "Pine Glade"), (2, 1, "red", 21.0, 34.0, "Lumberjack")]
    for li, side, diff, tdeg, mdeg, nm in plan:
        lf = lifts[li]
        tx, tz = lf["top"]
        bx, bz = lf["bottom"]
        ang = math.atan2(bz - tz, bx - tx) + side * 0.9
        sx, sz = tx + math.cos(ang) * 50, tz + math.sin(ang) * 50
        pts = route(H, (sx, sz), (bx + side * 70, bz + 40), tdeg, mdeg, grid=12.0, pad=700.0)
        if len(pts) > 15:
            pistes.append(dict(name=nm, difficulty=diff, pts=[[p[0], p[1]] for p in pts], width=30.0 if diff != "black" else 24.0))
    lay["pistes"] = pistes
    # terrain park kickers along the first piste
    kick = []
    if pistes:
        p = pistes[0]["pts"]
        for frac in (0.45, 0.52, 0.59):
            i = int(len(p) * frac)
            a = p[max(i - 1, 0)]
            b = p[min(i + 1, len(p) - 1)]
            kick.append(dict(x=p[i][0], z=p[i][1], dx=b[0] - a[0], dz=b[1] - a[1], size=1.0 + 0.35 * len(kick)))
    lay["kickers"] = kick
    return lay


def apply_pistes(H, lay):
    """Smooth & groom the piste corridors.  Returns groomed mask (0..1)."""
    groomed = np.zeros(H.shape, dtype=np.float32)
    Hs = blur(H, 6)
    for p in lay["pistes"]:
        pts = p["pts"]
        w = p["width"]
        xs = [q[0] for q in pts]
        zs = [q[1] for q in pts]
        x0 = int(max(min(xs) - w * 2, 0) / SP)
        x1 = int(min(max(xs) + w * 2, WORLD) / SP)
        z0 = int(max(min(zs) - w * 2, 0) / SP)
        z1 = int(min(max(zs) + w * 2, WORLD) / SP)
        gx = np.arange(x0, x1 + 1, dtype=np.float32) * SP
        gz = np.arange(z0, z1 + 1, dtype=np.float32) * SP
        PX, PZ = np.meshgrid(gx, gz)
        dmin = np.full(PX.shape, 1e9, dtype=np.float32)
        for i in range(len(pts) - 1):
            dmin = np.minimum(dmin, seg_dist(PX, PZ, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]))
        m = smoothstep(w, w * 0.55, dmin)
        sub = H[z0:z1 + 1, x0:x1 + 1]
        H[z0:z1 + 1, x0:x1 + 1] = sub * (1 - m * 0.8) + Hs[z0:z1 + 1, x0:x1 + 1] * m * 0.8
        groomed[z0:z1 + 1, x0:x1 + 1] = np.maximum(groomed[z0:z1 + 1, x0:x1 + 1], m)
    return groomed


def apply_kickers(H, lay):
    for k in lay["kickers"]:
        dx, dz = k["dx"], k["dz"]
        ln = math.hypot(dx, dz) or 1.0
        dx /= ln
        dz /= ln
        s = k["size"]
        length = 14.0 * s
        height = 2.6 * s
        width = 9.0
        cx, cz = k["x"], k["z"]
        r = int((length + width) / SP) + 2
        ci, cj = int(cz / SP), int(cx / SP)
        for i in range(ci - r, ci + r + 1):
            for j in range(cj - r, cj + r + 1):
                px, pz = j * SP - cx, i * SP - cz
                along = px * dx + pz * dz        # + downhill
                across = -px * dz + pz * dx
                if abs(across) > width or along < -length or along > 3.0:
                    continue
                t = (along + length) / length    # 0 at start .. 1 at lip
                if along <= 0:
                    prof = height * (t ** 1.7)
                else:
                    prof = height * max(0.0, 1.0 - along / 3.0) ** 2
                edge = min(1.0, (width - abs(across)) / 3.0)
                H[i, j] += prof * edge


def surface_maps(H, W, slope, groomed, X, Z, fm=None):
    powder = region_param(W, "powder")
    ice = region_param(W, "ice")
    trees = region_param(W, "trees")
    # convexity (wind exposure) -> wind crust / ice
    lap = blur(H, 4) - H
    convex = smoothstep(0.0, -2.5, lap)
    hn = NZ_MASK.fbm(X / 220.0, Z / 220.0, 4)
    alt = smoothstep(500.0, 1900.0, H)
    pd = np.clip(powder * (0.55 + 0.45 * alt) * (1 - 0.65 * convex) + hn * 0.25, 0, 1)
    pd = pd * (1 - groomed) * smoothstep(52.0, 38.0, slope)
    icem = np.clip(ice * (convex * 0.8 + smoothstep(33.0, 45.0, slope) * 0.6) + hn * 0.3 - 0.15, 0, 1) * (1 - groomed)
    treeline = 1180.0 + NZ_MASK.fbm(X / 400.0, Z / 400.0, 3) * 160.0
    td = trees * smoothstep(treeline, treeline - 220.0, H) * smoothstep(36.0, 24.0, slope) * (1 - groomed)
    td = np.clip(td * (0.6 + 0.8 * (NZ_MASK.fbm(X / 140.0 + 9, Z / 140.0, 4) + 0.3)), 0, 1)
    rock = smoothstep(38.0, 50.0, slope + hn * 6.0)
    if fm is not None:
        lk = fm["lake"]
        clear = np.maximum(np.maximum(lk, fm["cliff"]), fm["gully"])
        pd = pd * (1 - lk)
        icem = np.maximum(icem, lk)
        td = td * (1 - np.clip(clear * 1.5, 0, 1))
        pd = np.maximum(pd, fm["gully"] * 0.6)
    surf = np.stack([pd, groomed, icem, td], axis=-1)
    # downsample surface to the 4 m grid (enough for gameplay & shading)
    surf = surf[::2, ::2]
    return (np.clip(surf, 0, 1) * 255).astype(np.uint8), (np.clip(rock, 0, 1) * 255).astype(np.uint8)[::2, ::2]


def bake_light(H):
    """Sun visibility (horizon marching, C) + ambient occlusion, on the 4 m grid."""
    H4 = np.ascontiguousarray(H[::2, ::2], dtype=np.float32)
    n = H4.shape[0]
    sp = SP * 2
    hor = math.hypot(SUN_DIR[0], SUN_DIR[2])
    out = np.zeros_like(H4)
    _LIB.sun_shadow(H4, n, float(SUN_DIR[0] / hor), float(SUN_DIR[2] / hor), float(SUN_DIR[1] / hor * sp), 900, 6.0, out)
    out = blur(out, 1)
    ao = np.clip(1.0 - (blur(H4, 8) - H4) / 45.0, 0.3, 1.0)
    return (np.clip(out, 0, 1) * 255).astype(np.uint8), (ao * 255).astype(np.uint8)


def bake_far(HF):
    H = np.ascontiguousarray(HF, dtype=np.float32)
    n = H.shape[0]
    hor = math.hypot(SUN_DIR[0], SUN_DIR[2])
    out = np.zeros_like(H)
    _LIB.sun_shadow(H, n, float(SUN_DIR[0] / hor), float(SUN_DIR[2] / hor), float(SUN_DIR[1] / hor * FAR_SP), 400, 30.0, out)
    return (np.clip(blur(out, 1), 0, 1) * 255).astype(np.uint8)


def place_trees(H, slope, surface, X, Z, lay):
    rng = np.random.default_rng(1234)
    td = surface[..., 3].astype(np.float32) / 255.0   # 4 m grid
    n4 = td.shape[0]
    trees = []
    # candidate per 4 m cell with probability ~ density * k
    prob = td * 0.16
    roll = rng.random(td.shape)
    ii, jj = np.nonzero(roll < prob)
    jit = rng.uniform(-1.9, 1.9, (len(ii), 2))
    xs = jj * 4.0 + jit[:, 0]
    zs = ii * 4.0 + jit[:, 1]
    # keep away from lifts / village
    keep = np.ones(len(xs), dtype=bool)
    for lf in lay["lifts"]:
        b, t = lf["bottom"], lf["top"]
        d = seg_dist(xs, zs, b[0], b[1], t[0], t[1])
        keep &= d > 18
    vx, vz = lay["village"]["x"], lay["village"]["z"]
    keep &= np.hypot(xs - vx, zs - vz) > 260
    # clear race lines (a corridor either side) so routes stay skiable at speed
    for chg in lay.get("challenges", []):
        if chg.get("type") != "race":
            continue
        pth = chg["path"]
        for i in range(len(pth) - 1):
            keep &= seg_dist(xs, zs, pth[i][0], pth[i][1], pth[i + 1][0], pth[i + 1][1]) > 10.0
    for f in lay.get("features", []):
        if f["type"] in ("trail", "gully"):
            pth = f["path"]
            clear = 7.0 if f["type"] == "trail" else 16.0
            for i in range(len(pth) - 1):
                keep &= seg_dist(xs, zs, pth[i][0], pth[i][1], pth[i + 1][0], pth[i + 1][1]) > clear
        elif f["type"] in ("lip", "cliff"):
            keep &= ~in_landing(xs, zs, f)
    for m in lay.get("landmarks", []):
        keep &= np.hypot(xs - m["x"], zs - m["z"]) > 22.0
    xs, zs = xs[keep], zs[keep]
    sc = rng.uniform(0.7, 1.35, len(xs))
    rot = rng.uniform(0, 2 * math.pi, len(xs))
    return np.stack([xs, zs, sc, rot], axis=-1).tolist()


def in_landing(xs, zs, f):
    """True for points in the run-in / landing corridor of a cliff or kicker (kept clear of trees and rocks)."""
    u = (xs - f["x"]) * f["dx"] + (zs - f["z"]) * f["dz"]
    v = -(xs - f["x"]) * f["dz"] + (zs - f["z"]) * f["dx"]
    if f["type"] == "cliff":
        length, half = f["drop"] * 3.4 + 45.0, f["width"] * 0.42
    else:
        length, half = 60.0, f["width"] * 0.5 + 8.0
    return (u > -25.0) & (u < length) & (np.abs(v) < half)


def place_rocks(H, slope, W, X, Z, lay, fm=None):
    rng = np.random.default_rng(4321)
    rough = region_param(W, "rough")
    s4 = slope[::2, ::2]
    r4 = rough[::2, ::2]
    # scattered rocks: far fewer than before, and only on steep rough ground
    prob = smoothstep(32.0, 50.0, s4) * r4 * 0.0035 + smoothstep(45.0, 62.0, s4) * 0.004
    if fm is not None:
        prob *= 1.0 - np.clip(fm["lake"][::2, ::2] + fm["gully"][::2, ::2], 0, 1)
    roll = rng.random(s4.shape)
    ii, jj = np.nonzero(roll < prob)
    xs = list(jj * 4.0 + rng.uniform(-2, 2, len(ii)))
    zs = list(ii * 4.0 + rng.uniform(-2, 2, len(ii)))
    sc = list(rng.uniform(1.2, 3.4, len(xs)) ** 1.3)
    # boulder fields at the foot of cliff bands
    for f in lay.get("features", []):
        if f["type"] != "cliff":
            continue
        for _ in range(int(f["width"] / 12)):
            # on the flanks, leaving the landing in the middle of the band clear
            c = rng.choice([-1.0, 1.0]) * rng.uniform(0.44, 0.62) * f["width"]
            a = f["drop"] * rng.uniform(1.0, 3.2) + 4.0
            xs.append(f["x"] + f["dx"] * a - f["dz"] * c)
            zs.append(f["z"] + f["dz"] * a + f["dx"] * c)
            sc.append(rng.uniform(1.3, 3.6))
    # big outcrops on the high ridges of the rough regions
    A = Analysis(H)
    ridge = (A.prom > 10.0) & (A.slope > 18) & (A.slope < 45) & (region_param(region_weights(A.X, A.Z), "rough") > 0.8) \
        & (A.X > 300) & (A.X < WORLD - 300) & (A.Z > 300) & (A.Z < WORLD - 300)
    ci, cj = np.nonzero(ridge)
    for k in rng.permutation(len(ci))[:70]:
        xs.append(float(A.X[ci[k], cj[k]]) + rng.uniform(-3, 3))
        zs.append(float(A.Z[ci[k], cj[k]]) + rng.uniform(-3, 3))
        sc.append(rng.uniform(5.0, 9.0))
    xs = np.array(xs)
    zs = np.array(zs)
    sc = np.array(sc)
    rot = rng.uniform(0, 2 * math.pi, len(xs))
    keep = np.ones(len(xs), dtype=bool)
    for p in lay["pistes"]:
        pts = p["pts"]
        for i in range(0, len(pts) - 1):
            keep &= seg_dist(xs, zs, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]) > p["width"] + 6
    for chg in lay.get("challenges", []):
        if chg.get("type") == "race":
            pth = chg["path"]
            for i in range(len(pth) - 1):
                keep &= seg_dist(xs, zs, pth[i][0], pth[i][1], pth[i + 1][0], pth[i + 1][1]) > 10.0
    for d in lay.get("drop_zones", []):
        keep &= np.hypot(xs - d["x"], zs - d["z"]) > 30.0
    for f in lay.get("features", []):
        if f["type"] in ("trail", "gully"):
            pth = f["path"]
            for i in range(len(pth) - 1):
                keep &= seg_dist(xs, zs, pth[i][0], pth[i][1], pth[i + 1][0], pth[i + 1][1]) > 14.0
        elif f["type"] in ("lip", "cliff"):
            keep &= ~in_landing(xs, zs, f)
    for m in lay.get("landmarks", []):
        keep &= np.hypot(xs - m["x"], zs - m["z"]) > 15.0
    return np.stack([xs[keep], zs[keep], sc[keep], rot[keep]], axis=-1).tolist()


def finalize_layout(lay, H):
    """Drop zones (spawn points), viewpoints and challenges."""
    drop = []
    A = lay["_analysis"]
    names = {0: ("Summit Peak", "Glacier Shoulder"), 1: ("Powder Bowl", "Valley Meadows"),
             2: ("Pinewood Ridge", "Timber Hollow"), 3: ("Rocky Spire", "Crag Saddle"),
             5: ("Widowmaker", "Far East Couloir")}
    max_slope = {0: 34.0, 1: 30.0, 2: 30.0, 3: 37.0, 5: 42.0}
    edge = (A.X > 480) & (A.X < WORLD - 480) & (A.Z > 480) & (A.Z < WORLD - 480)
    seeds = []
    for rid, (n1, n2) in names.items():
        inreg = (A.region == rid) & edge & (A.slope > 14.0) & (A.slope < max_slope[rid])
        chosen = []
        for nm in (n1, n2):
            mask = inreg.copy()
            for (cx, cz) in chosen:
                mask &= np.hypot(A.X - cx, A.Z - cz) > 900.0
            for _try in range(40):
                p = A.best(mask, A.H)
                if p is None:
                    break
                if runout_ok(H, p[0], p[1], max_slope[rid] + 8.0, A=A):
                    chosen.append(p)
                    seeds.append((nm, p[0], p[1], rid))
                    break
                mask &= np.hypot(A.X - p[0], A.Z - p[1]) > 60.0
    if lay["lifts"]:
        t = lay["lifts"][0]["top"]
        tx, tz = skiable_near(H, t[0], t[1] + 30.0, 120)
        seeds.append(("Resort Top", tx, tz, 4))
    vb = lay["village"]
    seeds.append(("Village Base", vb["x"], vb["z"] - 120.0, 4))
    for nm, px, pz, rid in seeds:
        h = sample(H, px, pz)
        # facing: downhill direction
        pts = descend_path(H, px, pz, 60, step=10.0)
        fx, fz = pts[-1][0] - px, pts[-1][1] - pz
        drop.append(dict(name=nm, region=rid, x=px, z=pz, y=h, yaw=math.atan2(-fx, -fz),
                         unlocked=nm in ("Resort Top", "Village Base")))
    lay["drop_zones"] = drop
    # viewpoints: highest points per region
    vps = []
    vp_names = {0: "Summit Lookout", 1: "Valley Overlook", 2: "Pinewood Knoll", 3: "Spire View", 4: "Resort Panorama", 5: "Backcountry Crown"}
    for rid, nm in vp_names.items():
        dzs = [d for d in drop if d["region"] == rid]
        if not dzs:
            continue
        top = max(dzs, key=lambda d: d["y"])
        dd = np.hypot(A.X - top["x"], A.Z - top["z"])
        mask = (dd > 150) & (dd < 900) & (A.H < top["y"] - 60) & (A.H > top["y"] - 450) & (A.slope < 24.0) & edge
        p = A.best(mask, A.prom * 3.0 - dd * 0.02)
        if p is None:
            continue
        vps.append(dict(name=nm, x=p[0], z=p[1], y=sample(H, p[0], p[1]), region=rid))
    lay["viewpoints"] = vps
    # challenges
    ch = []
    # races: follow believable descents from drop zones
    race_defs = [("Resort Top", "Village Sprint", "Village Base", 18.0, 34.0),
                 ("Powder Bowl", "Powder Rush", None, 20.0, 36.0),
                 ("Pinewood Ridge", "Timber Slalom", None, 17.0, 32.0),
                 ("Summit Peak", "Summit Downhill", None, 26.0, 42.0),
                 ("Widowmaker", "Widowmaker Line", None, 26.0, 40.0)]
    dz_by = {d["name"]: d for d in drop}
    for dzn, nm, goal, tdeg, mdeg in race_defs:
        if dzn not in dz_by:
            continue
        d = dz_by[dzn]
        if goal is None:
            nat = descend_path(H, d["x"], d["z"], 2200, step=12.0, momentum=0.8)
            goal = nat[-1]
        if isinstance(goal, str):
            g2 = dz_by[goal]
            goal = (g2["x"], g2["z"])
        if nm == "Village Sprint" and lay["pistes"]:
            pts = [tuple(p) for p in lay["pistes"][min(1, len(lay["pistes"]) - 1)]["pts"]]
        else:
            # races must never climb (a skier stalls on an uphill), so uphill is penalised hard
            pts = route(H, (d["x"], d["z"]), goal, tdeg, mdeg, grid=12.0, pad=600.0, uphill_pen=400.0)
        total = sum(math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]) for i in range(1, len(pts)))
        spacing = max(160.0, total / 15.0)
        cps = []
        acc = 0.0
        for i in range(1, len(pts)):
            acc += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            if acc >= spacing or i == len(pts) - 1:
                if i == len(pts) - 1 and cps and acc < spacing * 0.4:
                    cps[-1] = [pts[i][0], pts[i][1], sample(H, pts[i][0], pts[i][1])]
                else:
                    cps.append([pts[i][0], pts[i][1], sample(H, pts[i][0], pts[i][1])])
                acc = 0.0
        length = sum(math.hypot(cps[i][0] - cps[i - 1][0], cps[i][1] - cps[i - 1][1]) for i in range(1, len(cps)))
        length += math.hypot(cps[0][0] - d["x"], cps[0][1] - d["z"])
        drop_h = d["y"] - cps[-1][2]
        est_speed = min(24.0, 8.0 + drop_h / max(length, 1) * 38.0)
        gold = length / est_speed
        ch.append(dict(id="race_" + nm.lower().replace(" ", "_"), type="race", name=nm, region=d["region"],
                       drop=dzn, start=[d["x"], d["z"], d["y"]], yaw=d["yaw"], checkpoints=cps,
                       medals=[round(gold, 1), round(gold * 1.25, 1), round(gold * 1.6, 1)], length=round(length),
                       path=[[round(p[0], 1), round(p[1], 1)] for p in pts[::2]]))
    # freestyle
    ch.append(dict(id="trick_park", type="trick_score", name="Park Session", region=4, start=None, drop="Resort Top",
                   target=[6000, 3500, 1500], time_limit=120))
    ch.append(dict(id="trick_spin", type="trick_specific", name="Spin Doctor", region=1, drop="Powder Bowl",
                   trick="360", count=3, time_limit=150))
    ch.append(dict(id="trick_grab", type="trick_specific", name="Grab Bag", region=2, drop="Pinewood Ridge",
                   trick="grab", count=4, time_limit=150))
    ch.append(dict(id="trick_combo", type="trick_combo", name="Combo King", region=0, drop="Glacier Shoulder",
                   target=[2, 1, 1], combo=3, time_limit=180))
    ch.append(dict(id="trick_big", type="trick_score", name="Big Mountain Freestyle", region=5, drop="Far East Couloir",
                   target=[9000, 5000, 2500], time_limit=180))
    # extreme: reach the bottom without crashing
    ch.append(dict(id="extreme_crag", type="extreme", name="Crag Descent", region=3, drop="Rocky Spire",
                   drop_req=600, time_limit=300))
    ch.append(dict(id="extreme_widow", type="extreme", name="No Fall Zone", region=5, drop="Widowmaker",
                   drop_req=800, time_limit=300))
    lay["challenges"] = [c for c in ch if c.get("drop", "Resort Top") in dz_by or c["type"] == "race"]
    # snap y values
    for p in lay["pistes"]:
        p["pts"] = [[q[0], q[1]] for q in p["pts"]]
    for lf in lay["lifts"]:
        lf["bottom_y"] = sample(H, *lf["bottom"])
        lf["top_y"] = sample(H, *lf["top"])
    lay.pop("_analysis", None)


def previews(H, nx, ny, nz, surface, sunvis, lay, prevdir, trees):
    s = 4
    Hs = H[::s, ::s]
    sh = np.clip(nx[::s, ::s] * SUN_DIR[0] + ny[::s, ::s] * SUN_DIR[1] + nz[::s, ::s] * SUN_DIR[2], 0, 1)
    sv = sunvis[::2, ::2].astype(np.float32) / 255.0
    sv = sv[: sh.shape[0], : sh.shape[1]]
    lit = 0.25 + 0.75 * sh * sv
    alt = (Hs - Hs.min()) / (Hs.max() - Hs.min())
    rgb = np.stack([lit * (0.75 + 0.25 * alt), lit * (0.8 + 0.2 * alt), lit * (0.9 + 0.1 * alt)], axis=-1)
    td = surface[::2, ::2, 3].astype(np.float32) / 255.0
    td = td[: rgb.shape[0], : rgb.shape[1]]
    rgb[..., 0] *= 1 - td * 0.6
    rgb[..., 2] *= 1 - td * 0.6
    gr = surface[::2, ::2, 1].astype(np.float32) / 255.0
    gr = gr[: rgb.shape[0], : rgb.shape[1]]
    rgb[..., 2] = np.maximum(rgb[..., 2], gr * 0.9)
    # contours every 100 m
    c = (np.floor(Hs / 100.0) != np.floor(np.roll(Hs, 1, 0) / 100.0)) | (np.floor(Hs / 100.0) != np.floor(np.roll(Hs, 1, 1) / 100.0))
    rgb[c] *= 0.8
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    k = 1.0 / (SP * s)
    for dz in lay.get("drop_zones", []):
        x, z = dz["x"] * k, dz["z"] * k
        d.ellipse([x - 4, z - 4, x + 4, z + 4], fill=(255, 60, 0))
        d.text((x + 6, z - 6), dz["name"], fill=(0, 0, 0))
    for lf in lay["lifts"]:
        d.line([lf["bottom"][0] * k, lf["bottom"][1] * k, lf["top"][0] * k, lf["top"][1] * k], fill=(40, 40, 40), width=2)
    for chg in lay.get("challenges", []):
        if chg["type"] == "race":
            pts = [(c[0] * k, c[1] * k) for c in chg["checkpoints"]]
            d.line(pts, fill=(255, 200, 0), width=1)
    for gx in range(0, 6145, 1024):
        d.text((gx * k + 2, 2), str(gx), fill=(200, 0, 0))
        d.text((2, gx * k + 2), str(gx), fill=(200, 0, 0))
    img.save(os.path.join(prevdir, "terrain_map.png"))


if __name__ == "__main__":
    main()
