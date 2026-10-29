# Renders a raw model from the front, three-quarter, side and back into one strip, for review.
# blender -b -P look.py -- <in.glb> <out.png>
import bpy, sys, math, os
from mathutils import Vector
src, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 500, 560
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.88, 0.92, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.4
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 2.2
cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
files = []
for i, yaw in enumerate((0, 35, 90, 180)):
    a = math.radians(yaw)
    cam.location = Vector((math.sin(a) * 5, -math.cos(a) * 5, 0)); cam.rotation_euler = (math.radians(90), 0, a)
    f = f"{out}.{i}.png"; scene.render.filepath = f; bpy.ops.render.render(write_still=True); files.append(f)
img = [bpy.data.images.load(f) for f in files]
