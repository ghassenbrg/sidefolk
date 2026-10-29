# Prints horizontal slices of a Meshy model (x clusters, depth range, mean texture colour per
# cluster) so joints and colour zones can be placed by numbers.
# blender -b -P measure.py -- <in.glb> [step]
import bpy, sys
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
src = argv[0]; step = float(argv[1]) if len(argv) > 1 else 0.05
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
o = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
me = o.data
co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
nv = len(co)
img = [n for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE"][0].image
uv = np.zeros((nv, 2))
lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
luv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", luv)
uv[lv] = luv.reshape(-1, 2)
w, h = img.size
px = np.array(img.pixels[:]).reshape(h, w, -1)
col = px[np.clip((uv[:, 1] % 1) * (h - 1), 0, h - 1).astype(int), np.clip((uv[:, 0] % 1) * (w - 1), 0, w - 1).astype(int), :3] ** (1 / 2.2)
print("bounds min", co.min(0).round(3), "max", co.max(0).round(3), "verts", nv)

def clusters(idx, gap=0.03):
    order = idx[np.argsort(co[idx, 0])]; xs = co[order, 0]; out = []; s = 0
    for i in range(1, len(xs)):
        if xs[i] - xs[i - 1] > gap: out.append(order[s:i]); s = i
    out.append(order[s:]); return out

zs = np.arange(co[:, 2].max(), co[:, 2].min() - 1e-3, -step)
for z in zs:
    sel = np.nonzero(np.abs(co[:, 2] - z) < 0.012)[0]
    if len(sel) == 0: continue
    parts = []
    for c in clusters(sel):
        m = (col[c].mean(0) * 255).astype(int)
        parts.append(f"[{co[c,0].min():+.3f},{co[c,0].max():+.3f} y{co[c,1].min():+.2f}..{co[c,1].max():+.2f} #{m[0]:02x}{m[1]:02x}{m[2]:02x}]")
    print(f"z={z:+.2f} " + " ".join(parts))
