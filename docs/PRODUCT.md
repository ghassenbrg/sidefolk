# Sidefolk — Product Specification (V1)

Sidefolk is a living AI companion for the Mac. A small character lives on your desktop, remembers
what you tell it, keeps track of time and things you asked it to watch, acts through tools you
allow, and comes to you when something needs you. Other AI agents (Claude Code, Codex, any MCP
client) can talk to it too.

The founding discussion (docs/FOUNDING.md summarises it) is the seed, not the contract. Where this
spec differs from it, docs/DECISIONS.md says why.

## 1. Vision in one paragraph

Today AI lives in a chat box: you open it, ask, get text, it forgets. Sidefolk inverts that. The
companion is always there, has a body that shows what it is doing at a glance, owns a memory you can
see and edit, and keeps working after the conversation ends: reminders fire tomorrow, watchers
notice a page changed, a routine runs every morning. Models are interchangeable brains; the
companion, its memory, its notebook, its jobs and its permissions persist.

## 2. Principles

1. **Presence over chat.** The body is an interface. State is visible without opening anything.
   Conversations are short exchanges that end in *results* (a saved note, a scheduled reminder),
   not an endless transcript.
2. **It works when you are not looking.** Reminders, watchers and routines are deterministic,
   persistent and survive restarts. AI wakes only when reasoning is needed.
3. **You stay in control.** A deterministic Guard (never the model) decides what may run. Risky
   actions are confirmed in plain language. Everything is logged in Activity and most things can be
   undone.
4. **Respect attention.** Interruptions are rare, graded and grouped. Quiet mode, fullscreen
   awareness, snooze and one-time re-nudges, never nagging.
5. **Memory you can see.** The Notebook (including "About you") is explicit, editable and deletable. No hidden
   profile. Implicit context expires.
6. **Local first.** Everything lives on the Mac in one folder. The only network traffic is the AI
   provider you chose, web pages you asked about, and extensions you allowed.
7. **Extensible core.** The core knows memory, time, jobs, permissions and orchestration. Abilities
   come from tools, skills and extensions (MCP compatible). The companion can write new skills.
8. **Model independent.** Claude via your Claude Code subscription, Anthropic API, OpenAI-compatible
   endpoints (OpenAI, Ollama, LM Studio, OpenRouter). Fast and Smart model slots per provider.
   Without any AI, slash commands and the UI still work.

## 3. Who it is for

- **Primary: the AI-native maker** (developer/designer/founder) who already uses Claude Code or
  Codex, juggles projects, forgets small things, and wants a companion that captures ideas,
  reminds, watches builds/pages/downloads and connects to their agents.
- **Secondary: the organised knowledge worker** who wants a friendly, private desk companion for
  notes, lists, reminders and "tell me when X" without learning a new productivity system.

## 4. Core experiences (V1)

| # | Experience | Example |
|---|------------|---------|
| E1 | Talk to it anywhere | Click the companion or press ⌘⇧Space, type, Enter. The panel opens beside the character. |
| E2 | Capture | "Save this idea to Sidefolk: extensions could have their own folk" → Pip pops up, *Saved to Sidefolk › Ideas*, Undo. |
| E3 | Recall | "What ideas did I save for Sidefolk?" → answered from the Notebook with links to the notes. |
| E4 | Remind | "Remind me tomorrow morning to send the document" → persists, fires at 09:00 (configurable "morning"), even after relaunch; Done / Snooze / Open. |
| E5 | Watch | "Tell me when example.com/pricing changes", "when report.pdf lands in Downloads", "when pid 4312 exits", "when the server is back up". |
| E6 | Act | Open apps/URLs, list/move/rename files in folders you granted, read/write clipboard, fetch a page, run a confirmed command. |
| E7 | Routines | "Every weekday at 9, give me my open tasks" → a scheduled prompt the companion runs and presents. |
| E8 | Glanceable state | Sleeping, listening, thinking, working (with a prop that says *what*), waiting for approval, success, error, alert. |
| E9 | Agents talk to it | In Claude Code: "tell Sidefolk to ping me when tests pass" → MCP tool call → companion watches and notifies. Also notes/reminders/ask_user from any MCP client. |
| E10 | Extend it | Install an extension folder (manifest + MCP-speaking executable), see its permissions, its tools and watchers become available; or ask the companion to write a skill. |
| E11 | Drop things on it | Drag a file, URL or text onto the character → choose Save, Ask, Remind, Watch. |
| E12 | Trust | Activity log of every action, Permissions page, Privacy page that shows what is stored and what was last sent to the AI. |

## 5. V1 scope

Priorities: **P0** must ship, **P1** ships unless blocked, **P2** stretch for V1 (otherwise backlog).
Updated after the product review (docs/DECISIONS.md D4–D12).

### Body and surfaces
- P0 Companion window: transparent, always on top, all Spaces, beside fullscreen apps, draggable,
  remembers position per display, stands on the desktop floor. Never wanders on its own.
- P0 Character engine: layered vector rig on Core Animation, pose-based states with smooth
  transitions, blink/breathe idle, props per activity, reduced motion, near-zero idle CPU.
- P0 Presence modes: Always / Only when needed (peek) / Menu bar only.
- P0 Companion choices: Mochi rabbit by default, original Sidefolk robot with its four light colors,
  and Spark. Switching is live; existing saved choices and custom names are preserved (D27, D29).
- P0 Ask panel beside the companion: input with a hint line (what Enter does, whether it uses AI),
  result cards (max 3 visible), approval cards, Undo; quick intents close it 1 s after the card.
- P0 Speech bubbles for proactive events, with actions; a count badge when several wait.
- P0 Drag and drop onto the companion: Save · Remind me · Watch (URLs/files) · Ask.
- P0 Menu bar item with a "Now" list; global hotkey ⌘⇧Space (configurable, registration checked).
- P0 Home window: Now (reminders, watchers, sessions, jobs, waiting items), Notebook, Activity.
- P1 Folks on duty: Tempo, Scout, Byte beside the companion while their job is live (max 3).
- P2 Voice input (push-to-talk, on-device speech recognition).

### Understanding and brain
- P0 Local intent parser (no AI): remind (times, dates, recurrence), note/idea/task to a
  collection, watch (URL, file, folder, process name), quiet mode, find, done/snooze.
- P0 Agent runtime with tool loop, step/time budgets, cancel (Stop), state events.
- P0 Providers: Claude Code CLI (subscription), Anthropic API, OpenAI-compatible. Main model plus
  optional smart model for "Think harder". Connection check. No-AI mode keeps everything local working.
- P0 Context builder with a budget: persona, rules, time zone, frontmost app, "About you" notes,
  relevant notebook items (FTS), live jobs, recent exchange (10-minute thread window).

### Memory and data
- P0 Notebook: Inbox, About you (profile), projects/topics/lists with notes, ideas, tasks, links;
  full-text search; Trash with restore (30 days); Undo for recent changes.
- P0 Short-term exchange history with retention (default 7 days), never shown as a transcript.
- P0 Activity log (audit) of every tool execution and decision.
- P1 Export all data (JSON) and delete all data.

### Time, watching and agents
- P0 Reminders: natural times, recurrence, snooze, done, survive restart, missed ones summarised on
  return, fallback system notifications scheduled when the app quits.
- P0 Watchers: web page change/contains (normalised text diff, 1% threshold, before/after),
  site up/down (2 failures in a row), file/folder appears, file changed, process (by name) exits,
  periodic command (confirmed). Floors, backoff, cooldown, expiry, pause/resume.
- P0 `sidefolk run -- <cmd>`: runs a command, the companion tells you when it ends (exit, time).
- P0 `sidefolk mcp`: Sidefolk tools for Claude Code, Codex and any MCP client (note, remind, watch,
  notify, ask_user, search). One-click connect after confirmation and config backup.
- P1 Claude Code session awareness via hooks (installed on click, with backup): working, needs
  you, finished; "Open" brings its app to the front.
- P1 Morning brief (deterministic): today's reminders, open tasks, active watchers.
- P2 Scheduled prompts (routines run by the agent), workers (hand a coding task to Claude Code/Codex).

### Hands and Guard
- P0 Built-in tools: notebook, about-you, reminders, watchers, clipboard, open URL/app/file,
  files (list/read/search/move/rename/create folder/trash) in granted folders, web fetch, time.
- P1 The Mac's own apps (D38): Apple Notes (list, read, copy into the notebook organized, and move
  after a whole copy when asked) and Apple Reminders (read), through Apple Events with Guard approvals.
- P0 Guard: risk levels, caller trust, taint, folder grants, protected paths, approvals, audit.
- P0 Secrets in the Keychain.

### Extensibility
- P0 Extension host: manifest, discovery, permissions shown at install, sandboxed process,
  MCP tools, Sidefolk watcher protocol, timeouts, crash isolation, enable/disable/uninstall.
- P0 Sample extension (System Vitals) and an extension developer guide.
- P0 Add any MCP server (unsandboxed, labelled, medium-risk tools).
- P1 Skills: markdown instructions loaded on demand; the companion can propose a skill (user approves).

### Attention
- P0 Levels and defaults in §11, quiet mode, fullscreen/away deferral, typing guard, rate limits,
  grouping, one re-nudge, snooze.

### Onboarding and settings
- P0 First run happens on the desktop through the companion (no wizard): hello, connect Claude Code
  and Codex if found, a real reminder in 2 minutes without AI, notifications asked in context, open
  at login. AI setup is offered when first needed. Each folk introduces itself the first time it appears.
- P0 Settings that all work: General, Companion & Attention, AI, Agents, Privacy & Permissions, Extensions.

### Quality
- P0 Structured local logs with redaction, diagnostics export, agent run records.
- P0 Tests for core logic, persistence, restart, failure and security paths.
- P0 Release build script, app icon, signing/notarization pipeline (credential step documented).

## 6. Explicit non-goals for V1

Accounts, sync, mobile, web app, cloud backend, multi-user, purchases/shopping, sending email or
messages on the user's behalf, reading other apps' window contents or the screen, continuous
clipboard monitoring, AI-generated executable code, auto-update (no signing identity/feed yet).

## 7. Interaction map

```
Companion (click) ─────────────► Ask panel ──► exchange ──► result cards / approvals
Companion (drag) ──────────────► move, settle on floor
Companion (drop file/url/text) ► Ask panel with attachment + quick actions
Companion (right-click) ───────► menu: Ask, Today, Notebook, Quiet 1h, Hide, Settings
Companion (double-click) ──────► Home window
⌘⇧Space ──────────────────────► Ask panel (from anywhere)
Menu bar icon ─────────────────► Ask, Open Sidefolk, Quiet, Show/Hide companion, Settings, Quit
Bubble ────────────────────────► action buttons (Done, Snooze, Open, Allow/Deny, Dismiss)
System notification ───────────► same actions when the companion is hidden/away
External agent (MCP) ──────────► tools → Guard → companion reacts (cameo + bubble)
```

## 8. Companion states

| State | Trigger | Body |
|-------|---------|------|
| idle | nothing happening | breathing, blinks, glances toward pointer |
| sleeping | user idle > 10 min, quiet hours, or Mac about to sleep | lying, closed eyes, zZz |
| listening | panel open / typing | looks at the panel, ear pods glow |
| thinking | model call in flight | eyes up, "…" dots |
| working | tool running | prop by category: notepad (notes), clock (time), binoculars (watch), folder (files), globe (web), laptop (agents/extensions) |
| waiting | approval needed | holds a card, Guard beside |
| success | action completed | happy eyes, small hop, sparkle |
| error | action failed | worried eyes, sweat drop |
| alert | reminder/watch fired | wave, exclamation, bubble |
| dragging | being moved | dangling, surprised |
| watching (badge) | active watchers | small binoculars badge (ambient) |

Priority when several apply: dragging > waiting > alert > error/success (transient) > working >
thinking > listening > idle > sleeping.

## 9. Capability model

- **Tool**: atomic, typed (JSON Schema input), declares `risk`, `capabilities` (e.g. `files.write`,
  `network`), `category` (for the body prop), whether it mutates and can be undone.
- **Skill**: instructions (markdown) that compose tools for a goal; loaded on demand.
- **Watcher kind**: a probe that turns config + previous state into "triggered?" deterministically.
- **Extension**: a package that contributes tools and watcher kinds (and a folk), runs out of
  process, sandboxed by its declared permissions.
- **Routine**: a schedule plus a prompt run by the agent.

## 10. Permissions model (Guard)

Risk: **low** (auto), **medium** (ask, may be granted "always" with a scope), **high** (ask every
time). Callers: user via UI/slash command (most trusted), Sidefolk's own agent, routine,
external MCP agent, extension. Rules:
- The model never decides permissions; Guard evaluates every call before execution.
- Untrusted content (web pages, files, clipboard, extension output) taints the turn; while tainted,
  any medium/high call and any network call with model-built URLs needs confirmation.
- File tools only act inside folders the user granted (granted on first use or in Settings).
- Destructive file operations move to Trash; nothing is hard-deleted by tools.
- Shell commands are shown verbatim; "always" can only be granted for that exact command.
- External agents and routines cannot answer approvals; approvals always come from the user.
- How much Sidefolk asks before its own agent acts is the person's choice (D37): Ask every time,
  Ask once per kind (default), Auto, or Full access (only after a sheet that says what it means).
  No mode lifts the rules above for content-steered actions that could send data out, for other
  agents or for extensions; the mode is always visible (Ask panel chip, menu bar, Now).
- If the person doesn't answer, a card of Sidefolk's own agent never holds the task: by default the
  step is skipped after 10 minutes and the task carries on; the step waits in Now with "Run it now".

## 11. Attention model

| Level | Presentation | Example |
|-------|--------------|---------|
| ambient | pose/badge/folk only | watcher active, job running |
| gentle | small bubble, 6 s, paused on hover, one at a time | Claude saved a note |
| attention | companion steps forward; bubble expanded 30 s then collapses to a held card + badge | reminder, watcher fired, command finished |
| critical | attention + system notification + sound | reminder marked important |

Defaults: typing guard (wait for 1.5 s without keys, defer at most 20 s); at most 1 attention event
per 90 s and 3 per source per 10 min, the rest fold into "+N"; external agents capped at attention
level without sound; quiet mode and fullscreen-frontmost hold everything but critical (which
becomes a system notification); away (5 min idle or locked) queues and shows one summary on return;
one re-nudge after 10 minutes, then it waits in the badge; celebrate only waits longer than 2 min.

## 12. Failure model

Every failure shown to the user says what failed, whether anything changed, and what they can do.
Examples: AI unreachable → "I couldn't reach Claude. Nothing was changed. Check your connection or
switch provider." Slash commands keep working offline. Watcher errors back off exponentially and
surface after 3 consecutive failures. Extension crashes are isolated; after 3 crashes in 5 minutes
it is disabled with a notice. Detailed diagnostics go to the local log.

## 13. Post-V1 backlog (not unfinished V1)

Scheduled prompts and workers, calendar awareness (EventKit), app-usage timeline and "what was I doing" recap, voice wake word,
Apple on-device model provider, embeddings for semantic recall, extension catalog/store,
companion-generated sandboxed code tools, Sparkle auto-update, cross-device sync, community
characters and personalities, Claude Code/Codex hook-based passive session monitoring.
