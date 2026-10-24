# Mint bunny reference model

Standalone character requested on 24 October 2026, modeled in Blender 5.2 through
BlendRelay MCP from the supplied cream bunny / charcoal ear tips / mint scarf image.
This does not change the Sidefolk companion or its sprite pipeline.

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
