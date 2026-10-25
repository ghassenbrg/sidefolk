# Final UX handoff review

25 October 2026 · Product/interaction seat

Reviewed the amended `design.js` and `design.css`, the earlier `team/REVIEW.md`,
`team/QA.md`, `team/VISUAL-REVIEW.md`, and rendered frames 25, 30 and 33. These are
design artifacts, not native desktop observations or release-gate checks.

## Judgment

Keep the direction. The amended package now separates creation from editing, shows a real
recurring reminder, distinguishes All entries from notebook filtering, exposes explicit
ambiguity/destination choices and covers the important long/released request states. No further
visual concept work or additional product scope is needed before handoff.

Keep **Overdue → Needs you → Today's reminders → Running sessions → Recent log**. The earlier
visual suggestion to put requests before Overdue is rejected because V1-R15 is the binding
order. Attention can retain its stronger surface while remaining second in that order.

## Remaining high-value needs

| Priority | Need | Minimum resolution |
|---|---|---|
| Before delivery | **Quick add's confirmation contradicts the chosen preview.** In `quickModal()`, Save still chooses a generic tomorrow-09:00/Log toast from the input string. Choosing 15:00 today or Evaluation H2 therefore produces a different claimed result. | Retain the chosen resolved label/destination in the local demo and use it in confirmation; or use the neutral confirmation “Demo preview confirmed” with no false saved date/destination. The illustrative parser must be explicitly excluded from production reuse. |
| In the final handoff | **The desktop type scale needs one deliberate interpretation.** The proposal uses 13 CSS px; V1-U7 says 13 pt. The older token file uses a different body scale again. | Document 13 CSS px as a proposed compact-window scale change, with 12 px metadata and the corresponding larger-text scale, requiring a recorded contract update when accepted. Alternatively comply literally with 13 pt. Do not leave the developer to silently resolve this mismatch. Never shrink overlay targets to match window density. |
| In the final handoff and layout verification | **The reference compact render is not the native minimum-size proof.** At the compact breakpoint, reminder details stack below the entire list. Entering create/edit can appear to do nothing until a long scroll. | At 640 × 480, opening a reminder editor must show/focus its title/first field immediately, using a real sheet or deliberate scroll-to-editor. Record layout inspection of Today, editor, request review, setup and Settings at the native minimum and 1100 × 760. A 720 px gallery frame is a different check. Keep native behavior explicitly unverified. |
| In the final handoff | **Recurrence dropdown labels alone do not tell the developer which controls to build.** Frame 25 shows the selected Sunday weekly case and occurrence scope, but not the other supported rule inputs. | Link the canonical reminder behavior table in `team/UX.md`: weekday multi-select; N=1–52 with day/week unit; monthly date with last-day fallback; yearly; This one vs All future; Pick… snooze with a visible zone; snooze never changing the series anchor. These can be written component states instead of more full-page images. |
| In the final handoff | **A readable short request and unread long request do not fully specify lifecycle transitions.** Frame 30 intentionally never adds Allow when scrolled; this must not be copied as the implemented lifecycle. | Point the developer to one authoritative state table: pending unread → complete display while still live → sending → confirmed outcome, plus released/expired, cannot-display (>50,000 chars) and failed/unknown delivery. `requests.rs` remains authority. Never derive “complete operation shown” from a decorative static pill; never re-enable Allow after release. |

The last four items are specification/verification closure, not reasons to expand the design or
start production implementation during this task. Existing detailed requirements are already
in `team/UX.md` and `team/QA.md`; the package index should link them as authoritative behavior
guidance so an engineer cannot mistake `design.js` for application logic.

## Prototype boundary to state once

The local prototype demonstrates navigation, selections and visual feedback. Actual store
writes, undo reversal, clipboard/export, repeat computation, notifications, installers,
permission routing, code-display gates and native focus are deliberately disconnected.
Prototype toasts are not evidence of persistence. Production uses the existing shared parsers,
Rust state and installer confirmations. No global agent config is changed by this package.

Preserve native text-field Undo, draft retention through rerenders, focus restoration after
sheets and deletes, and item-specific button labels during implementation. These have already
been specified; the final package should not claim they were verified by rendered images.

This review approves no V1 gate and creates no new scope.
