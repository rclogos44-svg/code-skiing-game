"""Fit the game's skeleton (same joints, limits and bone lengths as SkierBody) to the 2D joints
placed on the mute reference photo.  Weak-perspective camera; the photo's 'up' is taken as world
up (camera roll 0).  Prints the pose as a GRAB_POSES entry and draws the fit over the photo."""
import json
import math
import random
import sys

import numpy as np

sys.path.insert(0, '.')
from keypoints import KP, BONES, SKI_LINES  # noqa: E402

THIGH, SHIN, UPPER_ARM, FOREARM = 0.44, 0.43, 0.29, 0.27
HIP_HALF, SHOULDER_HALF, TORSO_LEN, ANKLE_H = 0.095, 0.185, 0.47, 0.15
LIM = {"flex": (-15, 125), "abd": (-25, 45), "rot": (-40, 40), "knee": (0, 140)}
SPINE = {"pitch": (0, 70), "side": (-17, 17), "curve": (-40, 40), "twist": (-26, 26)}
D = math.radians


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def leg_fk(hip, sgn, a):
    flex = D(clamp(a[0], *LIM["flex"]))
    abd = D(clamp(a[1], *LIM["abd"]))
    rot = D(clamp(a[2], *LIM["rot"]))
    kf = D(clamp(a[3], *LIM["knee"]))
    flex = min(flex, D(75) + kf * 0.8)              # hamstrings
    H = rx(flex) @ rz(sgn * abd) @ ry(sgn * rot)
    knee = hip + H @ np.array([0, -THIGH, 0])
    S = H @ rx(-kf)
    ankle = knee + S @ np.array([0, -SHIN, 0])
    B = S @ rx(D(15))
    ski = ankle - B[:, 1] * ANKLE_H - B[:, 2] * 0.03
    return knee, ankle, B, ski


def ik2(a, target, l1, l2, pole):
    d = target - a
    dl = np.linalg.norm(d)
    dist = clamp(dl, abs(l1 - l2) + 0.001, l1 + l2 - 0.001)
    dr = d / dl if dl > 1e-4 else np.array([0, -1.0, 0])
    c = clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
    bend = pole - a
    bend = bend - dr * bend.dot(dr)
    n = np.linalg.norm(bend)
    bend = bend / n if n > 1e-4 else np.array([1.0, 0, 0])
    return a + dr * (l1 * c) + bend * (l1 * math.sqrt(1 - c * c))


NAMES = ["l_flex", "l_abd", "l_rot", "l_knee", "r_flex", "r_abd", "r_rot", "r_knee", "pitch", "side", "curve", "twist",
         "hips_yaw", "hl_x", "hl_y", "hl_z", "free_x", "free_y", "free_z", "tilt", "roll", "cam_yaw", "cam_pitch", "dist", "ox", "oy"]
FOCAL = 731.0          # px: a phone's ~70 deg vertical field of view over 1024 px
CX, CY = 289.0, 512.0


def body(p):
    P = dict(zip(NAMES, p))
    j = {}
    LH = ry(D(P["hips_yaw"]))
    for sd, sgn in (("l", -1.0), ("r", 1.0)):
        hip = np.array([sgn * HIP_HALF, -0.04, 0.0])
        knee, ankle, B, ski = leg_fk(hip, sgn, [P[sd + "_flex"], P[sd + "_abd"], P[sd + "_rot"], P[sd + "_knee"]])
        j["hip_" + sd], j["knee_" + sd], j["ankle_" + sd] = LH @ hip, LH @ knee, LH @ ankle
        j["B_" + sd], j["ski_" + sd] = LH @ B, LH @ ski
    pt, sd_, cv, tw = D(P["pitch"]), D(P["side"]), D(P["curve"]), D(P["twist"])
    base = ry(tw)
    low = base @ rz(sd_ + cv * 0.2) @ rx(-pt * 0.4)
    mid = base @ rz(sd_ + cv * 0.55) @ rx(-pt * 0.75)
    top = base @ rz(sd_ + cv) @ rx(-pt)
    j["pelvis"] = np.zeros(3)
    j["waist"] = low[:, 1] * 0.07
    j["lumbar"] = j["waist"] + low[:, 1] * 0.16
    j["thoracic"] = j["lumbar"] + mid[:, 1] * 0.16
    j["chest"] = j["thoracic"] + top[:, 1] * (TORSO_LEN - 0.32)
    hb = top @ rx(pt * 0.8 - D(6))
    j["head"] = j["chest"] + hb[:, 1] * 0.19
    for sd, sgn in (("l", -1.0), ("r", 1.0)):
        j["shoulder_" + sd] = j["chest"] - top[:, 1] * 0.07 + top[:, 0] * (sgn * SHOULDER_HALF)
    # photo: right hand grabs, left arm is free
    j["hand_r"] = j["shoulder_r"] + top @ (np.array([P["hl_x"], P["hl_y"], P["hl_z"]]) / 100.0)
    j["hand_l"] = j["shoulder_l"] + top @ (np.array([P["free_x"], P["free_y"], P["free_z"]]) / 100.0)
    for sd, sgn in (("l", -1.0), ("r", 1.0)):
        sh = j["shoulder_" + sd]
        j["elbow_" + sd] = ik2(sh, j["hand_" + sd], UPPER_ARM, FOREARM, sh + top @ np.array([sgn * 0.5, -0.2, 0.45]))
    j["_top"] = top
    return j, P


def world_rot(P):
    return rx(D(P["tilt"])) @ rz(D(P["roll"]))


def view_rot(P):
    return rx(D(P["cam_pitch"])) @ ry(D(P["cam_yaw"]))


def project(p):
    j, P = body(p)
    M = view_rot(P) @ world_rot(P)
    off = np.array([P["ox"], P["oy"], -P["dist"]])

    def proj(v):
        q = M @ v + off
        z = max(-q[2], 0.2)
        return (CX + FOCAL * q[0] / z, CY - FOCAL * q[1] / z, q[2])
    out = {}
    for k, v in j.items():
        if k.startswith("_") or k.startswith("B_"):
            continue
        out[k] = proj(v)
    for sd in ("l", "r"):
        tipdir = -j["B_" + sd][:, 2]
        for nm, o in (("tip", 0.75), ("tail", -0.75)):
            out["ski%s_%s" % (nm, sd)] = proj(j["ski_" + sd] + tipdir * o)
    return out, j, P


def line_dist(pt, ln):
    (x1, y1), (x2, y2) = ln
    dx, dy = x2 - x1, y2 - y1
    return abs(dy * (pt[0] - x1) - dx * (pt[1] - y1)) / math.hypot(dx, dy)


PRIOR = [105, -10, 20, 120, 100, 15, 15, 120, 25, 0, -28, 10, -10, 10, -45, -20, -30, 45, 0, 0, 0, 0, -25, 1.9, 0.25, 0.25]
STEP = [10, 8, 8, 10, 10, 8, 8, 10, 8, 5, 8, 8, 8, 8, 8, 8, 10, 10, 10, 8, 8, 20, 8, 0.2, 0.05, 0.05]
PRIOR_W = {"cam_yaw": 0, "dist": 0, "ox": 0, "oy": 0, "hl_x": 0.02, "hl_y": 0.02, "hl_z": 0.02, "free_x": 0.02, "free_y": 0.02,
           "free_z": 0.02, "cam_pitch": 0.3, "tilt": 1.0, "roll": 0.4, "hips_yaw": 1.0, "pitch": 0.5, "twist": 0.8,
           "l_flex": 0.3, "r_flex": 0.3, "l_knee": 0.3, "r_knee": 0.3}
WEIGHT = {"hand_l": 0.25, "head": 0.6}


def cost(p):
    out, j, P = project(p)
    c = 0.0
    for k, (u, v) in KP.items():
        du, dv = out[k][0] - u, out[k][1] - v
        c += WEIGHT.get(k, 1.0) * (du * du + dv * dv)
    for sd, ln in SKI_LINES.items():
        for nm in ("tip", "tail"):
            c += 2.0 * line_dist(out["ski%s_%s" % (nm, sd)], ln) ** 2
    # joint and spine limits are hard in the game: penalise asking past them here too
    for i, nm in enumerate(NAMES[:8]):
        lo, hi = LIM[nm.split("_")[1]]
        c += 50.0 * (max(0, lo - p[i]) + max(0, p[i] - hi)) ** 2
    for nm, (lo, hi) in SPINE.items():
        v = p[NAMES.index(nm)]
        c += 50.0 * (max(0, lo - v) + max(0, v - hi)) ** 2
    # the arm can't stretch: each hand must be within reach of its shoulder
    for sd in ("l", "r"):
        r = np.linalg.norm(j["hand_" + sd] - j["shoulder_" + sd])
        c += 1e6 * max(0.0, r - (UPPER_ARM + FOREARM) * 0.98) ** 2
    # the right hand is holding the left ski: on its axis, within the front 0.7 m or back 0.5 m
    rel = j["hand_r"] - j["ski_l"]
    ax = -j["B_l"][:, 2]
    along = rel.dot(ax)
    perp = np.linalg.norm(rel - ax * along)
    c += 2e5 * max(0.0, perp - 0.09) ** 2 + 2e5 * (max(0.0, along - 0.7) + max(0.0, -0.5 - along)) ** 2
    # what the photo shows about depth: his left knee and left hand are nearer the camera than
    # the right knee and the pelvis (view +z = toward the camera)
    c += 2e4 * max(0.0, out["pelvis"][2] - out["hand_r"][2] + 0.05) ** 2
    # we see his face and the jacket zip: the camera is in front of his chest (model front = -Z)
    camdir = view_rot(P).T @ np.array([0, 0, 1.0])
    chest_fwd = -(world_rot(P) @ j["_top"])[:, 2]
    c += 2e5 * max(0.0, 0.35 - camdir.dot(chest_fwd)) ** 2
    # stay near a plausible prior where the photo can't tell (depth)
    for i, nm in enumerate(NAMES):
        w = PRIOR_W.get(nm, 0.15)
        c += w * ((p[i] - PRIOR[i]) / STEP[i]) ** 2 * 10.0
    return c


def descend(p, steps):
    best = cost(p)
    for scale in (1.0, 0.5, 0.25, 0.12, 0.06):
        for _ in range(60):
            improved = False
            for i in range(len(p)):
                for sgn in (1, -1):
                    q = list(p)
                    q[i] += sgn * steps[i] * scale
                    c = cost(q)
                    if c < best - 1e-6:
                        p, best = q, c
                        improved = True
            if not improved:
                break
    return p, best


def main():
    random.seed(4)
    results = []
    for yaw in range(120, 250, 15):
        for roll in (-20, 0, 20):
            p = list(PRIOR)
            p[NAMES.index("cam_yaw")] = yaw
            p[NAMES.index("roll")] = roll
            p, c = descend(p, STEP)
            results.append((c, p))
            print("start yaw %4d roll %3d -> cost %9.0f" % (yaw, roll, c), flush=True)
    results.sort(key=lambda r: r[0])
    c, p = results[0]
    # basin hopping: shake the legs and spine (inside their limits) and re-settle, keep the best
    for it in range(int(sys.argv[1]) if len(sys.argv) > 1 else 60):
        q = list(p)
        for i in range(13):
            q[i] += random.uniform(-1, 1) * STEP[i] * 4
        q, cq = descend(q, STEP)
        if cq < c:
            p, c = q, cq
            print("  hop %d -> cost %.0f" % (it, c), flush=True)
    p, c = descend(p, [s * 0.5 for s in STEP])
    out, j, P = project(p)
    err = [math.hypot(out[k][0] - u, out[k][1] - v) for k, (u, v) in KP.items() if k != "hand_l"]
    print("best cost %.0f, mean joint error %.1f px (max %.1f)" % (c, sum(err) / len(err), max(err)))
    for k in NAMES:
        print("  %-9s %8.2f" % (k, P[k]))
    rel = j["hand_r"] - j["ski_l"]
    ax = -j["B_l"][:, 2]
    print("right hand on the left ski: %.2f m toward the tip, %.2f m off the axis, side %+.2f" % (rel.dot(ax), np.linalg.norm(rel - ax * rel.dot(ax)), rel.dot(j["B_l"][:, 0])))
    print("free (left) hand in torso frame:", ((np.linalg.inv(j["_top"]) @ (j["hand_l"] - j["shoulder_l"]))).round(3).tolist())
    reach = {sd: float(np.linalg.norm(j["hand_" + sd] - j["shoulder_" + sd])) for sd in ("l", "r")}
    print("arm reach used: %s (max %.2f)" % (reach, UPPER_ARM + FOREARM))
    # camera direction in the body's (root) frame, for rendering the game from the same angle
    camdir = (view_rot(P)).T @ np.array([0, 0, 1.0])
    res = {"params": P, "camdir": camdir.tolist(), "proj": {k: v[:2] for k, v in out.items()}}
    json.dump(res, open("fit.json", "w"), indent=1)


if __name__ == "__main__":
    main()
