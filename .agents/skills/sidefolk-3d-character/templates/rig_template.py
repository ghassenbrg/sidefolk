# <Name>'s rig: <one line on the body>.
# blender -b -P rig_<id>.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head [› ear.{L,R}.{1,2}];  chest › arm.{L,R} › hand.{L,R};
#   hips › thigh.{L,R} › foot.{L,R} [› tail.1 › tail.2 › tail.3]
# Numbers from measure.py / probe.py (Z up, facing -Y, its left +X): <neck height, where the arms
# leave the torso, hips, feet, ears/tail axes, anything turned or shifted>.
#
# Template from the sidefolk-3d-character skill: replace every number with what you measured, drop
# the parts this body doesn't have (and their bones), add chains it does have.
import sys, os
sys.path.insert(0, os.path.join(os.getcwd(), "companions-3d", "blender"))
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, limb, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
# ratio: aim at about 70k faces. shift: move an off-centre body back to x = 0. turn: 180 when Meshy
# faced it backwards.
mesh = prepare(src, "Name", ratio=0.35, shift=(0, 0, 0), turn=0)

FLOOR, NECK, HIPS = -0.952, -0.12, -0.6          # z of the soles, the neck, the hip joints
B = [("root", (0, 0, FLOOR), (0, 0, FLOOR + 0.1), None, {"deform": False}),
     ("hips", (0, 0, HIPS - 0.15), (0, 0, HIPS + 0.15), "root"),
     ("spine", (0, 0, HIPS + 0.15), (0, 0, (HIPS + NECK) / 2 + 0.1), "hips", {"connect": True}),
     ("chest", (0, 0, (HIPS + NECK) / 2 + 0.1), (0, 0, NECK), "spine", {"connect": True}),
     ("head", (0, 0, NECK), (0, 0, 0.62), "chest", {"connect": True}),
     # Non-deforming socket for the face pieces; put it in front of the face.
     ("face", (0, -0.5, 0.2), (0, -0.6, 0.2), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    # Shoulder (where the arm leaves the torso), elbow-ish, paw tip.
    ARM[s] = ((0.22 * sx, 0, -0.2), (0.45 * sx, 0, -0.3), (0.62 * sx, 0, -0.36))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.15 * sx, 0, HIPS - 0.1), (0.15 * sx, 0, FLOOR + 0.12), "hips"),
          (f"foot.{s}", (0.15 * sx, 0, FLOOR + 0.12), (0.15 * sx, -0.15, FLOOR + 0.02), f"thigh.{s}", {"connect": True})]
rig = armature("NameRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one.
head = ss(NECK - 0.04, NECK + 0.03, z)
arm = np.zeros(len(co)); arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.1, 0.15)          # full within 0.1 of the arm's line
    on = np.sign(x) == sx
    arm = np.where(on, w * ss(0.19, 0.25, ax), arm); arm_t = np.where(on, t, arm_t)
arm *= 1 - head
leg = (1 - ss(HIPS - 0.12, HIPS - 0.05, z)) * (1 - head - arm)
foot = 1 - ss(FLOOR + 0.1, FLOOR + 0.15, z)
core = 1 - head - arm - leg
chest = ss(HIPS + 0.2, HIPS + 0.3, z)
spine = ss(HIPS - 0.02, HIPS + 0.08, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.55, 0.7, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W)
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("bow_side.png", 90, {"spine": (30, 0, 0), "chest": (15, 0, 0), "head": (10, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (80, 0, 0), "thigh.R": (80, 0, 0), "foot.L": (-75, 0, 0), "foot.R": (-75, 0, 0)}),
])
