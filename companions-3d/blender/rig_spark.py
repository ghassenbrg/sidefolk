# Spark's rig: a little robot, so parts stay rigid and bend only at their joints.
# blender -b -P rig_spark.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head › antenna.1 › antenna.2
#   chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe.py on the Meshy model (Z up, facing -Y): the head runs from the
# neck ring (z -0.2) to its cap (0.65), the antenna stem leaves it at x ≈ 0 and bends toward +x
# to a ball centred near (0.09, 0.02, 0.84); arms leave the torso past |x| ≈ 0.23 at z -0.44.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Spark", ratio=0.3)

B = [("root", (0, 0, -0.952), (0, 0, -0.85), None, {"deform": False}),
     ("hips", (0, 0, -0.66), (0, 0, -0.56), "root"),
     ("spine", (0, 0, -0.56), (0, 0, -0.42), "hips", {"connect": True}),
     ("chest", (0, 0, -0.42), (0, 0, -0.22), "spine", {"connect": True}),
     ("head", (0, 0, -0.22), (0, 0, 0.62), "chest", {"connect": True}),
     ("antenna.1", (0, 0, 0.64), (0.025, 0, 0.75), "head"),
     ("antenna.2", (0.025, 0, 0.75), (0.09, 0.02, 0.86), "antenna.1", {"connect": True}),
     ("face", (0, -0.40, 0.17), (0, -0.50, 0.17), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.22 * sx, 0, -0.43), (0.42 * sx, 0, -0.53), (0.49 * sx, -0.02, -0.62))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.15 * sx, 0, -0.66), (0.15 * sx, 0, -0.84), "hips"),
          (f"foot.{s}", (0.15 * sx, 0, -0.84), (0.15 * sx, -0.12, -0.94), f"thigh.{s}", {"connect": True})]
rig = armature("SparkRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

head = ss(-0.215, -0.175, z)
ant = ss(0.655, 0.675, z) * (ax < 0.25)
ant2 = ss(0.72, 0.76, z)
# Each part takes its share of what is left, so the shares always sum to one.
arm = ss(0.215, 0.245, ax) * ss(-0.68, -0.645, z) * (1 - ss(-0.36, -0.32, z)) * (1 - head)
leg = (1 - ss(-0.69, -0.645, z)) * (1 - head - arm)
foot = 1 - ss(-0.865, -0.825, z)
core = 1 - head - arm - leg
chest = ss(-0.47, -0.40, z)
spine = ss(-0.62, -0.55, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head * (1 - ant)); add("antenna.1", head * ant * (1 - ant2)); add("antenna.2", head * ant * ant2)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    t, _ = seg_param(co, ARM[s][0], ARM[s][1])
    hand = ss(0.82, 0.98, t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
# A robot's shells are rigid: only a light smoothing at the joints.
skin(mesh, rig, W, smooth=(0.35, 1))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -80), "hand.R": (0, 0, -30), "head": (0, 10, 0), "antenna.1": (0, 25, 0), "antenna.2": (0, 30, 0)}),
    ("bow_side.png", 90, {"spine": (30, 0, 0), "chest": (15, 0, 0), "head": (10, 0, 0)}),
    ("sit_side.png", 90, {"thigh.L": (80, 0, 0), "thigh.R": (80, 0, 0), "foot.L": (-75, 0, 0), "foot.R": (-75, 0, 0)}),
])
