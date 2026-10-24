# Sidefolk

A crew of 3D desktop pets that gives your AI agents a body. The main pet lives on your
desktop for free (no tokens) and acts out what Claude Code and Codex are doing. Each project
can get its own pet that comes out of its den when that project needs you. Pets bring you the
agents' questions, tell you what happened while you were away, remind you of things, and
agents can reach you through them.

Status and plan: [docs/ROADMAP.md](docs/ROADMAP.md) (phases 1–5 built, 6 partly). Logs:
[docs/PHASE0.md](docs/PHASE0.md), [docs/PHASE1.md](docs/PHASE1.md). The characters are built by
[art/blender/build_hero.py](art/blender/build_hero.py) ([art/HERO.md](art/HERO.md)). The
previous Electron app is preserved at the `legacy-v0` tag.

## Run it

Requires Rust (stable), Node 22+, and macOS 14+.

```sh
npm install
npm run dev        # desktop overlay (Tauri dev build)
npm run web        # browser preview: overlay at http://127.0.0.1:1420 (?zoom=3), window at /settings.html (?welcome)
npm test           # unit tests (commands, routing, reminders, briefings, the window's logic)
npm run check:webkit  # every view in WebKit, the app's engine (needs npm run web; once: npx playwright install webkit)
npm run build      # optimized src-tauri/target/release/bundle/macos/Sidefolk.app
npm run measure    # CPU/RAM of the built app and its WebKit helpers
npm run model      # rebuild public/models/*.glb in Blender (headless)
```

Releasing (signing, notarizing, auto-update): [docs/RELEASE.md](docs/RELEASE.md).

## Use it

The first run opens the Sidefolk window on a three-step welcome: what Sidefolk does, a comfort
style (Friendly with Pip, Professional with Slate, Minimal with Dot; every suggested change is
shown before it applies) and connecting Claude Code or Codex when you're ready. **Try a demo**
plays a labelled sample session on the desktop; nothing is connected or run.

**Click a companion** for its status and **Open session**. **Right-click** for everything it can
do; **double-click** to type (the line under the field says what Enter will do). The menu bar
mark shows how many requests wait, and has **Open Sidefolk…**, the waiting requests,
**Hide/Show companions**, **Call companions here**, **Crew ▸**, **New reminder…**,
**Connect Claude Code…**, **Move to this display** and **Quit**.

**The Sidefolk window** has five destinations: **Home** (what needs your attention first,
each companion's status, reminders coming up, recent activity), **Requests** (grouped by
project; a review shows the exact command and folder, with Decline / Allow once, and says
"Sent" only once the companion passed the answer on), **Crew** (companions, including resting
ones; each has a page for appearance with idle and "needs you" previews, name, project and
removal), **Reminders** (title, date and time, edit, complete, delete with Undo) and
**Settings**. The design follows `creative-design/`; [docs/DESIGN-COMPLIANCE.md](docs/DESIGN-COMPLIANCE.md)
maps every rule to the code.

**Open session** brings a live Claude Code session forward where it runs (Terminal and iTerm
switch to its tab; Ghostty, VS Code and the Claude app come to the front). An ended session, or
a Codex thread Sidefolk started in the background, continues in a new terminal window with
`claude --resume` / `codex resume` (Settings → Connected tools → Open sessions in). It's on the
status card, the right-click menu, Home, Crew, Requests and Activity, and `open session` /
`continue Byte` in the command bar.

Companions have voices: short sound cues when they talk or need you, made on the fly (no
sound files). Settings → Sound turns them off, sets the volume, or reads lines out loud with a
macOS voice.

- **⌘⇧Space** hides the companions, or brings them to your cursor. They sleep after 2 minutes
  without keyboard or mouse input and wake when you come back.
- **Desktop presence:** always visible, only when needed (companions rest until something needs
  you), or menu bar only (no companions; requests and reminders arrive as notifications).
- **Card detail:** full preview, project and status, or status only, for screens other people
  can see. The Sidefolk window always shows everything.
- **Connect Claude Code** (Settings → Connected tools): Sidefolk adds its HTTP hooks to
  `~/.claude/settings.json` after a confirmation, keeping your other hooks, with an exact backup
  first. For one session only: `claude --settings hooks/claude-settings.json`.
- **Requests:** when no terminal, editor or the Claude app is in front, the companion offers
  **Decline / Allow once** for up to 60 seconds; **Answer in Claude Code's window** leaves it to
  Claude Code and takes you there.

### The crew

When an AI tool works in a git project with no companion yet, the main companion offers one.
The first ones come from your comfort style's crew: Friendly brings Byte (charcoal cat, mint
glasses), Patch (terracotta fox) and Loom (lavender sheep); Professional brings Finch, Calder and
Orbit; Minimal brings Slate, Finch and Orbit. The full roster has 18 characters (also Moss,
Relay, Stack, Nib, Pico, Sora, Yuna, Kite, Dot, Vale), each in three art styles: Soft 3D, Ink &
Geek (flat fills, heavy line) and Pocket Anime (crisp cel shading). Resting companions stay out of the way and fade in
when their project asks something, fails or finishes. At most three are out at once; a fourth
project's request goes to the main companion, named in text. Every request names the companion,
project, tool and work session.

### The command bar

Double-click a companion and type. These run locally and cost no tokens:

| Type | What happens |
|---|---|
| `open session` · `continue Byte` | Bring a work session forward, or continue it in a terminal |
| `crew` · `call Byte` · `call api` | List the crew, or bring a companion out with its status |
| `send Byte home` · `go home` | Back to rest |
| `customize Byte` | Opens Byte's appearance in the Sidefolk window |
| `Byte wear glasses` · `Byte color midnight` · `Byte become a fox` · `Byte become anime` · `rename Byte to Bit` | Quick changes |
| `remind me Friday at 3 to review the PR` · `reminders` | Reminders, delivered by the project's companion |
| `adopt` | Give the latest work session its own temporary companion |
| `forget Byte` | Remove a companion (asks first) |
| `open Sidefolk` | The Sidefolk window |

Anything else is a task: `tell Byte to run the tests`, `Byte: fix the lint`, or plain text in
a companion's bar runs Codex in its project; in the main companion's bar it runs in a scratch
playground (`codex: …` always does).

Coming back after 30 minutes away, the main companion tells you what the AI tools did
meanwhile and your next reminder. Reminders survive restarts; missed ones show when Sidefolk
starts with their original time.

### Companion tools for AI tools (MCP)

**Settings → Connected tools → Companion tools for Claude Code / Codex** registers `sidefolk --mcp` with
`claude mcp add` / `codex mcp add` (after a confirmation, with a backup of the config file).
Work sessions then have four tools, spoken by the companion of their project:

- `notify(text)`: a speech bubble.
- `ask(question, choices?)`: answer buttons (or Yes / No / Reply…); returns your answer or
  "nobody answered".
- `remind(text, when)`: a reminder for you.
- `presence()`: active, idle or away.

### Custom looks

A companion's page → Appearance → **Other ways to choose a look**: describe it in words (local:
"a sleepy black cat with glasses"), **Choose a photo…** (one small Claude Haiku call, only when
you pick a photo) or **Import a model…** (a `.glb` following [docs/CREATORS.md](docs/CREATORS.md)).

## Settings and data

**Settings** covers comfort style, desktop presence, companion size, reduce motion, larger
text, sleep time, sound and voice, hiding from screen recordings (on by default, since cards
show project names), card detail, connected tools, where sessions open, the shortcut (press it
to record) and start at login. Everything lives in `~/Library/Application Support/dev.sidefolk.companion`
and never leaves the Mac:

| File | What |
|---|---|
| `settings.json` | Preferences (fields above, plus position and display) |
| `crew.json` | Pets, what each looks after, their looks |
| `reminders.json` | Reminders |
| `journal/*.jsonl` | Sessions, prompts, outcomes, questions; one file per UTC day, 30 days |
| `models/` | Imported pet models |
| `token` | Secret the MCP shim sends to the app |
| `backups/` | Exact copies of agent configs before each change |
| `logs/` | Crash and page errors, for bug reports |

`SIDEFOLK_DATA_DIR` overrides the folder, `SIDEFOLK_WORKDIR` the Codex playground, and
`SIDEFOLK_CLAUDE_SETTINGS` points the hook installer at a test copy. Agents must never install
into your real global settings themselves.

```sh
npm run typecheck && npm test
(cd src-tauri && cargo build && cargo test)
# Opt-in tests: hook installer on a COPY of your settings, agent CLIs on temp configs,
# and one live Claude Haiku call that describes a photo.
TEST_DIR=$(mktemp -d); cp ~/.claude/settings.json "$TEST_DIR/claude-settings.json"
(cd src-tauri && SIDEFOLK_CLAUDE_SETTINGS="$TEST_DIR/claude-settings.json" cargo test copied_user_settings_round_trip -- --ignored)
(cd src-tauri && cargo test agents_cli_round_trip -- --ignored --test-threads=1)
(cd src-tauri && cargo test describes_a_photo -- --ignored)
```

For CPU measurements, stop any dev instance, build, keep the screen awake and unlocked, then
run `npm run measure`; results are in [docs/PHASE1.md](docs/PHASE1.md).

## Layout

```
src/                 overlay page (TypeScript + three.js)
  tokens.css         the design system's tokens and shared badge, shared by both pages
  states.ts          one status vocabulary (glyph + word) and the card-detail level
  icons.ts           line icons and the Pip Signal mark
  main.ts            boot, events from Rust, frame loop, welcome-back, notifications
  crew.ts            the main pet and its crew: routing, permission and status cards, commands
  familiar.ts        one pet: model, mind, light, canvas, bubble, HUD, sessions
  routing.ts         which pet speaks for an event (pure)
  commands.ts        the command bar's phrases (pure)
  agents.ts          folds a pet's agent sessions into one thing to act out
  reminders.ts       reminder scheduler and cards; when.ts parses times (chrono-node)
  away.ts            the welcome-back briefing (pure)
  agent-tools.ts     agents' MCP tool calls shown on pets
  describe.ts        "describe your pet" words to a look (pure)
  mind.ts            behavior: routine, fade in/out, reactions, directives, physics, frame rate
  bubble.ts          speech bubble: lines, cards (who, context, facts, choices), prompt
  demo.ts            labelled sample session (welcome's "Try a demo") and preview keys
  input.ts           click-through hit testing against every pet's mesh
  pet/look.ts        species, palettes, accessories
  pet/model.ts       loads a species (or imported glb): toon shading, outline, recolor
  pet/pet.ts         mixer, crossfades, gaze, blinking, squash, props
  pet/orb.ts         floating status light
  dashboard/         the Sidefolk window: app.ts (navigation, live state), home, requests,
                     crew (+ portrait.ts 3D portraits and previews), reminders, settings,
                     welcome, comfort presets, activity; api.ts has the browser sample data
  sound.ts           babble and chirps (Web Audio); keys.ts shortcut labels and recording
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, refit, cursor and idle stream
  panel.rs           macOS non-activating panel on every Space, typing focus
  hooks.rs           127.0.0.1:47821: Claude Code hooks, /mcp/call, dev endpoints
  codex.rs           codex app-server driver, one thread per project folder
  mcp.rs             `sidefolk --mcp` stdio shim and the tool endpoint
  mcp_setup.rs       companion tools installer (claude/codex mcp add, with backups)
  sessions.rs        "Open session": finds where a session runs, focuses or resumes it
  claude_setup.rs    confirmed hook installer, backup and uninstall
  crew.rs            crew.json and the tray's crew list
  journal.rs         per-day activity journal
  reminders.rs       reminders.json
  models.rs          imported models, photo description
  prefs.rs           the Sidefolk window's commands, live status, logs
  voice.rs           "speak out loud" with macOS voices
  settings.rs        atomic preferences store and shared data directory
  tray.rs            menu, global shortcut
  bus.rs             shared event shapes, project roots, pending questions
art/                 concept sheets, spec, Blender build script (all 18 bodies), brand SVGs
creative-design/     the design package the app follows: system, UX spec, characters, prototype
public/models/       one glb per body, 18 in all (`npm run model`)
hooks/               Claude Code hook settings
scripts/measure.sh   resource measurement
scripts/make_icons.py  Pip Signal mark, app icon and menu bar icon from one geometry
scripts/webkit-check.mjs  loads every view in WebKit and fails on errors
```
