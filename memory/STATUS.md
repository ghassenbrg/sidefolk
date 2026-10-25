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

## P1 Foundation (25 October, Claude Code): built, verified in WebKit

- `src-tauri/src/requests.rs` is the one request lifecycle. It keeps the raw tool input apart
  from the display.
  - Commands are shown byte for byte; Edit shows a diff, Write the whole content.
  - Control and bidi characters are shown as visible escapes.
  - Anything over 50,000 characters can't be allowed.
  - At most 5 open per session.
  - A released or forgotten request can never become an Allow.
- `hooks.rs` uses it. The old `bus::Permissions`, `PermissionAsk` and `describe` are gone.
- Opening a live session releases its waiting requests to the session's own prompt.
- The window gets requests from Rust (`list_requests` plus the `requests` event) and answers in
  Rust. It works with the overlay hidden, and a reloaded overlay re-shows open requests.
- Pip's card shows Allow only if the operation fits on the card; otherwise it shows "Review all
  of it". Preview key 8 makes a long request.
- No polling: the overlay publishes status on change; the window refreshes on focus and events.
- Single instance (DECISIONS #42).
- A port bind failure is shown on Today and in Settings → AI tools (preview: `?portbusy`).
- File-IO commands run off the main thread (`#[tauri::command(async)]`).
- **Pip and Spark (founder, DECISIONS #41):**
  - Settings → Companion picks Pip or Spark (crew.json `main.look`); preview: `?look=spark`.
  - Spark's status light follows its antenna tip in every pose (`src/pip.ts` `tip`).
  - V1 F-24, C1 and C8 and PIP.md are updated.
- Verified: typecheck, 78 Vitest, 41 Rust, `npm run check:webkit` (adds long-request card, Pip and
  Spark choice).
- Codex's adversarial review (guardrail 5) found 3 blockers and 6 majors, all fixed with tests:
  - Edit `replace_all` and unknown fields are now shown, not hidden.
  - Allow appears only once the whole operation is on screen: the card shows the full height,
    and the window's Allow stays off until you scroll to the end.
  - Past its deadline, a request is refused even before the timer fires.
  - Paths and more invisible characters (U+2060, U+061C, NBSP, tags…) are escaped.
  - Diffs keep CRLF and say when a final newline is missing.
  - A store envelope must be exactly `{version, data}` with a known version.
  - Store shapes are checked, so `[]` or `null` is damage.
  - A crew.json that couldn't be set aside is never written over.
- Verified after the fixes: typecheck, 78 Vitest, 45 Rust, WebKit (including read-to-the-end),
  release build 4.83 MiB. Nothing native was hand-checked.

## Next step (exact)

P1 is done apart from moving reminders and companion state fully into Rust, which falls under
P2's series engine. Continue **P2 Reminders & log** (V1 §4, §5, §14):
1. The series engine in Rust (`reminders.rs`). The series anchor and occurrence overrides are
   separate, so snooze never moves the series. Repeats fire without Done; Skip next.
2. Pre-schedule up to 60 notifications (`notifications.rs`), and show "While you were away" for
   late ones.
3. The Log notebook as the inbox, exact-or-ask notebook matching (`src/notes.ts` matchNotebook:
   delete the most-recently-updated guess), Move, the timeline and date search, Your week.

## Waiting on the founder (V1 §16)

- Veto any reversal in V1 §15, or let it stand.
- Commit: nothing is committed. The staged `art/blender/film-duo/` files are untouched and
  still staged; V1 F-41 says they move to branch `art/film-duo`, on the founder's word.
- Apple Developer Program enrolment (critical path for G5); the wave-1 testers (8 developers +
  3 people with no agents); a domain; making the repo public under MIT.
- Hand checks in the real app once P1–P5 land (gates G2, G4), and the Mission Control spike
  for "Hide from screen recordings" (V1-X8).

## Known gaps (not done, do not claim)

- A request still skips Pip whenever any terminal is frontmost (B2): that's P4 (`release` is
  ready for focus tracking).
- Codex sessions are not watched. Reminders still advance only on Done; snooze moves the series
  (F05): that's P2.
- A notebook's partial name still picks the most recently updated match (F06): that's P2.
- The window is still the old CSS (P5). Settings still has 8 categories, not 4 (P5).
- No signing, updater or uninstall (P6). The hooks are still HTTP on 47821 (P4).
- Clippy shows 6 older warnings; CI with `-D warnings` comes in P6.
