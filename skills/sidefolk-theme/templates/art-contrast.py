#!/usr/bin/env python3
"""How well words read where they sit on a theme's art, which `sidefolk theme check` can't see: it knows solid surfaces only.
Run it on a UI snapshot, with a box drawn tightly around the words (in the image's own pixels) and the colour they're in.

  art-contrast.py <snapshot.png> <left,top,right,bottom> <#RRGGBB>

It samples the art in thin bands just above and below the box, where there are no letters, and compares the words' colour with
the hardest 2% of it (the brightest for light words, the darkest for dark ones). Under 4.5:1, move the words, change their
colour or quiet the art. Measure light and dark, and a long language too.
"""
import sys

from PIL import Image

BAND = 6


def luminance(c):
    v = [x / 255 for x in c[:3]]
    v = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in v]
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    left, top, right, bottom = (int(n) for n in sys.argv[2].split(","))
    hex_ = sys.argv[3].lstrip("#")
    ink = luminance([int(hex_[i:i + 2], 16) for i in (0, 2, 4)])
    image = Image.open(sys.argv[1]).convert("RGB")
    bands = [image.crop((left, top - BAND, right, top)), image.crop((left, bottom, right, bottom + BAND))]
    behind = sorted(luminance(p) for band in bands for p in band.getdata())
    # Light words are held to the art's brightest, dark words to its darkest.
    hard = behind[int(len(behind) * 0.98)] if ink > behind[len(behind) // 2] else behind[int(len(behind) * 0.02)]
    high, low = max(ink, hard), min(ink, hard)
    ratio = (high + 0.05) / (low + 0.05)
    print(f"{ratio:.1f}:1 {'ok' if ratio >= 4.5 else 'too low (text needs 4.5:1)'}")


if __name__ == "__main__":
    main()
