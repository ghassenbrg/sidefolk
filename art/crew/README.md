# The crew

Ten built-in characters, from the user's reference photos in `refs/` (24 October 2026), each in
two styles: `3d`, soft matte clay renders like the photos, and `2d`, flat drawings of the same
design. Settings → Companion picks your companion and the style; each Spark worker picks its own
character in Sessions. The ids and names are in `src/roster.ts`.

| # | Id | Name | Character |
|---|---|---|---|
| 1 | spark | Spark | Robot, the default Spark worker |
| 2 | pip | Pip | Bunny with a mint scarf, the default companion |
| 3 | pebble | Pebble | Penguin |
| 4 | capy | Capy | Capybara in a mint hoodie |
| 5 | nova | Nova | Alien |
| 6 | lumi | Lumi | Cloud spirit (creative assistant) |
| 7 | pixel | Pixel | Cat with glasses (productivity companion) |
| 8 | otis | Otis | Otter with a phone (hands-on helper) |
| 9 | rune | Rune | Owl with a monocle (knowledge expert) |
| 10 | sprout | Sprout | Tiny plant creature (calm focus assistant) |

Names 6–10 and their roles are the user's; 3–5 are placeholders until they name them.

## Making the frames

Each style is two 4×2 pose sheets on chroma green, generated with Codex image generation:

```sh
scripts/crew_art.sh <id> 3d a   # the photo, plus Pip's 3d sheet a for layout and poses
scripts/crew_art.sh <id> 3d b   # its 3d sheet a
scripts/crew_art.sh <id> 2d a   # its 3d sheet a, redrawn flat
scripts/crew_art.sh <id> 2d b   # its 3d sheet b, matched to its 2d sheet a
npm run sprites -- <id> 3d      # cuts public/crew/<id>/3d/<pose>.webp
```

The briefs are in `scripts/crew_art.sh`. Sheet a: idle, blink, listen, think, work1, work2, alert
(card with an orange "!"), sad. Sheet b: note, write1, write2, done, wave, sit, sleep, dangle.
Every character wears the same mint accent, so a Spark's color turns only the mint pixels
(`src/recolor.ts`) and leaves fur and faces as drawn.

`scripts/make_sprites.py` finds each pose by the empty space around it, keys out the green and its
fringe, scales the sheet so the first pose stands 300 px tall (at most 260 px wide), puts the feet
on one baseline, adds the ivory sticker outline and writes WebP at quality 90 (about 160 KB a set).
Look at every sheet before cutting: a pose that drifts from the character means generating that
sheet again.
