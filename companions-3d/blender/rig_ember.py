# Ember's rig: a chibi fox standing on its hind legs, with big ears and a big fluffy tail.
# blender -b -P rig_ember.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head › ear.{L,R}.{1,2}
#   chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R};  hips › tail.1 › tail.2 › tail.3
# Numbers from measure.py / probe.py, after moving the body back to x = 0 (Meshy centred the
# bounding box, which the tail on the fox's right pushes 0.094 off): the neck is at z -0.12, the
# arms stand out sideways at z ≈ -0.22 to paws at |x| 0.44–0.65, the legs are short (z < -0.78),
# and the tail rises from behind the hips on the right (-x) to a cream tip near z 0.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, limb, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
# 4.4M faces of fur: a desktop companion needs a fraction of that.
mesh = prepare(src, "Ember", ratio=0.018, shift=(-0.094, 0, 0))

TAIL = [(-0.12, 0.2, -0.62), (-0.42, 0.36, -0.62), (-0.65, 0.4, -0.38), (-0.58, 0.3, -0.02)]
B = [("root", (0, 0, -0.952), (0, 0, -0.85), None, {"deform": False}),
     ("hips", (0, 0, -0.78), (0, 0, -0.6), "root"),
     ("spine", (0, 0, -0.6), (0, 0, -0.4), "hips", {"connect": True}),
     ("chest", (0, 0, -0.4), (0, 0, -0.14), "spine", {"connect": True}),
     ("head", (0, -0.05, -0.14), (0, -0.05, 0.62), "chest", {"connect": True}),
     ("tail.1", TAIL[0], TAIL[1], "hips"),
     ("tail.2", TAIL[1], TAIL[2], "tail.1", {"connect": True}),
     ("tail.3", TAIL[2], TAIL[3], "tail.2", {"connect": True}),
     ("face", (0, -0.55, 0.2), (0, -0.65, 0.2), "head", {"deform": False})]
ARM, EAR = {}, {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.2 * sx, -0.1, -0.21), (0.44 * sx, -0.13, -0.24), (0.64 * sx, -0.15, -0.24))
    EAR[s] = ((0.24 * sx, -0.06, 0.55), (0.32 * sx, -0.08, 0.76), (0.39 * sx, -0.1, 0.95))
    B += [(f"ear.{s}.1", EAR[s][0], EAR[s][1], "head"),
          (f"ear.{s}.2", EAR[s][1], EAR[s][2], f"ear.{s}.1", {"connect": True}),
          (f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.15 * sx, -0.05, -0.74), (0.15 * sx, -0.05, -0.87), "hips"),
          (f"foot.{s}", (0.15 * sx, -0.05, -0.87), (0.15 * sx, -0.2, -0.94), f"thigh.{s}", {"connect": True})]
rig = armature("EmberRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one. The tail's tip
# rises beside the head: inside the head's ellipsoid is head, near the tail's line is tail.
r = np.sqrt((x / 0.53) ** 2 + ((y + 0.12) / 0.43) ** 2 + ((z - 0.26) / 0.39) ** 2)
d = np.stack([seg_param(co, TAIL[i], TAIL[i + 1])[1] for i in range(3)])
tail = ss(0.32, 0.24, d.min(0)) * ss(-0.2, -0.28, x) * (1 - ss(1.08, 0.98, r))
tail = np.maximum(tail, ss(-0.05, -0.12, x) * ss(0.28, 0.36, y) * (1 - ss(-0.45, -0.38, z)))
head = np.maximum(ss(1.08, 0.98, r), ss(-0.17, -0.1, z)) * (1 - tail)
ear = ss(0.56, 0.66, z) * ss(0.1, 0.2, ax) * head
arm = np.zeros(len(co)); arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.1, 0.15)
    on = np.sign(x) == sx
    arm = np.where(on, w * ss(0.19, 0.25, ax), arm); arm_t = np.where(on, t, arm_t)
arm *= 1 - head - tail
leg = (1 - ss(-0.82, -0.76, z)) * (1 - head - arm - tail)
foot = 1 - ss(-0.9, -0.86, z)
core = 1 - head - arm - tail - leg
chest = ss(-0.46, -0.36, z)
spine = ss(-0.68, -0.58, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head - ear)
# Tail chain: each vertex goes to the nearest of the three segments, blended softly.
soft = np.exp(-(d - d.min(0)) / 0.04); soft /= soft.sum(0)
for i in range(3): add(f"tail.{i + 1}", tail * soft[i])
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.5, 0.62, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    t, _ = seg_param(co, EAR[s][0], EAR[s][2])
    e2 = ss(0.4, 0.6, t)
    add(f"ear.{s}.1", ear * on * (1 - e2)); add(f"ear.{s}.2", ear * on * e2)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W)
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -60), "hand.R": (0, 0, -30), "ear.L.1": (0, -20, 0), "tail.2": (0, 0, 30), "tail.3": (0, 0, 30)}),
    ("back.png", 180, {"tail.1": (0, 0, -20), "tail.2": (0, 0, -25)}),
    ("sit_side.png", 90, {"thigh.L": (80, 0, 0), "thigh.R": (80, 0, 0), "foot.L": (-75, 0, 0), "foot.R": (-75, 0, 0)}),
])
