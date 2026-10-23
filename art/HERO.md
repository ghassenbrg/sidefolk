# Hero character

Concept sheets (generated with image generation, October 2026). These are references for
modeling, not shipped assets:

- [concepts/hero-turnaround.png](concepts/hero-turnaround.png): front, three-quarter, side, back
- [concepts/hero-poses.png](concepts/hero-poses.png): the eight states the pet acts out

## Design intent

A small chibi bunny who reads at about 140 px on any wallpaper. The ivory body carries dark
wallpapers; the charcoal "points" (ear tips, paws, feet, tail) carry light ones. The ears do most
of the emotional work: perked, bent, flying, drooping, folded. A floating light next to its head is
the agent status signal, readable in peripheral vision without any text.

## Proportions (feet at 0, total height about 2.35 units)

| Part | Shape | Notes |
|---|---|---|
| Head | Slightly wide sphere, about 45% of height | Big glossy eyes set wide, one highlight each |
| Body | Soft bean | Cream belly patch |
| Arms | Short stubby capsules, round paws | Charcoal paws; rest slightly away from the body |
| Legs | Short, oval feet | Feet fully charcoal |
| Ears | Long, rounded tips, about one head tall | Charcoal tips, pink inner ear; flare slightly outward |
| Tail | Small round puff | Charcoal |
| Scarf | Short knitted mint scarf | One end hanging at the character's front right |
| Light | Separate glowing orb, never attached | Floats above one side of the head |

## Palette

| Use | Hex |
|---|---|
| Coat | `#F1E4D2` |
| Muzzle, belly | `#FFFAF3` |
| Points (ear tips, paws, feet, tail) | `#4A3F4F` |
| Inner ear | `#F3AAA8` |
| Blush | `#F7A5A0` |
| Scarf | `#6FCFB4` |
| Outline | `#3B3342` |

## Status light

| State | Glow |
|---|---|
| Idle, waving, picked up | Pale amber |
| Thinking | Soft blue |
| Working (reading, editing, running) | Warm amber |
| Needs you | Bright orange |
| Done | Mint green |
| Failed, sad | Dim gray-violet |
| Asleep | Faint |

## Build

`npm run model` runs [blender/build_hero.py](blender/build_hero.py) headlessly. It models the
character from primitives in app space, paints vertex colors, rigs it, keys the clips, and
writes `public/models/hero.glb` plus the editable [blender/hero.blend](blender/hero.blend).
The script is the source of truth until an artist takes over the `.blend`; then the export
settings at the bottom of the script still apply.

Two meshes: `Body` (gets the outline: head, body, limbs, ears, tail, scarf) and `Face`
(details without outline: eyes, highlights, brows, nose, mouth, blush, muzzle, belly, inner
ears). All bones point straight up with no roll, so they export with identity rest rotations.

## Rig contract

The glTF must use these bone names (checked at load in `src/pet/model.ts`): `root`, `hips`,
`chest`, `head`, `earL`, `earLTip`, `earR`, `earRTip`, `eyeL`, `eyeR`, `armL`, `armR`, `legL`,
`legR`, `tail`. The tip bones let the ears bend (thinking) and hang (sad). The app scales the eye
bones to blink, so eye geometry must be weighted to them alone.

Clips, named as in `src/pet/clips.ts`: `idle`, `walk`, `sit`, `sleep`, `wave`, `think`, `read`, `work`,
`celebrate`, `alert`, `sad`, `dangle`, `fall`.
