# Status

Updated: 2026-10-26, overnight build (orchestrated by Claude; specialist agents in worktrees, merged
into `rework`).

## Done and verified
- **Spec and design:** PRODUCT, ARCHITECTURE, DECISIONS (D1–D15), SECURITY (threat model T1–T24),
  MACOS-NOTES, VOICE, FOUNDING, CHARACTER, EXTENSIONS.
- **Character:** Core Animation rig with 11 states and 10 props, all 10 folks, app icon and menu bar
  template. Idle CPU measured at 0.0% (blinks briefly use 1–3%).
- **Core:** storage (GRDB, FTS5, secure_delete, 0600 files) and Guard (risk, caller, taint, hardened
  path policy, grants, approvals). The executor provides audit and undo. Also attention policy and
  center, settings, redacting logs and the runtime container.
- **Understanding:** local intent parser (reminders, notes, ideas, tasks, About you, watches, quiet,
  find) and WhenParser with recurrence (fuzz-tested), plus slash commands. None of these use AI.
- **Time:** the reminder scheduler fires due reminders and handles missed ones, snooze, done and
  recurrence. It reschedules after wake or a clock change, schedules fallback notifications at quit,
  and runs the morning brief.
- **Watchers:** web page change (diff thresholds), site up/down (hysteresis), file appears or changes,
  new file in a folder (partial-download aware), process exit and command (confirmed), plus extension
  watchers. They have floors, backoff, cooldowns, quotas and SSRF protection.
- **Brain:** Claude Code CLI (isolated: `--tools ""`, strict MCP, restricted settings, init-event
  check), Anthropic API and OpenAI-compatible providers. The context builder has budgets and keeps
  untrusted content out. Keys live in the Keychain, bound to their host.
- **Bridge:**
  - Unix socket API with peer-uid check and brain tokens.
  - `sidefolk mcp` gives external agents a small tool set.
  - `sidefolk run -- <cmd>`, `sidefolk hook <Event>` (session tracking) and `sidefolk status`.
  - Claude Code and Codex installers that confirm first and keep a backup.
- **Extensions:** strict manifest, sandbox-exec profile, file hashes pinned and tampering detected,
  crash isolation, MCP client and plain MCP servers. Samples: System Vitals and Hello Folk. Skills
  include 2 bundled ones.
- **App:**
  - Companion window: click-through, drag and settle, on-duty folks, badges, gaze, presence modes,
    sleeping.
  - Ask panel: hint line, local intents, agent runs, result and approval cards, undo, drop
    attachments.
  - Bubbles, menu bar Now list, notifications and login item.
  - Home (Now, Notebook, Activity, Trash) and Settings (General, Companion, AI, Privacy & Permissions,
    Extensions).
  - Embodied onboarding, data export, delete everything, diagnostics export.
- **Tests:** 670 in 68 suites. `make test` runs them serially, and they pass consistently (about 25 s).

## End-to-end checks done in the dev app (`SIDEFOLK_HOME` QA folders, debug snapshot hook)
- "remind me in 1 minute to stretch" fired on time, showing a bubble and the alert pose.
- An idea saved to a new project was recalled with "what ideas did I save for Sidefolk?" (no AI).
- A watch on a temp folder asked for folder access through Guard, then fired when the file appeared.
- `sidefolk run`, `sidefolk status` and MCP over the bridge: an external agent saved a note, which
  was tagged with that agent as its source.
- Live Claude Code brain (2 tiny haiku calls): it answered a question, then saved a note and set a
  reminder in one request.
- Home and Settings render with real data.

## Known issues / not yet verified
- **Parallel test flakes:** under `swift test` (parallel) some process-spawning integration tests
  occasionally fail ("didn't start", or a freshly written fixture executable stalls at launch).
  Serial runs pass. Mitigations are in place: a spawn lock with close-on-exec pipes and a retry on
  ETXTBSY. Root cause not fully pinned down.
- **Not exercised by hand:**
  - Hooks inside a real Claude Code session.
  - Notifications permission prompt.
  - Login item from /Applications.
  - Multi-monitor and fullscreen behaviour.
- **Signing:** no Developer ID identity on this Mac, so `scripts/release.sh` (sign, notarize, staple)
  is ready but needs the founder's credentials. Dev and release builds are signed with the
  "Apple Development" identity or ad hoc.

## Next
Adversarial reviews (skeptical user, macOS, security, QA, plugin developer, performance, strategy),
then fix what they find, then release build, README, handoff.
