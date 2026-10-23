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


## Daily-driver pack · done

- Atomic JSON settings in the app data directory, or `SIDEFOLK_DATA_DIR`. The Codex playground
  shares that directory unless `SIDEFOLK_WORKDIR` is set.
- Grounded x saves every ~5 s after movement >8 px, restores and clamps on startup. Monitor
  name and hidden state persist; missing monitors fall back to the cursor display.
- Global ⌘⇧Space hides/summons with squash and wave. Tray: Hide/Show, Call pet here,
  Connect/Disconnect Claude Code…, Move to this display, Quit. Registration errors appear
  in the tray; native panel show/hide preserves the non-activating overlay.
- macOS CoreGraphics combined-session idle arrives every ~1 s. Two minutes without input
  triggers sleep; recent input (<0.5 s idle) wakes with a wave. Browser preview uses cursor
  stillness. Agent directives still take precedence over the autonomous routine.
- The Claude installer preserves JSON key order and unrelated hooks/preferences. It confirms
  asynchronously, backs up exact original bytes under `backups/claude-settings-<unix ns>.json`,
  then writes atomically. Missing settings start as `{}`; invalid JSON/shapes are refused.
  If settings changed while confirmation was open, the app asks the user to retry. Uninstall
  removes only handlers whose URL starts with `http://127.0.0.1:47821/`, then empty containers.
- Permission holds are disabled by `pet_answers_permissions=false`. Otherwise terminal/IDE/
  Claude foreground apps defer immediately; other apps get up to 60 s on the pet. Failure to
  read the foreground app also defers. Notification hooks continue to show waiting.

Verified: typecheck, Rust build/test after each implementation step. Eight regular Rust tests
pass; the ninth opt-in test also passed against a temporary copy of the user's real settings
with `SIDEFOLK_CLAUDE_SETTINGS`. The original file's SHA-256 stayed unchanged. No Codex global
configuration edits, screenshots or commits. Automated verification made no model calls.

Desktop `[ui]` logs confirmed x=321 restore, hide/show, summon clamping to x=1442, and x=1442
restore after restart. A disconnected-monitor fixture fell back and saved the current monitor;
a bogus shortcut logged its registration error. A synthetic hook request resolved Allow through
`/dev/resolve`; disabled pet permissions returned an empty 200 in 14 ms. Notification emitted
waiting. Headless Mind behavior checks passed bounds, summon, OS sleep/wake and browser fallback.

**Visible CPU / memory (23 October): 16.9% average CPU, 244.1 MB memory.** Release bundle:
4.17 MiB. Recorded after 15 s warm-up and 60 s sampling with the screen unlocked and pet sleep
disabled. Includes Sidefolk, WebKit GPU/WebContent/Networking and the audio sandbox helper;
see PHASE0 for the breakdown. Screen lock was checked throughout. The script handles macOS
omitting the lock flag when unlocked and excludes unrelated Chrome helpers. An earlier
contaminated run was discarded. Final typecheck, Rust build/test and shell syntax checks passed.

An isolated dev run after the measurement confirmed `vis=visible`, `unoccluded=true` and
27 renders/s in its first startup interval, with the panel not holding keyboard focus.

**Hand checks accepted (23 October):** the user replied “looks fine” to the requested
⌘⇧Space hide/summon, tray Hide/Show and Call pet here, Connect/Cancel/Disconnect on the test
copy, and two-minute idle/typing wake checks. No issues reported. Subsequent dev logs show
steady 30 renders/s, pet interactions and keyboard focus released after typing. A Codex greeting
round-trip also appears in the interactive dev log; automated checks did not initiate it.
Extended multi-display/Space coverage can continue during daily use. The isolated dev app is
left running, and the next Phase 1 step is to live with the pet for a few days.
