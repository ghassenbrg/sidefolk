# 2D companions (D59)

Every companion also has a 2D form, shown when Settings › Companion › Look is 2D: about 0.2% of a core where 3D
costs about 18% (D51). It is a 2D cartoon, not a flat copy of the 3D model, and follows one style target. Nine of
the ten are **painted cut-out rigs**: image generation paints the character's parts, and the vector rig (D30) moves
them, the way 2D animated series rig characters. The eyes, mouth, nose and cheeks stay drawn live, so blinks, gaze,
expressions and talking work. Mochi is a flat vector drawing in the same look.

| What | Where |
|---|---|
| The style target every 2D companion follows | `references/lineup-2d.webp` (prompt in `references/prompts.json`) |
| Each character cut out of it in canvas units | `targets/<name>.webp` (`targets.py`) |
| Painted parts sheets and parts painted again on their own | `parts/<name>-sheet.webp`, `parts/<name>-<part>.webp` |
| Their briefs | `parts/prompts.tsv` (sheets, through `parts/generate.sh`), `references/prompts.json` (single parts) |
| Which piece is which part | `parts/<name>.json` |
| The parts the app draws | `Sources/SidefolkCharacter/Art/<name>/<part>.png` |
| The rigs: outlines, face, motion | `Sources/SidefolkCharacter/<Name>.swift`; `Painted.swift`, `Layers.swift` (`Flat`), `Cel.swift` |

## How one is made

The `sidefolk-2d-character` skill walks through it, with templates for a folder companion and the checks that
caught mistakes before.

From a 3D companion, from reference images, or from a description:

1. **Style target.** The character in the look of `lineup-2d.webp`: Codex image gen (`codex-imagegen` skill) with its
   3D portrait, sheet or the person's images and `lineup-2d.webp` as references; or start from a description. Front
   view, full body, standing. Add it to a target sheet and to `CHARS` in `targets.py` (its body's middle and its
   soles), then run `python3 companions-2d/targets.py` to cut `targets/<name>.webp` in canvas units: 200 × 200,
   y up, soles on y = 20, centred on x = 100, 4 px a unit.
2. **Skeleton.** `python3 companions-2d/targets.py --grid <dir> <name>` draws the canvas grid over the target. Read
   the parts off it into a `Species` in `<Name>.swift`: head and torso outlines (the torso with its legs), shoulders
   and the arm's shape hanging from them, feet, ears and antennae (`appendages`), `tails`, the face (eye and mouth
   places, `eyeSize`, `mouthSize`, `iris`, `ink`, `blushAt`, nose) and colours for the flat fallback. Copy the
   nearest companion. Wire it: `CharacterSpecies`, `CompanionChoice` (`dimensions`, name, role), `Species.figure`.
3. **Parts sheet.** A line in `parts/prompts.tsv` listing its parts, then `companions-2d/parts/generate.sh <name>`:
   the parts separated on magenta, each complete, the head with a **blank face**. Check the sheet. Redo a part that
   came out wrong on its own with its target and the first try as references (heads come out too wide, faces get
   drawn, ears get attached); record that brief in `references/prompts.json`. A face drawn anyway can be taken off
   with `parts/blank.py` (it fills the features from the paint beside them).
4. **Cut and name.** `python3 companions-2d/parts/cut.py <name>` keys the magenta out and writes each piece and an
   `index.png` with their numbers (working files, not kept); name them in `parts/<name>.json` (`head`, `torso`,
   `armL`, `armR`, `footL`, `footR`, and any ear or tail names its file uses; `armL` and `footL` are the ones on the
   viewer's left, or the mittens and toes point inward; `"other:1"` takes piece 1 of a part
   painted on its own), then `cut.py <name> --install`.
5. **Paint the rig.** End the species with `.painted("<name>")`; ears, antennae and tails use `Painted("<name>/earL",
   over: outline)` in their layers. A part painted already leaning (ears, tails) gets its outline turned to match
   and its own angle 0; `turn` and `mirrored` fix a part painted lying another way; `nudge` and `grow` place a part
   (a body nudged up and grown sits wide under the chin, with no pinched neck). A painting is fitted over its outline's
   bounds by area in its own proportions: an outline must take in all that is painted on the part (a head's ears and
   headphones), in about the painting's proportions; a part painted far off them is better painted again.
6. **Review.** `swift run sidefolk-render out/ --only <name>`: every state, prop, gaze, size and the hit shapes, and
   `overlay-<name>.png`, the rig beside and over its target. `swift run sidefolk-render --live <state> <seconds>
   <name> --film out/` films the motion. `make test`: every companion holds every state and stays in the window
   (draw it smaller with `scale` if not).
7. **In the app.** `make dev`, then `swift scripts/dev.swift companion:<name>:2d` and `snap` (a gallery companion
   needs its pack in `$SIDEFOLK_HOME/Addons/Companions/<name>/`).

**A companion kept on one Mac** (added from a folder, D60) can't have a rig in the app's code: its 2D form is data
in its folder's `2d/` (D79): the same paintings in `2d/paint/`, and the outlines, face and colours you would write in
`<Name>.swift` as `2d/species.json` (`docs/research/lively-companions.md`, "Custom companions": `body.look: "flat"`,
`face.screen` and `glow` for a visor face, `paint`). Steps 1–4 are the same; check it with `swift run sidefolk-render
--check-companion <folder>/2d`, add the folder again, and switch with `swift scripts/dev.swift companion:local:<name>:2d`.
