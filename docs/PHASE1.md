# Phase 1 log

Goal: a pet you would keep running all day. No AI needed for any of it.

## Hero character concept · done

Generated two concept sheets with image generation: a four-view turnaround and an eight-state pose
sheet. They show an ivory chibi bunny with charcoal points, a mint scarf and a floating status
light. The spec (proportions, palette, light colors, rig contract) is in [art/HERO.md](../art/HERO.md).

## Hero in Blender · done

`npm run model` builds the hero headlessly in Blender 5.2 (`art/blender/build_hero.py`) and
exports `public/models/hero.glb`: 9,392 vertices, 15 bones (two per ear), 13 clips that each
key every bone, vertex colors, 1 MB. The app loads it with toon shading and an outline on the
`Body` mesh only, and a floating status light (`src/pet/orb.ts`) follows the head with the
colors from the spec. The primitive placeholder rig is gone.

Checked in the browser preview against the concept sheets: idle, walk, think (paw on chin, one
ear bent), alert (sign held beside the head, orange light), celebrate (happy eyes, green light),
sad (lop ears), sleep (eyes closed, ears folded back). The desktop overlay reloaded with the
model without errors.

Known gaps: the stubby arms cannot reach above the big head, so "arms up" poses end at cheek
height; the "!" on the sign is small at real size.

## Non-activating overlay · done

The overlay is now an `NSPanel` (via `tauri-nspanel`):

- Non-activating style mask, floating level, never hides on deactivate.
- Becomes key only when a view needs it, and Sidefolk hands keyboard focus back after every
  click unless you are typing in the bubble.
- Typing uses `makeKeyWindow` and `resignKeyWindow`, never app activation.

Checked from the log: with the bubble's text field open the overlay held keyboard focus while
the app you were using stayed frontmost, and closing it released focus with that app still
frontmost.

**Hand check passed (23 October):** nine clicks and drags on the pet while typing in Claude. After
every one, Claude stayed frontmost and the overlay did not hold keyboard focus. Before the
"hand focus back after each click" fix, a click left the overlay as the key window, which would
have swallowed the next keystrokes.

Fixed along the way: after the overlay refit to a smaller display, the pet could sit outside
the new bounds until it walked back. It is now clamped on every refit.

## Full-screen Spaces · done

Collection behavior: all Spaces, full-screen auxiliary, stationary, ignored by window cycling.
The overlay re-checks its display's work area every second and refits when it changes (Dock or
menu bar hiding, full-screen Spaces, display changes), so the pet stays on the right floor.

**Hand check passed (23 October):** with an app in full screen on the built-in display, the pet
stayed visible over it. The log agrees: the panel stayed on the active Space and unoccluded
throughout, and no refit fired.

Still open: macOS reports the same work area inside a full-screen Space, so with a visible Dock
the pet would walk at the Dock's height there rather than on the bottom edge. Not visible on this
setup (the Dock is hidden); handle it when the pet learns about Spaces.
