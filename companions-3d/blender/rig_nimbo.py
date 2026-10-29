# Nimbo's rig: a floating cloud. The body bends softly from bottom to top like jelly, and the two
# little cloud puffs in front of its lower sides are its hands, each on an arm bone that pivots
# inside the body, so a wave lifts a puff up beside the face.
# blender -b -P rig_nimbo.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R}
# Numbers from measure.py / probe.py on the second model (after the founder's sheet, 2026-10-30):
# a wide cloud, x ±0.95, z ±0.67, y ±0.43, its face flat-ish at y -0.39; the puffs bulge out of the
# body's lower front corners around (±0.63, -0.33, -0.36), radius about 0.17 (one piece with it).
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Nimbo", ratio=0.55)

B = [("root", (0, 0, -0.671), (0, 0, -0.6), None, {"deform": False}),
     ("hips", (0, 0, -0.55), (0, 0, -0.3), "root"),
     ("spine", (0, 0, -0.3), (0, 0, -0.1), "hips", {"connect": True}),
     ("chest", (0, 0, -0.1), (0, 0, 0.05), "spine", {"connect": True}),
     ("head", (0, 0, 0.05), (0, 0, 0.67), "chest", {"connect": True}),
     ("face", (0, -0.45, -0.1), (0, -0.55, -0.1), "head", {"deform": False})]
PUFF = {}
for s, sx in (("L", 1), ("R", -1)):
    PUFF[s] = np.array((0.63 * sx, -0.33, -0.36))
    B += [(f"arm.{s}", (0.4 * sx, -0.15, -0.25), tuple(PUFF[s]), "chest"),
          (f"hand.{s}", tuple(PUFF[s]), (0.72 * sx, -0.4, -0.45), f"arm.{s}", {"connect": True})]
rig = armature("NimboRig", B)

co = coords(mesh); x, y, z = co.T
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# The puffs are one piece with the body: the front of each bulge is its hand, fading into the
# cloud behind it, so a lifted puff stretches out of the cloud like soft jelly (the character
# file keeps those moves small).
puff = {}
for s, sx in (("L", 1), ("R", -1)):
    d = np.linalg.norm((co - PUFF[s]) * np.array((1, 0.8, 1)), axis=1)
    puff[s] = ss(0.22, 0.15, d) * ss(-0.18, -0.3, y) * (np.sign(x) == sx)
core = 1 - puff["L"] - puff["R"]
# Soft, overlapping bands: the cloud squashes and sways as one.
head = ss(-0.12, 0.15, z)
chest = ss(-0.35, -0.12, z) * (1 - head)
spine = ss(-0.55, -0.35, z) * (1 - head - chest)
add("head", core * head); add("chest", core * chest); add("spine", core * spine)
add("hips", core * (1 - head - chest - spine))
for s in ("L", "R"): add(f"hand.{s}", puff[s])
skin(mesh, rig, W, smooth=(0.5, 1))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -70), "head": (0, 10, 8)}),
    ("side.png", 90, {"spine": (12, 0, 0), "head": (10, 0, 0)}),
], scale=2.2)
