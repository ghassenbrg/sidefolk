# Sidefolk

A 3D familiar that lives on your desktop and gives your AI agents a body. It is alive on its
own (no tokens), acts out what Claude Code and Codex are doing, comes to get you when they
need an answer, and can hand work to the agent you already have installed.

This branch is the rework. Phase 0 spikes de-risked the stack ([docs/PHASE0.md](docs/PHASE0.md));
Phase 1 is in progress ([docs/PHASE1.md](docs/PHASE1.md)). The hero character's concept sheets and
spec are in [art/](art/HERO.md). The previous Electron app is preserved at the `legacy-v0` tag.

Where it is going: a crew of pets, one per project or agent, led by a main pet, with a journal,
reminders and a way for agents to reach you. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Run it

Requires Rust (stable), Node 22+, and macOS 14+.

```sh
npm install
npm run dev        # desktop overlay (Tauri dev build)
npm run web        # browser preview at http://127.0.0.1:1420 (add ?zoom=3 to inspect)
npm run build      # optimized src-tauri/target/release/bundle/macos/Sidefolk.app
npm run measure    # CPU/RAM of the built app and its WebKit helpers
npm run model      # rebuild public/models/hero.glb in Blender (headless)
```

The pet has no Dock icon. **⌘⇧Space** hides it; press again to bring it to the cursor's display,
under the cursor, with a wave. The tray also offers **Hide/Show pet**, **Call pet here**,
**Connect/Disconnect Claude Code…**, **Move to this display**, and **Quit**. If the shortcut
cannot register, the tray shows the error and its controls still work.

Position, display and visibility survive restarts. A disconnected display falls back to the
cursor's display. The pet sleeps after **2 minutes without keyboard or mouse input** and wakes
with a wave when you type or move the mouse in any app.

In the browser preview, number keys play fake agent events: `1` think, `2` read, `3` edit,
`4` run, `5` permission question, `6` done, `7` failed, `8` prompt, `0` end.

## Try it

- **Pet it:** click to poke, drag to pick up, fling to throw. It wanders, waves when your
  cursor comes near and follows the cursor with its eyes.
- **Watch Claude Code:** choose **Connect Claude Code…** in the tray and confirm. Sidefolk
  adds its HTTP hooks to `~/.claude/settings.json`, keeping existing hooks and preferences.
  It saves an exact backup under its data directory's `backups/` before each change.
  **Disconnect Claude Code…** removes only handlers pointing to Sidefolk's localhost endpoint.
  Both changes apply to new Claude Code sessions. Invalid JSON is refused without writing.

  For a session-only connection, use:

  ```sh
  claude --settings hooks/claude-settings.json
  ```

  The pet thinks, reads, works, and celebrates along with the session. When a terminal, IDE
  or the Claude desktop app is frontmost, its own permission prompt appears immediately.
  Otherwise the pet offers **Allow / Deny / In terminal** for up to 60 seconds before deferring.
  Notification hooks still show the pet waiting even when the agent handles the decision.
- **Hand work to Codex:** double-click the pet, type a request, press Enter. Codex runs in
  `~/Library/Application Support/dev.sidefolk.companion/playground` (override with
  `SIDEFOLK_WORKDIR`) and asks the pet before running commands.

## Preferences and development checks

Preferences live in `~/Library/Application Support/dev.sidefolk.companion/settings.json`.
Quit the app before editing them; missing fields use these defaults:

| Field | Default | Purpose |
|---|---|---|
| `pet_x` | `null` | Last grounded position in overlay pixels; saves every ~5 s after moving >8 px. |
| `display` | `null` | Saved monitor name. |
| `hidden` | `false` | Start with the pet hidden or visible. |
| `shortcut` | `CommandOrControl+Shift+Space` | Global hide/summon shortcut. |
| `sleep_after_secs` | `120` | OS idle time before sleep. |
| `pet_answers_permissions` | `true` | Set false to always let Claude handle its own permission prompts. |

`SIDEFOLK_DATA_DIR` overrides the data directory, including the Codex playground and backups.
`SIDEFOLK_WORKDIR` still overrides the playground itself. `SIDEFOLK_CLAUDE_SETTINGS` points the
installer at a test copy; agents must never install into your real global settings themselves.
The app only writes Claude settings after a tray click and confirmation.

```sh
npm run typecheck
(cd src-tauri && cargo build && cargo test)
# Optional installer integration test: create a COPY first.
TEST_DIR=$(mktemp -d)
cp ~/.claude/settings.json "$TEST_DIR/claude-settings.json"
(cd src-tauri && SIDEFOLK_CLAUDE_SETTINGS="$TEST_DIR/claude-settings.json" cargo test copied_user_settings_round_trip -- --ignored)
```

For visible CPU measurements, stop any dev instance, build, unlock the screen and keep it
unlocked, then run `npm run measure`. It warms up for 15 s and samples for 60 s, with isolated
data and Claude settings. Sleep is disabled for the sample so it measures the awake pet;
locked-screen samples are refused/discarded. The current measurement status is in
[docs/PHASE0.md](docs/PHASE0.md).

## Layout

```
src/                 overlay page (TypeScript + three.js)
  pet/model.ts       loads public/models/hero.glb: toon shading, outline, bones, clips
  pet/clips.ts       clip names the model must provide
  pet/pet.ts         mixer, crossfades, gaze, blinking, squash, props
  pet/orb.ts         floating status light
  mind.ts            behavior: routine, reactions, agent directives, drag/throw physics
  agents.ts          folds agent sessions into one thing to act out
  bubble.ts          speech bubble: lines, permission questions, prompt
  input.ts           click-through hit testing against the skinned mesh
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, refit, cursor stream
  panel.rs           macOS non-activating panel on every Space, typing focus
  hooks.rs           127.0.0.1:47821 endpoint for Claude Code HTTP hooks
  codex.rs           codex app-server JSON-RPC driver
  bus.rs             shared event shapes and pending permissions
  settings.rs        atomic preferences store and shared data directory
  tray.rs            menu controls and global summon shortcut
  claude_setup.rs    confirmed hook installer, backup and uninstall
art/                 hero concept sheets, spec, and the Blender build script
public/models/       hero.glb (generated by `npm run model`)
hooks/               Claude Code hook settings
scripts/measure.sh   resource measurement
```
