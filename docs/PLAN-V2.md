# Sidefolk v2: review, product plan and roadmap

24 October 2026 · Plan phase: nothing here is built yet. All six decisions in section 11 are
made (24 October); it supersedes the build order in [ROADMAP.md](ROADMAP.md). Building starts
with phase 0 when you say go.

## 1. What you asked for

You looked at the result and found it messy: too many things to click, crew "here and there",
an app that isn't a real app, a zoo of animal pets with poor animation, and features you can't
track. You want to stop, rethink, and ship a small MVP where a few things work perfectly and
really help, for developers and for people who aren't technical.

Your priorities, in your order:

1. **Reminders.** Tell the companion "tomorrow at 9 remind me to check the RT results" or "I
   have a meeting at 3". At that time it appears, even if hidden or closed, holding the note.
   Clicking it opens the details in the app.
2. **Notes that collect over time.** Your evaluation example: every few days you tell the
   companion an achievement worth mentioning; in six months the note has everything, dated, with
   details. The same works for any "memory" topic.
3. **Quick actions.** "Open a terminal in this folder and run this command." If it's just a
   command, run it.
4. **AI sessions by project or by session.** A companion for a repository or for one Claude or
   Codex session: it starts the session for you, tells you when it needs you or finished, and
   opens it (terminal at work, Claude desktop where you have it). It can be created from
   anywhere: the app, a terminal command in the folder, or a command inside the AI session.
   Later, a team: "ask the reviewer to check this".

Also: one companion can handle everything, and a crew is optional. A real app with a Dock icon
and full screen. A setup guide with good defaults. Settings for your default terminal and how
sessions open. Companions are assistants, not only pets. Brainstorm small helpers, even ones
other tools have: the value is that one companion does them all, one sentence away.

## 2. Honest review of what's there now

What went wrong is mostly in the order of work: I built breadth (eighteen characters, three
styles, comfort presets, presence modes, card-detail levels) before depth in the few things
people use every day.

**The app isn't an app.** Sidefolk runs as a menu bar accessory (no Dock icon, no ⌘Tab, no
full screen). The "Sidefolk window" is a settings panel that grew pages. Its center of gravity
is configuring companions, not getting help.

**Too many concepts.** To use it you meet: crew, main companion, den/resting, presence (3
modes), card detail (3 levels), comfort (3 presets), 18 characters, 3 art styles, 18 coats,
extras, bindings, requests, activity, connected tools, companion tools. Each is defensible
alone; together they are a maze.

**The companions behave badly.** Crew companions come and go on their own; the main one wanders
unless you know to turn on Reduce motion; questions are "urgent" cards with no ×; cards stack;
one click shows a status card, a double click a command bar, a right click a menu. Nothing
tells you which.

**The characters don't work.** They are procedural Blender shapes with procedural animation:
stiff, few states, and at 150 px they read as a zoo of small animals rather than one trusted
assistant. Three "art styles" are shaders on the same models, not real design. The Pip Signal
logo is the strongest visual in the project, and the app barely uses it.

**Open session is broken where it matters.** Verified today: for sessions in the Claude desktop
app the locator stops at the agent's own bundled binary
(`…/claude-code/<version>/…/claude.app/Contents/MacOS/claude`) and "opens" that instead of
Claude.app, so nothing visible happens. Terminal sessions depend on an Automation permission we
never ask for up front. It was tested with unit tests on a fake process list, never end to end.
That is the pattern to stop: features verified only in mock data.

**Reminders, the #1 feature, are an afterthought.** They work (natural-language times, snooze,
"missed while away") but they're a plain text card, there's no repeat ("every Monday"), no
"10 minutes before", and if Sidefolk isn't running, they don't fire at all.

**What is solid and worth keeping:** the Tauri app and Rust core, the hook server and the
Claude Code / Codex integrations, the MCP tools (notify, ask, remind, presence), the installers
with backups, the reminder store and time parsing, the journal, the settings store, the Pip
Signal brand and the design tokens. About half the code is reusable foundation; the part to
rethink is what people see and touch.

## 3. Product direction

**One sentence:** Sidefolk is a desktop companion you talk to: it remembers what you tell it,
reminds you at the right moment, keeps your notes, runs small actions, and, for developers,
watches your AI sessions and takes you back to them.

**Principles**

1. **Value before customization.** Every screen answers "what does this do for me now?".
   Appearance is one small settings page.
2. **One companion by default.** It handles everything. Extra companions are an advanced choice,
   each tied to a project or a session, never needed to use the app.
3. **Calm and in your control.** The companion stays where you put it. It never wanders. It
   comes forward only for a reminder or something that needs you, then returns. Every card closes
   with ×, Esc or a click outside.
4. **One way to talk to it.** Click the companion (or press the shortcut) → one input. Type what
   you want. It shows what it understood before it acts. No right-click menus to learn.
5. **The companion and the app do the same things.** The companion is the quick shortcut; the app
   is where you see everything, copy your notes, review and configure. Anything you can tell the
   companion you can also do in the app, and the other way round.
6. **No tokens for what the Mac can do itself.** A plain command (`ls -la`, `git status`, "open
   this folder") runs locally after a preview, never through Codex or Claude. AI is used only when
   the request needs reasoning.
7. **Works for everyone.** Reminders, notes and actions need no technical setup. Developer
   features appear only when you connect an AI tool.
8. **Local first, AI optional and visible.** Everything is stored on the Mac, notes as plain
   Markdown. Times and simple commands are understood locally. AI is used only for fuzzy requests
   and summaries, through your own Claude or Codex, and the app says when it does.
9. **Tested for real.** Each feature is checked end to end in the running app before it's called
   done (section 9).

## 4. The companion

**Discussed 24 October:** of three 2D sketches (Pip, Dot, Spark), you picked **Pip and Spark**;
Dot is out. Concept sheets with the eight key states are in
[creative-design/v2/](../creative-design/v2/) (`pip-concept-sheet.png`,
`spark-concept-sheet.png`), generated with Codex image generation, which we'll keep using to
explore assets before building them. Pip was also tried with a full body: `pip-body-a.png`
(simple all-charcoal body), `pip-body-b.png` (ivory belly and mint scarf), compared in
`pip-head-vs-body.png`. **Decided: Pip has a body, variant B** (charcoal, ivory belly, mint
scarf; `pip-body-b.png` is the reference). The head-only mark stays the logo and app icon.
**Decided: Pip is your personal companion** (reminders, notes, actions, everything), and
**Sparks are workers** you create for a project or an AI session. **Decided: color and accessory
identify a worker at a glance**: each new Spark gets its own color automatically (changeable),
picked from a set that never uses the status colors, so you know which project is talking before
reading anything. Status stays on the antenna dot and in words. Customization: name, color,
one accessory, size; Sparks also carry a small project badge.

**Recommendation: companions drawn in 2D vector from these sheets, animated by hand-tuned
code.** Retire the eighteen 3D animals.

- **Why the logo.** It's the thing you liked, it's simple enough to animate beautifully, and it
  reads as an assistant with a personality, not a pet. The mint signal dot becomes its status
  light, which ties brand and function together.
- **Why 2D vector.** Crisp at any size, light on CPU (no WebGL per companion), and every
  expression is drawn on purpose instead of emerging from a rig. Eyes, ears and the dot carry
  almost all emotion; the body can be a soft rounded base.
- **Why code-driven first.** I can build and tune it here with springs and easing (squash on
  landing, ears that lag, blinks, eye tracking). If a designer joins later, the same states can
  move to [Rive](https://rive.app), whose web runtime runs in our window and is built for
  interactive state machines.
- **States, few and polished:** idle (breathing, blinks, glances at the cursor), listening (you
  are typing), thinking, working, needs you, done, writing a note (pencil), holding a note
  (reminder), sleeping, and a short hop on arrival. Each one designed and reviewed as a frame, not
  improvised.
- **Customization, kept small:** name, color (6–8 curated), one accessory (glasses, headphones,
  scarf, cap), size. Extra companions use the same design with their own color and a project
  badge, so a crew looks like a team, not a zoo.

**First step:** I draw a character sheet (all states as static frames) and a short animated
prototype in the browser. You approve the look before anything else is built.

## 5. The app

A real macOS app: Dock icon, ⌘Tab, a normal resizable window with full screen, a menu bar with
the usual menus (File, Edit, View, Window, Help), and the menu bar icon kept for quick access. An
option hides the Dock icon for people who prefer a menu bar app.

**Sidebar, in this order:**

| Section | What it's for |
|---|---|
| **Today** | Next reminders, what needs you, notes added today, and (developers) sessions running or waiting |
| **Reminders** | Upcoming, repeating, done; edit, snooze, delete |
| **Notes** | Notebooks ("Evaluation H2 2026", "Ideas"); entries dated; search; export |
| **Actions** | Saved commands and shortcuts; run with one click or a sentence |
| **Sessions** | Developers only: AI sessions by project, their state, open/start/continue |
| **Settings** | Companion, shortcut, terminal and AI defaults, connections, privacy |

The companion and the app are one experience: anything you tell the companion shows up in the
app, and anything in the app has a "show me" that brings the companion.

**Setup guide (first launch, about a minute):**

1. Meet your companion: name it, pick a color.
2. Try it: "Remind me in 2 minutes to stretch". It writes the note and comes back holding it.
3. Where should it live: corner, size, the shortcut.
4. Optional, for developers: connect Claude Code / Codex, choose your terminal (detected:
   Terminal, iTerm, Ghostty, Warp, VS Code) and where sessions open (terminal or Claude desktop
   when both exist).
5. Start at login (recommended, so reminders always arrive).

## 6. The MVP

Four pillars, each finished properly. Everything else waits.

### 6.1 Reminders (the first and most important)

- **Say it naturally:** "tomorrow 9am check the RT results", "meeting at 3, remind me 10 minutes
  before", "every Monday at 9 standup notes", "in 20 minutes call mum". Times are understood
  locally. Before saving, the companion shows "Tomorrow, Fri 25 Oct, 9:00 · Check the RT
  results" with Save / Change.
- **Repeating reminders:** daily, weekdays, weekly, monthly, "every 2 weeks".
- **At the time:** the companion comes forward holding a note card with your words in a
  handwritten style, with a soft sound. Actions: Done, Snooze (10 min, 1 hour, tomorrow), Open.
  Open shows it in the app with details and history.
- **Even if hidden or closed:** a hidden companion still comes forward. If Sidefolk isn't
  running, a scheduled macOS notification fires anyway (macOS delivers it without the app);
  clicking it opens Sidefolk on that reminder. Start at login is the default so this is rare.
- **Missed while asleep:** shown once when you're back, with the original time.
- **Done when:** a reminder set by voice-style text fires on time with the app hidden, with the
  app quit (as a notification), after the Mac slept, and repeats correctly across a DST change.

### 6.2 Notes that collect over time

- **Notebooks** you name: "Evaluation H2 2026", "Project X decisions", "Ideas".
- **Capture in one sentence:** "note for evaluation: shipped the login migration, cut errors by
  40%". The companion writes it with today's date (and the project if you're in one) and
  confirms with a small writing animation. If it can't tell which notebook, it asks with
  one-click choices.
- **Gentle prompts (opt-in):** "Every Friday at 4, ask me what I achieved this week." That's a
  repeating reminder that opens a quick capture, which is exactly your evaluation habit.
- **In the app:** each notebook is a dated list; search; edit; export to Markdown. Stored as
  Markdown files you can open anywhere.
- **With AI (optional, visible):** "draft my evaluation from this notebook" turns six months of
  entries into a structured draft (achievements by objective, with dates), using your Claude or
  Codex.
- **Done when:** you can capture from the companion in under five seconds and, after weeks of
  entries, export or draft a summary without leaving the app.

### 6.3 AI sessions (for developers)

- **Start:** "open a Claude session in sidefolk" → opens it the way you chose (terminal with your
  default terminal, or Claude desktop), in that repository.
- **Watch:** every Claude Code / Codex session reports to the companion (hooks, as today):
  working, needs your answer, finished, failed. Finished and failed are announced once; "needs
  you" stays until handled.
- **Open (fixed and tested):** "open it" or one click takes you to that exact session: its
  terminal tab, or Claude desktop. If it ended, it resumes it. The host lookup will skip the
  agent's own bundled binaries and stop at the real app; Automation permission is requested
  during setup with an explanation, not at the first click.
- **Name and bind from anywhere:**
  - App: Sessions → New companion for a folder or a session.
  - Terminal: `sidefolk here --name "Backend"` in a folder; `sidefolk sessions` lists them.
  - Inside Claude Code or Codex: a `/sidefolk` command (shipped as a plugin/skill using our MCP
    tools): "/sidefolk name this session Confluence analyst".
- **Permissions per session.** By default a session asks you, and you answer on the companion
  with the full command shown, as today. Per session you can switch to **full access** ("do it and
  come back when you're done"): Claude Code's auto / accept-edits / bypass modes and Codex's
  approval policy and sandbox are set when Sidefolk starts the session, or changed for a running
  one. The current mode shows on the session and the companion's card; the default never changes
  silently.
- **Done when:** with Ghostty, Terminal and Claude desktop, start → get notified → open lands on
  the right session, every time, in the running app.

### 6.4 Quick actions (small, safe)

- "open a terminal in ~/git/sidefolk", "open sidefolk in VS Code", "open the team's Jira".
- "run npm test in sidefolk": shows the exact command and folder, runs it in your terminal (so
  you see the output), never silently.
- **Plain commands are recognized locally.** If what you type starts with a real command
  (`ls -la`, `git pull`, `npm test`), the companion offers "Run in terminal" or "Run here and
  show the output". v0.1 sent anything it didn't understand to Codex, which wasted tokens and
  asked for permissions on things you could run yourself; that path goes away. Asking an AI
  becomes an explicit choice ("ask Claude…", "ask Codex…").
- **Saved actions:** name a command once ("deploy staging") and run it by name or with a
  click. Results: the companion says done or failed and can open the output.
- **Done when:** the five most common actions take one sentence and nothing runs that the user
  didn't see first.

## 7. Brainstorm: small helpers worth adding

Grouped by when I'd do them. ★ marks ones that build on the MVP almost for free.

**Right after the MVP**

- ★ **Calendar heads-up:** reads your macOS Calendar (with permission); "meeting in 5 minutes"
  with a Join button for the video link. No setup beyond one permission.
- ★ **Morning brief:** first unlock of the day: today's reminders, meetings, sessions waiting.
  One card, dismissed in a click.
- ★ **Weekly wins prompt** (the evaluation habit, generalized), using notes.
- **Timers:** "tea in 4 minutes", "focus 25 minutes" (with a quiet do-not-disturb look).
- **Clipboard to note:** copy text, "save this to Ideas".
- **End of day:** what you finished, what's still open (reminders, sessions), what's tomorrow.

**Later**

- **Voice:** hold the shortcut and speak (macOS speech recognition, on device).
- **Screenshot to note:** capture a region; text is read on device (Vision) and saved.
- **AI on what you copied:** summarize, translate, rewrite an email, with a clear "uses Claude"
  label.
- **Apple Reminders / Calendar sync** for the phone.
- **Team of sessions:** "ask the reviewer to check this". Works reliably only for sessions
  Sidefolk launches itself (it can message them and keep a transcript you can open or resume in
  a terminal). Messaging a session you typed into yourself would mean typing into your
  terminal, which is fragile, so I'd only do the managed kind.

**Not now**

- More characters and styles, photo-to-companion, importing 3D models, Windows. Each is fun;
  none helps someone get through their day.

## 8. Keep, rework, park

| Keep (foundation) | Rework | Park or delete |
|---|---|---|
| Tauri + Rust core, data folder, settings store | The companion: 2D Pip, polished states | 18-character roster, 3 art styles, 18 coats |
| Hook server, Claude/Codex integrations, permissions | The app shell: real window, sidebar above | Comfort presets, presence modes, card-detail levels (keep one privacy switch) |
| MCP tools and installers with backups | Interaction: one input, every card closable | Crew wandering, den behavior, right-click menus |
| Reminder store, time parsing, journal | Reminders (repeat, offsets, notifications) | Photo-to-look, glb import, Codex dispatch from the bar, demo |
| Pip Signal brand, tokens, WebKit check | Open session (host lookup, permissions, Claude desktop) | Activity timeline (folds into Sessions and Today) |

Parked code stays in git history (tag the current state `v0.1-zoo` before removing it).

## 9. How we'll work so it doesn't get messy again

- **One pillar at a time,** in order; each ends with a demo you try on your Mac before the next
  starts.
- **End-to-end checks in the real app** for every "done when" above: a test script per pillar
  (for example: set reminder → hide app → quit → wait → notification appears → click → app
  opens on it). Unit tests stay, but they don't count as done.
- **A visual review for anything you see:** I render the states and screens and you approve
  them before wiring.
- **Scope guard:** new ideas go to section 7, not into the current pillar.

## 10. Roadmap

Sizes: S ≈ a few days, M ≈ a week, L ≈ two weeks of focused work.

| Phase | Goal | Delivers | Done when | Size |
|---|---|---|---|---|
| 0. Reset ✓ (24 Oct) | Clean ground | Tag `v0.1-zoo`; remove parked features; one companion on screen that stays put and never wanders; every card closable | The desktop is calm and you can't get stuck | S |
| 1. Companion ✓ (24 Oct) | A character you like | Pip (body B) and Spark from the concept sheets: final character sheet → approval → 2D with the core states, drag to place, hide to edge | You'd keep it on your screen all day | M |
| 2. App shell ✓ (24 Oct) | A real app | Dock app, window with sidebar (Today, Reminders, Notes, Settings; others hidden until built), menus, setup guide, the one input | A new user gets through setup and finds everything | M |
| 3. Reminders | Pillar 1 | Natural capture, confirm, repeats, offsets, note-holding arrival, notifications when quit, app views | Section 6.1 checks pass on your Mac | M |
| 4. Sessions basics ✓ built (24 Oct; hand checks pending) | Fix today's worst pains | Open session fixed for Terminal, Ghostty, iTerm and Claude desktop (tested end to end); plain commands run locally, never through AI; per-session full access; default terminal and session app in Settings | You open any session in one click, `ls -la` never reaches Codex, a full-access session doesn't ask | S–M |
| 5. Notes ✓ built (24 Oct; hand checks pending) | Pillar 2 | Notebooks, one-sentence capture, prompts, search, Markdown export, optional AI draft | Section 6.2 checks pass | M |
| 6. Sessions | Pillar 3 | Sparks per project or session (color, badge), start/watch from the companion, `sidefolk` CLI, `/sidefolk` command in Claude Code and Codex | Section 6.3 checks pass with your setup at work and at home | L |
| 7. Actions | Pillar 4 | Open folder/app/URL, run command with preview, saved actions | Section 6.4 checks pass | S–M |
| 8. Beta | Ship it | Signing and notarization (your keys), auto-update, crash reports opt-in, a short guide | Two or three colleagues use it for a week | M |
| 9. Next | Section 7 | Calendar heads-up, morning brief, weekly wins, timers… | One at a time, by your pick | – |

**Decided (order C):** reminders first, then the session basics that fix today's biggest pains,
then notes, then the full sessions pillar with Sparks, then actions. Phases 0–5 are useful for
anyone; phase 6 is the developer edge.

## 11. Decisions I need from you

1. **Companion look:** ~~2D Pip, or 3D with a designer?~~ 2D, Pip and Spark (concept sheets in
   creative-design/v2). Pip has a body (variant B) and is your personal companion; Sparks are
   workers per project or session, told apart by color and accessory. **Decided.**
2. **MVP order:** Reminders → session basics → Notes → Sessions (Sparks) → Actions.
   **Decided (option C).**
3. **AI:** layered. **Decided.** (1) Plain rules on the Mac first, no AI: times, repeats,
   commands, "note for …", "open …". (2) Apple's on-device model for small understanding tasks
   when Apple Intelligence is available. (3) Your installed Claude Code / Codex (`claude -p`,
   `codex exec`) for heavier writing, labelled "uses Claude" / "uses Codex" before it runs.
   (4) An API key only as a later, optional setting. Reminders, notes and actions never need AI.
4. **Dock:** in the Dock by default, like a normal Mac app (⌘Tab, resizable and full-screen
   window, standard menus); closing the window keeps the companion and reminders running; the
   menu bar icon stays; Settings → "Hide from Dock". **Decided (option A).**
5. **Reset:** **Decided (option A).** Phase 0 commits today's uncommitted work as it is (no
   Co-Authored-By), tags it `v0.1-zoo`, then removes the parked list in section 8 and keeps the
   foundation. Result: one calm Pip that stays put, every card closable, until phase 1.
6. **Calendar heads-up:** right after the MVP (first item of phase 9); until then "meeting at 3,
   remind me 10 minutes before" covers it. **Decided (option A).** Open: whether the work
   calendar is on the Mac (Calendar.app or Outlook for Mac) or only on the web.

## 12. Risks

- **Character quality** is the riskiest part; that's why it comes first with a visual review.
- **Opening the exact session** depends on each terminal's scripting support: Terminal and iTerm
  can pick a tab, Ghostty and Warp can only be brought forward. Claude desktop can be brought
  forward; selecting one chat inside it may not be possible. I'll confirm each one early in
  phase 5 and say so in the app.
- **Reminders while the app is quit** rely on macOS notifications being allowed; setup asks.
- **Messaging sessions (team)** is only reliable for sessions Sidefolk launches; that's why it's
  later and scoped.
