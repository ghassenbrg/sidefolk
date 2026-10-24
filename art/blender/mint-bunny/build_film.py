"""A fuller, furred, expressive bunny with a deform rig, built via BlendRelay.

Keeps the original version intact. Front = -Y, up = Z. Run with Blender Python.
The film file includes short hair; the GLB deliberately exports the skinned surface.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector, Quaternion

OUT = Path('/Users/ghassenbrg/git/sidefolk/output/mint-bunny-film')
OUT.mkdir(parents=True, exist_ok=True)
S = bpy.data.scenes.new('Bunny Film • character and rig')
bpy.context.window.scene = S
C = bpy.data.collections.new('FILM BUNNY • character')
ST = bpy.data.collections.new('FILM BUNNY • studio')
S.collection.children.link(C)
S.collection.children.link(ST)
parts = []

def lin(x):
    return x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4

def mat(name, rgb, rough=.7, fuzz=0):
    m = bpy.data.materials.new('Film • '+name)
    m.diffuse_color = tuple(lin(x) for x in rgb)+(1,)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = m.diffuse_color
    p.inputs['Roughness'].default_value = rough
    p.inputs['Specular IOR Level'].default_value = .3
    p.inputs['Sheen Weight'].default_value = fuzz
    return m

cream = mat('warm cream fur', (.94,.88,.76), .8, .08)
dark = mat('charcoal fur', (.095,.105,.13), .83, .04)
mint = mat('mint wool', (.27,.69,.58), .83, .12)
seam_mat = mat('mint stitching', (.36,.76,.64), .9)
eye_mat = mat('espresso eyes', (.055,.041,.032), .13)
p = eye_mat.node_tree.nodes['Principled BSDF']
p.inputs['Coat Weight'].default_value = .48
p.inputs['Coat Roughness'].default_value = .09
p.inputs['Specular IOR Level'].default_value = .48
nose_mat = mat('velvet nose', (.16,.11,.105), .4)
mouth_mat = mat('smile', (.23,.13,.11), .72)
floor_mat = mat('sand backdrop', (.79,.73,.63), .93)

# Wool has a small crossed weave in addition to the geometric seam.
nodes, links = mint.node_tree.nodes, mint.node_tree.links
tex = nodes.new('ShaderNodeTexNoise')
tex.inputs['Scale'].default_value = 120
tex.inputs['Detail'].default_value = 2
bump = nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = .28
bump.inputs['Distance'].default_value = .014
links.new(tex.outputs['Fac'], bump.inputs['Height'])
links.new(bump.outputs['Normal'], nodes['Principled BSDF'].inputs['Normal'])

def active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

def link(obj, name, material=None, col=C):
    obj.name = 'Film • '+name
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)
    if material:
        obj.data.materials.append(material)
    if obj.type == 'MESH':
        for p in obj.data.polygons:
            p.use_smooth = True
    if col == C:
        parts.append(obj)
    return obj

def ell(name, xyz, scale, material=cream, ry=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, location=xyz)
    ob = link(bpy.context.object, name, material)
    ob.scale = scale
    ob.rotation_euler[1] = ry
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return ob

def fuse(objects, name, voxel):
    parts[:] = [x for x in parts if x not in objects or x == objects[0]]
    for o in bpy.context.view_layer.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    ob = objects[0]
    ob.name = 'Film • '+name
    rem = ob.modifiers.new('Continuous sculpted volume', 'REMESH')
    rem.mode = 'VOXEL'
    rem.voxel_size = voxel
    rem.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=rem.name)
    sm = ob.modifiers.new('Relax sculpt', 'SMOOTH')
    sm.factor = .65
    sm.iterations = 5
    bpy.ops.object.modifier_apply(modifier=sm.name)
    # Keep one predictable material after joining primitive volumes.
    ob.data.materials.clear()
    ob.data.materials.append(cream)
    for p in ob.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    return ob

body_parts = [ell('torso volume', (0,.06,1.10), (.86,.65,.89)),
              ell('hips volume', (0,.06,.65), (.79,.61,.52)),
              ell('neck volume', (0,.06,1.81), (.50,.43,.36))]
for side in [-1,1]:
    body_parts += [ell('shoulder volume', (side*.69,.025,1.52), (.33,.38,.42)),
                   ell('arm volume', (side*.94,-.035,1.14), (.28,.31,.46), ry=-side*.18),
                   ell('paw volume', (side*1.00,-.14,.88), (.29,.33,.31)),
                   ell('haunch volume', (side*.46,.06,.57), (.37,.43,.49)),
                   ell('foot volume', (side*.46,-.25,.25), (.41,.50,.245))]
body = fuse(body_parts, 'Skin • continuous torso arms and feet', .045)

head_main = ell('head volume', (0,.005,2.68), (1.18,.76,.91))
# A domed forehead, soft cheeks, and a gentle muzzle rather than a squared block.
for v in head_main.data.vertices:
    z = v.co.z/.91
    if z < 0:
        v.co.z = -.91*abs(z)**.81
        v.co.x *= 1+.055*(-z)
head = fuse([head_main,
             ell('cheek volume L', (-.35,-.53,2.30), (.49,.32,.31)),
             ell('cheek volume R', (.35,-.53,2.30), (.49,.32,.31))],
            'Head • rounded forehead cheeks and muzzle', .032)

def uv_surface(name, func, material, lat=48, lon=64, secondary=None, split=0):
    vs = [func(0,0)]
    for j in range(1,lat):
        for i in range(lon):
            vs.append(func(math.pi*j/lat, 2*math.pi*i/lon))
    vs.append(func(math.pi,0))
    fs, regs = [], []
    for i in range(lon):
        fs.append((0,1+i,1+(i+1)%lon)); regs.append(0)
    for j in range(lat-2):
        a,b=1+j*lon,1+(j+1)*lon
        for i in range(lon):
            k=(i+1)%lon
            fs.append((a+i,b+i,b+k,a+k)); regs.append(j+1)
    a=1+(lat-2)*lon
    for i in range(lon):
        fs.append((a+i,len(vs)-1,a+(i+1)%lon)); regs.append(lat-1)
    mesh=bpy.data.meshes.new('Film • '+name)
    mesh.from_pydata(vs,[],fs); mesh.update()
    obj=bpy.data.objects.new(mesh.name,mesh); C.objects.link(obj); parts.append(obj)
    mesh.materials.append(material)
    if secondary: mesh.materials.append(secondary)
    for p,r in zip(mesh.polygons,regs):
        p.use_smooth=True
        p.material_index=int(bool(secondary and r<split))
    return obj

ears=[]
for side,label in [(-1,'L'),(1,'R')]:
    angle=side*math.radians(16)
    def ear_func(v,u,side=side,angle=angle):
        v=v+.09*math.sin(v)*math.cos(u)*side
        sn=max(0,math.sin(v))
        x=.385*sn**.74*math.cos(u)
        y=.225*sn**.8*math.sin(u)
        z=.93*math.cos(v)
        return (side*.73+x*math.cos(angle)+z*math.sin(angle), .14+y,
                3.99-x*math.sin(angle)+z*math.cos(angle))
    ear=uv_surface('Ear.'+label,ear_func,cream,secondary=dark,split=20)
    ears.append(ear)

tail=ell('Tail • little cotton tuft', (0,.64,.76), (.32,.29,.32))

def stroke(name, points, radius, material, mesh=True):
    data=bpy.data.curves.new('Film • '+name,'CURVE')
    data.dimensions='3D'; data.resolution_u=20
    data.bevel_depth=radius; data.bevel_resolution=3
    sp=data.splines.new('BEZIER'); sp.bezier_points.add(len(points)-1)
    for p,co in zip(sp.bezier_points,points):
        p.co=co; p.handle_left_type=p.handle_right_type='AUTO'
    ob=bpy.data.objects.new(data.name,data); C.objects.link(ob); parts.append(ob)
    data.materials.append(material)
    if mesh:
        active(ob); bpy.ops.object.convert(target='MESH')
    return ob

face=[]; eyes=[]; lids=[]
for side,label in [(-1,'L'),(1,'R')]:
    x=side*.445
    eye=ell('Eye.'+label+' • glossy', (x,-.711,2.64), (.178,.119,.217),eye_mat)
    eye.rotation_euler[2]=side*.12
    eye.shape_key_add(name='Basis')
    blink=eye.shape_key_add(name='Blink',from_mix=False)
    for v in blink.data:
        v.co.z*=.035
        v.co.y+=.055
    blink.value=0
    happy=eye.shape_key_add(name='Happy',from_mix=False)
    for v in happy.data:
        v.co.z=.88*v.co.z+.018
    happy.value=0
    eyes.append(eye); face.append(eye)
    lid=stroke('Upper eyelid.'+label,
        [(x-.155,-.716,2.74),(x,-.749,2.854),(x+.155,-.716,2.74)],.025,cream)
    lid.shape_key_add(name='Basis')
    blink=lid.shape_key_add(name='Blink',from_mix=False)
    for v in blink.data: v.co.z=2.64+.12*(v.co.z-2.64)
    blink.value=0
    lids.append(lid); face.append(lid)
    face.append(stroke('Brow.'+label,
        [(x-.13,-.64,2.985),(x,-.674,3.014),(x+.13,-.64,2.99)],.022,dark))

nose=ell('Nose • soft triangle', (0,-.849,2.365), (.085,.064,.057),nose_mat)
for v in nose.data.vertices:
    v.co.x*=.73+.27*(v.co.z/.057)
face.append(nose)
face.append(stroke('Philtrum',[(0,-.881,2.34),(0,-.889,2.28)],.012,mouth_mat))
mouth=stroke('Smile • expression control',
    [(-.18,-.831,2.29),(-.10,-.878,2.245),(0,-.891,2.277),(.10,-.878,2.245),(.18,-.831,2.29)],.014,mouth_mat)
mouth.shape_key_add(name='Basis')
smile=mouth.shape_key_add(name='Smile',from_mix=False)
for v in smile.data:
    v.co.z += .08*min(1,abs(v.co.x)/.18)**1.5
smile.value=.25
face.append(mouth)

# The scarf is soft fabric with shallow folds, thin edges and a stitched hem.
verts,faces=[],[]
nu,nv=96,24
for i in range(nu):
    u=2*math.pi*i/nu
    for j in range(nv):
        v=2*math.pi*j/nv
        rr=.145*math.copysign(abs(math.cos(v))**.65,math.cos(v))
        zz=.165*math.copysign(abs(math.sin(v))**.65,math.sin(v))
        fold=.012*math.sin(5*u+v)+.009*math.sin(9*u-2*v)
        verts.append(((.78+rr+fold)*math.cos(u),(.49+rr+fold)*math.sin(u),1.865+zz+.018*math.cos(3*u)))
for i in range(nu):
    for j in range(nv):
        faces.append((i*nv+j,((i+1)%nu)*nv+j,((i+1)%nu)*nv+(j+1)%nv,i*nv+(j+1)%nv))
me=bpy.data.meshes.new('Film • scarf collar'); me.from_pydata(verts,[],faces); me.update()
scarf=bpy.data.objects.new(me.name,me); C.objects.link(scarf); me.materials.append(mint); parts.append(scarf)
for p in me.polygons: p.use_smooth=True

def cloth_point(t,u):
    width=.245*(.95+.05*math.sin(math.pi*t))
    # Round the two lower corners while leaving a substantial straight hem.
    if t>.91: width*=math.sqrt(max(.35,1-((t-.91)/.13)**2))
    x=.60+.15*t+width*u
    y=-.62-.17*math.sin(math.pi*t*.75)+.028*math.sin(3*math.pi*u+2*t)+.02*u*u
    z=2.00-1.00*t+.035*u+.025*math.sin(math.pi*t)
    return (x,y,z)

vs=[]; fs=[]; rows,cols=24,12
for j in range(rows+1):
    for i in range(cols+1): vs.append(cloth_point(j/rows,-1+2*i/cols))
for j in range(rows):
    for i in range(cols):
        a=j*(cols+1)+i; fs.append((a,a+1,a+cols+2,a+cols+1))
me=bpy.data.meshes.new('Film • flowing scarf'); me.from_pydata(vs,[],fs); me.update()
drape=bpy.data.objects.new(me.name,me); C.objects.link(drape); me.materials.append(mint); parts.append(drape)
sol=drape.modifiers.new('Real fabric thickness','SOLIDIFY'); sol.thickness=.065
sub=drape.modifiers.new('Soft fabric folds','SUBSURF'); sub.levels=2
hem=[]
for u in [-.91,.91]:
    points=[]
    for j in range(17):
        co=Vector(cloth_point(.04+.90*j/16,u)); co.y-=.04; points.append(co)
    hem.append(stroke('Scarf • edge stitch',points,.007,seam_mat))
points=[]
for i in range(15):
    co=Vector(cloth_point(.945,-.80+1.60*i/14)); co.y-=.04; points.append(co)
hem.append(stroke('Scarf • bottom hem',points,.009,seam_mat))

# Deformation skeleton: controls remain simple FK bones with descriptive names.
ad=bpy.data.armatures.new('Film Bunny • deform skeleton')
rig=bpy.data.objects.new('Film Bunny • ANIMATE HERE',ad); C.objects.link(rig)
rig.show_in_front=False; ad.display_type='STICK'
active(rig); bpy.ops.object.mode_set(mode='EDIT')
bones={}
def bone(name,a,b,parent=None):
    eb=ad.edit_bones.new(name); eb.head=a; eb.tail=b
    if parent: eb.parent=ad.edit_bones[parent]
    bones[name]=(Vector(a),Vector(b))
    return eb

bone('Root',(0,0,0),(0,0,.3))
bone('Pelvis',(0,.06,.60),(0,.06,1.02),'Root')
bone('Spine',(0,.06,1.02),(0,.06,1.43),'Pelvis')
bone('Chest',(0,.06,1.43),(0,.06,1.84),'Spine')
bone('Neck',(0,.06,1.84),(0,.03,2.16),'Chest')
bone('Head',(0,.03,2.16),(0,.03,3.25),'Neck')
bone('Tail',(0,.52,.76),(0,.91,.85),'Pelvis')
for side,label in [(-1,'L'),(1,'R')]:
    bone('UpperArm.'+label,(side*.64,.025,1.58),(side*.91,-.035,1.15),'Chest')
    bone('Forearm.'+label,(side*.91,-.035,1.15),(side*1.00,-.14,.91),'UpperArm.'+label)
    bone('Paw.'+label,(side*1.00,-.14,.91),(side*1.00,-.20,.70),'Forearm.'+label)
    bone('Thigh.'+label,(side*.43,.06,.75),(side*.46,.03,.43),'Pelvis')
    bone('Shin.'+label,(side*.46,.03,.43),(side*.46,-.12,.25),'Thigh.'+label)
    bone('Foot.'+label,(side*.46,-.12,.25),(side*.46,-.56,.20),'Shin.'+label)
    bone('Ear.'+label,(side*.51,.14,3.23),(side*.73,.14,3.99),'Head')
    bone('EarTip.'+label,(side*.73,.14,3.99),(side*.98,.14,4.86),'Ear.'+label)
    bone('Eye.'+label,(side*.445,-.711,2.64),(side*.445,-.94,2.64),'Head')
bone('Scarf.01',(.59,-.63,1.99),(.67,-.75,1.55),'Chest')
bone('Scarf.02',(.67,-.75,1.55),(.75,-.78,1.02),'Scarf.01')
bpy.ops.object.mode_set(mode='OBJECT')
for pb in rig.pose.bones: pb.rotation_mode='XYZ'

def bind(obj,weights):
    # Weights is evaluated in rest-world coordinates so all meshes share the rig.
    groups={}
    for v in obj.data.vertices:
        ww=weights(obj.matrix_world@v.co)
        total=sum(ww.values())
        for name,w in ww.items():
            if w<=.00001: continue
            if name not in groups: groups[name]=obj.vertex_groups.new(name=name)
            groups[name].add([v.index],w/total,'REPLACE')
    mod=obj.modifiers.new('Character deformation','ARMATURE'); mod.object=rig
    # Apply armature before subdivision; hair later follows the deformed surface.
    active(obj)
    while list(obj.modifiers).index(mod)>0:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    obj.parent=rig

def fixed(name): return lambda p:{name:1}
def distance_segment(p,a,b):
    ab=b-a; t=max(0,min(1,(p-a).dot(ab)/ab.length_squared))
    return (p-(a+t*ab)).length

def body_weights(p):
    # Continuous capsule weights avoid a hard seam between the paw and hip.
    side='L' if p.x<0 else 'R'
    radii={'Pelvis':.64,'Spine':.61,'Chest':.56,'Neck':.42,
           'UpperArm.'+side:.29,'Forearm.'+side:.28,'Paw.'+side:.30,
           'Thigh.'+side:.35,'Shin.'+side:.31,'Foot.'+side:.40}
    ds=sorted([(distance_segment(p,*bones[n])/r,n) for n,r in radii.items()])[:4]
    return {n:1/(d+.12)**8 for d,n in ds}

bind(body,body_weights); bind(head,fixed('Head')); bind(tail,fixed('Tail'))
for ear,label in zip(ears,['L','R']):
    def ear_weights(p,label=label):
        t=max(0,min(1,(p.z-3.65)/.72)); t=t*t*(3-2*t)
        return {'Ear.'+label:1-t,'EarTip.'+label:t}
    bind(ear,ear_weights)
for obj in face:
    name='Eye.'+('L' if '.L' in obj.name else 'R') if obj in eyes else 'Head'
    bind(obj,fixed(name))
bind(scarf,fixed('Chest'))
def scarf_weights(p):
    t=max(0,min(1,(1.70-p.z)/.40))
    return {'Scarf.01':1-t,'Scarf.02':t}
for obj in [drape]+hem: bind(obj,scarf_weights)
for obj in [body,head]+ears:
    sub=obj.modifiers.new('Film silhouette smoothing','SUBSURF'); sub.levels=1; sub.render_levels=1

# Real short hair, with a sparse facial area so eyes and muzzle stay readable.
def fur(obj,length,count,material=1,region=None):
    active(obj)
    density=obj.vertex_groups.new(name='Fur density '+str(material))
    material_vertices={v.index:[] for v in obj.data.vertices}
    if region:
        for poly in obj.data.polygons:
            for vi in poly.vertices: material_vertices[vi].append(poly.material_index)
    for v in obj.data.vertices:
        p=obj.matrix_world@v.co
        w=1.0
        if obj==head and p.y<-.38 and abs(p.x)<.82 and 2.10<p.z<2.97: w=.12
        if region:
            indices=material_vertices[v.index]
            tip=sum(indices)/max(1,len(indices))
            w*=tip if region=='tip' else 1-tip
        density.add([v.index],w,'REPLACE')
    bpy.ops.object.particle_system_add()
    system=obj.particle_systems[-1]
    system.vertex_group_density=density.name
    st=system.settings; st.name='Film fur • '+obj.name+' '+str(material)
    st.type='HAIR'; st.count=count; st.hair_length=length; st.hair_step=3
    st.child_type='INTERPOLATED'; st.child_percent=5; st.rendered_child_count=12
    st.root_radius=.0022; st.tip_radius=.00045; st.radius_scale=.65
    st.roughness_1=.003; st.roughness_endpoint=.004; st.clump_factor=.025
    st.material=material; st.use_modifier_stack=True
    return system

fur(body,.038,5000); fur(head,.034,6000); fur(tail,.065,1200)
for ear in ears:
    fur(ear,.018,1800,1,'base'); fur(ear,.018,1500,2,'tip')

# Named NLA tracks merge rig motion and facial blinks into the same exported clip.
def store_action(owner,name):
    anim=owner.animation_data; act=anim.action; act.name='Film '+name+' • '+owner.name
    act.use_fake_user=True
    tr=anim.nla_tracks.new(); tr.name=name
    strip=tr.strips.new(name,1,act)
    strip.blend_type='REPLACE'; strip.extrapolation='NOTHING'
    anim.action=None
    return tr,act

tracks=[]
for clip,end in [('Idle',97),('Hello',73)]:
    rig.animation_data_create()
    for f in range(1,end+1,4):
        t=(f-1)/(end-1); wave=math.sin(t*2*math.pi)
        for pb in rig.pose.bones:
            pb.location=(0,0,0); pb.rotation_euler=(0,0,0); pb.scale=(1,1,1)
        rig.pose.bones['Spine'].scale=(1+.013*wave,1+.013*wave,1+.019*wave)
        rig.pose.bones['Head'].rotation_euler=(.025*math.sin(t*2*math.pi+.4),.075+.025*wave,-.035)
        rig.pose.bones['Ear.L'].rotation_euler[0]=.035*math.sin(t*2*math.pi-.4)
        rig.pose.bones['EarTip.L'].rotation_euler[1]=-.07+.04*math.sin(t*2*math.pi-.8)
        rig.pose.bones['Ear.R'].rotation_euler[0]=-.035*math.sin(t*2*math.pi-.4)
        rig.pose.bones['EarTip.R'].rotation_euler[1]=.05+.04*math.sin(t*2*math.pi-.9)
        rig.pose.bones['Scarf.01'].rotation_euler[0]=.025*math.sin(t*2*math.pi-.7)
        rig.pose.bones['Scarf.02'].rotation_euler[1]=.04*math.sin(t*2*math.pi-1)
        if clip=='Hello':
            lift=math.sin(math.pi*t)**.7
            for name,angle in [('UpperArm.R',-1.65*lift),('Forearm.R',-.48*lift)]:
                q=rig.data.bones[name].matrix_local.to_quaternion()
                rig.pose.bones[name].rotation_euler=(q.inverted()@Quaternion((0,1,0),angle)@q).to_euler('XYZ')
            rig.pose.bones['Paw.R'].rotation_euler[0]=.3*math.sin(t*8*math.pi)*lift
            rig.pose.bones['Head'].rotation_euler[1]+=.06*lift
        for pb in rig.pose.bones:
            pb.keyframe_insert('location',frame=f,group=pb.name)
            pb.keyframe_insert('rotation_euler',frame=f,group=pb.name)
            pb.keyframe_insert('scale',frame=f,group=pb.name)
    tracks.append(store_action(rig,clip))
    for eye in eyes+lids:
        keys=eye.data.shape_keys
        for f,val in [(1,0),(33,0),(36,1),(39,0),(end,0)]:
            keys.key_blocks['Blink'].value=val
            keys.key_blocks['Blink'].keyframe_insert('value',frame=f)
        tracks.append(store_action(keys,clip))

for track,act in tracks: track.mute=(track.name!='Idle')
rig['How to animate']='Pose bones in Pose Mode. Idle / Hello in NLA. Face keys: Blink, Happy, Smile.'
rig['Fur export']='Short hair stays in Blender; GLB contains the skinned PBR surface.'
rig['Rig level']='Basic FK deform rig with smooth weights; refine extreme poses before production.'

def aim(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015))
floor=link(bpy.context.object,'Ground',floor_mat,ST)
back_points=[(-20,0),(4,0)]
for j in range(1,25):
    a=(math.pi/2)*j/24
    back_points.append((4+4*math.sin(a),4*(1-math.cos(a))))
back_points.append((8,15))
vs=[(x,y,z-.014) for y,z in back_points for x in [-20,20]]
fs=[(2*j,2*j+1,2*j+3,2*j+2) for j in range(len(back_points)-1)]
mesh=bpy.data.meshes.new('Film • cyclorama'); mesh.from_pydata(vs,[],fs); mesh.update()
back=bpy.data.objects.new(mesh.name,mesh); ST.objects.link(back); mesh.materials.append(floor_mat)
for p in mesh.polygons: p.use_smooth=True
world=bpy.data.worlds.new('Film • soft daylight'); world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.72,.80,1,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.23
S.world=world
for name,xyz,energy,size,color in [
    ('Key',(-3.5,-4.5,6.2),780,3.0,(1,.86,.68)),
    ('Fill',(3.5,-4,3.3),250,3.5,(.78,.88,1)),
    ('Rim',(1.5,2.8,5.2),1100,2.5,(1,.86,.67))]:
    data=bpy.data.lights.new('Film • '+name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
    ob=bpy.data.objects.new(data.name,data); ST.objects.link(ob); ob.location=xyz; aim(ob,(0,0,2.3))
data=bpy.data.cameras.new('Film • portrait'); cam=bpy.data.objects.new(data.name,data); ST.objects.link(cam)
cam.location=(3.3,-12,4.0); aim(cam,(0,0,2.42)); data.lens=68
data.dof.use_dof=True; data.dof.focus_distance=(cam.location-Vector((0,-.3,2.6))).length; data.dof.aperture_fstop=8
S.camera=cam
S.render.engine='CYCLES'; S.cycles.samples=96; S.cycles.use_denoising=True
S.render.resolution_x=S.render.resolution_y=1200; S.render.resolution_percentage=100
S.render.image_settings.file_format='PNG'; S.render.fps=24
S.view_settings.view_transform='AgX'; S.view_settings.look='AgX - Medium High Contrast'; S.view_settings.exposure=.3
S.render.filepath=str(OUT/'bunny-film-portrait.png'); S.frame_start=1; S.frame_end=97
S.frame_set(17)

ref=bpy.data.images.get('REFERENCE • supplied character')
if ref and not ref.packed_file: ref.pack()
for view_layer in S.view_layers:
    for ob in view_layer.objects: ob.select_set(ob==rig,view_layer=view_layer)
    view_layer.objects.active=rig
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.color_type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bunny-film.blend'),check_existing=False)
print({'file':str(OUT/'bunny-film.blend'),'bones':len(ad.bones),'mesh_parts':len([o for o in C.objects if o.type=='MESH']),'hair_systems':sum(len(o.particle_systems) for o in C.objects if o.type=='MESH')})
