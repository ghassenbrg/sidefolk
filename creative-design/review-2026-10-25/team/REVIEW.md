# Prototype review

Reviewed 25 October 2026 from `index.html`, `design.js`, `design.css`, asset icons, and exported design renders 02, 05, 06, 09, 13, 18, 19 and 24. These are browser-rendered design artifacts, not captures of the user's desktop or proof of native behavior.

## Overall judgment

The direction fixes the major hierarchy problem: daily work has a quiet agenda, attention has one distinct decision surface, and the log shows actual writing rather than notebook containers. The shipped identity feels integrated. Keep this direction. The strongest remaining improvements concern truthful state examples, complete visible cards and a few overloaded affordances; adding visual ornament would not improve them.

## Fix before delivery

| Priority | Finding and evidence | Specific fix |
|---|---|---|
| 1 | **Clipped permission card.** In `18-desktop.png`, the upper-right bubble starts above its scene, losing the top edge and obscuring the scene caption. The bottom-aligned `.bubble-scene` does not accommodate its tallest card inside a 400 px cell. | Increase this board/cell height or reduce spacing and align the entire card within the scene. Preserve 44 px card actions. Rerender and inspect the full bubble including its top border and caption. |
| 1 | **A one-off reminder shows repeat-only controls.** In `05-reminder-edit.png`, Repeat is Does not repeat, yet the panel offers Skip next and says the next repeat keeps its schedule. | Hide Skip next and repeat-specific copy for one-offs. Alternatively select the repeating Call Mum fixture and reflect its actual title/date/time/repeat. Keep a separate one-off editor example. |
| 1 | **Notebook destination and contents disagree.** In `06-work-log.png`, Log is selected but the stream includes Sidefolk and Ideas entries, with a global count of 3. | Start with All entries selected, or filter the fixture by the selected notebook and update count. Every notebook selection should produce the matching visible entries. |
| 1 | **Setup offers Connect after saying installed/connected.** `13-setup-tools.png` says Connected and waiting for the first session above a primary Connect Claude Code button. | Supply mutually exclusive Not connected / Installed, waiting / Verified states. Waiting can offer Open Claude Code and a non-primary connection review. Continue can remain available but must not pretend an event was observed. |
| 2 | **Overflow looks like messaging.** Reminder rows and log entries use `icon('requests')`, a speech bubble, for More actions. The shape strongly suggests comments or a question. | Add one ellipsis glyph to the shared icon map and use it consistently for overflow. Keep accessible item-specific labels. |
| 2 | **Work log rows exceed the two-action design rule.** `noteEntry()` renders Edit, Move and More, while the handoff's own component statement says two actions at most. | Keep Edit plus ellipsis, with Move/Delete in the menu; or Move plus ellipsis with Edit/Delete inside. Use one rule on every entry. |
| 2 | **All projects filter wraps into an odd two-line badge.** `06-work-log.png` places All/projects beside a wide search field. It reads like static metadata and wastes the right edge. | Make this a real popup button with a chevron, `white-space:nowrap` and `flex:none`; allow the search field `min-width:0`. In compact layouts it may wrap below search deliberately. |
| 2 | **New reminder reuses an existing edit fixture.** Add reminder navigates to `reminder-edit`, prefilled Review launch notes and Save changes. | Add a distinct create mode with a blank title, actual default date/time, Add reminder heading and Save reminder action. Reusing the panel geometry is fine; distinguish intent and copy. |

## Handoff gaps to resolve in specification or extra states

1. **Small window proof.** Render 24 is 720 px wide with a 1000 px presentation window; it is useful evidence of the compact navigation but not proof of the native 640 × 480 minimum. Source has `?native=1`; inspect Today, reminder editor, request review, settings and setup at 640 × 480 and 1100 × 760. In particular, the compact reminder editor is placed below the entire list; opening it should focus/scroll the editor immediately, or use a true sheet so the user doesn't think nothing happened.
2. **Long request proof.** The short command and two-line diff are clear. Add a long unread operation state with disabled Allow and a readable explanation; a read-complete state; and an unavailable full-operation state with terminal handoff only. `Complete operation shown` must derive from complete display, not a static reassuring pill. Expired/released/sending/failed visuals should retain identity and raw content.
3. **Request product copy.** The lower callout on render 09 says what a longer operation must do. That is valuable implementation guidance but unnecessary in the normal short-operation user flow. Put it in the written handoff. Show contextual read-to-end guidance only when the current operation needs it.
4. **Recurring editor.** The single Repeat dropdown does not specify weekday multi-select, every-N interval, monthly invalid-date handling, and this-occurrence/future-series scope. The developer needs component states and exact field behavior, even if the primary image remains uncluttered.
5. **Component states.** Render 19 shows default controls and vocabulary well. Add a compact specimen row for keyboard focus, disabled-with-reason, pending save, invalid field and saved/Undo. State examples in render 20 are good but don't cover control-level changes.
6. **Type units.** The proposal sets `--app-body:13px`; V1-U7 says 13 pt. CSS pixels and print points are not equal. Record a deliberate interpretation/update so a developer does not silently choose between 13 px and 17.33 px. Pair the chosen desktop scale with a tested large-text variant.
7. **Companion identity.** Pip's alert portrait is very small on attention/review. This is not a failure: the identity lives in the sidebar and the text is primary. Do not enlarge it at the expense of operation content. Show the same card with Spark and use the user's current look consistently where Pip is speaking.

## Prototype limitations: acceptable if explicit

The prototype properly labels local sample data and demo-only actions. Native services, permission installers, actual notifications, clipboard/export, host routing and data persistence can remain disconnected. Do not turn this review into app implementation.

Several local interactions can mislead a developer copying the source, so the handoff should call them out or correct them cheaply:

- `updateQuick()` recognizes “at 3” as ambiguous, but supplies no choice controls; clicking Choose a time closes the draft and reports a saved reminder for tomorrow 09:00. Either disable save until a choice or show actual inline choices. This illustrates a core flow, not an optional polish detail.
- Input beginning “remind … at 3” enters the broad `/tomorrow|remind/` branch first, so the ambiguity branch never runs. Production must use `commands.ts`/`when.ts`, not this illustrative regex.
- A `note for X` input falls through to Log in the prototype. The production preview must resolve exact/alias destinations or ask, preserving the draft.
- Quick add's native dialog does not record/restore its trigger. Notebook switching rerenders the entire app and discards a half-written note. Production must preserve drafts and focus across all live changes.
- Global ⌘Z consumes Undo whenever a toast exists, including while a text field has focus. Production must preserve native text editing Undo and scope mutation undo deliberately.
- Local Undo toasts report success without actually reversing the changed note/completion state. Marked demo behavior is acceptable for a visual prototype, but must not become an acceptance example for implementation.
- Overflow, date search, project filtering, notebook move and repeat controls are visual stubs. The handoff needs their data contract and edge-state mapping, not an impression that they are working.

## Preserve

- Clear separation between the calm day and connected day.
- Existing cream/mint palette and warm dark counterpart, with operational state words and glyphs.
- Compact window controls versus 44 px overlay controls.
- Reminder times and notebook destinations visible before saving.
- Explicit request actions, exact operation space, project/host context and terminal escape path.
- Local files, native permission honesty, and visible demo/proposal labeling.

This review does not approve any V1 gate or certify accessibility. The supplied design direction is coherent; the issues above make its examples and developer contract more reliable.
