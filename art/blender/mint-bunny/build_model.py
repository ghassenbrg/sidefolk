"""Reference bunny, built through BlendRelay. Standalone asset, no app changes.

Run this saved source with BlendRelay's execute_blender_python. Front is -Y;
the character stands at Z=0. Materials and every body part remain editable.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path('/Users/ghassenbrg/git/sidefolk')
OUT = ROOT / 'output/mint-bunny'
OUT.mkdir(parents=True, exist_ok=True)

# Keep the starting scene intact, including any unsaved work.
scene = bpy.data.scenes.new('Mint Bunny • Reference Model')
bpy.context.window.scene = scene
character = bpy.data.collections.new('BUNNY • editable parts')
studio = bpy.data.collections.new('STUDIO • render only')
scene.collection.children.link(character)
scene.collection.children.link(studio)

def linear(c):
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4

def material(name, rgb, roughness=.85, plush=False):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*[linear(c) for c in rgb], 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = mat.diffuse_color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Specular IOR Level'].default_value = .22
    if plush:
        bsdf.inputs['Sheen Weight'].default_value = .22
        bsdf.inputs['Sheen Roughness'].default_value = .8
        tex = nodes.new('ShaderNodeTexNoise')
        tex.name = 'Fine woven plush grain'
        tex.inputs['Scale'].default_value = 185
        tex.inputs['Detail'].default_value = 2
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .17
        bump.inputs['Distance'].default_value = .012
        links.new(tex.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
        bsdf.inputs['Subsurface Weight'].default_value = .035
    return mat

ivory = material('Plush • warm ivory', (.965, .929, .855), plush=True)
charcoal = material('Plush • charcoal ear tips', (.19, .195, .21), plush=True)
eyes = material('Face • soft black', (.135, .14, .155), .56)
mint = material('Scarf • seafoam mint', (.40, .78, .68), plush=True)
floor_mat = material('Studio • warm white', (.98, .969, .945), .96)

root = bpy.data.objects.new('Mint Bunny • move character here', None)
character.objects.link(root)
root.empty_display_type = 'PLAIN_AXES'
root.empty_display_size = .25
root['reference'] = 'ChatGPT Image Oct 24, 2026, 05_13_25 PM-2.png'
root['front_axis'] = '-Y'
root['asset_note'] = 'Separate smooth meshes; no animation rig or clips.'

def link_part(obj, name, mat, collection=character):
    obj.name = name
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    if collection == character:
        obj.parent = root
    if obj.type == 'MESH':
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj

def ellipsoid(name, loc, scale, mat, tilt=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, location=loc)
    obj = link_part(bpy.context.object, name, mat)
    obj.scale = scale
    obj.rotation_euler[1] = tilt
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj

def surface(name, func, mat, lat=64, lon=96, tip_mat=None, tip_ring=0):
    # Single poles and closed quad rings avoid degenerate duplicate pole vertices.
    verts = [func(0, 0)]
    for j in range(1, lat):
        for i in range(lon):
            verts.append(func(math.pi*j/lat, 2*math.pi*i/lon))
    verts.append(func(math.pi, 0))
    faces, regions = [], []
    for i in range(lon):
        faces.append((0, 1+i, 1+(i+1)%lon))
        regions.append(0)
    for j in range(lat-2):
        a, b = 1+j*lon, 1+(j+1)*lon
        for i in range(lon):
            k = (i+1)%lon
            faces.append((a+i, b+i, b+k, a+k))
            regions.append(j+1)
    bottom = len(verts)-1
    a = 1+(lat-2)*lon
    for i in range(lon):
        faces.append((a+i, bottom, a+(i+1)%lon))
        regions.append(lat-1)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    character.objects.link(obj)
    obj.parent = root
    mesh.materials.append(mat)
    if tip_mat:
        mesh.materials.append(tip_mat)
    for p, region in zip(mesh.polygons, regions):
        p.use_smooth = True
        if tip_mat and region < tip_ring:
            p.material_index = 1
    return obj

ellipsoid('Body • rounded bean', (0, .04, .82), (.95, .61, .78), ivory)
ellipsoid('Foot • left', (-.46, -.25, .205), (.40, .46, .205), ivory)
ellipsoid('Foot • right', (.46, -.25, .205), (.40, .46, .205), ivory)
ellipsoid('Arm • left', (-.99, -.015, .91), (.275, .30, .46), ivory, math.radians(29))
ellipsoid('Arm • right', (.99, -.015, .91), (.275, .30, .46), ivory, math.radians(-29))

def head_shape(v, u):
    c, s = math.cos(v), max(0, math.sin(v))
    z = 2.53 + .91*math.copysign(abs(c)**.80, c)
    width = 1.235*(s**.78)*(1-.095*c)
    return (width*math.cos(u), .015+.745*(s**.82)*math.sin(u), z)

head = surface('Head • broad cheeks and soft jaw', head_shape, ivory)

for side, label in [(-1, 'left'), (1, 'right')]:
    angle = side * math.radians(17)
    def ear_shape(v, u, side=side, angle=angle):
        # Warp the material boundary into a gentle oblique arc around the ear.
        v = v + .11*math.sin(v)*math.cos(u)*side
        s = max(0, math.sin(v))
        x = .435*s**.67*math.cos(u)
        y = .245*s**.8*math.sin(u)
        z = 1.055*math.cos(v)
        return (side*.79 + x*math.cos(angle)+z*math.sin(angle),
                .13+y, 3.84-x*math.sin(angle)+z*math.cos(angle))
    surface('Ear • '+label+' • integrated dark tip', ear_shape, ivory,
            lat=64, lon=64, tip_mat=charcoal, tip_ring=28)

# The tiny face sits against the curved head instead of floating in front of it.
for side, label in [(-1, 'left'), (1, 'right')]:
    ellipsoid('Eye • '+label, (side*.472, -.704, 2.36), (.128, .057, .151), eyes)
ellipsoid('Nose • tiny oval', (0, -.736, 2.255), (.052, .037, .040), eyes)

# A padded elliptical loop, with a softened rectangular cross section.
verts, faces = [], []
n, m = 128, 32
for i in range(n):
    u = 2*math.pi*i/n
    for j in range(m):
        v = 2*math.pi*j/m
        radial = .185*math.copysign(abs(math.cos(v))**.65, math.cos(v))
        height = .215*math.copysign(abs(math.sin(v))**.65, math.sin(v))
        verts.append(((.865+radial)*math.cos(u),
                      .015+(.555+radial)*math.sin(u),
                      1.53+height+.018*math.sin(u+.3)))
for i in range(n):
    for j in range(m):
        faces.append((i*m+j, ((i+1)%n)*m+j,
                      ((i+1)%n)*m+(j+1)%m, i*m+(j+1)%m))
mesh = bpy.data.meshes.new('Scarf • padded wrap')
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new(mesh.name, mesh)
character.objects.link(obj)
obj.parent = root
mesh.materials.append(mint)
for p in mesh.polygons:
    p.use_smooth = True

# Flattened pill-shaped cloth with a curved centreline and rounded end.
def scarf_end(v, u):
    t = (1-math.cos(v))/2
    w = max(0, math.sin(v))**.43
    cx = .59+.16*t+.025*math.sin(t*math.pi)
    cy = -.66-.17*math.sin(t*math.pi/2)
    return (cx+.255*w*math.cos(u), cy+.115*w*math.sin(u), 1.77-1.13*t)

surface('Scarf • long draped end', scarf_end, mint, lat=64, lon=64)
ellipsoid('Scarf • tucked short end', (.88, -.15, 1.52), (.235, .17, .24), mint, -.16)

# Studio is separate, so selecting the character exports only the model.
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.007))
link_part(bpy.context.object, 'Ground • soft contact shadow', floor_mat, studio)
world = bpy.data.worlds.new('Studio • warm ambient')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.80, .84, .90, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = .32
scene.world = world

def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat('-Z', 'Y').to_euler()

def area(name, location, power, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = power, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    studio.objects.link(obj)
    obj.location = location
    aim(obj, (0, 0, 2.3))

area('Key • large softbox', (-3.7, -4.5, 7.3), 650, 4.5, (1, .94, .86))
area('Fill • broad softbox', (4.5, -2.5, 4.7), 420, 4, (.88, .95, 1))
area('Rim • overhead', (1, 3.5, 6.5), 700, 3.5, (1, .97, .9))

data = bpy.data.cameras.new('Portrait • reference front')
cam = bpy.data.objects.new(data.name, data)
studio.objects.link(cam)
cam.location = (0, -12.5, 4.0)
aim(cam, (0, 0, 2.43))
data.type = 'ORTHO'
data.ortho_scale = 6.1
data.lens = 65
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.render.film_transparent = False
scene.render.filepath = str(OUT / 'mint-bunny-front.png')

# Pack the reference for anyone editing the blend later.
ref = Path('/Users/ghassenbrg/Downloads/Images/ChatGPT Image Oct 24, 2026, 05_13_25 PM-2.png')
if ref.exists():
    image = bpy.data.images.load(str(ref), check_existing=True)
    image.name = 'REFERENCE • supplied character'
    image.pack()

for obj in scene.objects:
    obj.select_set(False)
for obj in character.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = head
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type == 'VIEW_3D':
            ar.spaces.active.region_3d.view_perspective = 'CAMERA'
            ar.spaces.active.shading.color_type = 'MATERIAL'

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'mint-bunny.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT / 'mint-bunny.glb'), export_format='GLB',
                          use_selection=True, export_animations=False,
                          export_cameras=False, export_lights=False)
print({'blend': str(OUT / 'mint-bunny.blend'), 'glb': str(OUT / 'mint-bunny.glb'),
       'parts': len(character.objects)-1,
       'vertices': sum(len(o.data.vertices) for o in character.objects if o.type == 'MESH')})
