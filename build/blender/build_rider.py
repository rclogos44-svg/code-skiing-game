"""Builds the rider in Blender (headless, built-in tools only - no add-ons).

The body: modelled standing (a soup of lofted limbs and torso sections, voxel-remeshed into one
surface and smoothed), skinned to an armature that matches SkierRig's 16 bones with Blender's
bone-heat weights, then posed into the game's bind pose: the measured ski stance in rider.json
(pelvis at the origin, torso upright, hips and knees flexed, elbows out).  Bone lengths are the
game's, so posing moves only angles and every joint lands exactly on the bind joints.  The body is
never exported: it is what the clothes are draped over and collide with.

The clothes: baggy pants and a fitted jacket with a standing collar, each a shell round the
standing body, carried into the stance and settled there by Blender's cloth simulation (see the
garments section).  --export writes them (decimated, with ray-cast AO) for build/rider_from_blender.py,
which adds the lining, weights, atlases, hood and gear and writes the game's raw rider files.

Coordinates: the game uses +Y up, -Z forward, +X the rider's right.  Blender uses +Z up; the rider is
built facing Blender's +Y with the usual Y-up -> Z-up conversion  (x, y, z) -> (x, -z, y).

usage:  tools/blender/blender -b --factory-startup --python build/blender/build_rider.py -- \
            --out DIR [--stage body|pants|clothes] [--render [--rest]] [--samples N] [--export NPZ]
writes  DIR/rider_stage.blend, with --render DIR/*.png (clay renders), with --export the garments
        (the repo keeps them as build/rider_garments.npz, so building the game needs no Blender)
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


# ------------------------------------------------------------------ coordinates
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))          # game -> Blender (proper rotation)


def g2b(v):
    return C @ Vector(v)


def b2g(v):
    return C.transposed() @ Vector(v)


def nrm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


# ------------------------------------------------------------------ joints (game space)
# Bind: identical to build/gen_rider.py (and the rider.json SkierRig reads).
J = {"pelvis": np.zeros(3), "waist": np.array([0, 0.07, 0.0]), "lumbar": np.array([0, 0.23, 0.0]),
     "thoracic": np.array([0, 0.39, 0.0]), "chest": np.array([0, 0.54, 0.0]), "head": np.array([0, 0.70, 0.0])}
for _s, _sd in ((-1.0, "l"), (1.0, "r")):
    J["hip_" + _sd] = np.array([_s * 0.095, -0.04, 0.0])
    J["knee_" + _sd] = J["hip_" + _sd] + 0.44 * nrm([_s * 0.079, -0.268, -0.339])
    J["ankle_" + _sd] = J["knee_" + _sd] + 0.43 * nrm([-_s * 0.059, -0.373, 0.207])
    J["shoulder_" + _sd] = np.array([_s * 0.185, 0.47, 0.0])
    J["elbow_" + _sd] = J["shoulder_" + _sd] + 0.29 * nrm([_s * 0.156, -0.244, -0.008])
    J["hand_" + _sd] = J["elbow_" + _sd] + 0.27 * nrm([-_s * 0.026, -0.205, -0.174])
BOOT_A = math.radians(10.7)
BOOT_B = np.array([[1, 0, 0], [0, math.cos(BOOT_A), -math.sin(BOOT_A)], [0, math.sin(BOOT_A), math.cos(BOOT_A)]])

# Rest: standing tall, legs straight and 6 deg apart (so the pant legs part just under the crotch),
# arms out at the stance's angle with soft elbows.
# the upper arms already hang at the stance's angle, so the shoulders don't move between the two
# poses (the shoulder skin would drag the collar and crease the chest); only the elbows bend
ARM_OUT = math.atan2(0.156, 0.244)
ELBOW_REST = math.radians(12.0)
R = {k: J[k].copy() for k in ("pelvis", "waist", "lumbar", "thoracic", "chest", "head")}
for _s, _sd in ((-1.0, "l"), (1.0, "r")):
    R["hip_" + _sd] = J["hip_" + _sd].copy()
    leg = nrm([_s * 0.105, -1.0, 0.0])
    R["knee_" + _sd] = R["hip_" + _sd] + 0.44 * leg
    R["ankle_" + _sd] = R["knee_" + _sd] + 0.43 * leg
    R["shoulder_" + _sd] = J["shoulder_" + _sd].copy()
    up = np.array([_s * math.sin(ARM_OUT), -math.cos(ARM_OUT), 0.0])
    R["elbow_" + _sd] = R["shoulder_" + _sd] + 0.29 * up
    fa = up * math.cos(ELBOW_REST) + np.array([0, 0, -1.0]) * math.sin(ELBOW_REST)
    R["hand_" + _sd] = R["elbow_" + _sd] + 0.27 * nrm(fa)
GROUND = R["ankle_l"][1] - 0.085               # sole height in the rest pose

BONES = ["pelvis", "sp1", "sp2", "sp3", "neck", "thigh_l", "shin_l", "thigh_r", "shin_r",
         "uarm_l", "farm_l", "uarm_r", "farm_r", "head", "foot_l", "foot_r"]
SPAN = [["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
        ["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"],
        ["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"]]
PARENT = {"pelvis": None, "sp1": "pelvis", "sp2": "sp1", "sp3": "sp2", "neck": "sp3", "head": "neck",
          "thigh_l": "pelvis", "shin_l": "thigh_l", "foot_l": "shin_l", "thigh_r": "pelvis", "shin_r": "thigh_r",
          "foot_r": "shin_r", "uarm_l": "sp3", "farm_l": "uarm_l", "uarm_r": "sp3", "farm_r": "uarm_r"}


def frames(j, boot_basis):
    """Bone frames (4x4, game space) the way SkierRig._frames builds them for an unrotated pelvis
    and torso: y along the bone, x = spine sideways axis or the limb's hinge axis signed to +X."""
    out = {}
    for i, (a, b) in enumerate(SPAN):
        h, t = j[a], j[b]
        y = nrm(t - h)
        if i < 5:
            hint = np.array([1.0, 0, 0])
        else:
            pair = i - 5
            top, mid = SPAN[i - (pair % 2)]
            end = SPAN[i - (pair % 2) + 1][1]
            ax = np.cross(j[top] - j[mid], j[end] - j[mid])
            hint = nrm(ax) * np.sign(ax[0] + 1e-6) if np.linalg.norm(ax) > 0.004 else np.array([1.0, 0, 0])
        x = hint - y * np.dot(hint, y)
        x = nrm(x)
        out[BONES[i]] = (np.stack([x, y, np.cross(x, y)], 1), h)
    out["head"] = (np.eye(3), j["head"])
    for sd in ("l", "r"):
        bb = boot_basis[sd] if isinstance(boot_basis, dict) else boot_basis
        out["foot_" + sd] = (bb, j["ankle_" + sd])
    return out


# In the standing build pose the boots already sit at the angle they hold against the shins in the ski
# stance (forward lean): rest -> bind then turns boot and shin together, so the pant hems that wrap
# the boots move with them instead of being cut by the boot.
_FB, _FR = frames(J, BOOT_B), frames(R, np.eye(3))
FOOT_REST = {sd: _FR["shin_" + sd][0] @ (_FB["shin_" + sd][0].T @ BOOT_B) for sd in ("l", "r")}


def to_blender_matrix(basis, origin):
    m = Matrix.Identity(4)
    bb = C @ Matrix(basis.tolist())
    for r in range(3):
        for c in range(3):
            m[r][c] = bb[r][c]
    m.translation = g2b(origin)
    return m


BONE_LEN = {"head": 0.16, "foot_l": 0.12, "foot_r": 0.12}


# ------------------------------------------------------------------ scene helpers
def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    return sc


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    return link(bpy.data.objects.new(name, me))


def set_active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    set_active(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ------------------------------------------------------------------ body (rest pose, game space)
def ring_loft(sections, n=32):
    """sections: [(centre, x_axis, z_axis, rx, rz_front, rz_back)] -> verts, faces of a capped tube.
    Front is -z (the game's forward)."""
    verts, faces = [], []
    for c, ex, ez, rx, rzf, rzb in sections:
        for k in range(n):
            a = 2 * math.pi * k / n
            sx, sz = math.cos(a), math.sin(a)
            rz = rzb if sz > 0 else rzf
            p = np.asarray(c) + np.asarray(ex) * rx * sx + np.asarray(ez) * rz * sz
            verts.append(p)
    m = len(sections)
    for i in range(m - 1):
        for k in range(n):
            a, b = i * n + k, i * n + (k + 1) % n
            faces.append((a, b, b + n, a + n))
    c0 = len(verts)
    verts.append(np.asarray(sections[0][0]))
    verts.append(np.asarray(sections[-1][0]))
    for k in range(n):
        faces.append((c0, (k + 1) % n, k))
        faces.append((c0 + 1, (m - 1) * n + k, (m - 1) * n + (k + 1) % n))
    return verts, faces


def limb(a, b, profile, side_axis, n=28):
    """Loft along a -> b.  profile: [(t, rx, rz_front, rz_back, dz)] with dz shifting the section
    toward the back (+) - calves and hamstrings sit behind the bone."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    y = nrm(b - a)
    x = nrm(np.asarray(side_axis, float) - y * np.dot(side_axis, y))
    z = np.cross(x, y)
    secs = []
    for t, rx, rzf, rzb, dz in profile:
        secs.append((a + (b - a) * t + z * dz, x, z, rx, rzf, rzb))
    return ring_loft(secs, n)


def ellipsoid(c, r, n=24, axes=None):
    """axes: 3x3 columns = the ellipsoid's local x, y, z in game space (default: world axes)."""
    M = np.eye(3) if axes is None else np.asarray(axes, float)
    verts, faces = [], []
    rings = n // 2
    for i in range(1, rings):
        th = math.pi * i / rings
        for k in range(n):
            ph = 2 * math.pi * k / n
            verts.append(np.asarray(c) + M @ np.array([r[0] * math.sin(th) * math.cos(ph), r[1] * math.cos(th),
                                                       r[2] * math.sin(th) * math.sin(ph)]))
    top, bot = len(verts), len(verts) + 1
    verts.append(np.asarray(c) + M @ np.array([0, r[1], 0]))
    verts.append(np.asarray(c) - M @ np.array([0, r[1], 0]))
    for i in range(rings - 2):
        for k in range(n):
            a, b = i * n + k, i * n + (k + 1) % n
            faces.append((a, a + n, b + n, b))
    for k in range(n):
        faces.append((top, (k + 1) % n, k))
        last = (rings - 2) * n
        faces.append((bot, last + k, last + (k + 1) % n))
    return verts, faces


def body_parts():
    """Anatomy as overlapping closed shapes in the rest pose (game space, metres)."""
    parts = []
    X, Z = np.array([1.0, 0, 0]), np.array([0, 0, 1.0])
    # torso: crotch to the base of the neck, sections (y, rx, rz_front, rz_back, z offset)
    torso = [(-0.165, 0.035, 0.03, 0.03, 0.01), (-0.14, 0.085, 0.06, 0.065, 0.012), (-0.1, 0.14, 0.088, 0.1, 0.014),
             (-0.05, 0.162, 0.098, 0.108, 0.014), (-0.0, 0.166, 0.1, 0.108, 0.012),
             (0.06, 0.156, 0.098, 0.098, 0.004), (0.13, 0.143, 0.098, 0.088, 0.0), (0.21, 0.148, 0.104, 0.09, 0.0),
             (0.29, 0.16, 0.112, 0.098, 0.0), (0.37, 0.168, 0.112, 0.104, 0.004), (0.44, 0.172, 0.1, 0.1, 0.01),
             (0.5, 0.158, 0.082, 0.09, 0.016), (0.535, 0.115, 0.064, 0.07, 0.016), (0.56, 0.07, 0.056, 0.058, 0.012)]
    parts.append(ring_loft([(np.array([0, y, dz]), X, Z, rx, rzf, rzb) for y, rx, rzf, rzb, dz in torso], 40))
    # glutes, chest, shoulder blades, trapezius
    for s in (-1, 1):
        parts.append(ellipsoid([s * 0.07, -0.075, 0.05], [0.085, 0.095, 0.07]))
        parts.append(ellipsoid([s * 0.07, 0.395, -0.078], [0.1, 0.055, 0.018]))
        parts.append(ellipsoid([s * 0.08, 0.4, 0.075], [0.075, 0.09, 0.03]))
        parts.append(ellipsoid([s * 0.085, 0.5, 0.012], [0.085, 0.035, 0.055]))
        # deltoid over the shoulder joint, blended into the trapezius and chest
        sh = R["shoulder_" + ("l" if s < 0 else "r")]
        parts.append(ellipsoid(sh + np.array([0.0, -0.015, 0.0]), [0.048, 0.07, 0.054]))
    # neck and head (the gaiter and helmet cover them; this is their collider)
    parts.append(limb([0, 0.5, 0.012], [0, 0.665, 0.004], [(0, 0.06, 0.055, 0.06, 0), (0.5, 0.054, 0.05, 0.052, 0),
                                                            (1, 0.052, 0.05, 0.05, 0)], X))
    hc = R["head"]
    parts.append(ellipsoid(hc + np.array([0, 0.018, 0.004]), [0.076, 0.104, 0.096]))
    parts.append(ellipsoid(hc + np.array([0, -0.058, -0.035]), [0.056, 0.045, 0.05]))
    for sd, s in (("l", -1.0), ("r", 1.0)):
        hip, knee, ank = R["hip_" + sd], R["knee_" + sd], R["ankle_" + sd]
        # thigh: starts above the hip joint so it fills the hip, quads in front, hamstrings behind
        top = hip + np.array([-s * 0.01, 0.12, 0.0])
        parts.append(limb(top, knee + (knee - hip) * 0.03, [
            (0.0, 0.04, 0.04, 0.04, 0.01), (0.12, 0.086, 0.08, 0.088, 0.012), (0.25, 0.094, 0.09, 0.092, 0.008), (0.4, 0.085, 0.086, 0.083, 0.004),
            (0.65, 0.071, 0.072, 0.068, 0.0), (0.88, 0.057, 0.058, 0.055, -0.002), (1.0, 0.052, 0.052, 0.05, 0.0)], X))
        parts.append(ellipsoid(knee + np.array([0, 0.0, -0.01]), [0.05, 0.055, 0.052]))
        # shin with the calf behind it
        parts.append(limb(knee, ank + (ank - knee) * 0.02, [
            (0.0, 0.05, 0.048, 0.05, 0.0), (0.16, 0.052, 0.046, 0.062, 0.012), (0.33, 0.054, 0.044, 0.066, 0.016),
            (0.55, 0.045, 0.04, 0.05, 0.012), (0.8, 0.034, 0.032, 0.036, 0.006), (1.0, 0.03, 0.03, 0.033, 0.004)], X))
        # foot: toes forward (-z of the boot frame, which carries the stance's forward lean)
        F = FOOT_REST[sd]
        parts.append(ellipsoid(ank + F @ np.array([0, -0.045, -0.06]), [0.045, 0.038, 0.115], axes=F))
        parts.append(ellipsoid(ank + F @ np.array([0, -0.05, 0.022]), [0.034, 0.035, 0.04], axes=F))
        sh, el, hd = R["shoulder_" + sd], R["elbow_" + sd], R["hand_" + sd]
        parts.append(limb(sh + (sh - el) * 0.05, el, [
            (0.0, 0.05, 0.052, 0.05, 0.0), (0.3, 0.047, 0.05, 0.046, 0.0), (0.6, 0.043, 0.046, 0.042, 0.0),
            (1.0, 0.037, 0.038, 0.038, 0.0)], X))
        parts.append(ellipsoid(el, [0.04, 0.042, 0.04]))
        parts.append(limb(el, hd, [
            (0.0, 0.04, 0.04, 0.04, 0.0), (0.25, 0.043, 0.038, 0.04, 0.0), (0.6, 0.034, 0.03, 0.032, 0.0),
            (1.0, 0.027, 0.021, 0.023, 0.0)], X))
        # hand: a mitten in a relaxed curl (the glove is modelled over it later)
        fa = nrm(hd - el)
        hx = nrm(np.array([1.0, 0, 0]) - fa * fa[0])
        parts.append(ellipsoid(hd + fa * 0.07, [0.024, 0.075, 0.048], axes=np.stack([hx, fa, np.cross(hx, fa)], 1)))
    return parts


def build_body():
    verts, faces = [], []
    for v, f in body_parts():
        off = len(verts)
        verts += [g2b(p) for p in v]
        faces += [tuple(i + off for i in face) for face in f]
    obj = mesh_object("body", verts, faces)
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.009                      # coarse enough to round the seams between parts
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.9
    sm.iterations = 16
    sm.use_volume_preserve = True
    sm.use_normalized = True
    obj.modifiers.new("subd", "SUBSURF").levels = 1
    dc = obj.modifiers.new("decimate", "DECIMATE")
    dc.ratio = 0.35
    obj.modifiers.new("tri", "TRIANGULATE")        # no concave quads (Surface Deform needs that)
    apply_modifiers(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


# ------------------------------------------------------------------ armature
def build_armature():
    data = bpy.data.armatures.new("rig")
    arm = link(bpy.data.objects.new("rig", data))
    data.display_type = "STICK"
    set_active(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    rest = frames(R, FOOT_REST)
    for name in BONES:
        basis, origin = rest[name]
        eb = data.edit_bones.new(name)
        length = BONE_LEN.get(name)
        if length is None:
            a, b = SPAN[BONES.index(name)]
            length = float(np.linalg.norm(R[b] - R[a]))
        eb.head = g2b(origin)
        eb.tail = g2b(origin + basis[:, 1] * length)
        eb.align_roll(C @ Vector(basis[:, 2].tolist()))
    for name in BONES:
        if PARENT[name]:
            data.edit_bones[name].parent = data.edit_bones[PARENT[name]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def pose_bind(arm):
    """Pose every bone onto its bind frame (armature space), parents first."""
    bind = frames(J, BOOT_B)
    order = []

    def visit(n):
        order.append(n)
        for c, p in PARENT.items():
            if p == n:
                visit(c)
    visit("pelvis")
    for name in order:
        basis, origin = bind[name]
        arm.pose.bones[name].matrix = to_blender_matrix(basis, origin)
        bpy.context.view_layer.update()
    # check: every bone head and tail must land on its bind joints
    err = 0.0
    for i, name in enumerate(BONES):
        _, origin = bind[name]
        err = max(err, (b2g(arm.pose.bones[name].head) - Vector(origin)).length)
        if i < len(SPAN):
            err = max(err, (b2g(arm.pose.bones[name].tail) - Vector(J[SPAN[i][1]])).length)
    return err


def rest_pose(arm):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def skin(body, arm):
    rest_pose(arm)
    set_active(body)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # bone heat leaves the hands empty (no bone runs inside them): give such vertices to the
    # nearest bone segment
    segs = []
    for pb in arm.data.bones:
        segs.append((pb.name, np.array(pb.head_local), np.array(pb.tail_local)))
    missing = [v for v in body.data.vertices if not v.groups]
    for v in missing:
        p = np.array(v.co)
        best, name = 1e9, None
        for n, a, b in segs:
            t = np.clip(np.dot(p - a, b - a) / np.dot(b - a, b - a), 0, 1)
            d = np.linalg.norm(p - (a + (b - a) * t))
            if d < best:
                best, name = d, n
        body.vertex_groups[name].add([v.index], 1.0, "REPLACE")
    return len(missing)


# ------------------------------------------------------------------ garments (cloth simulation)
# Each garment starts as a loose shell round the standing body (the body pushed out along its
# normals by the garment's ease, voxel-remeshed into one even sheet and cut open at the hems).  A
# Surface Deform binding carries it onto the body posed in the ski stance, then the cloth is
# simulated in that stance with the standing shell as its rest shape: where the pose shortens the
# fabric (behind the knees, the hip crease, inside the elbows) it buckles into folds, where it
# stretches it (seat, knees, elbows) it pulls tight, and gravity drapes the rest.  Nothing moves
# during the simulation, so the collisions stay clean.
SIM_END = 50


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mesh_arrays(obj):
    """Vertex positions and normals (game space) of a mesh's own data (the rest pose)."""
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    no = np.empty(n * 3)
    me.vertices.foreach_get("normal", no)
    to_g = np.array(C.transposed())
    return co.reshape(-1, 3) @ to_g.T, no.reshape(-1, 3) @ to_g.T


def group_weights(obj, names):
    W = np.zeros((len(obj.data.vertices), len(names)))
    idx = {g.index: names.index(g.name) for g in obj.vertex_groups if g.name in names}
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in idx:
                W[v.index, idx[g.group]] = g.weight
    return W


def set_groups(obj, names, W, threshold=0.002):
    for k, name in enumerate(names):
        vg = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
        for i in np.nonzero(W[:, k] > threshold)[0]:
            vg.add([int(i)], float(W[i, k]), "REPLACE")


def copy_weights(src, dst, k=6):
    """Skin `dst` like the nearest surface of `src` (inverse-distance mean of k nearest vertices)."""
    from mathutils.kdtree import KDTree
    tree = KDTree(len(src.data.vertices))
    for v in src.data.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    Ws = group_weights(src, BONES)
    Wd = np.zeros((len(dst.data.vertices), len(BONES)))
    for v in dst.data.vertices:
        hits = tree.find_n(v.co, k)
        acc, tot = np.zeros(len(BONES)), 0.0
        for _, i, d in hits:
            w = 1.0 / (d + 0.004)
            acc += Ws[i] * w
            tot += w
        Wd[v.index] = acc / tot
    set_groups(dst, BONES, Wd)


def keep_largest_island(bm):
    bm.verts.ensure_lookup_table()
    seen, best = set(), []
    for v0 in bm.verts:
        if v0 in seen:
            continue
        comp, stack = [], [v0]
        seen.add(v0)
        while stack:
            v = stack.pop()
            comp.append(v)
            for e in v.link_edges:
                o = e.other_vert(v)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        if len(comp) > len(best):
            best = comp
    keep = set(best)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in keep], context="VERTS")


def shell_from_body(body, name, offset_fn, voxel, cuts, keep_fn=None, extra=()):
    """Body (plus `extra` closed parts, e.g. the boots) pushed out by offset_fn(P, N) (game space),
    remeshed into one surface, then cut open.
    cuts: [(point, normal)] in game space - geometry on the normal's side is removed."""
    P, N = mesh_arrays(body)
    faces = [tuple(p.vertices) for p in body.data.polygons]
    if extra:
        tmp = mesh_object("tmp", [], [])
        verts = []
        fl = []
        fixed = []                                 # an extra part may carry its own fixed offset
        for part in extra:
            v, f = part[0], part[1]
            off = len(verts)
            verts += [g2b(q) for q in v]
            fl += [tuple(i + off for i in face) for face in f]
            fixed += [part[2] if len(part) > 2 else np.nan] * len(v)
        tmp.data.from_pydata(verts, [], fl)
        tmp.data.update()
        bm = bmesh.new()                           # outward normals: the offset goes along them
        bm.from_mesh(tmp.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(tmp.data)
        bm.free()
        tmp.data.update()
        Pe, Ne = mesh_arrays(tmp)
        fl = [tuple(p.vertices) for p in tmp.data.polygons]
        bpy.data.objects.remove(tmp)
        faces += [tuple(i + len(P) for i in face) for face in fl]
        nb = len(P)
        P, N = np.concatenate([P, Pe]), np.concatenate([N, Ne])
    else:
        nb, fixed = len(P), []
    off = offset_fn(P, N)
    fx = np.concatenate([np.full(nb, np.nan), np.array(fixed, float)])
    off = np.where(np.isnan(fx), off, fx)
    Q = P + N * off[:, None]
    obj = mesh_object(name, [g2b(q) for q in Q], faces)
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.5
    sm.iterations = 4
    apply_modifiers(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for cut in cuts:
        co, no = cut[0], cut[1]
        radius = cut[2] if len(cut) > 2 else None
        if radius is None:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=g2b(co), plane_no=g2b(no),
                                   clear_outer=True)
        else:
            # a cut that only acts near `co` (a cuff, say), so it can't clip the rest of the garment
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=g2b(co), plane_no=g2b(no))
            c, n = g2b(co), g2b(no)
            bad = [v for v in bm.verts if (v.co - c).dot(n) > 1e-5 and (v.co - c).length < radius]
            bmesh.ops.delete(bm, geom=bad, context="VERTS")
    if keep_fn is not None:
        bad = [v for v in bm.verts if not keep_fn(np.array(b2g(v.co)))]
        bmesh.ops.delete(bm, geom=bad, context="VERTS")
    # weld the slivers the cuts leave along the open edges
    edge_v = list({v for e in bm.edges if e.is_boundary for v in e.verts})
    bmesh.ops.remove_doubles(bm, verts=edge_v, dist=voxel * 0.35)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=voxel * 0.1)
    keep_largest_island(bm)
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


PANTS_WAIST = 0.1
PANTS_HEM = R["ankle_l"][1] - 0.05           # over the boot's instep, as ski pants sit


def pants_offset(P, N):
    y = P[:, 1]
    ank = R["ankle_l"][1]
    off = np.interp(y, [ank - 0.1, ank - 0.02, ank + 0.06, -0.7, -0.48, -0.3, -0.16, -0.06, 0.0, 0.06],
                    [0.02, 0.026, 0.05, 0.054, 0.044, 0.038, 0.03, 0.02, 0.012, 0.01])
    return off


def build_pants(body):
    boots = [(v, f) for sd in ("l", "r") for v, f, _ in boot_proxy(sd)]
    # the hem is cut in the boot's frame: high over the instep, low at the heel, the toe box clear
    F = FOOT_REST["l"]
    hn = F @ nrm([0, -1.0, -0.3])
    hn = nrm([0.0, hn[1], hn[2]])
    hp = R["ankle_l"] + F @ np.array([0, -0.022, 0.0])  # crosses the leg tube, clear of the boot top
    obj = shell_from_body(body, "pants", pants_offset, 0.013,
                          [((0, PANTS_WAIST, 0), (0, 1, 0)), ((0, hp[1], hp[2]), hn)],
                          keep_fn=lambda p: abs(p[0]) < 0.3, extra=boots)
    copy_weights(body, obj)
    P, _ = mesh_arrays(obj)
    # below the calf the leg follows the shin alone (the foot's weights would flare the hem)
    W = group_weights(obj, BONES)
    for sd in ("l", "r"):
        side = (P[:, 0] > 0) if sd == "r" else (P[:, 0] <= 0)
        low = side & (P[:, 1] < R["knee_" + sd][1] - 0.12)
        W[low] = 0.0
        W[low, BONES.index("shin_" + sd)] = 1.0
    set_groups(obj, BONES, W, threshold=-1.0)
    # the waistband is pinned; elsewhere a goal (weight^4 x pin stiffness in Blender's cloth) holds the
    # posed shape loosely, except behind the knees and in the hip crease where the fabric is left free
    # to buckle
    w = np.full(len(P), 0.66)
    hem_d = (P - hp) @ -hn                      # height above the hem plane
    w = np.maximum(w, np.where(hem_d < 0.13, 0.85, 0.0))
    w = np.where(hem_d < 0.05, 1.0, w)         # the hem band holds round the boot (its inner gaiter)
    for sd in ("l", "r"):
        kn = R["knee_" + sd]
        d = np.abs(P[:, 1] - kn[1]) / 0.14 + np.maximum(0.0, -P[:, 2]) / 0.03
        w *= 1.0 - 0.75 * (1.0 - sstep(0.6, 1.0, d))
    crease = (1.0 - sstep(0.04, 0.1, np.abs(P[:, 1] + 0.1))) * sstep(0.0, -0.05, P[:, 2])
    w *= 1.0 - 0.75 * crease
    w = np.where(P[:, 1] > PANTS_WAIST - 0.022, 1.0, w)
    pin = obj.vertex_groups.new(name="pin")
    for i, x in enumerate(w):
        pin.add([i], float(x), "REPLACE")
    # extra length (cloth "shrink" below zero): baggy legs are cut long and stack above the boots;
    # a little more round the knees and the hip crease so they fold rather than stretch
    grow = 0.16 * (1.0 - sstep(0.06, 0.26, hem_d)) * sstep(0.03, 0.07, hem_d)
    for sd in ("l", "r"):
        kn = R["knee_" + sd]
        grow += 0.05 * (1.0 - sstep(0.06, 0.16, np.abs(P[:, 1] - kn[1]))) * (np.sign(P[:, 0]) == (1 if sd == "r" else -1))
    sh = obj.vertex_groups.new(name="grow")
    for i, x in enumerate(np.clip(grow / 0.16, 0, 1)):
        sh.add([i], float(x), "REPLACE")
    # below the calf the leg is carried rigidly by the shin (like the boot cuff), not by the skin
    rigid = 1.0 - sstep(R["knee_l"][1] - 0.2, R["knee_l"][1] - 0.06, P[:, 1])
    return obj, rigid


JACKET_HEM = -0.15
JACKET_NECK = 0.625


def arm_param(P, sd):
    """(t along shoulder -> hand, distance from that line) in the build pose."""
    sh, hd = R["shoulder_" + sd], R["hand_" + sd]
    ax = hd - sh
    L = np.linalg.norm(ax)
    t = np.clip((P - sh) @ ax / (L * L), 0.0, 1.0)
    d = np.linalg.norm(P - (sh + t[:, None] * ax), axis=1)
    return t, d


def jacket_offset(P, N):
    y = P[:, 1]
    # fitted through the chest and back, roomier at the hem where it goes over the pants
    off = np.interp(y, [-0.3, -0.15, -0.06, 0.04, 0.14, 0.3, 0.44, 0.5, 0.56, 0.7],
                    [0.042, 0.04, 0.038, 0.032, 0.028, 0.029, 0.029, 0.027, 0.02, 0.02])
    # the head and neck sink inside the standing collar (the chin must not shape the collar)
    head = (y > 0.575) | ((y > 0.5) & (np.abs(P[:, 0]) < 0.07))
    off = np.where(head & (y > 0.56), -0.03, off)
    for sd in ("l", "r"):
        t, d = arm_param(P, sd)
        sleeve = np.interp(t, [0.0, 0.3, 0.7, 1.0], [0.026, 0.028, 0.032, 0.038])
        k = sstep(0.06, 0.18, t) * (d < 0.12)
        off = off * (1 - k) + sleeve * k
    return off


def build_jacket(body):
    # the collar is cut lower at the front (under the chin) than at the back
    # the hem rides higher at the front, where the thighs come up under it
    cuts = [((0, JACKET_HEM + 0.04, 0), (0, -1, -0.35)), ((0, JACKET_NECK - 0.02, 0), (0, 1, -0.3))]
    for sd in ("l", "r"):
        el, hd = R["elbow_" + sd], R["hand_" + sd]
        fa = nrm(hd - el)
        cuts.append((hd - fa * 0.035, fa, 0.16))         # cuffs end over the glove gauntlets
    # a standing collar: a short tube round the neck, a touch wider at the base
    collar = limb([0, 0.5, 0.008], [0, JACKET_NECK + 0.02, -0.004],
                  [(0, 0.064, 0.062, 0.064, 0), (0.6, 0.06, 0.058, 0.06, 0), (1, 0.059, 0.057, 0.059, 0)],
                  np.array([1.0, 0, 0]), 32)
    obj = shell_from_body(body, "jacket", jacket_offset, 0.012, cuts, extra=[collar + (0.018,)])
    copy_weights(body, obj)
    P, _ = mesh_arrays(obj)
    w = np.full(len(P), 0.7)
    w = np.where(P[:, 1] + 0.35 * P[:, 2] < JACKET_HEM + 0.08, 0.85, w)
    grow = np.zeros(len(P))
    for sd in ("l", "r"):
        t, d = arm_param(P, sd)
        on = d < 0.12
        w = np.where(on & (t > 0.9), 0.95, w)
        # inside the elbow and under the arm the fabric is free to bunch
        el = R["elbow_" + sd]
        near_el = np.linalg.norm(P - el, axis=1) < 0.09
        w = np.where(on & near_el & (P[:, 2] < el[2] + 0.01), 0.3, w)
        pit = np.linalg.norm(P - (R["shoulder_" + sd] + np.array([0.0, -0.09, 0.0])), axis=1) < 0.07
        w = np.where(pit, 0.4, w)
        # sleeves cut a little long: they bunch above the cuffs
        grow = np.maximum(grow, np.where(on, 0.06 * sstep(0.6, 0.85, t) * (1 - sstep(0.93, 0.98, t)), 0.0))
    w = np.where(P[:, 1] - 0.3 * P[:, 2] > JACKET_NECK - 0.05, 1.0, w)
    pin = obj.vertex_groups.new(name="pin")
    for i, x in enumerate(w):
        pin.add([i], float(x), "REPLACE")
    gr = obj.vertex_groups.new(name="grow")
    for i, x in enumerate(np.clip(grow / 0.06, 0, 1)):
        gr.add([i], float(x), "REPLACE")
    # the collar rides the neck and spine bones rigidly (the shoulders' skin moves with the arms and
    # would drag it)
    rigid = sstep(0.5, 0.55, P[:, 1]) * (1.0 - sstep(0.1, 0.13, np.linalg.norm(P[:, [0, 2]], axis=1)))
    return obj, rigid


def boot_proxy(sd):
    """A rounded ski boot (shell + cuff) at the rest ankle, skinned to the foot and shin: the
    pant hems drape over it."""
    ank = R["ankle_" + sd]
    F = FOOT_REST[sd]
    parts = []
    X = np.array([1.0, 0, 0])
    # shell: a lofted box from heel to toe, sole 0.105 below the ankle (boot frame, then placed)
    secs = []
    for z, ry, top in ((0.11, 0.035, -0.03), (0.08, 0.05, -0.015), (0.0, 0.055, 0.0), (-0.09, 0.052, -0.035),
                       (-0.17, 0.045, -0.06), (-0.2, 0.025, -0.075)):
        c = np.array([0, (top + (-0.105)) / 2, z])
        secs.append((c, X, np.array([0, 1.0, 0]), ry, (top + 0.105) / 2, (top + 0.105) / 2))
    v, f = [], []
    # loft along z: sections are in the x/y plane
    n = 24
    for c, _, _, rx, ryl, ryu in secs:
        for k in range(n):
            a = 2 * math.pi * k / n
            v.append(c + np.array([rx * math.cos(a), (ryu if math.sin(a) > 0 else ryl) * math.sin(a), 0]))
    m = len(secs)
    for i in range(m - 1):
        for k in range(n):
            a, b = i * n + k, i * n + (k + 1) % n
            f.append((a, b, b + n, a + n))
    c0 = len(v)
    v += [secs[0][0], secs[-1][0]]
    for k in range(n):
        f.append((c0, (k + 1) % n, k))
        f.append((c0 + 1, (m - 1) * n + k, (m - 1) * n + (k + 1) % n))
    v = [ank + F @ q for q in v]
    parts.append((v, f, "foot_" + sd))
    up = nrm(R["knee_" + sd] - ank)
    parts.append(limb(ank + F @ np.array([0, -0.06, 0.012]), ank + up * 0.15 + F @ np.array([0, 0, 0.012]),
                      [(0, 0.06, 0.062, 0.06, 0), (1, 0.056, 0.058, 0.056, 0)], X, 24) + ("shin_" + sd,))
    return parts


def build_collider(body, arm):
    """Low-poly copy of the body plus boots, skinned like the body: what the cloth collides with."""
    col = body.copy()                           # object copy: keeps the vertex group names
    col.data = body.data.copy()
    col.name = "collider"
    link(col)
    col.parent = None
    col.modifiers.clear()
    col.data.materials.clear()
    dc = col.modifiers.new("decimate", "DECIMATE")
    dc.ratio = 0.3
    apply_modifiers(col)
    W = group_weights(col, BONES)
    bm = bmesh.new()
    bm.from_mesh(col.data)
    extra_w = []
    for sd in ("l", "r"):
        for v, f, bone in boot_proxy(sd):
            base = len(bm.verts)
            vs = [bm.verts.new(g2b(p)) for p in v]
            for face in f:
                bm.faces.new([vs[i] for i in face])
            wrow = np.zeros(len(BONES))
            wrow[BONES.index(bone)] = 1.0
            extra_w += [wrow] * len(v)
    # outward normals everywhere: single-sided collision and the push-out both rely on them
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(col.data)
    bm.free()
    W = np.concatenate([W, np.array(extra_w)], 0)
    if (W.sum(1) < 0.5).any():
        raise SystemExit("collider: %d unweighted vertices" % (W.sum(1) < 0.5).sum())
    col.vertex_groups.clear()
    set_groups(col, BONES, W)
    am = col.modifiers.new("armature", "ARMATURE")
    am.object = arm
    cm = col.modifiers.new("collision", "COLLISION")
    col.collision.thickness_outer = 0.01
    col.collision.thickness_inner = 0.02
    col.collision.use_culling = True           # single sided: cloth found inside the body is pushed out
    col.collision.cloth_friction = 6.0
    col.hide_render = True
    return col


def pose_garment(obj, body, arm, collider, margin=0.008, rigid=None):
    """Shape keys: Basis = the standing shell, 'posed' = carried onto the posed body, with the
    joint creases relaxed (Corrective Smooth against the standing shape) and anything that ended up
    inside the body pushed back out.  rigid: per-vertex 0..1 - how much to follow the armature
    skinning (the garment's own vertex groups) instead of the body surface."""
    rest_pose(arm)
    sd = obj.modifiers.new("sdeform", "SURFACE_DEFORM")
    sd.target = body
    sd.falloff = 4.0
    set_active(obj)
    bpy.ops.object.surfacedeform_bind(modifier="sdeform")
    if not sd.is_bound:
        raise SystemExit("surface deform: %s could not bind to the body" % obj.name)
    pose_bind(arm)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    co = [v.co.copy() for v in ev.data.vertices]
    obj.modifiers.remove(sd)
    if rigid is not None:
        am = obj.modifiers.new("arm", "ARMATURE")
        am.object = arm
        dg = bpy.context.evaluated_depsgraph_get()
        ca = [v.co.copy() for v in obj.evaluated_get(dg).data.vertices]
        obj.modifiers.remove(am)
        co = [c.lerp(a, float(t)) for c, a, t in zip(co, ca, rigid)]
    obj.shape_key_add(name="Basis")
    if "--debug-keys" in ARGV:
        kd = obj.shape_key_add(name="dbg_deformed")
        for i, c in enumerate(co):
            kd.data[i].co = c
        kd.value = 0.0
    k = obj.shape_key_add(name="posed")
    for i, c in enumerate(co):
        k.data[i].co = c
    k.value = 1.0
    # relax the crushed fabric inside the bends (behind the knees, the hip crease)
    cs = obj.modifiers.new("csmooth", "CORRECTIVE_SMOOTH")
    cs.rest_source = "ORCO"
    cs.factor = 0.6
    cs.iterations = 24
    cs.smooth_type = "LENGTH_WEIGHTED"
    dg = bpy.context.evaluated_depsgraph_get()
    co = [v.co.copy() for v in obj.evaluated_get(dg).data.vertices]
    obj.modifiers.remove(cs)
    if "--debug-keys" in ARGV:
        kd = obj.shape_key_add(name="dbg_smoothed")
        for i, c in enumerate(co):
            kd.data[i].co = c
        kd.value = 0.0
    # push out of the posed body (and garments underneath), as smooth bulges rather than dents
    from mathutils.bvhtree import BVHTree
    trees = []
    for c_obj in (collider if isinstance(collider, (list, tuple)) else [collider]):
        cme = bpy.data.meshes.new_from_object(c_obj.evaluated_get(dg))
        trees.append(BVHTree.FromPolygons([v.co.copy() for v in cme.vertices], [tuple(p.vertices) for p in cme.polygons]))
        bpy.data.meshes.remove(cme)

    def push(cs):
        disp = np.zeros((len(cs), 3))
        for i, c in enumerate(cs):
            for tree in trees:
                # only nearby surfaces: an open shell (the pants) says nothing about points far away
                loc, n, _, _ = tree.find_nearest(c + Vector(disp[i]), 0.05)
                if loc is None:
                    continue
                d = (c + Vector(disp[i]) - loc).dot(n)
                if d < margin:
                    disp[i] += np.array(n) * (margin - d)
        return disp
    nb = [[] for _ in co]
    for e in obj.data.edges:
        a, b = e.vertices
        nb[a].append(b)
        nb[b].append(a)
    disp = push(co)
    raw = np.linalg.norm(disp, axis=1)
    if raw.max() > 0.03:
        print("  %s: warning, pushed up to %.3f m" % (obj.name, raw.max()))
    for _ in range(3):                         # soften the pushes into small bulges
        disp = 0.5 * disp + 0.5 * np.array([disp[n].mean(0) if n else disp[i] for i, n in enumerate(nb)])
    co = [c + Vector(d) for c, d in zip(co, disp)]
    disp2 = push(co)
    co = [c + Vector(d) for c, d in zip(co, disp2)]
    pushed = int((raw > 0).sum())
    for i, c in enumerate(co):
        k.data[i].co = c
    print("  %s: posed, %d vertices pushed out of the body" % (obj.name, pushed))


def add_cloth(obj, mass, tension, bending, compression=None, self_collide=True, goal=2.0, grow=0.0):
    cm = obj.modifiers.new("cloth", "CLOTH")
    st = cm.settings
    st.quality = 8
    st.mass = mass
    st.air_damping = 2.0
    st.tension_stiffness = tension
    st.compression_stiffness = tension if compression is None else compression
    st.shear_stiffness = tension * 0.5
    st.bending_stiffness = bending
    st.tension_damping = 8.0
    st.compression_damping = 8.0
    st.shear_damping = 8.0
    st.bending_damping = 1.0
    st.vertex_group_mass = "pin"
    st.pin_stiffness = goal
    st.rest_shape_key = obj.data.shape_keys.key_blocks["Basis"]
    if grow > 0.0 and "grow" in obj.vertex_groups:
        st.vertex_group_shrink = "grow"
        st.shrink_min = 0.0
        st.shrink_max = -grow
    cs = cm.collision_settings
    cs.collision_quality = 4
    cs.distance_min = 0.005
    cs.use_self_collision = self_collide
    cs.self_distance_min = 0.004
    cs.self_friction = 8.0
    cm.point_cache.frame_start = 1
    cm.point_cache.frame_end = SIM_END
    return cm


def simulate(objs):
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, SIM_END
    sc.frame_set(1)
    import time
    t0 = time.time()
    for f in range(1, SIM_END + 1):
        sc.frame_set(f)
        if f % 20 == 0:
            print("  sim frame %d (%.0fs)" % (f, time.time() - t0))
    out = []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        d = link(bpy.data.objects.new(o.name + "_draped", me))
        for p in d.data.polygons:
            p.use_smooth = True
        # take the collision jitter out, keep the folds
        sm = d.modifiers.new("smooth", "LAPLACIANSMOOTH")
        sm.lambda_factor = 0.4
        sm.iterations = 6
        apply_modifiers(d)
        o.hide_render = True
        o.hide_set(True)
        out.append(d)
    return out


# ------------------------------------------------------------------ folds
# The simulation gives the drape; the folds a stiff ski fabric keeps (stacked rings above the
# boots, creases behind the knees and inside the elbows, the hip crease, drape lines down the legs,
# bunching above the cuffs and at the waist) are added as geometry along the normals before the
# mesh is decimated, so they stay in the silhouette and darken the AO.  Placements follow
# gen_rider's older sculpted outfit, larger.
def wrap(a):
    return (a + np.pi) % (2.0 * np.pi) - np.pi


def poly_coords(p, pts, inner):
    """Closest point on a polyline: arc length S, angle TH round it (0 toward `inner`), distance R."""
    n = len(p)
    best = np.full(n, np.inf)
    S, TH, R = np.zeros(n), np.zeros(n), np.zeros(n)
    cum = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = nrm(b - a)
        f = nrm(inner - d * np.dot(inner, d))
        side = np.cross(d, f)
        L = np.linalg.norm(b - a)
        t = np.clip((p - a) @ (b - a) / (L * L), 0.0, 1.0)
        q = p - (a + t[:, None] * (b - a))
        d2 = (q * q).sum(1)
        better = d2 < best
        best = np.where(better, d2, best)
        S = np.where(better, cum + t * L, S)
        TH = np.where(better, np.arctan2(q @ side, q @ f), TH)
        R = np.where(better, np.sqrt(d2), R)
        cum += L
    return S, TH, R


def ring(S, sc, a, w=0.013):
    """A fold round a limb at arc length sc: a ridge with the crease just below it."""
    return a * np.exp(-((S - sc) / w) ** 2) - 0.6 * a * np.exp(-((S - sc - 1.7 * w) / (0.65 * w)) ** 2)


def pants_folds(P):
    disp = np.zeros(len(P))
    rl = [poly_coords(P, leg_pts(sd), np.array([0.0, 0.0, -1.0])) for sd in ("l", "r")]
    for k, sd in enumerate(("l", "r")):
        S, TH, R = rl[k]
        own = R <= rl[1 - k][2]                       # the leg this point hangs on
        ss = -1.0 if sd == "l" else 1.0
        pts = leg_pts(sd)
        s_knee = np.linalg.norm(pts[1] - pts[0])
        s_ank = s_knee + np.linalg.norm(pts[2] - pts[1])
        d = np.zeros(len(P))
        # stacking above the boot: tilted, wobbly rings
        for up, a, tilt, ph in ((-0.012, 0.011, 0.02, 0.3), (0.03, 0.012, -0.025, 2.0), (0.073, 0.01, 0.03, 4.1),
                                (0.116, 0.007, -0.02, 1.0), (0.16, 0.004, 0.02, 2.6)):
            sc = s_ank - up + tilt * np.cos(TH - ph) + 0.01 * np.sin(2 * TH + ph)
            d += ring(S, sc, a)
        # behind the knee: soft creases where the bend gathers the cloth
        back = np.exp(-(wrap(TH - np.pi) / 0.9) ** 2)
        for off, a in ((-0.045, 0.006), (-0.005, 0.008), (0.035, 0.007), (0.075, 0.004)):
            d += back * ring(S, s_knee + off + 0.012 * np.sin(TH * 2.0 + off * 40), a, 0.012)
        # hip crease across the top of the thigh
        front = np.exp(-(wrap(TH) / 0.9) ** 2)
        for s0, a in ((0.07, 0.007), (0.115, 0.006)):
            d += front * ring(S, s0 + 0.012 * np.cos(TH * 3), a, 0.011)
        # long drape lines hanging down the thigh and shin (ridge with a soft valley beside it)
        for th0, s_a, s_b, a in ((0.35, s_knee + 0.02, s_ank - 0.05, 0.008), (-0.4, s_knee + 0.06, s_ank - 0.05, 0.007),
                                 (ss * 1.4, 0.12, s_knee - 0.12, 0.006), (ss * 2.2, s_knee + 0.03, s_ank - 0.03, 0.008),
                                 (-ss * 2.0, s_knee + 0.05, s_ank - 0.03, 0.006), (0.05, 0.1, s_knee - 0.14, 0.005),
                                 (-ss * 0.9, 0.14, s_knee - 0.12, 0.005)):
            win = sstep(s_a, s_a + 0.06, S) * (1.0 - sstep(s_b - 0.06, s_b, S))
            dth = wrap(TH - th0 - 0.6 * (S - s_a))
            d += a * win * (np.exp(-(dth / 0.16) ** 2) - 0.45 * np.exp(-((dth - 0.3) / 0.12) ** 2))
        disp += np.where(own, d * sstep(0.03, 0.07, S), 0.0)
    return disp


def leg_pts(sd):
    s = -1.0 if sd == "l" else 1.0
    hip, knee, ank = J["hip_" + sd], J["knee_" + sd], J["ankle_" + sd]
    return [hip + np.array([s * 0.005, 0.06, 0.012]), knee, ank, ank + BOOT_B @ np.array([0.0, -0.09, 0.012])]


def arm_pts(sd):
    s = -1.0 if sd == "l" else 1.0
    sh, el, hd = J["shoulder_" + sd], J["elbow_" + sd], J["hand_" + sd]
    return [sh + np.array([-s * 0.03, 0.0, 0.005]), el, hd - nrm(hd - el) * 0.035]


def jacket_folds(P):
    disp = np.zeros(len(P))
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    for sd in ("l", "r"):
        s = -1.0 if sd == "l" else 1.0
        sh, el, hd = J["shoulder_" + sd], J["elbow_" + sd], J["hand_" + sd]
        inner = nrm(nrm(hd - el) - nrm(el - sh))
        pts = arm_pts(sd)
        S, TH, R = poly_coords(P, pts, inner)
        on = (R < 0.12) & (s * x > 0.15)
        s_el = np.linalg.norm(pts[1] - pts[0])
        s_end = s_el + np.linalg.norm(pts[2] - pts[1])
        d = np.zeros(len(P))
        # sleeves bunch above the cuffs
        for up, a, ph in ((0.025, 0.006, 0.4), (0.06, 0.007, 2.2), (0.097, 0.005, 4.0), (0.135, 0.003, 1.3)):
            d += ring(S, s_end - up + 0.012 * np.cos(TH - ph) + 0.006 * np.sin(2 * TH + ph), a, 0.011)
        # inside the elbow: creases fanning out of the bend
        inside = np.exp(-(wrap(TH) / 0.8) ** 2)
        for off, a in ((-0.04, 0.005), (-0.012, 0.007), (0.016, 0.007), (0.044, 0.005)):
            d += inside * ring(S, s_el + off + 0.02 * np.sin(TH * 2.0 + off * 50), a, 0.01)
        # a drag line from the armpit down the back of the upper arm
        dth = wrap(TH - np.pi - 0.4 * (S - 0.05))
        d += 0.004 * sstep(0.04, 0.1, S) * (1 - sstep(s_el - 0.08, s_el - 0.02, S)) * np.exp(-(dth / 0.18) ** 2)
        disp += np.where(on, d, 0.0)
    # waist: the jacket gathers across the front as the hips fold
    front = sstep(-0.02, -0.09, z) * (1 - sstep(0.13, 0.19, np.abs(x)))
    torso = ~((np.abs(x) > 0.17) & (y < 0.5))         # not the sleeves
    for y0, a, ph in ((0.0, 0.006, 0.0), (0.05, 0.007, 1.7), (0.1, 0.005, 3.1), (0.15, 0.003, 4.4)):
        yc = y0 + 0.012 * np.sin(x * 25 + ph)
        disp += torso * front * (a * np.exp(-((y - yc) / 0.012) ** 2) - 0.5 * a * np.exp(-((y - yc - 0.022) / 0.008) ** 2))
    return disp


FOLDS = {"pants": pants_folds, "jacket": jacket_folds}


# ------------------------------------------------------------------ export
def ambient_occlusion(obj, occluders, rays=24, reach=0.3):
    """Per-vertex AO by ray casting the outward hemisphere against `occluders` (BVH trees)."""
    me = obj.data
    k = np.arange(rays) + 0.5
    phi = np.arccos(np.sqrt(1.0 - k / rays))         # cosine-weighted
    th = np.pi * (1 + 5 ** 0.5) * k
    local = np.stack([np.sin(phi) * np.cos(th), np.sin(phi) * np.sin(th), np.cos(phi)], 1)
    ao = np.ones(len(me.vertices))
    for v in me.vertices:
        nz = np.array(v.normal)
        tx = np.cross(nz, [0.0, 0.0, 1.0] if abs(nz[2]) < 0.9 else [1.0, 0.0, 0.0])
        tx /= np.linalg.norm(tx)
        ty = np.cross(nz, tx)
        dirs = local @ np.stack([tx, ty, nz])
        o = v.co + v.normal * 0.002
        occ = 0.0
        for d in dirs:
            dv = Vector(d)
            best = None
            for tree in occluders:
                # start past the first 8 mm: the occluders include the undecimated copy of this very
                # surface, which can lie a few millimetres above it
                hit = tree.ray_cast(o + dv * 0.008, dv, reach)
                if hit[0] is not None and (best is None or hit[3] < best):
                    best = hit[3]
            if best is not None:
                occ += 1.0 - best / reach
        ao[v.index] = 1.0 - occ / rays
    return ao


def export_garments(garments, occluders, path):
    """garments: [(name, object, target_tris)] -> npz of game-space vertices, normals, triangles
    and AO for build/rider_from_blender.py."""
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
    to_g = np.array(C.transposed())
    dense = []
    for name, obj, target in garments:
        cp = bpy.data.objects.new(name + "_export", obj.data.copy())
        link(cp)
        cp.modifiers.clear()
        cp.vertex_groups.clear()
        cp.modifiers.new("tri", "TRIANGULATE")
        apply_modifiers(cp)
        # even out the open edges (hems, cuffs, collar): relax each edge loop along itself
        bm = bmesh.new()
        bm.from_mesh(cp.data)
        for _ in range(24):
            new = {}
            for v in bm.verts:
                if v.is_boundary:
                    nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
                    if len(nb) == 2:
                        new[v] = v.co * 0.5 + (nb[0].co + nb[1].co) * 0.25
            for v, c in new.items():
                v.co = c
        bm.to_mesh(cp.data)
        bm.free()
        # finer mesh for the folds, then the folds along the normals
        sub = cp.modifiers.new("sub", "SUBSURF")
        sub.levels = 1
        sub.boundary_smooth = "PRESERVE_CORNERS"
        cp.modifiers.new("tri", "TRIANGULATE")
        apply_modifiers(cp)
        me = cp.data
        n = len(me.vertices)
        co = np.empty(n * 3)
        me.vertices.foreach_get("co", co)
        no = np.empty(n * 3)
        me.vertices.foreach_get("normal", no)
        Pg = co.reshape(-1, 3) @ to_g.T
        Ng = no.reshape(-1, 3) @ to_g.T
        disp = FOLDS[name](Pg) if name in FOLDS else np.zeros(n)
        Pg = Pg + Ng * disp[:, None]
        me.vertices.foreach_set("co", (Pg @ np.array(C).T).ravel())
        me.update()
        print("  folds %-7s %6d verts, displacement %.4f..%.4f m" % (name, n, disp.min(), disp.max()))
        dense.append((name, cp, target))
    dg = bpy.context.evaluated_depsgraph_get()
    trees = []
    for o in [c for _, c, _ in dense] + list(occluders):
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        trees.append(BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons]))
        bpy.data.meshes.remove(me)
    out = {}
    for name, cp, target in dense:
        # keep the decimation away from the open edges
        edge_co = []
        bm = bmesh.new()
        bm.from_mesh(cp.data)
        edge_co = [v.co.copy() for v in bm.verts if v.is_boundary]
        bm.free()
        kd = KDTree(len(edge_co))
        for i, c in enumerate(edge_co):
            kd.insert(c, i)
        kd.balance()
        keep = cp.vertex_groups.new(name="keep")
        for v in cp.data.vertices:
            d = kd.find(v.co)[2]
            if d < 0.008:                          # just the edge loop and the ring inside it
                keep.add([v.index], 1.0 - d / 0.008, "REPLACE")
        dc = cp.modifiers.new("dec", "DECIMATE")
        dc.vertex_group = "keep"
        dc.invert_vertex_group = True              # decimate everything but the edge band
        dc.vertex_group_factor = 1.0
        dc.ratio = min(1.0, target / max(1, len(cp.data.polygons)))
        cp.modifiers.new("tri", "TRIANGULATE")
        apply_modifiers(cp)
        me = cp.data
        n = len(me.vertices)
        co = np.empty(n * 3)
        me.vertices.foreach_get("co", co)
        no = np.empty(n * 3)
        me.vertices.foreach_get("normal", no)
        tris = np.array([tuple(p.vertices) for p in me.polygons], np.int32)
        ao = ambient_occlusion(cp, trees)
        out[name + "_v"] = co.reshape(-1, 3) @ to_g.T
        out[name + "_n"] = no.reshape(-1, 3) @ to_g.T
        out[name + "_t"] = tris
        out[name + "_ao"] = ao
        print("  export %-7s %6d verts %6d tris, AO mean %.2f" % (name, n, len(tris), ao.mean()))
    np.savez_compressed(path, **out)


# ------------------------------------------------------------------ rendering
def clay(name, rgb, rough=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def setup_render(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 600, 900
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.66, 0.72, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = world
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(8)
    so = link(bpy.data.objects.new("key", sun))
    so.rotation_euler = (math.radians(50), 0, math.radians(150))
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 1.0
    fo = link(bpy.data.objects.new("fill", fill))
    fo.rotation_euler = (math.radians(70), 0, math.radians(-40))
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = link(bpy.data.objects.new("cam", cam))
    sc.camera = co
    return co


def shoot(cam, path, yaw_deg, centre_z, scale=2.15, pitch_deg=4.0):
    """Orthographic view; yaw 0 = looking at the rider's front."""
    yaw = math.radians(yaw_deg)
    d = 6.0
    # the rider faces +Y: a front view sits on +Y looking back toward -Y
    dirv = Vector((math.sin(yaw), math.cos(yaw), math.sin(math.radians(pitch_deg))))
    cam.location = Vector((0, 0, centre_z)) + dirv.normalized() * d
    cam.rotation_euler = (Vector((0, 0, centre_z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = scale
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    if "--from-blend" in ARGV:
        # re-export garments already draped and saved by a --stage clothes run
        bpy.ops.wm.open_mainfile(filepath=arg("--from-blend"))
        o = bpy.data.objects
        export_garments([("pants", o["pants_draped"], 11000), ("jacket", o["jacket_draped"], 13000)],
                        [o["pants_draped"], o["jacket_draped"], o["collider"]], arg("--export"))
        return
    out = os.path.abspath(arg("--out", "build/.cache/blender"))
    os.makedirs(out, exist_ok=True)
    clean_scene()
    body = build_body()
    arm = build_armature()
    unweighted = skin(body, arm)
    print("body: %d verts, %d faces, %d unweighted verts" % (len(body.data.vertices), len(body.data.polygons), unweighted))
    body.data.materials.append(clay("skin", (0.55, 0.5, 0.47)))
    stage = arg("--stage", "body")
    cam = setup_render(int(arg("--samples", "48"))) if "--render" in ARGV else None
    if stage == "body":
        if cam:
            for yaw in (0, 90, 180):
                shoot(cam, os.path.join(out, "rest_%03d.png" % yaw), yaw, (GROUND + 0.82) / 2 - 0.02)
        err = pose_bind(arm)
        print("bind pose: max joint error %.6f m" % err)
        if err > 1e-4:
            raise SystemExit("bind pose does not match the game's joints (%.5f m)" % err)
        if cam:
            for yaw in (0, 35, 90, 180, 270):
                shoot(cam, os.path.join(out, "bind_%03d.png" % yaw), yaw, -0.12, 1.9)
    else:
        rest_pose(arm)
        collider = build_collider(body, arm)
        pants, rigid = build_pants(body)
        jacket, jrigid = build_jacket(body)
        print("pants: %d verts, jacket: %d verts" % (len(pants.data.vertices), len(jacket.data.vertices)))
        khaki, sage = clay("khaki", (0.42, 0.35, 0.23), 0.8), clay("sage", (0.23, 0.29, 0.2), 0.75)
        if cam and "--rest" in ARGV:
            pants.data.materials.append(khaki)
            jacket.data.materials.append(sage)
            for yaw in (0, 90, 180):
                shoot(cam, os.path.join(out, "crest_%03d.png" % yaw), yaw, (GROUND + 0.82) / 2 - 0.02)
            pants.data.materials.clear()
            jacket.data.materials.clear()
        pose_garment(pants, body, arm, collider, rigid=rigid)
        add_cloth(pants, mass=0.25, tension=15.0, bending=14.0, compression=8.0, goal=4.0, grow=0.16)
        pants_d = simulate([pants])[0]
        pants_d.data.materials.append(khaki)
        pc = pants_d.modifiers.new("collision", "COLLISION")
        pants_d.collision.thickness_outer = 0.005
        pants_d.collision.use_culling = True
        if stage == "clothes":
            pose_garment(jacket, body, arm, [collider, pants_d], rigid=jrigid)
            if "--pose-only" not in ARGV:
                add_cloth(jacket, mass=0.3, tension=20.0, bending=10.0, compression=10.0, goal=4.0, grow=0.06)
                jacket_d = simulate([jacket])[0]
                jacket_d.data.materials.append(sage)

        else:
            jacket.hide_render = True
        if cam:
            for yaw in (0, 35, 90, 180, 270):
                shoot(cam, os.path.join(out, "clothes_%03d.png" % yaw), yaw, -0.12, 1.9)
        if "--export" in ARGV and stage == "clothes" and "--pose-only" not in ARGV:
            # triangle budgets: with the lining and the hood the game meshes land near the old
            # rider's (jacket 20k, pants 15k)
            export_garments([("pants", pants_d, 11000), ("jacket", jacket_d, 13000)],
                            [pants_d, jacket_d, collider], arg("--export"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "rider_stage.blend"))


if __name__ == "__main__":
    main()
