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

## CPU (Phase 1 exit)

- `AppHandle::cursor_position` sends a message to the main thread and waits. At 30 Hz that kept
  AppKit and WebKit's run-loop observers busy. `CGEventCreate(NULL)` + `CGEventGetLocation`
  gives the same global points on any thread.
- WebKit's libpas scavenger thread runs inside the app process and woke for every frame (~2% of
  a core). Setting `Malloc=1` at the top of `main` (before WebKit allocates) switches this
  process to the system allocator and the thread disappears. Web content is unaffected.
- Profile with `sample <pid> 8 -file out.txt` and read "Sort by top of stack"; release
  binaries are stripped, so look at system frames.
- `top` averages over 30 s runs vary by a couple of percent; compare with `npm run measure`.

## Crew, reminders, MCP, custom pets (24 October 2026)

- 23 October 2026 was a Friday. Write date tests from a fixed `now` and check the weekday.
- chrono-node reads "at 3" as 03:00; `when.ts` moves bare hours 1–7 to the afternoon unless
  am/pm is given, and leaves ISO times alone.
- `claude --allowedTools a b "prompt"` swallows the prompt as another tool name. Use
  `--allowedTools=Read` or put the prompt first.
- `claude mcp add --scope user` writes `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`);
  `codex mcp add` writes `~/.codex/config.toml` (or `$CODEX_HOME`). Point those variables at
  temp folders to test without touching real configs.
- MCP over stdio is JSON-RPC 2.0 with `"jsonrpc"`, unlike Codex app-server. Echo the client's
  `protocolVersion`; `clientInfo.name` tells Claude Code from Codex.
- Tauri raw responses (`tauri::ipc::Response`) arrive in the page as an `ArrayBuffer`;
  `GLTFLoader.parseAsync(buffer, "")` loads them.
- Blender: actions outlive their objects. When exporting several species in one run, remove
  `bpy.data.actions` (and meshes, armatures) between builds or the next export carries
  ".001" duplicates.
- Ellipsoid rotations in build_hero.py: a negative x rotation tips +y toward -z (backwards).
  The first fox tail leaned forward into the body.
- Look changes are async (model loads); apply them in order on top of each other, or quick
  clicks race (a slow fox load overwrote a palette change).
- The browser pane throttles timers and rAF when it is not in front (about 1 frame/s) and can
  show a stale screenshot; take a second screenshot or check state with JS.
- `tauri dev` did not rebuild after Rust edits made while `cargo build` also ran; restart it if
  the log shows no new "Running" line.
- `open` drops environment variables; run `Sidefolk.app/Contents/MacOS/sidefolk` directly to
  pass `SIDEFOLK_DATA_DIR`.
- Apple's Foundation Models framework is present on macOS 27, but `SystemLanguageModel.default`
  reported `modelNotReady` here (model assets not downloaded).

## UI, sound, icons (24 October 2026, later)

- A chip under a text field must `preventDefault` on mousedown, or the field's blur closes the
  prompt before the click lands.
- `say` takes embedded commands: `[[pbas 60]] text` changes the pitch base. Escape `[[` in
  untrusted text. `say -o file.aiff` checks it silently; `say -v '?'` lists voices.
- Tray icon: `tauri::image::Image::from_bytes` needs the tauri `image-png` feature;
  `icon_as_template(true)` tints a black-on-transparent PNG for light and dark menu bars.
  Tauri scales it to the menu bar height, so one 44 px image is enough.
- Blender Workbench renders vertex colors grey with the default view transform; set
  `view_settings.view_transform = "Standard"` (still a little dark with studio light, so
  scripts/make_icons.py brightens the render).
- `npx tauri icon` writes Windows, iOS and Android sizes too; write to a temp folder and copy
  the five files tauri.conf.json lists.
- Rebuilding the release bundle while it runs is fine; the running copy keeps its loaded
  binary until relaunched.
- Flat face decals on a curved head stand off the skin away from their center, so a big face
  patch hides eyes placed near its edge. Lift the eyes (`eyes(..., lift=)`) above the patch.
- The hook server sees Claude Code's TCP peer port (`into_make_service_with_connect_info`);
  `lsof -nP -t -iTCP@127.0.0.1:<port>` lists both ends, so drop Sidefolk's own pid.
- `ps -axo pid=,ppid=,tty=,comm=` gives full executable paths; the outermost `.app/` in the
  path is the hosting app (VS Code's helpers live inside VS Code.app).
- Sample data for the window (`src/dashboard/api.ts`) is created lazily, so the dashboard
  modules import cleanly in vitest (no `window` or `location` at import time).
- The browser pane sometimes returns a stale screenshot after a JS change; take a second one.
- WebKit (the app's engine) can be driven headless with Playwright: `npm run check:webkit`
  loads every view of the preview and fails on page or console errors. WebGL portraits render
  there too. The in-app browser pane is not WebKit.
- Loom's wool puffs covered its scarf: details meant to read at 140 px must sit outside the
  outermost silhouette shapes, not just in front of the core body.
- Fewer mesh segments don't break recoloring: palette regions are matched per vertex, and
  vertex colors stay exact; only the rendering interpolates between them.
- A character picker should show characters in their own designed looks; showing every body
  in the current companion's coat made them hard to tell apart.

## UI redesign verification (24 October 2026)

- Prevent the Tell field's Enter default before awaiting a folder lookup and
  opening a native HTML dialog: focus moves to its close button, and the original
  Enter's default action can otherwise immediately close the new dialog.
- A live notebook refresh should update entries, keeping capture text and an
  unfinished edit. Defer entry redraw while editing, then refresh on Save/Cancel.
- In Vite browser checks, dynamically importing an unversioned API URL after HMR
  can create a separate preview store. Use the API resource URL already loaded by
  the page when injecting an incoming event in a regression test.

## Tests must never reach the user's real files (25 October 2026, Claude Code)

A first version of the uninstall test called code that reads `~/.claude.json` and
`~/.codex/config.toml`, runs `claude mcp remove` / `codex mcp remove`, and deletes
`~/Library/LaunchAgents/Sidefolk.plist`. `cargo test` then removed the user's real Sidefolk MCP
entries and login item. The backups went into the test's temp folder, which the test deleted.

Rules:
- Any function that touches agent configs, the login item or other paths under `$HOME` takes
  those paths as arguments (`uninstall::Places`). Tests pass temp paths and an empty agent list.
- Never call `Agent::installed()`, `mcp_setup::run()` or the autostart plugin from a test.
- A test that is much slower than the others (seconds rather than milliseconds) probably spawned
  a CLI: stop and check what it touched (`stat` on `~/.claude.json`, `~/.codex/config.toml`).

## Claude Code must only run a Sidefolk that knows `hook` (25 October 2026)

The hook line runs `<app> hook`. A binary from before command hooks doesn't know `hook` and
starts the whole app instead, once per tool call. Only new versions install the line, so the risk
is a downgrade after installing. Don't test `hook` against an old binary (a stale
`target/release/sidefolk` started a full app copy this way).
