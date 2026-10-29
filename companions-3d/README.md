# 3D companions (D51)

Mochi, Spark, Ember, Kiko and Nimbo as animated 3D characters. Mochi and Spark can be shown in 2D
or 3D (Settings › Companion › Look); Ember, Kiko and Nimbo exist only in 3D. The app shows them in
a transparent web view over the companion's 2D rig, which still runs undrawn: it keeps the states,
idle life, clicks, petting and bubble anchors, and every cue it gets is replayed in 3D
(`Companion3DStage`).

| What | Where |
|---|---|
| Runtime the app ships: page, engine, characters, three.js r180, rigged models, detail maps, portraits | [`Resources/Companions3D`](../Resources/Companions3D) |
| Character sheets: supplied (lineup, Spark, Mochi) and generated with Codex image gen (Ember, Kiko, Nimbo) | `references/` |
| Every prompt, its references and the Meshy task ids | `references/prompts.json` |
| Meshy front design images (blank faces, A-pose) | `meshy/` |
| Rigs (Blender, headless) | `blender/rig_<name>.py` on the shared `blender/rigkit.py` |
| Fabric photos (Codex) → seamless relief maps | `textures/` → `Resources/Companions3D/assets/*-height.png` |
| Browser playground (every move, feeling, state and posture; review sheets; recording) | `playground/` + `serve.py` |

## How a character is made

1. **Sheet.** A turnaround and expression sheet, generated with Codex image gen when there is none
   (`references/prompts.json`).
2. **Design image (Meshy, nano-banana-pro).** A front view in A-pose with the sheet's proportions and
   a deliberately blank face, so the face can be built as animatable parts.
3. **Model (Meshy 7.1 image-to-3D, 4K texture).** Raw models aren't kept here (Ember's is 132 MB);
   download them again by task id from `prompts.json` while Meshy keeps them.
4. **Rig.** `measure.py` and `probe.py` print slices, colour zones and gaps to place joints by
   numbers; `look.py` renders the raw model from four sides. Each `rig_<name>.py` merges UV-seam
   doubles, decimates to about 70k faces, builds the bones, computes weights from position (bone heat
   tears these meshes; each part takes its share of what is left, so the shares always sum to one),
   bakes ambient occlusion into a vertex colour, exports the GLB with a 2K texture, and renders
   deformation tests.

   ```sh
   blender -b -P companions-3d/blender/rig_spark.py -- spark-model.glb Resources/Companions3D/assets/spark.glb build/rig-tests/spark
   ```
5. **Character file.** `Resources/Companions3D/characters/<name>.js`: the material (colours
   classified from Meshy's texture in GLSL, relief, sheen, inner light, glow), the face (ink: glossy
   3D eyes with shader lids and a painted decal cut from the head; screen: light on Spark's visor),
   springy chains (ears, antenna, tail), its stand pose, and postures for bodies that need their own
   (Nimbo floats).
6. **Portrait.** In the playground, `(await import('./sheet.js')).portrait(companion)` saves the
   still Settings shows; copy it to `Resources/Companions3D/portraits/<name>.png`.

## The engine

One engine (`Resources/Companions3D/engine/`) for every character. Each frame builds a pose from
layers (posture, idle life, Sidefolk's state loop, one-shot moves, look-at with the eyes leading),
then springs finish it: chains, the scarf tag, squash and stretch, and follow-through on the core,
head and limbs. 28 moves, 29 feelings, 12 states and 4 postures; Mochi's nose and mouth always
keep a clear gap. In the app it draws 15 frames a second while it only breathes and glances, 30
while it moves, at 1.5× pixels, with a small shadow map redrawn every other frame, and nothing while
the window is hidden: about 18% of a core (D51), against 0.2% for a 2D companion.

## Playground

```sh
python3 companions-3d/serve.py 8765     # http://localhost:8765/?c=ember   (mochi, spark, ember, kiko, nimbo)
```

`?bare&frame=tight` for clean captures; in the console `(await import('./sheet.js')).sheet(companion)`
lays 16 feelings, moves and postures out in one grid. `?record=<name>&frame=tight` records the
showreel frame by frame into `build/companions-3d/<name>/`.

## Rebuild the app's copy

The runtime is edited in place in `Resources/Companions3D`; `scripts/build-app.sh` bundles it.
Model sizes: 3–6 MB each, 23 MB in all.
