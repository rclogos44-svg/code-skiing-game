"""Draw an eye-placed skeleton on a reference photo.
usage: python3 -I overlay.py IMG KP.json OUT [crop x0,y0,x1,y1] [scale]
KP.json: {"pts": {"head": [x, y], ...}, "skis": [[[x, y], [x, y]], ...], "note": "..."}"""
import json, sys
from PIL import Image, ImageDraw

BONES = [["pelvis", "hip_l"], ["pelvis", "hip_r"], ["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"],
         ["knee_r", "ankle_r"], ["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"],
         ["chest", "head"], ["chest", "shoulder_l"], ["chest", "shoulder_r"], ["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"],
         ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"], ["ankle_l", "heel_l"], ["ankle_l", "toe_l"], ["heel_l", "toe_l"],
         ["ankle_r", "heel_r"], ["ankle_r", "toe_r"], ["heel_r", "toe_r"]]
img, kpf, out = sys.argv[1], sys.argv[2], sys.argv[3]
kp = json.load(open(kpf))
pts = {k: tuple(v) for k, v in kp["pts"].items()}
im = Image.open(img).convert("RGB")
crop = [int(v) for v in sys.argv[4].split(",")] if len(sys.argv) > 4 else [0, 0, im.width, im.height]
sc = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
im = im.crop(crop)
im = im.resize((int(im.width * sc), int(im.height * sc)))
d = ImageDraw.Draw(im)
P = lambda p: ((p[0] - crop[0]) * sc, (p[1] - crop[1]) * sc)
for a, b in kp.get("skis", []):
    d.line([P(a), P(b)], fill=(255, 0, 200), width=4)
for a, b in BONES:
    if a in pts and b in pts:
        col = (0, 230, 255) if a.endswith("_l") or b.endswith("_l") else (255, 200, 0) if a.endswith("_r") or b.endswith("_r") else (245, 245, 235)
        d.line([P(pts[a]), P(pts[b])], fill=col, width=5)
for k, p in pts.items():
    x, y = P(p)
    d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(255, 90, 30), outline="black")
note = kp.get("note", "")
if note:
    d.rectangle([0, im.height - 18, im.width, im.height], fill="black")
    d.text((4, im.height - 15), note, fill="white")
im.save(out, quality=90)
print(out)
