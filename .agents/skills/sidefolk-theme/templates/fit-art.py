#!/usr/bin/env python3
"""Fits a generated picture to a Sidefolk theme's art: crop, size, a soft top edge, a colour shift and a PNG small
enough to ship. Needs Pillow (`python3 -m pip install pillow`).

  fit-art.py <src> <out.png> --size 1600x533 [--crop x0,y0,x1,y1] [--fade-top 70 --page "#F3F1EA"]
             [--tint 1,1,0.86] [--colors 256]

--size      the exact pixels to write; the picture is cover-cropped to that ratio first, keeping its top (a page
            wash's interest is at the top) and centring it across.
--crop      a box of the source to start from (a nook backdrop cut from the page wash).
--fade-top  blends this many pixels at the top into --page: pages begin under an opaque title band, and a hard line
            along the wash's top edge reads as a seam there.
--page      the page colour (the theme's surfaceSunken for that appearance), for --fade-top.
--tint      multiplies R, G, B: pulls a generated night picture off a blue cast toward the theme's own darks.
--colors    quantises to that many colours (256 roughly halves a soft watercolour wash; check it for banding).
"""
import argparse
from PIL import Image


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("out")
    p.add_argument("--size", required=True)
    p.add_argument("--crop")
    p.add_argument("--fade-top", type=int, default=0)
    p.add_argument("--page", default="#FFFFFF")
    p.add_argument("--tint")
    p.add_argument("--colors", type=int)
    a = p.parse_args()

    w, h = (int(v) for v in a.size.lower().split("x"))
    im = Image.open(a.src).convert("RGB")
    if a.crop:
        im = im.crop(tuple(int(v) for v in a.crop.split(",")))
    W, H = im.size
    if W / H > w / h:
        nw = round(H * w / h)
        im = im.crop(((W - nw) // 2, 0, (W - nw) // 2 + nw, H))
    else:
        im = im.crop((0, 0, W, round(W * h / w)))
    im = im.resize((w, h), Image.LANCZOS)

    if a.tint:
        f = [float(v) for v in a.tint.split(",")]
        im = Image.merge("RGB", [band.point(lambda v, k=k: min(255, round(v * k))) for band, k in zip(im.split(), f)])

    if a.fade_top:
        page = Image.new("RGB", im.size, a.page)
        mask = Image.new("L", im.size, 255)
        for y in range(min(a.fade_top, h)):
            t = y / a.fade_top
            mask.paste(round(255 * t * t * (3 - 2 * t)), (0, y, w, y + 1))  # smoothstep: no visible band
        im = Image.composite(im, page, mask)

    if a.colors:
        im = im.quantize(colors=a.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    im.save(a.out, optimize=True)
    print(f"{a.out}: {w}x{h}")


if __name__ == "__main__":
    main()
