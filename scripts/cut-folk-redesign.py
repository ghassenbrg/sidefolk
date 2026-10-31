#!/usr/bin/env python3
"""Cut the approved folk reference into the transparent paintings used by FolkRig.

Requires Pillow and NumPy. The source is a white studio sheet; flood-fill only the
white connected to its edges, preserving enclosed white details such as Guard's shield.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[1]
sheet = Image.open(root / 'folk-family/redesign-2026-10-31/folk-redesign-reference.png').convert('RGB')
output = root / 'Sources/SidefolkCharacter/Art/folks'
output.mkdir(parents=True, exist_ok=True)
names = ['pip', 'byte', 'seed', 'melody', 'scout', 'tempo', 'play', 'guard', 'nova', 'brew']
for i, name in enumerate(names):
    column, row = i % 5, i // 5
    left, right = ([(0, 337), (337, 674), (674, 1010), (1010, 1347), (1347, 1684)] if row == 0 else [(0, 375), (378, 674), (674, 1010), (1010, 1347), (1347, 1684)])[column]
    top, bottom = ((50, 450), (490, 842))[row]
    crop = sheet.crop((left, top, right, bottom))
    rgb = np.asarray(crop).astype(np.int16)
    # Ignore the pale neutral studio shadow, then close small gaps before filling
    # enclosed light details (calendar, paper, shield) from the outside.
    low, high = rgb.min(axis=2), rgb.max(axis=2)
    ink = (low < 224) & ~((high - low < 14) & (low > 182))
    mask = Image.new('L', (crop.width + 40, crop.height + 40))
    mask.paste(Image.fromarray(np.where(ink, 255, 0).astype('uint8')), (20, 20))
    mask = mask.filter(ImageFilter.MaxFilter(19))
    outside = Image.eval(mask, lambda v: 255 - v)
    ImageDraw.floodfill(outside, (0, 0), 128)
    filled = Image.fromarray(np.where(np.asarray(outside) == 128, 0, 255).astype('uint8')).copy()
    filled = filled.filter(ImageFilter.MinFilter(19)).crop((20, 20, crop.width + 20, crop.height + 20))
    alpha = np.array(filled.filter(ImageFilter.GaussianBlur(0.6)))
    interior = np.asarray(filled.filter(ImageFilter.MinFilter(15))) > 0
    # Discard studio-white slivers left at open edges, while keeping light details
    # safely inside the figure (notably Tempo's calendar and Pip's paper).
    alpha[(low > 235) & (high - low < 12) & ~interior] = 0
    rgba = np.dstack((rgb.astype('uint8'), alpha))
    art = Image.fromarray(rgba, 'RGBA')
    box = art.getbbox()
    if box is None:
        raise ValueError(f'No artwork found for {name}')
    art = art.crop(box)
    art.thumbnail((320, 320), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (384, 384))
    canvas.alpha_composite(art, ((384 - art.width) // 2, 350 - art.height))
    pixels = np.array(canvas)
    floor = pixels[330:, :, :3].astype(np.int16)
    neutral_shadow = (floor.min(axis=2) > 205) & (floor.max(axis=2) - floor.min(axis=2) < 18)
    pixels[330:, :, 3][neutral_shadow] = 0
    canvas = Image.fromarray(pixels)
    canvas.save(output / f'{name}.png', optimize=True)
