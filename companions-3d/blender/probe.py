# Ad-hoc numbers for one model: run with an expression file. blender -b -P probe.py -- <glb> <script.py>
import bpy, sys
import numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
o = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
me = o.data
co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
nv = len(co); x, y, z = co.T
img = [n for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE"][0].image
uv = np.zeros((nv, 2))
lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
luv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", luv)
uv[lv] = luv.reshape(-1, 2)
w, h = img.size
px = np.array(img.pixels[:]).reshape(h, w, -1)
col = px[np.clip((uv[:, 1] % 1) * (h - 1), 0, h - 1).astype(int), np.clip((uv[:, 0] % 1) * (w - 1), 0, w - 1).astype(int), :3] ** (1 / 2.2)
r, g, b = col.T
def rng(m, name):
    if not m.any(): print(name, "none"); return
    print(f"{name}: n={m.sum()} x[{x[m].min():+.3f},{x[m].max():+.3f}] y[{y[m].min():+.3f},{y[m].max():+.3f}] z[{z[m].min():+.3f},{z[m].max():+.3f}]")
exec(open(argv[1]).read())
