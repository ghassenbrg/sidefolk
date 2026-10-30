# Purl's rig: a stitched-linen ragdoll: a huge soft square head on a small pear-shaped body.
# blender -b -P rig_purl.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe (Z up, facing -Y, its left +X; Meshy centred it, no shift): the head
# is a rounded cube from z -0.1 to 0.95 (±0.61 wide, ±0.53 deep, its flat face at y -0.53, centred
# near z 0.42); the neck is at z -0.12; the arms leave the torso at |x| 0.38 near z -0.2 and reach out
# almost level to tips at (±0.79, -0.34); the body ends at z -0.76 over two stub legs centred at |x| 0.19.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, limb, prepare, regutter, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Purl", ratio=0.33)
regutter(mesh)   # the texture's islands touch: seams would show as pale cracks when it is shrunk

FLOOR, NECK, HIPS = -0.952, -0.12, -0.6
B = [("root", (0, 0, FLOOR), (0, 0, FLOOR + 0.1), None, {"deform": False}),
     ("hips", (0, 0, HIPS - 0.1), (0, 0, HIPS + 0.12), "root"),
     ("spine", (0, 0, HIPS + 0.12), (0, 0, -0.32), "hips", {"connect": True}),
     ("chest", (0, 0, -0.32), (0, 0, NECK), "spine", {"connect": True}),
     ("head", (0, 0, NECK), (0, 0, 0.95), "chest", {"connect": True}),
     ("face", (0, -0.53, 0.42), (0, -0.63, 0.42), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.37 * sx, 0, -0.21), (0.58 * sx, 0, -0.27), (0.79 * sx, 0, -0.34))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.19 * sx, 0, -0.7), (0.19 * sx, 0, FLOOR + 0.12), "hips"),
          (f"foot.{s}", (0.19 * sx, 0, FLOOR + 0.12), (0.19 * sx, -0.13, FLOOR + 0.02), f"thigh.{s}", {"connect": True})]
rig = armature("PurlRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one.
# The head's rounded corners start at z 0 out past |x| 0.5: the mitten tips, which curl up to
# z -0.12 out there, stay the arms'.
head = ss(NECK - 0.04, NECK + 0.03, z) * (1 - ss(0.46, 0.52, ax) * (1 - ss(-0.07, -0.02, z)))
# The arms are everything out past the body's sides under the head (the mitten tips curl up off
# the arm's line, so a distance from it would leave them behind).
arm = ss(0.35, 0.42, ax) * (1 - ss(-0.1, -0.04, z))
arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    t, _ = seg_param(co, ARM[s][0], ARM[s][2])
    arm_t = np.where(np.sign(x) == sx, t, arm_t)
arm *= 1 - head
leg = (1 - ss(-0.8, -0.73, z)) * (1 - head - arm)
foot = 1 - ss(-0.92, -0.87, z)
core = 1 - head - arm - leg
chest = ss(-0.42, -0.28, z)
spine = ss(HIPS - 0.06, HIPS + 0.08, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.5, 0.66, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W)
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 40, 0), "hand.R": (0, 20, 0), "head": (0, 12, 0)}),
    ("side.png", 90, {"spine": (15, 0, 0), "chest": (10, 0, 0), "head": (12, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (75, 0, 0), "thigh.R": (75, 0, 0), "foot.L": (-70, 0, 0), "foot.R": (-70, 0, 0)}),
])
