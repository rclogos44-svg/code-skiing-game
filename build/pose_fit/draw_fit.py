import json, sys
sys.path.insert(0, '.')
from keypoints import KP, BONES, SKI_LINES
from PIL import Image, ImageDraw
res = json.load(open('fit.json'))
pr = res['proj']
src = '/tmp/claude-0/-home-user-code-skiing-game/b6f5a65b-b10e-50c8-a0dc-3a7ec167ab26/images/5.png'
im = Image.open(src).convert('RGB').crop((0, 0, 578, 760))
pad = 90
can = Image.new('RGB', (578, 760 + pad), (60, 80, 110)); can.paste(im, (0, pad))
d = ImageDraw.Draw(can)
P = lambda xy: (xy[0], xy[1] + pad)
for a, b in BONES:
    d.line([P(KP[a]), P(KP[b])], fill=(245, 245, 235), width=5)
for a, b in BONES:
    d.line([P(pr[a]), P(pr[b])], fill=(0, 230, 255), width=4)
for sd in ('l', 'r'):
    d.line([P(pr['skitip_' + sd]), P(pr['skitail_' + sd])], fill=(255, 0, 200), width=3)
for k in KP:
    d.line([P(KP[k]), P(pr[k])], fill=(255, 60, 60), width=2)
    x, y = P(pr[k]); d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(0, 230, 255))
    x, y = P(KP[k]); d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(255, 115, 25))
    d.text((x + 6, y - 6), k, fill=(255, 255, 255))
can.save(sys.argv[1] if len(sys.argv) > 1 else 'fit_overlay.png')
