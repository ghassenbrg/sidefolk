"""Export the active film bunny with skinning, morphs and merged NLA clips.

Run through BlendRelay after build_film.py. Hair is a Blender render feature;
disabling its evaluation while sampling animations makes exports much faster.
"""
import bpy
from pathlib import Path

OUT=Path('/Users/ghassenbrg/git/sidefolk/output/mint-bunny-film')
scene=bpy.data.scenes['Bunny Film • character and rig']
bpy.context.window.scene=scene
character=bpy.data.collections['FILM BUNNY • character']
rig=bpy.data.objects['Film Bunny • ANIMATE HERE']
owners=[rig]+[o.data.shape_keys for o in character.objects
             if o.type=='MESH' and o.data.shape_keys and o.data.shape_keys.animation_data]
tracks=[(t,t.mute) for own in owners for t in own.animation_data.nla_tracks]
particles=[(m,m.show_viewport,m.show_render) for o in character.objects
           if o.type=='MESH' for m in o.modifiers if m.type=='PARTICLE_SYSTEM']
try:
    for t,_ in tracks: t.mute=False
    for m,_,_ in particles: m.show_viewport=False; m.show_render=False
    for o in scene.objects: o.select_set(o.name in character.objects)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(OUT/'bunny-film-rigged.glb'),
        export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',
        export_anim_single_armature=False,export_morph=True,export_extras=True)
finally:
    for t,mute in tracks: t.mute=mute
    for m,view,render in particles: m.show_viewport=view; m.show_render=render
    scene.frame_set(17)
    for o in scene.objects: o.select_set(o==rig)
    bpy.context.view_layer.objects.active=rig
print('Exported:',OUT/'bunny-film-rigged.glb')
