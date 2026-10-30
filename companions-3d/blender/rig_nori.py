# Nori's rig: a chibi tuxedo cat on its hind legs, with big pointed ears, thick glasses and a curled tail.
# blender -b -P rig_nori.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head › ear.{L,R}.{1,2};  chest › arm.{L,R} › hand.{L,R}
#   hips › thigh.{L,R} › foot.{L,R};  hips › tail.1 › tail.2 › tail.3;  chest › scarf (the hanging tag)
# Numbers from measure.py / probe.py (Z up, facing -Y, its left +X; Meshy centred it, no shift): the
# scarf sits at z -0.08…-0.25 with the neck at z -0.14, the arms leave the torso at |x| 0.4 near
# z -0.22 to cream paws at |x| 0.55–0.74, the legs are short (z < -0.64) with cream feet below -0.84,
# the ears rise from z 0.62 to tips at (±0.44, -0.09, 0.95), the glasses are modelled in front of the
# face (y -0.58…-0.37, z 0.1…0.37: they move with the head) and the tail leaves the hips on the
# character's left (+x), curls out behind and rises to a cream tip near z -0.5.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from rigkit import ss, seg_param, seg_dist, limb, prepare, regutter, armature, coords, colours, skin, bake_ao, mark, grow, export, shots

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
mesh = prepare(src, "Nori", ratio=0.3)
regutter(mesh)   # the texture's islands touch: seams would show as pale cracks when it is shrunk

FLOOR, NECK, HIPS = -0.952, -0.14, -0.6
TAIL = [(0.2, 0.34, -0.82), (0.5, 0.4, -0.8), (0.66, 0.38, -0.66), (0.64, 0.38, -0.48)]
B = [("root", (0, 0, FLOOR), (0, 0, FLOOR + 0.1), None, {"deform": False}),
     ("hips", (0, 0, HIPS - 0.15), (0, 0, HIPS + 0.15), "root"),
     ("spine", (0, 0, HIPS + 0.15), (0, 0, -0.35), "hips", {"connect": True}),
     ("chest", (0, 0, -0.35), (0, 0, NECK), "spine", {"connect": True}),
     ("head", (0, 0, NECK), (0, 0, 0.62), "chest", {"connect": True}),
     ("tail.1", TAIL[0], TAIL[1], "hips"),
     ("tail.2", TAIL[1], TAIL[2], "tail.1", {"connect": True}),
     ("tail.3", TAIL[2], TAIL[3], "tail.2", {"connect": True}),
     ("scarf", (0, -0.3, -0.22), (0, -0.31, -0.36), "chest"),
     ("face", (0, -0.5, 0.3), (0, -0.6, 0.3), "head", {"deform": False})]
ARM, EAR = {}, {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.3 * sx, 0, -0.22), (0.52 * sx, 0, -0.3), (0.72 * sx, 0, -0.4))
    EAR[s] = ((0.33 * sx, -0.05, 0.65), (0.4 * sx, -0.08, 0.8), (0.45 * sx, -0.09, 0.96))
    B += [(f"ear.{s}.1", EAR[s][0], EAR[s][1], "head"),
          (f"ear.{s}.2", EAR[s][1], EAR[s][2], f"ear.{s}.1", {"connect": True}),
          (f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.2 * sx, 0, HIPS - 0.02), (0.2 * sx, 0, FLOOR + 0.13), "hips"),
          (f"foot.{s}", (0.2 * sx, 0, FLOOR + 0.13), (0.2 * sx, -0.15, FLOOR + 0.02), f"thigh.{s}", {"connect": True})]
rig = armature("NoriRig", B)

co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w

# Each part takes its share of what is left, so the shares always sum to one.
# The tail lies along the floor behind the body (whose back is at y 0.34) and curls up its left side
# to z -0.48: near its segments (not their lines, which run on up through the head), behind the
# back and below z -0.4. Its root blends into the hips.
d = np.stack([seg_dist(co, TAIL[i], TAIL[i + 1]) for i in range(3)])
tail = ss(0.25, 0.17, d.min(0)) * ss(0.2, 0.32, x) * ss(0.3, 0.4, y) * (1 - ss(-0.44, -0.38, z))
head = ss(NECK - 0.05, NECK + 0.03, z) * (1 - tail)
ear = ss(0.58, 0.68, z) * ss(0.12, 0.22, ax) * head
arm = np.zeros(len(co)); arm_t = np.zeros(len(co))
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.12, 0.19)
    on = np.sign(x) == sx
    arm = np.where(on, w * ss(0.33, 0.42, ax), arm); arm_t = np.where(on, t, arm_t)
arm *= 1 - head - tail
# The legs are columns in front of the back (y < 0.25): behind them the tail's root lies on the
# floor, which tucked feet would otherwise drag into a sheet.
leg = (1 - ss(-0.72, -0.64, z)) * (1 - ss(0.2, 0.28, y)) * (1 - head - arm - tail)
foot = 1 - ss(-0.9, -0.84, z)
core = 1 - head - arm - tail - leg
chest = ss(-0.46, -0.36, z)
spine = ss(HIPS - 0.04, HIPS + 0.08, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine))
add("head", head - ear)
soft = np.exp(-(d - d.min(0)) / 0.05); soft /= soft.sum(0)
for i in range(3): add(f"tail.{i + 1}", tail * soft[i])
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | ((x == 0) & (s == "L"))
    hand = ss(0.5, 0.64, arm_t)
    add(f"arm.{s}", arm * on * (1 - hand)); add(f"hand.{s}", arm * on * hand)
    t, _ = seg_param(co, EAR[s][0], EAR[s][2])
    e2 = ss(0.4, 0.6, t)
    add(f"ear.{s}.1", ear * on * (1 - e2)); add(f"ear.{s}.2", ear * on * e2)
    add(f"thigh.{s}", leg * on * (1 - foot)); add(f"foot.{s}", leg * on * foot)
# The scarf's square tag (mint, in front, below the band) swings on its own bone: it takes its
# share from every other part.
col = colours(mesh)
mint = (col[:, 1] > col[:, 0] + 0.12) & (col[:, 1] > 0.5)
tag = mint * ss(-0.2, -0.25, z) * (y < -0.22)
for k in list(W): W[k] = W[k] * (1 - tag)
add("scarf", tag)
skin(mesh, rig, W)
bake_ao(mesh)
# The frames are as dark as the fur behind them: they are told apart by standing in front of the
# face (fronts at y -0.54, the face at -0.45), then grown back along the rims.
lum = col @ np.array([0.3, 0.55, 0.15])
box = (ax < 0.5) & (z > 0.04) & (z < 0.4) & (y < -0.36)
# (Meshy also painted the frames' shadow onto the face beside the rims: the mask takes those in.)
glasses = grow(mesh, box & (y < -0.475) & (lum < 0.34), box & (lum < 0.42), 10)
print("glasses vertices", int(glasses.sum()))
mark(mesh, glasses.astype(float))
export(dst)
shots(rig, tests, [
    ("rest_front.png", 0, {}),
    ("wave_front.png", 0, {"arm.R": (0, 0, -60), "hand.R": (0, 0, -30), "ear.L.1": (0, -20, 0), "tail.2": (0, 0, 30), "tail.3": (0, 0, 30)}),
    ("back.png", 180, {"tail.1": (0, 0, 20), "tail.2": (0, 0, 25)}),
    # A tail flung hard (a flip, a jump): nothing of the body may come with it.
    ("tail_flung.png", 135, {"tail.1": (40, 0, 40), "tail.2": (30, 0, 40), "tail.3": (20, 0, 30)}),
    ("sit_side.png", 90, {"thigh.L": (80, 0, 0), "thigh.R": (80, 0, 0), "foot.L": (-75, 0, 0), "foot.R": (-75, 0, 0)}),
])
