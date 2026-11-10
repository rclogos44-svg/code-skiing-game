"""Builds the rider's clothes and gear as skinned meshes (no external modelling tools).

Every garment is a signed distance field in the bind pose - lofted torso sections, tubes along the
limbs, smooth unions where they meet - with sewn-in folds (stacked sleeve and pant hems, creases
behind the knees and inside the elbows, drape on the jacket), open hems / cuffs / collar with a lined
inside, and layering that keeps each layer outside the one under it.  The fields are meshed (surface
nets, then projected onto the exact surface), skinned to SkierRig's bones with smooth weights,
ambient occlusion is baked into the vertex colours, and each piece gets a UV layout.  The texture
atlases (seams, stitching, zip, pockets) are painted from 3D positions, so they line up across UV
seams.

usage: python3 -I gen_rider.py PROJECT [--preview OUTDIR]
writes  build/.cache/rider_raw.bin + rider_raw.json  (turned into PROJECT/assets/rider/*.res by
        godot_tools/import_rider.gd)  and  PROJECT/assets/rider/*.png  (texture atlases)
"""
import ctypes
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = ctypes.CDLL(os.path.join(HERE, ".cache", "librider.so"))
_fp = np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS")
_ip = np.ctypeslib.ndpointer(dtype=np.int32, flags="C_CONTIGUOUS")
_bp = np.ctypeslib.ndpointer(dtype=np.uint8, flags="C_CONTIGUOUS")
_LIB.raster.argtypes = [ctypes.c_int, _ip, _fp, ctypes.c_void_p, ctypes.c_int, _fp, ctypes.c_int, ctypes.c_int,
                        ctypes.c_void_p, _fp, ctypes.c_void_p]
_LIB.dilate.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int, _fp, _bp, ctypes.c_int]
_LIB.qem_simplify.argtypes = [ctypes.c_int, _fp, ctypes.c_int, _ip, ctypes.c_int, ctypes.c_double,
                              ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]


def nrm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def dot(a, b):
    return (a * b).sum(-1)


def length(v):
    return np.sqrt((v * v).sum(-1))


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def wrap(a):
    return (a + np.pi) % (2.0 * np.pi) - np.pi


# ------------------------------------------------------------------ bind pose
# Skeleton space: pelvis at the origin, +X his right, +Y up, -Z forward.  The bind pose is the
# game's usual skiing stance measured in the pelvis frame (hips flexed ~50 deg with the knees out
# over the skis, knees ~80 deg, elbows out and bent), so skiing is a small deformation of it; the
# torso is modelled upright.  Bone lengths match SkierBody (thigh 0.44, shin 0.43, arms 0.29 / 0.27).
J = {"pelvis": np.zeros(3), "waist": np.array([0, 0.07, 0.0]), "lumbar": np.array([0, 0.23, 0.0]),
     "thoracic": np.array([0, 0.39, 0.0]), "chest": np.array([0, 0.54, 0.0]), "head": np.array([0, 0.73, 0.0])}
for _s, _sd in ((-1.0, "l"), (1.0, "r")):
    J["hip_" + _sd] = np.array([_s * 0.095, -0.04, 0.0])
    J["knee_" + _sd] = J["hip_" + _sd] + 0.44 * nrm([_s * 0.079, -0.268, -0.339])
    J["ankle_" + _sd] = J["knee_" + _sd] + 0.43 * nrm([-_s * 0.059, -0.373, 0.207])
    J["shoulder_" + _sd] = np.array([_s * 0.185, 0.47, 0.0])
    J["elbow_" + _sd] = J["shoulder_" + _sd] + 0.29 * nrm([_s * 0.156, -0.244, -0.008])
    J["hand_" + _sd] = J["elbow_" + _sd] + 0.27 * nrm([-_s * 0.026, -0.205, -0.174])
# boots sit toe-up ~11 deg relative to the pelvis in that stance (columns = local axes)
_a = math.radians(10.7)
BOOT_B = np.array([[1, 0, 0], [0, math.cos(_a), -math.sin(_a)], [0, math.sin(_a), math.cos(_a)]])


def boot_local(p, sd):
    return (p - J["ankle_" + sd]) @ BOOT_B

BONES = ["pelvis", "sp1", "sp2", "sp3", "neck", "thigh_l", "shin_l", "thigh_r", "shin_r",
         "uarm_l", "farm_l", "uarm_r", "farm_r", "head", "foot_l", "foot_r"]
B = {n: i for i, n in enumerate(BONES)}


def side_sign(sd):
    return -1.0 if sd == "l" else 1.0


# ------------------------------------------------------------------ primitives
def loft(p, table, zc=0.0):
    """Stack of rounded-rectangle sections over y: rows [y, half width, front depth, back depth,
    exponent].  Returns ~distance (radial) to the side surface; open at both ends."""
    t = np.asarray(table, dtype=np.float64)
    y = np.clip(p[:, 1], t[0, 0], t[-1, 0])
    a = np.interp(y, t[:, 0], t[:, 1])
    f = np.interp(y, t[:, 0], t[:, 2])
    b = np.interp(y, t[:, 0], t[:, 3])
    n = np.interp(y, t[:, 0], t[:, 4])
    x = np.abs(p[:, 0]) + 1e-9
    z = p[:, 2] - zc
    d = np.where(z < 0.0, f, b)
    q = ((x / a) ** n + (np.abs(z) / d) ** n) ** (1.0 / n)
    rho = np.sqrt(x * x + z * z)
    return rho * (1.0 - 1.0 / np.maximum(q, 1e-6))


def poly_frame(pts, inner):
    """Per-segment unit directions and 'front' vectors (perpendicular, toward `inner`)."""
    dirs, fronts = [], []
    for i in range(len(pts) - 1):
        d = nrm(pts[i + 1] - pts[i])
        f = inner - d * np.dot(inner, d)
        dirs.append(d)
        fronts.append(nrm(f))
    return dirs, fronts


def poly_coords(p, pts, inner):
    """Closest point on a polyline: arc length s, angle th around it (0 toward `inner`), radial
    distance r, segment index."""
    dirs, fronts = poly_frame(pts, inner)
    n = len(p)
    best = np.full(n, np.inf)
    S = np.zeros(n)
    TH = np.zeros(n)
    R = np.zeros(n)
    SEG = np.zeros(n, dtype=np.int32)
    cum = 0.0
    for i in range(len(pts) - 1):
        a = pts[i]
        ba = pts[i + 1] - a
        L = np.linalg.norm(ba)
        t = np.clip(((p - a) @ ba) / (L * L), 0.0, 1.0)
        q = p - (a + t[:, None] * ba)
        d2 = dot(q, q)
        side = np.cross(dirs[i], fronts[i])
        better = d2 < best
        best = np.where(better, d2, best)
        S = np.where(better, cum + t * L, S)
        TH = np.where(better, np.arctan2(q @ side, q @ fronts[i]), TH)
        R = np.where(better, np.sqrt(d2), R)
        SEG = np.where(better, i, SEG)
        cum += L
    return S, TH, R, SEG, cum


def tube(p, pts, radii, k=0.0):
    """Tube along a polyline with a radius at each point (linear along each segment); segments
    joined with a smooth union of size k."""
    out = None
    for i in range(len(pts) - 1):
        a = pts[i]
        ba = pts[i + 1] - a
        L2 = np.dot(ba, ba)
        t = np.clip(((p - a) @ ba) / L2, 0.0, 1.0)
        q = p - (a + t[:, None] * ba)
        d = length(q) - (radii[i] + (radii[i + 1] - radii[i]) * t)
        out = d if out is None else (smin(out, d, k) if k > 0 else np.minimum(out, d))
    return out


def ellipsoid(p, c, r):
    q = (p - c) / r
    k0 = length(q)
    k1 = length(q / r)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def rbox(p, c, half, rad, rot=None):
    q = p - c
    if rot is not None:
        q = q @ rot
    q = np.abs(q) - (np.asarray(half) - rad)
    return length(np.maximum(q, 0.0)) + np.minimum(np.max(q, axis=1), 0.0) - rad


def capsule(p, a, b, r):
    a = np.asarray(a, float)
    ba = np.asarray(b, float) - a
    t = np.clip(((p - a) @ ba) / np.dot(ba, ba), 0.0, 1.0)
    return length(p - (a + t[:, None] * ba)) - r


def _hash(ix, iy, iz, seed):
    n = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    n = n & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF) / 32767.5 - 1.0


def vnoise(p, scale, seed):
    """Smooth 3D value noise in [-1, 1]."""
    q = p / scale + 1000.0
    i = np.floor(q).astype(np.int64)
    f = q - i
    u = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fabric_noise(p, amp):
    """Low-frequency irregularity (fabric never sits perfectly smooth)."""
    return amp * (vnoise(p, 0.075, 1) + 0.5 * vnoise(p, 0.038, 2)) / 1.2


def opening(solid, cut, depth_cut, t):
    """An open end: `solid` (< 0 inside) is cut where `cut` > 0 (cut = signed distance past the
    opening plane), and hollowed for `depth_cut` metres inside it with walls `t` thick, so the hem
    has an edge and a lined inside instead of a closed bottom.  depth_cut: distance (>0) from the
    opening plane inward."""
    cavity = smax(solid + t, -(cut + depth_cut), 0.01)      # inside the shrunk solid, near the opening
    return smax(smax(solid, -cavity, 0.004), cut, 0.005)    # rounded rim


# ------------------------------------------------------------------ garments
class Garment:
    def __init__(self, name, h, lo, hi, target=4000):
        self.name, self.h, self.lo, self.hi = name, h, np.array(lo, float), np.array(hi, float)
        self.target = target                       # triangles after simplification

    def sdf(self, p):
        raise NotImplementedError

    def weights(self, p):
        raise NotImplementedError

    def extra(self, p):
        """Per-vertex extras: (hem sway, hood sway, lining flag, unused)."""
        return np.zeros((len(p), 4))


def leg_pts(sd):
    s = side_sign(sd)
    hip, knee, ank = J["hip_" + sd], J["knee_" + sd], J["ankle_" + sd]
    top = hip + np.array([s * 0.005, 0.06, 0.012])
    hem = ank + BOOT_B @ np.array([0.0, -0.09, 0.012])
    return [top, knee, ank, hem]


def leg_coords(p, sd):
    pts = leg_pts(sd)
    return poly_coords(p, pts, np.array([0.0, 0.0, -1.0])) + (pts,)


def pants_solid(p, folds=True):
    seat = loft(p, [[-0.19, 0.08, 0.05, 0.06, 2.0], [-0.16, 0.125, 0.085, 0.1, 2.1], [-0.12, 0.158, 0.104, 0.122, 2.3],
                    [-0.07, 0.18, 0.118, 0.138, 2.4],
                    [0.02, 0.19, 0.128, 0.148, 2.4], [0.08, 0.19, 0.13, 0.144, 2.4], [0.14, 0.188, 0.13, 0.142, 2.4]], zc=0.004)
    seat = np.maximum(seat, p[:, 1] - 0.16)
    seat = smax(seat, -0.19 - p[:, 1], 0.04)         # a rounded seat, no flat underside
    d = seat
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = leg_coords(p, sd)
        k_s = np.array([0.0, 0.44, 0.87, 0.96])  # approx arc positions of the control points
        rad = np.interp(S, [0.0, 0.1, 0.44, 0.62, 0.84, 0.9, 0.99], [0.116, 0.112, 0.099, 0.097, 0.103, 0.109, 0.116])
        leg = R - rad
        if folds:
            disp = np.zeros(len(p))
            # stacking above the boot: tilted, wobbly rings with a crease between each
            for s0, a, tilt, ph in ((0.975, 0.009, 0.02, 0.3), (0.935, 0.01, -0.025, 2.0), (0.893, 0.008, 0.03, 4.1),
                                    (0.852, 0.006, -0.02, 1.0)):
                sc = s0 + tilt * np.cos(TH - ph) + 0.008 * np.sin(2 * TH + ph)
                disp += a * np.exp(-((S - sc) / 0.012) ** 2) - a * 0.6 * np.exp(-((S - sc - 0.02) / 0.008) ** 2)
            # behind the knee: crushed creases (the knee is bent in the bind pose)
            back = np.exp(-(wrap(TH - np.pi) / 0.9) ** 2)
            for s0, a in ((0.39, 0.006), (0.425, 0.008), (0.46, 0.007), (0.495, 0.005)):
                sc = s0 + 0.01 * np.sin(TH * 2.0 + s0 * 40)
                disp += back * (a * np.exp(-((S - sc) / 0.009) ** 2) - a * 0.7 * np.exp(-((S - sc - 0.017) / 0.006) ** 2))
            # hip crease at the top front of the thigh, and a fold from the crotch down the inside
            front = np.exp(-(wrap(TH) / 0.9) ** 2)
            for s0, a in ((0.06, 0.006), (0.1, 0.005)):
                disp += front * a * np.exp(-((S - s0 - 0.01 * np.cos(TH * 3)) / 0.01) ** 2)
            inner = np.exp(-(wrap(TH + side_sign(sd) * np.pi / 2) / 0.5) ** 2)
            disp += inner * 0.005 * np.exp(-((S - 0.16) / 0.06) ** 2) * np.cos((S - 0.16) * 30)
            # long drape lines down the shin front and the thigh side
            for th0, s_a, s_b, a in ((0.35, 0.5, 0.82, 0.004), (-0.4, 0.55, 0.8, 0.0035), (side_sign(sd) * 1.4, 0.12, 0.36, 0.004)):
                win = sstep(s_a, s_a + 0.05, S) * (1.0 - sstep(s_b - 0.05, s_b, S))
                disp += a * win * np.exp(-(wrap(TH - th0 - 0.6 * (S - s_a)) / 0.18) ** 2)
            leg = leg - disp * sstep(0.02, 0.06, S)
        d = smin(d, leg, 0.05)
    if folds:
        d = d - fabric_noise(p, 0.0018)
    return d


class Pants(Garment):
    def sdf(self, p):
        d = pants_solid(p)
        # waistband: open at the top, the jacket tucked inside
        d = opening(d, p[:, 1] - pants_top(p), 0.1, WALL)
        for sd in ("l", "r"):
            q = boot_local(p, sd)
            # hem: lower at the back than the front (the break), hollow 10 cm up
            cut = (-0.088 + 0.03 * np.clip(-q[:, 2] / 0.1, -1, 1)) - q[:, 1]
            near = length(q[:, [0, 2]]) < 0.2
            cut = np.where(near, cut, -1.0)
            d = opening(d, cut, 0.1, WALL)
        return d

    def weights(self, p):
        return leg_weights(p)

    def extra(self, p):
        """r / a: sway of the left / right leg's baggy fabric (most at the stacked hem)."""
        e = np.zeros((len(p), 4))
        solid = pants_solid(p)
        for k, sd in ((0, "l"), (1, "r")):
            inside = (solid < -WALL * 0.5) & (boot_local(p, sd)[:, 1] < 0.06)
            e[:, 2] = np.maximum(e[:, 2], inside.astype(float))
            S, TH, R, SEG, L, pts = leg_coords(p, sd)
            on = sstep(0.0, 0.06, side_sign(sd) * p[:, 0])
            e[:, k if k == 0 else 1] = on * (0.35 * sstep(0.12, 0.45, S) + 0.65 * sstep(0.45, 0.95, S))
        e[:, 2] = np.maximum(e[:, 2], (solid < -WALL * 0.5) & (p[:, 1] > pants_top(p) - 0.11))
        return e


def leg_weights(p, jacket=False):
    """Pelvis / thigh / shin / foot weights for anything on the legs."""
    w = np.zeros((len(p), len(BONES)))
    w[:, B["pelvis"]] = 1.0
    for sd in ("l", "r"):
        s = side_sign(sd)
        S, TH, R, SEG, L, pts = leg_coords(p, sd)
        on_side = sstep(-0.035, 0.035, s * p[:, 0])           # which leg this point belongs to
        # the crotch stays with the pelvis instead of webbing between the thighs
        on_side *= 1.0 - (1.0 - sstep(0.015, 0.07, np.abs(p[:, 0]))) * sstep(-0.32, -0.2, p[:, 1])
        # hip: thigh weight grows along the leg from the hip crease (further down behind, under
        # the buttock); points on the seat project near the top of the leg line and stay pelvis
        back = 0.5 - 0.5 * np.cos(TH)
        lo = 0.075 + 0.07 * back
        wt = sstep(lo, lo + 0.11, S) * on_side
        # knee: thigh -> shin across a band around the bisector, sharper behind the knee
        knee_s = 0.44
        band = np.where(np.abs(wrap(TH)) > np.pi / 2, 0.035, 0.06)
        ws = sstep(knee_s - band, knee_s + band, S) * on_side
        # ankle: the stacked hem partly follows the boot
        wf = sstep(0.9, 1.0, S) * 0.35 * on_side
        w[:, B["pelvis"]] -= wt
        w[:, B["thigh_" + sd]] += wt * (1.0 - ws)
        w[:, B["shin_" + sd]] += wt * ws * (1.0 - wf)
        w[:, B["foot_" + sd]] += wt * ws * wf
    return w


# --- jacket: fitted, tucked into the pants' waistband (it bags a little over the band)
WALL = 0.0145                 # hem / cuff / collar thickness (>= 2 grid cells)
JACKET_BOTTOM = -0.07         # the jacket ends here, inside the pants


def pants_top(p):
    """Height of the pants' waistband top edge (a little higher at the back)."""
    return 0.1 + 0.02 * sstep(-0.1, 0.1, p[:, 2])


def arm_pts(sd):
    s = side_sign(sd)
    sh, el, hd = J["shoulder_" + sd], J["elbow_" + sd], J["hand_" + sd]
    start = sh + np.array([-s * 0.03, 0.0, 0.005])
    end = hd - nrm(hd - el) * 0.035
    return [start, el, end]


def arm_inner(sd):
    el, sh, hd = J["elbow_" + sd], J["shoulder_" + sd], J["hand_" + sd]
    return nrm(nrm(hd - el) - nrm(el - sh))


def arm_coords(p, sd):
    pts = arm_pts(sd)
    return poly_coords(p, pts, arm_inner(sd)) + (pts,)


# rows: y, half width, front depth, back depth, exponent.  Narrow where it goes into the pants,
# bloused just above the waistband, fitted through the chest, square shoulders.
TORSO = [[-0.09, 0.158, 0.104, 0.113, 2.4], [0.0, 0.161, 0.106, 0.116, 2.4], [0.07, 0.166, 0.11, 0.12, 2.4],
         [0.115, 0.19, 0.128, 0.132, 2.5], [0.16, 0.198, 0.134, 0.132, 2.6], [0.26, 0.205, 0.137, 0.13, 2.7],
         [0.36, 0.215, 0.136, 0.126, 2.8], [0.42, 0.226, 0.128, 0.12, 2.7], [0.46, 0.214, 0.116, 0.112, 2.5],
         [0.5, 0.165, 0.098, 0.098, 2.2], [0.535, 0.115, 0.086, 0.09, 2.0], [0.57, 0.095, 0.082, 0.086, 2.0]]


def collar_sdf(p):
    return tube(p, [np.array([0, 0.5, 0.004]), np.array([0, 0.64, -0.008])], [0.088, 0.084])


# --- the hood, down: a soft hood lying on the upper back, attached round the collar, its face
# opening turned up and its crown point hanging down between the shoulder blades
HOOD_C = np.array([0.0, 0.49, 0.118])
HOOD_OPEN_N = nrm([0.0, 0.8, 0.6])           # the opening faces up and back
HOOD_OPEN_P = np.array([0.0, 0.52, 0.15])


def hood_bag(p):
    bag = ellipsoid(p, HOOD_C, np.array([0.135, 0.11, 0.062]))
    crown = capsule(p, [0.0, 0.45, 0.14], [0.0, 0.375, 0.148], 0.028)      # the point of the hood
    bag = smin(bag, crown, 0.05)
    # soft crumples where the fabric folds over itself
    bag -= 0.005 * np.sin(p[:, 0] * 34 + 1.0) * np.exp(-((p[:, 1] - 0.47) / 0.05) ** 2)
    bag -= 0.003 * np.sin(p[:, 1] * 55 + p[:, 0] * 18)
    return bag


def hood_cut(p):
    return (p - HOOD_OPEN_P) @ HOOD_OPEN_N


def hood_sdf(p):
    """Hollow hood with its rim rolled round the opening."""
    bag = hood_bag(p)
    return opening(bag, hood_cut(p), 0.075, WALL)


def jacket_solid(p, folds=True, with_hood=True):
    d = loft(p, TORSO, zc=0.006)
    d = np.maximum(d, p[:, 1] - 0.6)
    d = smin(d, collar_sdf(p), 0.03)
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = arm_coords(p, sd)
        rad = np.interp(S, [0.0, 0.08, 0.29, 0.4, 0.52], [0.074, 0.07, 0.064, 0.06, 0.058])
        sl = R - rad
        if folds:
            disp = np.zeros(len(p))
            inner = np.exp(-(wrap(TH) / 0.8) ** 2)
            # crushed fabric inside the elbow
            for s0, a in ((0.25, 0.005), (0.282, 0.008), (0.31, 0.007), (0.338, 0.005)):
                sc = s0 + 0.012 * np.sin(TH * 2 + s0 * 50)
                disp += inner * (a * np.exp(-((S - sc) / 0.008) ** 2) - 0.6 * a * np.exp(-((S - sc - 0.015) / 0.006) ** 2))
            # the sleeve stacks above the cuff
            for s0, a, tilt, ph in ((0.505, 0.005, 0.012, 0.5), (0.47, 0.006, -0.015, 2.4), (0.435, 0.004, 0.015, 4.0)):
                sc = s0 + tilt * np.cos(TH - ph) + 0.006 * np.sin(2 * TH + ph)
                disp += a * np.exp(-((S - sc) / 0.01) ** 2) - 0.5 * a * np.exp(-((S - sc - 0.017) / 0.007) ** 2)
            disp += 0.003 * sstep(0.49, 0.5, S)
            sl = sl - disp * sstep(0.02, 0.07, S)
        d = smin(d, sl, 0.035)
    if folds:
        d = d - jacket_folds(p)
    d = np.maximum(d, JACKET_BOTTOM - p[:, 1])          # tucked: the bottom is hidden in the pants
    if with_hood:
        d = smin(d, hood_sdf(p), 0.02)
    return d


def jacket_folds(p):
    th = np.arctan2(p[:, 0], -(p[:, 2] - 0.006))          # 0 front, +-pi back
    y = p[:, 1]
    disp = np.zeros(len(p))
    front = np.exp(-(th / 1.1) ** 2)
    body = 1.0 - sstep(0.4, 0.47, y)
    # bloused over the waistband: soft pleats all round, and the overhang's lower edge
    blouse = sstep(0.09, 0.115, y) * (1.0 - sstep(0.15, 0.2, y))
    disp += blouse * 0.004 * np.sin(th * 9 + 0.7 * np.sin(th * 3))
    disp += 0.004 * np.exp(-((y - 0.118) / 0.008) ** 2)
    # belly: a couple of horizontal folds as he leans forward
    for y0, a in ((0.17, 0.005), (0.22, 0.004)):
        yc = y0 + 0.01 * np.sin(th * 3 + y0 * 30)
        disp += front * (a * np.exp(-((y - yc) / 0.01) ** 2) - 0.6 * a * np.exp(-((y - yc - 0.018) / 0.007) ** 2))
    # armpits: diagonal pull from the underarm toward the chest / shoulder blades
    for sgn in (-1.0, 1.0):
        for th0, a in ((0.95, 0.004), (2.2, 0.004)):
            win = sstep(0.18, 0.24, y) * (1.0 - sstep(0.36, 0.41, y))
            disp += a * win * np.exp(-(wrap(th - sgn * (th0 - 1.8 * (y - 0.3))) / 0.12) ** 2)
    disp *= body
    return disp + fabric_noise(p, 0.0014)


class Jacket(Garment):
    def sdf(self, p):
        d = jacket_solid(p)
        # cuffs
        for sd in ("l", "r"):
            pts = arm_pts(sd)
            axis = nrm(pts[2] - pts[1])
            cut = (p - pts[2]) @ axis
            near = length(p - pts[2]) < 0.16
            d = opening(d, np.where(near, cut, -1.0), 0.08, WALL)
        # collar top (higher at the back)
        ct = 0.618 + 0.03 * sstep(-0.08, 0.08, p[:, 2])
        near = (np.abs(p[:, 0]) < 0.14) & (p[:, 1] > 0.5) & (p[:, 2] < 0.075)
        d = opening(d, np.where(near, p[:, 1] - ct, -1.0), 0.09, WALL)
        return d

    def weights(self, p):
        w = np.zeros((len(p), len(BONES)))
        y = p[:, 1]
        # spine: bands up the back, eased into each other; everything inside the pants is pelvis
        ws = [B["pelvis"], B["sp1"], B["sp2"], B["sp3"], B["neck"]]
        ys = [0.08, 0.2, 0.33, 0.47, 0.63]
        prof = np.zeros((len(p), 5))
        for i in range(5):
            prof[:, i] = np.exp(-((y - ys[i]) / 0.08) ** 2)
        prof[:, 0] = np.where(y < ys[0], 1.0, prof[:, 0])
        prof[:, 4] *= sstep(0.56, 0.62, y)
        prof /= prof.sum(1, keepdims=True)
        for i, bi in enumerate(ws):
            w[:, bi] = prof[:, i]
        # sleeves: shoulder -> upper arm -> forearm
        for sd in ("l", "r"):
            S, TH, R, SEG, L, pts = arm_coords(p, sd)
            near_arm = sstep(0.11, 0.075, R - np.interp(S, [0, 0.52], [0.074, 0.058]) + 0.07)
            s = side_sign(sd)
            wa = near_arm * sstep(0.0, 0.07, S)
            wa = np.clip(wa * sstep(0.1, 0.17, s * p[:, 0] + 0.03 * (S > 0.1)), 0, 1)
            wf = sstep(0.24, 0.33, S)
            w *= (1.0 - wa)[:, None]
            w[:, B["uarm_" + sd]] += wa * (1.0 - wf)
            w[:, B["farm_" + sd]] += wa * wf
        return w

    def extra(self, p):
        """r: sleeve-end / blouse sway, a: hood sway (more toward the hood's hanging point)."""
        e = np.zeros((len(p), 4))
        y = p[:, 1]
        sw = 0.5 * sstep(0.09, 0.12, y) * (1.0 - sstep(0.16, 0.22, y))        # the bloused overhang
        for sd in ("l", "r"):
            S, TH, R, SEG, L, pts = arm_coords(p, sd)
            on_arm = (R < 0.1) & (side_sign(sd) * p[:, 0] > 0.15)
            sw = np.maximum(sw, on_arm * 0.8 * sstep(0.3, 0.52, S))
        e[:, 0] = sw
        hood = (hood_bag(p) < 0.012) & (p[:, 2] > 0.06) & (y > 0.34)
        e[:, 1] = hood * sstep(0.6, 0.4, y)
        solid = jacket_solid(p)
        e[:, 2] = (solid < -WALL * 0.5).astype(float)            # inside of the cuffs / collar / hood
        e[:, 2] = np.maximum(e[:, 2], hood * (hood_bag(p) < -WALL * 0.5))
        return e


# --- gloves: a fist round the pole grip, padded back, gauntlet cuff inside the sleeve
def hand_frame(sd):
    el, hd, sh = J["elbow_" + sd], J["hand_" + sd], J["shoulder_" + sd]
    y = nrm(hd - el)
    x = np.cross(sh - el, hd - el)
    x = nrm(x) * np.sign(x[0] + 1e-9)            # hinge axis, signed like the body's +X (SkierRig)
    z = np.cross(x, y)
    return np.stack([x, y, z], 1), hd            # columns = local axes


class Glove(Garment):
    def __init__(self, sd, *a, **k):
        super().__init__(*a, **k)
        self.sd = sd

    def local(self, p):
        M, o = hand_frame(self.sd)
        return (p - o) @ M                               # (lx, ly, lz)

    def sdf(self, p):
        q = self.local(p)
        s = side_sign(self.sd)
        med = -s                                         # palm faces the body's midline (local x)
        gaunt = tube(q, [np.array([0, -0.085, 0.0]), np.array([0, -0.01, 0.0]), np.array([0, 0.02, 0.0])], [0.05, 0.047, 0.045])
        gaunt -= 0.003 * sstep(-0.05, -0.045, q[:, 1]) * (1 - sstep(-0.03, -0.025, q[:, 1]))     # cinch strap
        palm = rbox(q, np.array([med * 0.004, 0.058, 0.0]), [0.03, 0.05, 0.046], 0.022)
        # curled fingers: a roll along the knuckle line, grooved between the fingers
        fing = capsule(q, [med * 0.024, 0.088, -0.04], [med * 0.024, 0.088, 0.036], 0.027)
        for zc in (-0.02, 0.0, 0.02):
            fing = fing + 0.003 * np.exp(-((q[:, 2] - zc) / 0.003) ** 2)
        thumb = capsule(q, [med * 0.012, 0.03, 0.042], [med * 0.034, 0.075, 0.034], 0.0165)
        d = smin(gaunt, palm, 0.02)
        d = smin(d, fing, 0.014)
        d = smin(d, thumb, 0.012)
        # padded back of the hand
        pad = rbox(q, np.array([-med * 0.022, 0.06, 0.0]), [0.01, 0.035, 0.035], 0.008)
        d = smin(d, pad, 0.01)
        return d

    def weights(self, p):
        w = np.zeros((len(p), len(BONES)))
        q = self.local(p)
        wf = 1.0
        w[:, B["farm_" + self.sd]] = wf
        return w


# --- boots (in the foot frame: origin at the ankle, sole 0.105 below, toe toward -Z)
class Boot(Garment):
    def __init__(self, sd, *a, **k):
        super().__init__(*a, **k)
        self.sd = sd

    def sdf(self, p):
        q = boot_local(p, self.sd)
        shell = rbox(q, np.array([0, -0.064, -0.035]), [0.054, 0.04, 0.152], 0.032)
        toe = ellipsoid(q, np.array([0, -0.07, -0.15]), np.array([0.05, 0.034, 0.06]))
        heel = ellipsoid(q, np.array([0, -0.06, 0.085]), np.array([0.05, 0.045, 0.05]))
        d = smin(smin(shell, toe, 0.02), heel, 0.02)
        # the cuff runs up the shin (it hinges with it)
        ank = J["ankle_" + self.sd]
        shin_up = nrm(J["knee_" + self.sd] - ank)
        c0 = (ank + BOOT_B @ np.array([0, -0.05, 0.012]) - ank) @ BOOT_B
        c1 = (ank + shin_up * 0.15 + BOOT_B @ np.array([0, 0, 0.012]) - ank) @ BOOT_B
        cuff = tube(q, [c0, c1], [0.063, 0.057])
        d = smin(d, cuff, 0.03)
        # binding lugs at the toe and heel
        sole = rbox(q, np.array([0, -0.097, -0.035]), [0.04, 0.009, 0.172], 0.004)
        d = smin(d, sole, 0.006)
        # buckles on the instep and the cuff
        for zc, yc in ((-0.11, -0.03), (-0.045, -0.008)):
            d = smin(d, rbox(q, np.array([0.0, yc, zc]), [0.05, 0.006, 0.01], 0.003), 0.004)
        return d

    def weights(self, p):
        # the cuff hinges with the shin (as a real boot's cuff does); the shell stays with the foot
        w = np.zeros((len(p), len(BONES)))
        q = boot_local(p, self.sd)
        ws = sstep(0.0, 0.11, q[:, 1]) * 0.95
        w[:, B["shin_" + self.sd]] = ws
        w[:, B["foot_" + self.sd]] = 1.0 - ws
        return w


# --- head: helmet, goggles, neck gaiter pulled up over the nose (no face to get wrong)
HC = J["head"]


def helmet_solid(p):
    q = p - HC
    shell = ellipsoid(q, np.array([0, 0.026, 0.008]), np.array([0.105, 0.112, 0.126]))
    shell = smin(shell, ellipsoid(q, np.array([0, -0.035, 0.07]), np.array([0.08, 0.04, 0.066])), 0.03)
    # vents: grooves front to back over the top
    for xc in (-0.04, 0.0, 0.04):
        g = np.exp(-((q[:, 0] - xc) / 0.006) ** 2) * sstep(0.1, 0.13, q[:, 1]) * sstep(0.08, -0.02, np.abs(q[:, 2] + 0.01))
        shell += 0.004 * g
    return shell


def helmet_cut(q):
    return np.interp(q[:, 2], [-0.16, -0.085, -0.05, 0.03, 0.08, 0.16], [0.04, 0.036, -0.055, -0.07, -0.05, -0.04])


class Helmet(Garment):
    def sdf(self, p):
        q = p - HC
        return opening(helmet_solid(p), helmet_cut(q) - q[:, 1], 0.06, 0.016)

    def weights(self, p):
        w = np.zeros((len(p), len(BONES)))
        w[:, B["head"]] = 1.0
        return w


def goggle_parts(p):
    q = p - HC
    c = np.array([0, 0.004, 0.012])
    v = q - c
    rr = length(v[:, [0, 2]])                          # wrap radius round the face
    ang = np.arctan2(v[:, 0], -v[:, 2])                # 0 straight ahead
    u = ang * 0.12                                     # arc distance across the face
    yy = v[:, 1] + 0.004 * (u / 0.09) ** 2             # a slight smile at the bottom
    win_out = (np.abs(u) / 0.098) ** 4 + (np.abs(yy) / 0.043) ** 4 - 1.0
    win_in = (np.abs(u) / 0.088) ** 4 + (np.abs(yy) / 0.034) ** 4 - 1.0
    front = -v[:, 2] > 0.0
    slab = np.maximum(rr - 0.131, 0.108 - rr)
    frame = np.maximum(slab, win_out * 0.03)
    frame = np.maximum(frame, -np.maximum(win_in * 0.03, 0.126 - rr))   # window for the lens
    frame = np.where(front, frame, 1.0)
    lens = np.maximum(np.maximum(rr - 0.1285, 0.112 - rr), win_in * 0.03 + 0.001)
    lens = np.where(front, lens, 1.0)
    # strap round the back of the helmet
    hs = helmet_solid(p)
    strap = np.maximum(np.abs(hs - 0.004) - 0.0035, np.abs(q[:, 1] - 0.012) - 0.02)
    strap = np.maximum(strap, -(q[:, 2] + 0.06))
    return frame, lens, strap


class GoggleFrame(Garment):
    def sdf(self, p):
        return goggle_parts(p)[0]

    def weights(self, p):
        return Helmet.weights(self, p)


class GoggleLens(Garment):
    def sdf(self, p):
        return goggle_parts(p)[1]

    def weights(self, p):
        return Helmet.weights(self, p)


class Strap(Garment):
    def sdf(self, p):
        return goggle_parts(p)[2]

    def weights(self, p):
        return Helmet.weights(self, p)


class Gaiter(Garment):
    def sdf(self, p):
        q = p - HC
        neck = tube(q, [np.array([0, -0.21, 0.012]), np.array([0, -0.1, 0.006])], [0.064, 0.066])
        face = ellipsoid(q, np.array([0, -0.045, -0.018]), np.array([0.074, 0.075, 0.088]))
        nose = ellipsoid(q, np.array([0, -0.03, -0.097]), np.array([0.02, 0.028, 0.02]))
        chin = ellipsoid(q, np.array([0, -0.098, -0.072]), np.array([0.04, 0.03, 0.03]))
        d = smin(smin(smin(neck, face, 0.04), nose, 0.02), chin, 0.02)
        # bunched rings round the neck
        d -= 0.004 * np.sin(q[:, 1] * 140 + np.arctan2(q[:, 0], q[:, 2]) * 1.5) * sstep(-0.09, -0.12, q[:, 1])
        top = -0.026 - 0.012 * sstep(-0.06, 0.04, q[:, 2])
        d = np.maximum(d, q[:, 1] - top)
        d = np.maximum(d, -0.215 - q[:, 1])
        return d

    def weights(self, p):
        w = np.zeros((len(p), len(BONES)))
        q = p - HC
        wh = sstep(-0.15, -0.09, q[:, 1])
        w[:, B["head"]] = wh
        w[:, B["neck"]] = 1.0 - wh
        return w


def all_garments():
    g = [Jacket("jacket", 0.005, [-0.47, -0.13, -0.42], [0.47, 0.7, 0.29], 20000),
         Pants("pants", 0.0065, [-0.33, -0.9, -0.52], [0.33, 0.14, 0.26], 15000),
         Helmet("helmet", 0.004, HC + [-0.15, -0.11, -0.17], HC + [0.15, 0.17, 0.17], 4000),
         GoggleFrame("goggle_frame", 0.0026, HC + [-0.14, -0.06, -0.16], HC + [0.14, 0.07, 0.0], 2000),
         GoggleLens("goggle_lens", 0.0026, HC + [-0.13, -0.05, -0.16], HC + [0.13, 0.06, -0.06], 900),
         Strap("strap", 0.0026, HC + [-0.15, -0.025, -0.1], HC + [0.15, 0.05, 0.17], 1200),
         Gaiter("gaiter", 0.0045, HC + [-0.12, -0.24, -0.15], HC + [0.12, 0.0, 0.11], 3000)]
    for sd in ("l", "r"):
        hd = J["hand_" + sd]
        g.append(Glove(sd, "glove_" + sd, 0.0035, hd - 0.15, hd + 0.15, target=3200))
        a = J["ankle_" + sd]
        g.append(Boot(sd, "boot_" + sd, 0.004, a + [-0.1, -0.15, -0.27], a + [0.1, 0.22, 0.2], target=2800))
    return g


# ------------------------------------------------------------------ meshing
def sample_grid(fn, lo, hi, h):
    xs = np.arange(lo[0], hi[0] + h, h)
    ys = np.arange(lo[1], hi[1] + h, h)
    zs = np.arange(lo[2], hi[2] + h, h)
    F = np.empty((len(xs), len(ys), len(zs)), dtype=np.float32)
    for i in range(0, len(xs), 8):
        X, Y, Z = np.meshgrid(xs[i:i + 8], ys, zs, indexing="ij")
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
        F[i:i + 8] = fn(P).reshape(X.shape)
    return F, np.array([xs[0], ys[0], zs[0]])


def surface_nets(F, origin, h):
    nx, ny, nz = F.shape
    shp = (nx - 1, ny - 1, nz - 1)
    ncell = shp[0] * shp[1] * shp[2]
    sums = np.zeros((ncell, 3))
    cnt = np.zeros(ncell)
    edges = []
    for ax in range(3):
        s0 = [slice(None)] * 3
        s1 = [slice(None)] * 3
        s0[ax] = slice(0, -1)
        s1[ax] = slice(1, None)
        a = F[tuple(s0)]
        b = F[tuple(s1)]
        cr = (a < 0) != (b < 0)
        idx = np.array(np.nonzero(cr)).T                     # edge start (i,j,k)
        av, bv = a[cr].astype(np.float64), b[cr].astype(np.float64)
        t = av / (av - bv)
        pos = idx.astype(np.float64)
        pos[:, ax] += t
        o1, o2 = [d for d in range(3) if d != ax]
        cells = []
        for d1 in (0, -1):
            for d2 in (0, -1):
                c = idx.copy()
                c[:, o1] += d1
                c[:, o2] += d2
                ok = (c[:, o1] >= 0) & (c[:, o2] >= 0) & (c[:, o1] < shp[o1]) & (c[:, o2] < shp[o2]) & (c[:, ax] < shp[ax])
                flat = np.ravel_multi_index(np.clip(c, 0, np.array(shp) - 1).T, shp)
                cells.append((flat, ok))
                for k in range(3):
                    sums[:, k] += np.bincount(flat[ok], weights=pos[ok, k], minlength=ncell)
                cnt += np.bincount(flat[ok], minlength=ncell)
        edges.append((ax, cells, av < 0))
    active = cnt > 0
    vid = -np.ones(ncell, dtype=np.int64)
    vid[active] = np.arange(active.sum())
    verts = sums[active] / cnt[active][:, None] * h + origin
    quads = []
    for ax, cells, inside_first in edges:
        (c00, k00), (c01, k01), (c10, k10), (c11, k11) = cells
        ok = k00 & k01 & k10 & k11
        q = np.stack([vid[c00], vid[c10], vid[c11], vid[c01]], 1)[ok]
        flip = inside_first[ok]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    quads = np.concatenate(quads)
    return verts, quads


def grad(fn, p, e=0.0007):
    g = np.zeros_like(p)
    for k in range(3):
        d = np.zeros(3)
        d[k] = e
        g[:, k] = (fn(p + d) - fn(p - d)) / (2 * e)
    return g


def project(fn, v, iters=4, max_step=0.006):
    for _ in range(iters):
        f = fn(v)
        g = grad(fn, v)
        g2 = np.maximum(dot(g, g), 1e-8)
        step = (f / g2)[:, None] * g
        step = np.clip(step, -max_step, max_step)
        v = v - step
    return v


def triangulate(v, quads, n):
    a, b, c, d = quads.T
    d1 = length(v[a] - v[c])
    d2 = length(v[b] - v[d])
    t1 = np.where((d1 <= d2)[:, None], np.stack([a, b, c], 1), np.stack([a, b, d], 1))
    t2 = np.where((d1 <= d2)[:, None], np.stack([a, c, d], 1), np.stack([b, c, d], 1))
    tris = np.concatenate([t1, t2])
    # drop degenerate ones
    e1 = v[tris[:, 1]] - v[tris[:, 0]]
    e2 = v[tris[:, 2]] - v[tris[:, 0]]
    cr = np.cross(e1, e2)
    area = length(cr)
    keep = area > 1e-10
    tris, cr = tris[keep], cr[keep]
    # Godot's front faces wind clockwise: (v1-v0)x(v2-v0) points into the surface
    fn_out = n[tris].mean(1)
    flip = dot(cr, fn_out) > 0
    tris[flip] = tris[flip][:, [0, 2, 1]]
    return tris


def simplify(v, tris, target):
    V = np.ascontiguousarray(v, dtype=np.float32)
    T = np.ascontiguousarray(tris, dtype=np.int32)
    onv, ont = ctypes.c_int(), ctypes.c_int()
    _LIB.qem_simplify(len(V), V.reshape(-1), len(T), T.reshape(-1), int(target), 1e9, ctypes.byref(onv), ctypes.byref(ont))
    return V[:onv.value].astype(np.float64), T[:ont.value].astype(np.int64)


def mesh_garment(g):
    t0 = time.time()
    F, org = sample_grid(g.sdf, g.lo, g.hi, g.h)
    faces = [F[0], F[-1], F[:, 0], F[:, -1], F[:, :, 0], F[:, :, -1]]
    if min(float(f.min()) for f in faces) < 0.0:
        raise SystemExit("%s: the garment reaches the edge of its sampling box %s..%s" % (g.name, g.lo, g.hi))
    v, q = surface_nets(F, org, g.h)
    v = project(g.sdf, v)
    n = grad(g.sdf, v)
    n /= np.maximum(length(n), 1e-9)[:, None]
    tris = triangulate(v, q, n)
    # remove unreferenced vertices
    used = np.zeros(len(v), bool)
    used[tris.ravel()] = True
    remap = -np.ones(len(v), np.int64)
    remap[used] = np.arange(used.sum())
    v, tris = v[used], remap[tris]
    n_in = len(tris)
    if len(tris) > g.target:
        v, tris = simplify(v, tris, g.target)
        v = project(g.sdf, v, 2, 0.0015)          # small nudge only: big steps jump across thin rims
    n = grad(g.sdf, v)
    n /= np.maximum(length(n), 1e-9)[:, None]
    print("  %-13s %6d verts %6d tris (from %6d)  grid %s  %.1fs" % (g.name, len(v), len(tris), n_in, F.shape, time.time() - t0))
    return v, n, tris


# ------------------------------------------------------------------ skin weights, AO
def top4(w):
    idx = np.argsort(-w, axis=1)[:, :4]
    ww = np.take_along_axis(w, idx, 1)
    ww = np.clip(ww, 0.0, None)
    s = ww.sum(1, keepdims=True)
    ww = np.where(s > 0, ww / np.maximum(s, 1e-9), np.array([[1.0, 0, 0, 0]]))
    return idx.astype(np.int32), ww


def bake_ao(v, n, scene_fn):
    occ = np.zeros(len(v))
    for hh, wt in ((0.006, 0.3), (0.014, 0.25), (0.028, 0.22), (0.05, 0.16), (0.085, 0.1)):
        d = scene_fn(v + n * hh)
        occ += wt * np.clip((hh - d) / hh, 0.0, 1.0)
    return np.clip(1.0 - occ * 1.25, 0.2, 1.0)


# ------------------------------------------------------------------ preview
def render_preview(meshes, path, view, size=(520, 900), extent=1.0, center=(0, -0.12, 0)):
    """meshes: list of (v, n, tris, color(N,3)). Orthographic, view = yaw degrees (0 = from the front)."""
    W, H = size
    a = math.radians(view)
    fwd = np.array([math.sin(a), 0.0, -math.cos(a)])        # camera looks along -fwd ... toward the rider
    cam_dir = -fwd
    right = np.cross(cam_dir, [0, 1, 0])
    right = right / np.linalg.norm(right)
    up = np.cross(right, cam_dir)
    sc = H / (2.0 * extent)
    allv, alln, allc, allt = [], [], [], []
    off = 0
    for v, n, t, c in meshes:
        allv.append(v)
        alln.append(n)
        allc.append(c)
        allt.append(t + off)
        off += len(v)
    v = np.concatenate(allv) - np.array(center)
    n = np.concatenate(alln)
    c = np.concatenate(allc)
    t = np.concatenate(allt).astype(np.int32)
    xy = np.stack([v @ right * sc + W / 2, -(v @ up) * sc + H / 2], 1).astype(np.float32)
    z = (v @ cam_dir).astype(np.float32)
    light = nrm([-0.4, 0.7, 0.6])
    light = right * light[0] + up * light[1] - cam_dir * light[2]
    lam = np.clip(n @ light, 0, 1)
    rim = np.clip(1.0 - np.abs(n @ cam_dir), 0, 1) ** 3
    sky = 0.5 + 0.5 * n[:, 1]
    shade = c[:, :3] * (0.32 * sky[:, None] * c[:, 3:4] + 0.85 * lam[:, None] * (0.5 + 0.5 * c[:, 3:4])) + 0.12 * rim[:, None]
    attr = np.ascontiguousarray(np.clip(shade, 0, 1).astype(np.float32))
    zb = np.full(W * H, 1e9, np.float32)
    out = np.zeros((W * H, 3), np.float32)
    out[:] = [0.78, 0.84, 0.92]
    _LIB.raster(len(t), np.ascontiguousarray(t.ravel()), np.ascontiguousarray(xy.ravel()), z.ctypes.data, 3, attr.ravel(),
                W, H, zb.ctypes.data, out.reshape(-1), None)
    img = (np.clip(out.reshape(H, W, 3), 0, 1) ** (1 / 1.1) * 255).astype(np.uint8)
    Image.fromarray(img).save(path)


COLORS = {"jacket": (0.36, 0.42, 0.3), "shirt": (0.9, 0.9, 0.88), "pants": (0.63, 0.57, 0.45), "helmet": (0.12, 0.12, 0.13),
          "goggle_frame": (0.9, 0.9, 0.88), "goggle_lens": (0.95, 0.4, 0.1), "strap": (0.15, 0.15, 0.16),
          "gaiter": (0.1, 0.1, 0.11), "glove": (0.08, 0.08, 0.085), "boot": (0.2, 0.2, 0.22)}


# ------------------------------------------------------------------ UV charts
def cyl_proj(o, axis, ref, R):
    o = np.asarray(o, float)
    axis = nrm(axis)
    ref = nrm(np.asarray(ref, float) - axis * np.dot(ref, axis))
    side = np.cross(axis, ref)

    def f(p):
        q = p - o
        return np.stack([np.arctan2(q @ side, q @ ref) * R, q @ axis], 1)
    f.wrap = 2 * np.pi * R
    return f


def planar_proj(o, e1, e2):
    o, e1, e2 = np.asarray(o, float), nrm(e1), nrm(e2)

    def f(p):
        q = p - o
        return np.stack([q @ e1, q @ e2], 1)
    f.wrap = None
    return f


def limb_proj(pts, inner, R):
    def f(p):
        S, TH, Rr, SEG, L = poly_coords(p, pts, inner)
        return np.stack([TH * R, S], 1)
    f.wrap = 2 * np.pi * R
    return f


def jacket_charts():
    ch = {"torso": cyl_proj([0, 0, 0.006], [0, 1, 0], [0, 0, -1], 0.2),
          "yoke": planar_proj([0, 0.5, 0], [1, 0, 0], [0, 0, 1]),
          "collar": cyl_proj([0, 0.5, 0.004], [0, 0.14, -0.012], [0, 0, -1], 0.088),
          "hood": planar_proj([0, 0.5, 0.15], [1, 0, 0], [0, -0.5, 0.87]),
          "hood_lin": planar_proj([0, 0.5, 0.15], [1, 0, 0], [0, -0.5, 0.87]),
          "hem_lin": cyl_proj([0, 0, 0.006], [0, 1, 0], [0, 0, -1], 0.19),
          "collar_lin": cyl_proj([0, 0.5, 0.004], [0, 0.14, -0.012], [0, 0, -1], 0.075)}
    for sd in ("l", "r"):
        ch["sleeve_" + sd] = limb_proj(arm_pts(sd), arm_inner(sd), 0.07)
        ch["cuff_lin_" + sd] = limb_proj(arm_pts(sd), arm_inner(sd), 0.055)
    return ch


def jacket_assign(c, nc, lin):
    key = np.full(len(c), "torso", dtype=object)
    y = c[:, 1]
    hood = (hood_sdf(c) < 0.02) & (y > 0.43) & (c[:, 2] > 0.07)
    arm = {}
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = arm_coords(c, sd)
        arm[sd] = (S > 0.05) & (R < 0.12) & (side_sign(sd) * c[:, 0] > 0.12)
    collar = (y > 0.52) & (length(c[:, [0, 2]] - [0, -0.004]) < 0.115) & ~hood
    yoke = (y > 0.42) & (nc[:, 1] > 0.45) & ~collar & ~hood & ~arm["l"] & ~arm["r"]
    key[yoke] = "yoke"
    key[collar] = "collar"
    for sd in ("l", "r"):
        key[arm[sd]] = "sleeve_" + sd
    key[hood] = "hood"
    # inside surfaces
    key[lin & (y < 0.2)] = "hem_lin"
    for sd in ("l", "r"):
        key[lin & arm[sd]] = "cuff_lin_" + sd
    key[lin & collar] = "collar_lin"
    key[lin & hood] = "hood_lin"
    rest = lin & ~np.isin(key, ["hem_lin", "cuff_lin_l", "cuff_lin_r", "collar_lin", "hood_lin"])
    key[rest] = "hem_lin"
    return key


def pants_charts():
    ch = {"seat": cyl_proj([0, 0, 0.004], [0, 1, 0], [0, 0, -1], 0.17)}
    for sd in ("l", "r"):
        pts = leg_pts(sd)
        ch["leg_" + sd] = limb_proj(pts, np.array([0, 0, -1.0]), 0.11)
        ch["hem_lin_" + sd] = limb_proj(pts, np.array([0, 0, -1.0]), 0.095)
    return ch


def pants_assign(c, nc, lin):
    key = np.full(len(c), "seat", dtype=object)
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = leg_coords(c, sd)
        on = (side_sign(sd) * c[:, 0] > -0.01) & (S > 0.07)
        key[on] = "leg_" + sd
        key[on & lin] = "hem_lin_" + sd
    return key


def split_by_charts(v, tris, keys, charts):
    """Per-triangle chart keys -> new vertex list (duplicated where charts or the wrap meet), UVs in
    metres per chart, and the chart index of each triangle."""
    names = sorted(set(keys))
    vid_of = {}
    new_src, new_uv, new_chart = [], [], []
    out_tris = np.zeros_like(tris)
    tri_chart = np.zeros(len(tris), np.int32)
    for ci, name in enumerate(names):
        sel = np.nonzero(keys == name)[0]
        f = charts[name]
        t = tris[sel]
        uv = f(v[t.ravel()]).reshape(len(t), 3, 2)
        shift = np.zeros((len(t), 3), bool)
        if f.wrap:
            span = uv[:, :, 0].max(1) - uv[:, :, 0].min(1)
            shift = (span > f.wrap * 0.5)[:, None] & (uv[:, :, 0] < 0)
            uv[:, :, 0] += shift * f.wrap
        tri_chart[sel] = ci
        for k in range(3):
            src = t[:, k]
            key = src * 4 + ci * 0 + shift[:, k]
            for j in range(len(sel)):
                kk = (int(src[j]), ci, bool(shift[j, k]))
                idx = vid_of.get(kk)
                if idx is None:
                    idx = len(new_src)
                    vid_of[kk] = idx
                    new_src.append(src[j])
                    new_uv.append(uv[j, k])
                    new_chart.append(ci)
                out_tris[sel[j], k] = idx
    return (np.array(new_src), np.array(new_uv), np.array(new_chart), out_tris, tri_chart, names)


def pack_charts(uv, chart, tri_chart, tris, names, size, margin=6):
    """Shelf-pack the charts' UV rectangles into a size x size atlas at the largest texel density
    that fits.  Returns pixel UVs (0..size) and the density (px per metre)."""
    rects = []
    for ci in range(len(names)):
        m = chart == ci
        lo, hi = uv[m].min(0), uv[m].max(0)
        rects.append((ci, lo, hi - lo))

    def try_pack(D):
        order = sorted(rects, key=lambda r: -r[2][1])
        x = y = row_h = 0
        pos = {}
        for ci, lo, ext in order:
            w = int(math.ceil(ext[0] * D)) + margin * 2
            h = int(math.ceil(ext[1] * D)) + margin * 2
            if x + w > size:
                x, y, row_h = 0, y + row_h, 0
            if w > size or y + h > size:
                return None
            pos[ci] = (x + margin, y + margin)
            x += w
            row_h = max(row_h, h)
        return pos

    lo_d, hi_d = 50.0, 5000.0
    best = None
    for _ in range(30):
        mid = (lo_d + hi_d) / 2
        p = try_pack(mid)
        if p:
            lo_d, best = mid, (mid, p)
        else:
            hi_d = mid
    D, pos = best
    px = np.zeros_like(uv)
    for ci, lo, ext in rects:
        m = chart == ci
        px[m] = (uv[m] - lo) * D + np.array(pos[ci])
    return px, D


def tangents(v, n, uv, tris):
    t = np.zeros_like(v)
    b = np.zeros_like(v)
    p0, p1, p2 = v[tris[:, 0]], v[tris[:, 1]], v[tris[:, 2]]
    w0, w1, w2 = uv[tris[:, 0]], uv[tris[:, 1]], uv[tris[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = w1 - w0, w2 - w0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    sdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    tdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    for k in range(3):
        np.add.at(t, tris[:, k], sdir)
        np.add.at(b, tris[:, k], tdir)
    t = t - n * dot(n, t)[:, None]
    bad = length(t) < 1e-9
    alt = np.cross(n, [0.0, 1.0, 0.0])
    alt2 = np.cross(n, [1.0, 0.0, 0.0])
    alt = np.where((length(alt) < 1e-3)[:, None], alt2, alt)
    t = np.where(bad[:, None], alt, t)
    t /= length(t)[:, None]
    w = np.where(dot(np.cross(n, t), b) < 0.0, -1.0, 1.0)
    return np.concatenate([t, w[:, None]], 1)


# ------------------------------------------------------------------ texture painting (3D)
def band(d, w, soft=0.0008):
    """1 inside |d| < w, soft edges."""
    return sstep(w + soft, w - soft, np.abs(d))


def seam(d, depth=0.0007):
    """Height of a sewn seam at signed distance d (m): a groove with puckered edges."""
    return -depth * np.exp(-(d / 0.0011) ** 2) + 0.35 * depth * np.exp(-((np.abs(d) - 0.0032) / 0.0016) ** 2)


def stitch(d, off=0.0045):
    return 0.00025 * np.exp(-((np.abs(d) - off) / 0.0006) ** 2)


def paint_jacket(P, N, lin, chart_name):
    n = len(P)
    lum = 1.0 + 0.045 * vnoise(P, 0.12, 11) + 0.025 * vnoise(P, 0.03, 12)
    acc = np.zeros(n)
    third = np.zeros(n)
    hgt = np.zeros(n)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    front = z < -0.04
    torso_like = np.isin(chart_name, ["torso", "yoke", "collar"])
    # centre-front zip under a storm flap (right over left), up to the top of the collar
    flap = sstep(-0.006, -0.004, x) * sstep(0.028, 0.026, x)
    on_front = front & torso_like
    hgt += np.where(on_front, 0.0012 * flap + seam(x - 0.027) + stitch(x - 0.027, 0.004), 0.0)
    lum *= np.where(on_front, 1.0 - 0.25 * np.exp(-((x - 0.0285) / 0.0012) ** 2), 1.0)
    garage = on_front & (np.abs(x - 0.01) < 0.012) & (y > 0.6)
    acc = np.maximum(acc, garage * sstep(0.6, 0.605, y))
    # side seams and yokes
    tor = chart_name == "torso"
    hgt += np.where(tor & (np.abs(x) > 0.14), seam(z - 0.012), 0.0)
    yoke_f = 0.405 - 0.035 * (np.abs(x) / 0.24) ** 2
    hgt += np.where(front & torso_like, seam(y - yoke_f) + stitch(y - yoke_f), 0.0)
    hgt += np.where((z > 0.04) & torso_like & (y < 0.47), seam(y - 0.375) + stitch(y - 0.375), 0.0)
    # hand-warmer pockets: diagonal zips low on the front, above the waistband
    for sx in (-1.0, 1.0):
        a = np.array([sx * 0.095, 0.135])
        b = np.array([sx * 0.15, 0.25])
        ab = b - a
        t = np.clip(((P[:, [0, 1]] - a) @ ab) / (ab @ ab), 0, 1)
        d = length(P[:, [0, 1]] - (a + t[:, None] * ab))
        m = front & tor & (t > 0.0) & (t < 1.0)
        acc = np.maximum(acc, m * band(d, 0.0035))
        hgt += m * (0.0006 * band(d, 0.0035) + seam(d - 0.006) * 0.6)
        pull = front & tor & (length(P[:, [0, 1]] - (b - ab * 0.06)) < 0.008)
        acc = np.maximum(acc, pull.astype(float))
        hgt += 0.0015 * pull
    # chest pocket: vertical zip on his left chest
    m = front & tor & (np.abs(x + 0.095) < 0.004) & (y > 0.22) & (y < 0.355)
    acc = np.maximum(acc, m.astype(float))
    hgt += 0.0005 * m
    # logo patch on the left chest: a dark square with a pale mountain
    lc = np.array([-0.1, 0.33])
    q = P[:, [0, 1]] - lc
    patch = front & tor & (np.abs(q[:, 0]) < 0.0) & False
    # sleeves: armhole, back seam, elbow patch outline, cuff band and velcro tab, logo
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = arm_coords(P, sd)
        near = (R < 0.12) & np.isin(chart_name, ["sleeve_" + sd, "torso", "yoke"])
        hgt += np.where(near & (S > 0.0), seam(S - 0.07) + stitch(S - 0.07), 0.0)
        sl = chart_name == "sleeve_" + sd
        hgt += np.where(sl & (S > 0.07), seam(wrap(TH - np.pi) * 0.07), 0.0)
        hgt += np.where(sl, seam(S - 0.455) * 0.8 + stitch(S - 0.455, 0.004), 0.0)
        tab = sl & (np.abs(wrap(TH - np.pi + 0.35) * 0.068) < 0.016) & (S > 0.462) & (S < 0.51)
        acc = np.maximum(acc, tab.astype(float))
        hgt += 0.0012 * tab
        if sd == "l":
            # logo: dark rounded square on the upper sleeve, pale mountain glyph
            u = wrap(TH - 2.0) * 0.074
            vv = S - 0.15
            sq = sl & (np.abs(u) < 0.024) & (np.abs(vv) < 0.024)
            acc = np.maximum(acc, sq.astype(float))
            hgt += 0.0006 * sq
            mx = np.abs(u)
            glyph = sq & (vv < 0.012 - 0.0 - mx * 1.1) & (vv > -0.012) & (mx < 0.017)
            glyph |= sq & (np.abs(vv + 0.016) < 0.002) & (mx < 0.017)
            third = np.maximum(third, glyph.astype(float))
    # hood: centre seam and a stitched rim round the opening
    hd = chart_name == "hood"
    hgt += np.where(hd, seam(x) * 0.8, 0.0)
    hgt += np.where(hd, stitch(hood_cut(P) + 0.012, 0.0) * 2.0, 0.0)
    # collar: stitch line round the top
    ct = 0.618 + 0.03 * sstep(-0.08, 0.08, z)
    hgt += np.where(chart_name == "collar", stitch(y - ct + 0.012, 0.0) * 2.0, 0.0)
    # colour blocking: the yoke (shoulders), hood and cuffs a shade darker
    dark = np.zeros(n)
    dark = np.maximum(dark, (front & torso_like & (y > yoke_f)).astype(float))
    dark = np.maximum(dark, ((z > 0.04) & torso_like & (y > 0.375)).astype(float))
    dark = np.maximum(dark, (chart_name == "yoke").astype(float))
    dark = np.maximum(dark, np.isin(chart_name, ["hood", "collar"]).astype(float))
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = arm_coords(P, sd)
        dark = np.maximum(dark, ((chart_name == "sleeve_" + sd) & ((S < 0.07) | (S > 0.455))).astype(float))
    lum *= 1.0 - 0.22 * dark
    lum = np.where(lin > 0.5, lum * 0.92, lum)
    return lum, acc, third, hgt


def paint_pants(P, N, lin, chart_name):
    n = len(P)
    lum = 1.0 + 0.05 * vnoise(P, 0.13, 21) + 0.03 * vnoise(P, 0.03, 22)
    acc = np.zeros(n)
    third = np.zeros(n)
    hgt = np.zeros(n)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    seat = chart_name == "seat"
    # belt round the waistband, loops, buckle
    top = pants_top(P)
    belt = seat & (y > top - 0.034) & (y < top - 0.006)
    third = np.maximum(third, belt.astype(float))
    hgt += np.where(seat, 0.0008 * belt + seam(y - top + 0.006) * 0.6 + seam(y - top + 0.034) * 0.6, 0.0)
    ang = np.arctan2(x, -(z - 0.004))
    for a0 in (-2.6, -1.5, -0.6, 0.6, 1.5, 2.6, np.pi):
        loop = seat & (np.abs(wrap(ang - a0)) * 0.17 < 0.006) & (y > top - 0.04) & (y < top - 0.0)
        hgt += 0.001 * loop
    buckle = seat & (np.abs(x) < 0.022) & (z < 0) & (np.abs(y - (top - 0.02)) < 0.017)
    acc = np.maximum(acc, buckle.astype(float))
    third = np.where(buckle, 0.0, third)
    hgt += 0.0012 * buckle
    # centre back seam, fly
    hgt += np.where(seat & (z > 0.0), seam(x), 0.0)
    fly = seat & (z < 0) & (y > -0.11) & (y < top - 0.04)
    hgt += np.where(fly, seam(x - 0.025) + stitch(x - 0.025, 0.0) * 2.0 + seam(x), 0.0)
    for sd in ("l", "r"):
        s = side_sign(sd)
        S, TH, R, SEG, L, pts = leg_coords(P, sd)
        lg = chart_name == "leg_" + sd
        both = lg | (seat & (s * x > 0))
        # out- and inseam
        hgt += np.where(both & (S > 0.03), seam(wrap(TH - s * np.pi / 2) * 0.11) + stitch(wrap(TH - s * np.pi / 2) * 0.11), 0.0)
        hgt += np.where(lg & (S > 0.12), seam(wrap(TH + s * np.pi / 2) * 0.11), 0.0)
        # articulated knee: two darts across the front
        for k0 in (0.405, 0.475):
            hgt += np.where(lg & (np.abs(wrap(TH)) < 0.9), seam(S - k0 - 0.01 * TH ** 2) * 0.9, 0.0)
        # cargo pocket on the outer thigh: outline, flap and snap
        u = wrap(TH - s * np.pi / 2) * 0.115
        vv = S
        inp = lg & (np.abs(u) < 0.07) & (vv > 0.19) & (vv < 0.36)
        edge = np.minimum(0.07 - np.abs(u), np.minimum(vv - 0.19, 0.36 - vv))
        hgt += np.where(inp, 0.0012 + seam(edge) * 0.0 + stitch(edge, 0.004), 0.0)
        hgt += np.where(lg & (np.abs(u) < 0.075) & (np.abs(vv - 0.19) < 0.005), seam(vv - 0.19), 0.0)
        flap = lg & (np.abs(u) < 0.074) & (vv > 0.185) & (vv < 0.225)
        hgt += 0.0012 * flap + np.where(lg & (np.abs(u) < 0.074), seam(vv - 0.225) * 0.8, 0.0)
        snap = lg & (u ** 2 + (vv - 0.212) ** 2 < 0.006 ** 2)
        acc = np.maximum(acc, snap.astype(float))
        hgt += 0.001 * snap
        # scuff guard on the inside of the hem
        sc = lg & (np.abs(wrap(TH + s * np.pi / 2)) < 0.7) & (S > 0.93)
        acc = np.maximum(acc, sc * 0.65)
        hgt += np.where(lg, seam(S - 0.93) * 0.7, 0.0)
    lum = np.where(lin > 0.5, lum * 0.9, lum)
    return lum, acc, third, hgt


def bake_atlas(path_base, v, n, lin, tris, uvpx, tri_chart, names, D, size, painter):
    t0 = time.time()
    attr = np.concatenate([v, n, lin[:, None]], 1).astype(np.float32)
    out = np.zeros((size * size, 7), np.float32)
    tid = -np.ones(size * size, np.int32)
    xy = np.ascontiguousarray(uvpx.astype(np.float32))
    _LIB.raster(len(tris), np.ascontiguousarray(tris.astype(np.int32).ravel()), xy.ravel(), None, 7,
                np.ascontiguousarray(attr.ravel()), size, size, None, out.reshape(-1), tid.ctypes.data)
    m = tid >= 0
    P = out[m, 0:3].astype(np.float64)
    N = out[m, 3:6].astype(np.float64)
    L = out[m, 6].astype(np.float64)
    cn = np.array(names, dtype=object)[tri_chart[tid[m]]]
    lum, acc, third, hgt = painter(P, N, L, cn)
    img = np.zeros((size * size, 4), np.float32)
    img[m, 0] = np.clip(lum * 0.5, 0, 1)
    img[m, 1] = np.clip(acc, 0, 1)
    img[m, 2] = np.clip(third, 0, 1)
    img[m, 3] = 1.0
    H = np.zeros(size * size, np.float32)
    H[m] = hgt
    mask = m.astype(np.uint8)
    pad = np.concatenate([img, H[:, None]], 1).astype(np.float32)
    pad = np.ascontiguousarray(pad)
    _LIB.dilate(size, size, 5, pad.reshape(-1), mask, 8)
    img = pad[:, :4].reshape(size, size, 4)
    H = pad[:, 4].reshape(size, size)
    # tangent-space normal from the height (metres): slope = dH/dpx * D
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * 0.5 * D
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * 0.5 * D
    nn = np.stack([-gx, -gy, np.ones_like(H)], -1)
    nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path_base + "_albedo.png", optimize=True)
    Image.fromarray(((nn * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8), "RGB").save(path_base + "_normal.png", optimize=True)
    print("  atlas %s %dpx, %.0f px/m, %d charts, %.1fs" % (os.path.basename(path_base), size, D, len(names), time.time() - t0))


# ------------------------------------------------------------------ gear colouring (vertex ids)
def gear_ids(g, v):
    """COLOR.b for gear: 0 = base colour, 0.5 = accent, 1 = dark (liner, sole)."""
    b = np.zeros(len(v))
    if isinstance(g, Helmet):
        b = (helmet_solid(v) < -0.005).astype(float)                  # liner inside the shell
    elif isinstance(g, Boot):
        q = boot_local(v, g.sd)
        b = np.where(q[:, 1] < -0.088, 1.0, 0.0)                       # sole and lugs
        buck = (np.abs(q[:, 1] + 0.03) < 0.007) & (q[:, 2] < -0.095) | (np.abs(q[:, 1] + 0.008) < 0.007) & (np.abs(q[:, 2] + 0.045) < 0.011)
        b = np.where(buck & (q[:, 1] > -0.04), 0.5, b)
    elif isinstance(g, Glove):
        q = g.local(v)
        s = side_sign(g.sd)
        palm = (q[:, 0] * -s > 0.012) & (q[:, 1] > 0.02)              # grippy palm and fingers
        strap = np.abs(q[:, 1] + 0.048) < 0.006
        b = np.where(palm | strap, 0.5, 0.0)
    elif isinstance(g, Strap):
        q = v - HC
        b = np.where(np.abs(q[:, 1] - 0.012) > 0.014, 0.5, 0.0)       # thin grey edges on the black band
    elif isinstance(g, Gaiter):
        b = np.where(vnoise(v, 0.03, 5) > 0.35, 0.5, 0.0)
    elif isinstance(g, GoggleFrame):
        q = v - HC
        b = np.where(-q[:, 2] > 0.125, 0.5, 0.0)                      # dark face of the frame
    return b


def simple_uv(g, v):
    """Metric UVs for the tiled fabric detail on gear (gaiter, gloves)."""
    if isinstance(g, Glove):
        q = g.local(v)
        return np.stack([np.arctan2(q[:, 2], q[:, 0]) * 0.045, q[:, 1]], 1)
    q = v - HC
    return np.stack([np.arctan2(q[:, 0], -q[:, 2]) * 0.08, q[:, 1]], 1)


# ------------------------------------------------------------------ export
SURFACE_MAT = {"jacket": "jacket", "shirt": "shirt", "pants": "pants", "helmet": "helmet", "goggle_frame": "goggle_frame",
               "goggle_lens": "goggle_lens", "strap": "strap", "gaiter": "gaiter", "glove_l": "glove", "glove_r": "glove",
               "boot_l": "boot", "boot_r": "boot"}
HEAD_GROUP = {"helmet", "goggle_frame", "goggle_lens", "strap", "gaiter"}


ATLAS_SIZE = {"jacket": 2048, "pants": 1024}


def build_all(proj, prev=None, only=None):
    gs = all_garments()
    if only:
        gs = [g for g in gs if g.name in only or g.name.split("_")[0] in only]
    t0 = time.time()
    out = []
    for g in gs:
        v, n, tris = mesh_garment(g)
        out.append((g, v, n, tris))
    sdfs = [g.sdf for g in gs]

    def scene(p):
        d = None
        for f in sdfs:
            x = f(p)
            d = x if d is None else np.minimum(d, x)
        return d

    assets = os.path.join(proj, "assets", "rider")
    os.makedirs(assets, exist_ok=True)
    surfaces = []
    meshes_prev = []
    for g, v, n, tris in out:
        ao = bake_ao(v, n, scene)
        ex = g.extra(v)
        w = g.weights(v)
        bi, bw = top4(w)
        col = np.zeros((len(v), 4))
        col[:, 0] = ex[:, 0]
        col[:, 1] = ao
        col[:, 2] = np.maximum(ex[:, 2], gear_ids(g, v))
        col[:, 3] = ex[:, 1]
        key = g.name.split("_")[0] if g.name.split("_")[0] in COLORS else g.name
        pc = np.tile(np.array(COLORS.get(key, (0.5, 0.5, 0.5))), (len(v), 1)) * (1.0 - 0.55 * (col[:, 2:3] > 0.75))
        meshes_prev.append((v, n, tris, np.concatenate([pc, ao[:, None]], 1)))
        if isinstance(g, (Jacket, Pants)):
            lin = ex[:, 2] > 0.5
            c = v[tris].mean(1)
            nc = n[tris].mean(1)
            lin_t = lin[tris].sum(1) >= 2
            if isinstance(g, Jacket):
                charts, keys, painter = jacket_charts(), jacket_assign(c, nc, lin_t), paint_jacket
            else:
                charts, keys, painter = pants_charts(), pants_assign(c, nc, lin_t), paint_pants
            src, uvm, chart, tris2, tri_chart, names = split_by_charts(v, tris, keys, charts)
            atlas_size = ATLAS_SIZE[g.name]
            uvpx, D = pack_charts(uvm, chart, tri_chart, tris2, names, atlas_size)
            v2, n2 = v[src], n[src]
            bake_atlas(os.path.join(assets, g.name), v2, n2, ex[src, 2], tris2, uvpx, tri_chart, names, D, atlas_size, painter)
            uv = uvpx / atlas_size
            v, n, tris, col, bi, bw = v2, n2, tris2, col[src], bi[src], bw[src]
            uv_detail_scale = D / atlas_size          # UV units per metre (for the shader's weave tiling)
        else:
            uv = simple_uv(g, v)
            uv_detail_scale = 1.0
        tan = tangents(v, n, uv, tris)
        surfaces.append(dict(name=g.name, mat=SURFACE_MAT.get(g.name, g.name), group="head" if g.name in HEAD_GROUP else "body",
                             v=v, n=n, tan=tan, uv=uv, col=col, bi=bi, bw=bw, tris=tris, uv_per_m=uv_detail_scale))
        print("  %-13s exported %6d verts %6d tris" % (g.name, len(v), len(tris)))
    print("built in %.1fs" % (time.time() - t0))
    if prev:
        os.makedirs(prev, exist_ok=True)
        for ang in (0, 35, 90, 150, 180, 270):
            render_preview(meshes_prev, os.path.join(prev, "bind_%03d.png" % ang), ang)
    return surfaces


def write_raw(surfaces, path_json, path_bin):
    bb = [round(float(x), 6) for x in BOOT_B.T.ravel()]          # x, y, z axes
    meta = {"bones": BONES, "bind": {k: [round(float(x), 6) for x in v] for k, v in J.items()},
            "bind_bases": {"boot_l": bb, "boot_r": bb}, "surfaces": []}
    blob = bytearray()
    for sfc in surfaces:
        ent = {"name": sfc["name"], "material": sfc["mat"], "group": sfc["group"], "nv": len(sfc["v"]), "nt": len(sfc["tris"]),
               "uv_per_m": float(sfc["uv_per_m"])}
        for key, arr, dt in (("pos", sfc["v"], np.float32), ("nrm", sfc["n"], np.float32), ("tan", sfc["tan"], np.float32),
                             ("uv", sfc["uv"], np.float32), ("col", sfc["col"], np.float32), ("bones", sfc["bi"], np.int32),
                             ("weights", sfc["bw"], np.float32), ("idx", sfc["tris"], np.int32)):
            b = np.ascontiguousarray(arr, dtype=dt).tobytes()
            ent[key] = [len(blob), len(b)]
            blob += b
        meta["surfaces"].append(ent)
    with open(path_bin, "wb") as f:
        f.write(blob)
    with open(path_json, "w") as f:
        json.dump(meta, f, indent=1)
    print("wrote %s (%.1f MB)" % (path_bin, len(blob) / 1e6))


def write_weave(path, n=128):
    """Tileable twill weave normal map: diagonal wales with yarn-to-yarn bumps (the shader tiles it
    every ~1.2 cm on the clothes)."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    t = 2 * np.pi / n
    wale = np.sin((x + y) * t * 12)                      # 12 diagonal wales per tile
    yarn = np.sin(x * t * 24) * np.sin(y * t * 24)
    rnd = np.random.default_rng(3).normal(size=(n, n))
    k = np.fft.fft2(rnd) * np.exp(-((np.fft.fftfreq(n)[:, None] ** 2 + np.fft.fftfreq(n)[None, :] ** 2) / 0.004))
    blot = np.real(np.fft.ifft2(k))
    blot /= np.abs(blot).max()
    H = 0.6 * wale + 0.25 * yarn + 0.35 * blot
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * 0.5
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * 0.5
    nn = np.stack([-gx, -gy, np.ones_like(H) * 1.4], -1)
    nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
    Image.fromarray(((nn * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8), "RGB").save(path, optimize=True)


def main():
    proj = sys.argv[1]
    write_weave(os.path.join(proj, "assets", "rider", "weave_normal.png"))
    prev = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    surfaces = build_all(proj, prev, only)
    if not only:
        cache = os.path.join(HERE, ".cache")
        write_raw(surfaces, os.path.join(cache, "rider_raw.json"), os.path.join(cache, "rider_raw.bin"))


if __name__ == "__main__":
    main()
