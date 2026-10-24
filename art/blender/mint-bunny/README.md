# Mint bunny reference model

Standalone character requested on 24 October 2026, modeled in Blender 5.2 through
BlendRelay MCP from the supplied cream bunny / charcoal ear tips / mint scarf image.
This does not change the Sidefolk companion or its sprite pipeline.

## Film character revision

The user requested a fuller, expressive character that feels alive and can be
animated. The revised version is in `output/mint-bunny-film/`:

- `bunny-film.blend`: rounded sculpted torso, freely deforming arms and paws,
  cheek/muzzle forms, glossy eyes, short geometric hair, a thin folded wool scarf
  with seams, portrait lighting and a seamless backdrop.
- `bunny-film-rigged.glb`: 21 skinned meshes, seven PBR materials, one 27-bone rig,
  two animation clips (`Idle`, `Hello`), and facial morph targets.
- `bunny-film-portrait.png`: final Cycles portrait.
- `bunny-film-wave.png`: raised-paw pose used to check shoulder deformation.
- `bunny-film-motion.mp4` / `.gif`: small rendered greeting preview.
- `mesh-validation.json`, `skin-validation.json`, `glb-validation.json`: checks.

Use `Film Bunny • ANIMATE HERE` in Pose Mode. Bones are named for the torso, head,
eyes, ears and ear tips, upper arms, forearms, paws, legs, feet, tail and scarf.
The NLA editor contains `Idle` (breathing, ear/scarf follow-through, blink) and
`Hello` (raised-paw greeting). The default is Idle. To switch, mute Idle and unmute
Hello on the rig and eye/lid shape-key NLA tracks. The GLB merges the corresponding
tracks into two complete clips. Eye morphs: `Blink`, `Happy`; mouth: `Smile`.

This is a basic FK deformation rig. The checked greeting and idle poses work;
extreme poses and a full facial/speech system need further character work. The
short fur and procedural weave are Blender render features and are not in GLB.

Rebuild through BlendRelay with `build_film.py`, then `export_film.py` and
`render_film.py`. The render script makes a full portrait and 36 small motion frames.
Export disables particle evaluation temporarily while sampling animation, then
restores it. The original static version below remains intact.

## Files

Generated files are in `output/mint-bunny/` (gitignored):

- `mint-bunny.blend`: editable model, four character materials, procedural plush
  grain, packed reference image, portrait camera and studio lighting.
- `mint-bunny.glb`: character only, 14 separate meshes under one root, four PBR
  materials, 44,730 vertices / 89,408 triangles. Procedural grain stays in Blender.
- `mint-bunny-front.png` and `mint-bunny-three-quarter.png`: Cycles previews.

The front faces -Y, Z is up, and the feet rest at Z=0. Move the root empty to move
all parts together. This is a static model, without an armature or animation clips.
Back and side shapes are inferred from the single front reference.

## Rebuild

Execute `build_model.py` through BlendRelay's `execute_blender_python` tool.
It creates a separate scene and saves the blend and character-only GLB. Use
`bpy.ops.render.render(write_still=True)` to render the front camera afterward.
Paths at the top of the script target this checkout and the supplied reference.

Verified in BlendRelay: all 14 character meshes have zero boundary or non-manifold
edges, zero degenerate faces or edges, and no non-finite vertex coordinates.
The GLB JSON was inspected to confirm 14 meshes, four materials, no studio objects,
and no default cube. Front and three-quarter renders were visually inspected.
