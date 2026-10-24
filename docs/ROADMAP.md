# Roadmap

> **Superseded by [PLAN-V2.md](PLAN-V2.md)** once the user approves it (24 October 2026). This
> file records how v0.1 was planned and built.

Agreed with the user on 23 October 2026: where Sidefolk is going and in what order. The
decisions behind it are entries 12–17 in [memory/DECISIONS.md](../memory/DECISIONS.md); progress
is tracked in [memory/STATUS.md](../memory/STATUS.md).

## Status (24 October 2026)

Phases 1–5 are built and checked through tests, the browser preview and the desktop app's
logs; a few things need a hand check by the user (STATUS.md lists them). Phase 6 is partly done:
the parts that need the user's Apple and update-signing keys are written up in
[docs/RELEASE.md](RELEASE.md). Where the build departed from this plan, the plan below says so
in *Built:* notes, and DECISIONS 18–23 give the reasons.

## The goal

> Sidefolk is a small crew of desktop pets, one per project or agent, led by your main pet. At
> a glance you see which agent needs you. You answer from the pet without switching windows. It
> tells you where you left off and reminds you of what matters, and your agents can reach you
> through it. Free to run, private, on your Mac.

Why a crew: with several agent sessions running at once, approving is not the hard part. The
hard part is knowing which session is waiting and what it was doing. Today one pet speaks for
every session. A pet per project or agent can be recognized from across the screen, without
reading terminal tabs.

## Principles

- **Mood is information.** A crew pet's pose and status light show the state of whatever it is
  bound to. The pets are a dashboard you never have to open, not decoration.
- **Out only when needed.** The main pet stays on screen. Crew pets wait in the den and walk out
  when their project or agent needs you.
- **Never identify by color alone.** Every question shows the pet's name and project as text, so
  you cannot approve the wrong session by mistake, and color-blind users can tell pets apart.
- **No quota by default.** Anything that spends model tokens is an explicit user action.
  Commands and reminders are understood locally first.
- **Local and scoped.** Everything stays on the Mac. A project's journal is only used for that
  project.
- **The pet is the body, not the brain** (decision 2). It does not replace Claude's or Codex's
  memory or UI. It shows their state, asks for them, and lets them reach you.

## The pieces

### Main pet

Today's bunny. Always on screen unless hidden. It owns the command bar (double-click), reminders
and the "where you left off" briefing, and it can call any crew pet. Events that no crew pet
claims go to it.

### Crew and bindings

A crew pet has a name, a look (see the species kit) and one or more bindings:

| Bound to | Matched by | Lifetime |
|---|---|---|
| A session | source + session id (hooks) or Codex thread | Leaves when the session ends ("adopt this session") |
| A project | git root of the event's `cwd`, or `cwd` outside a repo | Permanent |
| An agent | `source`: `claude`, `codex`, later ACP agents | Permanent |

The most specific binding wins: session, then project, then agent, then the main pet. When
events arrive from a project that has no pet, the main pet offers once: "New project
*sidefolk*: give it its own pet?"

### The den

Where idle crew pets wait. A crew pet walks out when its project or agent asks for a
permission, fails, or (briefly) finishes, then goes back. At most three pets are on screen at
once (to be tuned).

*Built:* the den is off screen. Pets walk on from the nearer screen edge and walk back off it;
the tray's Crew menu lists them.

### Mood

| State | Crew pet |
|---|---|
| Agent working | Busy clip (think, read, work), work light |
| Waiting on you | Walks out and holds up the sign, alert light |
| Run failed or tests failing | Sad |
| Finished | Celebrates, then goes home |
| Untouched for a week | Asleep in the den |

These reuse the existing 13 clips and status-light colors ([art/HERO.md](../art/HERO.md)).

### Calling and briefings

- **"Call Project X"** (command bar or tray) brings that pet out with a status card: sessions
  running and waiting, the last finished run, the last failure.
- **"Tell Project X to …"** hands the task to an agent in that project's folder, after you
  confirm.
- **"Send X home"** returns it to the den.

### Journal and reminders (the shared memory)

Kept small and concrete, in the data directory (*built:* small JSON files and one JSONL file
per day instead of SQLite, see DECISIONS 19):

- **Pets and bindings.**
- **A journal per project:** events we already receive (sessions, a summary of tool activity,
  approvals, how each run ended), kept 30 days by default. It powers the "where you left off"
  briefing: on Monday the project pet says what happened on Friday.
- **Reminders:** text, a time, optionally a project, and optionally an action (open a link, or a
  task to hand to an agent, always confirmed before it runs).
- **About you:** name, working hours, preferences.

It is not an agent memory: Claude and Codex keep their own (CLAUDE.md, AGENTS.md, their memory
features). The pet records what happened, not what agents should know.

### Pet tools for agents (MCP)

An MCP server lets agents act through the pet instead of only being watched:

- `notify(text)`: say something through the session's pet.
- `ask(question, choices)`: show a question on the pet and return the answer, or time out.
- `remind(when, text)`: create a reminder for the user.
- `presence()`: whether the user is active, idle or away, and nothing more.

The calling session's project decides which pet speaks (a stdio shim inherits the session's
working folder). It is installed from the tray for Claude Code and Codex, with the same
confirm-and-backup rules as the hook installer.

### Species kit

Every species shares the skeleton and clip contract (15 bones, 13 clips; art/HERO.md), so every
animation works on every pet.

- A species is a parameter set for `art/blender/build_hero.py`, exported as its own glb.
- Colors are set per body region: vertex colors become region ids, and a palette is applied at
  runtime.
- Accessories (scarf, hat, glasses, headphones) are small meshes attached to bones, like the sign.
- **Describe your pet:** text ("sleepy black cat with a red bandana") or a photo goes to a vision
  model once; it picks kit settings and the user confirms.
- **Import:** a glb that passes the loader's contract check, for creators.

### Understanding requests without spending quota

1. A local grammar and date parser for common phrases ("call X", "remind me Friday at 3 to …").
2. Apple's on-device model (Foundation Models framework, macOS 26+) for the rest: free and
   private, but it needs a Swift bridge, so spike it first.
3. An agent only when the user explicitly asks for one.

## Not doing, for now

- **Turning an image into a 3D pet.** Image-to-3D output does not fit our skeleton, varies
  between runs, costs money and breaks the animations. The kit plus "describe your pet" gives the
  same feeling reliably. Revisit if image-to-3D can produce our rig.
- **General-assistant pets first** (weather checks and the like). Siri and ChatGPT already do
  this, and every run would spend quota. The mechanism returns later as routines, developer
  routines first; weather-style ones can be plugins.
- **An agent memory of our own.** It would duplicate CLAUDE.md and Codex's memory.

## Risks

- **CPU.** One visible pet costs 16.9% (WebKit WebContent 8.1%, the Sidefolk process 5.2%,
  WebKit GPU 3.6%; docs/PHASE0.md). Several pets would drain the battery, so Phase 1 ends by
  cutting this. Budget: under 5% for everything on screen.
- **Clutter.** The den and the three-pet cap.
- **Approving the wrong session.** Name and project as text on every question.
- **Sessions don't last.** Bind to projects and agents; sessions are one-offs.
- **Screen sharing.** Crew pets show project names, so they auto-hide while you share.
- **Local spoofing.** Once agents can ask questions and create reminders, the endpoint needs the
  per-install token planned in PHASE0.

## Build order

Each phase ends with something usable. Its detailed checklist goes into STATUS.md when it starts.

### Phase 1 exit: one pet, cheap · done

*Built:* 16.8% → 8.7% awake, 1.0% hidden; the 5% target was not reached (docs/PHASE1.md says
why).

- Live with the pet for a few days and fix what comes up.
- Cut visible CPU. Measure before changing anything: idle already renders at 30 fps (the WebKit
  cap) and sleep at 12 (`Mind.fps`), and the cursor stream already sends only on movement, so
  find what the 5.2% in the Sidefolk process is. Candidates: idle at 15 fps, skipping frames when
  nothing changed, a smaller canvas.
- Exit: no blocking issues from daily use, and one awake pet at 5% or less (or the best reached,
  recorded with the reason).
- Leftovers, done when convenient: following the cursor across displays, window awareness, the
  full-screen floor offset with a visible Dock, the "arms up" reach.

### Phase 2: Crew · done

*Built:* everything below except the hook endpoint token (DECISIONS 21); one small canvas per
pet instead of a shared renderer (DECISIONS 18); hiding from screen recordings uses macOS
content protection instead of detecting screen sharing.

- One renderer for several pets (one WebGL context), within the CPU budget.
- Pets, bindings and resolution (session, project, agent, main pet); the "new project" offer.
- Bunny variants: palette regions and two or three accessories (the first use of the species
  kit; new species wait for Phase 5).
- The den, the three-pet cap, the mood table.
- Questions come from the right pet, with name and project as text.
- Command bar: call, send home, tell X to …; the status card (this replaces the planned
  sessions panel).
- "Tell X to …" runs Codex in that project's folder (this replaces the playground folder picker).
- Codex approval timeout and an "open in Codex" handoff (PHASE0).
- Per-install token on the hook endpoint (PHASE0).
- Auto-hide during screen sharing.
- Exit: with three projects running at once, you can tell at a glance which one needs you and
  answer from the right pet.

### Phase 3: Journal and reminders · done

*Built:* a hidden pet comes back on screen for a due reminder instead of a native
notification (DECISIONS 20). The on-device model spike compiled but the model reported
`modelNotReady` on this Mac, so chrono-node is the only parser for now.

- SQLite store; pets and bindings move into it, while settings.json keeps preferences.
- Journal from hook and Codex events, with retention.
- "Where you left off" briefing: when you return after a long idle, or when you call a pet.
- Reminders: created from the command bar, fired on time, caught up after sleep or quit, shown
  as a native notification when the pet is hidden; launch at login (opt-in).
- Local date parsing; the on-device model spike.
- Exit: a reminder set on Monday fires on Friday even after restarts, and Monday's briefing is
  right.

### Phase 4: Agents can reach you · done

*Built:* the token protects `/mcp/call`; the installer runs the agents' own `mcp add/remove`.

- The MCP server (notify, ask, remind, presence) and the stdio shim for project identity.
- Tray installer for Claude Code and Codex, with confirmation and backup.
- Exit: a Claude session asks you a question through its project's pet and gets the answer.

### Phase 5: Make your own · done

*Built:* the whole creative-design roster, 18 characters on one rig (each under 8k triangles),
in three art styles (Soft 3D, Ink & Geek, Pocket Anime); eighteen palettes; four accessories; local
"describe your pet"; photos through one Haiku call; glb import with docs/CREATORS.md.

- Two or three more species from the kit.
- A customizer: species, colors, accessories, name.
- "Describe your pet" from text or a photo.
- glb import with the contract check and a short creator guide.
- Exit: someone makes a pet of their own cat in under a minute.

### Phase 6: Production · partly done

*Built:* the Sidefolk window on the creative-design system (Home, Requests, Crew, Reminders,
Settings; docs/DESIGN-COMPLIANCE.md), a three-step first minute with comfort presets, Pip
Signal app and menu bar icons, desktop presence and card detail settings, "Open session" for
live and ended work sessions, pet menus and command previews, voices (sound cues, optional
speech), local crash and error logs, no Dock icon at launch.
*Waiting on the user's keys:* signing, notarizing and auto-update (docs/RELEASE.md). Windows
not started.

- Signed and notarized app, auto-update.
- Onboarding (connect agents, make a first pet) and a settings window.
- Opt-in crash reports.
- Then Windows.

### Later

- Routines: a pet with a schedule, starting with developer ones (each morning: CI status and the
  PRs waiting on you).
- Other agents through ACP (decision 5).
- Voice.
- A shop for pets and accessories if revenue is wanted: looks only, never features.
