# Takes the face off a painted head the generator drew one on (the rig draws eyes, nose, mouth and cheeks itself):
#   python3 companions-2d/parts/blank.py <part.png> <out.png> [--keep-outline 14]
#
# Features are what stands out inside the head, away from its outline: dark ink (eyes, brows, nose, mouth), pink
# (blush) and white glints, grown a little to take in the irises. They are filled from the paint beside them in their
# row, so the cream and orange of the face meet again where they would.
import sys
from PIL import Image, ImageFilter


def blank(path, out, keep=14):
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    alpha = image.getchannel("A")
    # Inside the head, clear of its outline by `keep` pixels.
    inner = alpha.point(lambda a: 255 if a > 200 else 0).filter(ImageFilter.MinFilter(keep * 2 + 1)).load()
    px = image.load()
    feature = Image.new("L", image.size)
    f = feature.load()
    for y in range(h):
        for x in range(w):
            if not inner[x, y]:
                continue
            r, g, b, _ = px[x, y]
            dark = r + g + b < 330
            pink = r > 200 and b > 110 and g < 200 and r - g > 40
            glint = min(r, g, b) > 246
            if dark or pink or glint:
                f[x, y] = 255
    # Grown to take in the highlights and the iris round each dark mark, but never out to the outline.
    feature = feature.filter(ImageFilter.MaxFilter(17))
    f = feature.load()
    # Each hole pixel takes the paint of the nearer clean pixel in its row: face colours meet in rows (a mask's edge
    # runs across the face), so filling along them keeps that edge where it was on both sides of the hole.
    source = image.copy().load()
    for y in range(h):
        row = [x for x in range(w) if f[x, y] and inner[x, y]]
        for x in row:
            left = next((nx for nx in range(x - 1, -1, -1) if not (f[nx, y] and inner[nx, y]) and source[nx, y][3] > 200), None)
            right = next((nx for nx in range(x + 1, w) if not (f[nx, y] and inner[nx, y]) and source[nx, y][3] > 200), None)
            near = min((c for c in (left, right) if c is not None), key=lambda c: abs(c - x), default=None)
            if near is not None:
                px[x, y] = source[near, y]
    image.save(out)


if __name__ == "__main__":
    keep = int(sys.argv[sys.argv.index("--keep-outline") + 1]) if "--keep-outline" in sys.argv else 14
    blank(sys.argv[1], sys.argv[2], keep)
