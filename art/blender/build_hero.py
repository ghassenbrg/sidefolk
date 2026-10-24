"""Builds the Sidefolk pets (mesh, colors, rig, clips) and exports one glb per species:
public/models/hero.glb (Pip the bunny), cat.glb (Byte), fox.glb (Patch), sheep.glb (Loom), and
the Studio Collection's penguin.glb (Slate) and capsule.glb (Dot).

    npm run model
    # = blender --background --factory-startup --python art/blender/build_hero.py

Every species shares the skeleton, the clips and the palette colors, so every animation and
every palette (src/pet/look.ts recolors these exact colors) works on every species. The bunny,
cat and fox differ in ears, tail and face details; the penguin and capsule have their own
shapes ("form") on the same rig: Loom is a wool cloud with floppy ears, Slate shows no ears, Dot no arms (its alert sign rides the
hidden right arm bone).

Everything is modeled in app space (x right, y up, z toward the viewer, feet at y = 0) and
converted to Blender space (x, -z, y) when the mesh is built. Bones all point straight up with
no roll, so they export with identity rest rotations and their local axes match the app's.

References: art/concepts/hero-turnaround.png, art/HERO.md (palette, rig contract).
"""

import math
import os

import bmesh
import bpy
from mathutils import Euler, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "public", "models")
BLEND = os.path.join(ROOT, "art", "blender", "hero.blend")
FPS = 30


def srgb(hex_color):
    """Hex sRGB to linear RGBA, which is what glTF vertex colors hold."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_color[i : i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


COAT = srgb("F1E4D2")
CREAM = srgb("FFFAF3")
POINTS = srgb("4A3F4F")
INNER_EAR = srgb("F3AAA8")
BLUSH = srgb("F7A5A0")
SCARF = srgb("6FCFB4")
SCARF_DARK = srgb("5BB89E")
INK = srgb("2B2430")
WHITE = srgb("FFFFFF")
NOSE = srgb("E98E8E")
# Not palette regions: beaks and penguin feet, and the soft mouth on a dark face, keep their
# color in every coat.
BEAK = srgb("F2A541")
MOUTH = srgb("9A93A3")

# ---------------------------------------------------------------------------------------------
# Skeleton (app space). Parents first.

JOINTS = {
    "root": (None, (0, 0, 0)),
    "hips": ("root", (0, 0.3, 0)),
    "chest": ("hips", (0, 0.32, 0)),
    "head": ("chest", (0, 0.86, 0)),
    "earL": ("head", (-0.25, 1.78, -0.02)),
    "earLTip": ("earL", (-0.33, 2.16, -0.02)),
    "earR": ("head", (0.25, 1.78, -0.02)),
    "earRTip": ("earR", (0.33, 2.16, -0.02)),
    "eyeL": ("head", (-0.25, 1.33, 0.5)),
    "eyeR": ("head", (0.25, 1.33, 0.5)),
    "armL": ("chest", (-0.29, 0.74, 0.02)),
    "armR": ("chest", (0.29, 0.74, 0.02)),
    "legL": ("hips", (-0.16, 0.3, 0)),
    "legR": ("hips", (0.16, 0.3, 0)),
    "tail": ("hips", (0, 0.4, -0.28)),
}

# ---------------------------------------------------------------------------------------------
# Geometry helpers. Each part is (verts, faces, colors, weights) in app space.


class Part:
    def __init__(self, verts, faces, color, bone):
        self.verts = [Vector(v) for v in verts]
        self.faces = faces
        self.colors = [color] * len(verts)
        self.weights = [{bone: 1.0} for _ in verts]


# Segment counts above are written for close-up detail; the desktop shows pets about 150 px
# tall, so every sphere and ring is built at this fraction of them. It keeps each pet under the
# design package's 8k-triangle budget (creative-design/PRODUCTION.md).
DETAIL = 0.55


def unit_sphere(u=32, v=20):
    u, v = max(8, round(u * DETAIL)), max(5, round(v * DETAIL))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    bm.verts.index_update()
    verts = [v.co.copy() for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    # bmesh spheres are Z-up; turn them Y-up so their poles follow app space.
    return [Vector((p.x, p.z, -p.y)) for p in verts], faces


def ellipsoid(center, radii, color, bone, rotation=None, segments=(32, 20), shape=None):
    """`shape(p)` may reshape the unit-sphere point before scaling (for beans and tapers)."""
    verts, faces = unit_sphere(*segments)
    out = []
    for p in verts:
        if shape:
            p = shape(p)
        q = Vector((p.x * radii[0], p.y * radii[1], p.z * radii[2]))
        if rotation:
            q = rotation @ q
        out.append(q + Vector(center))
    return Part(out, faces, color, bone)


def torus(center, major, minor, color, bone, arc=2 * math.pi, segments=(40, 10), rotation=None, ribs=0):
    """Ring in the XZ plane (around the Y axis). `ribs` adds knit-like ridges."""
    n, m = max(8, round(segments[0] * DETAIL)), max(5, round(segments[1] * DETAIL))
    closed = arc >= 2 * math.pi - 1e-6
    rings = n if closed else n + 1
    verts, faces = [], []
    for i in range(rings):
        a = arc * i / n
        r = minor * (1 + 0.1 * math.sin(ribs * a)) if ribs else minor
        for j in range(m):
            b = 2 * math.pi * j / m
            p = Vector(((major + r * math.cos(b)) * math.cos(a), r * math.sin(b), (major + r * math.cos(b)) * math.sin(a)))
            if rotation:
                p = rotation @ p
            verts.append(p + Vector(center))
    for i in range(n):
        for j in range(m):
            a0, a1 = i, (i + 1) % rings
            # Wound so normals face outward (the outline hull depends on it).
            faces.append([a0 * m + j, a0 * m + (j + 1) % m, a1 * m + (j + 1) % m, a1 * m + j])
    return Part(verts, faces, color, bone)


def align_z(normal):
    """Rotation turning +Z (toward the viewer) to `normal`."""
    return Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized())


class Ellipsoid:
    """Analytic surface used to sit face and belly details exactly on the skin."""

    def __init__(self, center, radii):
        self.c = Vector(center)
        self.r = Vector(radii)

    def front(self, x, y, lift=0.0):
        dx = (x - self.c.x) / self.r.x
        dy = (y - self.c.y) / self.r.y
        z = self.c.z + self.r.z * math.sqrt(max(0.0, 1 - dx * dx - dy * dy))
        p = Vector((x, y, z))
        n = Vector(((p.x - self.c.x) / self.r.x**2, (p.y - self.c.y) / self.r.y**2, (p.z - self.c.z) / self.r.z**2))
        n.normalize()
        return p + n * lift, n


def decal(surface, x, y, radii, color, bone, lift=0.0, spin=0.0, segments=(24, 12)):
    """A flattened ellipsoid lying on a surface, half sunk in."""
    point, normal = surface.front(x, y, lift)
    rotation = align_z(normal).to_matrix() @ Euler((0, 0, spin)).to_matrix()
    return ellipsoid(point, radii, color, bone, rotation=rotation, segments=segments)


def arc_decal(surface, x, y, major, minor, color, bone, arc, spin, lift=0.004):
    """A thin curved stroke lying on a surface. With spin 0 the arc hangs below its center (a
    smile); spin turns it."""
    point, normal = surface.front(x, y, lift)
    # Torus rings lie in XZ; stand the stroke up in the XY plane, then align it to the skin.
    stand = Euler((math.pi / 2, 0, 0)).to_matrix()
    rotation = align_z(normal).to_matrix() @ Euler((0, 0, spin)).to_matrix() @ stand
    return torus(point, major, minor, color, bone, arc=arc, segments=(14, 6), rotation=rotation)


# ---------------------------------------------------------------------------------------------
# The character.

HEAD = Ellipsoid((0, 1.36, 0.02), (0.66, 0.52, 0.56))
BODY = Ellipsoid((0, 0.52, 0), (0.34, 0.38, 0.3))


def boxy(p):
    # Squarer than a sphere: a rounded slab, for the knitted scarf end.
    return Vector(tuple(math.copysign(abs(c) ** 0.45, c) for c in p))


def bean(p):
    # Slightly wider toward the bottom, like the turnaround's body.
    return Vector((p.x * (1 + 0.1 * -p.y), p.y, p.z * (1 + 0.06 * -p.y)))


def ear(side):
    """Long ear flaring outward; charcoal tip; weights blend from base bone to tip bone."""
    base = Vector((0.25 * side, 1.7, -0.02))
    tilt = Euler((0, 0, -0.17 * side)).to_matrix()
    length = 0.86
    part = ellipsoid(base + tilt @ Vector((0, length / 2, 0)), (0.14, length / 2, 0.075), COAT, "x", rotation=tilt, segments=(28, 24))
    inner = ellipsoid(
        base + tilt @ Vector((0, length * 0.45, 0.055)), (0.075, length * 0.28, 0.03), INNER_EAR, "x", rotation=tilt, segments=(20, 16)
    )
    bone, tip = ("earL", "earLTip") if side < 0 else ("earR", "earRTip")
    for p in (part, inner):
        for i, v in enumerate(p.verts):
            t = (tilt.transposed() @ (v - base)).y / length  # 0 at the base, 1 at the tip
            w = min(1.0, max(0.0, (t - 0.35) / 0.25))
            p.weights[i] = {bone: 1 - w, tip: w} if w > 0 else {bone: 1.0}
            if p is part and t > 0.72:
                p.colors[i] = POINTS
    return part, inner


def taper(p):
    # Wide at the base, nearly a point at the top: a cat or fox ear.
    t = max(0.06, (1 - p.y) / 2) ** 0.75
    return Vector((p.x * t, p.y, p.z * t))


def pointed_ear(side, length, width, tilt, tip_from):
    """Short pointed ear on the base ear bone only (the tip bone sits above it)."""
    base = Vector((0.27 * side, 1.64, -0.02))
    rotation = Euler((-0.12, 0, -tilt * side)).to_matrix()
    part = ellipsoid(base + rotation @ Vector((0, length / 2, 0)), (width, length / 2, 0.08), COAT, "earL" if side < 0 else "earR",
                     rotation=rotation, segments=(28, 24), shape=taper)
    inner = ellipsoid(base + rotation @ Vector((0, length * 0.42, 0.06)), (width * 0.55, length * 0.32, 0.03), INNER_EAR,
                      "earL" if side < 0 else "earR", rotation=rotation, segments=(20, 16), shape=taper)
    for i, v in enumerate(part.verts):
        if (rotation.transposed() @ (v - base)).y / length > tip_from:
            part.colors[i] = POINTS
    return part, inner


def long_tail():
    """A cat's tail curling up beside the body: overlapping beads, charcoal at the tip."""
    beads = [(0.0, 0.36, -0.3), (0.02, 0.42, -0.43), (0.04, 0.53, -0.53), (0.05, 0.66, -0.58), (0.05, 0.79, -0.57),
             (0.04, 0.91, -0.52), (0.03, 1.0, -0.45)]
    return [ellipsoid(c, (0.082 - 0.003 * k,) * 3, POINTS if k == len(beads) - 1 else COAT, "tail", segments=(16, 10))
            for k, c in enumerate(beads)]


def bushy_tail():
    """A fox's brush: one big plume and a cream tip."""
    # Sweeps up and back from the hips (negative x rotation tips +y toward -z).
    turn = Euler((-0.85, 0, -0.3)).to_matrix()
    base = Vector((0.04, 0.42, -0.34))
    center = base + turn @ Vector((0, 0.3, 0))
    tip = base + turn @ Vector((0, 0.62, 0))
    return [
        ellipsoid(center, (0.18, 0.34, 0.18), COAT, "tail", rotation=turn, segments=(24, 16)),
        ellipsoid(tip, (0.13, 0.14, 0.13), CREAM, "tail", segments=(18, 12)),
    ]


class Cylinder:
    """An upright elliptic cylinder: the straight middle of Dot's capsule, for its eyes and stripe."""

    def __init__(self, center, radii):
        self.c = Vector(center)
        self.r = Vector(radii)

    def front(self, x, y, lift=0.0):
        dx = (x - self.c.x) / self.r.x
        z = self.c.z + self.r.z * math.sqrt(max(0.0, 1 - dx * dx))
        n = Vector(((x - self.c.x) / self.r.x**2, 0, (z - self.c.z) / self.r.z**2)).normalized()
        return Vector((x, y, z)) + n * lift, n


def capsule(p):
    # A unit sphere stretched into a capsule: straight sides for |y| < 0.5, round ends.
    ring = math.sqrt(max(1e-9, p.x * p.x + p.z * p.z))
    end = max(0.0, abs(p.y) - 0.5) / 0.5
    want = math.sqrt(max(0.0, 1 - end * end))
    k = want / ring if ring > 1e-4 else 0
    return Vector((p.x * k, p.y, p.z * k))


def eyes(surface, x, y, size, out, lift=0.0):
    """Small ordinary eyes (Studio Collection): dark ovals with one highlight, no brows or blush.
    `lift` raises them over a face patch they sit on."""
    for s in (-1, 1):
        eye = "eyeL" if s < 0 else "eyeR"
        out.append(decal(surface, x * s, y, (size, size * 1.2, 0.04), INK, eye, lift=lift - 0.01))
        out.append(decal(surface, x * s - size * 0.3, y + size * 0.35, (size * 0.3, size * 0.33, 0.02), WHITE, eye, lift=lift + 0.028, segments=(12, 8)))


def build_penguin(spec):
    """Slate: charcoal penguin, ivory face and belly, mint lapel patch, flippers, no visible ears."""
    head = Ellipsoid((0, 1.42, 0.02), (0.6, 0.53, 0.52))
    belly = Ellipsoid((0, 0.66, 0), (0.5, 0.6, 0.42))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(40, 28)),
        ellipsoid(belly.c, belly.r, COAT, "chest", segments=(36, 24), shape=bean),
        ellipsoid((0, 0.5, -0.36), (0.12, 0.1, 0.1), POINTS, "tail", segments=(16, 10)),
    ]
    face = [
        decal(head, 0, 1.3, (0.42, 0.3, 0.05), CREAM, "head", lift=-0.035),
        decal(belly, 0, 0.6, (0.34, 0.44, 0.05), CREAM, "chest", lift=-0.03),
        # The mint lapel patch, on the viewer's right, over the edge of the belly.
        decal(belly, 0.27, 0.9, (0.08, 0.1, 0.035), SCARF, "chest", lift=0.03, segments=(16, 10)),
    ]
    # A small beak pointing at the viewer.
    tip, normal = head.front(0, 1.3, 0.04)
    face.append(ellipsoid(tip, (0.075, 0.11, 0.055), BEAK, "head", rotation=align_z(normal).to_matrix() @ Euler((math.pi / 2, 0, 0)).to_matrix(),
                          shape=taper, segments=(18, 12)))
    eyes(head, 0.2, 1.42, 0.085, face, lift=0.045)
    # Flippers: flat, hanging close to the body.
    for s in (-1, 1):
        bone = "armL" if s < 0 else "armR"
        shoulder = Vector((0.36 * s, 0.86, 0.02))
        paw = Vector((0.55 * s, 0.5, 0.06))
        turn = Vector((0, -1, 0)).rotation_difference((paw - shoulder).normalized()).to_matrix()
        body.append(ellipsoid((shoulder + paw) / 2, (0.05, 0.25, 0.13), COAT, bone, rotation=turn, segments=(20, 14)))
    # Orange feet; the legs stay inside the body.
    for s in (-1, 1):
        body.append(ellipsoid((0.17 * s, 0.06, 0.1), (0.14, 0.055, 0.2), BEAK, "legL" if s < 0 else "legR", segments=(22, 12)))
    return body, face


def build_capsule(spec):
    """Dot: an ivory capsule with two tiny dark eyes and a mint side stripe. No visible arms;
    the alert sign rides the hidden right arm bone like an anchored sign."""
    radii = (0.55, 0.95, 0.5)
    shell = ellipsoid((0, 1.0, 0), radii, COAT, "chest", segments=(40, 32), shape=capsule)
    # The top bends with the head bone, the bottom stays with the chest.
    for i, v in enumerate(shell.verts):
        w = min(1.0, max(0.0, (v.y - 1.0) / 0.5))
        shell.weights[i] = {"chest": 1 - w, "head": w} if w > 0 else {"chest": 1.0}
    side = Cylinder((0, 1.0, 0), radii)
    face = []
    eyes(side, 0.16, 1.36, 0.065, face)
    # Mint stripe down the viewer's right side.
    angle = 1.05
    point = Vector((radii[0] * math.sin(angle), 0.95, radii[2] * math.cos(angle)))
    normal = Vector((math.sin(angle) / radii[0], 0, math.cos(angle) / radii[2])).normalized()
    face.append(ellipsoid(point + normal * -0.012, (0.045, 0.36, 0.025), SCARF, "chest", rotation=align_z(normal).to_matrix(), segments=(16, 16)))
    body = [shell]
    for s in (-1, 1):
        body.append(ellipsoid((0.2 * s, 0.07, 0.06), (0.12, 0.07, 0.15), POINTS, "legL" if s < 0 else "legR", segments=(18, 10)))
    return body, face


def build_sheep(spec):
    """Loom: a lavender wool cloud (a few broad puffs, not curls) around a charcoal face, floppy
    ears, dark legs and one chunky scarf knot."""
    head = Ellipsoid((0, 1.3, 0.06), (0.5, 0.44, 0.46))
    body = [ellipsoid(head.c, head.r, POINTS, "head", segments=(36, 24))]
    # Wool crown over the top and back of the head.
    for x, y, z, r in [(0, 1.72, -0.02, 0.25), (-0.3, 1.66, -0.05, 0.22), (0.3, 1.66, -0.05, 0.22), (-0.48, 1.46, -0.12, 0.2),
                       (0.48, 1.46, -0.12, 0.2), (0, 1.52, -0.3, 0.32), (-0.17, 1.8, 0.12, 0.17), (0.17, 1.8, 0.12, 0.17)]:
        body.append(ellipsoid((x, y, z), (r, r * 0.92, r), COAT, "head", segments=(20, 14)))
    # The wool body: one core and a ring of broad puffs.
    body.append(ellipsoid((0, 0.6, 0), (0.44, 0.42, 0.38), COAT, "chest", segments=(32, 22), shape=bean))
    for k in range(9):
        a = TAU * k / 9
        for y, spread, r in ((0.42, 0.4, 0.2), (0.76, 0.34, 0.19)):
            body.append(ellipsoid((spread * math.sin(a), y + 0.03 * math.cos(3 * a), spread * 0.92 * math.cos(a)), (r, r * 0.9, r), COAT, "chest", segments=(18, 12)))
    body.append(ellipsoid((0, 0.5, -0.4), (0.15, 0.14, 0.13), COAT, "tail", segments=(16, 10)))
    face = []
    # Floppy ears, dark outside and pink inside.
    for s in (-1, 1):
        bone = "earL" if s < 0 else "earR"
        turn = Euler((0, 0, 0.45 * s)).to_matrix()
        body.append(ellipsoid((0.56 * s, 1.36, 0.04), (0.23, 0.085, 0.12), POINTS, bone, rotation=turn, segments=(20, 12)))
        face.append(ellipsoid((0.56 * s, 1.35, 0.13), (0.15, 0.05, 0.035), INNER_EAR, bone, rotation=turn, segments=(16, 10)))
    # Chunky scarf: a thick ribbed ring, a knot at the front and a small pom.
    # It sits over the wool, so the knot stays visible at small sizes.
    body.append(torus((0, 0.99, 0.03), 0.37, 0.1, SCARF, "chest", segments=(48, 12), ribs=22))
    body.append(ellipsoid((0.15, 0.9, 0.47), (0.13, 0.11, 0.1), SCARF, "chest", segments=(18, 12)))
    face.append(ellipsoid((0.23, 0.72, 0.5), (0.07, 0.07, 0.065), SCARF_DARK, "chest", segments=(14, 10)))
    # Dark arms and legs.
    for s in (-1, 1):
        bone = "armL" if s < 0 else "armR"
        shoulder = Vector((0.29 * s, 0.74, 0.02))
        paw = Vector((0.5 * s, 0.49, 0.1))
        turn = Vector((0, -1, 0)).rotation_difference((paw - shoulder).normalized()).to_matrix()
        body.append(ellipsoid((shoulder + paw) / 2, (0.08, 0.2, 0.08), POINTS, bone, rotation=turn, segments=(18, 12)))
        body.append(ellipsoid(paw, (0.095, 0.09, 0.095), POINTS, bone, segments=(18, 12)))
        leg = "legL" if s < 0 else "legR"
        body.append(ellipsoid((0.16 * s, 0.18, 0.0), (0.1, 0.16, 0.1), POINTS, leg, segments=(16, 10)))
        body.append(ellipsoid((0.17 * s, 0.07, 0.05), (0.13, 0.07, 0.16), POINTS, leg, segments=(20, 12)))
    # Eyes with a white ring, so they read on the dark face; slow-blinking like the rest.
    for s in (-1, 1):
        eye = "eyeL" if s < 0 else "eyeR"
        face.append(decal(head, 0.2 * s, 1.34, (0.12, 0.14, 0.04), WHITE, eye, lift=-0.012))
        face.append(decal(head, 0.2 * s, 1.33, (0.09, 0.11, 0.04), INK, eye, lift=0.0))
        face.append(decal(head, 0.2 * s - 0.03, 1.37, (0.028, 0.032, 0.02), WHITE, eye, lift=0.032, segments=(12, 8)))
        face.append(decal(head, 0.36 * s, 1.18, (0.075, 0.045, 0.02), BLUSH, "head", lift=-0.004, segments=(16, 10)))
        face.append(arc_decal(head, 0.03 * s, 1.15, 0.03, 0.009, MOUTH, "head", arc=math.pi, spin=0, lift=0.006))
    return body, face


# ---------------------------------------------------------------------------------------------
# The rest of the roster (creative-design/CHARACTERS.md, PROFESSIONAL-COLLECTION.md). Each one
# is a few broad shapes on the shared rig; colors use the palette regions (COAT, POINTS, CREAM,
# SCARF) so every coat works, plus a few fixed colors (skin, gold, grey, book).

SKIN = srgb("F6DCC8")
GREY = srgb("8F929C")
GOLD = srgb("E3B955")
BOOK = srgb("8A5A3C")


def rounded(k):
    """Unit-sphere reshaper toward a rounded box; k < 1 squares it off (0.45 is very boxy)."""
    return lambda p: Vector(tuple(math.copysign(abs(c) ** k, c) for c in p))


class Flat:
    """A flat front at depth z, for screens and faceplates on boxy heads."""

    def __init__(self, z):
        self.z = z

    def front(self, x, y, lift=0.0):
        return Vector((x, y, self.z + lift)), Vector((0, 0, 1))


def limb(start, end, radius, color, bone, segments=(18, 12)):
    """An ellipsoid stretched from start to end (an arm, a leg, a tentacle piece)."""
    start, end = Vector(start), Vector(end)
    turn = Vector((0, 1, 0)).rotation_difference((end - start).normalized()).to_matrix()
    r = radius if isinstance(radius, tuple) else (radius, radius)
    return ellipsoid((start + end) / 2, (r[0], (end - start).length / 2 + r[0] * 0.4, r[1]), color, bone, rotation=turn, segments=segments)


def arms(color, hand, hand_color, shoulder_y=0.74, spread=0.29, reach=(0.5, 0.49, 0.08), thick=0.09):
    out = []
    for s in (-1, 1):
        bone = "armL" if s < 0 else "armR"
        shoulder = Vector((spread * s, shoulder_y, 0.02))
        paw = Vector((reach[0] * s, reach[1], reach[2]))
        out.append(limb(shoulder, paw, thick, color, bone))
        if hand:
            out.append(ellipsoid(paw, (hand, hand * 0.95, hand), hand_color, bone, segments=(18, 12)))
    return out


def legs(color, foot_color, thick=0.11, foot=(0.14, 0.08, 0.19), spread=0.16):
    out = []
    for s in (-1, 1):
        bone = "legL" if s < 0 else "legR"
        out.append(ellipsoid((spread * s, 0.2, 0.0), (thick, 0.13, thick), color, bone, segments=(16, 10)))
        out.append(ellipsoid((spread * s, foot[1], 0.05), foot, foot_color, bone, segments=(20, 12)))
    return out


def big_eyes(surface, x, y, size, out, lift=0.0, ring=None, iris=None):
    """Friendly eyes: dark ovals, a big and a small highlight; `ring` adds a light rim for dark
    faces, `iris` a colored lower half (anime eyes)."""
    for s in (-1, 1):
        eye = "eyeL" if s < 0 else "eyeR"
        if ring:
            out.append(decal(surface, x * s, y + size * 0.05, (size * 1.3, size * 1.5, 0.04), ring, eye, lift=lift - 0.012))
        out.append(decal(surface, x * s, y, (size, size * 1.22, 0.045), INK, eye, lift=lift))
        if iris:
            out.append(decal(surface, x * s, y - size * 0.4, (size * 0.75, size * 0.55, 0.03), iris, eye, lift=lift + 0.02, segments=(16, 10)))
        out.append(decal(surface, x * s - size * 0.32, y + size * 0.42, (size * 0.34, size * 0.38, 0.02), WHITE, eye, lift=lift + 0.035, segments=(12, 8)))
        out.append(decal(surface, x * s + size * 0.35, y - size * 0.42, (size * 0.15, size * 0.15, 0.01), WHITE, eye, lift=lift + 0.035, segments=(10, 6)))


def smile(surface, y, out, color=INK, width=0.034, lift=0.01, blush=None, blush_x=0.36):
    for s in (-1, 1):
        out.append(arc_decal(surface, 0.035 * s, y, width, 0.0095, color, "head", arc=math.pi, spin=0, lift=lift))
        if blush:
            out.append(decal(surface, blush_x * s, y + 0.03, (0.08, 0.045, 0.02), blush, "head", lift=-0.004, segments=(16, 10)))


def beak(surface, y, color, out, size=(0.07, 0.1, 0.05)):
    tip, normal = surface.front(0, y, 0.035)
    out.append(ellipsoid(tip, size, color, "head", rotation=align_z(normal).to_matrix() @ Euler((math.pi / 2, 0, 0)).to_matrix(), shape=taper, segments=(16, 10)))


def build_turtle(spec):
    """Moss: sage turtle with a low rounded shell, cream front plate and a small mint neck tag;
    the face stays fully visible."""
    head = Ellipsoid((0, 1.34, 0.1), (0.47, 0.41, 0.42))
    torso = Ellipsoid((0, 0.66, 0.06), (0.4, 0.44, 0.34))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(36, 24)),
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(30, 20), shape=bean),
        # The shell: one broad dome on the back and its rim.
        ellipsoid((0, 0.74, -0.2), (0.56, 0.6, 0.4), POINTS, "chest", segments=(36, 24)),
        torus((0, 0.74, -0.12), 0.5, 0.06, POINTS, "chest", rotation=Euler((0, 0, math.pi / 2)).to_matrix() @ Euler((math.pi / 2, 0, 0)).to_matrix(), segments=(40, 10)),
        ellipsoid((0, 0.36, -0.3), (0.09, 0.08, 0.12), COAT, "tail", segments=(14, 10)),
    ]
    face = [decal(torso, 0, 0.64, (0.3, 0.38, 0.05), CREAM, "chest", lift=-0.02)]
    for k in range(3):  # plate seams
        face.append(decal(torso, 0, 0.45 + 0.15 * k, (0.2, 0.008, 0.012), POINTS, "chest", lift=0.012, segments=(12, 6)))
    face.append(decal(head, 0, 1.17, (0.25, 0.14, 0.04), CREAM, "head", lift=-0.025))
    big_eyes(head, 0.19, 1.37, 0.085, face)
    smile(head, 1.16, face, blush=BLUSH, blush_x=0.32)
    body.append(torus((0, 1.0, 0.08), 0.27, 0.025, SCARF, "chest", segments=(40, 8)))
    face.append(decal(torso, 0, 0.92, (0.065, 0.085, 0.03), SCARF, "chest", lift=0.03, segments=(14, 10)))
    body += arms(COAT, 0.1, COAT, spread=0.33, reach=(0.52, 0.5, 0.12), thick=0.1)
    body += legs(COAT, COAT, thick=0.13, foot=(0.15, 0.09, 0.18))
    return body, face


def robot_body(spec, face_kind):
    """Relay and Orbit: an ivory robot with a rounded head, a dark faceplate and an antenna."""
    head = Ellipsoid((0, 1.4, 0.02), (0.52, 0.44, 0.44))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(36, 24), shape=rounded(0.8)),
        ellipsoid((0, 0.66, 0), (0.38, 0.4, 0.34), COAT, "chest", segments=(30, 20), shape=rounded(0.85)),
    ]
    plate = Ellipsoid((0, 1.4, 0.04), (0.5, 0.42, 0.44))
    face = [decal(plate, 0, 1.39, (0.39, 0.27, 0.05), POINTS, "head", lift=-0.015)]
    if face_kind == "smile":
        for s in (-1, 1):
            eye = "eyeL" if s < 0 else "eyeR"
            face.append(arc_decal(plate, 0.16 * s, 1.37, 0.065, 0.02, SCARF, eye, arc=math.pi, spin=math.pi, lift=0.04))
        face.append(arc_decal(plate, 0, 1.27, 0.05, 0.013, SCARF, "head", arc=math.pi, spin=0, lift=0.04))
        face.append(decal(Ellipsoid((0, 0.66, 0), (0.38, 0.4, 0.34)), 0, 0.7, (0.07, 0.07, 0.04), SCARF, "chest", lift=0.02, segments=(16, 10)))
        for s in (-1, 1):  # ear discs
            body.append(ellipsoid((0.53 * s, 1.4, 0.0), (0.06, 0.13, 0.13), GREY, "earL" if s < 0 else "earR", segments=(18, 12)))
    else:
        for s in (-1, 1):
            face.append(decal(plate, 0.15 * s, 1.4, (0.075, 0.022, 0.03), SCARF, "eyeL" if s < 0 else "eyeR", lift=0.035, segments=(16, 8)))
    # Antenna: a thin stalk and a mint ball; it rides an ear bone so it sways a little.
    lean = 0.25 if face_kind == "smile" else 0.0
    base = Vector((0.08, 1.8, 0.0))
    top = base + Vector((lean * 0.4, 0.36, 0))
    body.append(limb(base, top, 0.02, GREY, "earR", segments=(8, 6)))
    body.append(ellipsoid(top, (0.065, 0.065, 0.065), SCARF, "earR", segments=(14, 10)))
    body += arms(GREY if face_kind != "smile" else COAT, 0.1, COAT, reach=(0.5, 0.48, 0.08))
    body += legs(GREY, POINTS, thick=0.1, foot=(0.13, 0.08, 0.17))
    return body, face


def build_relay(spec):
    """Relay: expressive ivory robot, smiling mint screen eyes, ear discs, a bent antenna."""
    return robot_body(spec, "smile")


def build_orbit(spec):
    """Orbit: the quiet one. Dark faceplate, two mint bars, a straight antenna, grey arms."""
    return robot_body(spec, "bars")


def build_raccoon(spec):
    """Stack: raccoon with a dark eye mask, cream face, a mint overshirt, one closed book and a
    tail with three broad bands."""
    side = (-1, 1)
    body = [ellipsoid(HEAD.c, (0.62, 0.5, 0.54), COAT, "head", segments=(40, 28))]
    torso = Ellipsoid((0, 0.56, 0), (0.42, 0.42, 0.34))
    body.append(ellipsoid(torso.c, torso.r, SCARF, "chest", segments=(32, 22), shape=bean))
    face = [decal(torso, 0, 0.52, (0.2, 0.32, 0.04), CREAM, "chest", lift=-0.01)]
    for s in side:  # the shirt's open front edges
        face.append(decal(torso, 0.17 * s, 0.6, (0.04, 0.3, 0.03), SCARF_DARK, "chest", lift=0.012, segments=(10, 12)))
    face.append(decal(HEAD, 0, 1.2, (0.42, 0.25, 0.05), CREAM, "head", lift=-0.03))
    for s in (-1, 1):  # the mask: one dark patch around each eye
        face.append(decal(HEAD, 0.23 * s, 1.35, (0.2, 0.13, 0.05), POINTS, "head", lift=-0.018, spin=0.15 * s))
    big_eyes(HEAD, 0.23, 1.36, 0.075, face, lift=0.02, ring=CREAM)
    face.append(decal(HEAD, 0, 1.2, (0.06, 0.045, 0.03), INK, "head", lift=0.0, segments=(14, 8)))
    smile(HEAD, 1.12, face)
    for s in side:
        part, inner = pointed_ear(s, 0.34, 0.2, 0.42, 0.62)
        body.append(part)
        face.append(inner)
    body += arms(SCARF, 0.1, POINTS)
    body += legs(POINTS, POINTS, thick=0.12)
    # The book, held in the left paw (the right one holds the alert sign).
    body.append(ellipsoid((-0.48, 0.55, 0.16), (0.07, 0.16, 0.12), BOOK, "armL", segments=(12, 10), shape=rounded(0.4)))
    turn = Euler((-0.9, 0, 0.35)).to_matrix()
    base = Vector((0.06, 0.4, -0.32))
    for k in range(6):  # three dark bands on a broad tail
        c = base + turn @ Vector((0, 0.12 * k, 0))
        body.append(ellipsoid(c, (0.17 - 0.012 * k, 0.09, 0.17 - 0.012 * k), POINTS if k % 2 else COAT, "tail", rotation=turn, segments=(18, 10)))
    return body, face


def build_squid(spec):
    """Nib: indigo squid with a tapered cap, a cream face, four broad tentacles and a mint pencil
    tucked at the side of the head."""
    cap = Ellipsoid((0, 1.5, 0), (0.5, 0.7, 0.46))
    body = [
        ellipsoid(cap.c, cap.r, COAT, "head", segments=(36, 28), shape=taper),
        ellipsoid((0, 1.1, 0.02), (0.46, 0.34, 0.42), COAT, "head", segments=(32, 20)),
        ellipsoid((0, 0.72, 0), (0.32, 0.26, 0.28), COAT, "chest", segments=(24, 16)),
    ]
    front = Ellipsoid((0, 1.1, 0.02), (0.46, 0.34, 0.42))
    face = [decal(front, 0, 1.08, (0.34, 0.25, 0.05), CREAM, "head", lift=-0.025)]
    big_eyes(front, 0.15, 1.12, 0.07, face, lift=0.01)
    smile(front, 0.98, face, blush=BLUSH, blush_x=0.27)
    # Tentacles: two on the arm bones, two on the leg bones, each a tapering chain.
    for bone, points in [
        ("armL", [(-0.28, 0.74, 0.04), (-0.48, 0.6, 0.08), (-0.6, 0.42, 0.1), (-0.58, 0.3, 0.12)]),
        ("armR", [(0.28, 0.74, 0.04), (0.48, 0.6, 0.08), (0.6, 0.42, 0.1), (0.58, 0.3, 0.12)]),
        ("legL", [(-0.14, 0.5, 0.04), (-0.2, 0.3, 0.08), (-0.3, 0.12, 0.1), (-0.42, 0.06, 0.1)]),
        ("legR", [(0.14, 0.5, 0.04), (0.2, 0.3, 0.08), (0.3, 0.12, 0.1), (0.42, 0.06, 0.1)]),
    ]:
        for k in range(len(points) - 1):
            body.append(limb(points[k], points[k + 1], 0.11 - 0.02 * k, COAT, bone))
        tip = Vector(points[-1])
        face.append(ellipsoid(tip + Vector((0, 0.0, 0.07)), (0.035, 0.035, 0.02), GREY, bone, segments=(10, 6)))
    turn = Euler((0, 0, -0.5)).to_matrix()
    body.append(ellipsoid((0.42, 1.42, 0.18), (0.045, 0.24, 0.045), SCARF, "head", rotation=turn, segments=(10, 12)))
    body.append(ellipsoid(Vector((0.42, 1.42, 0.18)) + turn @ Vector((0, -0.26, 0)), (0.04, 0.06, 0.04), CREAM, "head", rotation=turn, shape=taper, segments=(10, 8)))
    return body, face


def build_crt(spec):
    """Pico: a cheerful CRT bot. One wide screen with static mint eyes and a cursor mouth, mint
    mitten hands and boots; no flicker."""
    screen = Flat(0.42)
    shell = ellipsoid((0, 0.82, 0), (0.62, 0.5, 0.42), COAT, "chest", segments=(36, 24), shape=rounded(0.5))
    for i, v in enumerate(shell.verts):
        w = min(1.0, max(0.0, (v.y - 0.75) / 0.45))
        shell.weights[i] = {"chest": 1 - w, "head": w} if w > 0 else {"chest": 1.0}
    body = [shell, ellipsoid((0.6, 0.8, 0.02), (0.05, 0.13, 0.13), GREY, "head", segments=(14, 10))]
    face = [ellipsoid((0, 0.84, 0.38), (0.48, 0.35, 0.06), POINTS, "head", segments=(28, 18), shape=rounded(0.45))]
    for s in (-1, 1):
        face.append(decal(screen, 0.15 * s, 0.91, (0.045, 0.075, 0.02), SCARF, "eyeL" if s < 0 else "eyeR", lift=0.03, segments=(14, 10)))
    # The cursor mouth, ">".
    for s in (-1, 1):
        face.append(ellipsoid((0.03, 0.74 + 0.025 * s, 0.45), (0.04, 0.012, 0.012), SCARF, "head", rotation=Euler((0, 0, -0.6 * s)).to_matrix(), segments=(10, 6)))
    body += arms(GREY, 0.1, SCARF, shoulder_y=0.7, spread=0.55, reach=(0.74, 0.5, 0.06), thick=0.06)
    body += legs(GREY, SCARF, thick=0.09, foot=(0.15, 0.09, 0.2), spread=0.22)
    return body, face


def person(hair_parts, outfit, accents):
    """Sora and Yuna: chibi adults (about 2.5 heads tall) on the shared rig."""
    head = Ellipsoid((0, 1.42, 0.03), (0.46, 0.44, 0.42))
    body = [ellipsoid(head.c, head.r, SKIN, "head", segments=(36, 24))]
    face = []
    big_eyes(head, 0.17, 1.36, 0.075, face, iris=accents.get("iris"))
    face.append(arc_decal(head, 0, 1.2, 0.03, 0.009, INK, "head", arc=math.pi, spin=0, lift=0.006))
    for s in (-1, 1):
        face.append(decal(head, 0.3 * s, 1.25, (0.06, 0.035, 0.02), BLUSH, "head", lift=-0.004, segments=(14, 8)))
    body += hair_parts
    body += outfit
    return body, face


def hair_bob(tuft):
    parts = [
        ellipsoid((0, 1.55, -0.06), (0.52, 0.38, 0.46), POINTS, "head", segments=(32, 20)),
        ellipsoid((0, 1.38, -0.16), (0.5, 0.42, 0.36), POINTS, "head", segments=(28, 18)),
    ]
    for x in (-0.28, -0.1, 0.1, 0.28):  # bangs
        parts.append(ellipsoid((x, 1.66, 0.3), (0.13, 0.13, 0.08), POINTS, "head", segments=(14, 10)))
    for s in (-1, 1):  # side locks down to the jaw
        parts.append(ellipsoid((0.43 * s, 1.3, 0.06), (0.1, 0.24, 0.16), POINTS, "head", segments=(14, 12)))
    if tuft:
        parts.append(limb((0.02, 1.88, -0.04), (0.14, 2.12, 0.0), (0.035, 0.02), POINTS, "earR", segments=(8, 8)))
    return parts


def build_courier(spec):
    """Sora: navy bob with one upright tuft, cream jacket, short mint scarf, navy trousers."""
    torso = Ellipsoid((0, 0.72, 0), (0.33, 0.3, 0.27))
    outfit = [
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(28, 18)),
        torus((0, 0.98, 0.0), 0.2, 0.06, SCARF, "chest", segments=(32, 10)),
        ellipsoid((0.14, 0.84, 0.25), (0.06, 0.11, 0.03), SCARF, "chest", rotation=Euler((0.3, 0, 0.3)).to_matrix(), segments=(12, 10)),
        ellipsoid((0, 0.46, 0), (0.3, 0.12, 0.25), POINTS, "hips", segments=(22, 12)),
    ]
    outfit += arms(COAT, 0.075, SKIN, shoulder_y=0.86, spread=0.3, reach=(0.42, 0.5, 0.06), thick=0.08)
    outfit += legs(POINTS, CREAM, thick=0.12, foot=(0.12, 0.08, 0.17), spread=0.13)
    return person(hair_bob(True), outfit, {"iris": srgb("4A6FA5")})


def build_archivist(spec):
    """Yuna: plum bob with bangs and a small crescent clip, a mint shoulder cape, a cream tunic,
    dark leggings and boots."""
    torso = Ellipsoid((0, 0.68, 0), (0.32, 0.34, 0.27))
    outfit = [
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(28, 18), shape=bean),
        # The cape: narrow at the neck, over the shoulders, open below the chest.
        ellipsoid((0, 0.86, -0.03), (0.58, 0.27, 0.48), SCARF, "chest", segments=(28, 16), shape=taper),
        ellipsoid((0, 0.95, 0.2), (0.035, 0.035, 0.02), GOLD, "chest", segments=(10, 6)),
        ellipsoid((0, 0.66, 0.0), (0.33, 0.03, 0.28), INK, "chest", segments=(24, 6)),
    ]
    outfit += arms(COAT, 0.072, SKIN, shoulder_y=0.84, spread=0.29, reach=(0.36, 0.52, 0.12), thick=0.075)
    outfit += legs(INK, INK, thick=0.09, foot=(0.11, 0.1, 0.15), spread=0.12)
    hair = hair_bob(False)
    # The crescent clip, on top of the hair at the viewer's right.
    hair.append(torus((0.33, 1.66, 0.36), 0.06, 0.02, GOLD, "head", arc=math.pi * 1.3, rotation=Euler((math.pi / 2, 0, 0.4)).to_matrix(), segments=(14, 6)))
    return person(hair, outfit, {"iris": srgb("7A5C99")})


def build_dragon(spec):
    """Kite: a rounded mint dragon with two rounded horns, a cream belly, small folded wings and
    a thick tail. No sharp shapes."""
    head = Ellipsoid((0, 1.36, 0.06), (0.52, 0.45, 0.46))
    torso = Ellipsoid((0, 0.62, 0), (0.42, 0.44, 0.36))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(36, 24)),
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(30, 20), shape=bean),
    ]
    face = [decal(torso, 0, 0.58, (0.27, 0.36, 0.05), CREAM, "chest", lift=-0.02), decal(head, 0, 1.18, (0.28, 0.16, 0.05), CREAM, "head", lift=-0.025)]
    big_eyes(head, 0.2, 1.38, 0.09, face, iris=srgb("C98A2E"))
    face.append(arc_decal(head, 0, 1.17, 0.07, 0.012, INK, "head", arc=math.pi, spin=0, lift=0.02))
    for s in (-1, 1):
        face.append(decal(head, 0.08 * s, 1.24, (0.018, 0.014, 0.01), INK, "head", lift=0.022, segments=(8, 6)))
        bone = "earL" if s < 0 else "earR"
        turn = Euler((-0.5, 0, -0.35 * s)).to_matrix()
        body.append(ellipsoid(Vector((0.24 * s, 1.75, -0.04)) + turn @ Vector((0, 0.12, 0)), (0.075, 0.16, 0.075), CREAM, bone, rotation=turn, shape=taper, segments=(14, 10)))
        # Folded wings on the back: two flat rounded leaves.
        wing = Euler((0.2, 0.5 * s, -0.5 * s)).to_matrix()
        body.append(ellipsoid((0.3 * s, 0.86, -0.3), (0.24, 0.18, 0.04), POINTS, "chest", rotation=wing, segments=(18, 10)))
        face.append(decal(torso, 0.25 * s, 0.8, (0.05, 0.05, 0.02), POINTS, "chest", lift=-0.004, segments=(10, 6)))
    for k in range(3):  # soft spikes down the back of the head
        body.append(ellipsoid((0, 1.72 - 0.16 * k, -0.3 - 0.08 * k), (0.06, 0.08, 0.06), POINTS, "head", segments=(10, 8)))
    turn = Euler((-1.15, 0, 0.25)).to_matrix()
    base = Vector((0.04, 0.4, -0.3))
    for k in range(5):
        body.append(ellipsoid(base + turn @ Vector((0, 0.13 * k, 0)), (0.15 - 0.022 * k,) * 3, COAT, "tail", segments=(16, 10)))
    body += arms(COAT, 0.1, COAT, reach=(0.5, 0.5, 0.12), thick=0.1)
    body += legs(COAT, POINTS, thick=0.13)
    return body, face


def build_owl(spec):
    """Calder: slate owl, angular brow tufts, cream face disc and belly, thin mint collar."""
    head = Ellipsoid((0, 1.38, 0.02), (0.56, 0.46, 0.48))
    torso = Ellipsoid((0, 0.66, 0), (0.48, 0.5, 0.42))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(36, 24)),
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(32, 22), shape=bean),
        torus((0, 0.98, 0.02), 0.44, 0.028, SCARF, "chest", segments=(48, 8)),
    ]
    face = [decal(torso, 0, 0.6, (0.32, 0.4, 0.05), CREAM, "chest", lift=-0.025)]
    for s in (-1, 1):
        face.append(decal(head, 0.17 * s, 1.36, (0.19, 0.2, 0.05), CREAM, "head", lift=-0.03))
        bone = "earL" if s < 0 else "earR"
        tuft = Euler((0, 0, -0.55 * s)).to_matrix()
        body.append(ellipsoid(Vector((0.38 * s, 1.74, 0.02)), (0.12, 0.17, 0.08), COAT, bone, rotation=tuft, shape=taper, segments=(14, 10)))
        # Angular brow: one flat dark stroke over each eye.
        face.append(decal(head, 0.2 * s, 1.52, (0.13, 0.025, 0.02), POINTS, "head", lift=0.005, spin=-0.25 * s, segments=(12, 6)))
        # Wings as arms: long flat feathers at the sides.
        arm = "armL" if s < 0 else "armR"
        body.append(limb((0.4 * s, 0.86, 0.0), (0.5 * s, 0.4, 0.02), (0.1, 0.16), POINTS, arm))
    face.append(decal(head, 0, 1.28, (0.26, 0.16, 0.05), CREAM, "head", lift=-0.03))
    eyes(head, 0.17, 1.37, 0.065, face, lift=0.02)
    beak(head, 1.25, POINTS, face, size=(0.05, 0.075, 0.045))
    body += legs(COAT, POINTS, thick=0.09, foot=(0.12, 0.05, 0.14))
    return body, face


def build_bird(spec):
    """Finch: a round sand bird with a dark cap, a charcoal folded wing with a mint tab, a small
    beak and thin legs."""
    head = Ellipsoid((0, 1.25, 0.06), (0.5, 0.44, 0.46))
    torso = Ellipsoid((0, 0.72, 0), (0.5, 0.5, 0.45))
    body = [
        ellipsoid(head.c, head.r, COAT, "head", segments=(36, 24)),
        ellipsoid(torso.c, torso.r, COAT, "chest", segments=(32, 22), shape=bean),
        ellipsoid((0, 1.48, -0.06), (0.47, 0.28, 0.42), POINTS, "head", segments=(30, 16)),
        ellipsoid((0, 0.55, -0.48), (0.12, 0.05, 0.22), POINTS, "tail", rotation=Euler((0.6, 0, 0)).to_matrix(), segments=(14, 8)),
    ]
    face = []
    eyes(head, 0.19, 1.3, 0.065, face, lift=0.0)
    beak(head, 1.16, POINTS, face, size=(0.05, 0.08, 0.04))
    for s in (-1, 1):
        arm = "armL" if s < 0 else "armR"
        wing = Euler((0.1, 0.25 * s, -0.3 * s)).to_matrix()
        body.append(ellipsoid((0.47 * s, 0.74, 0.06), (0.1, 0.34, 0.26), POINTS, arm, rotation=wing, segments=(18, 12)))
        face.append(ellipsoid((0.56 * s, 0.7, 0.14), (0.035, 0.15, 0.1), SCARF, arm, rotation=wing, segments=(12, 8)))
        leg = "legL" if s < 0 else "legR"
        body.append(limb((0.14 * s, 0.3, 0.0), (0.15 * s, 0.05, 0.02), 0.025, POINTS, leg, segments=(8, 6)))
        body.append(ellipsoid((0.15 * s, 0.03, 0.08), (0.07, 0.025, 0.1), POINTS, leg, segments=(10, 6)))
    return body, face


SPECIES = {
    "hero": {"ears": "long", "tail": "puff"},
    "cat": {"ears": (0.5, 0.2, 0.32, 0.72), "tail": "long", "whiskers": True},
    "fox": {"ears": (0.66, 0.22, 0.22, 0.6), "tail": "bushy", "muzzle": 1.3},
    # Starter Studio's fourth (creative-design/CHARACTERS.md).
    "sheep": {"form": build_sheep},
    "turtle": {"form": build_turtle},
    "robot": {"form": build_relay},
    # Ink & Geek's first characters, then Pocket Anime's.
    "raccoon": {"form": build_raccoon},
    "squid": {"form": build_squid},
    "crt": {"form": build_crt},
    "courier": {"form": build_courier},
    "archivist": {"form": build_archivist},
    "dragon": {"form": build_dragon},
    # Studio Collection (creative-design/PROFESSIONAL-COLLECTION.md).
    "penguin": {"form": build_penguin},
    "capsule": {"form": build_capsule},
    "owl": {"form": build_owl},
    "bird": {"form": build_bird},
    "orbit": {"form": build_orbit},
    "vale": {"ears": (0.6, 0.22, 0.24, 0.6), "tail": "curl", "muzzle": 1.25, "band": True, "calm": True},
}


def build_parts(spec):
    body, face = [], []
    side = (-1, 1)

    # Head and body.
    body.append(ellipsoid(HEAD.c, HEAD.r, COAT, "head", segments=(40, 28)))
    body.append(ellipsoid(BODY.c, BODY.r, COAT, "chest", segments=(32, 22), shape=bean))
    face.append(decal(BODY, 0, 0.47, (0.21, 0.26, 0.035), CREAM, "chest", lift=-0.022))

    # Scarf: ribbed ring at the neck and one end hanging at the front, viewer's right. Vale wears
    # only a thin band.
    if spec.get("band"):
        body.append(torus((0, 0.9, 0.0), 0.3, 0.035, SCARF, "chest", segments=(48, 8)))
    else:
        body.append(torus((0, 0.88, 0.0), 0.3, 0.075, SCARF, "chest", segments=(48, 12), ribs=18))
        tail_end = ellipsoid((0.19, 0.68, 0.27), (0.075, 0.16, 0.03), SCARF, "chest", rotation=Euler((0.3, 0, 0.12)).to_matrix(),
                             shape=boxy)
        body.append(tail_end)
        for k in range(3):  # knit ribs across the hanging end
            face.append(ellipsoid((0.19 + 0.02 * k, 0.6 + 0.07 * k, 0.305 - 0.02 * k), (0.07, 0.008, 0.012), SCARF_DARK, "chest",
                                  rotation=Euler((0.3, 0, 0.12)).to_matrix(), segments=(12, 6)))

    # Arms with charcoal paws, angled out and down from the shoulders.
    for s in side:
        bone = "armL" if s < 0 else "armR"
        shoulder = Vector((0.29 * s, 0.74, 0.02))
        paw = Vector((0.5 * s, 0.49, 0.07))
        axis = (paw - shoulder).normalized()
        turn = Vector((0, -1, 0)).rotation_difference(axis).to_matrix()
        body.append(ellipsoid((shoulder + paw) / 2, (0.095, 0.2, 0.095), COAT, bone, rotation=turn, segments=(20, 14)))
        body.append(ellipsoid(paw, (0.105, 0.1, 0.105), POINTS, bone, segments=(20, 14)))

    # Short legs and charcoal feet.
    for s in side:
        bone = "legL" if s < 0 else "legR"
        body.append(ellipsoid((0.16 * s, 0.21, 0.0), (0.12, 0.12, 0.12), COAT, bone, segments=(18, 12)))
        body.append(ellipsoid((0.17 * s, 0.085, 0.05), (0.15, 0.085, 0.2), POINTS, bone, segments=(24, 14)))

    if spec["tail"] == "puff":
        body.append(ellipsoid((0, 0.4, -0.33), (0.12, 0.12, 0.12), POINTS, "tail", segments=(18, 12)))
    elif spec["tail"] == "curl":
        # A broad tail curled up beside the body, cream at the tip.
        for k, (c, r) in enumerate([((0.18, 0.36, -0.34), 0.2), ((0.36, 0.52, -0.3), 0.22), ((0.44, 0.76, -0.24), 0.2), ((0.38, 0.96, -0.18), 0.15)]):
            body.append(ellipsoid(c, (r, r * 0.9, r * 0.85), CREAM if k == 3 else COAT, "tail", segments=(20, 12)))
    else:
        body.extend(long_tail() if spec["tail"] == "long" else bushy_tail())

    for s in side:
        outer, inner = ear(s) if spec["ears"] == "long" else pointed_ear(s, *spec["ears"])
        body.append(outer)
        face.append(inner)

    # Face, sitting on the head surface.
    m = spec.get("muzzle", 1.0)
    face.append(decal(HEAD, 0, 1.16, (0.25 * m, 0.16 * m, 0.05), CREAM, "head", lift=-0.03))
    if spec.get("whiskers"):
        for s in side:
            for k in (-1, 0, 1):
                face.append(decal(HEAD, 0.53 * s, 1.17 + 0.045 * k, (0.085, 0.009, 0.012), INK, "head", lift=0.0, spin=0.12 * k * s,
                                  segments=(12, 6)))
    for s in side:
        eye = "eyeL" if s < 0 else "eyeR"
        face.append(decal(HEAD, 0.25 * s, 1.33, (0.1, 0.125, 0.05), INK, eye, lift=-0.012))
        face.append(decal(HEAD, 0.25 * s - 0.035, 1.375, (0.032, 0.036, 0.02), WHITE, eye, lift=0.03, segments=(12, 8)))
        face.append(decal(HEAD, 0.25 * s + 0.035, 1.29, (0.014, 0.014, 0.01), WHITE, eye, lift=0.03, segments=(10, 6)))
        # Brows: short arcs centered on the top of their circle.
        # Work-friendly characters (Vale) skip brows and blush.
        if not spec.get("calm"):
            face.append(arc_decal(HEAD, 0.24 * s, 1.5, 0.05, 0.011, INK, "head", arc=math.pi * 0.55, spin=math.pi * 0.775))
            face.append(decal(HEAD, 0.43 * s, 1.19, (0.095, 0.055, 0.02), BLUSH, "head", lift=-0.004, segments=(16, 10)))
        # Mouth: two small smiles side by side, sitting on the muzzle patch.
        face.append(arc_decal(HEAD, 0.035 * s, 1.17, 0.034, 0.0095, INK, "head", arc=math.pi, spin=0, lift=0.022))
    face.append(decal(HEAD, 0, 1.215, (0.045, 0.032, 0.03), NOSE, "head", lift=0.0, segments=(14, 8)))
    return body, face


# ---------------------------------------------------------------------------------------------
# Blender scene.


def to_blender(v):
    return Vector((v.x, -v.z, v.y))


def build_armature():
    data = bpy.data.armatures.new("HeroRig")
    rig = bpy.data.objects.new("Hero", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (parent, at) in JOINTS.items():
        bone = data.edit_bones.new(name)
        bone.head = to_blender(Vector(at))
        bone.tail = bone.head + Vector((0, 0, 0.12))
        bone.roll = 0
        if parent:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def build_mesh(name, parts, rig):
    verts, faces, colors, weights = [], [], [], []
    for part in parts:
        offset = len(verts)
        verts.extend(to_blender(v) for v in part.verts)
        faces.extend([i + offset for i in f] for f in part.faces)
        colors.extend(part.colors)
        weights.extend(part.weights)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    attribute = mesh.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    attribute.data.foreach_set("color", [c for rgba in colors for c in rgba])
    mesh.color_attributes.active_color = attribute
    mesh.validate()

    material = bpy.data.materials.new(name + "Toon")
    mesh.materials.append(material)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    groups = {bone: obj.vertex_groups.new(name=bone) for bone in JOINTS}
    for i, w in enumerate(weights):
        for bone, value in w.items():
            groups[bone].add([i], value, "REPLACE")
    return obj


# ---------------------------------------------------------------------------------------------
# Clips: functions of the loop phase p in [0, 1). Rotations are app-space Euler 'XYZ'
# (three.js order) under "r" or a quaternion under "q"; offsets ("p") are added to the rest
# position; scales ("s") multiply.

TAU = math.tau


def wave(p, offset=0.0):
    return math.sin(TAU * p + offset)


def breathe(p, depth):
    return (1, 1 + depth * (0.5 + 0.5 * wave(p)), 1)


def idle_ears(p, base=0.08):
    return {
        "earL": {"r": (0, 0, base + 0.05 * wave(p, 0.6))},
        "earR": {"r": (0, 0, -base - 0.05 * wave(p, 1.1))},
        "earLTip": {"r": (0.04 * wave(p, 1.4), 0, 0.06 * wave(p, 1.6))},
        "earRTip": {"r": (0.04 * wave(p, 1.9), 0, -0.06 * wave(p, 2.1))},
    }


def sitting(p):
    return {
        "hips": {"p": (0, -0.13, 0)},
        "legL": {"r": (-1.3, 0, -0.18)},
        "legR": {"r": (-1.3, 0, 0.18)},
        "chest": {"s": breathe(p, 0.025)},
        "armL": {"r": (-0.45, 0, -0.05)},
        "armR": {"r": (-0.45, 0, 0.05)},
    }


ARM_REST = {-1: Vector((-0.21, -0.25, 0.05)), 1: Vector((0.21, -0.25, 0.05))}  # shoulder to paw


def aim_arm(side, target):
    """Quaternion that points an arm from its shoulder at an app-space target."""
    shoulder = Vector((0.29 * side, 0.74, 0.02))
    return ARM_REST[side].rotation_difference(Vector(target) - shoulder)


def merge(*poses):
    out = {}
    for pose in poses:
        out.update(pose)
    return out


CLIPS = {
    "idle": (3.0, lambda p: merge(idle_ears(p), {
        "chest": {"s": breathe(p, 0.025)},
        "head": {"r": (0.02 * wave(p), 0, 0.03 * wave(p, 1))},
        "armL": {"r": (0, 0, -0.08 - 0.03 * wave(p))},
        "armR": {"r": (0, 0, 0.08 + 0.03 * wave(p))},
        "tail": {"r": (0, 0.2 * wave(p), 0)},
    })),
    "walk": (0.7, lambda p: {
        "hips": {"p": (0, 0.035 * (1 - math.cos(2 * TAU * p)), 0)},
        "chest": {"r": (0.06, 0, 0.05 * wave(p))},
        "head": {"r": (-0.04, 0, -0.04 * wave(p))},
        "legL": {"r": (0.55 * wave(p), 0, 0)},
        "legR": {"r": (-0.55 * wave(p), 0, 0)},
        "armL": {"r": (-0.5 * wave(p), 0, -0.15)},
        "armR": {"r": (0.5 * wave(p), 0, 0.15)},
        "earL": {"r": (-0.2, 0, 0.12 + 0.08 * wave(2 * p, 0.8))},
        "earR": {"r": (-0.2, 0, -0.12 - 0.08 * wave(2 * p, 1.2))},
        "earLTip": {"r": (-0.15 + 0.1 * wave(2 * p, 0.2), 0, 0.08 * wave(2 * p, 0.4))},
        "earRTip": {"r": (-0.15 + 0.1 * wave(2 * p, 0.6), 0, -0.08 * wave(2 * p, 0.8))},
        "tail": {"r": (0, 0.3 * wave(p), 0)},
    }),
    "sit": (3.0, lambda p: merge(sitting(p), idle_ears(p), {"head": {"r": (0.04 * wave(p), 0, 0.05)}})),
    "sleep": (4.0, lambda p: merge(sitting(p), {
        "chest": {"s": breathe(p, 0.045)},
        "head": {"r": (0.38 + 0.03 * wave(p), 0, 0.14)},
        # Ears folded back over the head.
        "earL": {"r": (-1.0, 0, 0.25)},
        "earR": {"r": (-1.0, 0, -0.25)},
        "earLTip": {"r": (-0.6, 0, 0.1)},
        "earRTip": {"r": (-0.6, 0, -0.1)},
        "armL": {"r": (-0.3, 0, -0.02)},
        "armR": {"r": (-0.3, 0, 0.02)},
    })),
    "wave": (1.1, lambda p: merge(idle_ears(p), {
        "chest": {"s": breathe(p, 0.02)},
        "head": {"r": (0, 0, -0.1)},
        "armR": {"r": (0, 0, 2.5 + 0.35 * wave(2 * p))},
        "armL": {"r": (0, 0, -0.1)},
        "hips": {"p": (0, 0.02 * abs(wave(p)), 0)},
    })),
    "think": (2.4, lambda p: {
        "chest": {"s": breathe(p, 0.02)},
        "head": {"r": (-0.14, 0, 0.16 + 0.04 * wave(p))},
        "armR": {"q": aim_arm(1, (0.12, 1.0, 0.45))},  # paw on the chin
        "armL": {"r": (-0.3, 0, -0.15)},
        "earL": {"r": (0, 0, 0.15 + 0.04 * wave(p))},
        "earR": {"r": (0, 0, -0.25)},
        "earRTip": {"r": (0.2, 0, -0.9)},  # one ear bent over, as in the pose sheet
        "tail": {"r": (0, 0.25 * wave(p), 0)},
    }),
    "read": (2.0, lambda p: merge(idle_ears(p, 0.12), {
        "chest": {"s": breathe(p, 0.02), "r": (0.05, 0, 0)},
        "head": {"r": (0.22, 0.18 * wave(p), 0)},
        "armL": {"r": (-1.0, 0, -0.42)},
        "armR": {"r": (-1.0, 0, 0.42)},
    })),
    "work": (0.5, lambda p: {
        "chest": {"r": (0.1, 0, 0)},
        "head": {"r": (0.16, 0, 0.03 * wave(p))},
        "armL": {"r": (-0.95 + 0.14 * wave(p), 0, -0.3)},
        "armR": {"r": (-0.95 - 0.14 * wave(p), 0, 0.3)},
        "earL": {"r": (-0.1, 0, 0.1 + 0.05 * wave(2 * p))},
        "earR": {"r": (-0.1, 0, -0.1 - 0.05 * wave(2 * p))},
    }),
    "celebrate": (0.7, lambda p: (lambda jump: {
        "hips": {"p": (0, 0.3 * jump, 0)},
        "armL": {"r": (0, 0, -2.6 - 0.25 * wave(2 * p))},
        "armR": {"r": (0, 0, 2.6 + 0.25 * wave(2 * p))},
        "legL": {"r": (0.45 * jump, 0, -0.1)},
        "legR": {"r": (0.45 * jump, 0, 0.1)},
        "earL": {"r": (0.3 * jump, 0, 0.3)},
        "earR": {"r": (0.3 * jump, 0, -0.3)},
        "earLTip": {"r": (0.4 * jump, 0, 0.3)},
        "earRTip": {"r": (0.4 * jump, 0, -0.3)},
        "head": {"r": (-0.12, 0, 0)},
    })(max(0.0, wave(p)))),
    "alert": (0.6, lambda p: {
        "hips": {"p": (0, 0.07 * abs(wave(p)), 0)},
        # Out to the side at shoulder height; the app's sign prop sits in this paw.
        "armR": {"r": (0, 0, 1.6 + 0.08 * wave(p))},
        "armL": {"r": (0, 0, -0.35 - 0.25 * wave(p))},
        "head": {"r": (-0.08, 0, 0.06)},
        "earL": {"r": (-0.15, 0, 0.04)},
        "earR": {"r": (-0.15, 0, -0.04)},
    }),
    "sad": (2.6, lambda p: {
        "chest": {"s": breathe(p, 0.03), "r": (0.12, 0, 0)},
        "head": {"r": (0.32, 0, 0.06 * wave(p))},
        # Lop ears: out to the sides, tips hanging down.
        "earL": {"r": (0.35, 0, 1.75)},
        "earR": {"r": (0.35, 0, -1.75)},
        "earLTip": {"r": (0.2, 0, 0.9)},
        "earRTip": {"r": (0.2, 0, -0.9)},
        "armL": {"r": (0, 0, 0.12)},
        "armR": {"r": (0, 0, -0.12)},
    }),
    "dangle": (1.6, lambda p: {
        "legL": {"r": (0.3 * wave(p), 0, -0.12)},
        "legR": {"r": (0.3 * wave(p, 0.7), 0, 0.12)},
        "armL": {"r": (0, 0, -1.3 - 0.25 * wave(p))},
        "armR": {"r": (0, 0, 1.3 + 0.25 * wave(p, 0.5))},
        "head": {"r": (0.05, 0, 0.08 * wave(p, 1))},
        "earL": {"r": (-0.2, 0, -0.1)},
        "earR": {"r": (-0.2, 0, 0.1)},
        "earLTip": {"r": (0.15 * wave(p, 0.5), 0, -0.1)},
        "earRTip": {"r": (0.15 * wave(p, 1.0), 0, 0.1)},
        "tail": {"r": (0, 0.4 * wave(p), 0)},
    }),
    "fall": (0.4, lambda p: {
        "armL": {"r": (0, 0, -2.1 - 0.3 * wave(p))},
        "armR": {"r": (0, 0, 2.1 + 0.3 * wave(p))},
        "legL": {"r": (-0.3, 0, -0.3)},
        "legR": {"r": (-0.3, 0, 0.3)},
        "earL": {"r": (0.5, 0, -0.2)},
        "earR": {"r": (0.5, 0, 0.2)},
        "earLTip": {"r": (0.4, 0, -0.2)},
        "earRTip": {"r": (0.4, 0, 0.2)},
    }),
}


def build_actions(rig):
    rig.animation_data_create()
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    for name, (seconds, pose) in CLIPS.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        frames = max(8, round(seconds * FPS))
        for frame in range(frames + 1):
            keys = pose((frame % frames) / frames)
            # Every clip keys every bone so crossfades never leave a bone behind.
            for bone in rig.pose.bones:
                key = keys.get(bone.name, {})
                if "q" in key:
                    bone.rotation_quaternion = key["q"]
                else:
                    rx, ry, rz = key.get("r", (0, 0, 0))
                    bone.rotation_quaternion = Euler((rx, ry, rz), "ZYX").to_quaternion()
                bone.location = key.get("p", (0, 0, 0))
                bone.scale = key.get("s", (1, 1, 1))
                for path in ("rotation_quaternion", "location", "scale"):
                    bone.keyframe_insert(path, frame=frame + 1, group=bone.name)
        # Keep animation curves as sampled; no easing between samples.
        for curve in all_fcurves(action):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_quaternion = Quaternion()
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def all_fcurves(action):
    """F-curves of a slotted (Blender 4.4+) or legacy action."""
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    else:
        yield from action.fcurves


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    # Actions outlive their objects; left over, they would export again under ".001" names.
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for armature in list(bpy.data.armatures):
        bpy.data.armatures.remove(armature)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


def build(name, spec):
    reset()
    bpy.context.scene.render.fps = FPS
    rig = build_armature()
    body, face = spec.get("form", build_parts)(spec)
    build_mesh("Body", body, rig)
    build_mesh("Face", face, rig)
    build_actions(rig)

    glb = os.path.join(MODELS, f"{name}.glb")
    os.makedirs(MODELS, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=glb,
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_vertex_color="ACTIVE",
        export_materials="EXPORT",
        export_morph=False,
    )
    triangles = sum(len(f) - 2 for p in body + face for f in p.faces)
    print(f"{name}: {sum(len(p.verts) for p in body + face)} vertices, {triangles} triangles, {len(CLIPS)} clips -> {glb}")


def main():
    # The bunny goes last: its scene is the one saved for an artist to open.
    for name in sorted(SPECIES, key=lambda n: n == "hero"):
        build(name, SPECIES[name])
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)


main()
