# Noor's rig: a chubby baby moth. Meshy's body is kept for its proportions only: it comes out as one fused piece with its
# wings as flat plates through the hips, feathers as carved slabs and fur as a sculpted crust, so those are cut away,
# the rest is voxel-remeshed into a clean closed shape for the fur shells (characters/noor.js) to grow from, and wings,
# feathers and rosette are built here as parts of their own from paintings (textures/noor/).
# blender -b -P rig_noor.py -- <in.glb> <out.glb> <test dir>
#   root › hips › spine › chest › head › antenna.{L,R}.{1,2,3};  chest › arm › hand, wing;  hips › thigh › foot
# Numbers from probe.py on the raw model: the plates lie at y 0.19–0.24; the raw head is 0.83 wide, its face reaches
# y -0.41; feathers above z 0.5; rosette at |x| < 0.14, z -0.43…-0.16; arms leave the body past |x| 0.33, hands end near
# (0.64, -0.18, -0.39) before slimming. Green of the AO colour: 0 bare, 0.5 fur, 1 ruff.
import sys, os, json, bpy, bmesh
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from mathutils import kdtree
from rigkit import ss, limb, prepare, armature, coords, colours, skin, bake_ao, export, shots, grow, mark, islands

src, dst, tests = sys.argv[sys.argv.index("--") + 1:][:3]
TEX = os.path.join(os.path.dirname(__file__), "..", "textures", "noor") + "/"
mesh = prepare(src, "Noor", ratio=0.2)

# --- What the raw colours say, kept by place, because the remesh below drops the texture.
co = coords(mesh); x, y, z = co.T; ax = np.abs(x); col = colours(mesh); r, g, b = col.T
rb = r - b; lo = col.min(1)
gold = (rb > 0.22) & (r > 0.5)
plate = ((y > 0.165) & (y < 0.29) & (ax > 0.31) & (z < -0.04) & ~((lo > 0.62) & (z > -0.3) & (y > 0.27))) | (gold & (y > 0.1) & (z < 0.1))
plate |= (y > 0.165) & (ax > 0.42) & (z < -0.12)
feather = gold & (z > 0.5)
ros = (ax < 0.17) & (z > -0.47) & (z < -0.12) & (y < -0.3) & (gold | ((lo > 0.55) & (z < -0.17)))
kill = plate | feather | ros
print("cut", plate.sum(), feather.sum(), ros.sum(), "of", len(co))
d0 = np.sqrt((x / 0.44) ** 2 + ((y + 0.04) / 0.40) ** 2 + ((z - 0.31) / 0.37) ** 2)
beside = (z < -0.14) & (ax > 0.4)
cream = (rb > 0.045) & (lo > 0.6) & (z > -0.47) & (z < 0.36) & (ax < 0.7) & ~beside & (d0 > 0.9)
hand = (lo > 0.6) & (ax > 0.45) & (z < -0.2) & (z > -0.62) & (y < 0.15) & ~cream
foot = (lo > 0.55) & (z < -0.66)
keep = ~kill
kd = kdtree.KDTree(int(keep.sum()))
idx = np.nonzero(keep)[0]
for k, i in enumerate(idx): kd.insert(co[i], k)
kd.balance()
raw_ruff, raw_hand, raw_foot = cream[idx], hand[idx], foot[idx]

bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(kill)[0]], context="VERTS")
bm.to_mesh(mesh.data); bm.free()
isl = islands(mesh)
bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(isl > 0)[0]], context="VERTS")
bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=4000)
print("open edges left", sum(1 for e in bm.edges if e.is_boundary))
bm.to_mesh(mesh.data); bm.free()

# --- One closed, even skin, with no crust and no holes.
# (Octree: a voxel remesh falls to pieces on what the cuts leave open.)
mod = mesh.modifiers.new("v", "REMESH"); mod.mode = "SMOOTH"; mod.octree_depth = 8; mod.scale = 0.9; mod.use_remove_disconnected = True; mod.threshold = 1.0; mod.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier="v")
isl = islands(mesh)
if isl.max() > 0:
    bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(isl > 0)[0]], context="VERTS"); bm.to_mesh(mesh.data); bm.free()
FACES = 22000
dec = mesh.modifiers.new("d", "DECIMATE"); dec.ratio = min(1, FACES / max(1, len(mesh.data.polygons)))
bpy.ops.object.modifier_apply(modifier="d")
bpy.ops.object.shade_smooth()
print("body faces", len(mesh.data.polygons))
co = coords(mesh); nv = len(co)
ruff = np.zeros(nv, bool); hand_ = np.zeros(nv, bool); foot_ = np.zeros(nv, bool)
for i in range(nv):
    near = [t[1] for t in kd.find_n(co[i], 5)]
    ruff[i] = raw_ruff[near].sum() >= 3; hand_[i] = raw_hand[near].sum() >= 3; foot_[i] = raw_foot[near].sum() >= 3
# Only real hands and feet: the raw texture has pearl flecks elsewhere, and a bare patch shows as a hole in the fur.
hand_ &= np.linalg.norm(np.abs(co) * np.array([1, 0, 1]) - np.array([0.64, 0, 0.39]), axis=1) < 0.15
foot_ &= co[:, 2] < -0.72
ruff = grow(mesh, ruff, ~(hand_ | foot_), 1)

# --- The shape, toward the sheet.
def move(c):
    mesh.data.vertices.foreach_set("co", c.ravel()); mesh.data.update()
# The founder: a little less fat. The body below the ruff narrows and thins, arms with it; the feet keep most of their stance.
c0 = coords(mesh); slim = 1 - 0.13 * ss(-0.06, -0.2, c0[:, 2]) * (1 - 0.6 * ss(-0.72, -0.82, c0[:, 2]))
c0[:, 0] *= slim; c0[:, 1] = -0.06 + (c0[:, 1] + 0.06) * slim; move(c0)
bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
allv = list(bm.verts)
for _ in range(3): bmesh.ops.smooth_vert(bm, verts=allv, factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
furv = [bm.verts[i] for i in np.nonzero(~(hand_ | foot_))[0]]
for _ in range(10): bmesh.ops.smooth_vert(bm, verts=furv, factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.to_mesh(mesh.data); bm.free()
# The sheet's head is a full round dome (Meshy's narrows to a hood): pulled onto an ellipsoid above the ruff.
HEAD_C = np.array([0, -0.03, 0.27]); HEAD_R = np.array([0.43, 0.405, 0.355])
c0 = coords(mesh); q = (c0 - HEAD_C) / HEAD_R; rad = np.linalg.norm(q, axis=1)
on = ss(0.02, 0.14, c0[:, 2]) * (rad < 1.25) * (~ruff) * ss(0.0, 0.3, 1.25 - rad + 0.2)
c0 = c0 + (HEAD_C + HEAD_R * (q / rad[:, None]) - c0) * on[:, None]; move(c0)
bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
headv = [bm.verts[i] for i in np.nonzero(on > 0.02)[0]]
for _ in range(4): bmesh.ops.smooth_vert(bm, verts=headv, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.to_mesh(mesh.data); bm.free()
mesh.data.materials.clear()
mesh.data.materials.append(bpy.data.materials.new("noor-body"))

# --- Bones.
CURVE = np.array([[0.085, 0.56, 0.15], [0.125, 0.70, 0.16], [0.19, 0.83, 0.13], [0.32, 0.94, 0.09], [0.5, 0.985, 0.04], [0.7, 0.91, -0.02]])  # x, up, toward the viewer
def cr(pts, t):
    n = len(pts) - 1; f = t * n; i = min(int(f), n - 1); u = f - i
    p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n)]
    return 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (3 * p1 - p0 - 3 * p2 + p3) * u * u * u)
def bl(p, sx=1): return (p[0] * sx, -p[2], p[1])  # three → Blender
B = [("root", (0, 0, -0.952), (0, 0, -0.85), None, {"deform": False}),
     ("hips", (0, 0, -0.62), (0, 0, -0.42), "root"),
     ("spine", (0, 0, -0.42), (0, 0, -0.2), "hips", {"connect": True}),
     ("chest", (0, 0, -0.2), (0, 0, 0.06), "spine", {"connect": True}),
     ("head", (0, 0, 0.06), (0, 0, 0.62), "chest", {"connect": True}),
     ("face", (0, -0.4, 0.25), (0, -0.5, 0.25), "head", {"deform": False})]
ARM = {}
for s, sx in (("L", 1), ("R", -1)):
    ARM[s] = ((0.29 * sx, -0.03, -0.16), (0.44 * sx, -0.1, -0.28), (0.56 * sx, -0.17, -0.39))
    B += [(f"arm.{s}", ARM[s][0], ARM[s][1], "chest"),
          (f"hand.{s}", ARM[s][1], ARM[s][2], f"arm.{s}", {"connect": True}),
          (f"thigh.{s}", (0.19 * sx, -0.03, -0.7), (0.2 * sx, -0.03, -0.8), "hips"),
          (f"foot.{s}", (0.2 * sx, -0.03, -0.8), (0.21 * sx, -0.26, -0.93), f"thigh.{s}", {"connect": True}),
          # The hinge lies along the wing's root, next to the spine: the engine turns bones about the model's axes.
          (f"wing.{s}", (0.04 * sx, 0.31, -0.08), (0.04 * sx, 0.31, -0.5), "chest")]
    pts = [bl(cr(CURVE, t), sx) for t in (0, 1 / 3, 2 / 3, 1)]
    for i in range(3):
        B.append((f"antenna.{s}.{i + 1}", pts[i], pts[i + 1], "head" if i == 0 else f"antenna.{s}.{i}", {"connect": i > 0}))
rig = armature("NoorRig", B)

# --- The body's weights: each part takes its share of what is left.
co = coords(mesh); x, y, z = co.T; ax = np.abs(x)
W = {}
def add(n, w): W[n] = W.get(n, 0) + w
on_ = {"L": x >= 0, "R": x < 0}
dh = np.sqrt((x / 0.45) ** 2 + ((y + 0.03) / 0.43) ** 2 + ((z - 0.29) / 0.38) ** 2)
head = ss(1.04, 0.94, dh) * ~ruff
arm = np.zeros(nv); t_ = np.zeros(nv)
for s, sx in (("L", 1), ("R", -1)):
    w, t = limb(co, ARM[s][0], ARM[s][2], 0.1, 0.15)
    arm = np.where(on_[s], w * ss(0.26, 0.33, ax), arm); t_ = np.where(on_[s], t, t_)
arm *= (1 - head)
legs = (1 - ss(-0.8, -0.7, z)) * (1 - arm - head) * (ax < 0.4)
foot_w = 1 - ss(-0.85, -0.79, z)
core = 1 - head - arm - legs
chest = ss(-0.3, -0.15, z); spine = ss(-0.55, -0.42, z) * (1 - chest)
add("chest", core * chest); add("spine", core * spine); add("hips", core * (1 - chest - spine)); add("head", head)
for s, sx in (("L", 1), ("R", -1)):
    m = on_[s] * 1.0
    hnd = ss(0.6, 0.72, t_)
    add(f"arm.{s}", arm * m * (1 - hnd)); add(f"hand.{s}", arm * m * hnd)
    add(f"thigh.{s}", legs * m * (1 - foot_w)); add(f"foot.{s}", legs * m * foot_w)
skin(mesh, rig, W)

# --- Parts.
def new_part(name, verts, faces, uvs, image):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    uv = me.uv_layers.new(name="UV"); loops = np.array([l.vertex_index for l in me.loops])
    uv.data.foreach_set("uv", np.asarray(uvs)[loops].ravel())
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons)); me.update()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name); mat.use_nodes = True; nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(TEX + image)
    bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]; nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    return ob
def rig_part(ob, W_):
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    for name, w in W_.items():
        vg = ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name)
        for i in np.nonzero(w > 1e-4)[0]: vg.add([int(i)], float(w[i]), "REPLACE")

OUT = np.array(json.load(open(TEX + "wing-outline.json"))["outline"]); SIZE = 1254
def pad(side):
    # A thick soft pad: rings of the outline, domed, swept back from the outer edge to behind the spine.
    N, M = len(OUT), 22; C = np.array([0.42, -0.44]); V, UV, F = [], [], []
    for sign in (1, -1):
        for j in range(M + 1):
            u = j / M
            for i in range(N):
                p0 = C + (OUT[i] - C) * u
                px, py = p0
                dome = 0.036 * np.sqrt(max(0, 1 - u ** 3)) + 0.006
                along = -0.37 + 0.4 * px - 0.06 * (1 - u * u)     # three's z: toward the viewer
                V.append(bl((side * (px - 0.37 * dome * sign), py, along + 0.93 * dome * sign)))
                UV.append(((p0[0] + 0.03) / 0.9, 1 - (-0.01 - p0[1]) / 0.9))
    at = lambda s, j, i: s * (M + 1) * N + j * N + (i % N)
    for s in range(2):
        for j in range(M):
            for i in range(N):
                a, b_, c, d = at(s, j, i), at(s, j, i + 1), at(s, j + 1, i), at(s, j + 1, i + 1)
                F.append((a, c, d, b_) if (s == 0) == (side > 0) else (a, b_, d, c))
    return V, F, UV
V, F, UV, WL, WR = [], [], [], [], []
for side in (1, -1):
    v, f, uv = pad(side); o = len(V)
    V += v; UV += uv; F += [tuple(i + o for i in q) for q in f]
    (WL if side > 0 else WR).extend(range(o, o + len(v)))
wings = new_part("A_Wings", V, F, UV, "wing-color.jpg")
wl = np.zeros(len(V)); wl[WL] = 1; wr = np.zeros(len(V)); wr[WR] = 1
rig_part(wings, {"wing.L": wl, "wing.R": wr})

# Occlusion on the body now, with the wings there to shade its back, before the feathers and the rosette.
bake_ao(mesh, samples=48)
col_ = np.full(nv, 0.5); col_[hand_ | foot_] = 0.0; col_[ruff & ~(hand_ | foot_)] = 1.0
# Blurred over the mesh's edges: the fur's borders follow this field, and hard steps show as jagged cuffs.
ev = np.empty(len(mesh.data.edges) * 2, dtype=np.int64); mesh.data.edges.foreach_get("vertices", ev); ea, eb = ev.reshape(-1, 2).T
for _ in range(3):
    s_ = np.zeros(nv); n_ = np.zeros(nv)
    np.add.at(s_, ea, col_[eb]); np.add.at(s_, eb, col_[ea]); np.add.at(n_, ea, 1); np.add.at(n_, eb, 1)
    col_ = 0.5 * col_ + 0.5 * s_ / np.maximum(n_, 1)
mark(mesh, col_)
print("ruff", ruff.sum(), "hands", hand_.sum(), "feet", foot_.sum())

V, F, UV = [], [], []; AW = {}
NT, NS, WID = 44, 8, 0.2
for s, side in (("L", 1), ("R", -1)):
    o = len(V)
    for i in range(NT + 1):
        t = i / NT; p = cr(CURVE, t); dp = cr(CURVE, min(1, t + 0.01)) - cr(CURVE, max(0, t - 0.01)); tan = dp / np.linalg.norm(dp)
        perp = np.array([-tan[1], tan[0], 0]); perp /= np.linalg.norm(perp)
        # Turned about its stem, so it still has width from the side.
        ang = 0.5 - 0.2 * t; perp = perp * np.cos(ang) + np.cross(tan, perp) * np.sin(ang)
        for j in range(NS + 1):
            k = j / NS * 2 - 1
            q = p + perp * k * WID + np.array([0, 0, -k * k * 0.045])
            V.append(bl(q, side)); UV.append((t, 1 - (0.49 + k * 0.49)))
    for i in range(NT):
        for j in range(NS):
            a = o + i * (NS + 1) + j; b_ = a + NS + 1
            F.append((a, b_, b_ + 1, a + 1))
    for b_i in (1, 2, 3): AW[f"antenna.{s}.{b_i}"] = np.zeros(10)
feathers = new_part("A_Feathers", V, F, UV, "feather-color.jpg")
ts = np.array([uv[0] for uv in UV]); sx = np.array([v[0] for v in V])
w1 = ss(0.42, 0.24, ts); w3 = ss(0.58, 0.76, ts); w2 = 1 - w1 - w3
FW = {}
for s, on_s in (("L", sx >= 0), ("R", sx < 0)):
    FW[f"antenna.{s}.1"] = w1 * on_s; FW[f"antenna.{s}.2"] = w2 * on_s; FW[f"antenna.{s}.3"] = w3 * on_s
rig_part(feathers, FW)

# The rosette: curved openwork hanging just over the fur, on the chest under the ruff.
co = coords(mesh); near = (np.abs(co[:, 0]) < 0.05) & (np.abs(co[:, 2] + 0.5) < 0.03)
Y0 = co[near, 1].min() - 0.05; R_, CZ, Vn = 0.16, -0.35, 26
V, F, UV = [], [], []
for j in range(Vn + 1):
    for i in range(Vn + 1):
        a, b_ = i / Vn * 2 - 1, j / Vn * 2 - 1
        V.append((a * R_, Y0 + 0.06 * (a * a + b_ * b_), CZ + b_ * R_)); UV.append((i / Vn, j / Vn))
for j in range(Vn):
    for i in range(Vn):
        q = j * (Vn + 1) + i; F.append((q, q + 1, q + Vn + 2, q + Vn + 1))
rosette = new_part("A_Rosette", V, F, UV, "rosette-color.jpg")
n = len(V); rig_part(rosette, {"chest": np.full(n, 0.7), "spine": np.full(n, 0.3)})

# Textures the materials need beyond their colour, carried on small quads the character file takes away.
def carrier(name, image):
    me = bpy.data.meshes.new(name); me.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)]); me.uv_layers.new(name="UV")
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name); mat.use_nodes = True; nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(TEX + image)
    bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]; nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
for c_ in ("wing-height", "wing-mat", "feather-alpha", "rosette-alpha"):
    carrier("tx_" + c_.replace("-", "_"), c_ + ".jpg")
export(dst, tex=2048)
