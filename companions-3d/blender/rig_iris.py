# Iris's rig: a toy camera: one soft rounded-square body with a big lens, two brown stub arms, two feet.
# blender -b -P rig_iris.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe (Z up, facing -Y, its left +X; Meshy centred it, no shift): the body
# is ±0.72 wide, ±0.33 deep and runs from z -0.59 to 0.76 (the shutter button above, to 0.86); the
# lens ring (outer radius 0.455, glass 0.3) is centred at (0, 0.106) and stands out to y -0.36; the
# arms leave the sides past |x| 0.72 at z ≈ 0.03 and hang to tips near (±0.9, -0.5); the legs are
# stumps below z -0.6, feet centred at |x| 0.28.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, regutter, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Iris", ratio=0.26)
regutter(mesh)   # the texture's islands touch: seams would show as pale cracks when it is shrunk

FLOOR = -0.858
B = [("root", (0, 0, FLOOR), (0, 0, FLOOR + 0.1), None, {"deform": False}),
     ("hips", (0, 0, -0.6), (0, 0, -0.3), "root"),
     ("spine", (0, 0, -0.3), (0, 0, 0.0), "hips", {"connect": True}),
     ("chest", (0, 0, 0.0), (0, 0, 0.3), "spine", {"connect": True}),
     ("head", (0, 0, 0.3), (0, 0, 0.8), "chest", {"connect": True}),
     ("face", (0, -0.36, 0.106), (0, -0.46, 0.106), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.72 * sx, 0, 0.02), (0.86 * sx, 0, -0.22), (0.9 * sx, 0, -0.5))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.28 * sx, 0, -0.58), (0.28 * sx, 0, -0.72), "hips"),
          (f"foot.{s}", (0.28 * sx, 0, -0.72), (0.28 * sx, -0.12, FLOOR + 0.02), f"thigh.{s}", {"connect": True})]
rig = armature("IrisRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one. The body is one
# soft block: wide overlapping bands, so a nod or a lean bends all of it a little.
arm = ss(0.725, 0.765, ax) * ss(-0.62, -0.56, z) * (1 - ss(0.07, 0.13, z))
leg = (1 - ss(-0.65, -0.6, z)) * (1 - arm)
foot = 1 - ss(-0.8, -0.74, z)
core = 1 - arm - leg
head = ss(0.0, 0.45, z)
chest = ss(-0.35, 0.0, z) * (1 - head)
spine = ss(-0.6, -0.3, z) * (1 - head - chest)
add("head", core * head); add("chest", core * chest); add("spine", core * spine)
add("hips", core * (1 - head - chest - spine))
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    t, _ = seg_param(co, ARM[s][0], ARM[s][2])
    hand = ss(0.5, 0.7, t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W, smooth=(0.5, 1))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 70, 0), "hand.R": (0, 30, 0), "head": (0, 10, 0)}),
    ("side.png", 90, {"spine": (15, 0, 0), "head": (10, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (70, 0, 0), "thigh.R": (70, 0, 0), "foot.L": (-65, 0, 0), "foot.R": (-65, 0, 0)}),
], scale=2.4)
