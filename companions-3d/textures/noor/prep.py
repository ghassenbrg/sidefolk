# Cuts Noor's paintings (Codex image gen, prompts.json) into the maps his rig carries, and writes the wing's outline
# as read off the painting, in model units. python3 companions-3d/textures/noor/prep.py
import json, math, os
from PIL import Image, ImageChops, ImageFilter
P = os.path.dirname(os.path.abspath(__file__)) + '/'
w = Image.open(P + 'wing-painted.png').convert('RGB'); W, H = w.size
r, g, b = w.split()
gold = ImageChops.multiply(ImageChops.subtract(r, b).point(lambda v: 255 if v > 90 else 0), r.point(lambda v: 255 if v > 165 else 0))
bg = ImageChops.darker(ImageChops.darker(r, g), b).point(lambda v: 255 if v > 232 else 0)
px = bg.load(); cx, cy = 620, 620; radii = []
for i in range(240):
    a = i * 2 * math.pi / 240; last = 0
    for k in range(1, 900):
        x, y = cx + math.cos(a) * k, cy + math.sin(a) * k
        if not (0 <= x < W and 0 <= y < H): break
        if px[int(x), int(y)] == 0: last = k
    radii.append(last)
# A small blur round the outline: the painting's edge wobbles by a few pixels, a mesh's shouldn't.
smooth = [sum(radii[(i + d) % 240] for d in range(-2, 3)) / 5 for i in range(240)]
# Model units: 1254 px are 0.9 units; x outward from the spine, y up (the silhouette the painter was given).
outline = [[(cx + math.cos(i * 2 * math.pi / 240) * q * 0.985) / W * 0.9 - 0.03, -0.01 - (cy + math.sin(i * 2 * math.pi / 240) * q * 0.985) / H * 0.9] for i, q in enumerate(smooth)]
json.dump({'outline': outline, 'size': W}, open(P + 'wing-outline.json', 'w'))
print('wing x', min(p[0] for p in outline), max(p[0] for p in outline), 'y', min(p[1] for p in outline), max(p[1] for p in outline))
# The background becomes rim gold, so mipmaps don't bring white into the rim.
# The velvet is calmed toward the sheet's dusty purples (the painter ran neon); the gold keeps its colour.
calm = Image.blend(w, w.convert('L').convert('RGB'), 0.14).point(lambda v: int(v * 0.86))
w2 = Image.composite(w, calm, gold.filter(ImageFilter.GaussianBlur(1.5)))
Image.composite(Image.new('RGB', w.size, (232, 160, 72)), w2, bg).save(P + 'wing-color.jpg', quality=92)
gold.filter(ImageFilter.GaussianBlur(4)).point(lambda v: 60 + int(v * 0.76)).save(P + 'wing-height.jpg', quality=88)
soft = gold.filter(ImageFilter.GaussianBlur(1.5))
# glTF packing: green roughness, blue metalness.
Image.merge('RGB', (Image.new('L', w.size, 0), soft.point(lambda v: 225 - int(v * 0.62)), soft.point(lambda v: int(v * 0.72)))).save(P + 'wing-mat.jpg', quality=88)
fr = Image.open(P + 'feather-rosette-painted.png').convert('RGB')
def cut(box, name, lo, hi):
    c = fr.crop(box); ch = c.split(); a = ImageChops.lighter(ImageChops.lighter(ch[0], ch[1]), ch[2])
    alpha = a.point(lambda v: max(0, min(255, int((v - lo) * 255 / (hi - lo)))))
    # The colour is pushed out past the edge, so a soft edge never picks up the black.
    grown = c
    for _ in range(14):
        grown = Image.composite(grown, grown.filter(ImageFilter.MaxFilter(5)), alpha.point(lambda v: 255 if v > 200 else 0))
    grown.save(P + name + '-color.jpg', quality=92); alpha.save(P + name + '-alpha.jpg', quality=90)
cut((20, 330, 884, 670), 'feather', 14, 90)
cut((925, 195, 1515, 785), 'rosette', 26, 80)
