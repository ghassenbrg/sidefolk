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

- **P0 Reset and P1 Foundation are committed** (`5e411dc`, `91327a5`); the details are in
  [LOG.md](LOG.md):
  - deleted features
  - store.rs data safety
  - `$`-only commands
  - requests in Rust, with Codex's review fixes
  - no polling, single instance
  - Pip and Spark
- Release build 5.03 MiB at P2; not relaunched on the user's Mac.

## P2 Reminders & work log (25 October, Claude Code): built, verified in WebKit

- **Series engine in Rust** (`series.rs`, `reminders.rs`; DECISIONS #43):
  - The anchor and occurrence are separate, and a snooze moves only `due`.
  - Done and Skip move to the next occurrence counted from the anchor.
  - A 20 s tick records missed occurrences and keeps the latest.
  - DST in Paris and New York, month ends and weekdays are tested.
- **Notifications:** macOS holds up to 60 (`queue`): every one-off, then each series' next
  occurrences in turn. Clicking one opens that reminder.
- **Answers:** the overlay card adds "This evening" before 17:00 and "Skip this one" for
  repeats. The window's Snooze and Mark complete go through `answer_reminder`, and the detail
  view has Skip.
- **Overdue and away:** after a quit or sleep, late reminders are gathered on one "While you
  were away" card. Today labels overdue reminders.
- **Work log:**
  - "note: …" and "log …" go to Log; `matchNotebook` is exact-or-ask.
  - "Noted in X" has Undo and Move, and stays until it's closed.
  - `move_note` in Rust.
  - Notes page: Log first, the "All entries" timeline by week with a notebook filter, and
    date-aware search (`matchesNote`). Move on every entry.
  - The sidebar and menu say "Work log".
- **Your week:** a view (route `week`) and a Friday 16:00 card (setting `your_week`, default
  on).
- **Log it:** a finished session's card stores the project and the first prompt line in Log.
- **Verified:** typecheck, 80 Vitest, 53 Rust, WebKit (Log capture, exact-or-ask, timeline
  search, Your week, renamed accessible buttons). Not hand-checked: real notifications after
  quit or sleep, and DST on a real Mac (G2-core).

## Next step (exact)

**P3 Quick add** (V1 §6, §14):
1. The 300-phrase corpus as a Vitest table: 150 everyday, 100 developer, 50 adversarial, on a
   fixed clock in Europe/Paris and Asia/Tokyo across DST. Gates: ≥95% correct, 100% no shell
   without `$`, 0 silently wrong times.
2. The choice UI for an ambiguous bare hour (`Parsed.alternative`: "3 PM today · 3 AM
   tomorrow") on the companion and in the window.
3. Same-surface finishing: the window's Quick add must finish reminders and notes in the window
   (today it hands them to the companion, `dashboard/tell.ts`; Codex F07).
4. About 20 small-talk replies in Pip's voice; compound weekday lists ("Monday and Thursday").

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
- Codex sessions are not watched (P4 spike).
- The window is still the old CSS (P5). Settings still has 8 categories, not 4 (P5).
- No signing, updater or uninstall (P6). The hooks are still HTTP on 47821 (P4).
- Clippy shows 6 older warnings; CI with `-D warnings` comes in P6.

## Design handoff (25 Oct, Codex; founder requested a UI/UX team)

- New proposal: `creative-design/review-2026-10-25/` — 34 WebKit-rendered boards, 5 native-size
  references, editable local prototype, HANDOFF.md, component/behavior specs and asset manifest.
- Keep Pip Signal/Pip/Spark/palette; new Today/agenda/notebook composition, separate Settings.
  Scoped 13 CSS px window type is an explicit proposal versus V1's 13 pt; no gate passed.
- Verified: 34 exports, 48 native-size/theme combinations, 10 focused prototype scenarios.
  Domain/native services are disconnected. No production source edits or commits by this task.
- Handoff: read the package README/HANDOFF for P5; current P2 backend priority is unchanged.
