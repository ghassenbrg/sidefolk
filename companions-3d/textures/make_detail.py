# Turns the generated fabric photos into seamless detail height maps for the runtime's bump shading.
# Runs in Blender's Python for numpy: blender -b -P make_detail.py
import os
import numpy as np
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Companions3D", "assets")

def load(name):
    img = bpy.data.images.load(os.path.join(HERE, name))
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, -1)[..., :3]
    return a.mean(axis=2)

def blur(a, r):
    # Box blur three times ≈ Gaussian, wrapping around (the result must tile).
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.concatenate([a.take(range(-r, 0), axis=ax), a, a.take(range(0, r + 1), axis=ax)], axis=ax), axis=ax)
            a = (c.take(range(2 * r + 1, c.shape[ax]), axis=ax) - c.take(range(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a

def seamless(a):
    # Cross-fade with a half-period-shifted copy: the shifted copy has no seam where the original does.
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    wx = np.abs((xx / (w - 1)) * 2 - 1); wy = np.abs((yy / (h - 1)) * 2 - 1)
    edge = np.clip(np.maximum(wx, wy) * 1.6 - 0.6, 0, 1) ** 2
    shifted = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    return a * (1 - edge) + shifted * edge

def save(a, name, size):
    a = (a - a.min()) / (a.max() - a.min() + 1e-6)
    h, w = a.shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels[:] = np.dstack([a, a, a, np.ones_like(a)]).ravel()
    img.scale(size, size)
    img.filepath_raw = os.path.join(OUT, name); img.file_format = "PNG"; img.save()
    print("wrote", name)

for src, name, size, lo in (("plush-velvet-src.png", "plush-height.png", 512, 40), ("knit-src.png", "knit-height.png", 512, 60)):
    lum = load(src)
    lum = lum[: min(lum.shape), : min(lum.shape)]
    # Height = the fine relief only: subtract the slow light falloff so it tiles evenly.
    detail = lum - blur(lum, lo)
    save(seamless(detail), name, size)
