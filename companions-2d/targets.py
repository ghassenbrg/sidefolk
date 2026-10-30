# Cuts each character out of the style target (references/lineup-2d.webp) in the rig's own coordinates: the
# 200 x 200 canvas, y up, soles on y = 20, centred on x = 100, at one scale for all (Mochi's height), 4 px a unit.
#
#   python3 companions-2d/targets.py              writes targets/<name>.webp (what sidefolk-render compares with)
#   python3 companions-2d/targets.py --grid <dir>  the same with a labelled canvas grid, to read shapes off
#
# A new character: add it to the target sheet (or a sheet of its own) and to CHARS, its body's middle and its soles.
import os
import sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "references", "lineup-2d.webp")
SCALE = 0.44  # canvas units per pixel of the sheet
# name: (x of the body's middle, y of the soles), in sheet pixels
CHARS = {"mochi": (217, 392), "spark": (605, 393), "ember": (1030, 393), "kiko": (1381, 395),
         "nimbo": (1772, 400), "folio": (209, 752), "iris": (603, 757), "nori": (1000, 762),
         "purl": (1370, 760), "rune": (1775, 762)}


def crop(name, sheet):
    cx, sole = CHARS[name]
    box = (cx - 100 / SCALE, sole - 180 / SCALE, cx + 100 / SCALE, sole + 20 / SCALE)
    return sheet.crop(tuple(int(v) for v in box)).resize((800, 800))


def grid(image):
    d = ImageDraw.Draw(image)
    for u in range(0, 201, 10):
        p = u * 4
        d.line([(p, 0), (p, 800)], fill=(255, 0, 0) if u % 50 == 0 else (255, 150, 150))
        d.line([(0, 800 - p), (800, 800 - p)], fill=(0, 0, 255) if u % 50 == 0 else (150, 150, 255))
        if u % 20 == 0:
            d.text((p + 2, 2), str(u), fill=(200, 0, 0))
            d.text((2, 800 - p - 12), str(u), fill=(0, 0, 200))
    return image


if __name__ == "__main__":
    sheet = Image.open(SHEET).convert("RGB")
    if len(sys.argv) > 2 and sys.argv[1] == "--grid":
        for name in sys.argv[3:] or CHARS:
            grid(crop(name, sheet)).save(os.path.join(sys.argv[2], f"grid-{name}.png"))
    else:
        os.makedirs(os.path.join(HERE, "targets"), exist_ok=True)
        for name in CHARS:
            crop(name, sheet).save(os.path.join(HERE, "targets", f"{name}.webp"), quality=90, method=6)
