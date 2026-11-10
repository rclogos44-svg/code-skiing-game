"""Terrain parks for SUMMIT: three groomed park runs regraded into the 2 m heightmap, each with a
flat staging area and three lines - progression (small jumps, ride-on boxes), jump line (S/M/L
tabletop kickers with shaped landings) and jib line (boxes, rails, tubes).  Kickers are stamped
into the terrain so physics and visuals agree; rails, boxes and tubes are exported for the game
to build (scripts/world/park.gd).  Imported by gen_terrain.py (`g` is the generator module)."""
import math

import numpy as np

LENGTH = 560.0           # skiable length (m) after the staging area
STAGE = 40.0             # flat-ish staging area at the top
HALF_W = 60.0            # half width of the groomed park
BLEND = 30.0             # regrade blends into the natural slope over this distance
LINES = {"prog": -34.0, "jump": 0.0, "jib": 34.0}
# tabletop kickers: height (m), lip angle above horizontal (deg), approach speed shown on the sign (m/s),
# lip speed a skier arriving at that speed actually has (measured in --test=physics), half width
KICKERS = {"S": (1.2, 22.0, 10.0, 9.3, 3.5), "M": (2.0, 26.0, 13.0, 11.2, 4.0), "L": (3.0, 30.0, 16.0, 13.2, 4.5),
           "XL": (5.0, 28.0, 19.0, 15.5, 6.0), "XS": (0.7, 18.0, 9.0, 8.5, 2.2)}
LANDING_DEG = 32.0       # landing slope, absolute
SWEET = 0.4              # design touchdown point, as a fraction of the landing


def kicker_geometry(size, theta_deg, speeds=None, h2=None):
    """Ramp / deck / landing lengths for a tabletop on a slope of theta: the ramp curves up to the lip
    angle, the landing is LANDING_DEG steep, and the deck is just long enough that a skier leaving the
    lip at the measured lip speed touches down SWEET of the way down the landing.  `speeds` overrides
    (approach, lip) speed for a kicker in a flowing line, where the speed a rider naturally carries
    from the jump before (measured with --test=line) sets the size of the gap."""
    h, alpha, v_app, v, hw = KICKERS[size]
    if speeds:
        v_app, v = speeds
    h2 = h if h2 is None else h2                          # knuckle height: lower than the lip = step-down
    th = math.radians(theta_deg)
    s_end = math.tan(math.radians(alpha) + th)
    lr = 2.0 * h / s_end                                  # parabolic ramp: height h, end slope s_end
    ll = h2 / math.tan(math.radians(LANDING_DEG - theta_deg))
    al = math.atan(s_end - math.tan(th)) - math.radians(3.0)   # world launch angle (skier leaves ~3 deg flat)
    a = 9.81 / (2.0 * v * v * math.cos(al) ** 2)
    b = math.tan(al) + math.tan(th)
    c = (h - h2) + SWEET * h2
    xt = (b + math.sqrt(b * b + 4.0 * a * c)) / (2.0 * a)
    ld = max(xt - SWEET * ll, 2.0)
    g = dict(height=h, ramp=round(lr, 2), deck=round(ld, 2), landing=round(ll, 2), half_width=hw,
             lip_deg=alpha, speed=v, approach_speed=v_app)
    if h2 != h:
        g["knuckle_h"] = h2
    return g
# rails / boxes / tubes: height of the top above the snow (matches park.gd HEIGHT)
RAIL_H = {"box": 0.35, "rail": 0.55, "tube": 0.5, "widebox": 0.45}


def rail_points(shape, L, theta, kind):
    """(s, u, h) points of a shaped rail along its lane, h above the park's plane (the regraded slope
    drops tan(theta) per metre, so a "flat" stretch climbs above the snow).  Shapes: straight down
    rail, kink (down-flat-down, the last part steeper), flatdown, tabletop (up-flat-down), rainbow
    (an arch), srail (an S in plan view), flat (level the whole way, for gap-to-rail)."""
    t = math.tan(theta)
    h0 = RAIL_H[kind]
    if shape == "kink":
        l1, l2 = 0.35 * L, 0.3 * L
        return [(0, 0, h0), (l1, 0, h0), (l1 + l2, 0, h0 + t * l2), (L, 0, h0)]
    if shape == "flatdown":
        l1 = 0.45 * L
        return [(0, 0, h0), (l1, 0, h0 + t * l1), (L, 0, h0)]
    if shape == "tabletop":
        l1, l2, up = 0.25 * L, 0.25 * L, 0.4
        return [(0, 0, h0), (l1, 0, h0 + up + t * l1), (l1 + l2, 0, h0 + up + t * (l1 + l2)), (L, 0, h0)]
    if shape == "rainbow":
        return [(L * i / 14.0, 0, h0 + 0.6 * math.sin(math.pi * i / 14.0)) for i in range(15)]
    if shape == "srail":
        return [(L * i / 16.0, 0.8 * math.sin(TWO_PI * i / 16.0), h0) for i in range(17)]
    if shape == "flat":
        return [(0, 0, h0), (L, 0, h0 + t * L)]
    return [(0, 0, h0), (L, 0, h0)]


TWO_PI = 2.0 * math.pi
RAIL_LIP = dict(h=0.7, lip_deg=20.0, deck=0.4, gap=1.3, rail_h=0.9, half_width=1.6)


def rail_lip(s0, u0, L, theta, x0, z0, dx, dz, line):
    """Gap to rail: a small snow lip, a short gap, then a level ("flat") rail that runs out over the
    slope - you pop off the lip onto it, slide it and drop off the end."""
    g = RAIL_LIP
    th = theta
    s_end = math.tan(math.radians(g["lip_deg"]) + th)
    lr = 2.0 * g["h"] / s_end
    ll = g["h"] / math.tan(math.radians(LANDING_DEG) - th)
    pt = lambda t: [round(x0 + dx * (s0 + t) - dz * u0, 2), round(z0 + dz * (s0 + t) + dx * u0, 2)]
    k = dict(height=g["h"], ramp=round(lr, 2), deck=g["deck"], landing=round(ll, 2), half_width=g["half_width"],
             lip_deg=g["lip_deg"], speed=8.0, approach_speed=9.0, line=line, size="S", start_s=s0, dir=[dx, dz],
             origin=pt(0.0), lip=pt(lr), knuckle=pt(lr + g["deck"]), end=pt(lr + g["deck"] + ll), rail_lip=True)
    r0 = s0 + lr + g["deck"] + g["gap"]
    t = math.tan(th)
    pts = [[round(x0 + dx * (r0 + s) - dz * u0, 2), round(z0 + dz * (r0 + s) + dx * u0, 2), round(g["rail_h"] + t * s, 3)]
           for s in (0.0, L)]
    return k, dict(kind="rail", shape="flat", line=line, pts=pts)


# superpipes (s0, s1 down the park, centred on lane u): flat bottom, quarter-circle walls of radius
# `radius` that steepen to `wall_deg` at the top (a heightfield can't hold a true vertical; the game
# sends riders straight up off the coping), a flat deck behind the coping and an outer bank back down
PIPE = dict(flat=18.0, radius=7.5, wall_deg=84.0, deck=3.0, outer=12.0, taper=25.0)
PIPES = {"Sierra Main Park": [(378.0, 548.0, 0.0)]}


def pipe_geometry(s0, s1, u, x0, z0, dx, dz):
    g = dict(PIPE)
    th = math.radians(g["wall_deg"])
    g["wall_h"] = round(g["radius"] * (1.0 - math.cos(th)), 3)
    g["wall_w"] = round(g["radius"] * math.sin(th), 3)
    g.update(origin=[round(x0 + dx * s0 - dz * u, 2), round(z0 + dz * s0 + dx * u, 2)], dir=[dx, dz], length=s1 - s0,
             start_s=s0)
    return g


# snow shapes (exact profiles the game adds on top of the regraded slope, like kickers - see
# TerrainData.shape_offset): rollers, banks (a curved wall beside the lane to carve up), step-ups
# (takeoff, a gap, a face up to a deck higher than the lip, then a rollout)
STEPUP = dict(h1=1.2, back=1.2, gap=1.6, face=3.0, h2=3.3, deck=7.0)


def shape_entry(kind, arg, opt, s0, uc, theta, x0, z0, dx, dz, line):
    pt = lambda t: [round(x0 + dx * (s0 + t) - dz * uc, 2), round(z0 + dz * (s0 + t) + dx * uc, 2)]
    e = dict(kind=kind, line=line, start_s=s0, dir=[dx, dz], origin=pt(0.0))
    if kind == "roller":
        h, L = arg
        e.update(height=h, length=L, half_width=float(opt.get("hw", 7.0)))
    elif kind == "bank":
        h, L = arg
        e.update(height=h, length=L, half_width=float(opt.get("hw", 5.0)), side=float(opt.get("side", 1.0)),
                 wall=float(opt.get("wall", 4.5)))
    elif kind == "stepup":
        g = dict(STEPUP)
        g.update(opt.get("geo", {}))
        lr = 2.0 * g["h1"] / math.tan(math.radians(24.0) + theta)
        ll = g["h2"] / math.tan(math.radians(LANDING_DEG) - theta)
        e.update(height=g["h1"], ramp=round(lr, 2), back=g["back"], gap=g["gap"], face=g["face"], top=g["h2"],
                 deck=g["deck"], landing=round(ll, 2), half_width=float(opt.get("hw", 4.5)),
                 length=round(lr + g["back"] + g["gap"] + g["face"] + g["deck"] + ll, 2))
        e["lip"] = pt(lr)
        e["deck_start"] = pt(lr + g["back"] + g["gap"] + g["face"])
    e["end"] = pt(e["length"])
    return e


# per park: (line, kind, start metres down the park, size or length)
DESIGNS = [
    ("Main Park", [
        ("prog", "kicker", 70, "S"), ("prog", "box", 150, 8.0), ("prog", "kicker", 240, "S"), ("prog", "tube", 330, 8.0),
        ("jump", "kicker", 90, "S"), ("jump", "kicker", 210, "M"), ("jump", "kicker", 350, "L"),
        # jib line: a row of three side by side, then shaped rails, a gap-to-rail and another row
        ("jib", "box", 70, 9.0, {"u": 27.0}), ("jib", "rail", 70, 9.0), ("jib", "tube", 70, 9.0, {"u": 41.0}),
        ("jib", "rail", 150, 12.0, {"u": 30.0, "shape": "kink"}), ("jib", "box", 150, 10.0, {"u": 39.0, "shape": "flatdown"}),
        ("jib", "rail", 235, 10.0, {"u": 30.0, "shape": "rainbow"}), ("jib", "box", 235, 12.0, {"u": 39.0, "shape": "tabletop"}),
        ("jib", "raillip", 320, 7.0),
        ("jib", "rail", 400, 12.0, {"u": 34.0, "shape": "srail"}), ("jib", "rail", 400, 12.0, {"u": 26.0}),
        ("jib", "box", 400, 12.0, {"u": 42.0}),
        ("prog", "box", 400, 8.0, {"u": -38.0}), ("prog", "widebox", 400, 8.0, {"u": -30.0}),
    ]),
    ("Big Air Park", [
        ("prog", "kicker", 70, "S"), ("prog", "kicker", 170, "S"), ("prog", "box", 270, 9.0),
        # a flowing big-air line: one large, then six XL tables ~12 m apart (landing to next ramp), each
        # sized for the (approach, lip) speed a rider carries from the jump before when riding it
        # straight (measured with --test=line), last value = deck trim (m) that centres the touchdown
        ("jump", "kicker", 50, ("L", 12.5, 10.2)), ("jump", "kicker", 96, ("XL", 14.9, 11.7, 0.54)),
        ("jump", "kicker", 156, ("XL", 16.7, 13.7, 1.08)), ("jump", "kicker", 216, ("XL", 17.6, 14.7, 1.08)),
        ("jump", "kicker", 276, ("XL", 18.0, 15.0, 0.72)), ("jump", "kicker", 336, ("XL", 18.4, 15.5, 1.35)),
        ("jump", "kicker", 398, ("XL", 18.6, 15.7, 2.16)),
        ("jib", "rail", 80, 10.0, {"u": 28.0}), ("jib", "box", 80, 10.0), ("jib", "tube", 80, 10.0, {"u": 40.0}),
        ("jib", "raillip", 170, 8.0),
        ("jib", "rail", 260, 12.0, {"u": 30.0, "shape": "kink"}), ("jib", "rail", 260, 10.0, {"u": 39.0, "shape": "rainbow"}),
        ("jib", "rail", 350, 12.0, {"shape": "srail"}),
    ]),
    ("Jib Garden", [
        ("prog", "box", 70, 8.0), ("prog", "tube", 150, 8.0), ("prog", "box", 230, 10.0), ("prog", "kicker", 320, "S"),
        ("jump", "kicker", 90, "S"), ("jump", "kicker", 220, "M"),
        # the jib garden: rows of rails side by side and every shape - tabletop, S-rail, rainbow,
        # kinks, a flat-down box, a gap-to-rail
        ("jib", "box", 60, 9.0, {"u": 27.0}), ("jib", "rail", 60, 9.0), ("jib", "widebox", 60, 8.0, {"u": 41.0}),
        ("jib", "rail", 130, 12.0, {"shape": "tabletop"}), ("jib", "box", 130, 12.0, {"u": 43.0, "shape": "tabletop"}),
        ("jib", "rail", 200, 14.0, {"u": 30.0, "shape": "srail"}), ("jib", "rail", 200, 10.0, {"u": 40.0, "shape": "rainbow"}),
        ("jib", "raillip", 275, 8.0),
        ("jib", "rail", 350, 14.0, {"u": 28.0, "shape": "kink"}), ("jib", "box", 350, 12.0, {"u": 36.0, "shape": "flatdown"}),
        ("jib", "tube", 350, 12.0, {"u": 44.0}),
        ("jib", "rail", 430, 14.0), ("jib", "box", 430, 14.0, {"u": 27.0}), ("jib", "box", 430, 12.0, {"u": 42.0, "shape": "rainbow"}),
        ("prog", "box", 400, 10.0, {"u": -38.0}), ("prog", "tube", 400, 10.0, {"u": -30.0}),
    ]),
    # after Mammoth Mountain's Main Park (Unbound): five lanes side by side - jibs on both edges, a
    # medium jump line ending in a step-down, the XL line down the middle (each jump sized for the
    # speed carried from the one before), and a transfer lane of hips that kick you left and right
    # across it; the mega pipe fills the bottom of the run (pipes, below)
    ("Sierra Main Park", [
        ("jib_l", "box", 45, 8.0, {"u": -56.0}), ("jib_l", "rail", 45, 8.0), ("jib_l", "tube", 45, 8.0, {"u": -44.0}),
        ("jib_l", "rail", 110, 12.0, {"shape": "kink"}), ("jib_l", "raillip", 180, 7.0),
        ("jib_l", "rail", 255, 10.0, {"u": -53.0, "shape": "rainbow"}), ("jib_l", "widebox", 255, 8.0, {"u": -45.0}),
        ("jib_l", "rail", 335, 12.0, {"shape": "srail"}), ("jib_l", "box", 410, 12.0, {"shape": "tabletop"}),
        ("jib_l", "rail", 480, 14.0, {"u": -54.0}), ("jib_l", "box", 480, 12.0, {"u": -46.0}),
        ("med", "kicker", 55, "M"), ("med", "kicker", 105, "M"), ("med", "kicker", 165, "L"),
        ("med", "kicker", 235, "L", {"h2": 1.6}),
        ("jump", "kicker", 90, ("XL", 16.1, 13.1, 1.13)), ("jump", "kicker", 150, ("XL", 18.1, 15.3, 2.53)),
        ("jump", "kicker", 218, ("XL", 19.1, 16.4, 3.21)), ("jump", "kicker", 290, ("XL", 19.7, 17.0, 3.84)),
        ("hip", "kicker", 60, "M", {"u": 21.0, "yaw": 22.0}), ("hip", "kicker", 140, "M", {"u": 37.0, "yaw": -22.0}),
        ("hip", "kicker", 220, "L", {"u": 21.0, "yaw": 22.0}), ("hip", "kicker", 300, "M", {"u": 33.0, "h2": 1.0}),
        ("jib", "rail", 55, 10.0), ("jib", "widebox", 55, 6.0, {"u": 56.0}), ("jib", "rail", 100, 18.0),
        ("jib", "tube", 165, 12.0), ("jib", "rail", 165, 12.0, {"u": 44.0}), ("jib", "rail", 230, 14.0, {"shape": "srail"}),
        ("jib", "raillip", 300, 8.0), ("jib", "rail", 370, 14.0, {"shape": "kink"}),
        ("jib", "rail", 440, 12.0, {"shape": "rainbow"}), ("jib", "tube", 440, 10.0, {"u": 56.0}), ("jib", "box", 505, 10.0),
    ], {"jib_l": -50.0, "med": -27.0, "jump": 0.0, "hip": 27.0, "jib": 50.0}),
    # Ridgeline Park: the freestyle development park.  Four routes side by side that cross where the
    # hips send you: a progression lane (forgiving small tables, wide boxes, low rollers, room to
    # learn the arrow tricks), a flow lane (rollers, banked walls, side hits, a transfer hip and a
    # step-up), the big line (tables sized for the speed carried from the one before, for off-axis
    # spins and flips, a transfer hip and a step-down) and a jib lane (flat-down, down, kinked,
    # rainbow and S rails, boxes).  Sections are quick drops in the pause menu.
    ("Ridgeline Park", [
        ("prog", "roller", 22, (0.5, 10.0)), ("prog", "roller", 36, (0.5, 10.0)), ("prog", "kicker", 62, ("S", 12.1, 11.1)),
        ("prog", "widebox", 130, 8.0, {"u": -46.0}), ("prog", "box", 130, 8.0, {"u": -38.0}),
        ("prog", "kicker", 190, ("S", 15.8, 14.2)), ("prog", "roller", 255, (0.6, 12.0)), ("prog", "widebox", 290, 10.0),
        ("prog", "kicker", 350, ("S", 16.6, 15.0)), ("prog", "widebox", 425, 10.0, {"u": -46.0}), ("prog", "box", 425, 10.0, {"u": -38.0}),
        ("flow", "roller", 24, (0.9, 12.0)), ("flow", "roller", 42, (1.0, 12.0)), ("flow", "roller", 60, (0.8, 10.0)),
        ("flow", "bank", 92, (2.2, 34.0), {"side": 1.0, "u": -14.0}),
        ("flow", "kicker", 148, ("XS", 15.2, 13.6), {"u": -21.0, "yaw": 28.0}),
        ("flow", "kicker", 180, ("M", 15.6, 13.2), {"yaw": 24.0}),
        ("flow", "roller", 248, (1.0, 12.0)), ("flow", "roller", 266, (1.2, 14.0)),
        ("flow", "bank", 292, (2.2, 34.0), {"side": -1.0, "u": -16.0}),
        ("flow", "kicker", 346, ("XS", 15.6, 14.0), {"u": -8.0, "yaw": -28.0}),
        ("flow", "stepup", 380, None),
        ("flow", "roller", 468, (0.8, 10.0)), ("flow", "roller", 484, (0.8, 10.0)),
        # sized for the speed carried from the jump before (line_design, --test=line): 1.3-2 s of air
        ("big", "kicker", 55, ("M", 11.7, 10.1)), ("big", "kicker", 112, ("L", 14.2, 12.0)),
        ("big", "kicker", 178, ("XL", 15.7, 12.3)), ("big", "kicker", 250, ("XL", 16.6, 13.3, 0.86)),
        ("bighip", "kicker", 330, ("L", 15.8, 12.7), {"u": 16.0, "yaw": -24.0}),
        ("bighip", "kicker", 410, ("L", 14.3, 12.0), {"u": 16.0, "h2": 1.8}),
        ("jib", "widebox", 40, 8.0, {"u": 40.0}), ("jib", "rail", 40, 8.0, {"u": 48.0, "shape": "flatdown"}),
        ("jib", "rail", 100, 12.0), ("jib", "rail", 165, 14.0, {"shape": "kink"}), ("jib", "box", 230, 12.0, {"shape": "flatdown"}),
        ("jib", "rail", 295, 10.0, {"shape": "rainbow"}), ("jib", "rail", 360, 14.0, {"shape": "srail"}),
        ("jib", "raillip", 425, 7.0), ("jib", "box", 490, 12.0, {"u": 40.0, "shape": "tabletop"}), ("jib", "tube", 490, 10.0, {"u": 48.0}),
    ], {"prog": -42.0, "flow": -14.0, "big": 16.0, "jib": 44.0},
        [("Top", 0.0, 0.0), ("Progression", 0.0, -42.0), ("Flow line", 0.0, -14.0), ("Big line", 30.0, 16.0),
         ("Jib lane", 20.0, 44.0), ("Step-up", 350.0, -14.0)]),
]


def find_sites(g, H, lay, placer, count):
    """Wide, even slopes of 11-20 degrees that a straight 600 m park fits on."""
    Hs = g.blur(H, 10)
    sites = []
    ss = np.arange(-STAGE, LENGTH + 1.0, 10.0, dtype=np.float32)
    us = np.arange(-HALF_W, HALF_W + 1.0, 15.0, dtype=np.float32)
    S, U = np.meshgrid(ss, us)
    vg = lay.get("village", {})
    for z in np.arange(450.0, g.WORLD - 450.0, 60.0):
        for x in np.arange(450.0, g.WORLD - 450.0, 60.0):
            _, gx, gz = g.bilinear(Hs, np.array([x / g.SP]), np.array([z / g.SP]))
            gl = math.hypot(float(gx[0]), float(gz[0])) / g.SP
            if not (0.15 < gl < 0.42):
                continue
            dx, dz = -float(gx[0]) / (gl * g.SP), -float(gz[0]) / (gl * g.SP)
            PX = x + S * dx - U * dz
            PZ = z + S * dz + U * dx
            if PX.min() < 300 or PZ.min() < 300 or PX.max() > g.WORLD - 300 or PZ.max() > g.WORLD - 300:
                continue
            h, _, _ = g.bilinear(H, PX / g.SP, PZ / g.SP)
            b, a = np.polyfit(S.ravel(), h.ravel(), 1)
            res = h - (a + b * S)
            slope = math.degrees(math.atan(-b))
            rms = float(np.sqrt(np.mean(res * res)))
            if not (9.0 <= slope <= 22.0) or rms > 8.0 or float(np.abs(res).max()) > 20.0:
                continue
            if any(not placer.free(x + s * dx, z + s * dz, HALF_W * 0.4) for s in np.arange(0.0, LENGTH, 70.0)):
                continue
            near = math.hypot(x - vg["x"], z - vg["z"]) if vg else 0.0
            sites.append((rms + abs(slope - 14.0) * 0.4 + near * 0.0008, x, z, dx, dz, float(a), slope))
    sites.sort()
    chosen = []
    for s in sites:
        if all(math.hypot(s[1] - c[1], s[2] - c[2]) > 700.0 for c in chosen):
            chosen.append(s)
        if len(chosen) >= count:
            break
    return chosen


# parks added after the mountain's natural features are placed (so adding them doesn't move any
# cliff, lip or gully elsewhere): they regrade their own footprint and drop the features inside it
LATE = {"Ridgeline Park"}
PARK_SLOPE = {"Ridgeline Park": 10.0}
_late_jobs = []


def apply_parks(g, H, lay, groomed, placer):
    parks = []
    lay["parks"] = parks
    sites = find_sites(g, H, lay, placer, len(DESIGNS) + 24)
    legacy = [e for e in DESIGNS if e[0] not in LATE]
    for site, entry in zip(sites, legacy):            # the original parks keep their original sites
        _apply_one(g, H, lay, groomed, placer, site, entry)
    for entry in DESIGNS:
        if entry[0] in LATE:
            _late_jobs.append((sites[len(legacy):], entry))
    return parks


def _footprint_hits(site, feats):
    score, x0, z0, dx, dz, h0, slope = site
    hits = []
    for f in feats:
        rx, rz = f["x"] - x0, f["z"] - z0
        s_ = rx * dx + rz * dz
        u_ = -rx * dz + rz * dx
        if -STAGE - BLEND - 15.0 < s_ < LENGTH + 75.0 and abs(u_) < HALF_W + BLEND + 15.0:     # the regraded area
            hits.append(dict(f, _s=round(s_), _u=round(u_)))
    return hits


def apply_late_parks(g, H, lay, groomed, masks):
    """The parks in LATE, after the features: regrade, then clear the features and their rock /
    gully masks from the footprint (the regrade has flattened them)."""
    for spare, entry in _late_jobs:
        # a learning park wants an even, moderate slope (speed you can control on the small lines),
        # on ground with none of the mountain's cliffs, lips or gullies in the way
        taken = [(p["origin"][0], p["origin"][1]) for p in lay["parks"]]
        ok = []
        for st in spare:
            # slide the park sideways up to 30 m if that clears a feature at its edge
            for shift in (0.0, -15.0, 15.0, -30.0, 30.0):
                sc, x0, z0, dx, dz, h0, slope = st
                cand = (sc + abs(shift) * 0.02, x0 - dz * shift, z0 + dx * shift, dx, dz, h0, slope)
                if not _footprint_hits(cand, lay.get("features", [])) \
                        and all(math.hypot(cand[1] - a, cand[2] - b) > 700.0 for a, b in taken):
                    ok.append(cand)
                    break
        pool = ok if ok else spare
        site = min(pool, key=lambda st: abs(st[6] - 12.5) + st[0] * 0.05)
        g.log("late park %s: slope %.1f deg (clear candidates %s; all %s)" % (entry[0], site[6], ", ".join("%.1f" % st[6] for st in ok),
              ", ".join("%.1f/%s" % (st[6], [(h["type"], h["_s"], h["_u"]) for h in _footprint_hits(st, lay.get("features", []))]) for st in spare)))
        pk, (i0, i1, j0, j1, w) = _apply_one(g, H, lay, groomed, None, site, entry)
        o = np.array(pk["origin"])
        d = np.array(pk["dir"])
        keep = []
        for f in lay.get("features", []):
            rel = np.array([f["x"], f["z"]]) - o
            s_ = float(rel @ d)
            u_ = float(rel @ np.array([-d[1], d[0]]))
            if -STAGE - BLEND - 15.0 < s_ < LENGTH + 75.0 and abs(u_) < HALF_W + BLEND + 15.0:
                g.log("  %s: removed %s %s (inside the park)" % (pk["name"], f["type"], f.get("name", "")))
                continue
            keep.append(f)
        lay["features"] = keep
        for m in masks.values():
            m[i0:i1 + 1, j0:j1 + 1] *= (1.0 - w)
    _late_jobs.clear()


def _apply_one(g, H, lay, groomed, placer, site, entry):
    parks = lay["parks"]
    score, x0, z0, dx, dz, h0, slope = site
    if True:
        name, design = entry[0], entry[1]
        lines = entry[2] if len(entry) > 2 else LINES
        sections = entry[3] if len(entry) > 3 else []
        theta = math.radians(min(max(slope, 11.0), 16.0))
        if name in PARK_SLOPE:
            theta = math.radians(PARK_SLOPE[name])     # a gentler regrade than the hillside (speed you can learn on)
        pad = HALF_W + BLEND + 10.0
        r = LENGTH + STAGE + 80.0
        i0 = int(max(min(z0, z0 + dz * r) - pad - STAGE, 0) / g.SP)
        i1 = int(min(max(z0, z0 + dz * r) + pad + STAGE, g.WORLD) / g.SP)
        j0 = int(max(min(x0, x0 + dx * r) - pad - STAGE, 0) / g.SP)
        j1 = int(min(max(x0, x0 + dx * r) + pad + STAGE, g.WORLD) / g.SP)
        gz = np.arange(i0, i1 + 1, dtype=np.float32) * g.SP
        gx = np.arange(j0, j1 + 1, dtype=np.float32) * g.SP
        PX, PZ = np.meshgrid(gx, gz)
        Sg = (PX - x0) * dx + (PZ - z0) * dz
        Ug = -(PX - x0) * dz + (PZ - z0) * dx
        # regrade: gentle staging area, then an even park slope; low banks along the sides
        target = h0 + STAGE * math.tan(math.radians(3.0)) - np.tan(np.float32(math.radians(3.0))) * np.minimum(Sg + STAGE, STAGE) \
            - np.float32(math.tan(theta)) * np.maximum(Sg, 0.0)
        target = target + g.smoothstep(HALF_W - 14.0, HALF_W, np.abs(Ug)) * 1.2
        w = g.smoothstep(HALF_W + BLEND, HALF_W, np.abs(Ug)) * g.smoothstep(-STAGE - BLEND, -STAGE, Sg) \
            * g.smoothstep(LENGTH + 60.0, LENGTH, Sg)
        sub = H[i0:i1 + 1, j0:j1 + 1]
        H[i0:i1 + 1, j0:j1 + 1] = sub * (1 - w) + target * w
        groomed[i0:i1 + 1, j0:j1 + 1] = np.maximum(groomed[i0:i1 + 1, j0:j1 + 1], g.smoothstep(HALF_W + 12.0, HALF_W, np.abs(Ug)) * (Sg > -STAGE - 10))
        kickers, rails, tips, shapes = [], [], [], []
        for item in design:
            line, kind, s0, arg = item[:4]
            opt = item[4] if len(item) > 4 else {}
            uc = float(opt["u"]) if "u" in opt else float(lines[line])
            if kind == "kicker":
                # kickers are exact shapes the game adds on top of the regraded slope (sharper than the 2 m grid);
                # opt: "u" lateral position, "yaw" (deg, + toward the park's right) for a hip / transfer jump,
                # "h2" knuckle height below the lip for a step-down
                size, speeds = (arg[0], arg[1:3]) if isinstance(arg, tuple) else (arg, None)
                yaw = math.radians(float(opt.get("yaw", 0.0)))
                kdx = dx * math.cos(yaw) - dz * math.sin(yaw)
                kdz = dz * math.cos(yaw) + dx * math.sin(yaw)
                th_k = math.degrees(math.atan(math.tan(theta) * math.cos(yaw)))    # fall along the kicker
                kg = kicker_geometry(size, th_k, speeds, opt.get("h2"))
                if isinstance(arg, tuple) and len(arg) > 3:
                    kg["deck"] = round(max(kg["deck"] - arg[3], 2.0), 2)
                ox, oz = x0 + dx * s0 - dz * uc, z0 + dz * s0 + dx * uc
                pt = lambda t: [round(ox + kdx * t, 2), round(oz + kdz * t, 2)]
                kg.update(line=line, size=size, start_s=s0, dir=[kdx, kdz], origin=pt(0.0), lip=pt(kg["ramp"]),
                          knuckle=pt(kg["ramp"] + kg["deck"]), end=pt(kg["ramp"] + kg["deck"] + kg["landing"]))
                if yaw != 0.0:
                    kg["yaw"] = float(opt["yaw"])
                kickers.append(kg)
            elif kind in ("roller", "bank", "stepup"):
                shapes.append(shape_entry(kind, arg, opt, s0, uc, theta, x0, z0, dx, dz, line))
            elif kind == "raillip":
                k, r = rail_lip(s0, uc, float(arg), theta, x0, z0, dx, dz, line)
                kickers.append(k)
                rails.append(r)
            elif "shape" in opt:
                pts = [[round(x0 + dx * (s0 + ps) - dz * (uc + pu), 2), round(z0 + dz * (s0 + ps) + dx * (uc + pu), 2), round(ph, 3)]
                       for ps, pu, ph in rail_points(opt["shape"], float(arg), theta, kind)]
                rails.append(dict(kind=kind, shape=opt["shape"], line=line, pts=pts))
            else:
                a = (x0 + dx * s0 - dz * uc, z0 + dz * s0 + dx * uc)
                b = (x0 + dx * (s0 + arg) - dz * uc, z0 + dz * (s0 + arg) + dx * uc)
                rails.append([round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2), kind, line])
        pipes = [pipe_geometry(a, b, u, x0, z0, dx, dz) for a, b, u in PIPES.get(name, [])]
        sx, sz = x0 - dx * 14.0, z0 - dz * 14.0           # spawn near the drop-in so you roll straight in
        pk = dict(name=name, start=[round(sx, 1), round(sz, 1), float(g.sample(H, sx, sz))], yaw=math.atan2(-dx, -dz),
                  origin=[round(x0, 1), round(z0, 1)], dir=[dx, dz], slope=round(math.degrees(theta), 1),
                  length=LENGTH, half_width=HALF_W, lines=lines, kickers=kickers, rails=rails, pipes=pipes)
        if shapes:
            pk["shapes"] = shapes
        if sections:
            # quick drops: a point a few metres above the section, on its lane, facing down the park
            pk["sections"] = [dict(name=n, pos=[round(x0 + dx * (ss - 14.0) - dz * uu, 1), round(z0 + dz * (ss - 14.0) + dx * uu, 1)])
                              for n, ss, uu in sections]
        parks.append(pk)
        if placer is not None:
            placer.take(x0 + dx * LENGTH * 0.5, z0 + dz * LENGTH * 0.5, LENGTH * 0.5 + 60.0)
        g.log("park %s at (%.0f, %.0f) slope %.1f deg, fit rms %.1f m" % (name, x0, z0, math.degrees(theta), score))
    return pk, (i0, i1, j0, j1, w)
