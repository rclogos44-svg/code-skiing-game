"""Terrain features for SUMMIT: cliff bands, wind lips, halfpipe gullies, frozen lakes, a mogul run,
glade trails and landmark sites.  Stamped into the 2 m heightmap so physics and visuals agree.
Imported by gen_terrain.py (functions receive the generator module `g` to reuse its helpers)."""
import math

import numpy as np

CLIFF_NAMES = ["Eagle Cliffs", "Raven Drop", "Thunder Ledge", "Granite Steps", "Falcon Band", "Lynx Drop",
               "Wolf Cliffs", "Ibex Ledge", "Chamois Steps", "Marmot Drop", "Condor Wall", "Hawk Ledge",
               "Bear Steps", "Fox Drop", "Owl Cliffs", "Stag Ledge", "Crow Band", "Pika Drop", "Otter Steps", "Elk Ledge",
               "Badger Steps", "Heron Ledge", "Viper Wall", "Kestrel Drop", "Bison Ledge", "Moose Drop", "Wolverine Wall", "Hare Steps"]
LIP_NAMES = ["Wind Lip", "Cornice Kicker", "Pillow Pop", "Spine Launch", "Rollover Kicker", "Drift Ramp",
             "Snow Wave", "Ridge Hit", "Gap Lip", "Whale Back"]


class Placer:
    """Keeps features apart from each other and from pistes, spawns, races, lifts and the village."""

    def __init__(self, g, lay):
        self.g = g
        self.lay = lay
        self.taken = []          # (x, z, radius)
        self.lines = []          # (ax, az, bx, bz, clearance)
        for p in lay.get("pistes", []):
            pts = p["pts"]
            for i in range(len(pts) - 1):
                self.lines.append((pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], p["width"] + 25.0))
        for c in lay.get("challenges", []):
            if c.get("type") == "race":
                pth = c["path"]
                for i in range(len(pth) - 1):
                    self.lines.append((pth[i][0], pth[i][1], pth[i + 1][0], pth[i + 1][1], 30.0))
        for lf in lay.get("lifts", []):
            self.lines.append((lf["bottom"][0], lf["bottom"][1], lf["top"][0], lf["top"][1], 40.0))
        for d in lay.get("drop_zones", []):
            self.taken.append((d["x"], d["z"], 110.0))
        for v in lay.get("viewpoints", []):
            self.taken.append((v["x"], v["z"], 60.0))
        vg = lay.get("village", {})
        if vg:
            self.taken.append((vg["x"], vg["z"], 420.0))

    def free(self, x, z, r):
        if not (300 < x < self.g.WORLD - 300 and 300 < z < self.g.WORLD - 300):
            return False
        for (tx, tz, tr) in self.taken:
            if math.hypot(x - tx, z - tz) < r + tr:
                return False
        for (ax, az, bx, bz, cl) in self.lines:
            d = float(self.g.seg_dist(np.array([x]), np.array([z]), ax, az, bx, bz)[0])
            if d < r + cl:
                return False
        return True

    def take(self, x, z, r):
        self.taken.append((x, z, r))


def _window(g, x, z, r):
    n = g.N
    i0 = max(int((z - r) / g.SP), 0)
    i1 = min(int((z + r) / g.SP) + 1, n - 1)
    j0 = max(int((x - r) / g.SP), 0)
    j1 = min(int((x + r) / g.SP) + 1, n - 1)
    gz = np.arange(i0, i1 + 1, dtype=np.float32) * g.SP
    gx = np.arange(j0, j1 + 1, dtype=np.float32) * g.SP
    PX, PZ = np.meshgrid(gx, gz)
    return (slice(i0, i1 + 1), slice(j0, j1 + 1)), PX, PZ


def stamp_cliff(g, H, mask, x, z, dx, dz, width, drop, seed):
    """A cliff band across the fall line: lip, near-vertical face, then a steepened landing that
    rejoins the original slope."""
    below = drop * 3.4 + 24.0
    win, PX, PZ = _window(g, x, z, width * 0.5 + below + 12.0)
    a = (PX - x) * dx + (PZ - z) * dz          # + downhill
    c = -(PX - x) * dz + (PZ - z) * dx
    rng = np.random.default_rng(seed)
    ph = rng.uniform(0, 6.28, 3)
    wav = (np.sin(c / 9.0 + ph[0]) * 2.2 + np.sin(c / 4.1 + ph[1]) * 0.9 + np.sin(c / 23.0 + ph[2]) * 3.0)
    ap = a - wav
    lat = g.smoothstep(width * 0.5, width * 0.5 - 14.0, np.abs(c))
    face = g.smoothstep(-1.0, 2.8, ap)
    recover = 1.0 - g.smoothstep(4.0, below, ap)
    lip = 0.7 * np.exp(-((ap + 2.6) / 2.2) ** 2)
    H[win] += (-drop * face * recover + lip) * lat
    mask[win] = np.maximum(mask[win], (face * (1.0 - g.smoothstep(2.8, 9.0, ap)) * lat).astype(np.float32))


def stamp_lip(g, H, x, z, dx, dz, width, height):
    """Natural kicker: ramp, sharp lip, step-down landing."""
    ramp = 5.5 + height * 2.4
    win, PX, PZ = _window(g, x, z, width * 0.5 + ramp + 30.0)
    a = (PX - x) * dx + (PZ - z) * dz
    c = -(PX - x) * dz + (PZ - z) * dx
    lat = g.smoothstep(width * 0.5, width * 0.5 - 6.0, np.abs(c))
    up = np.where(a <= 0.0, height * np.clip((a + ramp) / ramp, 0.0, 1.0) ** 1.8, 0.0)
    after = np.where(a > 0.0, -height * 1.0 * g.smoothstep(0.0, 2.0, a) * (1.0 - g.smoothstep(5.0, 30.0, a)), 0.0)
    H[win] += (up + after) * lat


def stamp_gully(g, H, mask, pts, width, depth):
    """U-shaped halfpipe gully along a polyline, faded in/out at the ends."""
    P = np.array(pts, dtype=np.float32)
    seglen = np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1]))
    total = float(seglen.sum())
    x0, x1 = P[:, 0].min(), P[:, 0].max()
    z0, z1 = P[:, 1].min(), P[:, 1].max()
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    win, PX, PZ = _window(g, cx, cz, max(x1 - x0, z1 - z0) * 0.5 + width + 10.0)
    dmin = np.full(PX.shape, 1e9, dtype=np.float32)
    along = np.zeros(PX.shape, dtype=np.float32)
    acc = 0.0
    for i in range(len(P) - 1):
        ax, az, bx, bz = P[i, 0], P[i, 1], P[i + 1, 0], P[i + 1, 1]
        d = g.seg_dist(PX, PZ, ax, az, bx, bz)
        L = max(float(seglen[i]), 1e-3)
        t = np.clip(((PX - ax) * (bx - ax) + (PZ - az) * (bz - az)) / (L * L), 0.0, 1.0)
        closer = d < dmin
        dmin = np.where(closer, d, dmin)
        along = np.where(closer, acc + t * L, along)
        acc += L
    half = width * 0.5
    prof = np.clip(1.0 - (dmin / half) ** 2, 0.0, 1.0) ** 0.75
    ends = g.smoothstep(0.0, 45.0, along) * g.smoothstep(total, total - 45.0, along)
    # small raised lips along the rims make the walls launch
    rim = 0.8 * np.exp(-((dmin - half * 1.02) / 3.0) ** 2)
    H[win] += (-depth * prof + rim) * ends
    mask[win] = np.maximum(mask[win], (prof * ends).astype(np.float32))
    return total


def label_components(mask):
    """4-connected components of a boolean grid (BFS). Returns list of index arrays."""
    seen = np.zeros(mask.shape, dtype=bool)
    comps = []
    ii, jj = np.nonzero(mask)
    for s in range(len(ii)):
        i0, j0 = ii[s], jj[s]
        if seen[i0, j0]:
            continue
        stack = [(i0, j0)]
        seen[i0, j0] = True
        cells = []
        while stack:
            i, j = stack.pop()
            cells.append((i, j))
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, b = i + di, j + dj
                if 0 <= a < mask.shape[0] and 0 <= b < mask.shape[1] and mask[a, b] and not seen[a, b]:
                    seen[a, b] = True
                    stack.append((a, b))
        comps.append(np.array(cells))
    return comps


def make_lake(g, H, lake_mask, x, z, radius, seed):
    """Flatten an irregular basin into a frozen lake slightly below its shore."""
    rng = np.random.default_rng(seed)
    win, PX, PZ = _window(g, x, z, radius * 1.5 + 20.0)
    ang = np.arctan2(PZ - z, PX - x)
    ph = rng.uniform(0, 6.28, 3)
    rr = radius * (1.0 + 0.18 * np.sin(ang * 2 + ph[0]) + 0.1 * np.sin(ang * 3 + ph[1]) + 0.06 * np.sin(ang * 5 + ph[2]))
    d = np.hypot(PX - x, PZ - z)
    inside = d < rr
    if not inside.any():
        return None
    sub = H[win]
    level = float(np.percentile(sub[inside], 20)) - 0.4
    w = g.smoothstep(rr + 14.0, rr, d)
    sub[...] = np.where(inside, level, sub * (1 - w) + np.maximum(sub, level + 0.3) * w)
    lake_mask[win] = np.maximum(lake_mask[win], inside.astype(np.float32))
    return level


def apply_features(g, H, lay, lake4):
    """Returns (features list, landmarks list, masks dict)."""
    A = g.Analysis(H)
    pl = Placer(g, lay)
    rng = np.random.default_rng(99)
    cliff_mask = np.zeros(H.shape, dtype=np.float32)
    gully_mask = np.zeros(H.shape, dtype=np.float32)
    lake_mask = np.zeros(H.shape, dtype=np.float32)
    feats = []
    names = list(CLIFF_NAMES)
    rng.shuffle(names)
    edge = (A.X > 320) & (A.X < g.WORLD - 320) & (A.Z > 320) & (A.Z < g.WORLD - 320)

    def fall_dir(x, z):
        _, gx, gz = g.bilinear(H, np.array([x / g.SP]), np.array([z / g.SP]))
        v = np.array([-float(gx[0]), -float(gz[0])])
        ln = float(np.hypot(*v))
        return (v / ln) if ln > 1e-6 else np.array([0.0, 1.0])

    def consistent(x, z, d, length=90.0, lo=16.0, hi=40.0):
        for k in range(-2, 9):
            px, pz = x + d[0] * k * length / 8.0, z + d[1] * k * length / 8.0
            iz = min(max(int(round(pz / A.sp)), 0), A.slope.shape[0] - 1)
            ix = min(max(int(round(px / A.sp)), 0), A.slope.shape[1] - 1)
            if not (lo <= A.slope[iz, ix] <= hi):
                return False
        return True

    # ---- cliff bands: per region (count, drop range, width range, slope window)
    plan = {3: (6, (8, 14), (50, 110), (22, 40)), 5: (6, (10, 17), (50, 120), (24, 42)),
            0: (5, (7, 12), (50, 100), (20, 38)), 1: (3, (3, 5), (30, 60), (16, 30)),
            2: (3, (3, 5), (25, 50), (14, 28)), 4: (2, (3, 4.5), (25, 45), (14, 28))}
    for rid, (count, dr, wr, (slo, shi)) in plan.items():
        cand = (A.region == rid) & edge & (A.slope > slo) & (A.slope < shi)
        ci, cj = np.nonzero(cand)
        order = rng.permutation(len(ci))
        made = 0
        for k in order:
            if made >= count:
                break
            x, z = float(A.X[ci[k], cj[k]]), float(A.Z[ci[k], cj[k]])
            width = float(rng.uniform(*wr))
            if not pl.free(x, z, width * 0.5 + 40.0):
                continue
            d = fall_dir(x, z)
            if not consistent(x, z, d, 70.0 + width * 0.3, slo - 4, shi + 6):
                continue
            drop = float(rng.uniform(*dr))
            stamp_cliff(g, H, cliff_mask, x, z, float(d[0]), float(d[1]), width, drop, int(rng.integers(1 << 30)))
            pl.take(x, z, width * 0.5 + 60.0)
            nm = names.pop() if names else "Cliff Band"
            feats.append(dict(type="cliff", name=nm, x=x, z=z, dx=float(d[0]), dz=float(d[1]), width=width, drop=round(drop, 1), region=rid))
            made += 1
    # ---- natural kickers / wind lips on rollovers
    lnames = list(LIP_NAMES)
    rng.shuffle(lnames)
    convex = (g.blur(A.H, 3) - A.H) < -0.6
    for rid, count in ((1, 3), (0, 2), (2, 2), (4, 2), (5, 1)):
        cand = (A.region == rid) & edge & (A.slope > 14) & (A.slope < 30) & convex
        ci, cj = np.nonzero(cand)
        made = 0
        for k in rng.permutation(len(ci)):
            if made >= count:
                break
            x, z = float(A.X[ci[k], cj[k]]), float(A.Z[ci[k], cj[k]])
            if not pl.free(x, z, 45.0):
                continue
            d = fall_dir(x, z)
            if not consistent(x, z, d, 50.0, 10.0, 36.0):
                continue
            hgt = float(rng.uniform(1.6, 3.2))
            width = float(rng.uniform(12, 22))
            stamp_lip(g, H, x, z, float(d[0]), float(d[1]), width, hgt)
            pl.take(x, z, 70.0)
            feats.append(dict(type="lip", name=lnames.pop() if lnames else "Kicker", x=x, z=z, dx=float(d[0]), dz=float(d[1]), width=width, height=round(hgt, 1), region=rid))
            made += 1
    # ---- halfpipe gullies
    for rid, nm in ((1, "Halfpipe Gully"), (2, "Serpent Gully"), (0, "Glacier Pipe")):
        cand = (A.region == rid) & edge & (A.slope > 14) & (A.slope < 26)
        ci, cj = np.nonzero(cand)
        for k in rng.permutation(len(ci))[:400]:
            x, z = float(A.X[ci[k], cj[k]]), float(A.Z[ci[k], cj[k]])
            if not pl.free(x, z, 40.0):
                continue
            pts = g.descend_path(H, x, z, 420.0, step=10.0, momentum=0.9)
            if len(pts) < 36:
                continue
            ok = True
            for (px, pz) in pts[::3]:
                iz = min(max(int(round(pz / A.sp)), 0), A.slope.shape[0] - 1)
                ix = min(max(int(round(px / A.sp)), 0), A.slope.shape[1] - 1)
                if not (8.0 <= A.slope[iz, ix] <= 32.0) or not pl.free(px, pz, 22.0):
                    ok = False
                    break
            if not ok:
                continue
            total = stamp_gully(g, H, gully_mask, pts, 26.0, 6.0)
            for (px, pz) in pts[::4]:
                pl.take(px, pz, 35.0)
            mid = pts[len(pts) // 2]
            feats.append(dict(type="gully", name=nm, x=mid[0], z=mid[1], path=[[round(p[0], 1), round(p[1], 1)] for p in pts[::2]],
                              length=round(total), region=rid))
            break
    # ---- frozen lakes: the largest natural basins (depression-filled areas) become frozen lakes
    lakes = []
    comps = label_components(lake4)
    comps.sort(key=len, reverse=True)
    for comp in comps[:6]:
        if len(comp) < 350 or len(lakes) >= 2:
            break
        ci_, cj_ = comp[:, 0].mean(), comp[:, 1].mean()
        x, z = float(cj_ * g.SPM), float(ci_ * g.SPM)
        r = float(math.sqrt(len(comp) * g.SPM * g.SPM / math.pi))
        r = min(max(r, 45.0), 140.0)
        if not pl.free(x, z, r):
            continue
        lvl = make_lake(g, H, lake_mask, x, z, r, len(lakes) + 7)
        if lvl is None:
            continue
        pl.take(x, z, r + 40.0)
        lakes.append((x, z, r))
    if not lakes:
        # no natural basin available: build one on the flattest valley floor of Powder Valley
        flat = (A.region == 1) & edge & (g.blur(A.slope, 6) < 6.0)
        p = A.best(flat, -A.H)
        if p is not None and pl.free(p[0], p[1], 80.0):
            make_lake(g, H, lake_mask, p[0], p[1], 80.0, 3)
            pl.take(p[0], p[1], 120.0)
            lakes.append((p[0], p[1], 80.0))
    for i, (x, z, r) in enumerate(lakes):
        feats.append(dict(type="lake", name=["Frozen Lake", "Lac Blanc", "Mirror Tarn"][i], x=x, z=z, radius=round(r), region=g.region_at(x, z)))
    # ---- moguls on the black run
    for p in lay.get("pistes", []):
        if p["difficulty"] != "black":
            continue
        pts = p["pts"]
        a, b = int(len(pts) * 0.35), int(len(pts) * 0.7)
        sec = pts[a:b]
        if len(sec) < 4:
            continue
        P = np.array(sec, dtype=np.float32)
        cx, cz = float(P[:, 0].mean()), float(P[:, 1].mean())
        win, PX, PZ = _window(g, cx, cz, float(np.hypot(np.ptp(P[:, 0]), np.ptp(P[:, 1]))) * 0.5 + 40.0)
        dmin = np.full(PX.shape, 1e9, dtype=np.float32)
        for i in range(len(P) - 1):
            dmin = np.minimum(dmin, g.seg_dist(PX, PZ, P[i, 0], P[i, 1], P[i + 1, 0], P[i + 1, 1]))
        ang = math.atan2(P[-1, 1] - P[0, 1], P[-1, 0] - P[0, 0])
        u = (PX * math.cos(ang) + PZ * math.sin(ang))
        v = (-PX * math.sin(ang) + PZ * math.cos(ang))
        bumps = 0.6 * np.sin(u * 2 * math.pi / 8.0) * np.sin(v * 2 * math.pi / 7.0 + u * 0.35)
        m = g.smoothstep(p["width"] * 0.6, p["width"] * 0.35, dmin)
        H[win] += bumps * m
        feats.append(dict(type="moguls", name="Mogul Alley", x=float(P[len(P) // 2, 0]), z=float(P[len(P) // 2, 1]), region=4))
    # ---- glade trails through the forest (trees are cleared along them)
    tnames = ["Fox Trail", "Pine Glade Trail", "Owl Hollow Run"]
    for k, rid in enumerate((2, 2, 4)):
        cand = (A.region == rid) & edge & (A.slope > 12) & (A.slope < 26)
        for (ox, oz, _r) in pl.taken[-6:]:
            cand &= np.hypot(A.X - ox, A.Z - oz) > 150.0
        p = A.best(cand, A.H + rng.uniform(0, 80, A.H.shape))
        if p is None or not pl.free(p[0], p[1], 20.0):
            continue
        pts = g.descend_path(H, p[0], p[1], 700.0, step=12.0, momentum=0.8)
        if len(pts) < 25:
            continue
        feats.append(dict(type="trail", name=tnames[k], x=pts[0][0], z=pts[0][1],
                          path=[[round(q[0], 1), round(q[1], 1)] for q in pts[::2]], region=rid))
    # ---- landmark sites
    marks = []

    def site(rid, kind, name, mode):
        m = (A.region == rid) & edge
        if mode == "peak":
            p = A.best(m, A.H)
        else:
            p = A.best(m & (A.slope < 14.0), A.prom * 2.0 + A.H * 0.05)
        if p is None:
            return
        for _ in range(30):
            if pl.free(p[0], p[1], 12.0) or mode == "peak":
                break
            m &= np.hypot(A.X - p[0], A.Z - p[1]) > 40.0
            p = A.best(m & (A.slope < 14.0), A.prom * 2.0 + A.H * 0.05)
            if p is None:
                return
        pl.take(p[0], p[1], 30.0)
        marks.append(dict(type=kind, name=name, x=p[0], z=p[1], region=rid))
    site(0, "summit_cross", "Summit Cross", "peak")
    site(1, "hut", "Powder Hut", "flat")
    site(3, "weather_station", "Weather Station", "peak")
    site(2, "ruin", "Old Trapper's Cabin", "flat")
    site(5, "summit_cross", "Backcountry Cairn", "peak")
    masks = {"cliff": cliff_mask, "gully": gully_mask, "lake": lake_mask}
    return feats, marks, masks
