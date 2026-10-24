"""Draws the character template people paint their own companion on.

    python3 scripts/make_template.py

A 4×4 grid of the 16 poses the app uses, in the order src/character-import.ts reads them. Each
400×400 box has a 352 px drawing area with a dashed feet line and the pose's name in the strip
below it. Guides are pale grey on white, so the import's background removal drops them; the
names sit outside the drawing area and are never read.

Output: public/character-template.png
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
POSES = [
    ("idle", "standing, arms relaxed"),
    ("blink", "idle, eyes closed"),
    ("listen", "head tilted, attentive"),
    ("think", "hand at the chin"),
    ("work1", "busy (laptop, tool)"),
    ("work2", "busy, hands moved"),
    ("alert", "needs you: hand up"),
    ("sad", "something failed"),
    ("note", "holding a note"),
    ("write1", "writing"),
    ("write2", "writing, pencil moved"),
    ("done", "happy, arms up"),
    ("wave", "waving"),
    ("sit", "sitting"),
    ("sleep", "asleep"),
    ("dangle", "being held up"),
]
CELL = 400
DRAW = 352
FEET = 330
GUIDE = (236, 236, 236)
TEXT = (150, 150, 150)


def font(size):
    for path in ["/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    image = Image.new("RGB", (CELL * 4, CELL * 4), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    title, note = font(22), font(15)
    for i, (name, hint) in enumerate(POSES):
        x, y = (i % 4) * CELL, (i // 4) * CELL
        draw.rectangle([x, y, x + CELL - 1, y + CELL - 1], outline=GUIDE, width=2)
        for dx in range(x + 24, x + CELL - 24, 18):
            draw.line([dx, y + FEET, dx + 9, y + FEET], fill=GUIDE, width=2)
        draw.line([x, y + DRAW, x + CELL, y + DRAW], fill=GUIDE, width=1)
        draw.text((x + 14, y + DRAW + 6), name, fill=TEXT, font=title)
        draw.text((x + 14 + draw.textlength(name, font=title) + 10, y + DRAW + 12), hint, fill=TEXT, font=note)
    out = os.path.join(ROOT, "public", "character-template.png")
    image.save(out, optimize=True)
    print(out)


main()
