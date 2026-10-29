# Nimbo's rig: a floating cloud. The body bends softly from bottom to top like jelly, and the two
# little cloud puffs in front of its lower sides are its hands, each on an arm bone that pivots
# inside the body, so a wave lifts a puff up beside the face.
# blender -b -P rig_nimbo.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R}
# Numbers from measure.py / probe.py: the cloud spans z -0.83…0.83, its face looks out at y -0.67;
# the puffs sit around (±0.74, -0.45, -0.63), radius about 0.2.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, prepare, armature, coords, islands, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Nimbo", ratio=0.55)

B = [("root", (0, 0, -0.831), (0, 0, -0.75), None, {"deform": False}),
     ("hips", (0, 0, -0.62), (0, 0, -0.32), "root"),
     ("spine", (0, 0, -0.32), (0, 0, -0.06), "hips", {"connect": True}),
     ("chest", (0, 0, -0.06), (0, 0, 0.14), "spine", {"connect": True}),
     ("head", (0, 0, 0.14), (0, 0, 0.83), "chest", {"connect": True}),
     ("face", (0, -0.7, 0.05), (0, -0.8, 0.05), "head", {"deform": False})]
PUFF = {}
for s, sx in (("L", 1), ("R", -1)):
    PUFF[s] = np.array((0.74 * sx, -0.45, -0.63))
    B += [(f"arm.{s}", (0.42 * sx, -0.25, -0.42), tuple(PUFF[s]), "chest"),
          (f"hand.{s}", tuple(PUFF[s]), (0.86 * sx, -0.5, -0.72), f"arm.{s}", {"connect": True})]
rig = armature("NimboRig", B)

co = coords(mesh); x, y, z = co.T
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# The puffs are modelled apart from the body: each is whole pieces near its corner, moving
# rigidly (a puff half on the body smeared when raised).
part = islands(mesh)
puff = {}
for s, sx in (("L", 1), ("R", -1)):
    near = np.zeros(len(co), bool)
    for k in np.unique(part[np.linalg.norm(co - PUFF[s], axis=1) < 0.2]):
        if k == 0: continue
        near |= part == k
    print("puff", s, "pieces", np.unique(part[near]), "verts", int(near.sum()))
    puff[s] = near.astype(float)
core = 1 - puff["L"] - puff["R"]
# Soft, overlapping bands: the cloud squashes and sways as one.
head = ss(-0.02, 0.3, z)
chest = ss(-0.3, -0.04, z) * (1 - head)
spine = ss(-0.58, -0.3, z) * (1 - head - chest)
add("head", core * head); add("chest", core * chest); add("spine", core * spine)
add("hips", core * (1 - head - chest - spine))
for s in ("L", "R"): add(f"hand.{s}", puff[s])
skin(mesh, rig, W, smooth=(0.5, 0))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -70), "head": (0, 10, 8)}),
    ("side.png", 90, {"spine": (12, 0, 0), "head": (10, 0, 0)}),
], scale=2.2)
