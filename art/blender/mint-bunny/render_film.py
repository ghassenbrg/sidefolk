"""Render the final portrait and a small, genuine rig-animation preview.

The preview frames are the Hello clip sampled at 12 fps, rendered in Cycles.
Encode the ordered PNGs with ffmpeg; leave the editable scene on the Idle clip.
"""
import bpy
from pathlib import Path

OUT=Path('/Users/ghassenbrg/git/sidefolk/output/mint-bunny-film')
frames=OUT/'motion-frames'
frames.mkdir(exist_ok=True)
s=bpy.data.scenes['Bunny Film • character and rig']
bpy.context.window.scene=s
c=bpy.data.collections['FILM BUNNY • character']
rig=bpy.data.objects['Film Bunny • ANIMATE HERE']
owners=[rig]+[o.data.shape_keys for o in c.objects
             if o.type=='MESH' and o.data.shape_keys and o.data.shape_keys.animation_data]

def clip(name):
    for owner in owners:
        for t in owner.animation_data.nla_tracks: t.mute=(t.name!=name)

clip('Idle'); s.frame_set(17)
s.render.engine='CYCLES'; s.cycles.samples=128
s.render.resolution_x=s.render.resolution_y=1200; s.render.resolution_percentage=100
s.render.filepath=str(OUT/'bunny-film-portrait.png')
bpy.ops.render.render(write_still=True,scene=s.name)

children=[(ps.settings,ps.settings.rendered_child_count) for o in c.objects
          if o.type=='MESH' for ps in o.particle_systems]
try:
    clip('Hello')
    for st,_ in children: st.rendered_child_count=6
    s.render.resolution_x=s.render.resolution_y=400; s.cycles.samples=16
    for frame in range(2,74,2):
        s.frame_set(frame)
        s.render.filepath=str(frames/f'hello_{frame:04d}.png')
        bpy.ops.render.render(write_still=True,scene=s.name)
finally:
    for st,n in children: st.rendered_child_count=n
    clip('Idle'); s.frame_set(17)
    s.render.resolution_x=s.render.resolution_y=1200; s.cycles.samples=128
    s.render.filepath=str(OUT/'bunny-film-portrait.png')
    for ob in s.objects: ob.select_set(ob==rig)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bunny-film.blend'),check_existing=False)
print('Rendered portrait and 36 motion frames.')
