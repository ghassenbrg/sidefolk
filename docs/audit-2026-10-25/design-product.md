# Jun — senior Mac UI designer: independent Sidefolk audit

25 October 2026 · Jun seat · Independent review for the Codex council

## Decision

**Keep the foundation and current visual system. Do not restart the application. Release a smaller, more dependable product before adding breadth.** The preferred first public release is **A: a local desktop companion for reminders and dated notes, with a narrowly scoped, optional AI session feature that earns its own release gate**. Developer-first positioning is a credible alternative for a private beta, but the current evidence does not establish that its setup and session return flows are ready to carry the entire first experience. A broad “assistant that can do everything” release is the weakest option.

The interface is much calmer than the earlier product plans describe. Its main problem is no longer an obviously ugly shell. The central risks are promises that exceed verified behavior, completing one task across two disconnected surfaces, and a large scope whose operational reliability has not been established by browser previews.

This is expert analysis, not user research. Jun is the assigned senior Mac UI design perspective. The product, creative and accessibility observations below are cross-seat recommendations from this review, not substitutes for those seats' independent votes. No usability conversion rates or user satisfaction scores are claimed.

## Evidence and limits

Read: `AGENTS.md`, current memory status/decisions/learnings, `docs/PLAN-V2.md`, `docs/GUIDE.md`, approved review package and design system, frontend shell/setup/home/settings/reminder/note/action/session/request code, reminder and command behavior, and relevant integration state sources. Inspected existing browser screenshots in `output/playwright/redesign/`, including light Home, Reminders, Settings, Review, Notebook and overlay permission card.

Those screenshots are prior browser captures from 24 October, not fresh native verification, and some show the previous character artwork. Current source is used to qualify them. This reviewer did not capture the native desktop, invoke a model, change global configuration, implement features, run native interactions or claim accessibility conformance. Native notifications, macOS permissions, screen-reader behavior, tray-only operation, multi-monitor overlays and actual session reopening remain unverified here. The parent council owns current test execution and browser exploration.

Severity: **P1** = resolve before broad public release of the affected feature; **P2** = significant friction or incomplete product behavior; **P3** = refinement. Confidence distinguishes a directly visible source behavior from an inferred user consequence. A P1 product issue is not necessarily a security vulnerability.

## Jun's cross-cutting design lenses

| Council lens | Judgment | What this perspective would protect |
|---|---|---|
| Product strategist | There are two products competing for the same home: personal capture and developer orchestration. Ship one clear promise with an optional extension. | A person can describe the value in one sentence and achieve it without learning the other product. |
| Senior UX designer | The approved shell, labels and list-first flows are sound. Cross-surface completion and inconsistent errors matter more than another layout redesign. | A task begun in the app finishes in the app; state changes remain legible and recoverable. |
| Creative/art director | The warm cream, mint and charcoal identity is coherent and distinctive. The disciplined UI lets character personality work. More characters and decorative changes have diminishing value now. | Keep the exact logo and restrained system. Judge characters at their real desktop size and in all functional states. |
| Accessibility advocate | Tokens, real controls, focus rings, reduced motion and larger text are useful foundations. They do not prove that the overlay or all custom control behavior works with assistive technology. | A keyboard and VoiceOver user can perform the same core task, including recovery, without the companion being visible. |

A simulated first-time nontechnical perspective predicts that “Tell Pip…” will be understood as open-ended conversation, that a daily reminder will appear daily without needing yesterday's completion, and that clicking a button in the window will finish the task there. Those predictions must be tested with actual people. A simulated experienced developer perspective appreciates exact commands and project labels but is likely to distrust “Full access” assurances and “Connected” badges that do not show operational health. A simulated older/low-vision user perspective values larger text and labelled actions, but the dense reminder action row and transient Undo need direct testing. These are hypotheses, not statements about all older or nontechnical users.

## What already works well

1. **The new hierarchy is comprehensible.** Today, Reminders and Notes precede conditional Sessions. Actions and Settings are secondary. AI navigation is conditional rather than required (`src/dashboard/app.ts:259`, `src/dashboard/app.ts:270`). This follows the latest approved everyday-first direction.
2. **The everyday features do not require model setup.** Local parsing and Markdown notes support a useful account-free experience. The notebook is a concrete, understandable container rather than an abstract “memory” (`src/commands.ts:57`, `src/dashboard/notes.ts:15`).
3. **The design language is disciplined.** Shared colors, spacing, system typography, 44 px target token, text-and-icon statuses and controlled mint emphasis are visible in code and browser captures (`src/tokens.css:4`, `src/tokens.css:31`, `src/tokens.css:43`, `src/states.ts`). This is worth retaining.
4. **Structured forms complement natural language.** Reminder date/time labels, the resolved timezone, inline validation, loading guards and undo make the feature more approachable than a parser-only interface (`src/dashboard/reminders.ts:32`, `src/dashboard/reminders.ts:62`, `src/dashboard/reminders.ts:85`, `src/dashboard/reminders.ts:128`).
5. **Request review preserves identity and actual action.** Project, tool, session, command and working folder are present. Expiry, explicit choices, sending state, failed state and retry receive dedicated treatment (`src/dashboard/requests.ts:78`, `src/dashboard/requests.ts:90`, `src/dashboard/requests.ts:94`, `src/dashboard/requests.ts:134`). This is stronger than many pet-style notification concepts.
6. **Settings is a real findable place.** Search, categorized configuration, system/light/dark selection and plain descriptions are useful. Avoid dismantling this because nine categories sound like a large number in a document (`src/dashboard/settings.ts:326`, `src/dashboard/settings.ts:386`).
7. **Accessibility intent is embedded.** Native HTML dialogs, label associations, focus restoration, polite status messages, reduced motion and narrow layout handling are all present (`src/dashboard/dialog.ts:3`, `settings.html:16`, `src/dashboard/redesign.css:115`). They need behavioral verification, not replacement by another component library.

## Findings to resolve

### DP-01 — A task begun in the window can require finding the desktop pet to finish

**P1 · high confidence in source; native visibility impact requires hand check.**

The window's Tell bar confirms shell commands and session creation in a local sheet, but delegates other commands to the overlay (`src/dashboard/tell.ts:36`, `src/dashboard/tell.ts:39`). A natural-language reminder creates its Save/Change preview through `companion.pet.bubble` and replies “Review the reminder on the companion” (`src/reminders.ts:82`, `src/reminders.ts:94`). Selecting a notebook or creating an unknown notebook also opens bubble-only choices (`src/notes.ts:101`, `src/notes.ts:118`). These intermediate drafts are not the durable request queue created by `Companion.request`.

Consequences: a person types in one surface, receives a short toast, then must discover another surface and decide whether the task was saved. The experience is particularly questionable with the companion hidden, on a different display or occluded by the window. This is a source-grounded risk, not a claim that all hidden companion states were reproduced.

**Recommendation:** return a structured draft from the shared command service; render its confirmation on the originating surface. Share domain behavior, not the physical bubble. Show the exact resolved reminder and destination notebook there, keep text on failure/cancel, and provide a durable “Saved” result linked to the object. Core window operations must work with the overlay unavailable.

### DP-02 — “Repeating reminder” has completion-dependent semantics that users may not expect

**P1 product-contract decision · high confidence.**

The reminder fires once and its `fired` state suppresses subsequent checks. A repeat advances only on Done (`src/reminders.ts:183`, `src/reminders.ts:232`). The settings explanation and guide acknowledge this (`src/dashboard/notifications.ts:17`, `docs/GUIDE.md:15`); the creation form simply says “Every day” or “Weekly” and “then every…” (`src/dashboard/reminders.ts:36`, `src/dashboard/reminders.ts:62`).

For a daily “check mail” alert, ignoring Monday may mean no new Tuesday occurrence until Monday is completed. That can be a deliberate recurring-task model, but it conflicts with a common repeating-alert mental model. Copy in Settings is too far from the decision.

**Recommendation:** decide explicitly between recurring tasks and independently scheduled recurring alerts. Prefer alerts advancing on schedule, while preserving unfinished occurrences without producing an unbounded backlog. If v1 keeps the current model, call it out beside Repeat, show “Next scheduled after you mark this done”, and verify that real users predict it correctly. Do not advertise general recurring reminders before this decision and native repeat/quit/sleep checks pass.

### DP-03 — Permission UI offers stronger reassurance than a finite heuristic supports

**P1 for public release of delegation · high confidence in wording; security exploitability belongs to technical review.**

A session row switches directly between “Asks first” and “Full access”, then says “Risky commands still ask” (`src/dashboard/ui.ts:108`). The visible risk filter is a finite list of command regular expressions and returns no reason to ask for non-command actions (`src/access.ts:9`, `src/access.ts:22`). The guide repeats the broad assurance (`docs/GUIDE.md:70`). The overlay permission screenshot also places “Allow everything from this session” in the decision flow.

The UI can encourage a person who cannot assess commands to treat this as a general safety guarantee. “Full access” may also represent different native tool modes, not just this app's filter. A friendly pet amplifies the need for literal language.

**Recommendation:** remove this from the everyday v1 flow. Before it returns, define exactly what authority is granted, which tool owns it, persistence/expiry, and how to revoke it. A separate review should name the session/project and state that Sidefolk cannot identify every dangerous action. Prefer preserving the tool's approval model rather than creating an extra reassurance layer. Do not merely lengthen a tooltip.

### DP-04 — Saved-list and initial-load failures are not consistently distinguishable from empty state

**P1 for core data screens; P2 for optional tools · high confidence.**

Actions converts a load failure into an empty array, then reports “No actions yet” (`src/dashboard/actions.ts:21`). Custom character loading does the same (`src/dashboard/characters.ts:20`). Notes begins an asynchronous list request without a local loading/error/retry surface (`src/dashboard/notes.ts:40`). Calendar errors on Today are swallowed (`src/dashboard/home.ts:79`). The app periodically calls refresh without a user-facing connection state (`src/dashboard/app.ts:99`, `src/dashboard/app.ts:326`).

“No data” and “couldn't read your data” are very different statements. This affects trust more than button styling does.

**Recommendation:** establish the same explicit states on every data surface: loading, loaded empty, loaded content, unavailable/stale, and recoverable failure with Retry. Keep the last successful data visible when refresh fails and label it stale. Prefer plain recovery text over raw Rust/OS error strings alone. A filesystem permission/read error must not look like deletion.

### DP-05 — Notebook ambiguity can silently file a note in the wrong place

**P1 for notes-as-memory promise · high confidence.**

Exact notebook matches win, but a prefix matching multiple notebooks falls back to whichever was updated most recently (`src/notes.ts:23`). “Evaluation” can therefore resolve differently as “Evaluation H1” and “Evaluation H2” receive new entries. The user sees “Noted in…” afterwards, but a transient confirmation is a weak safeguard for six months of accumulated notes.

**Recommendation:** ambiguous matches must open an explicit destination chooser on the initiating surface. Preserve the note, include an always-visible destination on capture, and support Move entry as recovery. Exact names and IDs may remain immediate. Validate this with two similarly named notebooks, not one ideal sample notebook.

### DP-06 — “Connected” describes installation state, not demonstrated capability or health

**P1 for AI feature claims; P2 if clearly an opt-in beta · high confidence.**

The status fields use installer/config checks (`src-tauri/src/prefs.rs:198`), while setup calls these states “Connected” (`src/dashboard/setup.ts:56`) and Settings also badges them “Connected” (`src/dashboard/settings.ts:97`). Claude hooks and Codex companion tools have different capabilities; the setup labels partly acknowledge this, but there is no common “last activity seen / send test / needs reconnect” model.

**Recommendation:** distinguish Installed, Activity confirmed and Needs attention. Show the actual capability: “Follow Claude Code sessions” versus “Let Codex send notes and questions”. After setup, provide a tiny non-model connection test and a real-session verification checklist. A configured integration must not imply all external sessions are being watched. If terminal/tab selection is best effort, the Open action must say what it can actually bring forward.

### DP-07 — The natural-language interface has an unnecessarily broad implied contract

**P2 · high confidence.**

“Tell Pip…” looks like chat. The command grammar is intentionally finite (`src/commands.ts:57`). Unknown text explains that it is not recognized (`src/commands.ts:164`), which is honest; however a saved action name goes through that same unknown parsing branch before being recognized at execution (`src/companion.ts:398`). The preview can say it does not understand a valid saved action. The field also has no visible submit button; its keyboard hint appears only after typing (`src/dashboard/tell.ts:14`).

**Recommendation:** describe the field as quick capture, keep examples visible on first use and add a labelled submit control. Show current supported capabilities without claiming open-ended intelligence. Resolve saved actions before explaining execution. Unsupported text should offer “Make a reminder / Save as note / Cancel” with the original text preserved, not silently call AI or dead-end.

### DP-08 — Core list actions are visually and cognitively busier than they need to be

**P2 · visual judgment supported by source and browser capture.**

Each reminder row offers Open, Snooze 10 min, Edit, Delete and Mark complete (`src/dashboard/reminders.ts:190`). This is manageable for two sample reminders; twenty rows repeat a large number of actions and place deletion in the same scan path as frequent actions. Completed reminders are silently limited to five (`src/dashboard/reminders.ts:149`).

**Recommendation:** make the row/title open details; keep completion and a labelled Snooze as primary row actions; place edit/delete in details or a clearly labelled More menu. Show overdue as a factual status without visual pressure. Offer useful snooze choices consistently in window and overlay. Provide Show more/history instead of presenting five completed items as the entire record. Validate with 30 mixed overdue/repeating/completed reminders and 200% text.

### DP-09 — Accessibility foundations have specific unfinished behavior

**P2; promote to P1 if a core journey fails native keyboard/VoiceOver checks · high confidence in code gap, impact unverified.**

The custom segmented groups use `role=radio` on ordinary buttons but do not implement radio arrow-key behavior or roving tab stops (`src/dashboard/settings.ts:56`). Other theme/character choices correctly use actual radio inputs. Notes headings arrive asynchronously after initial focus navigation (`src/dashboard/notes.ts:35`, `src/dashboard/app.ts:245`), so a screen-reader navigation announcement may be missed. Changing settings forces redraw and some selects blur themselves (`src/dashboard/settings.ts:49`, `src/dashboard/app.ts:135`). Toasts containing Undo disappear after nine seconds (`src/dashboard/app.ts:117`).

**Recommendation:** use native radio inputs, preserve meaningful focus after async content and settings changes, and provide durable recovery for deleted notes/reminders instead of a timer as the only accessible route. Test from a fresh install with VoiceOver, keyboard only, larger text, OS reduced motion, both themes and the companion hidden. Include native tray and notification entry points. Good contrast tokens and a passing DOM scan are not sufficient evidence.

### DP-10 — Actions and summaries need an explicit place in the first release

**P2 scope/operability · high confidence.**

Actions defaults to a shell command with a deploy example; its list exposes Run quietly and Run in terminal (`src/dashboard/actions.ts:27`, `src/dashboard/actions.ts:84`). It has removal but no evident edit flow. The summary feature does explain what it sends and plan quota, which is good, but its result exists in a temporary panel with Copy/Close rather than a saved artifact (`src/dashboard/notes.ts:348`, `src/dashboard/notes.ts:375`).

**Recommendation:** do not make shell execution a default nontechnical destination. For v1 either hide Actions behind an advanced preference or restrict everyday shortcuts to saved links/folders, retaining command actions for an explicit developer extension. Keep summary as optional beta until cancellation, retry, saved output and longer-run handling are verified. Do not add a full writing workspace to solve this now.

### DP-11 — Companion identity is not consistently represented in the window

**P2 for multiple-project use; P3 for one companion · high confidence.**

Request identities always render the same brand mark (`src/dashboard/ui.ts:21`) and the shell's picture helper falls back to Pip for custom imported characters (`src/roster.ts:34`). The names/project labels are a good safety baseline, but a user who chose a different character sees a weaker match between the desktop source and its request row. “Use for Pip” remains hardcoded after the companion has been renamed (`src/dashboard/characters.ts:55`).

**Recommendation:** preserve the logo as brand identity, but use actual companion thumbnails and project labels in functional identities. Say “Use as my companion” or the saved name. Before releasing multiple companions, test whether people can associate two concurrent requests with their correct project without relying on color or knowing “Spark” terminology.

### DP-12 — Decision history and release truth need one maintained owner

**P2 governance issue; release risk rather than direct UI defect · high confidence.**

`docs/PLAN-V2.md` begins “nothing here is built yet” but later marks phases built; older design docs describe a five-destination UI while the approved redesign uses Today/Reminders/Notes/optional Sessions/Actions. The newest memory status explains supersession, but a new collaborator has to reconcile several competing truths. This increases the chance that the next development turn rebuilds a solved concept or calls an unverified native feature complete.

**Recommendation:** create one current release contract: shipped scope, actual supported OS/tool behavior, known limitations, test evidence, pending native checks and beta exclusions. Mark older plans as historical with a pointer. Preserve decision history but give it a clear latest-authoritative index. New ideas belong in a parking lot until the current release gates pass.

## Visual and creative assessment

The inspected light-theme browser captures look like one coherent product. The cream background, restrained mint, strong charcoal headings, familiar system font, icon/label navigation, unambiguous cards and generous spacing are effective. It is reasonable to call this polished enough for a **visual beta**, subject to current capture/native review. It is not reasonable to equate polished screenshots with release readiness.

The weakest visual moments are consequences of information structure: a review screen repeats Sessions and the selected request in several places; the decision buttons can fall below the first viewport; notebook navigation creates two sidebars; reminder rows repeatedly display five actions. These call for targeted hierarchy and density work. They do not justify throwing away the palette, logo or component language.

Keep the current production logo exactly. Preserve existing approved characters; there is no product reason to delete them or reverse the user's artwork choice. Keep them behind one Companion page, freeze new variants and customizer expansion, and test one default Pip plus one worker at actual size. Review alert/note/sleep/done states on light and dark wallpapers, at the smallest supported size and with reduced motion. Sprite pose switching is a valid art choice if it reads well; it should not be marketed as full real-time 3D animation. More art does not resolve permission or reminder reliability.

## The three viable product versions

| Option | Public promise | Benefit | Main risk | Council recommendation |
|---|---|---|---|---|
| **A — Everyday companion** | “A small desktop companion for reminders and dated notes.” Optional AI extension only when supported. | Matches the latest stated priorities; works without setup/quota; coherent quick-capture habit. | Reminder/notes tools already exist; the desktop character must add useful presence without becoming distracting. | **Preferred v1. Validate retention before expanding.** |
| **B — Developer session companion** | “Know when your AI coding sessions need you, and get back to the right one.” Reminders/notes secondary. | Clearest specialized differentiation; existing integrations are valuable foundation. | Installation, changing vendor protocols, permissions and exact-session reopening dominate reliability. | Good private developer beta if a real multi-session cohort proves the loop; acceptable fallback if A has weak repeated use. |
| **C — Broad desktop assistant** | Reminders, notes, calendar, commands, terminals, summaries, characters, project workers and approval authority. | Impressive demo breadth; serves the builder's own workflows. | Multiple mental models, broad test matrix, higher trust burden and unclear reason to return. | **Reject for first public release.** Preserve useful code, keep advanced features out of the primary promise. |

The distinction between A and B is the first-screen promise, activation path, support commitment and metrics. It need not require two codebases or deletion of the other features. Do not claim both audiences equally served until evidence supports it.

## Concrete preferred v1 scope

**Ship as stable:** one companion by default; app/menu-bar/keyboard access; Today; reliable one-off reminders; explicitly defined repeat behavior; edit/complete/snooze/history; notebooks with dated capture, search/edit/move, understandable destination and Markdown export; system/light/dark; hide/show, quiet sound default with a preview; reduced motion/larger text; diagnostics and clear data location; signing/notarization and an actual update path.

**Keep behind optional, separately verified developer setup:** session state, request identity and return-to-source. Support only the tools/hosts actually exercised in native tests; describe best-effort focusing honestly. If permission answering is retained, it needs separate authority/recovery review and must preserve the source tool's semantics. Passive monitoring should still deliver value when approval answering is off.

**Freeze/defer from the public v1 promise:** blanket auto-approval, default command execution, background shell jobs, embedded terminal, AI drafts as a headline, calendar heads-up/morning/weekly automation as headline benefits, import-as-creation workflow and additional character/style work. Existing settings and data need not be destructively removed. Calendar and import may remain explicitly labelled opt-in beta if they neither complicate onboarding nor block the stable loop.

**Do not promise:** mobile sync, cloud backup, general chat intelligence, universal calendar integration, guaranteed session/tab targeting, universal screen-share privacy, or complete dangerous-command detection.

## Roadmap expressed as release gates

| Gate | Work | Required evidence to leave the gate |
|---|---|---|
| 0. Product contract | Pick A or B; write one-sentence promise, stable/beta/deferred inventory, repeat semantics and privacy/authority wording. | A new tester can explain what it does and what it does not do after reading the first screen; no contradictory shipping claims. |
| 1. One complete core loop | Same-surface capture/review/save; robust list loading/retry; exact or explicitly chosen notebook; durable recovery; focus and keyboard repair. | Every core task works with the overlay hidden; failure injection never masquerades as empty data; text survives failed operations. |
| 2. Native dependability | Reminder delivery while visible/hidden/quit/sleep; denied notification permission; restart; timezone/DST/month-end repeats; upgrade with user data; companion/tray/window behavior. | Written end-to-end evidence on supported macOS versions; known limitations visible at the moment they matter; no claim based solely on sample previews. |
| 3. Human usability | Independent first-run tasks, accessibility sessions and a one-week pilot, before showing a tutorial or explaining “Spark”. | Thresholds below met or failures understood and fixed; a repeat round confirms the fix. |
| 4. Optional developer extension | Real tool setup/uninstall/reconnect, two similar concurrent projects, request expiry, lost connection, return to exact supported source, revoked authority. | A capability matrix backed by native runs. No “Connected” success inferred solely from config presence. Release without extension if it fails. |
| 5. Release operations | Signed/notarized distribution, clean install, update/rollback, data durability/recovery, support contact, diagnostic privacy review. | A tester outside the development machine installs, receives a real reminder, updates, finds existing notes and can submit a useful problem report. |

No calendar estimate should override these gates. The current code makes a short hardening cycle plausible, but there is insufficient evidence to promise a fixed number of days until public readiness.

## Actual user research plan

Recruit 6–8 people with different workflow needs: several Mac users who do not code or run AI CLIs, several developers who already run multiple AI sessions, at least one keyboard-focused/low-vision/VoiceOver participant and at least one person sensitive to desktop distraction. Age alone is not a substitute for accessibility or experience diversity. The builder should not coach; ask participants to think aloud and observe behavior. Get explicit consent before recording or collecting any diary data; notes can stay local and anonymized.

Use tasks without product terminology:

1. Install and explain what the application does, without being told the answer.
2. Make “call Alex tomorrow at 9” happen, then correct it to 9:30; verify where it was saved.
3. Create a weekday reminder, skip its first occurrence and predict what happens tomorrow.
4. Save a win into one of two similarly named notebooks, retrieve it, move/edit it and export it.
5. Hide the companion, capture something from the window, and finish without hunting for another surface.
6. Quit, reopen and recover from a denied notification permission or simulated data-read failure.
7. For developer participants only, connect their actual tool, distinguish two same-named repository folders, decline a request and return to the right work session. Ask them to explain the consequence of enabling broad authority before clicking it.
8. Complete the reminder and note journeys with keyboard only and VoiceOver where applicable.

Record completion without help, critical misunderstanding, recovery behavior, point of hesitation and task time. Proposed **decision targets**, not observed results: at least 80% complete each primary task unaided; zero wrong-project approvals or silently wrong notebook destinations; everyone can find and disable the companion/sound; everyone correctly predicts the documented repeat model after creation. Small samples provide directional evidence, not population statistics. Any dangerous misunderstanding blocks the affected feature even if aggregate completion looks good.

After first-run fixes, a 7-day diary should answer: did they return without reminders from the researcher; did the pet prevent a missed useful task; did it interrupt work; did they hide it permanently; which notebook grew; what native tool did it replace; would they keep it if the animation disappeared? These results should determine whether A remains the primary release or B becomes the sharper niche.

## Jun's final recommendation

Sidefolk has enough coherent UI and reusable behavior to deserve hardening, not another reset. The strongest release is smaller than the current feature inventory: a trusted capture-and-reminder companion, with developer capabilities admitted only when their own end-to-end behavior is demonstrated. Protect the quiet visual identity, remove accidental complexity from everyday paths, and make the next design work about trustworthy task completion and actual human evidence.
