# Compares a character's colours and light with its sheet: each image's figure (everything not its background) split
# into white, red-ish, black and other zones, with each zone's mean sRGB colour, median brightness, spread and share of
# near-white highlights. A render that is duller, pinker, bluer or glossier than the sheet shows as a gap here before
# it shows on the desktop. PIL only (no numpy outside Blender).
#   python3 companions-3d/zones.py <sheet> x0,y0,x1,y1 build/companions-3d/front-<id>/00001.png
#   (the crop is the sheet's front view; the render comes from sheet.js front())
import sys
from PIL import Image

def zones(im):
    px = im.load(); w, h = im.size
    bg = px[1, 1]
    found = {"white": [], "red": [], "black": [], "other": []}
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if sum(abs(c[i] - bg[i]) for i in range(3)) < 18:
                continue
            lum = 0.3 * c[0] + 0.55 * c[1] + 0.15 * c[2]
            if c[0] - c[1] > 70 and c[0] > 110: zone = "red"
            elif lum < 70: zone = "black"
            elif lum > 170 and max(c) - min(c) < 40: zone = "white"
            else: zone = "other"
            found[zone].append((c, lum))
    total = sum(len(v) for v in found.values()) or 1
    out = {}
    for name, v in found.items():
        if not v: continue
        lums = sorted(l for _, l in v); n = len(v)
        out[name] = dict(share=100 * n / total, mean=tuple(round(sum(c[i] for c, _ in v) / n) for i in range(3)),
                         p5=lums[n // 20], p50=lums[n // 2], p95=lums[n * 19 // 20], hi=100 * sum(l > 235 for l in lums) / n)
    return out

def show(title, z):
    print(title)
    for name, s in z.items():
        print(f"  {name:6s} {s['share']:5.1f}%  mean {s['mean']}  lum p5 {s['p5']:.0f} p50 {s['p50']:.0f} p95 {s['p95']:.0f}"
              f"  highlights {s['hi']:.1f}%")

sheet = Image.open(sys.argv[1]).convert("RGB").crop(tuple(int(v) for v in sys.argv[2].split(",")))
render = Image.open(sys.argv[3]).convert("RGB")
a, b = zones(sheet), zones(render)
show("sheet", a); show("render", b)
print("render − sheet (aim within a few points; the median brightness first)")
for name in a.keys() & b.keys():
    d = [b[name]["mean"][i] - a[name]["mean"][i] for i in range(3)]
    print(f"  {name:6s} mean {d}  p50 {b[name]['p50'] - a[name]['p50']:+.0f}  highlights {b[name]['hi'] - a[name]['hi']:+.1f}")
