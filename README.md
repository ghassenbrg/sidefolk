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
npm run web        # browser preview at http://127.0.0.1:1420 (add ?zoom=3 to inspect)
npm test           # unit tests (commands, routing, reminders, briefings, descriptions)
npm run build      # optimized src-tauri/target/release/bundle/macos/Sidefolk.app
npm run measure    # CPU/RAM of the built app and its WebKit helpers
npm run model      # rebuild public/models/*.glb in Blender (headless)
```

Releasing (signing, notarizing, auto-update): [docs/RELEASE.md](docs/RELEASE.md).

## Use it

The first run shows a welcome card. **Right-click any pet** for everything it can do;
**double-click** to type (the field shows what Enter will do before anything happens). The
menu bar bunny has **Hide/Show pet**, **Call pet here**, **Crew ▸**, **New reminder…**,
**Connect Claude Code…**, **Open Sidefolk…**, **Move to this display**, **Quit**.

**Open Sidefolk…** is the dashboard: **Home** (what is waiting on you, answerable right
there; every pet and what its sessions are doing; next reminders; connections),
**Activity** (the journal as a timeline), **Crew**, **Reminders**, **Agents**, **Settings**
and **About & help**.

Pets have voices: a soft babble when they talk and little chirps when they react, made on the
fly (no sound files). Settings → Sound and voice turns them off, sets the volume, or has pets
**speak out loud** with any macOS voice.

- **⌘⇧Space** hides the pets, or brings them to your cursor. They sleep after 2 minutes
  without keyboard or mouse input and wake when you come back.
- **Pet them:** click to poke, drag to pick up, fling to throw.
- **Connect Claude Code** (tray or Settings): Sidefolk adds its HTTP hooks to
  `~/.claude/settings.json` after a confirmation, keeping your other hooks, with an exact backup
  first. For one session only: `claude --settings hooks/claude-settings.json`.
- **Questions:** when no terminal, editor or the Claude app is in front, the pet offers
  **Allow / Deny / In terminal** for up to 60 seconds; otherwise the agent asks as usual.

### The crew

When an agent works in a git project with no pet yet, the main pet offers one. Crew pets wait
off screen (the den) and walk on when their project asks a question, fails, or finishes, then
walk back. At most three are out at once; a fourth project's question goes to the main pet,
labeled with the crew pet's name. Every question names the pet and project in text.

### The command bar

Double-click a pet and type. These run locally and cost no tokens:

| Type | What happens |
|---|---|
| `crew` · `call Pip` · `call api` | List the crew, or bring a pet out with a briefing |
| `send Pip home` · `go home` | Back to the den |
| `customize Pip` | Body (bunny, cat, fox, imported), coat, extra; live |
| `Pip wear glasses` · `Pip color midnight` · `Pip become a fox` · `rename Pip to Bun` | Quick changes |
| `remind me Friday at 3 to review the PR` · `reminders` | Reminders, delivered by the project's pet |
| `adopt` | Give the latest session its own temporary pet |
| `forget Pip` | Remove a crew pet (asks first) |

Anything else is a task: `tell Pip to run the tests`, `Pip: fix the lint`, or plain text in a
crew pet's bar runs Codex in that pet's project; in the main pet's bar it runs in a scratch
playground (`codex: …` always does).

Coming back after 30 minutes away, the main pet tells you what the agents did meanwhile and
your next reminder. Reminders survive restarts; missed ones show when Sidefolk starts, and
the pet appears for them even when hidden.

### Pet tools for agents (MCP)

**Settings → Pet tools for Claude Code / Codex** registers `sidefolk --mcp` with
`claude mcp add` / `codex mcp add` (after a confirmation, with a backup of the config file).
Sessions then have four tools, spoken by the pet of their project:

- `notify(text)`: a speech bubble.
- `ask(question, choices?)`: answer buttons (or Yes / No / Reply…); returns your answer or
  "nobody answered".
- `remind(text, when)`: a reminder for you.
- `presence()`: active, idle or away.

### Custom pets

`customize` offers **Describe…** (local words: "a sleepy black cat with glasses"),
**Photo…** (one small Claude Haiku call, only when you pick a photo) and **Import…** (a `.glb`
following [docs/CREATORS.md](docs/CREATORS.md)).

## Settings and data

**Settings** covers the shortcut (press it to record), pet size, calm pets, larger text,
sleep time, sounds and voice, hiding from screen recordings (on by default, since crew pets
show project names) and start at login; **Agents** covers connections, pet tools and
permissions on the pet. Everything lives in `~/Library/Application Support/dev.sidefolk.companion`
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
  main.ts            boot, events from Rust, frame loop, onboarding, welcome-back
  crew.ts            the main pet and its crew: routing, den, offers, commands, customizer
  familiar.ts        one pet: model, mind, light, canvas, bubble, HUD, sessions
  routing.ts         which pet speaks for an event (pure)
  commands.ts        the command bar's phrases (pure)
  agents.ts          folds a pet's agent sessions into one thing to act out
  reminders.ts       reminder scheduler and cards; when.ts parses times (chrono-node)
  away.ts            the welcome-back briefing (pure)
  agent-tools.ts     agents' MCP tool calls shown on pets
  describe.ts        "describe your pet" words to a look (pure)
  mind.ts            behavior: routine, den walks, reactions, directives, physics, frame rate
  bubble.ts          speech bubble: lines, cards with buttons or chips, prompt
  input.ts           click-through hit testing against every pet's mesh
  pet/look.ts        species, palettes, accessories
  pet/model.ts       loads a species (or imported glb): toon shading, outline, recolor
  pet/pet.ts         mixer, crossfades, gaze, blinking, squash, props
  pet/orb.ts         floating status light
  settings-page.ts   the Sidefolk window (dashboard and settings)
  dashboard-home.ts  its Home; dashboard-activity.ts its Activity timeline
  sound.ts           babble and chirps (Web Audio); keys.ts shortcut labels and recording
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, refit, cursor and idle stream
  panel.rs           macOS non-activating panel on every Space, typing focus
  hooks.rs           127.0.0.1:47821: Claude Code hooks, /mcp/call, dev endpoints
  codex.rs           codex app-server driver, one thread per project folder
  mcp.rs             `sidefolk --mcp` stdio shim and the tool endpoint
  mcp_setup.rs       pet tools installer (claude/codex mcp add, with backups)
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
art/                 concept sheets, spec, Blender build script (bunny, cat, fox)
public/models/       hero.glb (bunny), cat.glb, fox.glb (generated by `npm run model`)
hooks/               Claude Code hook settings
scripts/measure.sh   resource measurement
```
