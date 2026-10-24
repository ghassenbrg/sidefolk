# Sidefolk UI/UX review — 24 October 2026

Status: **approved for implementation by the user on 24 October 2026**.
Implementation is complete and built; review images remain visual references.
Actual WebKit captures are in `../../output/playwright/redesign/`.
This package proposes screen layouts and interactions. It does not replace the
approved product plan, change the application, or approve a character redesign.
The generated mockups use illustrative data; this written specification governs
behavior if an image contains incidental wording or layout errors.

Review images:
1. [Today](01-today.png): main hierarchy and shared navigation.
2. [Reminders and Notes](02-reminders-and-notes.png): list-first reminders,
   creation sheet, notebooks and dated capture.
3. [Sessions and request review](03-sessions-and-review.png): a session list
   beside the exact action requiring a decision.
4. [Desktop and Settings](04-desktop-and-settings.png): quick capture,
   a due reminder and one focused settings category.
5. [Appearance settings](05-appearance-light-and-dark.png): theme choices and
   the central settings structure in light and dark.

## Direction

**User-confirmed constraint during review:** keep the current logo exactly as it
is. Reuse the existing production logo/icon assets and geometry; do not redraw,
regenerate, restyle or replace them. Logo variations in generated mockups are
placeholders and are not proposals for a brand change.

Keep Pip Signal, the existing cream/charcoal/mint tokens, system typography and
the state vocabulary in `src/states.ts`. Make the interface feel like a small
Mac utility: readable lists, a clear main action, quiet separators, and a small
companion. Avoid large mascot banners, a character collection on the home screen,
charts, permanent chat history and layers of cards inside cards.

Pip body B is the identity reference for these mockups. The separately produced
bunny, robot and penguin assets are not implicitly selected as the new default.

## What the current source suggests improving

These are an assessment of the current TypeScript/CSS and product documents,
not findings from a live screen capture or a user study.

| Current implementation | Proposed change | Intended benefit |
| --- | --- | --- |
| Six equally weighted navigation destinations, including Sessions before a tool is connected | Today, Reminders, Notes first; Sessions in an AI tools group after connection; Actions and Settings at the bottom | Put everyday tasks first and introduce technical concepts when relevant |
| Reminder creation form permanently precedes the reminder list | List first; Add reminder opens an editor sheet | Make checking existing reminders faster |
| New session form and Spark customization share the Sessions page | New session button opens a short sheet; project companion options live in session/project details | Keep monitoring separate from configuration |
| Many unrelated settings groups in one long page | One settings category at a time | Make an individual preference easier to find |
| Tell Pip input relies on a placeholder and knowledge of phrases | Keep the shared input; add visible examples and ordinary labelled buttons | Support both sentence capture and browsing |
| Terminal execution confirmation is an action in a temporary toast | Persistent review sheet with exact command, folder, destination and explicit Run/Cancel | Leave enough time to review an action |
| Today mixes requests, work and upcoming items in a single stream | Attention first; upcoming reminders next; compact sessions and recent notes alongside when space allows | Make the next useful action easier to see |

## Navigation and shell

- Everyday: Today, Reminders, Notes.
- AI tools: Sessions, shown after connection. Before connection, AI setup is
  available in Settings → AI tools and an optional setup step; no persistent
  connection promotion displaces reminders on Today.
- Utilities: Actions and Settings anchored at the bottom.
- One Tell Pip input in the window and the same interpretation on the desktop.
  Examples show supported phrases; the input does not imply unrestricted AI chat.
- A wide window may use a secondary content column. A narrow window stacks the
  same sections in priority order and keeps full text labels and actions.

## Main journeys

### Today

The title is Today with a small local date. Show pending requests first, with
their count and a Review request action. Show upcoming reminders and meetings
(only when calendar access is enabled), then recent notes. Connected users also
see a compact work session list. Avoid duplicating full request cards in several
sections. With no pending requests, use a short “You're all caught up” line,
not a large empty card. Add reminder stays visible.

### Reminders

Show open reminders grouped by Today, Tomorrow and Later; Overdue appears only
when needed. Repeating and Completed are optional filters, not separate products.
Each row has a completion control, title, due time and clear recurrence text.
Selecting a row opens details with Edit, Snooze and history. Less common actions
can sit in a labelled More menu. Deletion offers Undo.

Add reminder opens a sheet with a labelled sentence field and resolved title,
date, time, timezone and repeat controls. For example, “tomorrow at 9 check the
results” resolves to **Sunday, 25 October 2026, 09:00 · Asia/Tokyo** in this
review's sample data. The actual app uses the user's timezone and current date.
Save reminder is explicit; Cancel preserves the original reminder when editing.
Invalid or ambiguous times receive inline clarification, not a silent guess.

### Notes

Use a notebook list and a readable dated entry view. Capture with Add note or
Tell Pip; keep the chosen notebook visible. New notebook is secondary. Search
stays within Notes. Export is available from the notebook toolbar. Draft a
summary is an optional, explicitly labelled Claude/Codex action showing which
tool will run; it does not run automatically when opening a notebook.

### Sessions and requests

Project rows show project, tool, session identity, state word and an Open or
Review action. Keep full session identity available when several sessions share
a folder. Recently finished sessions offer Continue. Do not show invented
progress percentages or claim Sidefolk replaces the tool's own interface.

New session opens a sheet: project folder picker, tool and where it opens.
Default to Asks first. Full access is a separate deliberate per-session choice
whose actual tool-specific scope is explained before starting. A project Spark
is optional and configured in details, not a requirement to create a session.

A request opens a persistent detail pane or dedicated review view. Order:
project/companion, tool/session, question, exact command/action, exact folder,
then the request's actual choices. A sample with Decline and Allow once must not
be generalized to requests with different semantics. Long commands wrap and
remain selectable; technical metadata can be disclosed without hiding the action
or scope. No approval is preselected; Enter in another field never approves.
Show Sending until acknowledgment, Retry on failure, and disable resolved or
expired requests. Closing the view does not answer or discard a pending request.

### Desktop companion

Click Pip or use the configured shortcut to open one input card. Show three
examples: a reminder, a note, and Open Sidefolk. On text entry, show what will
happen before the user saves or runs. A reminder preview includes the resolved
time. At due time, show the note with Done, Snooze and Open; Snooze reveals its
choices. A small count gives access to other pending items without stacking
many floating cards. Every card closes with × and Escape; pending decisions
remain in the app. Do not steal keyboard focus for an arriving reminder.

### Settings and first use

User-requested revision: Settings is the central place to find **all supported
user-facing configuration**, including a convenient System / Light / Dark theme
choice. This expands the six-category sketch in board 04; the following category
map and new Appearance board take precedence.

| Category | Configuration and related editors |
| --- | --- |
| General | Start at login, Dock visibility, companion shortcut |
| Appearance | System / Light / Dark, with live theme previews |
| Companion | Name, existing available looks and imports, size, visibility, idle/sleep behavior; project companion options through their existing editors |
| Reminders & calendar | Notification delivery status and shortcut to its permission control, calendar connection and meeting lead time; links to manage repeating reminders |
| Notifications & sound | Sound cues, volume, spoken output and voice; link to macOS notification settings |
| AI tools | Claude Code/Codex connections and capabilities, terminal choice and terminal control, CLI setup; links to per-session access and project configuration |
| Privacy | Capture protection with its current platform limitations and clear explanation of local data |
| Accessibility | Follow system reduced motion, app reduced motion, larger text |
| About & data | Version, local data location, export links, logs, problem report, setup guide |

One option has one canonical editor; other categories can link directly to it.
For example notification permission belongs to Notifications & sound, while
Reminders & calendar links there and displays its actual delivery status.
Notes/notebook and saved action editors remain in their feature pages, reachable
from Settings, so “everything configurable” does not mean duplicating every form.
Do not expose internal migration flags or settings that the backend cannot honor.
Optional AI controls stay discoverable in Settings even before a tool is connected.

**Theme choice**
- Settings → Appearance → Theme has three visible, labelled radio tiles:
  **System**, **Light**, **Dark**. Default is System.
- System follows the Mac appearance at launch and while running. Light and Dark
  remain selected regardless of later OS changes. Returning to System resumes
  following the OS immediately; no stale manual override remains.
- Choosing a theme updates the UI immediately, persists without an Apply button,
  and is restored after relaunch. Successful saves show quiet inline feedback;
  failures keep a clear unsaved/retry state and do not falsely show Saved.
- Use the same preference for every Sidefolk window and overlay card, including
  a hidden window opened later. Native menus/controls use the corresponding
  appearance where supported. Companion artwork and the current logo assets stay
  unchanged; UI background/text adapt through the existing light/dark tokens.
- Preview tiles expose their label and selected state to assistive technology.
  The selected theme remains identifiable without color. Keyboard arrows select
  within the group; keep focus visible in both themes and reduced motion honored.

**Convenience**
- Settings remains a fixed labelled navigation destination and opens with ⌘,.
- Search settings matches labels and common words (theme/dark, sound/volume,
  shortcut, terminal, notifications); results show category and jump to the exact
  control. Empty results provide a clear message and Clear search.
- Show one category at a time, remember the last category, and let direct links
  from feature pages open the right control. Remembered categories never override
  an explicit link target.
- Common controls remain visible; disclose advanced details without hiding basic
  preferences. Explain disabled controls and offer the relevant setup action.
- Ordinary reversible preferences save automatically; installers, disconnects,
  native permissions and access changes retain their existing explicit actions.
  A global Settings page must not silently turn every session into Full access.
- All categories reflect real saved values and real permission/connection status.
  Search and theme persistence are proposed additions, not already implemented.

Keep capture protection's current platform limitations visible; do not promise
universal hiding.

Propose a shorter, outcome-led setup:
1. Meet Pip and create a real two-minute reminder (name is optional).
2. Explain desktop access, shortcut and reminder delivery. Request notification
   permission only from an explicit Allow notifications button; show whether
   permission is actually granted and explain what still works if declined.
3. Optional: connect an AI tool, or start using Sidefolk immediately. Desktop
   size, art selection and advanced configuration can be changed later.

Do not claim first-use success until the real save/delivery/connection succeeds.

## Approval and later verification

Review visual hierarchy, navigation, companion treatment and the main journeys
before changing app code. If approved, implement the shell and Today first, then
Reminders and Notes, then Sessions/review, then settings and desktop parity.
Keep implementation changes reviewable by journey; do not add unrelated helpers.

Later checks: keyboard navigation and focus return; large text and 200% zoom;
narrow layouts and dark theme; System/Light/Dark persistence, live OS changes,
consistent window/overlay themes and Settings search navigation; long commands and paths; multiple identical-tool
sessions; saving while data refreshes; no notification permission; connection
failure, expired request and retry; reminder delivery after hide/quit/sleep.
Use repository tests/WebKit checks and dev logs, with native hand checks by the
user as required by AGENTS.md. Static images do not verify working behavior.

## Generation record

Images are created with the built-in imagegen tool. Exact prompts are recorded
in `prompts.json`. Images and this proposal were approved by the user before implementation.

Image review notes: generated compositions illustrate hierarchy rather than
literal window measurements. The reminder board repeats “Check the results” in
the background sample list and unsaved editor; an actual new reminder must only
enter the list after a successful save. Status labels, button contrast, borders
and flat token colors must be implemented from the source design system, not
sampled from generated shading. Connection labels are example states, not a
check of this Mac's integrations.
