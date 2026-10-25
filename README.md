# Sidefolk

Pip sits on your desktop, taps you when Claude Code or a reminder needs you, takes you to that
exact session, and keeps a dated log of what you got done. macOS 14+, Apple Silicon.

**How to use it:** [docs/GUIDE.md](docs/GUIDE.md), the short guide for people trying it.
**The plan:** [docs/V1.md](docs/V1.md) is the v1 release contract (25 October 2026), decided after
two independent audits ([docs/audit-2026-10-25-claude/](docs/audit-2026-10-25-claude/),
[docs/audit-2026-10-25/](docs/audit-2026-10-25/)). Everything cut for v1 (ten characters, the 2D
style, Sparks, the terminal inside Sidefolk, saved actions, full access…) is in git at `76b38f1`;
v0.1 is at the `v0.1-zoo` tag and the older Electron app at `legacy-v0`.

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
npm run sprites -- pip 3d   # cut Pip's frames from its sheets (art/crew/README.md)
```

Releasing (signing, notarizing, auto-update): [docs/RELEASE.md](docs/RELEASE.md).

## Use it

**Pip stays where you put it.** Drag it anywhere; it never wanders. ⌘⇧Space hides it or
calls it to your cursor. It falls asleep after a while without keyboard or mouse input.

**Click Pip to talk to it,** or use the field at the top of the window. The line under the field
says what Enter will do before anything happens. Everything is understood on your Mac, without
AI, and nothing is ever sent to an AI tool. The full list is in [docs/GUIDE.md](docs/GUIDE.md):
reminders (with repeats and "10 minutes before"), notes ("note for evaluation: …"), opening
things, opening Claude Code sessions. Settings → Labs adds `$` commands (shown before they run)
and starting sessions; plain sentences never run as commands.

**Every card closes** with its ×. A request you close stays in the window until it's answered or
the tool stops waiting.

**The Sidefolk window** is a normal Mac app (Dock, menus, full screen): Today ⌘1, Reminders ⌘2,
Notes ⌘3, Sessions ⌘4, Settings ⌘,. First launch opens a three-step setup guide.

**With Claude Code** (Settings → Agents): Pip shows what each session is doing, brings its
permission requests (Decline / Allow once, or answer in Claude's window; Pip never answers on its
own) and tells you when it finishes or fails. MCP tools for Claude Code and Codex: `notify`,
`ask`, `remind`, `presence`, plus authoritative companion controls, reminder management and exact
notebook capture. Install the portable Sidefolk skill from Settings → Agents. Codex session
watching is opt-in Beta: native confirmation, exact backups, then manual `/hooks` trust in Codex.
It reports status and opens sessions; approvals stay in Codex. See [the guide](docs/GUIDE.md).

The founder-adopted window package lives in `creative-design/review-2026-10-25`; Pip and Spark
both remain available. `npm run release:check` runs the complete offline/browser checks;
`npm run release:ready` reports missing signing and release inputs. A local build is not a signed
release or evidence that native gates have passed.

## Settings and data

Settings: companion size, reduce motion, larger text, sleep time, sounds, hide from screen
recordings (off by default), agent connections, where sessions open, Labs, the shortcut (press it to
record) and start at login. Everything lives in
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
src/                 the companion's page (TypeScript)
  main.ts            boot, events from Rust, frame loop, welcome-back
  companion.ts       the companion: requests, commands, opening sessions, status for the window
  familiar.ts        the companion on screen: Pip's frames, mind, card and status badge
  pip.ts             Pip: frame per pose, breathing, blinks, hop, status light, hit testing
  agents.ts          folds agent sessions into one thing to act out
  commands.ts        what the field understands (pure, local)
  reminders.ts       reminder scheduler and cards; when.ts parses times (chrono-node)
  agent-tools.ts     AI tools' MCP calls shown on the companion
  away.ts            the welcome-back briefing (pure)
  mind.ts            behavior: idle routine, reactions, directives, dragging, frame rate
  bubble.ts          the card: lines, requests (who, context, facts, choices), the field
  input.ts           click-through: interactive only over Pip's opaque pixels or its card
  tokens.css         design tokens; states.ts status words and glyphs; icons.ts icons and mark
  dashboard/         the Sidefolk window: app.ts, home, requests, reminders, settings
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, refit, cursor and idle stream
  panel.rs           macOS non-activating panel on every Space, typing focus
  hooks.rs           127.0.0.1:47821: Claude Code hooks, /mcp/call, dev endpoints
  sessions.rs        "Open session": finds where a session runs, focuses or resumes it
  mcp.rs             `sidefolk --mcp` stdio shim and the tool endpoint
  mcp_setup.rs       companion tools installer (claude/codex mcp add, with backups)
  claude_setup.rs    confirmed hook installer, backup and uninstall
  actions.rs         `$` commands and "open …" (Labs), folder lookup, starting sessions
  calendar.rs        meeting heads-up, behind the `calendar` Cargo feature (off until v1.1)
  journal.rs · reminders.rs · notifications.rs · notes.rs · crew.rs · settings.rs · prefs.rs · tray.rs
art/                 pip/ (generated sprite sheets and how to remake them), brand SVGs, icon
creative-design/     the design package; PIP.md is Pip's character bible (frozen for v1)
public/crew/         the two companions' frames, Pip and Spark (3d; `npm run sprites`)
scripts/             make_icons.py, make_sprites.py, measure.sh, webkit-check.mjs
```
