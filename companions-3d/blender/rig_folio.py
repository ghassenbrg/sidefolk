# Folio's rig: a folded-paper character: one stiff body that bends a little like card, two paper
# fins for arms and two folded feet.
# blender -b -P rig_folio.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head;  chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R}
# Numbers from measure.py / probe.py, after turning the model 180° (Meshy faced it backwards: the
# cream corner flap belongs on the front): the body runs from its feet (z < -0.66) to the roof's
# point (0.84), about ±0.7 wide and only ±0.25 deep; the fins leave its sides past |x| ≈ 0.7 at
# z -0.15…-0.5; the feet are centred at |x| ≈ 0.33.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, prepare, armature, coords, skin, bake_ao, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Folio", ratio=0.35, turn=180)

B = [("root", (0, 0, -0.837), (0, 0, -0.75), None, {"deform": False}),
     ("hips", (0, 0, -0.62), (0, 0, -0.32), "root"),
     ("spine", (0, 0, -0.32), (0, 0, -0.02), "hips", {"connect": True}),
     ("chest", (0, 0, -0.02), (0, 0, 0.2), "spine", {"connect": True}),
     ("head", (0, 0, 0.2), (0, 0, 0.84), "chest", {"connect": True}),
     ("face", (0, -0.3, -0.05), (0, -0.4, -0.05), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.66 * sx, 0, -0.2), (0.82 * sx, 0, -0.3), (0.95 * sx, 0, -0.4))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.33 * sx, 0, -0.6), (0.33 * sx, 0, -0.72), "hips"),
          (f"foot.{s}", (0.33 * sx, 0, -0.72), (0.33 * sx, -0.15, -0.82), f"thigh.{s}", {"connect": True})]
rig = armature("FolioRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one. The body is card:
# wide, overlapping bands, so a nod or a lean bends all of it a little rather than at a crease.
arm = ss(0.68, 0.75, ax) * ss(-0.56, -0.5, z) * (1 - ss(-0.1, -0.04, z))
leg = (1 - ss(-0.69, -0.62, z)) * (1 - arm)
foot = 1 - ss(-0.77, -0.72, z)
core = 1 - arm - leg
head = ss(-0.05, 0.4, z)
chest = ss(-0.3, 0.05, z) * (1 - head)
spine = ss(-0.6, -0.3, z) * (1 - head - chest)
add("head", core * head); add("chest", core * chest); add("spine", core * spine)
add("hips", core * (1 - head - chest - spine))
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    t, _ = seg_param(co, ARM[s][0], ARM[s][2])
    hand = ss(0.4, 0.6, t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
skin(mesh, rig, W, smooth=(0.5, 1))
bake_ao(mesh)
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -70), "hand.R": (0, 0, -30), "head": (0, 10, 0)}),
    ("side.png", 90, {"spine": (15, 0, 0), "head": (10, 0, 0)}),
], scale=2.2)
