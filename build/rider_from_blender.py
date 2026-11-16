"""Turns the clothes built and draped in Blender (build/blender/build_rider.py --export) into the
rider's skinned meshes, in the same raw format as gen_rider.py:

  * a lining round every opening (hems, cuffs, collar): the cloth is a single sheet in Blender, so an
    inner shell 6 mm in (dark, the shader's lining colour) and a rim are added near the openings;
  * skin weights from gen_rider's skeleton rules (legs that never web together, the crotch staying
    with the pelvis, spine bands, sleeves) and the cloth-sway vertex channels SkierBody drives;
  * UV charts, packing and the painted atlases (seams, zip, pockets, belt) from gen_rider;
  * the hood: gen_rider's hood, moved onto the new jacket's back;
  * the gear (helmet, goggles, gaiter, gloves, boots) from gen_rider unchanged.

usage: python3 -I build/rider_from_blender.py PROJECT GARMENTS.npz
       (GARMENTS.npz: build/rider_garments.npz, written by
        tools/blender/blender -b --factory-startup --python build/blender/build_rider.py -- \\
            --stage clothes --export build/rider_garments.npz)
writes build/.cache/rider_raw.{json,bin} and PROJECT/assets/rider/{jacket,pants}_{albedo,normal}.png
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_rider as gr  # noqa: E402

LINING_DEPTH = 0.006
LINING_REACH = 0.1          # how far into an opening the lining runs (further in is never seen)


def add_lining(v, n, ao, tris):
    """Inner shell near the open edges plus a rim joining it to the outside (triangles in Blender's
    counter-clockwise winding).  Returns the new arrays and the lining flag per vertex."""
    e = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    _, inv, cnt = np.unique(np.sort(e, 1), axis=0, return_inverse=True, return_counts=True)
    bedges = e[cnt[inv.ravel()] == 1]                       # oriented as in their triangle
    bv = np.unique(bedges)
    d = np.empty(len(v))
    B = v[bv]
    for i in range(0, len(v), 1024):
        d[i:i + 1024] = np.linalg.norm(v[i:i + 1024, None, :] - B[None], axis=2).min(1)
    near_t = (d[tris] < LINING_REACH).any(1)
    src = np.unique(np.concatenate([tris[near_t].ravel(), bv]))
    remap = -np.ones(len(v), np.int64)
    remap[src] = len(v) + np.arange(len(src))
    # offset along smoothed normals, so the lining's edge follows the hem instead of zig-zagging
    ns = n.copy()
    for _ in range(3):
        acc = np.zeros_like(ns)
        for k in range(3):
            np.add.at(acc, tris[:, k], ns[tris].sum(1))
        ns = acc / np.linalg.norm(acc, axis=1, keepdims=True)
    vi = v[src] - ns[src] * LINING_DEPTH
    ni = -n[src]
    ti = remap[tris[near_t]][:, ::-1]
    a, b = bedges[:, 0], bedges[:, 1]
    rim = np.concatenate([np.stack([b, a, remap[a]], 1), np.stack([b, remap[a], remap[b]], 1)])
    ao_i = 0.25 + 0.35 * np.clip(1.0 - d[src] / LINING_REACH, 0.0, 1.0)
    V = np.concatenate([v, vi])
    N = np.concatenate([n, ni])
    AO = np.concatenate([ao, ao_i])
    T = np.concatenate([tris, ti, rim]).astype(np.int64)
    lin = np.concatenate([np.zeros(len(v)), np.ones(len(vi))])
    # the rim and the first centimetre inside read as the fabric's thickness (fabric colour); the
    # dark lining starts just inside it
    edge = np.concatenate([np.zeros(len(v)), (d[src] <= 0.012).astype(float)])
    return V, N, AO, T, lin, edge, len(bedges)


def drop_unused(v, n, ao, lin, edge, tris):
    used = np.unique(tris)
    remap = -np.ones(len(v), np.int64)
    remap[used] = np.arange(len(used))
    return v[used], n[used], ao[used], lin[used], edge[used], remap[tris]


# ------------------------------------------------------------------ hood (gen_rider's, re-seated)
def hood_shift(jacket_v):
    """Move the old hood so it lies on the new jacket's back as it did on the old jacket."""
    m = (np.abs(jacket_v[:, 0]) < 0.03) & (np.abs(jacket_v[:, 1] - 0.47) < 0.015)
    new_back = jacket_v[m, 2].max()
    z = np.linspace(0.0, 0.3, 601)
    p = np.stack([np.zeros_like(z), np.full_like(z, 0.47), z], 1)
    d = gr.jacket_solid(p, folds=False, with_hood=False)
    old_back = z[np.nonzero(d > 0)[0][0]]
    return np.array([0.0, 0.0, new_back - old_back])


class Hood(gr.Garment):
    def __init__(self, shift):
        c = gr.HOOD_C + shift
        super().__init__("hood", 0.004, c - [0.2, 0.2, 0.12], c + [0.2, 0.14, 0.14], 3000)
        self.shift = shift

    def sdf(self, p):
        return gr.hood_sdf(p - self.shift)

    def weights(self, p):
        return gr.Jacket.weights(None, p)


def build_hood(shift):
    g = Hood(shift)
    v, n, tris = gr.mesh_garment(g)
    ao = gr.bake_ao(v, n, g.sdf)
    lin = (gr.hood_bag(v - shift) < -gr.WALL * 0.5).astype(float)
    return v, n, ao, lin, tris


# ------------------------------------------------------------------ garments
def jacket_hem(p):
    """The Blender jacket's hem: higher at the front (where the thighs come up under it)."""
    return -0.11 - 0.35 * p[:, 2]


def jacket_channels(v, lin, edge, hood):
    e = np.zeros((len(v), 4))
    sw = 0.4 * (1.0 - gr.sstep(0.0, 0.1, v[:, 1] - jacket_hem(v)))
    for sd in ("l", "r"):
        S, TH, R, SEG, L, pts = gr.arm_coords(v, sd)
        on_arm = (R < 0.12) & (gr.side_sign(sd) * v[:, 0] > 0.15)
        sw = np.maximum(sw, on_arm * 0.8 * gr.sstep(0.3, 0.52, S))
    e[:, 0] = np.where(hood, 0.0, sw)
    e[:, 1] = hood * gr.sstep(0.6, 0.4, v[:, 1])
    e[:, 2] = lin * (1.0 - edge)
    return e


def pants_channels(v, lin, edge):
    e = np.zeros((len(v), 4))
    own = gr.leg_owner(v)
    for k, sd in ((0, "l"), (1, "r")):
        S = gr.leg_coords(v, sd)[0]
        e[:, k] = own[sd] * (0.35 * gr.sstep(0.12, 0.45, S) + 0.65 * gr.sstep(0.45, 0.95, S))
    e[:, 2] = lin * (1.0 - edge)
    return e


def jacket_keys(c, nc, lin_t, hood_t):
    key = gr.jacket_assign(c, nc, lin_t)
    y = c[:, 1]
    # the hood is known exactly here; nothing else is hood
    stray = ~hood_t & (key == "hood")
    key[stray] = np.where(y[stray] > 0.42, "yoke", "torso")
    key[~hood_t & (key == "hood_lin")] = "hem_lin"
    key[hood_t] = np.where(lin_t[hood_t], "hood_lin", "hood")
    return key


def finish(name, v, n, ao, lin, tris, ex, assets, hood=None):
    """Weights, colours, charts, atlas, tangents -> a surface dict for gen_rider.write_raw."""
    if name == "pants":
        w = gr.leg_weights(v)
    else:
        w = gr.Jacket.weights(None, v)
    bi, bw = gr.top4(w)
    if name == "pants":
        lw = np.zeros(len(v))
        rw = np.zeros(len(v))
        for k in range(4):
            lw += np.where(np.isin(bi[:, k], [gr.B["thigh_l"], gr.B["shin_l"], gr.B["foot_l"]]), bw[:, k], 0.0)
            rw += np.where(np.isin(bi[:, k], [gr.B["thigh_r"], gr.B["shin_r"], gr.B["foot_r"]]), bw[:, k], 0.0)
        both = (v[:, 1] < -0.3) & (np.minimum(lw, rw) > 0.05)
        if both.any():
            raise SystemExit("pants: %d lower-leg vertices are skinned to both legs" % both.sum())
    col = np.zeros((len(v), 4))
    col[:, 0] = ex[:, 0]
    col[:, 1] = ao
    col[:, 2] = ex[:, 2]
    col[:, 3] = ex[:, 1]
    c = v[tris].mean(1)
    nc = n[tris].mean(1)
    lin_t = lin[tris].sum(1) >= 2
    if name == "jacket":
        charts, keys, painter = gr.jacket_charts(), jacket_keys(c, nc, lin_t, hood[tris].sum(1) >= 2), gr.paint_jacket
    else:
        charts, keys, painter = gr.pants_charts(), gr.pants_assign(c, nc, lin_t), gr.paint_pants
    src, uvm, chart, tris2, tri_chart, names = gr.split_by_charts(v, tris, keys, charts)
    size = gr.ATLAS_SIZE[name]
    uvpx, D = gr.pack_charts(uvm, chart, tri_chart, tris2, names, size)
    v2, n2 = v[src], n[src]
    gr.bake_atlas(os.path.join(assets, name), v2, n2, lin[src], tris2, uvpx, tri_chart, names, D, size, painter)
    uv = uvpx / size
    tan = gr.tangents(v2, n2, uv, tris2)
    print("  %-7s exported %6d verts %6d tris" % (name, len(v2), len(tris2)))
    return dict(name=name, mat=gr.SURFACE_MAT.get(name, name), group="body", v=v2, n=n2, tan=tan, uv=uv,
                col=col[src], bi=bi[src], bw=bw[src], tris=tris2, uv_per_m=D / size)


def main():
    proj, npz = sys.argv[1], sys.argv[2]
    data = np.load(npz)
    assets = os.path.join(proj, "assets", "rider")
    gr.write_weave(os.path.join(assets, "weave_normal.png"))
    surfaces = []
    for name in ("jacket", "pants"):
        v, n, t, ao = data[name + "_v"], data[name + "_n"], data[name + "_t"].astype(np.int64), data[name + "_ao"]
        n = n / np.linalg.norm(n, axis=1, keepdims=True)
        v, n, ao, t, lin, edge, nb = add_lining(v, n, ao, t)
        v, n, ao, lin, edge, t = drop_unused(v, n, ao, lin, edge, t)
        # Blender's front faces wind counter-clockwise, Godot's (and gen_rider's) clockwise
        t = t[:, ::-1]
        hood = np.zeros(len(v), bool)
        if name == "jacket":
            shift = hood_shift(v)
            hv, hn, hao, hlin, ht = build_hood(shift)
            print("  hood: moved %.3f m back onto the new jacket, %d verts" % (shift[2], len(hv)))
            t = np.concatenate([t, ht + len(v)])
            v, n, ao, lin = np.concatenate([v, hv]), np.concatenate([n, hn]), np.concatenate([ao, hao]), np.concatenate([lin, hlin])
            edge = np.concatenate([edge, np.zeros(len(hv))])
            hood = np.concatenate([hood, np.ones(len(hv), bool)])
            ex = jacket_channels(v, lin, edge, hood)
        else:
            ex = pants_channels(v, lin, edge)
        print("  %s: %d open edges lined" % (name, nb))
        surfaces.append(finish(name, v, n, ao, lin, t, ex, assets, hood))
    gear = gr.build_all(proj, None, only=["helmet", "goggle", "strap", "gaiter", "glove", "boot"])
    cache = os.path.join(HERE, ".cache")
    gr.write_raw(surfaces + gear, os.path.join(cache, "rider_raw.json"), os.path.join(cache, "rider_raw.bin"))


if __name__ == "__main__":
    main()
