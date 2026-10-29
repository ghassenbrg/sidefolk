# Builds Mochi's skinned rig from the Meshy mesh and exports a GLB for the runtime.
# blender -b -P rig_mochi.py -- <in.glb> <out.glb> <test_render_dir>
#
# Bones (Blender Z-up, model facing -Y, character's left = +X):
#   root › hips › spine › chest › head › ear.{L,R}.{1,2,3}
#   chest › arm.{L,R} › hand.{L,R};  hips › thigh.{L,R} › foot.{L,R};  hips › tail;  chest › scarf
# Weights are computed from position (bone heat tore this generated mesh); the scarf's hanging tag
# is found by its texture colour and given to `scarf` so it can swing. `tail` carries the pompom
# the runtime adds.
import bpy, sys, os, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, tests = argv[0], argv[1], argv[2]
os.makedirs(tests, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
mesh.name = "Mochi"
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# glTF import splits vertices along UV seams; weight smoothing would then pull the two sides of a
# seam apart into cracks. UVs live on loops, so merging keeps them.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth()

# 235k faces is more than a desktop companion needs; collapse keeps UVs and the soft silhouette.
dec = mesh.modifiers.new("dec", "DECIMATE"); dec.ratio = 0.3
bpy.ops.object.modifier_apply(modifier="dec")
print("faces after decimate", len(mesh.data.polygons))

# --- Armature -------------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("MochiRig")
rig = bpy.data.objects.new("MochiRig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None, connect=False, deform=True, roll=0.0):
    b = eb.new(name); b.head = Vector(head); b.tail = Vector(tail); b.roll = roll
    if parent: b.parent = eb[parent]; b.use_connect = connect
    b.use_deform = deform
    return b

bone("root", (0, 0, -0.952), (0, 0, -0.85), deform=False)
bone("hips", (0, 0, -0.74), (0, 0, -0.60), "root")
bone("spine", (0, 0, -0.60), (0, 0, -0.50), "hips", True)
bone("chest", (0, 0, -0.50), (0, 0, -0.40), "spine", True)
bone("head", (0, 0, -0.40), (0, 0, 0.28), "chest", True)
for s, sx in (("L", 1), ("R", -1)):
    base, tip = Vector((0.15 * sx, 0.03, 0.22)), Vector((0.335 * sx, 0.025, 0.94))
    pts = [base.lerp(tip, t) for t in (0, 0.30, 0.62, 1.0)]
    bone(f"ear.{s}.1", pts[0], pts[1], "head")
    bone(f"ear.{s}.2", pts[1], pts[2], f"ear.{s}.1", True)
    bone(f"ear.{s}.3", pts[2], pts[3], f"ear.{s}.2", True)
    # Shoulder at the arm's real root (measure_arm.py: the arm leaves the torso at |x| ≈ 0.28,
    # centred at z ≈ -0.53), so a raised arm turns about its own base, not the chest.
    bone(f"arm.{s}", (0.272 * sx, 0.015, -0.535), (0.415 * sx, 0.015, -0.575), "chest")
    bone(f"hand.{s}", (0.415 * sx, 0.015, -0.575), (0.535 * sx, 0.015, -0.61), f"arm.{s}", True)
    bone(f"thigh.{s}", (0.135 * sx, 0, -0.71), (0.14 * sx, 0, -0.85), "hips")
    bone(f"foot.{s}", (0.14 * sx, 0, -0.85), (0.14 * sx, -0.10, -0.935), f"thigh.{s}", True)
bone("tail", (0, 0.20, -0.70), (0, 0.32, -0.70), "hips")
bone("scarf", (0.10, -0.30, -0.44), (0.10, -0.31, -0.66), "chest")
# A socket for the face pieces the runtime builds (eyes, mouth, blush): not deforming.
bone("face", (0, -0.40, -0.05), (0, -0.50, -0.05), "head", deform=False)
bpy.ops.object.mode_set(mode="OBJECT")

# --- Skin -----------------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True); rig.select_set(True)
bpy.context.view_layer.objects.active = rig
# Bone heat tears this generated mesh (ear front and back, scarf layers get different bones), so
# weights are computed from position instead: neighbouring surfaces always move together.
bpy.ops.object.parent_set(type="ARMATURE_NAME")

me = mesh.data
nv = len(me.vertices)
co = np.empty(nv * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
x, y, z = co[:, 0], co[:, 1], co[:, 2]
side = np.where(x >= 0, "L", "R")

def ss(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def seg_param(p, a, b):
    a, b = np.array(a), np.array(b); ab = b - a
    t = ((p - a) @ ab) / (ab @ ab)
    d = np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)
    return t, d

# Texture colour per vertex (first loop's UV), to find the scarf tag.
img = me.materials[0].node_tree.nodes["Image Texture"].image if me.materials[0].use_nodes else None
uv = np.zeros((nv, 2))
loops_v = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", loops_v)
luv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", luv); luv = luv.reshape(-1, 2)
uv[loops_v] = luv
w, h = img.size
px = np.array(img.pixels[:]).reshape(h, w, -1)
ix = np.clip((uv[:, 0] % 1) * (w - 1), 0, w - 1).astype(int)
iy = np.clip((uv[:, 1] % 1) * (h - 1), 0, h - 1).astype(int)
col = px[iy, ix, :3]
turq = (col[:, 1] > col[:, 0] + 0.15) & (col[:, 2] > col[:, 0] + 0.15)

W = {}
def add(name, w):
    W[name] = W.get(name, 0) + w

# Torso: hips › spine › chest › head by height.
w_head = ss(-0.42, -0.33, z)
w_chest = ss(-0.56, -0.46, z) * (1 - w_head)
w_spine = ss(-0.70, -0.60, z) * (1 - w_head - w_chest)
w_hips = 1 - w_head - w_chest - w_spine
body = {"hips": w_hips, "spine": w_spine, "chest": w_chest, "head": w_head}

# Ears: outside the head ellipsoid, along each ear's axis.
r = np.sqrt((x / 0.44) ** 2 + ((y - 0.005) / 0.42) ** 2 + ((z + 0.03) / 0.36) ** 2)
ear = np.zeros(nv); ear_t = np.zeros(nv)
for s, sx in (("L", 1), ("R", -1)):
    on = (np.sign(x) == sx) | (np.abs(x) < 1e-6)
    t, d = seg_param(co, (0.15 * sx, 0.03, 0.22), (0.335 * sx, 0.025, 0.94))
    w = ss(0.97, 1.10, r) * ss(0.02, 0.12, t) * (z > 0.12) * on
    ear = np.where(on, w, ear); ear_t = np.where(on, t, ear_t)

# Arms: everything past the torso's edge (|x| ≈ 0.28) between armpit and shoulder heights, with
# a short blend at the joint. The scarf reaches past the shoulder there: by colour, it stays on
# the chest (an arm that grabbed it pulled a lump out of the neck when raised).
arm = np.zeros(nv); arm_s = np.zeros(nv)
scarf_soft = np.clip(turq.astype(float), 0, 1)
for sx in (1, -1):
    on = np.sign(x) == sx
    s_, d = seg_param(co, (0.272 * sx, 0.015, -0.535), (0.535 * sx, 0.015, -0.61))
    w = ss(0.268, 0.302, np.abs(x)) * ss(-0.72, -0.68, z) * (1 - ss(-0.455, -0.43, z)) * (1 - scarf_soft) * on
    arm = np.where(on, w, arm); arm_s = np.where(on, s_, arm_s)

# Legs: below the crotch, each side its own.
leg = 1 - ss(-0.80, -0.735, z)
foot = 1 - ss(-0.885, -0.84, z)

rest = (1 - ear) * (1 - arm) * (1 - leg)
for k, v in body.items(): add(k, v * rest)
for s in ("L", "R"):
    m = (side == s)
    # Ear chain: blend across joints at t = 0.30 and 0.62.
    e2 = ss(0.24, 0.36, ear_t); e3 = ss(0.56, 0.68, ear_t)
    add(f"ear.{s}.1", ear * m * (1 - e2)); add(f"ear.{s}.2", ear * m * (e2 - e3)); add(f"ear.{s}.3", ear * m * e3)
    h = ss(0.42, 0.62, arm_s)
    add(f"arm.{s}", arm * m * (1 - h) * (1 - ear)); add(f"hand.{s}", arm * m * h * (1 - ear))
    add(f"thigh.{s}", leg * m * (1 - foot) * (1 - arm) * (1 - ear)); add(f"foot.{s}", leg * m * foot * (1 - arm) * (1 - ear))
total = sum(W.values())
assert np.all(total > 0.999) and np.all(total < 1.001), (total.min(), total.max())
for name, w in W.items():
    vg = mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
    idx = np.nonzero(w > 1e-4)[0]
    for i in idx: vg.add([int(i)], float(w[i]), "REPLACE")
print("ear verts", int((ear > 0.5).sum()), "arm verts", int((arm > 0.5).sum()), "leg verts", int((leg > 0.5).sum()))

def group(name):
    return mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)

# The hanging tag: turquoise below the band, in front, on the character's left.
tag = turq & (z < -0.47) & (y < -0.15) & (x > -0.03) & (x < 0.25)
print("scarf tag verts", int(tag.sum()), "z range", z[tag].min() if tag.any() else None)
sg = group("scarf")
for i in np.nonzero(tag)[0]:
    t = float(np.clip((-0.47 - z[i]) / 0.05, 0, 1))
    if t <= 0: continue
    for g in list(mesh.vertex_groups):
        if g.name == "scarf": continue
        try: wv = g.weight(int(i))
        except RuntimeError: continue
        g.add([int(i)], wv * (1 - t), "REPLACE")
    sg.add([int(i)], t, "REPLACE")

# Normalize and keep at most four influences (glTF/WebGL skinning).
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=2)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
bpy.ops.object.mode_set(mode="OBJECT")

# --- Ambient occlusion -----------------------------------------------------------------------
# Baked once in the rest pose into a vertex colour: soft contact shading under the head, in the
# armpits, round the ear roots and the scarf. The runtime uses it to darken bounce light only.
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 96
scene.cycles.device = "CPU"
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
ao = me.color_attributes.new(name="AO", type="BYTE_COLOR", domain="POINT")
me.color_attributes.active_color = ao
me.attributes.active_color = ao
bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
aov = np.empty(nv * 4, dtype=np.float32); ao.data.foreach_get("color", aov)
print("ao min/mean", float(aov[0::4].min()), float(aov[0::4].mean()))

# --- Export ---------------------------------------------------------------------------------
# A companion is a few hundred pixels tall: a 2K texture is plenty and keeps the app small.
for img in bpy.data.images:
    if img.size[0] > 2048: img.scale(2048, 2048)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True,
                          export_skins=True, export_animations=False, export_vertex_color="ACTIVE",
                          export_image_format="JPEG", export_jpeg_quality=92)
print("exported", dst)

# --- Deformation test renders ---------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 600, 700
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.88, 0.92, 1)
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 2.4
cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN")); scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(45), 0, math.radians(25)); sun.data.energy = 3

def shoot(name, yaw):
    a = math.radians(yaw)
    cam.location = Vector((math.sin(a) * 5, -math.cos(a) * 5, 0)); cam.rotation_euler = (math.radians(90), 0, a)
    scene.render.filepath = os.path.join(tests, name); bpy.ops.render.render(write_still=True)

pb = rig.pose.bones
for b in pb: b.rotation_mode = "XYZ"
def pose(**rots):
    for b in pb: b.rotation_euler = (0, 0, 0); b.location = (0, 0, 0)
    for k, v in rots.items(): pb[k.replace("_", ".")].rotation_euler = [math.radians(x) for x in v]
    bpy.context.view_layer.update()

pose(); shoot("rest_front.png", 0)
pose(ear_L_1=(0, -25, 0), ear_L_2=(-30, 0, 0), ear_L_3=(-35, 0, 0), ear_R_2=(20, 0, 0),
     arm_L=(0, 0, 0), arm_R=(0, -70, 0), hand_R=(0, -30, 0), head=(0, 12, 0))
shoot("ears_wave_front.png", 0)
pose(spine=(35, 0, 0), chest=(20, 0, 0), head=(15, 0, 0), ear_L_2=(25, 0, 0), ear_R_2=(25, 0, 0))
shoot("bow_side.png", 90)
pose(thigh_L=(80, 0, 0), thigh_R=(80, 0, 0), foot_L=(-70, 0, 0), foot_R=(-70, 0, 0))
shoot("sit_side.png", 90)
