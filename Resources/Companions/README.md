# Sprite companions

Mochi (`mochi/`) and Spark (`spark/`) are the two characters from the founder's earlier design,
offered in Settings › Companion beside the vector Sidefolk robot (docs/DECISIONS.md D27).

## Source

Copied unchanged from the legacy app on the `main` branch: `public/crew/pip/3d/*.webp` (the bunny,
called Pip there; renamed Mochi because Pip is the coral folk in the Folk Family) and
`public/crew/spark/3d/*.webp`. The legacy `art/crew/README.md` describes how they were made: two
4×2 pose sheets per character, generated with Codex image generation from the founder's reference
photos (24 October 2026), then cut by `scripts/make_sprites.py` into transparent 420×380 WebP
frames, scaled alike, with the feet on one baseline.

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
