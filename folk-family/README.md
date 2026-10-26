# Folk Family — companion concepts

Static, reference-led character artwork for choosing Sidefolk's appearance. The 13 concepts are the
main Sidefolk robot, redesigned legacy Mochi and Spark, and the ten named Folks from the supplied
family sheet. These are character concepts; animation rigs and pose sets are a separate next step
after a design is selected.

Open `character-sheet.png` for the complete labeled lineup, `main-companions.png` for the three main
directions, or `folk-family-sheet.png` for the ten Folks.

| # | Character | Direction / identity | Image |
|---|---|---|---|
| 01 | Sidefolk | The original main companion | [PNG](sidefolk/sidefolk.png) |
| 02 | Mochi | Redesigned legacy rabbit | [PNG](mochi/mochi.png) |
| 03 | Spark | Redesigned legacy robot | [PNG](spark/spark.png) |
| 04 | Pip | Ideas & notes | [PNG](pip/pip.png) |
| 05 | Byte | Code & development | [PNG](byte/byte.png) |
| 06 | Seed | Growth & learning | [PNG](seed/seed.png) |
| 07 | Melody | Music & focus | [PNG](melody/melody.png) |
| 08 | Scout | Search & research | [PNG](scout/scout.png) |
| 09 | Tempo | Tasks & calendar | [PNG](tempo/tempo.png) |
| 10 | Play | Fun & entertainment | [PNG](play/play.png) |
| 11 | Guard | Security & privacy | [PNG](guard/guard.png) |
| 12 | Nova | Design & creativity | [PNG](nova/nova.png) |
| 13 | Brew | Productivity & rituals | [PNG](brew/brew.png) |

Each named folder contains `<name>.png` (the clean transparent export) and `source.png` (the untouched
imagegen output). The exports preserve the character artwork; only extraction flecks and nearly
opaque alpha are cleaned for reliable display against light and dark backgrounds. Names on the
comparison sheets are typeset separately, so no generated text is baked into the characters.

`prompts.json` records the exact prompts and reference inputs. `references/folk-family-full.png` is
the user-supplied identity sheet. The legacy Mochi/Spark idle references came from repository commit
`fc36151`. Artwork uses built-in imagegen. None of these new concepts is installed as an animated
companion by this asset-generation task.

Rebuild the clean exports and labeled sheets from the saved source PNGs, without model calls:

```sh
swiftc -O scripts/companion-concept-sheets.swift -o build/companion-concept-sheets
build/companion-concept-sheets
```
