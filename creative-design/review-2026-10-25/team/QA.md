# Design QA and implementation handoff

Prepared 25 October 2026 from the checked-out application, `docs/V1.md`, shared memory, the current token system and dashboard sources. This is a design audit and acceptance plan; no app implementation, native testing, release gate approval, or desktop screen capture is claimed.

## What the redesign needs to fix

The current product has useful structure, but the composition gives settings and daily work similar visual weight. Stronger identity should come from how Sidefolk helps someone see, capture, and finish their day, rather than extra decorative panels.

| Observation from source | Result for the user | Design requirement |
|---|---|---|
| `dashboard.css` uses 16 px body text, 44 px controls and generously outlined cards throughout; `redesign.css` adds a second cascade. | Every action is large and similarly emphasized. Sparse content resembles a preferences utility. | Use a compact window scale, quiet grouped rows, clear section hierarchy and generous space around the day's main action. Keep 44 px targets on overlay cards. V1-U2/U7 already require this. |
| `home.ts` presents Needs you and Coming up, with a parallel sessions/notes column. | Overdue reminders can disappear into Coming up; the page doesn't tell a continuous story of the day. | Preserve the binding order: Overdue → Needs you → Today's reminders → Running sessions → Recent log (V1-R15). Secondary material must not become a competing dashboard. |
| `reminders.ts` exposes Open, Snooze, Edit, Delete and Mark complete on each open row. | Repeated buttons overwhelm the things to remember. | At most two visible row actions. Suggested: complete plus overflow. Open details by the labeled row title; put snooze/edit/delete in the menu and details. |
| Notes are called Notes; the notebook list and details are separate routes, with no global timeline. | Capture feels like maintaining folders instead of keeping a useful work record. | Work log is the nav label; Log is the default inbox. All entries, notebooks, date search and Move are explicit designs (V1-L1–L6). |
| `app.ts` auto-removes action toasts after 9 seconds. | An Undo affordance can disappear before the user acts. | Undo persists until dismissal, with ⌘Z and a clear result. Do not dismiss it merely because another passive notice arrives (V1-U8/L4). |
| `app.ts` preserves focused elements on redraw only when they have an ID; `sessions.ts` and reminder lists replace rows. | Live changes can remove the keyboard user's position. | Stable item IDs, keyed updates and a defined focus fallback per deletion, completion and expiry. |
| `notes.ts` and several views load content asynchronously with minimal or missing failure treatment. | A failed read can look like absence or leave a blank view. | Design empty, loading, stale, corrupt and failed states independently. Error copy offers a useful next step, not an error code. |
| Setup offers a fixed two-minute reminder and labels config presence as Connected; both Claude and Codex appear. | The first task is a demo, and connection success can be overstated. | Let the user set one real reminder, show its saved date, and confirm Claude with a live first event. Offer the clean no-AI path. Codex remains Beta in Agents settings. |
| Existing semantic buttons, shared states, native dialog focus trapping and explicit permission choices are present. | Useful trust and accessibility foundations already exist. | Retain them while replacing layout and components. |

## Scope and truth

The founder's current brief opens visual exploration, including a different shell or token proposal. It does not make unimplemented features real. The handoff must clearly identify proposals and runtime dependencies. Apply changes to `docs/V1.md` through its change process before implementation where the accepted visual direction departs from the release contract.

Keep the existing Pip Signal mark as the production identity unless the final design direction explicitly proposes a replacement. Retain Pip and Spark, their existing 3D clay identity, and `src/states.ts` words: Idle, Thinking, Working, Needs you, Done, Failed, Asleep. A status fill never carries meaning alone. Do not show work signals while idle or successful log/reminder actions before disk acknowledgement.

The calm path has Today, Reminders and Work log. No hook, MCP, terminal or command language appears in its setup, Quick add or daily content. Sessions appear after Claude is connected. Do not add task boards, streaks, productivity scores, a chat feed or an internal terminal to make the app seem more substantial.

## Required visual coverage

Each primary reference image should be paired with a behavior note or working prototype state. Beautiful happy-path images alone are insufficient to implement this product.

| Surface | Canonical image or prototype state | Required variants and edge states |
|---|---|---|
| Today | A realistic day with one overdue reminder, one waiting request, two due today and recent work | No agent connected; completely new account; quiet populated day; all caught up; >3 pending requests; corrupt data notice; connection failure; stale data |
| Quick add | Reminder draft with explicit resolved local date and time | Note → Log destination; named notebook choice; ambiguous hour; past date-only time; unsupported repeat; unrecognized text → note draft; save pending/failure; saved with Move/Undo; open app preview |
| Reminders | Upcoming list grouped by overdue/today/tomorrow/later | Repeating; completed; empty filter; 300-character title; changing time zone; queued late reminders; disabled notifications; Skip next and snoozed occurrence; detail history |
| Reminder sheet | Populated one-off editor with date, time, zone and resolved date | Repeat rule; multiple weekdays; every N days/weeks; monthly impossible-date policy; this occurrence vs future series; invalid date/blank title; save failure retaining fields |
| Work log | All entries stream with week grouping and named notebook destination | Log inbox; notebook detail/list pair; date/project filters; text search/no matches; 2,000-character entry; edit; Move; create/rename notebook; unreadable notebook; capture preserved during incoming note |
| Your week | Dated notes and completed reminders with Copy as Markdown | Empty week; previous week; copy success/failure; no AI affordance |
| Sessions | Live sessions plus recent outcomes, project + first prompt line + host | Two same-project sessions; long project name; failed outcome; ended session Continue; running session Open; supported/inexact host copy; Log it draft; no live sessions |
| Request review | Exact command/diff/content with clear session identity and explicit buttons | Long operation unread; full operation read; >50,000 chars unavailable; flagged command; several requests; sending; sent; failed send/Retry; released; timed out; moved to terminal |
| Overlay | Pip with compact request card and tail | Reminder; short request; long request → Review all of it; question/free text; done/failed queued behind request; Quiet; asleep; Spark equivalent; card near screen edge; large text; reduced motion |
| Setup | Useful reminder entry, native notification result, optional Claude setup | Permission denied; reminder save failure; skip AI tools; waiting for first live event; repair; completion with saved reminder visible |
| Settings | Four-pane sidebar: General, Companion, Agents, Privacy & data | Both looks, both themes/system; Quiet; reduce motion/large text; disconnected/waiting/working/repair/port failure; Beta explicitly labeled; report preview/redaction; export; disconnect/uninstall keeping data by default |
| Menu bar | Compact menu, exact status word where applicable | Show/Hide companion, Quick add, Pause/Resume answers, Quit; no hidden decision implied |

Use realistic, fixed fixture dates in image labels so Today, weekday and time remain internally consistent. Artwork must not silently claim P2/P3 capabilities already work in the current runtime.

## Layout and window behavior

Current native window: 1100 × 760 logical pixels, minimum 640 × 480 (`src-tauri/src/prefs.rs`). The existing 720/960 px breakpoints are implementation history, not a guarantee of correct new layouts.

| Test size | Expected composition |
|---|---|
| 1280 × 900 | Expanded app with legible maximum reading width; do not stretch note paragraphs or raw request text across the entire window |
| 1100 × 760 | Primary design target; Today can have supporting context, and Work log may show its notebook list/detail pair |
| 900 × 680 | Collapse optional supporting rail; keep the primary action and selected destination visible |
| 640 × 480 | Compact nav/menu with current destination label; single content column; no horizontal document scrolling; sheets scroll with reachable actions; no clipped error message |
| Every size with large text | Reflow and allow vertical growth; no fixed-height rows that truncate essential information |

Keep native traffic-light clearance and a deliberate draggable region; never put an invisible drag layer over a control. Native Settings must be a separate ⌘, destination per V1-U4; don't build a second broad app nav inside a settings page or a "Back to Sidefolk" control. Page scroll and nested raw-operation scroll are distinct. Make the latter keyboard reachable and visibly labeled. A topbar or footer must not cover the final line of content or a focused control.

For desktop controls, V1-U7 prescribes a 24–28 px visual/control height. Use the 28 px end for ordinary interaction, preserve spacing between adjacent targets, and retain the 44 px overlay target. Do not shrink hit areas further to make dense reference images fit. Larger text can increase control height. Add any new compact size tokens to a central specification, rather than multiplying one-off pixel values in screen CSS.

## Accessibility and interaction contract

These are acceptance targets. A visual audit cannot certify screen-reader or native keyboard behavior.

1. **Names and landmarks.** Use a nav landmark, one main heading, sections with meaningful labels, real buttons and persistent input labels. Repeated actions include the item name: "Complete Call mom", "Reminder actions for Call mom". Decorative Pip portraits have empty alt; the interactive companion has an accessible name plus state.
2. **Focus.** Navigation focuses the new heading; Quick add invocation focuses its field; the second shortcut focuses the newest card. Opening a sheet records the trigger. Closing it returns to that trigger, the next surviving row, or the destination heading. An incoming event never steals focus. Saving/failed saves keep a usable focused control; deletion never leaves focus on BODY.
3. **Keyboard.** Every workflow completes with Tab/Shift-Tab, Enter/Space and Escape. Menus support arrows, Home/End and Escape, or use an appropriate platform popup. A row cannot be a nested button containing other buttons. Native `<dialog>` remains a good sheet foundation. Menu dismissal returns to its trigger.
4. **Text and contrast.** The final semantic foreground/background pairs must be measured in both themes. Target at least 4.5:1 for ordinary text and 3:1 for required control outlines, focus indicators and meaningful icons; pale separators may be decorative. Preserve charcoal text on mint. A muted style must stay readable, including timestamps and disabled explanations. Do not use reduced opacity on an entire important state block.
5. **No color-only meanings.** Status is icon plus word. Selection has semantic current/selected state; invalid fields have text and field association. The brand dot is not live status. A request's dangerousness never depends on orange alone.
6. **Announcements.** Save outcome is a polite status; failure is a concise alert with recovery. Do not announce every countdown tick or every streaming status update. Announce request arrival once, expiry once and answer result once. Avoid whole-page live regions.
7. **Motion.** Reduced motion removes entrance translation, pulse and companion hop, while preserving the state word. No movement continues behind a request the user is reading. No essential content relies on animation.
8. **Undo.** Mutation Undo remains until dismissed; ⌘Z resolves the latest eligible action. Do not shadow text-field Undo. If a second mutation arrives, preserve previous undo information through a deliberate queue/history behavior.
9. **Text stress.** Test long project/notebook names, identical names, Unicode, punctuation, multi-line user content and narrow windows. Wrap human text; preserve exact tool-input whitespace and show control/bidi escapes. Never hide the meaningful end of a command behind an ellipsis.

## Request review: the most important regression boundary

The redesign must preserve `src-tauri/src/requests.rs` as authority. A card is a view of an immutable operation, not a policy engine.

| State | Visible action contract |
|---|---|
| Short complete operation | Allow once, Decline, Answer in terminal; no automatic answer and no destructive shortcut as Enter default |
| Operation longer than overlay card | Review all of it; no overlay Allow |
| Long review, unseen content | Allow once disabled with an explanation tied to the operation; users can reach/scroll content by keyboard |
| Entire display presented | Enable Allow only while still waiting; the Rust decision path checks liveness again |
| Cannot display complete operation | Answer in terminal + Open; no Allow |
| Flagged command | Warning is advisory; Decline is the default, never Allow |
| Sending | Lock competing answers, retain operation and identity, show Sending your answer… |
| Sent | Show precise result only after acknowledgement; keep readable content and return destination |
| Connection lost | State that answer was not sent; Retry only if request still live |
| Expired/released/focused in terminal | Remove or disable answer controls and explain where the decision moved; Open remains a navigation action |

Do not disguise the approximately one-minute hold as an urgent progress bar. Explain: "Claude waits about a minute, then asks in your terminal." Open/Answer in terminal releases the request; closing the view does not answer. Do not add "always allow", session-wide permissions or cosmetic risk scores. Session identity is project, first prompt line and host; a four-character ID alone is insufficient.

## Developer file map

File names below are current integration points, not an instruction to overhaul the app in this design task.

| Area | Current files | Intended developer change |
|---|---|---|
| Tokens/theme | `src/tokens.css`, `src/theme.ts` | Semantic compact-window tokens, explicit dark theme pairs, accessibility/motion variants; preserve shared overlay meanings |
| Kit | `src/dashboard/dom.ts`, `ui.ts`, `dialog.ts` | Small typed primitives: button, row, field, popup/menu, segmented control, toggle, sheet, persistent toast/Undo, data-state shell |
| Styles | `dashboard.css`, `redesign.css`, `settings.html` | One component stylesheet imports tokens; remove obsolete cascade and dead terminal styles after migration |
| Shell/routing | `src/dashboard/app.ts`, `src-tauri/src/prefs.rs`, native menu/tray | New navigation, distinct Settings window, predictable focus and data refresh, safe traffic-light/drag regions |
| Daily surface | `src/dashboard/home.ts` | Contract order, useful no-agent day, no decorative metrics, progressive context |
| Capture | `src/dashboard/tell.ts`, `src/commands.ts`, `src/when.ts` | Shared preview/draft choice behavior, true destination/date, complete on starting surface |
| Reminders | `src/dashboard/reminders.ts`, `src/reminders.ts`, Rust reminder engine | Render new rows/sheet only after recurrence authority supports the advertised states |
| Work log | `src/dashboard/notes.ts`, `src/notes.ts` and journal commands | Log inbox, timeline, notebook pair, Move/date search, preserved drafts, plain Markdown export |
| Sessions/review | `src/dashboard/sessions.ts`, `requests.ts`, `ui.ts`, Rust request/session APIs | Better identity and hierarchy; no relaxation of raw-operation display or lifecycle guards |
| Setup/settings | `src/dashboard/setup.ts`, `settings.ts`, `notifications.ts` | Three useful setup steps, live connection proof, four settings panes and truthful native permission results |
| Overlay | `src/pip.ts` and existing bubble/card modules | Shared cards/tokens, tail toward current companion, keyboard/VoiceOver path, all look/size variants |
| Verification | `src/dashboard/dashboard.test.ts`, `scripts/webkit-check.mjs` | Behavioral fixtures and all-window state runs, both themes, small window, reduced motion, large text |

## Recommended implementation sequence

1. Accept the visual direction and record any V1 deviations. Separate designed-for-v1 content from implemented runtime state.
2. Finish the state authority the runtime already plans for P2/P3; do not encode reminder recurrence or request policy in visual components.
3. Build a kit specimen page first: all controls and data states, light/dark, compact/large text, focus and disabled states. Measure contrast here.
4. Implement shell and Today as the first complete vertical slice, including calm/no-agent path, Quick add, error recovery and persistent Undo.
5. Migrate Reminders and Work log using shared rows, fields, menus and sheets. Add rich behavior only where backend authority is ready.
6. Migrate Sessions and review against existing permission lifecycle fixtures; then unify overlay styling. Native focus/terminal routing needs the user's hand check.
7. Implement Settings/setup and remove old CSS. Run the existing checks, inspect only the changed views more deeply, and record open hand checks. Follow WIP = 1, and never mark a release gate passed on behalf of the founder.

## Acceptance checklist for the final design package

- [ ] A reviewer can identify Sidefolk from a screen without relying on a huge mascot or logo.
- [ ] Today answers "What needs me? What is next? What did I get done?" in that order.
- [ ] No-agent screens stand alone and contain no developer vocabulary.
- [ ] Every image labels its intended theme, dimensions and fixture state; unimplemented behavior is explicit.
- [ ] Window and overlay densities are distinct and specified; ≤2 visible actions per list row.
- [ ] At least one compact-window layout and one dark canonical screen are supplied.
- [ ] Component board covers hover, focus, pressed, selected, disabled, pending and error states.
- [ ] Empty/loading/stale/error/corrupt data designs are not interchangeable.
- [ ] Long content, recurrence ambiguities, request expiry and Undo are designed, not left to developer guesswork.
- [ ] Pip and Spark each have a complete card/portrait treatment using existing approved assets.
- [ ] Asset manifest identifies editable masters, raster exports, dimensions, transparency, and intended placement.
- [ ] Implementation mapping preserves existing data and tests; no gate is claimed passed by design review.

After implementation, run `npm run typecheck`, `npm test`, `npm run check:webkit` with the preview running, and `npm run web:build`. Extend meaningful browser checks for focus, draft preservation, stale/error distinction, persistent Undo and request state changes. Native VoiceOver, Spaces, notification delivery, traffic lights, menu/shortcut behavior, and terminal handoff require app hand checks and must remain listed as unverified until performed.
