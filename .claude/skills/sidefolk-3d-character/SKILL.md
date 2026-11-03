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
| `companions-3d/` | Pipeline: `references/` (sheets, `prompts.json` with every prompt and Meshy task id), `meshy/<id>-front.png`, `blender/` (rig kit, `rig_<id>.py`, `measure.py`, `probe.py`, `look.py`), `playground/` (`sheet.js`: review sheets, films, close-ups, `edges()`, `front()`), `serve.py`, `zones.py` (colours against the sheet) |
| This skill's `templates/` | `rig_template.py`, `character_template.js` to start from |
| `~/git/sidefolk-private/` | Companions kept on one Mac (D60): `companions/<id>/` and `pipeline/` (its README); never in a repository |

Read `companions-3d/README.md` and one finished character close to the new one first (biped:
`ember`/`kiko` and `rig_ember.py`/`rig_kiko.py`; floating: `nimbo`; flat or odd body: `folio`; screen
face: `spark`). Copy what fits rather than inventing.

The founder's bar: movie-quality, cute, alive; it really sits, lies, sleeps, bows and waves; it
looks like its sheet. Mouth and nose never touch.

**Never show a companion, a still or a proof round, until the window check (§6, step 6) has passed in that same
state of the model.** The founder has caught ears and feathers cut flat at the top, as if the character stood in a box,
on more than one companion. On Noor's proof the cause was simply that the check hadn't been run.

**What the founder catches on the desktop**, so check each before showing anything (§6 has the tools): a part cut
off by the window's edge while it is petted, hops or lies down; a neck that bends oddly; a rest that looks like a doll
thrown down instead of a creature resting; stair-stepped or speckled colour edges up close (a visor's rim); a logo or
letter that looks low quality; light and colour that don't match the sheet (brighter, duller, pinker, extra
highlights); a profile picture that is a screenshot instead of a painted portrait.

## 0. Plan and costs

Say the plan in a line and the credit cost before spending (Meshy's rule): design image 9
(nano-banana-pro) + model 30 (meshy-7.1, 4K texture) ≈ 40 credits; check `meshy_check_balance`, and
`meshy_list_tasks` for one already made for this character (a request that says "try again" may follow one that
was charged). A sheet from Codex image gen uses the user's Codex quota (one image). A request to make the
character is consent; a remake of an approved one is too.

**Where to work.** Look at `git status` and `git worktree list` first. If someone else's changes are in the main
checkout, work in a worktree of your own (`git worktree add -b team/<name> ../sf-team-<name> <base>`, based on the
newest integration branch when one is ahead of `main`): two agents building in one `.build`
collide, and your commit must not sweep up their work. Engine changes (`Resources/Companions3D/engine/`) are shared
by every companion: make them options that default to the old behaviour, and check Spark still looks the same.

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
- The turnaround's views are small (often under 100 px): measure the face on a zoomed crop with a pixel grid drawn
  over it (PIL, `Image.NEAREST`) and read the numbers off it; automatic thresholds on a tiny crop catch the
  background and the neighbours. Measure everything against a reference inside the view (the visor's box, the
  head's width), not the image.
- Python outside Blender has PIL but no numpy: write pixel loops, or run numpy work with `blender -b --python`.

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
   ["glb"], `pose_mode` "a-pose" for limbed bodies (none for a cloud), `image_enhancement` false, and a
   `texture_prompt` that repeats the colours and says "blank face".
   - A letter, logo or badge on the body comes out blotchy in the texture (it is a few dozen texture pixels): plan
     to draw it as a decal (§5) and keep it only for its place.
   - Arms that come out close to the body are fused to it: fine, but plan the arm weights of §4 for them.
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
- Aim at about 70k faces (`ratio`) and a 2K texture (`export` does it): 3–6 MB per model. Where a hard colour edge
  will be seen large (a visor's rim, a panel's border), keep 4K (`regutter(mesh, size=4096)`,
  `export(dst, tex=4096)`): 2K steps show up close; flat colours compress well (a big-headed robot's 4K model was 3.9 MB).
- Look at the test renders: nothing torn, stretched or left behind (Ember's tail tip once stayed on
  the head because the head's height band claimed it: an ellipsoid for the head fixed it). Blender's local bone
  axes turn arms differently from the engine: judge raised arms in the engine's films (§6), not in these.
- **Arms fused to the body**: weight them by distance from the arm's own segment (`limb()`), plus a band past the
  shoulder only *above the armpit* for the thick root. A band by `|x|` alone gives the torso's sides (as wide as the
  shoulders, down to the hips) half an arm's weight, and a raised arm pulls a flap out of them; the segment alone
  leaves the top of the shoulder behind. Blend slowly under the arm (`ss(-0.47, -0.37, z)`, radii 0.1–0.17) so a
  raised arm stretches the armpit evenly.
- **Hands, mittens and other parts wider than the limb**: their edge lies past the limb's radius and stays with the
  torso (a black spike at the hip when the arms go up). Take them whole by their colour (`grow()` a colour mask over
  the mesh's edges) and give them to the hand.
- **Hanging pieces** (a scarf's tail, a tag): find them by colour inside a box, keep out look-alikes of the same
  colour (feet dots, a red logo beside it) by place, give them a bone the engine already springs (`scarf`), and
  `mark()` them when the material must tell them apart (a scarf's tail beside a chest logo, so the logo's paint-out stops at its edge).

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
- **postures**: for bodies the shared ones don't suit (floating: `hover`, `life`; a flat card: rest sitting; a big
  head: rest and sleep sitting up). Rests must look alive: never tip the body onto its side or face down like a doll
  thrown on the floor. Sitting with the feet swinging one after the other and the head looking around, dozing with
  the chin dipping a little on each slow breath (`POSTURES.sit` plus small sines) read as a creature resting. A big
  head never droops or rolls far: it reads as a broken neck. **skip**: moves the body can't do (`sniff` for a robot).
- **Room in the window (set it first, for every companion, not only big heads).** The app shows the character in a
  square that is `frame.sidefolk` units tall from 10% under the feet, so the top of the window is `0.9 × frame.sidefolk`
  above the floor, and the character has to fit well below it at rest. Measure from the tallest point of any part,
  antenna, ear, feather or hair tip included, and leave room for what it does in motion: hops, stretches, and springy
  parts that lag and swing up. Tall thin tips need room too (a 1.93-tall moth whose feathers touched the top at 2.3 needed
  2.7), and a head as wide as the others are tall needs more (2.5). `roomAbove()`, which eases hops under the ceiling,
  reads only the body mesh's bounding box: a part hung on a bone in `extras` isn't in it, so the engine won't lower a hop
  for it. Skin tall parts into the body where you can; otherwise raise the box in `extras` (`body.geometry.boundingBox.max.y`, to the part's tip plus a little), and the shared hops, jumps and stretches then stay under the ceiling. `pivot` is the height above the
  floor that whole-body turns go round (flips, lying), in world units, **not** model coordinates: put it at the
  body's middle (about 0.9 for a 1.9-tall body); at the feet a flip swings through the floor. `petLean` (default 1)
  makes a big head lean less into a stroking hand (0.55: a full lean swung a big head's ears out of the window and bent its
  neck). Leaps can be lowered without touching their timing: wrap `ACTIONS.hop/jump/flip` and scale only what they
  add to `P.root.py`; stub arms want a lower `cheer` (`raise(P, s, -24)`). `edges()` (§6) says when it is enough.
- **Logos, letters, badges**: a decal in `extras(c, THREE)`: the body's triangles in a box on its surface (skinned
  like it, lifted a hair), its own 1024 px canvas, and the mark drawn as vector paths traced on the design image
  (px → units with the figure's top and bottom rows and its middle). Paint the texture's version out under it in the
  material, stopping at neighbours the rig marked. Make it matte (`roughness` 0.85, `specularIntensity` 0.15): a
  glossy print catches the key light as a pale wash. Its colour is the same as the body's parts of that colour.
- **Big shapes with an edge you see** (a visor): don't take the outline from the texture. Sample the boundary on the
  raw model (dark-to-light radius per angle around its middle, `probe.py`), fit a short cosine series, and draw the
  mask in the surface with an antialiased edge (`fwidth`).
- **Screen faces**: measure eyes and mouth against the visor in the sheet's front view (fractions of its width and
  height). `glow` for the eyes, `mouthGlow` for a mouth of another colour, `layout.mouth.scale` for its size, and
  `softGlow: true` (the stepped halos read as rings up close).
- **light**: `light: { env, key, rim }` changes the scene's light for this character only; use it after the colour
  match (§6) when a white body is still too dim.
- `frame`, `floor`, `pivot`, `marks`, `blob`, `pick` from the measurements.

## 6. Review against the sheet

```sh
python3 companions-3d/serve.py 8765   # http://localhost:8765/?c=<id>&bare&frame=tight
```

(The preview needs a `launch.json` entry in the session's working folder, `.claude/launch.json` for Claude Code;
remove it after. A private
companion: `SIDEFOLK_ADDONS_REPO=$HOME/git/sidefolk-private python3 companions-3d/serve.py 8765`.) Start every
console script with `await ready` (`companion` exists before its model has loaded). The built-in browser pane runs
no animation frames while hidden: use `companion.step(seconds)` (renders), not waiting; when the pane is collapsed
the canvas has no size: give the tab one with `resize_window` first. Read results from files the page saves into
`build/companions-3d/`, not from screenshots.

Go through all of these before showing it; each caught a real mistake:
1. **The sheet grid**: `(await import('./sheet.js')).sheet(companion)`: 16 feelings, moves and postures. Iterate on
   shape, colours, eye size and placement, mouth, brows, blush and postures until it reads as the same character.
2. **Turnaround**: `turnaround(companion)` beside the sheet's turnaround row (front, ¾, side, back).
3. **Every big move filmed** from the front, the side and ±40°: `filmstrip(companion, 'cheer', { yaw: 40 })`, and
   wave, flip, jump, dance and its own moves. Look for flaps at the armpits, spikes at the hips, parts left behind.
4. **Close-ups**: `closeups(companion, '<id>', [[yaw, height, size], …])` on the face, rims, the logo and seams:
   stair-steps, specks, washes and halos that stills at window size hide.
5. **Colour and light against the sheet**: `front(companion)` in a `?frame=tight&capture` page (background the
   sheet's), then `python3 companions-3d/zones.py <sheet> <front view's x0,y0,x1,y1> build/companions-3d/front-<id>/00001.png`.
   Bring the white, red and black zones within a few points of the sheet, median brightness first (the "other" row
   is mostly anti-aliased edges): set colours by zone in the material, deepen reds, take blue out of blacks, then
   `light.env` for a white body that stays dim. Look at the two side by side after the numbers agree.
6. **The window (a gate: nothing is shown until it passes)**: `edges(companion)` in a `?frame=sidefolk&capture` page must
   return `{}`: it plays idle, petting from both sides, every move, posture and state in the app's square framing and
   names whatever touches an edge. Run it again after anything that changes a silhouette, proportions, a chain or
   `frame`, and on proof models too. It takes minutes on a heavy model: start it without awaiting
   (`window.r = 'running'; (await import('./sheet.js')).edges(companion).then((e) => window.r = e)`) and read `window.r` later, or a console call
   times out and the check looks done when it isn't. Portraits and tiles use this same framing, so a crop here shows
   in Settings too.
7. **Rests**: `restSheet(companion)` and `restFilm(companion, 'lie'|'sleep')`: alive, not dropped.

Then save the portrait: `(await import('./sheet.js')).portrait(companion)` in a 512 px
`?frame=sidefolk&capture` page (see how the existing ones were made in the README) and copy
`build/companions-3d/portrait-<id>/00001.png` to `portraits/<id>.png` in its add-on folder. Save it again after
anything that changes its look or framing.

**Profile picture** (D54): painted, never a crop of a render, unless the character is a real person's likeness (no
image generation of real people: then a render, cut round by `sidefolk-private/pipeline/make_avatar.py`). With `codex-imagegen`, `--ref` the new portrait, the sheet and
`companions-3d/references/avatars/mochi-avatar.webp` (framing and finish only), and the avatar style sentence
and a backdrop colour of its own from `prompts.json` › avatars. Keep the source as
`references/avatars/<id>-avatar.webp`, and save a round 256 px crop on the face (the face must read at 26 points;
see how the six were cut) as `avatars/<id>.png` in its add-on folder. Ask, the Sidecard's cards, Today, History and the Pocket show it.

## 7. Wire it into the app (a gallery companion)

Every companion also gets a 2D form (D59): make it after the 3D one with the `sidefolk-2d-character` skill
(`companions-2d/README.md`).

**A private companion** (a real person's likeness, or anything the user wants only on their Mac): keep every file
outside the repos (e.g. `~/git/sidefolk-private/companions/<id>/` with the pipeline beside it), give `addon.json`
an optional `body` (`biped`, `floating`, `card`: whose stand-in rig it borrows), and skip the rest of this step: the
user adds the folder in Settings › Companion › Made by you › Add from Folder… (D60), or in the debug app
`swift scripts/dev.swift addCompanion:<folder>`. Its 2D form is data in the folder's `2d/` (D85; `companions-2d/README.md`). For a likeness, keep the sheet's face in the design image, project
it onto the texture in the rig, and use the ink face's `lids` and `mouth.lips` instead of drawn eyes (D60).
Never name a private companion in a repository: not in code comments, docs, tests, decision text or commit
messages; generic engine options it needed are described without it. Record its prompts and task ids in
`sidefolk-private/pipeline/prompts.json` and how it was made in that folder's README.

- `Sources/SidefolkCore/Settings/AppSettings.swift`: `CompanionChoice` case and `dimensions`
  (`[.threeD, .twoD]` once its 2D rig exists).
- `Sources/SidefolkCharacter/CharacterLook.swift`: `CharacterSpecies` case, `has3D`, `inGallery`,
  `displayName`; `Species.swift` `figure(for:)` (its 2D rig, and the stand-in in 3D); `StandIns.swift`: a stand-in shaped like the 3D
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
(it is animating, not frozen). **Look at the top of the figure in the app itself:** at rest there must be clear space
above its tallest tip (with PIL, `getbbox()` of the snapshot's alpha must not start at row 0), and take snapshots during
`play:dance` and a hop too: `edges()` runs in the browser at another size, and this is what the person really sees. Try `play:dance`, `click`, `settings:companion` (bring the app forward first:
WebKit draws nothing in a background window). Several debug apps often run at once (other worktrees): use a fresh,
short `SIDEFOLK_HOME` of your own (`build/qa-<name>`), leave the others alone, and activate yours by its process id,
not its bundle id, which may pick another (`NSRunningApplication(processIdentifier:)?.activate()` from a tiny
`swift` script; System Events needs accessibility access). A companion added from a folder is re-added after every
change to its files. Measure cost with `top` over Sidefolk and the `com.apple.WebKit` processes started with it,
while it idles and animates, against Spark in the same app (about 18% of a core, D51). Commit in one coherent
milestone, no Co-Authored-By trailer; push only when asked.
