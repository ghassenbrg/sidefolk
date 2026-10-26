# Status

Updated: 2026-10-26, morning (orchestrated by Claude; specialist agents in worktrees, merged into
`rework`).

## Done and verified
- **Spec and design:** PRODUCT, ARCHITECTURE, DECISIONS (D1–D24), SECURITY (threat model T1–T24),
  MACOS-NOTES, VOICE, FOUNDING, CHARACTER, EXTENSIONS.
- **Character:** Core Animation rig with 11 states and 10 props, all 10 folks, app icon and menu bar
  template. Calm states settle after 20 s, loops are capped at 24 fps and pause while hidden (D20).
- **Core:** storage (GRDB, FTS5, secure_delete, 0600 files) and Guard (risk, caller, taint, user-typed
  links, hardened path policy, folder-bound command grants, approvals). Every tool input is checked
  against its schema. The executor provides audit and undo. Also attention policy and center (held
  notices survive a restart), settings, redacting logs and the runtime container.
- **Understanding:** local intent parser (reminders, notes, ideas, tasks, About you, watches, quiet,
  find) and WhenParser with recurrence (fuzz-tested: 600k random inputs, no crash), plus slash
  commands. None of these use AI.
- **Time:** the reminder scheduler fires due reminders and handles missed ones, snooze, done, edit and
  recurrence. It reschedules after wake or a clock change, schedules fallback notifications at quit,
  and runs the morning brief.
- **Watchers:** web page change, site up/down, file appears or changes, new file in a folder, process
  exit and command (confirmed), plus extension watchers. Floors, backoff, cooldowns, quotas, SSRF
  protection; the user's own request may watch localhost and the LAN (D21). Routine checks reach the
  database at most every 5 minutes.
- **Brain:** Claude Code CLI (isolated: `--tools ""`, strict MCP, restricted settings, init-event
  check), Anthropic API and OpenAI-compatible providers. The context builder has budgets and keeps
  untrusted content out; extension tool descriptions never reach the model (D24).
- **Bridge:**
  - Unix socket API with peer-uid check, brain tokens and rate limits.
  - `sidefolk mcp` gives external agents a small tool set (their names are labelled unverified; their
    approvals never take a keypress).
  - `sidefolk run -- <cmd>` (a failure shows the last stderr lines, D23), `sidefolk hook <Event>`
    (session tracking), `sidefolk status`, `sidefolk ext validate` (starts the program in its sandbox).
  - Claude Code and Codex installers that confirm first and keep a backup; the `sidefolk` command
    installs on PATH from Settings › Agents.
- **Extensions:** strict manifest, sandbox-exec profile, file hashes pinned and tampering detected,
  whole process tree tracked and stopped, crash isolation, MCP client and plain MCP servers. Changed
  tools are held until approved in Settings › Extensions ("Review changed tools…"). Samples: System
  Vitals and Hello Folk. Two bundled skills.
- **App:**
  - Companion window: click-through, drag and settle, on-duty folks (each introduces itself once),
    badges, gaze, presence modes, sleeping.
  - Ask panel: hint line, local intents, agent runs, inline questions, result and approval cards,
    undo, drop quick actions (Save, Remind me…, Watch, Ask…); newest request first.
  - Bubbles with a tail and buttons that never disappear; menu bar Now list; notifications; login item.
  - Home (Now with live work first, Notebook with search everywhere and ⌘F, Activity, Trash) and
    Settings (General, Companion, AI, Agents, Privacy & Permissions, Extensions).
  - Embodied onboarding (hello, agents, a real reminder, notifications, login), data export, delete
    everything (Keychain items included), diagnostics export with redacted logs.
- **Tests:** 813 in 88 suites. `make test` runs them serially and they pass consistently (about 40 s).

## Reviews done (second round) and what came of them
UX/product, security, QA/plugin developer and performance reviews (reports were working files, not in
the repo). Everything P0/P1 is fixed; P2 polish mostly done. Security: H1, H2, M1–M10 fixed, L items
mostly fixed (details in SECURITY.md). Performance: settled desktop now costs WindowServer 0–5 points
instead of +41 on a 120 Hz display; Sidefolk itself 0.07% CPU, 24 MB; no database writes while idle.

## End-to-end checks done in the dev app (`SIDEFOLK_HOME` QA folders, `swift scripts/dev.swift snap`)
- Reminders fire on time with a bubble and the alert pose; notes and recall work without AI.
- A watch on a temp folder asked for folder access, then fired when the file appeared.
- `sidefolk run`, `status` and MCP over the bridge; a failing `sidefolk run` shows its last stderr
  lines with Copy command / Open folder; stderr still reaches the terminal (pipe and pty both checked).
- Live Claude Code brain (2 tiny haiku calls): answered a question, then saved a note and set a
  reminder in one request.
- Onboarding order, folk introduction (Scout), bubble tail, Ask panel order, notebook search across
  collections, Settings › Extensions: checked by snapshot.
- Release build measured idle (see above).

## In progress
- A background agent is closing the security follow-ups that fell outside review 2's scope (watcher
  provenance and 24 h expiry for external watchers, reminder level clamp and own source for other
  agents' reminders, monthly anchor after undo, collection provenance, hook payload trust). Its branch
  will be merged into `rework` and the app adapted to any API change.

## Known issues / not yet verified
- **Not exercised by hand:** hooks inside a real Claude Code session; the notifications permission
  prompt; login item from /Applications; multi-monitor and fullscreen behaviour; "Connect…" for
  Claude Code/Codex (it edits real config files, so only the user should click it).
- **Watching huge folders:** a folder with more than 20,000 items can't be watched (a bound on memory
  and stored state).
- **Signing:** no Developer ID identity on this Mac, so `scripts/release.sh` (sign, notarize, staple)
  is ready but needs the founder's credentials. Builds are signed with the "Apple Development"
  identity or ad hoc.

## Next
1. Merge the security follow-up branch, adapt the app, full test run.
2. Release build (`make app`), final check, handoff.
3. Next iteration: a human "Today" timeline with an end-of-day recap (from the strategy review).
