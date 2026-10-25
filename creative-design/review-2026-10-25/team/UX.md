# Sidefolk: product and interaction specification

Design study · 25 October 2026 · Product/interaction seat

This is an implementation handoff, not a claim that the proposed application has shipped or
passed a release gate. It preserves the functionality and safety semantics in `docs/V1.md`.
The founder's current request authorizes a new visual direction. Nothing here changes production
code, adds a feature, grants an approval, or changes the logo or either companion's identity.

## The decision

Sidefolk should feel like a **small work desk**, with Pip keeping the things you meant to come
back to. The window has three jobs: see what needs attention, keep a promise, remember the work.
Sessions supports those jobs once connected. Settings supports the application from its own
window. This provides identity through composition, rhythm, language and tangible character
moments rather than adding a dashboard of statistics or decorative empty cards.

Keep the existing Pip Signal logo and the clay companions. Their recognizability is already
stronger than the current window. Use Pip or Spark where the companion actually speaks; use
the mark to sign the application. The companion appears in the sidebar and setup, with one
deliberate moment on an empty or successful state. It is not repeated next to every piece of
ordinary UI text. Personality should never reduce the clarity of a request.

## What the current source gets wrong

| Evidence | User effect | Redesign response |
|---|---|---|
| `src/dashboard/home.ts` uses the same bordered-card treatment for most content | The window resembles a collection of settings panels | Flat dated rows for ordinary content; one differentiated attention surface; open space around the day heading |
| Today begins with `Needs you`, then `Coming up`, including overdue items mixed with future ones | Urgent promises can be read as ordinary upcoming work | Explicit Overdue section before Needs you, then Today's reminders (V1-R15) |
| Recent notes shows notebooks and their counts, rather than actual entries | Users cannot recognize the work they recorded | Recent log shows the last entries themselves, each with its date and notebook |
| Navigation says `Notes`; Settings is a primary view | Product activity competes with configuration | Work log is first-class; Settings is a separate four-pane window opened with ⌘, |
| Reminder rows show Open, Snooze, Edit, Delete, Mark complete | Lists feel like forms and require scanning repeated verbs | Maximum two visible actions; detail and overflow carry the rest |
| `tell.ts` says Tell Pip and clears input before the outcome | It resembles a chat prompt and hides the pending draft | Quick add, explicit intent/date/destination preview, draft retained until saved |
| `app.ts` dismisses an action toast after nine seconds | Undo can disappear before it is found | Persistent Undo with close affordance and ⌘Z (V1-U8) |
| Setup's tool page includes Codex and connection claims without waiting for a live first event | Installed and functioning become indistinguishable | Claude Code first; Connecting → waiting for first event → real event verified |
| `sessions.ts` offers Codex in New session and a broad auto-mode switch | UI suggests capability beyond the v1 start-session contract | Labs start-session is Claude Code only, with a prompt and its named permission modes |

This is a code audit, not a native app observation. No desktop capture or native hand-check was
performed. The older design-system document includes historical examples that contradict v1
(Codex Allow, Den, multiple art families); `docs/V1.md` takes precedence.

## Information architecture

Main window, one sidebar level:

1. **Today** — the default destination; date, overdue reminders, requests, today's reminders,
   running sessions, recent log.
2. **Sessions** — inserted after Today once Claude Code is connected. No empty disabled item
   before connection. If only an explicitly enabled Codex beta integration exists, the session
   surface must name that narrower capability and stay Beta; it may not claim Claude approvals.
3. **Reminders** — upcoming and repeating reminders; completed history; list/detail.
4. **Work log** — All entries, Log inbox and topic notebooks inside a list/detail layout.

Sidebar footer: selected companion with accessible name/state, Quiet, and a Settings button.
Settings opens the separate window; the footer position makes it findable without making it
another work destination. Brand and window drag region remain apart from clickable controls.

No Home/Today duplicate, Activity page, Requests destination, Tasks page, Calendar tab, dashboard
analytics, crew Den, embedded terminal, or chat transcript. Requests are a focused view reached
from Today, a session or the companion. Your week is a view within Work log. All entries is a
view inside Work log, not a new global navigation item.

When someone skipped AI tools, Today has only the everyday sections and the sidebar has the
three everyday destinations. No connecting-agent promotion, terminal example or AI status
occupies this path. Optional tool configuration remains deliberately accessible in Settings.

## Window model and hierarchy

**Primary hierarchy:** where am I → what needs me → what I can do → supporting context.

The day heading has a large, readable date and the title Today; the quick capture control sits
within reach in the common toolbar. Reuse this toolbar location on every work view. A user
should not have to open Today before recording something.

Use the canvas as the large background, surface for the main work area and sheets, hairline
dividers for ordinary rows, and the existing mint treatment for selection. Preserve the shared
token and status vocabulary. Do not equate mint with the safety of an agent operation.

No metric tiles for number of sessions, number of notes, streaks, saved time, or productivity.
Useful counts belong beside the item they count (2 overdue; 3 requests), never as the main
purpose of the screen. A quiet day should still look intentional, not look like missing data.

At narrower window widths, support content follows the primary stream in the same semantic
order. List/detail collapses to list → detail with a named back action; filters become a popup.
No essential action requires a horizontal scrollbar. The first implementation should prefer
one readable content stream over cramming every section above the fold.

## Today

The semantic and visual order is always Overdue → Needs you → Today's reminders → Running
sessions → Recent log (V1-R15). A support column may hold later sections only if keyboard and
screen-reader order remain the same and a tall request does not strand a later section above
an earlier one. Do not use a visually misleading masonry layout.

| Section | Content and visible actions | Detail |
|---|---|---|
| Overdue | Reminder title, original date/time, Overdue word; Done and Snooze | Full reminder details, history, series edits |
| Needs you | Project, first prompt line, host, real status word, exact short operation when available; Review and Open | Full request review, never approval by row selection |
| Today's reminders | Time as a quiet left anchor; reminder title; repeat rule when present; Done and overflow | One-click row detail; Snooze and Edit remain discoverable in overflow/detail |
| Running sessions | Project, first prompt line, host, Working/Needs you; Open and overflow | Session list/detail; no terminal output |
| Recent log | Entry excerpt, notebook and date; row opens entry | Recent entries themselves, not notebook counts |

The section heading includes a count only when useful. Avoid rendering a different empty card
for every section. With no overdue items or requests, omit those sections; say once, "Nothing
needs you right now." A quiet day shows upcoming reminders and the latest recorded work. If
there is no data at all, offer Add reminder and Add note as the two clear starting actions.

New incoming requests update a count and an obvious surface without stealing focus or moving
the row the user is operating. Preserve row keys and scroll position. Once an interaction ends,
the stable section order can reconcile. An open permission review always retains that request's
identity even if another request arrives.

Recovery notices sit before the ordinary day content because data trust comes first. They are
not productivity items and do not appear as ordinary overdue rows. A disconnected integration
notice appears only if that integration was connected. Its inline Repair action opens the exact
relevant settings pane; it does not become a recurring promotion.

## Reminders

### List

Header: Reminders with Add reminder. Compact segmented filter: Upcoming / Repeating /
Completed. The upcoming list is grouped Overdue, Today, Tomorrow, then locale-formatted dates.
Repeating displays series, with a legible repeat description and the next occurrence. Completed
shows the actual completion and scheduled dates in detail. The source's five-item completed cap
is not a history design: if history must load in pages, use an explicit More action.

Ordinary row: due time/date, title, optional project/source and repeat cue. Visible actions: Done
and overflow. When a reminder is currently firing or overdue, Snooze can replace the overflow
as the second action, with detail still reached from the title/row. Never put a destructive
action permanently beside Done.

### Details

Read mode: title; resolved date/time and zone; one-off or repeat rule; project/source if any;
occurrence status; history. Primary action Done for the current occurrence. Secondary action
Snooze. Overflow: Edit, Skip next (series), Delete. Show the original scheduled time and new
snoozed time together, rather than rewriting history.

Recurring edits require the explicit scope choice This one / All future before saving. A
recurring deletion must likewise name the intended scope in its destructive action; implementation
must map only to backend-supported occurrence/series operations. Do not invent an unsupported
"delete this and all history" operation.

### Add/edit sheet

Order: reminder text → date and time with real values → time zone → Repeat → resolved summary
→ save. Default today, or tomorrow when the selected time has passed. Show "Reminders appear
on this Mac." Notification denial adds "Reminders show only while Sidefolk is running." Both
statements are honest scope information, not buried footnotes.

Resolved summary example: "Thursday, 29 October · 14:30 · Asia/Tokyo" (format follows locale).
The preview reuses the same resolved model as the eventual saved reminder. Save reminder is
disabled only for an actual invalid state and the reason appears beside the field. Do not use
an empty date placeholder as if it were a valid selected date.

Repeat presets map exactly to V1-R3: daily; weekdays; weekly on selected days; every N days or
weeks (1–52); monthly by date; yearly. Show a plain sentence before Save. A 31st-of-month
rule names its shorter-month behavior. Advanced controls appear only after choosing Repeat.

Snooze menu: 10 min / 1 hour / This evening (18:00) / Tomorrow 9:00 / Pick… . If this evening
has already passed, do not silently point it at an invented time: omit or explicitly disable it
with its reason. Pick… contains real date/time values. Confirmation says the new occurrence
time; for a repeat, include "The next Monday stays the same" when useful. The series anchor is
never modified by snooze.

### Delivery

One reminder firing means one chime and one card. After two minutes, fold into the companion's
held-note count; never mark it handled. Hidden companion peeks temporarily. Reopen to the same
reminder details. The macOS notification opens those same details, not a second editor.

On wake, the V1-R8 late-reminder recap shows one "While you were away: N reminders" card;
list original times and a late tag, latest occurrence per repeating series. This is the narrow
reminder recovery required in v1, distinct from the general v1.1 recap deferred in the roadmap.

## Work log

This is a place to remember what happened, not a filesystem browser or writing suite.

Initial state is All entries. Internal notebook rail: All entries, Log, the user's notebooks,
and New notebook. The main panel is a dated stream grouped by week with day labels; each
entry displays readable text, notebook and optional project. These are dated notes, not tasks
with checkboxes. Keep a direct Add note action at the header and Quick add in the common
toolbar.

Search field: "Search entries or dates". It supports literal text plus the dates promised in
V1-L6 (October, last week, 2026-04); resolve the date range visibly when a date query is used.
Notebook and project filters sit beside it. An empty filtered result says "No entries match"
and offers Clear filters. It never implies all notes were deleted.

Entry selection opens read/edit detail. Visible actions: Edit and overflow. Every entry offers
Move in overflow and its detail, with a destination picker. Move retains content, date, and
project. Export menu: Copy notebook as Markdown, Copy this week, Copy everything, Show in
Finder; show only the relevant actions in the current context. Copy failure leaves content
visible with Retry; successful copy names its scope.

Default capture (`note: …`, `log …`) saves to Log without a question. A named destination must
be exact or ask; never choose the most recently edited near-match. The chooser retains the
draft, offers exact notebook names, and includes New notebook “X” / Log where appropriate.
Before saving, label the destination. After saving: "Noted in Log · Move · Undo". The user can
reclassify without recreating the note.

Completed agent session: Log it opens an editable draft such as `sidefolk: simplify reminder
editing`, with the first prompt line only and the notebook shown. Nothing is logged without
Save. Do not promise an AI-generated completion summary.

Your week lives inside Work log, reached from its header/menu or the Friday 16:00 companion
offer. It is a plain dated list of that week's log entries and completed reminders, with Copy
as Markdown. Date range is visible and explicit. The reminder and note sections remain
distinguishable. There are no achievements, scorecards or generated claims about work.

## Sessions and request review

### Sessions

Group Needs you, Working, Recently finished; use the existing state word for each status.
Every row has project + first prompt line + host. A path is supplementary identification,
never a replacement for the project's name. Two similarly named projects show sufficient path
context to distinguish them. Permission mode is a read-only badge when known.

Live row actions: Open and overflow. Finished successful row: Continue and Log it. Continue
is only for an ended session; Open never starts a second copy of a live process. Failed rows
show a useful reason from the voice table and Open, without a fake success celebration.

For Terminal/iTerm, Open targets the exact supported tab. For other hosts, the UI says exactly
what the matrix promises: e.g. "Open Ghostty, then select the session there". tmux/ssh/unknown
offers Copy attach command with the tty visible; it never claims exact focus. Do not use a
single universal "Jump to exact session" claim.

Labs → Start session may expose New session, Claude Code only. Fields are Folder, Prompt,
and Claude's named permission mode. Show that it opens in the user's terminal. No Codex start,
embedded terminal, agent instruction textbox or per-session Sidefolk access switch.

### Permission review

Identity band: project → first prompt line → Claude Code + host. Then tool label, full exact
operation, working folder, and the plain waiting explanation. Optional session/request IDs
live under details. The operation remains visible while reading choices; don’t separate identity
from the action through multiple tabs or decorative hero sections.

Command display preserves whitespace and exposes control/bidi characters. Edit shows the real
diff, Write the full content, MCP the JSON. Long operations use an accessible scroll region;
Allow once appears only after the whole operation has been shown, under the actual backend
display limit. Keyboard and VoiceOver users can reach and read the complete region. No
ellipsis can hide the command tail the user would approve.

Actions: Allow once, Decline, Answer in terminal. Choosing a request from the list is navigation,
never an answer. Do not focus Allow automatically. A flagged command defaults to Decline.
No ordinary Return shortcut answers a permission unless the user has explicitly focused that
button. Use a calm wait sentence, not a red ticking countdown. A quiet remaining-time detail
may exist but must not turn expiry into pressure.

Required phases:

| Phase | UI and available action |
|---|---|
| Pending, fully viewable | Explicit three choices; Allow gated by full display |
| Pending, cannot be fully shown | Answer in terminal and Open only |
| Sending | Lock all decision controls; retain operation and identity |
| Allowed/declined/released confirmed | Show the actual outcome in place; Back to Today/Sessions |
| Session focused | "Moved to your terminal · Open"; remove decision controls within routing requirement |
| Expired | "Moved to your terminal · Open"; never relabel as Declined |
| Already answered elsewhere | Explain that it was handled; no stale Retry that can approve |
| Delivery failed/unknown | Explain uncertainty truthfully; Retry only if backend confirms still pending |

No Undo is offered for an approval. The persistence requirement applies to reversible saved
data actions, not reversing a command that may already have run. A confirmation cannot mean
more than the backend acknowledgment establishes.

Five queued requests per session is the backend cap. Show +N more and a compact identifiable
queue. Preserve completion/failure events behind an open request. Switching between requests
does not reset their backend hold, release, or immutable operation.

Codex beta surfaces only capabilities proven by its spike. It never displays Allow once or
Decline for Codex approvals. Without a documented needs-you signal, show only turn-finished
information; no fabricated Needs you row in mockup data.

## Quick add

Label Quick add. Placeholder "Remind me…, note…, open…". ⌘K focuses it; a companion summon
shortcut opens it at the companion with focus. The field is compact at rest, then expands into
an inline draft surface when useful. It is not an omniscient chat box.

| Input | Visible preview and outcome |
|---|---|
| `dentist thu 2:30` | Reminder title + complete resolved date/time/zone; Enter saves only after that preview is visible |
| `call mom at 3` | Explicit alternatives when ambiguous; choice updates the preview; next Enter saves |
| `note: shipped reminder editing` | Note preview; destination Log; Enter saves |
| `note for evaluation: …` | Exact notebook destination or a choice; retain the text while choosing |
| `open enrollment closes friday 5pm` | Reminder preview, because date resolution precedes open |
| `open https://example.com` | Exact target preview, then explicit open action |
| Unknown prose | Log note draft; Save as note / Make it a reminder… / Discard |
| `$ npm test` with Labs off | "Commands are off" and direct setting link; never execute |
| `$ npm test` with Labs on | Exact command and working folder in a terminal review; separate Run in terminal confirmation |

Plain English is never shell. Don't use natural-language examples that imply arbitrary actions
can run. Everyday users see everyday examples. No command, session, hook or MCP vocabulary is
in everyday Quick add suggestions. Do not display "uses Claude" for actions that run locally.

Finish where the user started: a companion note destination choice, time ambiguity, Save and
Undo all remain on the companion surface. The window follows the same rule. A focused sheet
may be part of the window surface; opening another top-level window merely to finish a short
draft is not.

Keep the draft while saving. Success is the moment to clear it. Failure retains it with an
inline explanation and Retry. Escape first closes a suggestion popup; next Escape closes the
draft and returns focus to its invoking control. If a populated unsaved draft would be lost,
offer Keep editing / Discard instead of silently dropping it. This is a transient draft behavior,
not a promised cross-launch autosave feature.

## Setup: first useful thing before configuration

Three steps with Back and a simple named progress indicator. No sidebar, marketing carousel,
feature grid, statistics, fake activity or terminal setup before a real reminder.

1. **A useful reminder.** Pip waves once. "Hi, I'm Pip." Ask "What should I remind you about?"
   with the real short example Stretch in two minutes. The user can edit it. Show the actual
   resolved time and "Reminders appear on this Mac" before Save reminder. After save, show the
   title, time, Saved state and Undo, then Continue. Name customization can wait for Settings.
2. **Delivery.** Notifications and Start at login have independent explicit controls and result
   states. Explain denied notifications truthfully and offer Open System Settings. Do not paint
   both green because one succeeded. Show the summon shortcut and keep the original reminder
   recognizable if it fires mid-setup. Continue remains available when the user declines.
3. **Optional tools.** "Do you use Claude Code?" Connect Claude Code / Skip, I don't use AI
   tools. Connection explains its exact change, backup and confirmation. Then wait for a real
   first session event. Installed-but-unseen reads "Connected and waiting for the first
   session", never Working. Let the user finish while waiting; retain that state in Agents.

Finishing setup lands on Today with the user's real reminder, not a synthetic example dataset.
If it has fired, show its actual outstanding state. Skip enters the calm path with no tool
vocabulary in its normal work views. Codex beta is a later deliberate settings action.

## Settings

Separate ⌘, window; no Back to Sidefolk control. Four named panes:

| Pane | Grouping and behavior |
|---|---|
| General | Startup and Dock; theme/System default; reduced motion and text size; shortcut; sounds/Quiet; default snooze; Your week schedule; Labs clearly separated at the bottom |
| Companion | Pip and Spark side by side using real frames; selected radio state; name; size; position; sleep. Show Idle and Needs you previews using frozen art. No accessories/style/color/import controls |
| Agents | One Connect Claude Code switch for hooks + MCP; exact health state and Repair; default terminal; supported host matrix word for word; optional Codex Beta below |
| Privacy & data | Screen recording protection; local-data explanation; journal retention/off/Clear; export; Copy report preview; Disconnect & uninstall |

Immediate preferences save with explicit failures beside the affected control. Failed saves
revert only the failed setting after explaining the outcome; don't leave a switch looking
persisted when it isn't. Avoid a generic global Save button for a long preference form.
Changing companion keeps its name and meaningful state. The real desktop companion only
changes after a confirmed successful save; no selection in the mockup is a deployed change.

Connection health uses exactly the domain meanings from V1-D13: Not connected; Connected and
waiting for the first session; Working; Needs repair (reason + Repair); Port or socket
unavailable. A connection switch is not enough evidence for the Working label.

Copy report opens a readable redacted preview, then Copy. Clear history explicitly names the
history affected; it does not delete notebooks or reminders. Disconnect & uninstall previews
what will be removed and what stays, keeps data by default, offers Export first or Delete data,
and reports completion honestly. Export is a real reachable step, not a line in a confirmation.

## Companion and desktop patterns

- Clicking the companion opens the compact session list when relevant, with project and
  status word. Quick add remains explicitly reachable. Clicking the body never answers a card.
- Cards have a tail toward the companion, stable readable surfaces and shared status tokens.
  Interactive card actions use the larger overlay targets required in V1-U7.
- One attention chime per firing; no repeated nag or faster pulse for queue depth. The queue
  count lives on the held state. Animation settles while someone reads.
- Right-click/tray exposes Show/Hide, Quick add, Quiet, Pause answers, Settings and Quit using
  the actual supported commands. Paused answers is a legible state, not merely a changed icon.
- Closing the main window keeps the companion and reminders running. Quit explicitly ends the
  app; local macOS notification behavior follows the supported pre-schedule contract. No
  notification or menu label promises phone delivery.
- Pip and Spark share semantics, copy, controls and state accessibility. A character change
  must not become a different permission behavior or information architecture.

## Accessibility and state contract

Use native semantic controls and labels before custom interaction. Window controls follow the
v1 24–28 px size; overlay targets follow the 44 px requirement. Compact presentation cannot
remove keyboard reachability. A title is not an accessible label. Every repeated button names
its item to VoiceOver, for example "Snooze Call mom". Status uses a shape and word, never color
or ear position alone.

| State | Required rendering |
|---|---|
| Loading | Stable section skeleton and named loading status; not an empty collection message |
| Empty | Specific scope and one useful next action; no invented sample work |
| Filtered empty | Name the query/filter; Clear filters |
| Error, no usable data | Plain-language explanation + Retry; keep unsafe actions unavailable |
| Stale cached data | Preserve last readable content; label Last updated and Retry; don't claim live |
| Corrupt store | Kept-aside-file explanation, Restore last good copy when available, Show in Finder; never "No reminders yet" |
| Saving | Keep draft; disable duplicate submit; announce completion once |
| Failed save | Draft/content retained and Retry; never false success |
| Deleted item | Focus moves to next row, previous row or section header; persistent Undo and ⌘Z |

Focus sequence follows the visible order. Navigation moves focus to the new page title;
updates preserve focus and scroll. Sheets trap focus while open and restore it to the invoker.
After removing the last item, focus its section header or Add action rather than BODY. Menus
support keyboard conventions and Escape. Successful background events never steal focus.

Live regions announce the meaningful change once. Don't announce every countdown second,
animation frame or incoming row repaint. A newly focused request announces project, first
prompt line, agent, host and pending state before the action controls.

Text size settings increase text without truncating action labels or raw operations. Reduced
motion removes hops, pulses and cross-fades; it retains the status, text and card. Both light
and dark require independent contrast and focus checks; choosing a token is not itself an
accessibility pass. Code regions need keyboard scrolling and readable line wrapping or an
explicit non-destructive wrap control; no hidden tail content before Allow.

Undo is persistent until dismissal, with a clear semantic association to the operation. For
successive reversible actions, keep a real undo stack behind ⌘Z; a visible latest-action bar
must not silently destroy earlier undo opportunities. Dismissal closes the bar rather than
pretending an already executed permission can be undone.

## Required design frames for implementation

The visual team should produce actual editable/renderable UI frames with these contents, not
just a mood board. Example content must obey the capability matrix.

1. Today populated in light: one overdue reminder, one real Claude request, two due reminders,
   working Claude session, two dated log entries. Show the complete page hierarchy.
2. Today quiet/first day: no agent language; only actual reminder and note starting points.
3. Today dark: same functional density, independent surfaces/focus, selected Spark companion.
4. Reminders list + detail: snoozed Monday occurrence on Tuesday, next Monday unchanged;
   original time and history readable. Include the editor and scope popup as adjacent frames.
5. Work log list/detail: dated weekly stream, notebook filter, searchable dates, a note Move
   picker and persistent Undo. Show Your week as a supporting frame.
6. Sessions + full request review: distinct projects/hosts, readable real diff, disabled Allow
   while unread, released state, confirmed sent state.
7. Quick add: reminder preview, ambiguous time choice, named-notebook choice, unknown prose
   note draft, save failure retaining input.
8. Setup: all three steps, notification denial and waiting-for-first-event variants.
9. Settings: all four panes and their reachable controls; Pip/Spark picker, health repair,
   privacy report preview and uninstall data choice.
10. Desktop cards: reminder, folded count, short request, long request → Review all of it,
    expiry/release, done → Log it, narrow late-reminder recap. Light/mid/dark backdrops are
    design compositions, not screenshots or claims of native testing.

## Deliberate departures and implementation limits

- **New visual target:** this review supersedes the 24 October aesthetic recommendation for
  the proposed redesign only. A future implementation must record the founder's design
  selection rather than silently editing the old approval history. Functional v1 scope stays.
- **Existing logo, two characters and token/status semantics stay.** No new art family, character
  pipeline, brand name, task system, model service, platform or entitlement is proposed.
- **Stronger hierarchy, fewer containers:** ordinary lists use hairlines, attention is a
  special surface, date/type hierarchy carries identity. This changes composition, not state.
- **P5 work is still implementation work.** Native keyboard/VoiceOver, exact-tab routing,
  recurrence, corruption recovery, real notification delivery and production performance
  cannot be established by static images or a design prototype. Founder checks remain open.
- **Known contract ambiguity resolved narrowly:** V1-R8 requires the late reminder recap in
  v1. The roadmap's general While you were away feature remains v1.1. Do not expand it into
  session summaries or a revived morning brief.
- **Work in progress remains one.** This parallel design study creates review artifacts, not
  concurrent feature implementation. No release gate is marked passed here.

## Acceptance walk-through for a developer

1. Complete setup without AI; save a real reminder with visible time; deny notifications;
   arrive at Today without agent terms or fake data.
2. Quick add `dentist thu 2:30`; inspect time; save; use Undo after reading another view.
3. Snooze a Monday repeat to Tuesday; inspect the unchanged next Monday in details.
4. Choose between two near-matching notebooks; keep the original draft; save; Move; Undo.
5. Connect Claude Code; see waiting-for-first-event, then a real Working event, then Needs you.
6. Review two similar projects' requests without mixing identity; read a complete diff; decline
   a flagged operation; release another by Open; verify no stale Allow remains.
7. Log it from a finished session; edit the title; choose notebook; later copy Your week.
8. Navigate all the above using only keyboard, then VoiceOver, with reduced motion and larger
   text in both themes. Verify an async update and deletion never lose focus.
9. Inspect loading, empty, stale, failed save and corrupt-store variants separately. Verify
   repair and restore remain within their actual backend capabilities.

These are review scenarios and engineering acceptance criteria, not completed test results.
