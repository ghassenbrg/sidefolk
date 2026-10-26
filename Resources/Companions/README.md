# Sprite companions

Mochi (`mochi/`) and Spark (`spark/`) are the two characters from the founder's earlier design,
offered in Settings › Companion beside the original vector Sidefolk robot (D27). Mochi is now the
default and the brand mascot (D29); the robot and all its light-color controls remain available.

## Source

The characters come from the founder's earlier design: the legacy app on the `main` branch has them as
`public/crew/pip/3d/*.webp` (the bunny, called Pip there; renamed Mochi because Pip is the coral folk
in the Folk Family) and `public/crew/spark/3d/*.webp`. Those frames were keyed out of lossy chroma-green
sheets about 300 px tall and kept green fringes, so the poses here were made again on 26 October 2026
with Codex image generation, with a real alpha channel at about 1250 px:

- each companion's idle was generated from its legacy idle and wave frames;
- every other pose used the new idle as the reference for character, scale and framing, and the
  legacy frame of that pose only for the posture;
- `generation-prompts.json` has every brief and reference;
- `scripts/companion-art.swift` turns the generated pictures into these 512 × 512 PNGs: one scale per
  companion taken from idle, the feet on one baseline, and the corrections in `<id>-scale.json` for
  poses the model drew a little larger or smaller than idle.

The new rabbit branding grades all 16 Mochi poses from cream/black/mint to white/navy/mint-aqua with
`scripts/rebrand-mochi.swift`. It preserves each pose's exact pixel dimensions and alpha, so the
animation scale, alignment and hit regions do not change. Original ungraded poses are archived in
`masters/mochi-legacy/`; repeated builds always use those originals, not previously graded exports.
Spark and the original robot are unaffected by this palette pass.

## Licence

The founder's own art, made for Sidefolk. It is covered by the repository's LICENSE (all rights
reserved, D17) like the rest of the app; no third party holds rights in it, so it is not listed in
THIRD_PARTY_NOTICES.md.

## Poses

Each folder has the same 16 files: `idle`, `blink`, `listen`, `think`, `work1`, `work2`, `write1`,
`write2`, `note`, `alert`, `sad`, `done`, `wave`, `sit`, `sleep`, `dangle`. A companion whose folder
misses one is not offered. How states map to poses is in docs/CHARACTER.md.

`scripts/build-app.sh` copies the folders (not this README) to `Contents/Resources/Companions/`.
`SpriteSet` scales the idle pose to the robot's height and stands it on the same floor line.
Review them with `swift run sidefolk-render <dir>` (`companion-<name>*.png`).
