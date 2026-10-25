# Status

Kept to 150 lines or fewer (docs/V1.md §13.9). History is in [LOG.md](LOG.md).

## The plan

[docs/V1.md](../docs/V1.md) is the binding v1 contract (25 October 2026). It covers every
feature's status, the requirements by ID, the gates G1–G5, the roadmap P0–P8 and the guardrails
in §13. Read it first. How it was decided:
[docs/audit-2026-10-25-claude/](../docs/audit-2026-10-25-claude/) (Claude's eight-seat council,
the comparison with Codex's audit, and the supreme council's papers and RULING.md).
[creative-design/PIP.md](../creative-design/PIP.md) is Pip's character bible, frozen for v1.

## Where we are (25 October 2026, Claude Code)

**P0 Reset: done (code), uncommitted.**
- Deleted, recoverable at `76b38f1`:
  - the Codex app-server driver, the terminal inside Sidefolk (portable-pty, xterm), characters
    and the importer
  - TTS voice, saved actions and the Actions page, Sparks runtime and the MCP `spark` tool
  - the `sidefolk here` CLI and its admin install, the morning brief, the AI "Draft a summary"
  - per-session full access (`access.ts`, "Allow everything", the Rust mirror)
  - nine of ten characters' frames and every 2D frame (public/crew is 508 KB); `public/crew/spark/3d`
    stays for v1.2
- Calendar is kept behind the Cargo feature `calendar` (off). Its TS isn't wired.
- Pip only: `src/roster.ts` (PIP_FRAMES, picture). Sample data shows only real capabilities (a
  Claude request, no Codex "needs you").
- Metadata: min macOS 14.0, new descriptions, `NSAppleEventsUsageDescription`, calendar usage
  strings removed.
- Docs: README, GUIDE, AGENTS.md (points to V1.md); PLAN-V2 and ROADMAP marked as history.

**Pulled forward from P1 and P3 (trust fixes, small):**
- `src-tauri/src/store.rs`: every JSON store (settings, reminders, crew) loads as
  Missing, Ok or Corrupt.
  - A damaged or unreadable file is renamed to `<name>.corrupt-<ms>` and never overwritten.
  - Each good load writes `<name>.json.bak`.
  - Files are written as `{version: 1, data}`; files from before are read as version 0.
  - Settings never block launch anymore.
  - Today shows "I couldn't read your … file" with Restore last good copy (`restore_store`
    restarts the app) and Show in Finder. Preview: `/settings.html?damaged`.
- Quick add:
  - `$` is the only way to a shell command, and only with Settings → General → Labs → Commands
    on (`labs_commands`, off by default).
  - Starting sessions is gated the same way (`labs_sessions`).
  - Any text with a date or time is a reminder, checked before `open …`.
  - Text Pip has no rule for offers "Save as a note".
  - "what do I have today" opens Today; "show my notes" and "show my reminders" work.
- Times (`src/when.ts` resolve(), DECISIONS #40):
  - a bare hour resolves between 07:00 and 21:59, today when possible; the other reading is kept
    as `alternative`
  - date and time said apart are merged
  - tonight/end of day/morning/afternoon/evening/noon
  - "meeting at 3, 10 min before" lands today
  - a past date-only time asks when

**Verified (25 Oct):**
- typecheck
- 77 Vitest
- 35 Rust tests (3 opt-in ignored)
- `npm run check:webkit` (both themes; updated for v1: no full-access switch, no "Allow
  everything", Labs gating, `$` commands, English never reaches the run card)
- `npm run web:build`
- cargo build with and without `--features calendar`

`npm run build` passed: Sidefolk.app is 4.73 MiB, down from 9.27. It was not relaunched; the
user's running copy is older.

Nothing native was checked in the real app.

## Next step (exact)

WIP = 1. Continue **P1 Foundation** (V1 §14):
1. `src-tauri/src/requests.rs`: one request lifecycle (pending → answered / released /
   expired). It keeps the raw tool input apart from the display and caps 5 per session; a
   released or expired request can never become an Allow. Move the lifecycle out of `hooks.rs`
   and `bus.rs` (Permissions). Test: a long prefix can't change the outcome.
2. Typed events and state in Rust instead of `publish_status` polling (`prefs.rs`,
   `src/main.ts` setInterval, `src/dashboard/app.ts` 3 s refresh). The window must work with
   the overlay hidden (V1-Q1, Codex F07). A look or size change must not drop open cards.
3. Single instance (tauri-plugin-single-instance; needs a DECISIONS line, guardrail 6), a port
   bind failure shown in the UI, IO commands made async.

Then P2 (series engine in Rust, Log notebook + exact-or-ask, timeline, Your week), P3 (corpus of
300 phrases, choice UI for `alternative`, same-surface finishing), P4 (sidecar hook over a Unix
socket, routing so a request reaches Pip unless that session's tab is focused, raw display and
diffs, host matrix spikes), P5 (component kit, view re-implementation, ⌘, Settings window with 4
panes, setup, keyboard/VoiceOver, voice table, puzzled pose), and P6 in parallel (signing,
updater, kill switch, uninstall, CI).

## Waiting on the founder (V1 §16)

- Veto any reversal in V1 §15, or let it stand.
- Commit: nothing is committed. The staged `art/blender/film-duo/` files are untouched and
  still staged; V1 F-41 says they move to branch `art/film-duo`, on the founder's word.
- Apple Developer Program enrolment (critical path for G5); the wave-1 testers (8 developers +
  3 people with no agents); a domain; making the repo public under MIT.
- Hand checks in the real app once P1–P5 land (gates G2, G4), and the Mission Control spike
  for "Hide from screen recordings" (V1-X8).

## Known gaps (not done, do not claim)

- A request still skips Pip whenever any terminal is frontmost (B2): that's P4.
- Codex sessions are not watched. Reminders still advance only on Done; snooze moves the series
  (F05): that's P2.
- A notebook's partial name still picks the most recently updated match (F06): that's P2.
- The window is still the old CSS (P5). Settings still has 8 categories, not 4 (P5).
- No signing, updater or uninstall (P6). The hooks are still HTTP on 47821 (P4).
- Clippy shows 6 older warnings; CI with `-D warnings` comes in P6.
