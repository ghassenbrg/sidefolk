---
name: sidefolk-3d-character
description: Create a new Sidefolk 3D companion end to end, or remake one, from a character sheet or just an idea - reference sheet (Codex image gen), blank-face design image and 3D model (Meshy), Blender rig, character file for the three.js engine, review, portrait, and wiring into the app (settings, stand-in rig, translations, docs, tests). Use when the user asks to add, create, design, build or fix a 3D companion/character for Sidefolk ("add Folio as a 3D companion", "make a 3D owl companion", "Nimbo doesn't look like the sheet, fix it"). Not for the 2D vector rigs (D30) or custom data companions (D43).
---

# Sidefolk 3D character

A 3D companion (DECISIONS D51) is a Meshy model rigged in Blender and driven by one three.js engine
in a web view over an undrawn 2D stand-in rig. Everything lives in the repo:

| Where | What |
|---|---|
| `Resources/Companions3D/` | Shipped runtime: `companion.html`, `engine/`, and the built-in companions' `characters/<id>.js`, `assets/<id>.glb`, `portraits/<id>.png`, `avatars/<id>.png` (Mochi, Spark) |
| `../sidefolk-addons/companions/<id>/` | Every other 3D companion (D55): the same four files and `addon.json`, published as a signed pack; `companions-3d/serve.py` serves them beside the app's |
| `companions-3d/` | Pipeline: `references/` (sheets, `prompts.json` with every prompt and Meshy task id), `meshy/<id>-front.png`, `blender/` (rig kit, `rig_<id>.py`, `measure.py`, `probe.py`, `look.py`), `playground/`, `serve.py` |
| This skill's `templates/` | `rig_template.py`, `character_template.js` to start from |

Read `companions-3d/README.md` and one finished character close to the new one first (biped:
`ember`/`kiko` and `rig_ember.py`/`rig_kiko.py`; floating: `nimbo`; flat or odd body: `folio`; screen
face: `spark`). Copy what fits rather than inventing.

The founder's bar: movie-quality, cute, alive; it really sits, lies, sleeps, bows and waves; it
looks like its sheet. Mouth and nose never touch. Never touch Codex's `sandbox/` folder (read only,
if the user points at a file there).

## 0. Plan and costs

Say the plan in a line and the credit cost before spending (Meshy's rule): design image 9
(nano-banana-pro) + model 30 (meshy-7.1, 4K texture) ≈ 40 credits; check `meshy_check_balance`.
A sheet from Codex image gen uses the user's Codex quota (one image). A request to make the
character is consent; a remake of an approved one is too.

## 1. Reference sheet

- **The user gave a sheet** (attachment or path): copy it into `companions-3d/references/<id>-sheet.*`
  unchanged. An attachment that isn't on disk: look for it (Downloads, the repo) or ask for the path.
- **Only an idea**: generate one with the `codex-imagegen` skill (`--ref` the lineup or another
  sheet for style). Reuse this layout and style sentence word for word so sheets match:

  > Premium 3D animated-feature character reference sheet, soft bright studio light, pale cool-white
  > background, rounded panels. A large hero pose on the left; on the top right a turnaround row of
  > four full-body views (front, three-quarter, side, back) in a neutral relaxed standing pose; on the
  > bottom right a grid of eight head close-ups with expressions (neutral, talking, blink, happy,
  > concerned, thinking, listening, sleep). Keep the character identical in every view. Absolutely no
  > text, no labels, no captions, no letters, no watermark, no logo.

  Show the sheet to the user before going on when they asked for a new design: it is the cheap place
  to change the character.
- Crop the hero, front, side and back views with PIL into a scratch folder for the next step.

## 2. Design image and model (Meshy)

1. `meshy_image_to_image`, `nano-banana-pro`, `aspect_ratio` "3:4" (tall) or "4:3" (wide), the crops as
   `reference_file_paths`. The prompt (see `prompts.json` for five real ones):
   - "Front view, full body, of this exact … for 3D modeling. Keep the reference's proportions exactly:"
     then every part, colour (hex) and material, plus shape words that matter ("wider than tall",
     "smooth, NOT lumpy").
   - "IMPORTANT: the face is completely BLANK: no eyes, no eyebrows, no nose, no mouth, no blush, no
     markings (the face will be added later as separate parts)". Keep colour zones such as a muzzle
     or glow.
   - Bipeds: "Neutral symmetric A-pose: arms held away from the body angled down 35 degrees with
     clear space between arms and body, feet slightly apart."
   - "Even soft studio lighting, plain flat light grey background (#E6E9EE), no ground shadow, no text."
2. Download it (`save_to` a scratch path), **look at it**, compare it with the sheet's shape, and redo
   it if the silhouette is wrong. A wrong shape here is the costliest mistake (Nimbo's first model was
   a round puffball where the sheet had a wide cloud).
3. `meshy_image_to_3d` with `input_task_id`, `meshy-7.1`, `texture_resolution` "4k", `target_formats`
   ["glb"], `pose_mode` "a-pose" for limbed bodies (none for a cloud), and a `texture_prompt` that
   repeats the colours and says "blank face".
4. Download the GLB to a scratch folder, **not the repo** (raw models are 15–130 MB). Record both task
   ids and the prompts in `companions-3d/references/prompts.json` and save the design image as
   `companions-3d/meshy/<id>-front.png`.

## 3. Measure

```sh
cd companions-3d/blender
blender -b -P look.py -- <model.glb> /tmp/<id>/look          # front, ¾, side, back renders
blender -b -P measure.py -- <model.glb> 0.05                 # slices: x clusters, depth, colour
blender -b -P probe.py -- <model.glb> /tmp/<id>/probe.py      # your own masks and numbers
```

Blender axes: Z up, the character faces **-Y**, its left is **+X**. Check, from the renders:
- **Facing**: the face side must show at yaw 0. Meshy sometimes faces flat characters backwards
  (Folio): `prepare(..., turn=180)`.
- **Centring**: a big tail or prop pushes the body off x = 0 (Ember: 0.094): find the feet or ears
  pairs and `prepare(..., shift=(-dx, 0, 0))`.
- **Floor**: the lowest z (about -0.95 for 1.9-tall bipeds; less for wide characters).
- **Joints**: where arms leave the torso (gaps in slices), shoulder and hip heights, ear and tail
  axes, the face's front depth and centre, separate pieces (`islands()`).
- **Colour zones** the material and weights need (probe with sRGB masks: `r`, `g`, `b`, `lum`).

## 4. Rig

Start from `templates/rig_template.py` (or the closest `rig_<id>.py`), save as
`companions-3d/blender/rig_<id>.py`, write the measured numbers into its header comment, and run:

```sh
blender -b -P companions-3d/blender/rig_<id>.py -- <model.glb> ../sidefolk-addons/companions/<id>/assets/<id>.glb /tmp/<id>/tests
```

Rules that came from mistakes:
- Weights are computed from position, never bone heat (it tears these meshes). Partition: each part
  takes its share of **what is left** (`arm = a * (1 - head)`, `leg = l * (1 - head - arm)`,
  `core = 1 - …`); `skin()` asserts the sum is 1.
- Bone names: `hips spine chest head`, `arm.L/R hand.L/R thigh.L/R foot.L/R`, chains such as
  `ear.L.1…`, `antenna.1…`, `tail.1…`, plus a non-deforming `face`. The engine strips the dots
  (`earL1`) and only animates bones that exist, so a body without legs or ears just has none.
- Parts modelled apart (puffs, props): weight whole islands. Parts fused to the body that must
  move (Nimbo's puffs): soft spherical weights, and `limbScale` in the character file.
- Aim at about 70k faces (`ratio`) and a 2K texture (`export` does it): 3–6 MB per model.
- Look at the test renders: nothing torn, stretched or left behind (Ember's tail tip once stayed on
  the head because the head's height band claimed it: an ellipsoid for the head fixed it).

## 5. Character file

Start from `templates/character_template.js`. A new companion is an add-on (D55): save it as
`../sidefolk-addons/companions/<id>/characters/<id>.js`, with its model at `assets/<id>.glb` beside it (and the
portrait and profile picture below), and add `<id>` to `CHARACTERS` in `companions-3d/playground/index.html`.
Only a companion meant to ship inside the app goes in `Resources/Companions3D/`. Coordinates there are three.js: x = its left, **y up**,
**z toward the viewer** (Blender `(x, y, z)` → three `(x, z, -y)`; three y = Blender z).

- **material**: `bodyMaterial` with a GLSL `surface` that classifies Meshy's texture into clean
  colour zones and sets `c`, `rough`, `bumpH` (keep relief subtle: 0.003–0.012; more looks grainy),
  `sheenTint`, `clear`, `inner`, `glow`. Fur and plush: sheen; plastic: `sheen: 0`, clearcoat;
  paper: matte, a little sheen. Thin bodies bake very dark occlusion: soften `ao`.
- **face**: `ink` (3D eyes + painted decal) or `screen` (light on a visor). `unwrap.R` is the
  distance from the cylinder axis to the face; a flat face needs a far axis (`R: 2, cz: -1.8`).
  `region` keeps only the face's front triangles. Lay out eyes, nose, mouth, brows and blush **by
  measuring the sheet**: px → model units with the body's width and height in the sheet's front
  view. Mouth below the nose with a gap, always. `iris` colours from the sheet.
- **chains**: springy ears, antennae, tails (`k`, `d`, `gain`, `wag`, `limit`, `twitch`).
- **stand**: brings arms down from the modelled A-pose (about 20–60°, by the model).
- **postures**: only for bodies the shared ones don't suit (floating: `hover`, `life`; a flat
  card: rest sitting). **skip**: moves the body can't do (`sniff` for a robot).
- `frame`, `floor`, `pivot`, `marks`, `blob`, `pick` from the measurements.

## 6. Review against the sheet

```sh
python3 companions-3d/serve.py 8765   # http://localhost:8765/?c=<id>&bare&frame=tight
```

(The preview needs a `.claude/launch.json` entry in the session's working folder; remove it after.)
In the console: `(await import('./sheet.js')).sheet(companion)` lays out 16 feelings, moves and
postures. Compare with the sheet side by side and iterate on shape, colours, eye size and
placement, mouth, brows, blush and postures until it reads as the same character. The built-in
browser pane runs no animation frames while hidden: use `companion.step(seconds)` (renders), not
waiting. Then save the portrait: `(await import('./sheet.js')).portrait(companion)` in a 512 px
`?frame=sidefolk&capture` page (see how the existing ones were made in the README) and copy
`build/companions-3d/portrait-<id>/00001.png` to `portraits/<id>.png` in its add-on folder.

**Profile picture** (D54): with `codex-imagegen`, `--ref` the new portrait, the sheet and
`companions-3d/references/avatars/mochi-avatar.webp` (framing and finish only), and the avatar style sentence
and a backdrop colour of its own from `prompts.json` › avatars. Keep the source as
`references/avatars/<id>-avatar.webp`, and save a round 256 px crop on the face (the face must read at 26 points;
see how the six were cut) as `avatars/<id>.png` in its add-on folder. The Ask panel and Conversations show it.

## 7. Wire it into the app (3D-only companion)

**A private companion** (a real person's likeness, or anything the user wants only on their Mac): keep every file
outside the repos (e.g. `~/git/sidefolk-private/companions/<id>/` with the pipeline beside it), give `addon.json`
an optional `body` (`biped`, `floating`, `card`: whose stand-in rig it borrows), and skip the rest of this step: the
user adds the folder in Settings › Companion › Made by you › Add from Folder… (D60), or in the debug app
`swift scripts/dev.swift addCompanion:<folder>`. For a likeness, keep the sheet's face in the design image, project
it onto the texture in the rig, and use the ink face's `lids` and `mouth.lips` instead of drawn eyes (D60).


- `Sources/SidefolkCore/Settings/AppSettings.swift`: `CompanionChoice` case and `dimensions`
  (`[.threeD]`; Mochi/Spark style `[.threeD, .twoD]` only when a 2D rig exists).
- `Sources/SidefolkCharacter/CharacterLook.swift`: `CharacterSpecies` case, `has3D`, `only3D`,
  `displayName`; `Species.swift` `figure(for:)`; `StandIns.swift`: a stand-in shaped like the 3D
  silhouette (canvas units: one model unit = 87, floor at y = 20, centred at x = 100;
  `restingFrame` starts at y = 20).
- `Sources/SidefolkApp/Companion/CompanionArt.swift`: `role` line.
- The add-on: `../sidefolk-addons/companions/<id>/addon.json` (copy Ember's: id `dev.sidefolk.companions.<id>`,
  name, tagline = the role line, a description true to the character, version, `engine`), then
  `scripts/build.py` there (it checks the four files) and, once the founder agrees, `scripts/publish.sh`. The app
  offers it only once a copy that knows the `CompanionChoice` case is out.
- Strings: `bash scripts/strings.sh`, then translate every new string into the nine other
  languages in `Resources/Localization/Localizable.xcstrings` (state "translated"); rerun until
  every language shows the full count.
- Tests: extend `Tests/SidefolkCoreTests/CompanionChoiceTests.swift`; `make test` (core and character
  suites must pass; the character suite checks the stand-in stays in the window).
- Docs: D51 in `docs/DECISIONS.md`, `docs/STATUS.md`, `companions-3d/README.md`,
  `companions-3d/references/prompts.json`.

## 8. Check it live, then commit

```sh
make dev
SIDEFOLK_HOME=$PWD/build/dev-home swift scripts/dev.swift companion:<id>
SIDEFOLK_HOME=$PWD/build/dev-home swift scripts/dev.swift snap     # twice, a second apart
```

Read the `CompanionPanel` snapshot, and compare two snapshots a second apart: they must differ
(it is animating, not frozen). Try `play:wave`, `settings:companion` (bring the app forward with
`osascript -e 'tell application id "app.sidefolk.Sidefolk.dev" to activate'`: WebKit draws nothing in
a background window). Measure cost with `top` over every `com.apple.WebKit` process plus Sidefolk,
while it animates. Commit in one coherent milestone, no Co-Authored-By trailer; push only when asked.
