"""Builds the Pip Signal brand mark and every icon made from it.

    python3 scripts/make_icons.py
    npx tauri icon art/icon/icon-1024.png -o <temp dir>   # then copy the sizes tauri.conf.json lists

The mark is the one the user picked in creative-design/ (references/selected-pip-signal.png):
a charcoal bunny head, two ivory eyes and a mint dot. Its geometry lives here once, in a
100-unit box, and is drawn as:

art/brand/pip-signal.svg       the color mark (charcoal, ivory eyes, mint dot)
art/brand/pip-signal-mono.svg  one color, eyes cut out (currentColor), for 16-24 px
art/icon/icon-1024.png         the app icon: the mark on an ivory tile in the macOS icon grid
src-tauri/icons/tray.png       44 px template image: the one-color mark, tinted by macOS

settings.html inlines the same shapes so the mark follows the light and dark themes.
"""

import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

CHARCOAL = (0x27, 0x2A, 0x33)
IVORY = (0xF7, 0xF3, 0xEA)
TILE = (0xFF, 0xFC, 0xF7)
MINT = (0x6F, 0xCF, 0xB4)

# (cx, cy, rx, ry, degrees) for the ears: long ellipses leaning outward, the left one taller.
EARS = [(37, 33, 10.5, 25, -9), (63.5, 36, 10, 22, 9)]
HEAD = (50, 67, 33, 24.5)  # ellipse: cx, cy, rx, ry
EYES = [(40, 65, 3.6), (60, 65, 3.6)]  # circles: cx, cy, r
DOT = (86, 17, 7.5)  # the signal dot, at least one diameter clear of the ear


def svg(mono):
    body = 'currentColor' if mono else "#272A33"
    ears = "\n".join(
        f'    <ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" transform="rotate({a} {x} {y})"/>' for x, y, rx, ry, a in EARS
    )
    cx, cy, rx, ry = HEAD
    eyes = "\n".join(f'    <circle cx="{x}" cy="{y}" r="{r}"/>' for x, y, r in EYES)
    dot = f'<circle cx="{DOT[0]}" cy="{DOT[1]}" r="{DOT[2]}" fill="{body if mono else "#6FCFB4"}"/>'
    if mono:
        return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Sidefolk">
  <mask id="eyes">
    <rect width="100" height="100" fill="#fff"/>
    <g fill="#000">
{eyes}
    </g>
  </mask>
  <g fill="{body}" mask="url(#eyes)">
{ears}
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/>
  </g>
  {dot}
</svg>
"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Sidefolk">
  <g fill="{body}">
{ears}
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/>
  </g>
  <g fill="#F7F3EA">
{eyes}
  </g>
  {dot}
</svg>
"""


def mask(size, shapes, box):
    """A grayscale mask of some of the mark's shapes, drawn 4x and reduced for smooth edges."""
    ss = 4
    big = size * ss
    left, top, span = box
    s = lambda v: (v * span / 100) * ss
    out = Image.new("L", (big, big), 0)
    if "body" in shapes:
        for x, y, rx, ry, a in EARS:
            ear = Image.new("L", (big, big), 0)
            ImageDraw.Draw(ear).ellipse(
                (left * ss + s(x - rx), top * ss + s(y - ry), left * ss + s(x + rx), top * ss + s(y + ry)), fill=255
            )
            # PIL turns counterclockwise; SVG's rotate() clockwise.
            ear = ear.rotate(-a, center=(left * ss + s(x), top * ss + s(y)), resample=Image.BICUBIC)
            out = ImageChops.lighter(out, ear)
        cx, cy, rx, ry = HEAD
        ImageDraw.Draw(out).ellipse(
            (left * ss + s(cx - rx), top * ss + s(cy - ry), left * ss + s(cx + rx), top * ss + s(cy + ry)), fill=255
        )
    draw = ImageDraw.Draw(out)
    for name, circles in (("eyes", EYES), ("dot", [DOT])):
        if name in shapes:
            for x, y, r in circles:
                draw.ellipse((left * ss + s(x - r), top * ss + s(y - r), left * ss + s(x + r), top * ss + s(y + r)), fill=255)
    return out.resize((size, size), Image.LANCZOS)


def solid(size, color):
    return Image.new("RGBA", (size, size), color + (255,))


def app_icon():
    size, tile, radius = 1024, (100, 100, 924, 924), 185
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((100, 112, 924, 936), radius=radius, fill=(39, 42, 51, 80))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    background = solid(size, TILE)
    tile_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(tile, radius=radius, fill=255)
    background.putalpha(tile_mask)
    canvas.alpha_composite(background)
    # The mark fills about 60% of the tile, optically centered (the dot sits in the corner).
    box = (238, 236, 560)
    for color, shapes in ((CHARCOAL, {"body"}), (IVORY, {"eyes"}), (MINT, {"dot"})):
        layer = solid(size, color)
        layer.putalpha(mask(size, shapes, box))
        canvas.alpha_composite(layer)
    canvas.save(os.path.join(ROOT, "art", "icon", "icon-1024.png"))


def tray_icon():
    # Template image: black with alpha; the eyes are holes so the face reads at 16 px.
    size = 44
    alpha = ImageChops.subtract(mask(size, {"body", "dot"}, (1, 1, 42)), mask(size, {"eyes"}, (1, 1, 42)))
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.putalpha(alpha)
    icon.save(os.path.join(ROOT, "src-tauri", "icons", "tray.png"))


os.makedirs(os.path.join(ROOT, "art", "brand"), exist_ok=True)
for name, mono in (("pip-signal.svg", False), ("pip-signal-mono.svg", True)):
    with open(os.path.join(ROOT, "art", "brand", name), "w") as f:
        f.write(svg(mono))
app_icon()
tray_icon()
print("brand: art/brand/*.svg · icons: art/icon/icon-1024.png, src-tauri/icons/tray.png")
