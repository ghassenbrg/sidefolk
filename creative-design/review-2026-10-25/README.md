# Sidefolk — the workday desk

25 October 2026 · Complete UI/UX design proposal and developer handoff.

**Recommendation:** keep the Sidefolk name, Pip Signal logo, Pip and Spark. Rebuild the application’s visual hierarchy around a useful day: what needs you, what is next, and what is worth keeping. The brand has an identity; the application needs to express it through daily use.

This package contains **34 designed image boards**, **5 native-size image references**, an editable HTML/CSS/JS prototype, a component system, interaction specifications, the asset inventory, and a developer implementation map. The screens are rendered design mockups with illustrative data, not captures of the running desktop app. The live application was not changed.

## Open and explore

[Open the local gallery and prototype](http://127.0.0.1:4178/creative-design/review-2026-10-25/index.html). The review server is local to this Mac.

To reopen after the server stops, run this from the repository root:

```sh
python3 -m http.server 4178 --bind 127.0.0.1
```

Then use the gallery link above. The prototype uses ES modules, so serve it over local HTTP rather than opening `index.html` as a file. It needs no account, API key, font download or native integration. Every example is local, nonpersistent and reset on reload.

- [Developer handoff](HANDOFF.md): the final design decisions, layout/component rules, behavior tables and implementation sequence.
- [Asset inventory](ASSETS.md) and [machine-readable manifest](assets/manifest.json).
- [Image index](screens.json): exact filenames, dimensions, theme and scenario.
- [Verification results](VERIFICATION.md) and [raw checks](verification.json).
- Editable masters: [HTML](index.html), [CSS](design.css), [screen and interaction source](design.js).

## The design decision

The app should feel like a small, personal work surface rather than a collection of settings panels. Three deliberate visual forms make that happen:

1. **An attention surface** for the thing asking for a decision. Soft mint, one clear next action, real project identity.
2. **A time-led agenda** for reminders. Dates, readable rows and quiet hairlines, with actions kept close to the relevant reminder.
3. **A dated notebook** for the work log. Actual writing, meaningful timestamps, a light notebook index and capture that opens when needed.

Pip has a purpose in the design: greeting, holding a reminder, carrying a question, keeping a note. The actual selected clay companion appears when it speaks. The company glyph stays the company identity. Quiet days are pleasant without fabricated activity, charts, streaks, a chat feed or a larger mascot banner.

The existing cream, charcoal and mint palette already works. This proposal gives it stronger composition, consistent density and a warm dark counterpart. It introduces no new feature scope.

## Image boards

| # | Design | What it establishes |
|---|---|---|
| 01 | [Direction cover](images/01-cover.png) | The tactile, quiet brand atmosphere; presentation art only |
| 02 | [Today](images/02-today.png) | Overdue → Needs you → today’s reminders; sessions and recent writing support them |
| 03 | [Everyday Today](images/03-calm.png) | A complete experience without connected AI tools |
| 04 | [Reminders](images/04-reminders.png) | List hierarchy, due times, recurrence and two visible row actions |
| 05 | [Reminder editor](images/05-reminder-edit.png) | Edit, resolved time, zone, snooze and history |
| 06 | [Work log](images/06-work-log.png) | Notebook index, readable dated entries and compact capture |
| 07 | [Your week](images/07-week.png) | A factual record, with Markdown copy |
| 08 | [Sessions](images/08-sessions.png) | Project, first prompt, host and deliberate Log it |
| 09 | [Command review](images/09-request.png) | Exact operation, identity and explicit decisions |
| 10 | [Edit review](images/10-request-diff.png) | A complete before/after change |
| 11 | [Setup: first reminder](images/11-setup.png) | Useful value before configuration |
| 12 | [Setup: permissions](images/12-setup-notifications.png) | Honest results and denied-notification recovery |
| 13 | [Setup: waiting for a live event](images/13-setup-tools.png) | Installed and working are separate states |
| 14 | [General settings](images/14-settings.png) | A focused, separate preferences window |
| 15 | [Companion settings](images/15-companion.png) | Pip and Spark, with stable capabilities |
| 16 | [Agents settings](images/16-agents.png) | Health, host behavior and Codex beta |
| 17 | [Privacy & data](images/17-privacy.png) | Local storage, retention, export and uninstall |
| 18 | [Desktop moments: Pip](images/18-desktop.png) | Reminders, complete requests, capture and menu access |
| 19 | [Design system](images/19-components.png) | Palette, type, density, controls and status vocabulary |
| 20 | [Recovery states](images/20-states.png) | Empty/loading/error/stale/late/released/repair |
| 21 | [Quick add: note](images/21-quick-add.png) | A visible destination before capture |
| 22 | [Today: dark](images/22-today-dark.png) | Same hierarchy and readable warm dark layers |
| 23 | [Settings: dark](images/23-settings-dark.png) | Dark controls and appearance selection |
| 24 | [Compact Today](images/24-narrow.png) | Reflowed navigation and priority order |
| 25 | [Repeating reminder](images/25-repeat-editor.png) | Series anchor and occurrence/future edit scope |
| 26 | [Quick add: reminder](images/26-quick-reminder.png) | Date, time, zone and save interpretation |
| 27 | [Quick add: ambiguous hour](images/27-quick-ambiguity.png) | Explicit choices before saving |
| 28 | [Quick add: notebook choice](images/28-notebook-choice.png) | Exact-or-ask destination matching |
| 29 | [Released request](images/29-request-released.png) | No answer controls after handoff |
| 30 | [Long operation](images/30-request-long.png) | Read-complete gate, with the raw content available |
| 31 | [Desktop moments: Spark](images/31-desktop-spark.png) | Same interaction system with the alternative companion |
| 32 | [Control states](images/32-control-states.png) | Hover, focus, disabled, pending, validation and durable Undo |
| 33 | [New reminder](images/33-new-reminder.png) | A blank title with populated schedule fields |
| 34 | [Setup: connection choice](images/34-setup-disconnected.png) | Optional connection before installation |

The presentation boards are 1440 × 1000, except the compact board at 720 × 1200. The actual layout also has [native 1100 × 760](images/native/today-1100x760.png) and [minimum 640 × 480](images/native/today-640x480.png) references, plus equivalent Work log references in `images/native/`.

## What the prototype demonstrates

Navigation, light/dark appearance, Pip/Spark selection, reminder filters, new/edit fields, note drafting with notebook filtering, local completion feedback, Quick add dialogs, ambiguous-hour choice, notebook destination choice, a short request outcome and an unread-long-operation gate. Dialogs are native HTML dialogs; Escape closes them. ⌘K opens Quick add and ⌘, opens the settings design.

The preview parser intentionally understands only the fixture phrases needed for the walkthrough. It is **not application logic**. Real persistence, recurrence calculation, clipboard/export, undo reversal, live agent transport, installer changes, native focus and notification delivery remain disconnected. Illustrative “saved” messages say Demo only. Use the existing shared parser and Rust lifecycle in production.

## Team and review

Three specialist sub-agents worked with the lead designer:

- Product/interaction: [UX specification](team/UX.md).
- Visual identity/system: [visual specification](team/VISUAL.md).
- Accessibility/implementation: [QA and implementation plan](team/QA.md).

Their [QA review](team/REVIEW.md), [visual critique](team/VISUAL-REVIEW.md) and [final interaction review](team/FINAL-UX-REVIEW.md) are retained as the review record. **The final HANDOFF and VERIFICATION files govern where a historical review describes an issue fixed afterward.**

The founder’s brief authorizes this design exploration. It does not make the earlier release plan or its gates passed. Two deliberate proposal changes are recorded in HANDOFF: the new composition supersedes the old screen references if selected, and the compact window scale is explicitly 13 CSS px rather than the literal 13 CSS pt conversion. Pip/Spark, the logo, palette, feature inventory and request policy are retained. No commits were made.
