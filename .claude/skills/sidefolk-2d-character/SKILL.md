---
name: sidefolk-2d-character
description: Create a Sidefolk companion's 2D form end to end, or remake one - style target and painted parts sheet (Codex image gen), cutting the parts, measuring outlines, face and colours into a rig (a Species in Swift for a gallery companion, or 2d/species.json for a companion added from a folder, D79), reviewing it against the target, filming it, and checking it live in the app. Use when the user asks for a 2D version of a companion ("do the 2D one", "make Kiko's 2D form", "the 2D Nimbo doesn't look like the 3D one, fix it"), or for a new companion's 2D form after its 3D one. Not for the 3D model (sidefolk-3d-character), Mochi's flat vector drawing, or the helper folks (D73).
---

# Sidefolk 2D character

A companion's 2D form (D59) is a 2D cartoon, not a flat copy of its 3D model: about 0.2% of a core where 3D costs
about 18% (D51). It is a **painted cut-out rig**: image generation paints the parts, the vector rig (D30) moves them
the way 2D animated series rig characters, and the eyes, mouth, nose and cheeks stay drawn live, so blinks, gaze,
expressions and talking work. Every 2D form follows one style target, `companions-2d/references/lineup-2d.webp`.

| Where | What |
|---|---|
| `companions-2d/README.md` | The pipeline, step by step: read it first |
| `companions-2d/references/` | `lineup-2d.webp` (the style), `prompts.json` (its prompt and parts painted again on their own) |
| `companions-2d/targets/`, `targets.py` | Each gallery companion cut out of the lineup in canvas units |
| `companions-2d/parts/` | `prompts.tsv`, `generate.sh` (parts sheets), `cut.py` (key and cut), `blank.py` (wipe a face drawn anyway), `<name>.json` (which piece is which part) |
| `Sources/SidefolkCharacter/<Name>.swift`, `Art/<name>/` | A gallery companion's rig and its paintings |
| `Sources/SidefolkCharacter/SpeciesFile.swift` | The data format a folder companion's `2d/species.json` uses (strict: an unknown key is an error) |
| `~/git/sidefolk-private/companions/<id>/2d/` | A folder companion's form (D60, D79): `species.json`, `parts/*.svg`, `paint/*.png`; never in a repository |
| This skill's `templates/` | `target.py`, `cut.py`, `compare.py`, `species.json`, `parts/*.svg` for a folder companion |

Copy the finished companion closest to the new one (screen face, headphones: `Spark.swift`; ears and tail: `Ember.swift`;
hair: `Kiko.swift`; floating: `Nimbo.swift`; flat body: `Folio.swift`) rather than inventing.

**The bar:** it reads as the same character as its 3D form and sheet, in the family's style; it holds every state and
moment without a part coming loose, cut off or pointing the wrong way. **Canvas:** 200 × 200 units, y up, soles on
y = 20, centred on x = 100, 4 px a unit in the targets; the figure's top at or under about y 172.

**What went wrong before**, so check each up front:
- **Mittens or toes pointing inward:** `armL` and `footL` are the parts on the *viewer's* left (the rig's first shoulder
  and foot), whatever the brief called them.
- **A part in the wrong place or size:** a painting is fitted over its outline's *bounds*, by area, in its own
  proportions. The outline must take in everything painted on that part (a head's ears, headphones or hair), in about
  the painting's proportions. Compare the painting's width/height with the outline box's before rendering.
- **A body painted tall and narrow** (or any part far off the target's proportions): paint that part again on its own
  with the target and the first sheet as references and the proportion in words ("about 1.7 times as wide as tall");
  `widen` only for a few percent.
- **Shoes or paws painted onto the legs** of a body: keep only its top (`keep`, about 0.85), cut where the feet drawn
  over the legs hide it.
- **Feet covering the legs, a stubby figure:** smaller `feet.size` and the torso's painting nudged up a few units.
- **Glowing eyes that look too big:** halos add size; compare with the target at the same scale and lower `face.scale`.
- **A face painted on the head:** the brief says the face (or visor) is EMPTY; `parts/blank.py` wipes one drawn anyway.
- **Identical snapshots in the app:** a calm idle can hold still for a second; play a move, then compare.

## 0. Plan and cost

Say the plan in a line. Codex image gen uses the user's Codex quota: a style target (only when the companion isn't in
the lineup), one parts sheet, and usually one part painted again: two to four images. A request to make the 2D form is
consent. If image generation is down, say so and do only what doesn't need it (outlines from a draft, app support).

**Where to work:** as in the 3D skill: look at `git status` and `git worktree list`; with someone else's changes in the
main checkout, work in a worktree of your own (`git worktree add -b team/<name> ../sf-team-<name> <base>`).

**Which kind:** a *gallery* companion gets a Swift rig and paintings in the app (§5a). A *folder* companion (private, or
anything kept on one Mac) gets `2d/` data in its own folder outside the repos (§5b), and is never named in a
repository (code, comments, docs, tests, decisions, commit messages).

## 1. Style target

- **In the lineup already** (the gallery's ten): `python3 companions-2d/targets.py` cuts `targets/<name>.webp`.
- **Otherwise** paint one with the `codex-imagegen` skill, `--ref` its 3D portrait, its sheet and `lineup-2d.webp`
  (style only). Brief: "Style target for the 2D version of a desktop companion character, matching the look of the
  third reference image (a lineup of 2D cartoon companions): true 2D cartoon, NOT 3D: flat colour fills, clean smooth
  coloured outlines (a darker tone of each part's fill, never black), exactly one hard-edged cel shadow tone on the
  lower-right side of each part, a small flat highlight shape, simplified friendly shapes like a modern 2D animated
  series or premium sticker set." Then the character, part by part with colours, "Full body, frontal, standing, arms
  relaxed at its sides. No gradients, no textures, no 3D lighting, no drop shadows except a flat soft oval on the floor.
  Plain very light grey background, no text." **Look at it** beside a lineup target (e.g. `targets/spark.webp`): same
  family, same character.
- Cut it to canvas units: a gallery companion joins `CHARS` in `targets.py` (or a sheet of its own); a folder companion
  copies `templates/target.py` beside its target (`pipeline/2d/`), sets `MIDDLE`, `SOLE` (the soles, not the floor
  shadow) and `SCALE` (so its top stays under y 172), and runs it with `--grid`.

## 2. Skeleton: read the shapes off the grid

`python3 companions-2d/targets.py --grid <dir> <name>` (or the template's `--grid`) draws the canvas over the target.
Read, in canvas units: the head (with everything painted on it), the torso with its legs, shoulders and the arm
hanging from them, feet, ears, antennae and tails, the face (eyes, mouth, `eyeSize`, `mouthSize`, `iris`, `ink`,
cheeks, nose) or the screen (a visor: `screen` centre, size, corner radius; `glow`, `mouthGlow` from the 3D form's
lights), the outline colour, and two to six body colours for the flat fallback.

## 3. Parts sheet

**Gallery:** a line in `companions-2d/parts/prompts.tsv`, then `companions-2d/parts/generate.sh <name>`. **Folder:** the
same brief (copy it from `generate.sh`) through `codex-imagegen` with `--ref <name>-target-canvas.webp --ref
lineup-2d.webp`, saved beside the target, as lossless WebP. The parts list, each numbered:
1) the head with a **blank face** (an EMPTY visor or screen: "no eyes, no mouth, only a soft reflection"), with or
   without its ears as the rig needs; 2) the body with its legs ending at the ankles, without arms, head or feet;
3)/4) each arm STRAIGHT and hanging down, with its hand; 5)/6) each foot; plus ears, antennae or tails painted apart
when the rig moves them.

**Look at it** against the target: every part complete and apart, the face blank, each part in the target's
proportions. Paint one again on its own when it is off (see the list above), and record that brief: gallery in
`references/prompts.json`, folder in `sidefolk-private/pipeline/prompts.json`.

## 4. Cut and name

**Gallery:** `python3 companions-2d/parts/cut.py <name>` writes the pieces and `index.png`; name them in
`parts/<name>.json` (`"other:1"` for a part painted on its own, `{"piece": 5, "keep": 0.86}` for only its top), then
`cut.py <name> --install` into `Art/<name>/`. **Folder:** copy `templates/cut.py` beside the sheets, run it once to get
`work/<sheet>/index.png`, fill in `PARTS`, and run it again: it writes `companions/<id>/2d/paint/`. Look at the index:
no pink fringe, no piece split or merged.

## 5a. Rig a gallery companion (Swift)

`Sources/SidefolkCharacter/<Name>.swift`: a `Species` from the measurements (`shading: .flat(shell, line:)`, torso and
head outlines with the legs and everything painted on the head, `neck`, `feet`, `foot`, `shoulders`, `arm`, `armTuck`,
`face`, `appendages`, `collar`, `restingFrame`, `markOffsets`), ending in `.painted("<name>", nudge:, grow:, widen:)`;
ears, antennae and tails use `Painted("<name>/earL", over: outline)` in their layers (a part painted leaning gets its
outline turned to match). Wire it: `CharacterSpecies` (`CharacterLook.swift`), `Species.figure(for:)`, and
`CompanionChoice.dimensions` `[.threeD, .twoD]` (`AppSettings.swift`).

## 5b. Rig a folder companion (data)

Copy `templates/species.json` and `templates/parts/` into `companions/<id>/2d/` and replace every number with the
measurements: `body.look: "flat"`, `line`, `colors`; `head` and `torso` as `{"part": "parts/head.svg"}` (SVG on a
200 × 200 artboard, y down: `ellipse`, `circle`, `rect` and `path` without arcs) so they can take in several shapes;
`arms.shape` one outline for both arms (shoulder at the origin, hanging down); `face.screen`, `glow`, `mouthGlow` for a
visor face, or `eyes`, `mouth`, `ink`, `iris`, `nose` for a drawn one; `paint` for each painting (`nudge`, `grow`,
`widen`). The whole format: `docs/research/lively-companions.md`, "Custom companions", and `SpeciesFile.swift`.

```sh
swift run sidefolk-render --check-companion <folder>/2d     # "ok: … draws in every state", or what is wrong
```

## 6. Review

```sh
swift run sidefolk-render out/ --only <name or folder>/2d   # every state, small with badges, hit shapes, gaze, styles
python3 templates/compare.py out/companion-<id>.png <name>-target-canvas.webp out/idle-vs-target.png   # folder ones
swift run sidefolk-render --live demo 14 <name or folder>/2d --film out/film   # every moment, filmed
```

A gallery companion also gets `overlay-<name>.png` and `compare-<name>.png`. Look at the idle beside its target first
and iterate (outline boxes, `nudge`, `grow`, feet, face scale) until it reads as the same character; then every state
(sleeping, dragging, the props), the hit shapes (they follow the art), and a strip of film frames (hops, cheer, yawn,
wink, wave: nothing comes apart, points the wrong way or leaves the window). `make test` for a gallery companion: every
companion holds every state and stays in its window (draw it smaller with `scale` if not).

## 7. Check it live, then record and commit

```sh
make dev     # or scripts/build-app.sh debug, then the app with a fresh short SIDEFOLK_HOME (build/qa-<name>)
SIDEFOLK_HOME=… swift scripts/dev.swift companion:<id>:2d          # a folder one: addCompanion:<folder> first (again
SIDEFOLK_HOME=… swift scripts/dev.swift companion:local:<id>:2d    # after every change to its files), then this
SIDEFOLK_HOME=… swift scripts/dev.swift play:wave; … snap          # snapshots during a move must differ
SIDEFOLK_HOME=… swift scripts/dev.swift settings:companion; … snap # the Look switch shows 3D | 2D, the tile a 2D chip
```

Bring the app forward by its process id before a Settings snapshot (`NSRunningApplication(processIdentifier:)
?.activate()` from a tiny `swift` script): several debug apps often run at once. Record the briefs and what each image
became (and the Codex images used), update `docs/STATUS.md` (and `companions-2d/README.md` for anything learned), and
commit in one coherent milestone, no Co-Authored-By trailer; push only when asked. A folder companion's work lives only
in `sidefolk-private` (its README and `pipeline/prompts.json`); the repository gets only generic tools and lessons.
