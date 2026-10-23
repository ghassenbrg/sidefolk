# Learnings

Things that cost time to discover. Add to this when something surprises you.

## macOS overlay (Tauri / WebKit)

- WebKit throttles `requestAnimationFrame` to about 8 fps in the overlay unless the window has
  `"backgroundThrottling": "disabled"` (tauri.conf.json). With it: 30 fps. WebKit still caps this
  window at 30 fps.
- Rendering stops completely when the overlay is hidden (locked screen, other Space): free.
- `setFocus()` activates the app and steals focus. Use the `overlay_typing` command
  (`makeKeyWindow` / `resignKeyWindow` on the panel) instead.
- Clicking the web view makes the panel key even with `becomesKeyOnlyIfNeeded`, so the page
  calls `overlay_typing(false)` after every pointerup unless the bubble is in typing mode.
- Don't swap tao's window class by hand: `TaoWindow` has a `focusable` ivar tao reads later.
  `tauri-nspanel` handles the conversion.
- `AppHandle::cursor_position`, `monitor_from_point`, and `Monitor::work_area` exist in Tauri
  2.12. The overlay refits to its monitor's work area every second.
- Inside a full-screen Space, macOS still reports the normal work area (with Dock and menu bar).

## Claude Code hooks

- `type: "http"` hooks POST JSON straight to the app. Empty 2xx body = no decision; connection
  failure = non-blocking. `SessionStart` did not arrive over HTTP (probably command-only).
- `PermissionRequest` fires in headless `-p` mode too; with no decision headless mode denies.
  Answer shape: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`.
- While the hook holds a permission (60 s), the terminal prompt waits too.
- To run `claude` from inside an agent session: `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude ...`.

## Codex app-server

- Newline-delimited JSON-RPC **without** the `"jsonrpc"` field. `initialize` → `initialized`
  notification → `thread/start` → `turn/start`.
- Generate exact types with `codex app-server generate-ts --out <dir>`.
- `codex` is a Node script (`#!/usr/bin/env node`); GUI apps need `/usr/local/bin` on PATH.
- Unanswered approval requests wait forever; there is no terminal fallback.

## three.js character

- Clips that key every bone avoid bones being left behind when crossfading.
- Gaze and blinking are applied after `mixer.update` each frame (head quaternion multiply, eye
  bone scale).
- A SkinnedMesh's cached bounding sphere rejects raycasts when limbs move; set a generous one.
- Face features placed by hand ended up buried inside the head sphere: place them on the
  surface with a helper.

## Blender (5.2, headless)

- Run with `blender --background --factory-startup --python <script>`.
- glTF export: `export_animation_mode='ACTIONS'`, `export_vertex_color='ACTIVE'` to get COLOR_0.
- Bones pointing straight up (+Z) with roll 0 export with identity rest rotation, so bone-local
  axes match the app's (x right, y up, z toward viewer).
- three.js Euler 'XYZ' (R = Rx·Ry·Rz) equals mathutils Euler order 'ZYX'.
- Hand-built torus faces must be wound so normals face outward, or the inverted-hull outline
  draws over the front (the scarf rendered as a dark band).
- With these stubby arms, a straight-up arm leaves the paw at cheek height; props held up must
  sit on a long stick held out to the side.
- Verify export structure without Blender: parse the GLB JSON chunk with Node
  (`node -e` reading bytes 20..20+len) and check joints, rotations, animations.


## Daily-driver pack

- macOS global-shortcut 2.4.1 supports `CommandOrControl+Shift+Space`. Dispatch shortcut actions
  onto the main thread before using `tauri-nspanel` show/hide. Keep dialog 2.8.3 confirmation
  nonblocking (`show`); writes run off the main thread and menu refresh returns to it.
- `serde_json` with `preserve_order` needs `shift_remove` (not swap-removal) when deleting keys.
  Reinstall must also keep the original `hooks` key position if removing old Sidefolk handlers
  temporarily empties it. Regression tests cover both cases.
- `CGEventSourceSecondsSinceLastEventType(0, u32::MAX)` provides keyboard-and-mouse idle without
  screen capture permissions. Ignore cursor coordinate changes once OS idle is authoritative.
- `ioreg -n Root -d1 -a` is a plist; recurse for `CGSSessionScreenIsLocked` rather than assuming
  a top-level array. `plutil` to JSON plus Node works in the measurement script. No visible-CPU
  claim is valid while locked. macOS removes `CGSSessionScreenIsLocked` when unlocked; require
  an active `kCGSSessionOnConsoleKey` session and no true lock flag, rather than a literal false
  flag. Keep the benchmark awake even if OS idle was already long.
- Resource sampling must not match every new `*Helper*` process: a Chrome extension renderer
  started during warm-up and contaminated the first attempt. Match the measured app path and
  the newly launched WebKit/audio XPC services; unrelated browser helpers are excluded.
- This agent shell did not include Cargo on PATH. Use `~/.cargo/bin/cargo`, or add that directory
  to PATH for `npm run dev` / `npm run build`.
