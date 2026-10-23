"""Builds the Sidefolk hero (mesh, colors, rig, clips) and exports public/models/hero.glb.

    npm run model
    # = blender --background --factory-startup --python art/blender/build_hero.py

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
GLB = os.path.join(ROOT, "public", "models", "hero.glb")
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


def unit_sphere(u=32, v=20):
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
    n, m = segments
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


def build_parts():
    body, face = [], []
    side = (-1, 1)

    # Head and body.
    body.append(ellipsoid(HEAD.c, HEAD.r, COAT, "head", segments=(40, 28)))
    body.append(ellipsoid(BODY.c, BODY.r, COAT, "chest", segments=(32, 22), shape=bean))
    face.append(decal(BODY, 0, 0.47, (0.21, 0.26, 0.035), CREAM, "chest", lift=-0.022))

    # Scarf: ribbed ring at the neck and one end hanging at the front, viewer's right.
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

    body.append(ellipsoid((0, 0.4, -0.33), (0.12, 0.12, 0.12), POINTS, "tail", segments=(18, 12)))

    for s in side:
        outer, inner = ear(s)
        body.append(outer)
        face.append(inner)

    # Face, sitting on the head surface.
    face.append(decal(HEAD, 0, 1.16, (0.25, 0.16, 0.05), CREAM, "head", lift=-0.03))
    for s in side:
        eye = "eyeL" if s < 0 else "eyeR"
        face.append(decal(HEAD, 0.25 * s, 1.33, (0.1, 0.125, 0.05), INK, eye, lift=-0.012))
        face.append(decal(HEAD, 0.25 * s - 0.035, 1.375, (0.032, 0.036, 0.02), WHITE, eye, lift=0.03, segments=(12, 8)))
        face.append(decal(HEAD, 0.25 * s + 0.035, 1.29, (0.014, 0.014, 0.01), WHITE, eye, lift=0.03, segments=(10, 6)))
        # Brows: short arcs centered on the top of their circle.
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


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    bpy.context.scene.render.fps = FPS

    rig = build_armature()
    body, face = build_parts()
    build_mesh("Body", body, rig)
    build_mesh("Face", face, rig)
    build_actions(rig)

    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=GLB,
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
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print(f"hero: {sum(len(p.verts) for p in body + face)} vertices, {len(CLIPS)} clips -> {GLB}")


main()
