# Developer handoff — Sidefolk: the workday desk

Final design decisions, 25 October 2026. Read this with [the image gallery](README.md) and [team/UX.md](team/UX.md). This specifies the intended interface. The editable prototype provides layout and interaction examples, not production state, storage or permission logic.

## 1. Design authority and scope

The founder asked for an open design rethink, a specialist team, image references and a complete handoff before development. This package fulfills that design task. It does not alter production UI, the existing uncommitted work, app behavior, global agent settings or release gates.

Keep Tauri/Rust/TypeScript and the existing Pip/Spark frame pipeline. Keep all v1 feature boundaries, the Pip Signal geometry and wordmark, companion silhouettes, voice rules, and palette. The new composition replaces the 24 October reference layouts only when adopted. Record that reference change against V1-U2 before the implementation handoff is treated as the release baseline.

**Explicit typography proposal:** use 13 **CSS px** for compact-window body/control text and 12 CSS px metadata. V1-U7 currently says 13 pt. In CSS, literal `13pt` is about `17.33px`; this prototype does not apply that conversion. The 13px choice is a deliberate proposed density adjustment, not a claim of literal compliance. Record it when this direction becomes the implementation baseline. Preserve 16px overlay body text, 44px overlay actions, and accessible text scaling. This package adds scoped sizes in `design.css` rather than shrinking global production tokens.

No feature is added or removed by the visual proposal. No change to the logo or mascot art is recommended. Settings shows the exact four contract panes: General, Companion, Agents, Privacy & data.

## 2. What makes it Sidefolk

The visual idea is a small personal work surface, grounded in the things Pip holds for you. Its signature is cream paper, charcoal type, restrained mint selections, useful dates, and the real clay companion at relevant moments.

- Use **one soft-mint attention surface** for a pending decision. It has a named source and a distinct action. It is not the template for every other section.
- Use **continuous time-led rows** for reminders. A column of times and quiet hairlines makes the agenda scannable.
- Use **dated writing** for the Work log. Saved entries lead; the empty composer expands when invoked. The notebook index uses a mint edge rather than a second large navigation pill.
- Pip/Spark is the speaker; the logo is the company. Never substitute the dark logo glyph for the speaking companion.
- Keep the palette and system font. Identity comes from composition, pacing, useful copy and interaction, not a new background illustration on each view.

The generated desk image is a **presentation cover asset only**. It does not become app wallpaper, an empty-state illustration, a dependency or part of the frozen character pipeline.

## 3. Geometry, scale and themes

| Item | Final proposal |
|---|---|
| Native primary window target | 1100 × 760 logical pixels; minimum 640 × 480 |
| Expanded review frame | 1440 × 1000 presentation canvas; 1344 × 800 framed window |
| Sidebar | 204px expanded, 176px medium; horizontal labeled navigation at ≤820px |
| Content gutter | 32px expanded, 24px medium/compact |
| Toolbar | 66px expanded, 56px compact |
| Main title | Existing 28px panel token, 1.18 line-height, weight ≈650 |
| Content title | Existing 20px card token; reserve for significant content |
| Window body / metadata | Proposed 13px / existing 12px |
| Operation text | 13px system mono; preserve whitespace; wrap only where faithful |
| Window controls | 28px standard visual height, 36px full-row navigation |
| Overlay controls | 44px minimum height; body text remains 16px in production |
| Rows | Minimum 52px, typically 60–72px for two lines; grow with content |
| Spacing | Existing 4/8/12/16/24/32px rhythm |
| Radii | Existing 10px controls, 18px content/cards, 24px overlay panel token |
| Focus | Existing focus token, 3px ring + 3px offset |

Use `src/tokens.css` as the single palette authority. `assets/production-tokens.css` is a review snapshot, not a second future production source. Keep semantic light/dark pairs, charcoal text on mint, status fills decorative, and essential control boundaries stronger than separators. See [exact colors/contrast](team/VISUAL.md).

The traffic-light circles in the images are placeholders for native window controls, not new custom buttons. Use the real macOS chrome and traffic-light clearance. In production, only genuinely empty header areas may be draggable.

At ≤820px, supporting Today content becomes a single ordered column. A reminder editor occupies the content area immediately instead of stacking beneath the full reminder list; Close returns to the list. Focus its title field when opened. No information requires horizontal document scrolling. Raw operations may have a separately labeled keyboard-reachable scroll region.

Larger text is not a fixed font swap in fixed-height rows: scale text, row height and controls together. Start the larger setting at 16px body/14px metadata while leaving 28px titles; allow controls to grow. At 200% text resizing, retain every action and resolved date. The proposal defines this behavior; native large-text/VoiceOver acceptance still needs implementation and hand checking.

## 4. Navigation and information order

Main navigation is one level: Today, Sessions after a Claude connection, Reminders, Work log. No Actions, Crew, dedicated Requests destination, permanent chat or settings categories in the daily sidebar. Settings opens separately through ⌘, or the small settings control. Its window has no “Back to Sidefolk”. Closing the daily window keeps reminders and the companion available.

**Today order remains binding:** Overdue → Needs you → Today’s reminders → Running sessions → Recent log. The visual reviewer suggested putting live requests first; that suggestion was rejected to retain V1-R15. A request can have stronger contrast without changing order. At wide sizes, the last two sections can occupy a quieter support column; DOM, keyboard and compact reading order remain the same.

No-agent Today has reminders and real recent writing. It contains no tool install promotion or developer terms. Never call an unloaded/failed store empty. Overdue one-offs remain visible until handled.

## 5. Component kit

Build small typed components around current `dom.ts`, `ui.ts` and `dialog.ts`; no framework rewrite or dependency is implied.

| Component | Required behavior |
|---|---|
| Button | Primary, secondary, text, destructive; hover/focus/disabled/pending; retain a clear label during saving |
| Row | Title area opens details; ≤2 visible actions; item-specific accessible labels; wrap long content |
| Overflow | Real ellipsis icon; anchored popup with standard arrow/Escape behavior; return focus to trigger |
| Field | Persistent label, value, associated hint/error; no placeholder standing in for date/time |
| Date/time | Native/localized values, explicit zone, resolved preview; preserve draft through invalid input |
| Segmented control | Group label, selection state, native keyboard semantics; no hidden meaning by color |
| Switch | Label + current state; pending persistence; failure restores prior value and explains recovery |
| Sheet/detail | Clear title/Close; bounded content scroll; visible task actions; originating focus restored |
| Status | Existing glyph + word from `states.ts`; no new state words or color-only meanings |
| Toast/Undo | Acknowledged outcome; Undo persists until dismissal; queue/history for earlier undoable changes |
| Data state | Separate empty, loading, failed, corrupt, stale and unavailable states with appropriate recovery |
| Operation viewer | Immutable exact content, whitespace retained, control/bidi escapes, complete-display state |

Window component states are illustrated on boards 19 and 32. A real native segmented control or switch may be preferable to the prototype’s CSS when accessibility behavior is equivalent. The new overflow glyph is the same 24-unit, 1.75-stroke icon grammar; add it once to `src/icons.ts`.

## 6. Reminder behavior and controls

Boards 04, 05, 25 and 33 cover list, one-off edit, recurring edit and create. New reminder must never reuse an existing reminder’s title, history or delete action. Use one editor structure with explicit create/edit modes. Show a real date/time value and the resolved schedule before saving; focus the title field on creation.

| Repeat choice | Controls / preview |
|---|---|
| Does not repeat | Date, time, zone; one occurrence |
| Daily | Time and anchor date |
| Weekdays | Monday–Friday, time and anchor |
| Weekly | One or more weekday choices, time and anchor; all chosen days named in preview |
| Every N days/weeks | Integer 1–52, day/week unit, anchor; reject unsupported compounds in full |
| Monthly | Date 1–31, time, anchor; say “last day in shorter months” where relevant |
| Yearly | Month/day, time and anchor; use the engine’s supported invalid-date policy, ask instead of guessing |

Changing a repeating item asks **This one / All future**. This one creates an occurrence override; All future changes the series from the chosen boundary without rewriting historical outcomes. Deleting a series likewise names the scope before confirmation.

Snooze choices: 10 min, 1 hour, This evening 18:00, Tomorrow 9:00, Pick…. Pick opens real date/time fields with a visible zone. One occurrence moves; the series anchor never moves. If a preset has already passed, resolve a future valid value or ask; never save into the past. Skip next exists only for a repeating reminder. One-off details never show series-only language.

Done completes the occurrence. A repeating occurrence still fires next time without requiring Done. Missed history rolls over when the next occurrence fires. After wake, show the latest missed occurrence per series with its original time and Late; do not invent the broader v1.1 away digest. Notifications denied uses the exact useful consequence: “Reminders show only while Sidefolk is running.”

Prototype dropdowns show the supported rule family but do not calculate recurrence. Rust is authority. [Full contract detail](team/UX.md) and V1-R1–R15 govern the engine.

## 7. Work log and Quick add

All entries is a dated stream; Log is the default capture inbox. Named notebooks have a light list/detail index inside Work log. Changing notebooks filters actual entries and preserves unsaved capture text. A written entry opens for editing from its title. Move and More are the two visible row actions. The menu contains Delete and other less common actions.

Search matches words and dates. Provide date-range results with a readable label (“October 2026”, “Last week”) and notebook/project filters. No matches is distinct from no entries. Your week lists real notes and completed reminders; Copy as Markdown uses those exact values, without model generation or a score.

Quick add is a shared capture component on window and overlay. Its field is labeled Quick add and uses “Remind me…, note…, open…”. It shows the resolved interpretation and destination before saving. Unambiguous Enter saves then gives persistent Undo. Ambiguity needs a choice. An unresolved phrase is a Log note draft with Make it a reminder / Discard; it never becomes shell execution. Shell requires `$` and the Labs flag.

| Draft | Preview and finish |
|---|---|
| `note: …` / `log …` | Save to Log, then Noted in Log · Move · Undo |
| `note for X: …` exact match | Named destination before save |
| One near match | Ask “Add to X?”; retain draft |
| Several near matches | Named notebook choices, no guess based on recency |
| No notebook match | New notebook X or Log; retain draft |
| Resolved time | Human date + time + zone + this Mac before save |
| Ambiguous time | Choice labels with distinct dates/times; success confirms the selected value |
| Unsupported recurrence | Ask for the missing rule; do not accept only the easy part |
| Open app/folder/https URL | Show the actual target; complete on the starting surface |
| Failed save | Keep fields/draft and destination, offer Retry, no success toast |

The prototype’s fixed clock is Sunday, 25 October 2026 at 14:32, Asia/Tokyo. Tomorrow is Monday, 26 October. This is fixture data, not date logic for reuse. Its deliberate choices are local examples; use `commands.ts` + `when.ts` in production. Normal text-field ⌘Z must remain native; application Undo only applies outside an active text edit.

## 8. Session and request lifecycle

Sessions identify project + first prompt line + host. A live session has Open; an ended session may have Continue. Log it opens an editable note draft and never writes automatically. The UI must use the host capability matrix from V1 §7.2, **word for word** in the full Agents detail. Compact rows may show a short summary but must not imply exact focus for an inexact host. Codex remains beta and never gets a Sidefolk approval control.

`requests.rs` owns immutable operations and liveness. The display is derived, not a second policy engine. Board 09 shows a complete command, 10 a diff, 29 a released request and 30 unread long content.

| Lifecycle state | Interface and available actions |
|---|---|
| Pending, short/full display | Identity + exact operation + Allow once / Decline / Answer in terminal; no default approval |
| Pending, unread long display | The full operation is reachable; Allow absent/disabled with a reason; Decline and terminal handoff remain |
| Complete display, still live | Allow once can appear; Rust must revalidate liveness when answering |
| Cannot display / >50,000 characters | Explain the limit; Answer in terminal + Open only; no approval |
| Sending | Lock competing actions, show Sending your answer…, retain operation/identity |
| Confirmed allowed/declined | Show the precise result after acknowledgment; do not claim completion of the agent’s work |
| Delivery failed or unknown | “Your answer hasn’t been sent” only if known; recheck liveness before offering Retry |
| Released / expired / focused in host | No answer controls; “Moved to your terminal · Open”; never enable Allow again |
| Already answered elsewhere | Read-only resolved outcome; Open remains navigation |

A command is byte-preserved; control/bidi characters are visible escapes. Edit shows the real old/new diff; Write shows the full content; MCP shows complete pretty JSON. Do not use ellipses to hide meaningful operation text. A decorative “complete” badge does not establish read-completeness. Bind the component to the presented operation/version and actual complete-display event; content must remain available. Scrolling the prototype’s 120-line fixture demonstrates the transition only, not production authorization.

The 60-second hold is explained calmly: “Claude waits about a minute, then asks in your terminal.” No urgency progress bar. A release never becomes Allow or Decline. Opening the session explicitly releases it to the tool’s own prompt. At most five requests per session; coalesce the visual count, retain each item’s exact identity, and queue completion/failure behind an open request.

## 9. Companion, setup, settings and copy

Use copied production WebP frames in the prototype; use `public/crew/{pip,spark}/3d/` in the app. The existing source asset size includes transparent margins; size/crop by optical silhouette, not by assuming the entire image is the visible body. Do not redraw/scale-distort the companions or generate new lookalikes. Existing greenish fringe visible when unusually enlarged is source art, not a proposed decorative outline; keep native small-size checks for the production artist.

Cards have a tail toward the selected companion. Near a screen edge flip/reposition the card without putting actions off-screen. Pip’s status dot follows the ear; Spark’s follows the antenna tip. No work light while idle. Quiet prevents sounds, not visible pending work. A reminder sounds once and folds after two minutes; important work remains discoverable in the window/menu.

Pip uses one first-person sentence of ≤12 words, then buttons. Name Claude for Claude’s acts. No emoji, guilt, generic success celebration, or raw errors. Personality belongs in the pose; permission copy stays factual. Suggested copy in images is part of this rule, not a new voice.

Setup has three useful steps: create one real reminder with a visible saved time; show notifications and login results honestly; offer optional Claude connection. Board 34 is disconnected, board 13 installed/waiting. Only a live event transitions the health to Working. Configuration presence does not establish a healthy connection. Install/repair must preview files, obtain the existing confirmation, and make byte-for-byte backups. Skip keeps a useful no-agent product.

Settings is a separate native window. General owns appearance/sounds/Quiet/shortcut/default snooze/Your week/Labs; Companion owns Pip/Spark/name/size/position/sleep; Agents owns one combined Claude connection/health/terminal/matrix/Codex beta; Privacy & data owns recording protection/retention/Clear/Export/report/uninstall. Show the installed application version there when wired to the real runtime. Preserve the recording-protection default as undecided until the native spike; the design is not evidence that it works in all capture tools.

## 10. Accessibility, motion and failure

Use semantic controls and one main heading. Repeated controls name their object. An interactive companion has an accessible name and state; decorative duplicates are hidden from VoiceOver. Save results are polite announcements, failure is a concise alert, and request arrival/release is announced once. No focus theft on incoming events.

Record the opener for every dialog/sheet/menu. Escape closes; closing restores that opener or a surviving row/heading. Save/delete/expiry never leaves focus on BODY. Keep active drafts through live updates, sorting, theme changes and notebook selection. Suppress no native editing Undo.

Use current motion tokens: controls 140ms, card transitions 200ms, companion entrance 520ms; real-success celebration under 1.2s. Reading an open decision surface should be still. Reduced motion removes movement and pulses while keeping the glyph, word and actions. No animation is needed to understand the screenshots.

Errors distinguish data absence from failure. Corrupt files are preserved; show Restore last good copy and Show in Finder as available. Restore explains the restart before acting. A failed write preserves the draft. Stale reads name the last known version and Retry. Never render “No reminders yet” over damaged or unloaded data.

## 11. Implementation sequence and source map

Implement one vertical slice at a time under V1 WIP = 1. This design task does not move the active P2 backend work to P5 or mark either done.

1. Record the chosen visual reference and scoped typography decision; finish the planned state authority.
2. Build a token-backed component specimen, including all states in boards 19/32. Replace the double CSS cascade with one shared component stylesheet.
3. Integrate shell + Today + Quick add, including no-agent/error/focus/Undo cases.
4. Migrate Reminders and Work log, retaining drafts and using Rust state, then implement Your week.
5. Migrate Sessions/review/overlay without changing request authorization semantics.
6. Integrate the separate Settings window and truthful setup, then remove obsolete styling.

| Current files | Intended change |
|---|---|
| `src/tokens.css`, `src/theme.ts` | Scoped window density and appearance; one palette authority |
| `src/icons.ts`, `src/states.ts` | Add one overflow glyph; retain canonical status words |
| `src/dashboard/dom.ts`, `ui.ts`, `dialog.ts` | Shared typed kit, keyed rows, focus restoration |
| `dashboard.css`, `redesign.css` | Replace with one kit/view stylesheet after migration |
| `src/dashboard/app.ts`, native window prefs/menu | Shell, Settings route/window, retained drafts, persistent Undo |
| `home.ts`, `tell.ts` | Today hierarchy and shared draft presentation |
| `reminders.ts`, `notes.ts` | Rows, editor, timeline, notebook index, recurrence UI |
| `sessions.ts`, `requests.ts` | Session identity and immutable operation/lifecycle views |
| `setup.ts`, `settings.ts`, `notifications.ts` | Three setup steps, four panes, actual permission/connection results |
| `src/bubble.ts`, `pip.ts`, `styles.css` | Tail-linked cards and shared semantics; 44px overlay controls |
| `scripts/webkit-check.mjs`, relevant unit suites | Meaningful behavior regression coverage |

Run the existing typecheck, Vitest, WebKit and build checks during implementation; add only behavior tests that protect the changed flows. Native VoiceOver, traffic lights, Spaces, real notification timing and host focus require founder hand checks. The design package’s export checks are not G1–G5 approval.

## 12. Review resolution and completion criteria

The three reviewers’ initial notes are historical observations of earlier drafts. Before delivery the lead fixed: clipped desktop request content; recurrence-only controls on one-offs; incorrect notebook selection/content; three entry actions; speech-bubble overflow icons; wrapped project filter; setup connect/wait contradiction; create vs edit confusion; Quick add selected-value confirmations; compact-editor visibility; note draft retention; and interception of text-field Undo. A long-operation preview now demonstrates enabling Allow after full display; production still delegates all authorization to Rust.

The request-before-overdue suggestion was rejected. A new logo/mascot family, ornamental app wallpaper and new product features were rejected. The existing assets and feature contract are deliberate final choices.

The handoff is complete when a developer can build the component kit and every flow above without inventing a visual language or permission policy. The application is complete only after implementation, native checks and the founder’s release-gate record. This package supplies the first of those, with clear verification limits in [VERIFICATION.md](VERIFICATION.md).
