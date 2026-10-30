#!/usr/bin/env python3
"""Packs float32 heightmaps into 16-bit big-endian pairs (RG8 texels: R = high byte, G = low byte)
and records the decode range in layout.json.  Usage: python3 -I height16.py <project_dir>"""
import json
import os
import sys

import numpy as np

world = os.path.join(sys.argv[1], "world")
lay_path = os.path.join(world, "layout.json")
lay = json.load(open(lay_path))
meta = lay["meta"]
for name, key in (("height", "core"), ("far", "far")):
    src = os.path.join(world, name + ".bin")
    h = np.fromfile(src, dtype="<f4")
    lo = float(np.floor(h.min() - 2.0))
    hi = float(np.ceil(h.max() + 2.0))
    scale = (hi - lo) / 65535.0
    q = np.clip(np.round((h - lo) / scale), 0, 65535).astype(">u2")
    q.tofile(os.path.join(world, name + "16.bin"))
    err = float(np.abs(q.astype(np.float64) * scale + lo - h).max())
    meta[key + "_min"] = lo
    meta[key + "_scale"] = scale
    os.remove(src)
    print("%s: %.1f..%.1f m, step %.4f m, max error %.4f m" % (name, lo, hi, scale, err))
json.dump(lay, open(lay_path, "w"), indent=1)
