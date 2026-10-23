# Status

Last updated: 2026-10-23 by Claude Code (Opus 5.5), after the Blender hero swap.

## Where things are

- Branch `rework`. Commits: `01e2f6e` Phase 0 spikes, `6ce076e` Phase 1 concept + panel +
  full-screen, then the Blender hero swap with the handoff setup. Not pushed.
- Phase 0: done (docs/PHASE0.md). Phase 1: in progress (docs/PHASE1.md).
- Done in Phase 1: hero concept sheets and spec (art/), non-activating panel, full-screen Spaces
  (both hand-checked by the user).

## Just finished: hero built in Blender and swapped in (committed)

`npm run model` → `public/models/hero.glb` (+ `art/blender/hero.blend`). App side:
`src/pet/model.ts` (loader, toon, outline, contract checks), `src/pet/orb.ts` (status light),
`src/pet/clips.ts` (names only). `src/pet/rig.ts` deleted. Verified in the browser preview at
`?zoom=2.5` for idle, walk, think, alert, celebrate, sad, sleep; the desktop overlay loaded the
model without errors (screen was locked, so no live look yet). Details in docs/PHASE1.md.

## Next after that

Phase 1 backlog (docs/PHASE0.md): global summon shortcut, OS idle time for sleep, auto-hide
during screen sharing, follow the cursor across displays, window awareness.

## Open questions for the user

None right now.
