#!/usr/bin/env python3
"""Turns the Godot web export into a hostable page: splits SUMMIT.wasm / SUMMIT.pck into
<15 MB chunks, writes the page (fragment for the Artifact host) and a local test wrapper.
Usage: python3 -I web_package.py <export_dir> <out_dir>"""
import hashlib
import json
import os
import re
import shutil
import sys

CHUNK = 14 * 1024 * 1024
src, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
shutil.rmtree(out, ignore_errors=True)
os.makedirs(os.path.join(out, "data"))
for f in ["SUMMIT.js", "SUMMIT.audio.worklet.js", "SUMMIT.audio.position.worklet.js"]:
    shutil.copy(os.path.join(src, f), os.path.join(out, f))
manifest = {}
for name, tag, ctype in [("SUMMIT.wasm", "wasm", "application/wasm"), ("SUMMIT.pck", "pck", "application/octet-stream")]:
    data = open(os.path.join(src, name), "rb").read()
    # world data changes with every release: content-hashed chunk names so a browser can never
    # mix cached chunks of two versions.  The engine chunks only change with the Godot version.
    if tag == "pck":
        tag += "-" + hashlib.sha256(data).hexdigest()[:10]
    parts = []
    for i in range(0, len(data), CHUNK):
        rel = "data/summit-%s-%d.wasm" % (tag, i // CHUNK)
        open(os.path.join(out, rel), "wb").write(data[i:i + CHUNK])
        parts.append(rel)
    manifest[name] = {"parts": parts, "size": len(data), "type": ctype}
html = open(os.path.join(src, "SUMMIT.html")).read()
m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
cfg = json.loads(m.group(1))
cfg["serviceWorker"] = ""
cfg["ensureCrossOriginIsolationHeaders"] = False
page = open(os.path.join(here, "web", "page_template.html")).read()
page = page.replace("__MANIFEST__", json.dumps(manifest)).replace("__GODOT_CONFIG__", json.dumps(cfg))
open(os.path.join(out, "index.html"), "w").write(page)
# local test wrapper: the same fragment inside the skeleton the host adds
wrap = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\"></head><body>\n" + page + "\n</body></html>")
open(os.path.join(out, "local_test.html"), "w").write(wrap)
total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(out) for f in fs)
print("web package:", out, "files:", sum(len(fs) for _, _, fs in os.walk(out)), "total %.1f MB" % (total / 1048576))
print(json.dumps(manifest, indent=1))
