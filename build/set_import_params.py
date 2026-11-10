#!/usr/bin/env python3
"""Sets texture import parameters for SUMMIT assets.  Everything is lossless (no GPU block
compression): block-compressed textures read back black in some WebGL implementations."""
import os
import re
import sys

proj = sys.argv[1]
RULES = {
    "world/normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
    "world/surface.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "world/bake.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "world/far_bake.png": {"compress/mode": "0", "mipmaps/generate": "false"},
    "world/map.png": {"compress/mode": "1", "compress/lossy_quality": "0.9", "mipmaps/generate": "true"},
    "assets/textures/snow_normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
    "assets/textures/rock_normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
    "assets/textures/rock_albedo.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/textures/bark.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/textures/noise.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/textures/puff.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/textures/flake.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/rider/jacket_albedo.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/rider/jacket_normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
    "assets/rider/pants_albedo.png": {"compress/mode": "0", "mipmaps/generate": "true"},
    "assets/rider/pants_normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
    "assets/rider/weave_normal.png": {"compress/mode": "0", "compress/normal_map": "0", "mipmaps/generate": "true"},
}
changed = 0
for rel, params in RULES.items():
    path = os.path.join(proj, rel + ".import")
    if not os.path.exists(path):
        print("missing", path)
        continue
    src = open(path).read()
    params = dict(params)
    params["detect_3d/compress_to"] = "0"
    new = src
    for k, v in params.items():
        new = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), new, flags=re.M)
    if new != src:
        open(path, "w").write(new)
        changed += 1
print("updated", changed, "import files")
