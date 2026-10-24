"""Cuts a crew character's generated sprite sheets into transparent frames for the app.

    python3 scripts/make_sprites.py <id> [3d|2d]      (npm run sprites -- pip 3d)

art/crew/<id>/<style>/sheet-a.webp and sheet-b.webp are 4×2 grids generated with Codex image
generation (scripts/crew_art.sh has the briefs) on a pure chroma-green background. Each figure is found from
the empty columns and rows between them (a pose may spill past its grid cell), the green is
keyed out and its fringe removed, and every frame is placed on the same canvas with the feet on
one baseline and the body centered, so swapping frames never makes Pip jump.

Output: public/crew/<id>/<style>/<pose>.webp (2× the on-screen size of the "medium" companion).
"""

import os
import sys

from PIL import Image, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NAME = sys.argv[1] if len(sys.argv) > 1 else "pip"
STYLE = sys.argv[2] if len(sys.argv) > 2 else "3d"
OUT = os.path.join(ROOT, "public", "crew", NAME, STYLE)

# Kept as WebP at quality 95 (crew_art.sh converts what Codex saves), a twelfth of the PNG.
SHEETS = {
    "sheet-a.webp": ["idle", "blink", "listen", "think", "work1", "work2", "alert", "sad"],
    "sheet-b.webp": ["note", "write1", "write2", "done", "wave", "sit", "sleep", "dangle"],
}
# Figure height of a standing pose on the canvas, in pixels; the app shows it at 150 CSS px.
STANDING = 300
# ...and at most this wide, so round characters (a cloud, a penguin) aren't much bigger than tall ones.
WIDEST = 260
CANVAS = (420, 380)
BASELINE = 366


def alpha_of(rgb):
    """Opacity from "how green" a pixel is: chroma green → 0, the character's colors → 255."""
    r, g, b = rgb.split()
    green = ImageChops.subtract(g, ImageChops.lighter(r, b))
    # Mint (#6FCFB4) is only ~30 greener than its other channels; the backdrop is ~255.
    return green.point(lambda v: 255 if v < 70 else 0 if v > 150 else int(255 * (150 - v) / 80))


def despill(rgb, alpha):
    """Edge pixels keep a green tint from the backdrop; cap green at the other channels there."""
    r, g, b = rgb.split()
    capped = ImageChops.darker(g, ImageChops.lighter(r, b))
    # Only where the pixel is partly transparent or clearly green-tinted.
    edge = alpha.point(lambda a: 255 if a < 250 else 0)
    g = Image.composite(capped, g, edge)
    return Image.merge("RGB", (r, g, b))


def spans(profile, min_gap, min_size):
    """Runs of non-empty entries in a projection, split where at least `min_gap` are empty."""
    out, start, gap = [], None, 0
    for i, v in enumerate(profile + [0] * (min_gap + 1)):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap > min_gap:
                end = i - gap + 1
                if end - start >= min_size:
                    out.append((start, end))
                start, gap = None, 0
    return out


def figures(alpha):
    w, h = alpha.size
    solid = alpha.point(lambda a: 255 if a > 128 else 0)
    rows = [1 if solid.crop((0, y, w, y + 1)).getbbox() else 0 for y in range(h)]
    boxes = []
    for top, bottom in spans(rows, 12, 80):
        band = solid.crop((0, top, w, bottom))
        cols = [1 if band.crop((x, 0, x + 1, bottom - top)).getbbox() else 0 for x in range(w)]
        for left, right in spans(cols, 10, 60):
            box = solid.crop((left, top, right, bottom)).getbbox()
            boxes.append((left + box[0], top + box[1], left + box[2], top + box[3]))
    return boxes


def foot_center(alpha, box):
    """The middle of the feet: the horizontal center of the figure's bottom rows."""
    left, top, right, bottom = box
    feet = alpha.crop((left, bottom - (bottom - top) // 8, right, bottom)).point(lambda a: 255 if a > 128 else 0).getbbox()
    return left + (feet[0] + feet[2]) / 2


def main():
    os.makedirs(OUT, exist_ok=True)
    scale = None
    for sheet, names in SHEETS.items():
        rgb = Image.open(os.path.join(ROOT, "art", "crew", NAME, STYLE, sheet)).convert("RGB")
        alpha = alpha_of(rgb)
        rgb = despill(rgb, alpha)
        boxes = figures(alpha)
        if len(boxes) != len(names):
            raise SystemExit(f"{sheet}: found {len(boxes)} figures, expected {len(names)}")
        # Both sheets end up at the same scale: their first (standing) pose is STANDING tall.
        first = boxes[0]
        sheet_scale = min(STANDING / (first[3] - first[1]), WIDEST / (first[2] - first[0]))
        scale = scale or sheet_scale
        for name, box in zip(names, boxes):
            cx = foot_center(alpha, box)
            figure = Image.merge("RGBA", (*rgb.split(), alpha)).crop(box)
            size = (round(figure.width * sheet_scale), round(figure.height * sheet_scale))
            figure = figure.resize(size, Image.LANCZOS)
            canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            x = round(CANVAS[0] / 2 - (cx - box[0]) * sheet_scale)
            y = BASELINE - figure.height
            canvas.alpha_composite(figure, (x, y))
            # WebP at quality 90: a seventh of the PNG's size, no visible difference at this scale.
            canvas.save(os.path.join(OUT, f"{name}.webp"), "WEBP", quality=90, method=6)
            print(f"{name}: {size[0]}×{size[1]} at ({x}, {y})")


main()
