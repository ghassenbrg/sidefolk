# Sidefolk

A desktop companion for macOS. Pip lives on your desktop, brings you your reminders, and acts
out what your AI tools (Claude Code, Codex) are doing: it brings you their requests and takes you
back to their work sessions.

**Where it's going:** [docs/PLAN-V2.md](docs/PLAN-V2.md), the plan agreed on 24 October 2026
(reminders, notes, AI sessions with worker companions, quick actions, in a real Mac app). This
README describes the app after phase 0 (the reset). Everything v0.1 had (a crew of 18
characters, art styles, comfort presets…) is in git at the `v0.1-zoo` tag. The older Electron
app is at `legacy-v0`.

## Run it

Requires Rust (stable), Node 22+, and macOS 14+.

```sh
npm install
npm run dev           # the desktop app, Tauri dev build (logs go to the terminal)
npm run web           # browser preview: companion at http://127.0.0.1:1420 (?zoom=3),
                      # the Sidefolk window at /settings.html, both with sample data
npm test              # unit tests
npm run check:webkit  # with npm run web running: every view in WebKit, fails on errors
                      # (once: npx playwright install webkit)
npm run build         # optimized src-tauri/target/release/bundle/macos/Sidefolk.app
npm run measure       # CPU/RAM of the built app and its WebKit helpers
npm run model         # rebuild public/models/hero.glb in Blender (headless)
```

Releasing (signing, notarizing, auto-update): [docs/RELEASE.md](docs/RELEASE.md).

## Use it

**Pip stays where you put it.** Drag it anywhere; it never wanders. ⌘⇧Space hides it or
calls it to your cursor. It falls asleep after a while without keyboard or mouse input.

**Click Pip (or right-click) to talk to it.** One field; the line under it says what Enter
will do before anything happens. Everything is understood on your Mac, without AI:

| Type | What happens |
|---|---|
| `remind me tomorrow at 9 to check the results` | A reminder; Pip brings it at that time, even when hidden |
| `reminders` | What's coming up |
| `open session` · `open api session` | Bring a work session forward, or continue it in a terminal |
| `open Sidefolk` · `hide` | The Sidefolk window, or hide the companion |
| `rename to Bun` | A new name for your companion |

Anything else gets a short answer; it's never sent to an AI tool.

**Every card closes** with its ×. A request you close stays in the Sidefolk window under
Requests until it's answered or the tool stops waiting.

**The Sidefolk window** (menu bar icon → Open Sidefolk…): Home (what needs you, your work
sessions, reminders coming up), Requests (each one with its exact command, Decline / Allow
once; "Sent" shows only once it went through), Reminders (add, edit, complete, delete with
Undo) and Settings.

**With Claude Code or Codex** (Settings → Connected tools): Pip shows what each work session is
doing, brings you its requests when no terminal or editor is in front (Decline / Allow once, or
answer in the tool's own window), and tells you when it finishes or fails. Companion tools let
sessions send you a note, ask a question, set a reminder or check whether you're around (MCP:
`notify`, `ask`, `remind`, `presence`).

## Settings and data

Settings: companion size, reduce motion, larger text, sleep time, sound and voice, hide from
screen recordings (on by default), connected tools, where sessions open, the shortcut (press it
to record) and start at login. Everything lives in
`~/Library/Application Support/dev.sidefolk.companion` and never leaves the Mac:

| File | What |
|---|---|
| `settings.json` | Preferences, position and display |
| `crew.json` | The companion's name |
| `reminders.json` | Reminders |
| `journal/*.jsonl` | Sessions, prompts, outcomes, requests; one file per UTC day, 30 days |
| `token` | Secret the MCP shim sends to the app |
| `backups/` | Exact copies of agent configs before each change |
| `logs/` | Crash and page errors, for bug reports |

`SIDEFOLK_DATA_DIR` overrides the folder and `SIDEFOLK_CLAUDE_SETTINGS` points the hook
installer at a test copy. Agents must never install into your real global settings themselves.

```sh
npm run typecheck && npm test
(cd src-tauri && cargo build && cargo test)
# Opt-in tests: the hook installer on a COPY of your settings, agent CLIs on temp configs.
TEST_DIR=$(mktemp -d); cp ~/.claude/settings.json "$TEST_DIR/claude-settings.json"
(cd src-tauri && SIDEFOLK_CLAUDE_SETTINGS="$TEST_DIR/claude-settings.json" cargo test copied_user_settings_round_trip -- --ignored)
(cd src-tauri && cargo test agents_cli_round_trip -- --ignored --test-threads=1)
```

## Layout

```
src/                 the companion's page (TypeScript + three.js)
  main.ts            boot, events from Rust, frame loop, welcome-back
  companion.ts       the companion: requests, commands, opening sessions, status for the window
  familiar.ts        its model, mind, light, canvas, card and status badge
  agents.ts          folds agent sessions into one thing to act out
  commands.ts        what the field understands (pure, local)
  reminders.ts       reminder scheduler and cards; when.ts parses times (chrono-node)
  agent-tools.ts     AI tools' MCP calls shown on the companion
  away.ts            the welcome-back briefing (pure)
  mind.ts            behavior: idle routine, reactions, directives, dragging, frame rate
  bubble.ts          the card: lines, requests (who, context, facts, choices), the field
  input.ts           click-through hit testing against the companion's mesh
  pet/               model loader, animation, status light
  tokens.css         design tokens; states.ts status words and glyphs; icons.ts icons and mark
  dashboard/         the Sidefolk window: app.ts, home, requests, reminders, settings
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, refit, cursor and idle stream
  panel.rs           macOS non-activating panel on every Space, typing focus
  hooks.rs           127.0.0.1:47821: Claude Code hooks, /mcp/call, dev endpoints
  codex.rs           codex app-server driver (used again in phase 6)
  sessions.rs        "Open session": finds where a session runs, focuses or resumes it
  mcp.rs             `sidefolk --mcp` stdio shim and the tool endpoint
  mcp_setup.rs       companion tools installer (claude/codex mcp add, with backups)
  claude_setup.rs    confirmed hook installer, backup and uninstall
  journal.rs · reminders.rs · crew.rs · settings.rs · prefs.rs · tray.rs · voice.rs
art/                 concept sheets, spec, Blender build script, brand SVGs
creative-design/     the design package; v2/ holds the Pip and Spark concept sheets
public/models/       hero.glb (`npm run model`)
scripts/             make_icons.py, measure.sh, webkit-check.mjs
```
