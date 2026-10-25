# Maya-led black-box user council

Date: 2026-10-25, Asia/Tokyo. Seat: **Maya, nontechnical operations manager**. Supporting perspective checks: an older/low-confidence computer user, a busy working professional, and a developer who has never used Sidefolk.

These are independent simulated perspectives from one agent's task walkthrough, **not interviews, real participant research, or measured success rates**. The seat deliberately avoided application source, backend code, memory, plans, and the product guide. It read repository safety instructions, the Playwright skill, then used the existing browser preview. After forming the initial opinion and exploring the main window unaided, it read `scripts/webkit-check.mjs` only to discover safe preview setup/overlay entry points. That script exposed expected flows; subsequent observations are marked accordingly. No native desktop capture, native permission changes, global configuration edits, real command executions, live model calls, or commits occurred.

## Verdict

The main window is calm, coherent, and noticeably more polished than a rough developer utility. Basic reminder creation has clear fields, useful validation, an explicit time zone, and a useful undo. The companion artwork is appealing. This does not need a wholesale visual restart.

**Maya cannot yet recommend it as a general-purpose assistant for nontechnical people.** The interface mixes a personal reminder/notebook product, an AI session control center, a command launcher, and an expressive desktop pet. It introduces these together but does not make the boundaries between them sufficiently clear. This is principally a product positioning and interaction-design issue; adding more features would make it worse.

The strongest credible initial audience is people who already use Claude Code or Codex and want awareness and a clear route back to their work. The pet and lightweight reminders can support that job. A reminder-first release is another possible product, but it must prove why the desktop companion helps someone more than their existing reminders tool. The current interface attempts both propositions at once.

## Initial comprehension, recorded before reading product material

The initial URL was `http://127.0.0.1:1420/settings.html`, at 1280 × 720. It opened Today with sample data. This is a preview landing state, not evidence that an installed first launch skips onboarding.

- It looked like a personal productivity dashboard. Reminders and Notes were easier to understand than the AI controls.
- The large top field, `Tell Pip…`, suggested a conversational assistant. It gave no persistent indication of what was local, what required an AI tool, or what kinds of request it understood.
- `Needs you` was an effective priority cue. The request card clearly provided `Review request`.
- `Pip · api`, `Codex · Work session 04c1`, `Run a command?`, and `Needs you` made one request involve several identities and abstractions. An informed developer can decode them; a novice cannot tell who is asking or why.
- The small bunny in the navigation was appealing but did not explain how the desktop companion relates to the main window.

Evidence: `output/audit-2026-10-25/blackbox-first.png`.

## Task ledger

Seventeen task/check scenarios were attempted. Outcomes below describe the preview only. No percentages are reported because these are not independent participant trials.

| # | Task | Observed outcome |
|---|---|---|
| 1 | Understand Today without help | Priority clear; product purpose and Pip/AI relationship ambiguous. |
| 2 | Review a pending command | Found through `Review request`. Project and exact command shown. No plain-language purpose, consequence, or rationale in the initial card. |
| 3 | Allow the sample request once | `Allowed once. Sent to Codex.` appeared, buttons replaced by result. Good acknowledgement. Sample session still said `Needs you`; preview consistency issue requiring native verification. |
| 4 | Add a reminder with only its title | `Choose a date and a time.` appeared in an alert. Recoverable, comprehensible. |
| 5 | Recover and save the reminder | Date 2026-10-25, time 10:00 saved successfully; list and confirmation toast showed correct intended time and Undo. |
| 6 | Discover what the Tell bar understands | `Examples` expanded to reminder, note, open, and help strings. Clicking `help` filled the field and showed `↵ Show what I understand`; Enter gave preview forwarding feedback, so dashboard command execution was not evaluated as live behavior. |
| 7 | Find and read a notebook | Notes → Open was straightforward. Dated entries and capture area were clear. |
| 8 | Understand AI notebook summary privacy/cost | `Draft a summary…` disclosed that only this notebook's two notes go to the user's AI tool and use plan quota. Did not invoke the draft. This disclosure is strong. |
| 9 | Discover a saved action | Actions clearly showed a command and folder, with `Run quietly` and `Run in terminal`. Did not run the deployment sample. `New action` form was understandable to a developer, highly technical to Maya. |
| 10 | Find AI connection setup | Settings → AI tools explained backups and connected state. Distinction between Claude Code connection and `Companion tools for Claude Code` required careful reading. |
| 11 | Customize the companion | Settings → Companion offered named characters, accent, 3D/2D, size and name. Extensive choices; attractive but not necessary for understanding the core value. |
| 12 | Enlarge text and return to app | Larger text saved immediately. At 900 × 650, `Back to Sidefolk` was below the visible portion of the Settings sidebar. A scroll or keyboard journey is required. |
| 13 | Understand/change permission mode | Sessions → `Asks first` immediately became `Full access` with toast `Full access on. Risky commands still ask.` No explanation before the mode change. Native semantics not established. |
| 14 | Start a session | `New session` dialog showed tool, folder, Full access off, and `Start in terminal`. Did not start it. Explanation says `Works without asking`, then differentiates Claude auto mode and Codex sandbox. This conflicts in apparent meaning with the earlier risky-commands toast. |
| 15 | Complete onboarding (after preview-script discovery) | Three concise steps: try a two-minute reminder, desktop/shortcut, optional AI connection. Reminder saved. Navigation easy. Native notification, login, connection, and eventual reminder delivery were not tested. |
| 16 | Discover companion capabilities in overlay | Preview shortcut `c` opened Talk to Pip. `What can you do?` produced a help card, not an error. Good forgiving help trigger; card is a dense syntax list. |
| 17 | Capture a reminder and recover from unsupported request | `Remind me in 10 minutes to take a break` showed parsed title/time and Save/Change, then Undo. `What is the weather tomorrow?` produced `I can set reminders, run commands and open your work sessions. Type “help” to see how.` It closed the field and gave no clickable help/retry in that response. |

## Findings by urgency

### High: permission-mode action looks like an informational status

At `/settings.html` → Sessions, `Asks first` is styled next to status and Open/Review controls. Clicking to learn what it means immediately enables `Full access`. It is plausible that an inexperienced user would click to inspect the policy. The toast appears only after changing it. This is an observed interaction issue; it is not proof of a sandbox escape or an unauthorized live command.

Recommendation: use an explicit `Change permissions…` action leading to a short explanation of scope, duration, tool-specific behavior, and remaining prompts. Make mode clear as status. Changing mode must be an intentional choice. Use one truthful label across new and existing sessions; `Full access`, `Works without asking`, and `Risky commands still ask` currently create incompatible expectations without explanation.

Evidence: walkthrough of Sessions, plus `blackbox-sessions-large.png` showing the original `Asks first` control placement. Parent engineering reviewer was asked to verify production semantics.

### High: permission decision is inaccessible in the first viewport

At 1280 × 720 with default text, the command-review screenshot ends around the Technical details section. `Decline` and `Allow once` are below the fold. The page spends space on the repeated Sessions list, repeated request identity, `Request details`, `Review request`, and `A clear choice, for the right project.` before reaching the actual decision. A waiting user must scroll through a substantial amount of framing to act.

Recommendation: put request purpose, command/folder, and the decision within the initial supported window height. Keep session context available but reduce repetition. A sticky decision region is one option after verifying it never obscures content or changes meaning. Remove decorative explanatory copy that does not help make the decision.

Evidence: `blackbox-permission.png`. Browser automation scrolled to the actual button automatically; do not misinterpret the successful scripted click as human first-viewport discoverability.

### High: the interface promises a broader assistant than it explains

`Tell Pip…` is globally prominent. Overlay title is `Talk to Pip`. These are conversational cues. The system can recognize natural reminders and some help questions, which is good; however, recovery from a plausible general question tells the user to type another command after closing the input. Help is a long list of syntax strings, including sessions, Sparks, shell commands, and saved actions. Maya would need to learn the product's grammar before confidently predicting behavior.

Recommendation: add one concise capability boundary near capture, then provide task choices and suggested continuations. Unsupported requests should retain the text and offer `See examples` / `Try again` directly. Explain when anything goes to an AI tool before the user sends it. Test whether a task-oriented capture label communicates the product better than chat language.

Evidence: `blackbox-weather-recovery.png`, `blackbox-unknown-question.png`. Dashboard `help` only produced preview forwarding, so the overlay provided the meaningful observed response.

### Medium: purpose and vocabulary are fragmented

The main window uses companion, Pip, work sessions, AI tools, project companions, and Spark. Companion settings say style applies to `every Spark`, and command-line help says a folder `gives it a Spark`. No definition was encountered before these uses. Project context is sometimes a short folder name (`api`) and sometimes a full path. Work session IDs consume scarce attention despite giving Maya little practical meaning.

Recommendation: pick one user-facing noun for each actual concept and introduce each at the first relevant moment. Prefer a human project/session title where available, with technical IDs secondary. Do not ask a novice to infer conceptual relationships from mascot names.

### Medium: the first-run story and everyday dashboard tell different stories

Onboarding is focused and friendly: reminders and dated notes, no AI needed; then optional AI connection. The dashboard immediately allocates substantial space to technical work sessions and a command permission request. This sample dashboard is not evidence of a fresh installed empty state, but it demonstrates why the product needs a declared audience and a matching demo/empty state.

Recommendation: make the first useful result match the audience promised on download. For a developer-focused v1, demonstrate agent working → needs attention → return safely to the right session. For a general companion, prove a reminder arrives and can be recovered before displaying advanced tools.

### Medium: Settings escape route gets lost at larger text

At 900 × 650 with Larger text, the Settings sidebar shows Accessibility and a clipped About & data near the bottom. `Back to Sidefolk` exists in the accessibility tree but is not visible without scrolling. Native browser navigation is not an appropriate fallback for a desktop settings window.

Recommendation: keep a persistent Back affordance at the top or outside the category scroll. Verify minimum supported desktop window sizes, longer text, keyboard-only navigation, and larger text together.

Evidence: `blackbox-large-text-900.png`. This is discoverability friction, not proof that the action is unreachable.

### Medium: helpful auxiliary features dilute the primary job

Notes, summaries, recurring reminders, saved shell actions, session management, own-character import, terminal choices, and several integration layers imply several products in one. Individually they are not inherently bad; collectively they require a lot of setup vocabulary before Sidefolk's unique benefit is obvious.

Recommendation: freeze feature expansion. Measure the chosen core loop first. Defer custom-character authoring, built-in terminal, and saved command launcher from the main v1 path unless actual target users demonstrate that they support adoption. Preserve current working implementation behind an advanced area if engineering cost favors that; deletion is not a usability goal.

## What to preserve

- Calm cream/mint visual system, coherent spacing, recognizable buttons, and companion artwork. The interface is not generally ugly.
- `Needs you`, clear project/agent labeling, and explicit one-time request answers.
- Reminder field validation, time-zone disclosure, parsed-time confirmation, Change, and Undo.
- Three-step onboarding and an immediate optional local action.
- Notebook summary disclosure: data scope and quota explained before invocation.
- Reduced-motion and larger-text controls, with their behavior plainly described.

## Perspective checks

**Maya, nontechnical operations manager:** likely comfortable with reminders/notes, uncomfortable deciding whether arbitrary shell commands are appropriate. AI setup assumes she has an installed developer CLI and understands its role. Would ask “Why do I need this over Reminders, and is Pip an AI I can ask anything?” Recommendation: do not market broad assistance until the capability boundary and everyday benefit are clear.

**Older or low-confidence user:** would benefit from labels, calm layout, optional connection, larger text and a reversible reminder. The shortcut is difficult to remember; hidden Back, terminal references, and grammar-heavy help increase anxiety. This perspective is a cognitive-accessibility hypothesis, not a claim about age determining computer skill.

**Busy working professional:** Today priority is useful. Repeated session context, lengthy command-review framing, and decisions below the fold slow the moment that matters. Needs quiet defaults, an obvious way to pause interruptions, and trustworthy reminder delivery. Delivery/quiet behavior was not verified here.

**Developer new to Sidefolk:** can understand most content quickly and may value session awareness. Needs precise integration status, session identity, permission semantics, and recovery more than another note system or launcher. The product may be useful as a developer beta once native end-to-end reliability is established by other council seats.

## Recommended v1 contract

Suggested release promise: **A small desktop companion that shows when your coding agents need you and brings you back to the right work.** Lightweight reminders are a supporting feature.

1. One short first-run path: see the companion, connect a supported agent with a clear reversible explanation, simulate an attention request safely, return to the correct tool. Do not make a live paid model call necessary to learn the app.
2. One coherent home: current agent state, requests needing attention, recent useful outcomes, and a clear route back. Keep repetitive session identity secondary.
3. Trustworthy request review: exact origin, project, understandable intent where available, inspectable raw command, intentional permission-mode changes, clear post-answer state, and recovery when delivery fails.
4. Lightweight local capture: reminders/notes with structured alternatives to typed grammar. Explicit capability/cost boundaries.
5. Quiet presence: visible pause/hide/summon controls and accessible text/motion settings. Actual notification delivery, startup, idle/resource behavior, and native recovery are release gates for other seats to verify.
6. Advanced integrations, custom art authoring, saved actions, and embedded terminals should not be required for the v1 success path.

Do not rewrite the UI from scratch based on this review. Rework product hierarchy and the request/capture flows first, then test those with real first-time target users.

## Release evidence this seat still requires

Browser preview cannot establish actual installation, configuration backups, disconnect/rollback, OS notifications while quit, session focusing, CLI compatibility, quota behavior, multi-monitor positioning, focus/keyboard routing, persistence across restarts, or native performance. It also cannot settle whether mock session state staying `Needs you` after an answer reproduces in production.

Before public release, run observed sessions with representative actual target users using a clean supported Mac and a sample project. They should explain the product back in their own words; connect and disconnect one agent; identify the correct waiting project; decline/allow an example with understanding; recover a lost companion; create and receive a reminder; locate settings and return with larger text. Record task completion, wrong assumptions, rescue prompts, and time to first useful outcome. These are proposed research tasks, not fabricated test results.

## Evidence files

All screenshots are browser preview images, never the user's native desktop:

- `output/audit-2026-10-25/blackbox-first.png`
- `output/audit-2026-10-25/blackbox-permission.png`
- `output/audit-2026-10-25/blackbox-companion.png`
- `output/audit-2026-10-25/blackbox-large-text-900.png`
- `output/audit-2026-10-25/blackbox-sessions-large.png`
- `output/audit-2026-10-25/blackbox-setup-first.png`
- `output/audit-2026-10-25/blackbox-setup-ai.png`
- `output/audit-2026-10-25/blackbox-unknown-question.png` (capabilities/help response)
- `output/audit-2026-10-25/blackbox-weather-recovery.png`

Preview showed one console error in Chromium. Its nature was not investigated by this source-blind seat; it is not included as a product defect. Product behavior requiring integration/native checks is explicitly left unverified.

Playwright snapshots and console logs were preserved in `output/audit-2026-10-25/blackbox-cli/`. The isolated `blackbox` browser session was closed after inspection.
