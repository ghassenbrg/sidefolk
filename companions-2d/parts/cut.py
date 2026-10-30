# Cuts a painted parts sheet (generate.sh) into its parts:
#   python3 companions-2d/parts/cut.py <name>               writes parts/<name>/NN.png and parts/<name>/index.png
#                                                            (working files, not kept: cut again from the sheet)
#   python3 companions-2d/parts/cut.py <name> --install     copies the parts named in parts/<name>.json into the app
#
# The magenta background is keyed out (edges unmixed from it, so no pink fringe), every separate piece becomes one
# transparent PNG cropped to itself, numbered left to right, top to bottom; index.png shows the numbers. parts/<name>.json
# names them ({"head": 3, "earL": 1, ...}, "ember-head:1" for a part painted again on its own, or {"piece": 5,
# "keep": 0.88} for only the top of a piece) and --install writes
# them to Sources/SidefolkCharacter/Art/<name>/<part>.png, which the rig draws in place of its flat parts, fitted over
# each part's outline.
import json
import os
import sys
from array import array
from collections import deque
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "..", "Sources", "SidefolkCharacter", "Art")
KEY = (255, 0, 255)


def keyed(sheet):
    """RGBA with the magenta gone: alpha from the distance to it, colour unmixed at the soft edges."""
    rgb = sheet.convert("RGB")
    out = Image.new("RGBA", rgb.size)
    src, dst = rgb.load(), out.load()
    w, h = rgb.size
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            # Magenta is the only colour with green far below both red and blue.
            d = min(r, b) - g
            a = 1.0 if d < 60 else max(0.0, 1.0 - (d - 60) / 140)
            if a <= 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            if a < 1:
                r, g, b = (min(255, max(0, round((c - (1 - a) * k) / a))) for c, k in zip((r, g, b), KEY))
            dst[x, y] = (r, g, b, round(a * 255))
    return out


def pieces(image, smallest=400):
    """The opaque pieces in reading order, as (bounding box, mask of that piece alone)."""
    w, h = image.size
    alpha = image.getchannel("A").load()
    seen = array("H", bytes(2 * w * h))
    boxes = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0] or alpha[x0, y0] < 128:
                continue
            label = len(boxes) + 2
            queue, n = deque([(x0, y0)]), 0
            seen[y0 * w + x0] = label
            box = [x0, y0, x0, y0]
            while queue:
                x, y = queue.popleft()
                n += 1
                box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and alpha[nx, ny] >= 128:
                        seen[ny * w + nx] = label
                        queue.append((nx, ny))
            # Specks still take a label, so they don't merge into a piece later; only real pieces are kept.
            boxes.append(((box[0], box[1], box[2] + 1, box[3] + 1), label, n))
    def mask(label, box):
        m = Image.new("L", (box[2] - box[0], box[3] - box[1]))
        mp = m.load()
        for y in range(box[1], box[3]):
            for x in range(box[0], box[2]):
                if seen[y * w + x] == label:
                    mp[x - box[0], y - box[1]] = 255
        # Grown by its soft edge, which is too faint to have been labelled.
        return m.filter(ImageFilter.MaxFilter(5))
    boxes = [(b, mask(label, (b[0] - 2, b[1] - 2, b[2] + 2, b[3] + 2))) for b, label, n in boxes if n >= smallest]
    # Reading order: rows by the box's middle, a third of the tallest piece apart.
    row = max(b[3] - b[1] for b, _ in boxes) / 3
    return sorted(boxes, key=lambda p: (round((p[0][1] + p[0][3]) / 2 / row), p[0][0]))


def cut(name):
    # A whole sheet (<name>-sheet.webp) or one part painted again on its own (<name>.webp, e.g. spark-head).
    path = os.path.join(HERE, f"{name}-sheet.webp")
    sheet = Image.open(path if os.path.exists(path) else os.path.join(HERE, f"{name}.webp"))
    image = keyed(sheet)
    folder = os.path.join(HERE, name)
    os.makedirs(folder, exist_ok=True)
    index = image.copy()
    draw = ImageDraw.Draw(index)
    for i, (box, alone) in enumerate(pieces(image), 1):
        part = image.crop((box[0] - 2, box[1] - 2, box[2] + 2, box[3] + 2))
        # Only this piece: corners of others inside its box are cleared.
        part.putalpha(Image.composite(part.getchannel("A"), Image.new("L", part.size), alone))
        part.save(os.path.join(folder, f"{i:02}.png"))
        draw.rectangle(box, outline=(0, 160, 255, 255), width=3)
        draw.text((box[0] + 6, box[1] + 4), str(i), fill=(0, 0, 0, 255))
    bg = Image.new("RGBA", index.size, (235, 238, 245, 255))
    bg.alpha_composite(index)
    bg.convert("RGB").save(os.path.join(folder, "index.png"))


def install(name):
    names = json.load(open(os.path.join(HERE, f"{name}.json")))
    out = os.path.join(ART, name)
    os.makedirs(out, exist_ok=True)
    for part, number in names.items():
        # {"piece": ..., "keep": 0.88} keeps only the top of a piece: legs painted too long, cut short where the
        # paws drawn in front of them hide the cut.
        keep = number.get("keep", 1) if isinstance(number, dict) else 1
        number = number["piece"] if isinstance(number, dict) else number
        # A number is a piece of this companion's sheet; "ember-head:1" a piece of a part painted again on its own.
        folder, number = number.split(":") if isinstance(number, str) else (name, number)
        image = Image.open(os.path.join(HERE, folder, f"{int(number):02}.png"))
        if keep < 1:
            image = image.crop((0, 0, image.width, round(image.height * keep)))
            # The cut's outer corners rounded off, so they tuck behind the paws instead of showing square.
            corners = Image.new("L", image.size)
            r = image.width // 6
            ImageDraw.Draw(corners).rounded_rectangle((0, -r, image.width - 1, image.height - 1), r, fill=255)
            image.putalpha(Image.composite(image.getchannel("A"), corners, corners))
        # 256 colours lose nothing visible in flat cartoon paint and make the app's copy a tenth of the size.
        image.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(
            os.path.join(out, f"{part}.png"), optimize=True)


if __name__ == "__main__":
    if "--install" in sys.argv:
        install(sys.argv[1])
    else:
        cut(sys.argv[1])
