# Production handoff

## What exists today

The app has three built-in GLBs (bunny, cat, fox), seven palettes and four optional accessories. Runtime rendering uses three.js skeletal animation and a shared toon material. A 2D picture cannot be imported as a pet. An imported GLB's custom shader is replaced by the loader, so a distinct cel-shading style needs renderer work, not only a new file.

The latest shared status also records a dashboard with Home, Activity, Crew, Reminders, Agents, Settings and help, plus larger text/calm/sound controls. The UI concepts in this package are a proposed visual and interaction refinement of that work, not a claim those surfaces are absent. Reconcile with the latest implementation before changing navigation or settings.

Authoritative sources: [hero spec](../art/HERO.md), [creator contract](../docs/CREATORS.md), [loader](../src/pet/model.ts), [look definitions](../src/pet/look.ts), [clips](../src/pet/clips.ts), [roadmap](../docs/ROADMAP.md).

The rig has **16 named bones** (some roadmap prose says 15): `root`, `hips`, `chest`, `head`, `earL`, `earLTip`, `earR`, `earRTip`, `eyeL`, `eyeR`, `armL`, `armR`, `legL`, `legR`, `tail`. Follow the loader's names. Required clips: `idle`, `walk`, `sit`, `sleep`, `wave`, `think`, `read`, `work`, `celebrate`, `alert`, `sad`, `dangle`, `fall`.

## Separate identity from presentation

Proposed model: one character ID, an art-family ID and a renderer type. `byte + ink + sprite` and `byte + soft-3d + glb` share their name, project bindings, journal and state. Existing `PetRecord.look` has species/palette/accessory only; do not silently write proposed fields into persisted records without a migration.

Introduce a renderer adapter only when implementing 2D. The state machine should call common operations such as play state, set gaze, set position, hit test and dispose. A GLB implementation can wrap the existing pet; a sprite implementation can map those operations to authored frames. Keep routing, approvals, labels and the status light outside the style-specific asset. Switching style must preserve session ownership and pending requests.

## 3D deliverables per character

- Front, side, back and three-quarter orthographic model sheet; neutral expression plus alert and sad faces.
- Editable Blender source and validated binary GLB; `Body` and `Face` skinned meshes, full named rig and 13 clips.
- Feet at y=0, facing +z, approximately 2.5 units tall. Preserve identity rest rotations and blink weighting from the creator contract.
- Every clip keys every required bone. Alert puts the sign in the right hand. Verify accessories, orbiting light, click bounds and floor contact in the actual app.
- Proposed starting budget: under 8k triangles and 2 MB per pet, no simulated fur/cloth, preferably no textures. These are authoring targets, not measured runtime limits; current import limit remains 20 MB.
- Sheep/turtle/robot shapes need pose review. Non-ear characters can retain required joints without visible ear geometry; confirm they do not deform unrelated parts. Do not assume a valid bone list guarantees good animation.

## Proposed 2D deliverables per character

Transparent lossless sprite atlases plus an explicit manifest: state name, atlas rectangle, frame count, fps, loop/once, consistent feet pivot, hit area, right-hand prop anchor, and head/orb anchor. Include all 13 state names, even where a static pose is sufficient. Support left/right facing; review asymmetric accessories instead of blindly mirroring text or signs.

Begin with 256 px square authoring frames at 2× the normal desktop size. Suggested 6–12 fps animation, 2–8 frames for quiet loops; exact timing follows an animation pass. Keep one-frame reduced-motion poses. Trim frames with stored offsets, not moving pivots. Load only the active pet's necessary atlases; budget decoded texture memory (width × height × 4), not just compressed PNG size. Verify click-through around transparent pixels.

These specs are a proposal. No manifest loader, sprite renderer or finished atlas is included here.

## Corrections from generated concepts

1. Soft 3D adds fur texture and expressive faces inside some status orbs. Use the shapes as reference; remove fiber detail and keep the production orb a simple state light. Pip's proportions should converge back to `art/HERO.md` before modeling.
2. Ink & Geek has watercolor/paper flavor and extra clothes or tool belts. Final desktop assets need flat, clean alpha and fewer costume details. Keep the richer treatment for promotional illustration only.
3. Anime Byte/Patch are shown seated or on four legs. The current shared clips expect upright arms and legs: redraw upright model sheets for a GLB adaptation. Sora/Yuna are taller than the intended pocket proportions; reduce them toward 2.5 heads tall before production.
4. Anime status orbs contain decorative glyphs. Replace them with the shared state light and real badge labels; decorative symbols must not become a second status vocabulary.
5. The design-system image is a visual sketch. Its lettering, spacing, mock session IDs and states are not actual app output. The generated den portraits drift (Byte looks like an otter, Patch like a cat); replace with the roster's cat and fox. Its colored badges also drift from the runtime orb palette. Implement from the written component rules and tokens, not by slicing the image. The image's font suggestion is incidental; the written spec uses the system font stack.
6. Logo concepts are raster proposals. Final master needs vector reconstruction, optical spacing, monochrome variants, tiny-size review and platform exports. No identity change is applied to current app icons.

## Suggested delivery order

1. The user selected Pip Signal. Keep that brand direction; choose a first character production set. Recommended: the existing trio first, followed by Slate or Dot for work.
2. Refine the bunny/cat/fox model sheets and exact palettes first; these have existing runtime bases.
3. Produce one new 3D species (Relay or Loom), verify the whole animation contract, then measure a main pet plus three active crew pets on an awake machine.
4. Build a minimal renderer adapter and one complete Ink Pip sprite set. Verify status, approvals, hit testing, sleep/hidden behavior and memory before expanding the family.
5. Add Pocket Anime as a separate art pack once proportions and state readability are proved. Start with Pip/Byte/Patch rather than three new humanoid rigs.
6. Ship additional crew characters incrementally. Keep signing, release work and the existing roadmap priorities in view.

## Review checklist

At 96, 140 and 180 px: can you identify each silhouette without color? On light and dark wallpapers: can you read the face, light and approval sign? With two similar pets: does every card name its exact project/session? In reduced motion: does the full state remain clear? Across styles: are alerts equally legible? For each rig: do feet, hands, accessories and eye blinks stay attached through all 13 clips?

These are future production checks. This package was checked as local design documentation and image assets, not as a running app implementation. No live agent-model calls or app tests are needed for the static package.

## Version 2 mockup corrections

The onboarding board uses a bunny head for Minimal; the intended neutral default is Dot. The preferences board depicts Dot like a robot; use the Studio board capsule instead. Its screen-recording subtitle overpromises capture protection: use the qualified wording in APP-UX.md and the prototype. Some generated green buttons use white text; implement the charcoal-on-mint token pair. Generated screen details illustrate layout, not exact behavior.
