# Sam — keyboard and accessibility audit

25 October 2026 · UX research and accessibility seat · independent findings

Sidefolk has a useful accessibility foundation, particularly its native controls, named fields, focus styling, and readable color tokens. The main v1 obstacle is inconsistent keyboard continuity: a user can complete an action, then lose their place or receive no accessible confirmation. Fix those transitions before adding more keyboard shortcuts. A novice should be able to understand what happened without knowing the DOM; an experienced user should be able to repeat the same work without retracing the interface. These needs do not depend on age.

## Scope and limits

I worked in an isolated Chromium Playwright session at `http://127.0.0.1:1420/settings.html`, using the browser sample store. I first exercised reminders, evaluation notes, request review, saved actions and settings; only then inspected the relevant frontend. No native desktop capture, VoiceOver manipulation, live model calls, real permissions, global configuration changes or user-data changes occurred. The only data created was a sample evaluation note in this isolated browser session.

This is an engineering accessibility audit, not observed human research or a compliance finding. Screen-reader announcements are inferred from DOM semantics, not heard with VoiceOver. The previously green WebKit suite exercises the browser sample API; it does not establish macOS accessibility, native folder selection, operating-system notifications or session reopening. Those remain unknown.

## Observed task costs

Counts below exclude typing characters and count a key chord as one action. They describe the stated starting focus, not total discovery cost. Pointer setup used to establish a starting state is excluded, so these are comparable microflows rather than end-to-end benchmarks.

| Task and starting point | Observed path | Cost and result |
| --- | --- | --- |
| Open reminder sheet; Today heading focused | Tab, Enter | 0 clicks, 2 key actions. Opens Reminders underneath, focuses reminder text. Escape is one more action; returns to Reminders heading. |
| Tell a reminder; Tell field focused | Type “tomorrow at 9 check RT results”, Enter | 0 clicks, 1 submission key. Preview toast says it would go to the companion. No reminder was created; natural-language execution is unverified. |
| Add achievement; Evaluation notebook’s New note button focused | Enter, type achievement, Tab, Enter | 0 clicks, 3 key actions. New note focuses capture field; saved entry appears with today’s date. No success status is added. |
| Review attention; Today heading focused | Tab twice, Enter; then Tab five times, Enter | 0 clicks, 10 key actions to Allow once. The second phase passes Copy command, Copy working folder, Technical details, Decline, Allow once. Sample decision succeeds. |
| Run saved action; Actions heading focused | Tab twice, Enter | 0 clicks, 3 key actions. Sample toast reports completion and explicitly says nothing ran. |
| Select Light; Appearance heading focused, System selected | Tab, ArrowRight | 0 clicks, 2 key actions. Light becomes checked, save is reported, focus remains on Light. |
| Enable larger text; Accessibility heading focused | Tab twice, Space | 0 clicks, 3 key actions. Larger text becomes checked; body text changes from 16 to 18 CSS pixels. |

These short paths are promising. Notebook entry is particularly efficient once the user reaches New note. However, reaching it after opening a notebook is less predictable because focus is lost during that route transition.

## Findings and priorities

**P1 — Complete asynchronous note navigation with deliberate focus.** From Notes, I opened Evaluation H2 2026. After loading, `document.activeElement` was BODY. The next Tab landed on the Notes navigation button, not the notebook heading or New note. The notebook exists visually, but the keyboard user is still navigating from the old location. `renderNotes` returns an empty view while `notebook()` awaits data; the central router attempts to focus its heading before that heading exists. See [notes.ts](../../src/dashboard/notes.ts#L30) and [app.ts](../../src/dashboard/app.ts#L240). Focus the destination heading once loading completes; provide an intelligible loading/error state without silently moving focus again during background refresh. This follows the goal of a meaningful navigation sequence in [W3C’s Focus Order guidance](https://www.w3.org/WAI/WCAG22/Understanding/focus-order.html).

**P1 — Announce successful note capture.** I added “Delivered RT results and documented next steps.” The dated entry appeared, the textarea cleared, and focus stayed on Add note, but the global status region remained empty and the entries region has no live semantics. A user who cannot see the inserted row receives no confirmation that their achievement was stored. [notes.ts](../../src/dashboard/notes.ts#L185) clears and refreshes without posting success. Add a concise status such as “Note added to Evaluation H2 2026, October 25.” Keep focus ready for the next note. An explicit success message should be programmatically exposed without requiring focus, as described in [W3C’s Status Messages guidance](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html). Actual announcement wording and timing need VoiceOver validation.

**P1 — Keep a usable focus destination after a request decision.** Starting at Review request, I tabbed to Allow once and pressed Enter. The inline result said “Allowed once. Sent to Codex.” with `role=status`, which is good. However, the focused action disappeared and activeElement became BODY. The replacement includes Back to requests, but focus does not reach it automatically. Preserve continuity by focusing the result’s next available action, or another stable destination that does not imply a second approval. Test sending, failure/retry, expiry and “already answered elsewhere” separately. The sample success does not verify real transport. Source: [requests.ts](../../src/dashboard/requests.ts#L134).

**P2 — Preserve the selected reminder filter and explain empty results.** With Reminders heading focused, Tab three times and Enter selects Repeating. I observed BODY focus afterward; the next Tab goes back to Add reminder. The selected button is accurately `aria-pressed=true`, but the empty message “Repeating reminders will appear here” is not a status. Retain focus on Repeating and announce the result count or empty result. [reminders.ts](../../src/dashboard/reminders.ts#L110) currently redraws the whole page. These are toggle buttons in a named group, not radios; do not advertise arrow-key behavior unless implemented. The theme picker correctly uses actual radios. [W3C’s radio pattern](https://www.w3.org/WAI/ARIA/apg/patterns/radio/) gives the expected Tab/arrow behavior for that separate widget.

**P2 — Make recovery actions durable enough to reach.** The shared toast removes ordinary messages after 4.5 seconds and messages containing Undo or Show output after nine seconds, with no focus/hover pause evident in [app.ts](../../src/dashboard/app.ts#L117). With a longer reminder or note list, keyboard traversal can consume that window. This is a source-backed risk, not a reproduced timeout failure in a long populated list. Keep important recovery reachable in the page, or pause dismissal while interacting and verify reachability with realistic list lengths. Error toasts share a polite status region; urgent failures may need more durable inline placement rather than merely increasing announcement urgency.

**P2 — Clarify the modal return destination from Today.** Add reminder opens a different underlying page. Escape returns to Reminders heading rather than Today’s original Add reminder action. The native sheet implements a reasonable fallback when its invoker has been removed, but this is a context change inside a seemingly simple modal. Prefer returning to a stable relevant invoker, or make the navigation understandable. Within the sheet, fields have associated labels, Escape closes it, and date/time validation uses described alert regions. Submitting without date/time produced “Choose a date and a time.” Focus stayed on Save reminder; moving to the first invalid field would make correction faster. I did not detect a route into the background while the modal was open.

## Readability, targets and states

At 600×700 with Larger text enabled, Settings changed its sidebar to a named category select, text wrapped, and the document had no horizontal overflow. The captured view shows a visible focus ring on Larger text; more content continues vertically. See [browser evidence](../../output/audit-2026-10-25/sam-accessibility-large-600.png). This is one narrow viewport, not a complete zoom/reflow test. Larger text scales body text to 18px and metadata to 14px; it is not a substitute for testing 200% resizing.

Calculated solid-token contrast is encouraging: ink/surface 14.00:1 light and 13.31:1 dark; muted/surface 5.52:1 light and 8.34:1 dark; light error/surface 8.55:1. These exceed the ordinary-text reference in [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), but are not a full composited-screen audit. Measured narrow Settings inputs/buttons were 44px high; switches were 48×28px. Do not report every target as 44×44. Larger clickable label rows would improve comfort without requiring precise switch aiming.

Theme saving disables its radios, reports Saving, rolls back after failure and restores radio focus in source. Reminder save guards duplicate submission and provides inline errors. Empty reminder text is specific. Request expiry disables choices and supplies status markup. These are good patterns; slow/error/expired behavior needs deterministic injected sample scenarios and native validation. I did not force real network failure or an expired permission to manufacture evidence.

## v1 acceptance script

1. On macOS with keyboard navigation enabled, open Notes and a notebook. The destination heading is announced once; Tab reaches its relevant next control. Repeat with delayed loading and a missing notebook.
2. Enter two dated achievements using New note. Confirm each save once, retain the second draft during incoming updates, and announce success/failure without losing text. Edit, cancel and delete; focus stays near the edited row and Undo remains reachable.
3. From Today, open/cancel/save a reminder. Tab and Shift-Tab remain within the modal; Escape has a predictable return; invalid fields identify the correction. Complete tomorrow at 09:00 and verify the native scheduled result separately.
4. Change all reminder filters repeatedly using keyboard only. Selection retains focus; populated and empty results are understandable without sight.
5. Review a request; exercise sending, retry, expiry and success with deterministic fixtures. No default Enter approval occurs; every replacement has a useful focus destination and announced result. Hand-check reopening the actual originating session.
6. Run theme radios with Tab/arrows/Space in both directions. Test persistence, save failure, larger text, reduced motion, 200% text resize and narrow layouts. Then have actual keyboard and VoiceOver users complete these tasks. Record findings; do not substitute this memo or a green WebKit run for that validation.
