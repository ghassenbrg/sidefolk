# Shared steps for rigging a Meshy character for the 3D companion engine (one script per
# character imports this). Blender axes: Z up, the character faces -Y, its left is +X.
#
#   prepare()   import, merge UV-seam doubles, smooth shading, decimate
#   armature()  bones from a list of (name, head, tail, parent)
#   colours()   texture colour per vertex (sRGB), to find parts by colour
#   skin()      weights from position (bone heat tears generated meshes), smoothed, ≤ 4, normalized
#   bake_ao()   ambient occlusion baked into a vertex colour the runtime uses for bounce light
#   export()    GLB with skin and AO;  shots() renders posed test images
import bpy, os, math
import numpy as np
from mathutils import Matrix, Vector


def ss(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def seg_param(p, a, b):
    """Position along segment a→b (0…1 inside) and distance from its line, per vertex."""
    a, b = np.array(a, float), np.array(b, float); ab = b - a
    t = ((p - a) @ ab) / (ab @ ab)
    d = np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)
    return t, d


def prepare(src, name, ratio=0.42, shift=(0, 0, 0), turn=0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    mesh.name = name
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    # Meshy centres the bounding box; a big tail pushes the body off centre, so it is moved back.
    mesh.location = Vector(shift)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Meshy sometimes faces a flat character backwards: `turn` degrees about Z put its face to -Y.
    if turn: mesh.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
    # glTF import splits vertices along UV seams; weight smoothing would then pull the two sides
    # of a seam apart into cracks. UVs live on loops, so merging keeps them.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    if ratio < 1:
        dec = mesh.modifiers.new("dec", "DECIMATE"); dec.ratio = ratio
        bpy.ops.object.modifier_apply(modifier="dec")
    print("faces", len(mesh.data.polygons))
    return mesh


def regutter(mesh, size=2048, margin=0.012):
    """Meshy packs its texture islands edge to edge, so when the texture is shrunk (mipmaps, a small
    window) the neighbouring island's colour bleeds into every seam as a pale crack. This packs the
    islands again with a margin and bakes the colour into a new texture whose margin carries each
    island's own colour outward."""
    me = mesh.data
    mat = me.materials[0]; nt = mat.node_tree
    src = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
    old = me.uv_layers.active.name
    # The old texture keeps reading the old UVs while the bake writes the new ones.
    uvnode = nt.nodes.new("ShaderNodeUVMap"); uvnode.uv_map = old
    nt.links.new(uvnode.outputs[0], src.inputs["Vector"])
    # Layer handles go stale across mode switches: they are found again by name.
    new = me.uv_layers.new(name="UVPacked"); new.active = True; new.active_render = True; packed = new.name
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=margin, rotate=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("baked_color", size, size)
    tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.image = img
    nt.nodes.active = tgt
    # The texture is baked as light (a diffuse bake reads black on a material Meshy made metallic).
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    shader = out.inputs["Surface"].links[0].from_socket
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(src.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 1
    scene.render.bake.margin = 24; scene.render.bake.margin_type = "EXTEND"
    bpy.ops.object.bake(type="EMIT")
    nt.links.new(shader, out.inputs["Surface"]); nt.nodes.remove(emit)
    # The baked texture replaces the old one on the new UVs, and the old UVs go.
    nt.links.new(uvnode.outputs[0], src.inputs["Vector"])
    uvnode.uv_map = packed
    src.image = img
    me.uv_layers.remove(me.uv_layers[old])
    nt.nodes.remove(tgt)
    print("regutter: baked", size, "px with margin", margin)


def armature(name, bones):
    """bones: [(name, head, tail, parent or None, {connect, deform})]."""
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = data.edit_bones
    for spec in bones:
        n, head, tail, parent = spec[:4]
        opt = spec[4] if len(spec) > 4 else {}
        b = eb.new(n); b.head = Vector(head); b.tail = Vector(tail)
        if parent: b.parent = eb[parent]; b.use_connect = opt.get("connect", False)
        b.use_deform = opt.get("deform", True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def limb(co, a, b, r0, r1):
    """1 within r0 of segment a→b (between its ends, a little past b), fading to 0 at r1."""
    t, d = seg_param(co, a, b)
    return ss(r1, r0, d) * ss(-0.15, 0.0, t) * (1 - ss(1.25, 1.45, t)), t


def coords(mesh):
    me = mesh.data
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def colours(mesh):
    me = mesh.data; nv = len(me.vertices)
    img = [n for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE"][0].image
    uv = np.zeros((nv, 2))
    lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
    luv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", luv)
    uv[lv] = luv.reshape(-1, 2)
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, -1)
    ix = np.clip((uv[:, 0] % 1) * (w - 1), 0, w - 1).astype(int)
    iy = np.clip((uv[:, 1] % 1) * (h - 1), 0, h - 1).astype(int)
    return px[iy, ix, :3] ** (1 / 2.2)


def skin(mesh, rig, W, smooth=(0.5, 2)):
    """W: {bone: weights per vertex}; must sum to 1 everywhere."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True); rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    total = sum(W.values())
    assert np.all(total > 0.999) and np.all(total < 1.001), (total.min(), total.max())
    for name, w in W.items():
        vg = mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
        for i in np.nonzero(w > 1e-4)[0]: vg.add([int(i)], float(w[i]), "REPLACE")
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    if smooth[1]:
        bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=smooth[0], repeat=smooth[1])
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_ao(mesh, samples=96):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.device = "CPU"
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
    me = mesh.data
    ao = me.color_attributes.new(name="AO", type="BYTE_COLOR", domain="POINT")
    me.color_attributes.active_color = ao
    me.attributes.active_color = ao
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    v = np.empty(len(me.vertices) * 4, dtype=np.float32); ao.data.foreach_get("color", v)
    print("ao min/mean", float(v[0::4].min()), float(v[0::4].mean()))


def mark(mesh, mask):
    """A part the texture can't tell apart by colour (Nori's black frames against charcoal fur)
    rides in the AO colour's green channel, after bake_ao(); the material reads it as `part`."""
    me = mesh.data; ao = me.color_attributes["AO"]
    v = np.empty(len(me.vertices) * 4, dtype=np.float32); ao.data.foreach_get("color", v)
    v[1::4] = np.clip(mask, 0, 1); ao.data.foreach_set("color", v)


def grow(mesh, seed, allowed, rings):
    """seed spread over the mesh's edges `rings` times, only into `allowed` vertices."""
    me = mesh.data
    ev = np.empty(len(me.edges) * 2, dtype=np.int64); me.edges.foreach_get("vertices", ev)
    a, b = ev.reshape(-1, 2).T
    m = seed.copy()
    for _ in range(rings):
        n = m.copy(); n[a] |= m[b]; n[b] |= m[a]
        m = n & allowed | seed
    return m


def islands(mesh):
    """Connected piece each vertex belongs to (0 = the largest), for parts modelled apart."""
    me = mesh.data; nv = len(me.vertices)
    parent = np.arange(nv)
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    ev = np.empty(len(me.edges) * 2, dtype=np.int64); me.edges.foreach_get("vertices", ev)
    for a, b in ev.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb: parent[ra] = rb
    roots = np.array([find(i) for i in range(nv)])
    ids, inv, counts = np.unique(roots, return_inverse=True, return_counts=True)
    order = np.argsort(-counts); rank = np.empty_like(order); rank[order] = np.arange(len(order))
    return rank[inv]


def export(dst, tex=2048):
    # A companion is a few hundred pixels tall: a 2K texture is plenty and keeps the app small.
    for img in bpy.data.images:
        if img.size[0] > tex: img.scale(tex, tex)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=False, export_vertex_color="ACTIVE",
                              export_image_format="JPEG", export_jpeg_quality=92)
    print("exported", dst)


def shots(rig, tests, poses, scale=2.4):
    """poses: [(file, yaw degrees, {bone: (x, y, z) degrees})] rendered orthographic."""
    os.makedirs(tests, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 600, 700
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.88, 0.92, 1)
    cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = scale
    cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
    sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN")); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(45), 0, math.radians(25)); sun.data.energy = 3
    pb = rig.pose.bones
    for b in pb: b.rotation_mode = "XYZ"
    for name, yaw, rots in poses:
        for b in pb: b.rotation_euler = (0, 0, 0)
        for k, v in rots.items(): pb[k].rotation_euler = [math.radians(a) for a in v]
        bpy.context.view_layer.update()
        a = math.radians(yaw)
        cam.location = Vector((math.sin(a) * 5, -math.cos(a) * 5, 0)); cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(tests, name); bpy.ops.render.render(write_still=True)
