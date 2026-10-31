# Cuts a folder companion's painted parts (D85) with the checkout's companions-2d/parts/cut.py (its keying and piece
# finding) into the companion folder's 2d/paint/. Copy it beside the sheets and fill in PARTS:
#   python3 cut.py [checkout]     work/<sheet>/NN.png and index.png (to read the numbers off), then the named parts
import os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/git/sidefolk"),
                                "companions-2d", "parts"))
from cut import keyed, pieces

OUT = os.path.join(HERE, "..", "..", "companions", "name", "2d", "paint")
# part: (sheet, piece number in its index.png, share of its height kept). As the gallery names them: armL and footL
# are the ones on the viewer's left. Keep < 1 cuts a piece short (legs painted with shoes, cut where the feet hide it).
PARTS = {
    "head": ("name-sheet.webp", 1, 1),
    "torso": ("name-sheet.webp", 2, 1),
    "armL": ("name-sheet.webp", 3, 1),
    "armR": ("name-sheet.webp", 4, 1),
    "footL": ("name-sheet.webp", 5, 1),
    "footR": ("name-sheet.webp", 6, 1),
}

def cut(sheet):
    """Each piece of a keyed sheet cropped to itself, in reading order; an index.png with their numbers."""
    image = keyed(Image.open(os.path.join(HERE, sheet)))
    work = os.path.join(HERE, "work", os.path.splitext(sheet)[0])
    os.makedirs(work, exist_ok=True)
    index = image.copy()
    draw = ImageDraw.Draw(index)
    parts = []
    for i, (box, mask) in enumerate(pieces(image), 1):
        part = image.crop((box[0] - 2, box[1] - 2, box[2] + 2, box[3] + 2))
        part.putalpha(Image.composite(part.getchannel("A"), Image.new("L", part.size), mask))
        part.save(os.path.join(work, f"{i:02}.png"))
        parts.append(part)
        draw.rectangle(box, outline=(0, 160, 255, 255), width=3)
        draw.text((box[0] + 6, box[1] + 4), str(i), fill=(0, 0, 0, 255))
        print(sheet, i, box)
    bg = Image.new("RGBA", index.size, (235, 238, 245, 255))
    bg.alpha_composite(index)
    bg.convert("RGB").save(os.path.join(work, "index.png"))
    return parts

def short(image, keep):
    """Only the top of a piece, its cut corners rounded so they tuck behind what is drawn over them."""
    image = image.crop((0, 0, image.width, round(image.height * keep)))
    corners = Image.new("L", image.size)
    r = image.width // 12
    ImageDraw.Draw(corners).rounded_rectangle((0, -r, image.width - 1, image.height - 1), r, fill=255)
    image.putalpha(Image.composite(image.getchannel("A"), corners, corners))
    return image

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sheets = {sheet: cut(sheet) for sheet in {s for s, _, _ in PARTS.values()}}
    for name, (sheet, number, keep) in PARTS.items():
        image = sheets[sheet][number - 1]
        if keep < 1:
            image = short(image, keep)
        # 256 colours lose nothing visible in flat cartoon paint and keep the folder small.
        image.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(
            os.path.join(OUT, f"{name}.png"), optimize=True)
