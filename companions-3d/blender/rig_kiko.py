# Kiko's rig: a chibi kid in a padded spacesuit with a backpack.
# blender -b -P rig_kiko.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe.py: the neck is narrowest at z 0.15 (the head with its hair runs
# up to 0.95), arms leave the shoulders past |x| ≈ 0.25 and slope down to gloves at |x| 0.5–0.7,
# z -0.03…-0.3; the legs part below z -0.5, knees near -0.72, boots below -0.75.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, limb, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Kiko", ratio=0.07)

B = [("root", (0, 0, -0.952), (0, 0, -0.85), None, {"deform": False}),
     ("hips", (0, 0, -0.5), (0, 0, -0.36), "root"),
     ("spine", (0, 0, -0.36), (0, 0, -0.18), "hips", {"connect": True}),
     ("chest", (0, 0, -0.18), (0, 0, 0.12), "spine", {"connect": True}),
     ("head", (0, 0, 0.12), (0, 0, 0.9), "chest", {"connect": True}),
     ("face", (0, -0.35, 0.33), (0, -0.45, 0.33), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.22 * sx, 0, -0.08), (0.5 * sx, 0, -0.2), (0.68 * sx, -0.01, -0.27))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.16 * sx, 0, -0.48), (0.18 * sx, 0, -0.76), "hips"),
          (f"foot.{s}", (0.18 * sx, 0, -0.76), (0.2 * sx, -0.18, -0.93), f"thigh.{s}", {"connect": True})]
rig = armature("KikoRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one.
head = ss(0.1, 0.17, z)
arm = np.zeros(len(co)); arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.11, 0.15)
    on = np.sign(x) == sx
    arm = np.where(on, w * ss(0.21, 0.27, ax), arm); arm_t = np.where(on, t, arm_t)
# The backpack and its straps stay on the back: an arm that grabbed them would tear the pack.
arm *= (1 - head) * (1 - ss(0.1, 0.16, y))
leg = (1 - ss(-0.54, -0.46, z)) * (1 - head - arm)
foot = 1 - ss(-0.8, -0.72, z)
core = 1 - head - arm - leg
chest = ss(-0.24, -0.14, z)
spine = ss(-0.42, -0.32, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.58, 0.7, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W)
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -80), "hand.R": (0, 0, -30), "head": (0, 10, 0)}),
    ("bow_side.png", 90, {"spine": (30, 0, 0), "chest": (15, 0, 0), "head": (10, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (80, 0, 0), "thigh.R": (80, 0, 0), "foot.L": (-75, 0, 0), "foot.R": (-75, 0, 0)}),
])
