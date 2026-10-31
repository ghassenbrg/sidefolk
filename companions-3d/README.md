# 3D companions (D51)

Mochi, Spark, Ember, Kiko, Nimbo and Folio (and Iris, Nori, Purl, Rune) as animated 3D characters. Each can be shown
in 2D or 3D (Settings › Companion › Look; the 2D forms: `companions-2d/`, D59). The app shows them in
a transparent web view over the companion's 2D rig, which still runs undrawn: it keeps the states,
idle life, clicks, petting and bubble anchors, and every cue it gets is replayed in 3D
(`Companion3DStage`).

| What | Where |
|---|---|
| Runtime the app ships: page, engine, characters, three.js r180, rigged models, detail maps, portraits | [`Resources/Companions3D`](../Resources/Companions3D) |
| Character sheets: supplied (lineup, Spark, Mochi, Nimbo v2, Folio, Iris, Nori, Purl, Rune) and generated with Codex image gen (Ember, Kiko, Nimbo v1) | `references/` |
| Every prompt, its references and the Meshy task ids | `references/prompts.json` |
| Meshy front design images (blank faces, A-pose) | `meshy/` |
| Rigs (Blender, headless) | `blender/rig_<name>.py` on the shared `blender/rigkit.py` |
| Fabric photos (Codex) → seamless relief maps | `textures/` → `Resources/Companions3D/assets/*-height.png` |
| Browser playground (every move, feeling, state and posture; review sheets; recording) | `playground/` + `serve.py` |

## How a character is made

The `sidefolk-3d-character` skill (`.claude/skills/sidefolk-3d-character/`) walks an agent through
all of this, from a sheet or just an idea, with templates for the rig and the character file.

1. **Sheet.** A turnaround and expression sheet, generated with Codex image gen when there is none
   (`references/prompts.json`).
2. **Design image (Meshy, nano-banana-pro).** A front view in A-pose with the sheet's proportions and
   a deliberately blank face, so the face can be built as animatable parts. Whatever the prompt asks
   for on the face, Meshy sculpts (Iris's first model had its brow and smile in relief), and it drifts
   to rounder shapes unless told what not to make (Rune's first head was a mushroom dome: "NOT a dome,
   NOT a mushroom" fixed it).
3. **Model (Meshy 7.1 image-to-3D, 4K texture).** Raw models aren't kept here (Ember's is 132 MB);
   download them again by task id from `prompts.json` while Meshy keeps them.
4. **Rig.** `measure.py` and `probe.py` print slices, colour zones and gaps to place joints by
   numbers; `look.py` renders the raw model from four sides. Each `rig_<name>.py` merges UV-seam
   doubles, decimates to about 70k faces, builds the bones, computes weights from position (bone heat
   tears these meshes; each part takes its share of what is left, so the shares always sum to one),
   bakes ambient occlusion into a vertex colour, exports the GLB with a 2K texture, and renders
   deformation tests. Meshy packs its texture islands edge to edge, so a shrunk texture shows pale
   cracks along every seam: `regutter()` repacks the islands with a margin and bakes the colour again.
   A part the texture can't tell apart by colour (Nori's black frames on charcoal fur) is marked by
   the rig (`mark()`, the AO colour's green channel) and read by the material as `part`.

   ```sh
   blender -b -P companions-3d/blender/rig_spark.py -- spark-model.glb Resources/Companions3D/assets/spark.glb build/rig-tests/spark
   ```
5. **Character file.** `Resources/Companions3D/characters/<name>.js`: the material (colours
   classified from Meshy's texture in GLSL, relief, sheen, inner light, glow), the face (ink: glossy
   3D eyes with shader lids and a painted decal cut from the head; screen: light on Spark's visor),
   springy chains (ears, antenna, tail), its stand pose, and postures for bodies that need their own
   (Nimbo floats; Folio, a flat card, rests sitting). `limbScale` keeps limbs that are one piece with
   the body (Nimbo's puffs) from tearing away from it. A likeness (a person's face in the model's own texture)
   keeps its eyes, brows and lips: `layout.lids` paints only lids over its eyes and `layout.mouth.lips` parts the
   lips only while the mouth opens (see `face.js`). A companion that should stay on one Mac only (a person's
   likeness) isn't published: its add-on folder is added in Settings › Companion › Made by you (D60).
6. **Portrait.** In the playground, `(await import('./sheet.js')).portrait(companion)` saves the
   still Settings shows; copy it to `Resources/Companions3D/portraits/<name>.png`.

## The engine

One engine (`Resources/Companions3D/engine/`) for every character. Each frame builds a pose from
layers (posture, idle life, Sidefolk's state loop, one-shot moves, look-at with the eyes leading),
then springs finish it: chains, the scarf tag, squash and stretch, and follow-through on the core,
head and limbs. Moves, feelings, states and postures are shared, and each character adds its own
trick (`actions`, `moments`). Liveliness decides what it starts on its own and how big its
reactions are (`REACTIONS` in `engine.js`, one table to tune); every move emits `'move'`, the hook
for sound effects later. In the app, the 2D view's effects and badges draw over it. Mochi's nose
and mouth always
keep a clear gap. In the app it draws 15 frames a second while it only breathes and glances, 30
while it moves, at 1.5× pixels, with a small shadow map redrawn every other frame, and nothing while
the window is hidden: about 18% of a core (D51), against 0.2% for a 2D companion.

## Playground

```sh
python3 companions-3d/serve.py 8765     # http://localhost:8765/?c=ember   (mochi, spark, ember, kiko, nimbo, folio, iris, nori, purl, rune)
```

`?bare&frame=tight` for clean captures; in the console `(await import('./sheet.js')).sheet(companion)`
lays 16 feelings, moves and postures out in one grid, and `turnaround(companion)` saves front, ¾,
side and back views to compare with the sheet's turnaround. Stills hide what motion shows:
`filmstrip(companion, 'flip', { yaw: 120 })` lays one move out frame by frame from any side, and
`closeups(companion, name, [[yaw, height, size], …])` renders the surface close up. Resting:
`restSheet(companion)` lays out stand, sit, lie and sleep from the front, ¾ and side with the head close up, and
`restFilm(companion, 'lie' | 'sleep')` films the way in and out (stand › sit › lie › stand, idle › sleeping › idle),
front and side, as Sidefolk's idle life plays them. Probes in Blender read
colours one gamma too bright (a `lum` of 0.46 there is 0.18 in the material). `?record=<name>&frame=tight` records the
showreel frame by frame into `build/companions-3d/<name>/`.

## Rebuild the app's copy

The runtime is edited in place in `Resources/Companions3D`; `scripts/build-app.sh` bundles it.
Model sizes: 3–6 MB each, 23 MB in all.
