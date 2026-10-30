# Rune's rig: a pocket golem of stones: a big blocky boulder head over a small barrel torso, egg-shaped
# pebble arms pressed to its sides and pebble feet.
# blender -b -P rig_rune.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe (Z up, facing -Y, its left +X; Meshy centred it, no shift): the head
# is a block from z -0.12 to 0.95 (±0.66 wide at z 0.1, narrowing to ±0.53 near the top, ±0.56 deep,
# its flat face at y -0.56, moss on the top left at (-0.3, 0.87)); the neck is at z -0.15; the torso is
# ±0.36 wide from z -0.15 to -0.72 with the amber gem at (0, -0.33) on its front; the arms are eggs
# fused to its sides at the crease |x| 0.36, from z -0.17 to tips near (±0.55, -0.68); the legs are
# pebbles below z -0.74 centred at |x| 0.24.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, regutter, limb, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
# 1.46M faces of stone relief: far more than a desktop companion needs.
mesh = prepare(src, "Rune", ratio=0.05)
regutter(mesh)   # the texture's islands touch: seams would show as pale cracks when it is shrunk

FLOOR, NECK, HIPS = -0.952, -0.14, -0.6
B = [("root", (0, 0, FLOOR), (0, 0, FLOOR + 0.1), None, {"deform": False}),
     ("hips", (0, 0, HIPS - 0.1), (0, 0, HIPS + 0.12), "root"),
     ("spine", (0, 0, HIPS + 0.12), (0, 0, -0.3), "hips", {"connect": True}),
     ("chest", (0, 0, -0.3), (0, 0, NECK), "spine", {"connect": True}),
     ("head", (0, 0, NECK), (0, 0, 0.95), "chest", {"connect": True}),
     ("face", (0, -0.56, 0.38), (0, -0.66, 0.38), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.42 * sx, 0, -0.19), (0.5 * sx, 0, -0.43), (0.56 * sx, 0, -0.68))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.24 * sx, 0, -0.7), (0.24 * sx, 0, FLOOR + 0.12), "hips"),
          (f"foot.{s}", (0.24 * sx, 0, FLOOR + 0.12), (0.24 * sx, -0.13, FLOOR + 0.02), f"thigh.{s}", {"connect": True})]
rig = armature("RuneRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one. The arms are whole
# stones: outside the crease and near their line, they stay rigid.
head = ss(NECK - 0.02, NECK + 0.03, z)
arm = np.zeros(len(co)); arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.17, 0.24)
    on = np.sign(x) == sx
    arm = np.where(on, w * ss(0.34, 0.39, ax), arm); arm_t = np.where(on, t, arm_t)
# The arm stones end at z -0.7, just above the feet: below that nothing goes with them.
arm *= (1 - head) * ss(-0.77, -0.71, z)
leg = (1 - ss(-0.78, -0.72, z)) * (1 - head - arm)
foot = 1 - ss(-0.92, -0.87, z)
core = 1 - head - arm - leg
chest = ss(-0.45, -0.3, z)
spine = ss(HIPS - 0.08, HIPS + 0.06, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.55, 0.75, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W, smooth=(0.5, 1))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 70, 0), "hand.R": (0, 20, 0), "head": (0, 12, 0)}),
    ("side.png", 90, {"spine": (12, 0, 0), "chest": (8, 0, 0), "head": (12, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (75, 0, 0), "thigh.R": (75, 0, 0), "foot.L": (-70, 0, 0), "foot.R": (-70, 0, 0)}),
])
