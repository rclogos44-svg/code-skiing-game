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
           "XL": (5.0, 28.0, 19.0, 15.5, 6.0)}
LANDING_DEG = 32.0       # landing slope, absolute
SWEET = 0.4              # design touchdown point, as a fraction of the landing


def kicker_geometry(size, theta_deg, speeds=None):
    """Ramp / deck / landing lengths for a tabletop on a slope of theta: the ramp curves up to the lip
    angle, the landing is LANDING_DEG steep, and the deck is just long enough that a skier leaving the
    lip at the measured lip speed touches down SWEET of the way down the landing.  `speeds` overrides
    (approach, lip) speed for a kicker in a flowing line, where the speed a rider naturally carries
    from the jump before (measured with --test=line) sets the size of the gap."""
    h, alpha, v_app, v, hw = KICKERS[size]
    if speeds:
        v_app, v = speeds
    th = math.radians(theta_deg)
    s_end = math.tan(math.radians(alpha) + th)
    lr = 2.0 * h / s_end                                  # parabolic ramp: height h, end slope s_end
    ll = h / math.tan(math.radians(LANDING_DEG - theta_deg))
    al = math.atan(s_end - math.tan(th)) - math.radians(3.0)   # world launch angle (skier leaves ~3 deg flat)
    a = 9.81 / (2.0 * v * v * math.cos(al) ** 2)
    b = math.tan(al) + math.tan(th)
    c = SWEET * h
    xt = (b + math.sqrt(b * b + 4.0 * a * c)) / (2.0 * a)
    ld = max(xt - SWEET * ll, 2.0)
    return dict(height=h, ramp=round(lr, 2), deck=round(ld, 2), landing=round(ll, 2), half_width=hw,
                lip_deg=alpha, speed=v, approach_speed=v_app)
# per park: (line, kind, start metres down the park, size or length)
DESIGNS = [
    ("Main Park", [
        ("prog", "kicker", 70, "S"), ("prog", "box", 150, 8.0), ("prog", "kicker", 240, "S"), ("prog", "tube", 330, 8.0),
        ("jump", "kicker", 90, "S"), ("jump", "kicker", 210, "M"), ("jump", "kicker", 350, "L"),
        ("jib", "box", 80, 9.0), ("jib", "rail", 165, 9.0), ("jib", "tube", 250, 9.0), ("jib", "rail", 335, 12.0), ("jib", "box", 420, 12.0),
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
        ("jib", "rail", 90, 10.0), ("jib", "box", 190, 10.0), ("jib", "tube", 290, 10.0),
    ]),
    ("Jib Garden", [
        ("prog", "box", 70, 8.0), ("prog", "tube", 150, 8.0), ("prog", "box", 230, 10.0), ("prog", "kicker", 320, "S"),
        ("jump", "kicker", 90, "S"), ("jump", "kicker", 220, "M"),
        ("jib", "box", 70, 9.0), ("jib", "rail", 140, 9.0), ("jib", "tube", 210, 10.0), ("jib", "rail", 280, 12.0),
        ("jib", "box", 350, 12.0), ("jib", "rail", 420, 14.0),
    ]),
    # after Mammoth Mountain's Main Park (Unbound): a line of four XL tables down the middle (sized
    # for the speed carried from the jump before), jibs top to bottom on both sides - down rails,
    # boxes, tubes, a wide "car box" and a long "lift-tower" rail on the advanced side
    ("Sierra Main Park", [
        ("prog", "box", 60, 8.0), ("prog", "rail", 110, 8.0), ("prog", "widebox", 160, 6.0), ("prog", "tube", 210, 9.0),
        ("prog", "box", 260, 12.0), ("prog", "rail", 320, 10.0), ("prog", "box", 380, 10.0), ("prog", "rail", 440, 12.0),
        ("jump", "kicker", 90, ("XL", 16.1, 13.1, 1.13)), ("jump", "kicker", 150, ("XL", 18.1, 15.3, 2.53)),
        ("jump", "kicker", 218, ("XL", 19.1, 16.4, 3.21)), ("jump", "kicker", 290, ("XL", 19.7, 17.0, 3.84)),
        ("jib", "rail", 60, 10.0), ("jib", "rail", 110, 18.0), ("jib", "tube", 180, 12.0), ("jib", "rail", 240, 14.0),
        ("jib", "widebox", 300, 8.0), ("jib", "rail", 350, 12.0), ("jib", "tube", 410, 10.0), ("jib", "rail", 460, 16.0),
    ]),
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


def apply_parks(g, H, lay, groomed, placer):
    parks = []
    for (score, x0, z0, dx, dz, h0, slope), (name, design) in zip(find_sites(g, H, lay, placer, len(DESIGNS)), DESIGNS):
        theta = math.radians(min(max(slope, 11.0), 16.0))
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
        kickers, rails, tips = [], [], []
        for line, kind, s0, arg in design:
            uc = LINES[line]
            if kind == "kicker":
                # kickers are exact shapes the game adds on top of the regraded slope (sharper than the 2 m grid)
                size, speeds = (arg[0], arg[1:3]) if isinstance(arg, tuple) else (arg, None)
                kg = kicker_geometry(size, math.degrees(theta), speeds)
                if isinstance(arg, tuple) and len(arg) > 3:
                    kg["deck"] = round(max(kg["deck"] - arg[3], 2.0), 2)
                arg = size
                pt = lambda s: [round(x0 + dx * s - dz * uc, 2), round(z0 + dz * s + dx * uc, 2)]
                kg.update(line=line, size=arg, start_s=s0, dir=[dx, dz], origin=pt(s0), lip=pt(s0 + kg["ramp"]),
                          knuckle=pt(s0 + kg["ramp"] + kg["deck"]), end=pt(s0 + kg["ramp"] + kg["deck"] + kg["landing"]))
                kickers.append(kg)
            else:
                a = (x0 + dx * s0 - dz * uc, z0 + dz * s0 + dx * uc)
                b = (x0 + dx * (s0 + arg) - dz * uc, z0 + dz * (s0 + arg) + dx * uc)
                rails.append([round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2), kind, line])
        sx, sz = x0 - dx * 14.0, z0 - dz * 14.0           # spawn near the drop-in so you roll straight in
        parks.append(dict(name=name, start=[round(sx, 1), round(sz, 1), float(g.sample(H, sx, sz))], yaw=math.atan2(-dx, -dz),
                          origin=[round(x0, 1), round(z0, 1)], dir=[dx, dz], slope=round(math.degrees(theta), 1),
                          length=LENGTH, half_width=HALF_W, lines=LINES, kickers=kickers, rails=rails))
        placer.take(x0 + dx * LENGTH * 0.5, z0 + dz * LENGTH * 0.5, LENGTH * 0.5 + 60.0)
        g.log("park %s at (%.0f, %.0f) slope %.1f deg, fit rms %.1f m" % (name, x0, z0, math.degrees(theta), score))
    lay["parks"] = parks
    return parks
