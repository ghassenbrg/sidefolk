# Status

Last updated: 2026-10-23 by Claude Code. Daily-driver pack complete (still uncommitted); user
hand checks accepted. Roadmap agreed with the user: [docs/ROADMAP.md](../docs/ROADMAP.md).

## Where things are

- Branch `main` (the rework branch was renamed to `main` and pushed to `origin/main`).
  Commits: `01e2f6e` Phase 0 spikes, `6ce076e` Phase 1 concept + panel + full-screen,
  `8d5197c` Blender hero + handoff setup. The old app is the local tag `legacy-v0` (not pushed).
- Phase 0: done (docs/PHASE0.md). Phase 1: in progress (docs/PHASE1.md).
- Done in Phase 1: hero concept sheets and spec (art/), non-activating panel, full-screen Spaces
  (both hand-checked by the user).

## Just finished: hero built in Blender and swapped in (committed)

`npm run model` → `public/models/hero.glb` (+ `art/blender/hero.blend`). App side:
`src/pet/model.ts` (loader, toon, outline, contract checks), `src/pet/orb.ts` (status light),
`src/pet/clips.ts` (names only). `src/pet/rig.ts` deleted. Verified in the browser preview at
`?zoom=2.5` for idle, walk, think, alert, celebrate, sad, sleep; the desktop overlay loaded the
model without errors (screen was locked, so no live look yet). Details in docs/PHASE1.md.

## Daily-driver pack · complete

Requested by the user on 2026-10-23. All seven checklist items are complete. The user replied “looks fine” to the
shortcut, tray/installer and sleep/wake hand-check request. Required typecheck/build/test checks passed after each implementation step.
Everything remains uncommitted on main. Existing AGENTS.md and memory edits were preserved.
Commit only when the user asks; no Co-Authored-By trailer.

- [x] **1. Settings store** (`src-tauri/src/settings.rs`). JSON file in the data dir
      (`app.path().app_data_dir()`, overridable with env `SIDEFOLK_DATA_DIR` for tests and
      `scripts/measure.sh`). Atomic save (temp file + rename). Fields, all `#[serde(default)]`:
      `pet_x: Option<f64>`, `display: Option<String>` (monitor name), `hidden: bool`,
      `shortcut: String` (default `CommandOrControl+Shift+Space`), `sleep_after_secs: u64`
      (default 120), `pet_answers_permissions: bool` (default true). Keep it in `Shared`.
      Also move the Codex playground under the same data dir.
- [x] **2. Persist pet state.** Commands `get_settings` and `save_pet { x }`. Page restores
      `mind.x` on start (clamped by `mind.fitBounds()`), saves every ~5 s when x moved > 8 px and
      the pet is on the ground. Rust fits the overlay to the saved display by name if
      connected, else the cursor's display, and saves the display name on every fit.
- [x] **3. Global summon shortcut** with `tauri-plugin-global-shortcut` 2.4. Press: if hidden,
      move the overlay to the cursor's display, show the panel, emit `summon {x}` so the page
      puts the pet under the cursor (squash + wave); if visible, hide (`panel.hide()`). Persist
      `hidden`. On registration failure, log it and show it in the tray. Tray menu (rebuild
      the labels on change): Hide/Show pet, Call pet here, Connect/Disconnect Claude Code…,
      Move to this display, Quit.
- [x] **4. Sleep from OS idle time.** macOS FFI, no permissions needed:
      `#[link(name = "CoreGraphics", kind = "framework")] extern "C" { fn
      CGEventSourceSecondsSinceLastEventType(state: i32, kind: u32) -> f64; }`, called with
      `(0, u32::MAX)` (combined session state, any input). Emit `idle` seconds once a second from
      the cursor thread in `overlay.rs`. In `src/mind.ts` replace `cursorStill` with `idle`:
      `setOsIdle(s)` is authoritative in Tauri; the web preview falls back to cursor stillness.
      Sleep after `sleep_after_secs`; wake (wave) when idle < 0.5 s. Typing in any app wakes it.
- [x] **5. One-click Claude Code hook install** (`src-tauri/src/claude_setup.rs`).
      - Target `~/.claude/settings.json` (env `SIDEFOLK_CLAUDE_SETTINGS` overrides for tests).
        Missing file → create `{}`. It is strict JSON; use `serde_json` with the
        `preserve_order` feature so the user's key order survives.
      - Pure functions with unit tests: `install(Value) -> Value` adds one matcher group per
        event (same events and URLs as `hooks/claude-settings.json`) after removing old Sidefolk
        groups; `uninstall(Value) -> Value` removes only handlers whose `url` starts with
        `http://127.0.0.1:47821/`, then empty groups and empty event arrays, then an empty
        `hooks` object; `is_installed(&Value)`. Tests: empty file, the user's real shape (it has
        a `SessionStart` group plus `enabledPlugins`, `theme`...), reinstall is idempotent,
        uninstall leaves everything else byte-for-byte equal after re-serializing.
      - Before writing: back up to `<data dir>/backups/claude-settings-<unix ts>.json`. Write
        atomically.
      - Tray item → confirmation dialog (`tauri-plugin-dialog` 2.8, async `show`, not
        `blocking_show` on the main thread) that says what changes, that it applies to new
        Claude Code sessions, and where the backup goes.
      - **Permission hold policy** in `hooks.rs`: if `pet_answers_permissions` is false, or
        the frontmost app is a terminal, IDE or the Claude app, return an empty 200 at once so
        that app's own prompt shows (the Notification hook still makes the pet show it's
        waiting). Otherwise hold up to 60 s for Allow/Deny on the pet. Frontmost bundle id via
        `NSWorkspace` on the main thread (see `panel::focus_report`). Defer list:
        com.apple.Terminal, com.googlecode.iterm2, dev.warp.Warp-Stable, com.mitchellh.ghostty,
        net.kovidgoyal.kitty, org.alacritty, com.microsoft.VSCode, com.todesktop.230313mzl4w4u92
        (Cursor), dev.zed.Zed, com.jetbrains.* (prefix), co.zeit.hyper,
        com.anthropic.claudefordesktop.
      - Verify against a COPY of the user's real settings via the env override. Do not install
        into the real file yourself; the user clicks it.
- [x] **6. Visible-CPU measurement.** Stop any dev instance first (port 47821). Check the
      screen is unlocked (`ioreg -n Root -d1 -a` → `CGSSessionScreenIsLocked`); if locked, ask
      the user. `npm run build`, then `npm run measure` (60 s); record visible CPU and memory
      in docs/PHASE0.md (the cost table's last row) and docs/PHASE1.md.
- [x] **7. Docs.** README (tray, shortcut, connect Claude), docs/PHASE1.md, this file,
      DECISIONS (hold policy), LEARNINGS.

## Roadmap (agreed 23 October)

The user brainstormed a multi-pet idea; the agreed plan is in [docs/ROADMAP.md](../docs/ROADMAP.md)
and decisions 12–17. In short: a main pet plus a crew of pets bound to projects and agents, a
den for idle pets, a local journal and reminders, an MCP server so agents can reach the user,
and custom pets from a species kit (not image-to-3D). Order:

1. **Phase 1 exit (now):** the user lives with the pet for a few days; cut visible CPU from
   16.9% toward 5% for one awake pet. Measure first (the roadmap lists what is already
   throttled).
2. **Phase 2, Crew:** bindings, bunny color and accessory variants, den, questions from the right
   pet, call/briefing. Absorbs the earlier Phase 2 items: the sessions panel becomes the status
   card, the Codex folder picker becomes "run in the project's folder", plus the Codex approval
   timeout, the hook endpoint token and auto-hide during screen sharing.
3. Phase 3 journal and reminders, Phase 4 MCP server, Phase 5 species and customizer, Phase 6
   production (signing, auto-update, onboarding, Windows).

Phase 1 leftovers, when convenient: following the cursor across displays, window awareness, the
full-screen floor offset with a visible Dock, the "arms up" reach.

## Open questions for the user

None blocking the pack. The user confirmed the requested hand checks with “looks fine”.
Defaults remain ⌘⇧Space, 120 s idle, pet permissions enabled with foreground-agent deferral.

## Current verification

- Step 1: typecheck, cargo build and cargo test passed (2 tests: serde defaults and atomic save/reload). Cargo is at `~/.cargo/bin/cargo` in this shell. Stopped the pre-existing dev instance to avoid rebuild contention; restart with isolated data/settings for desktop checks.
- Step 2: typecheck, cargo build and cargo test passed (2 tests). Saved display fallback, hidden startup, finite x validation and ground-only 5 s position saves implemented; restore/fallback verified through logs; extended multi-display testing remains optional.
- Step 3: typecheck, cargo build and cargo test passed (2 tests); global-shortcut 2.4.1, shared tray/shortcut actions, saved visibility and summon event added. Claude tray item was disabled at that stage and enabled in step 5. Shortcut hand check accepted by the user; extended cross-Space testing remains optional.
- Step 4: typecheck, cargo build and cargo test passed (2 tests). CoreGraphics idle emitted every ~1 s; desktop idle is authoritative, threshold defaults to 120 s; browser cursor fallback retained. Typing wake was included in the hand-check request accepted by the user.
- Step 5: typecheck/build/tests passed (8 regular tests + the explicit opt-in copy test, including the final key-order regression). Tested install/backup/uninstall against `/private/var/folders/1p/lvv92k4n1vs67n8x6_w0987m0000gn/T/sidefolk-daily-2fic1zg6/claude-settings.json` via `SIDEFOLK_CLAUDE_SETTINGS`; real global settings untouched. Installer tray item now enabled. Dev log `/tmp/sidefolk-daily-dev.log`: restored x=321, hide/show, summon clamped x=1442, restart restored x=1442; synthetic permission resolved Allow and Notification emitted waiting. No model calls in automated checks. Those early checks ran locked; the later unlocked dev log confirms visible rendering. The user subsequently accepted the requested manual checks.
- Step 6 complete: release build passed (4.17 MiB). After the user unlocked the screen, the clean 60 s visible/awake run measured **16.9% CPU, 244.1 MB** across 5 processes. Log `/tmp/sidefolk-daily-measure.log`. Script fixes: an unlocked console omits the lock flag; generic `*Helper*` filtering accidentally included Chrome, so it was narrowed and that attempt discarded. Lock fixtures (4 cases) and shell syntax passed; typecheck, cargo build and cargo test rerun after recording results.
- Step 7: README, PHASE0 cost row/status, PHASE1, DECISIONS and LEARNINGS updated. Post-doc typecheck, cargo build and cargo test passed (8 regular, 1 opt-in ignored by default; opt-in separately passed).
- User hand checks (23 October): replied “looks fine” to the requested shortcut hide/summon, tray controls, Connect/Cancel/Disconnect on the copy, and idle/typing wake checks. No issues reported. Later dev logs show steady 30 renders/s, pet interactions, a Codex greeting round-trip and keyboard focus released after typing. These later interactions were not initiated by automated verification.
- Additional checks: `/tmp/sidefolk-mind-check.mjs` against TS emitted into the temp data dir passed bounds, grounded state, summon/wave, authoritative OS idle and preview fallback. Fallback dev fixture checked missing-monitor recovery, invalid-shortcut logging, hidden startup settings, x=9999 clamped to 1442. `pet_answers_permissions=false` returned empty 200 in 14 ms. Logs: `/tmp/sidefolk-daily-fallback.log`. Real Claude settings SHA-256 still matches `original.sha256` in the test directory.

## Exact handoff / next step

1. Visible CPU measurement is complete and recorded in PHASE0 and PHASE1. No further sample
   is needed unless code changes affect rendering/resource use.
2. **An isolated dev app is now running** (tool session 17311; port 47821; Vite 1420).
   Log: `/tmp/sidefolk-daily-handcheck.log`. Startup confirms `vis=visible`, `unoccluded=true`,
   non-key panel and 27 renders/s in the first startup interval, then 30 renders/s.
   The user accepted the shortcut/tray, Connect/Cancel/Disconnect on the copy, and idle/typing
   wake hand checks. The app remains isolated; no global Claude installation was performed by
   the agent. To restart the same isolated run:
   `PATH="$HOME/.cargo/bin:$PATH" SIDEFOLK_DATA_DIR="$(cat /tmp/sidefolk-daily-path)" SIDEFOLK_CLAUDE_SETTINGS="$(cat /tmp/sidefolk-daily-path)/claude-settings.json" npm run dev`.
   Extended display/Space checks can be done during daily use. Inspect `[ui]` logs; no screenshots.
   Never click-install into the real file yourself.
3. Next: the user lives with the pet for a few days (Phase 1 exit). Record any issues they report.
   The first engineering step is the CPU cut in docs/ROADMAP.md ("Phase 1 exit"): profile the
   awake pet, change one thing at a time, re-run `npm run measure` with the screen unlocked, and
   record each result in docs/PHASE1.md. Then write the Phase 2 checklist here before coding it.
   Keep changes uncommitted until explicitly asked to commit.

Copy test rerun: `cd src-tauri && SIDEFOLK_CLAUDE_SETTINGS="$(cat /tmp/sidefolk-daily-path)/claude-settings.json" ~/.cargo/bin/cargo test copied_user_settings_round_trip -- --ignored`.
