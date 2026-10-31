# Cuts a companion's 2D style target into the rig's canvas, like companions-2d/targets.py does for the lineup:
# 200 x 200, y up, soles on y = 20, centred on x = 100, 4 px a unit. For a companion whose target is an image of its
# own (a folder companion, D85, or one painted apart from the lineup). Copy it beside the target and set the four
# numbers below from the target image (any image viewer, or the --grid output of a first guess):
#   python3 target.py            writes <name>-target-canvas.webp
#   python3 target.py --grid     and work/grid-<name>.png, the same with the canvas grid, to read shapes off
import os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "name"
# Canvas units per pixel: the figure's height in canvas units / its height in pixels. The family stands about 150-160
# tall (ear tips, antennae included); keep the top at or under y 172, so a big head is drawn a little smaller.
SCALE = 0.142
MIDDLE, SOLE = 625, 1153  # pixels: the x of the body's middle, the y of the soles (not the floor shadow)

def crop(sheet):
    box = (MIDDLE - 100 / SCALE, SOLE - 180 / SCALE, MIDDLE + 100 / SCALE, SOLE + 20 / SCALE)
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
    target = crop(Image.open(os.path.join(HERE, f"{NAME}-target.png")).convert("RGB"))
    target.save(os.path.join(HERE, f"{NAME}-target-canvas.webp"), quality=90, method=6)
    if "--grid" in sys.argv:
        os.makedirs(os.path.join(HERE, "work"), exist_ok=True)
        grid(target).save(os.path.join(HERE, "work", f"grid-{NAME}.png"))
