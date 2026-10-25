# Sidefolk release council — independent Codex audit

**25 October 2026 · Current source: `76b38f1` · Recommendations, not an approved reset**

## Decision brief

**Keep Sidefolk. Keep its architecture, logo and visual language. Hold the public production release. Make the next version smaller, more truthful and dependable before expanding it.** A complete restart is not justified by this audit.

The app is substantially better than its older planning documents suggest. It has a coherent Mac utility interface, useful reminder and notebook flows, a real window, optional AI, readable local data, and meaningful automated checks. It is not generally ugly, and it is not an empty prototype. Its largest remaining problems concern trust and completion: an incorrectly interpreted time, a note silently routed to the wrong notebook, an operation that requires finding another surface, a misleading permission mode, and integration status that does not establish the integration works.

**Recommended v1 experiment:** a calm desktop companion for dependable reminders and dated work notes, aimed first at Mac users who want to remember small commitments and collect a continuing record of their work. One companion by default. A narrow developer attention feature is optional and must earn its own acceptance gate. Avoid promising a general AI assistant, a task-management replacement, a coding environment, or automatic observation of every external agent session.

This is a recommendation to compare with Claude's independent report. **No implementation changes, feature removal, new product decision or commit is authorized by this report.** The proposed roadmap starts after the joint decision.

The immediate priorities are:

1. Preserve complete approval operations and remove unreliable permission assurances.
2. Protect existing data when stores cannot be read; correct time and recurrence behavior.
3. Let people finish capture, clarification and saving where they started.
4. Make actual integration capabilities, connection health and request outcomes explicit.
5. Repair keyboard continuity and prove native reminder/distribution behavior.
6. Validate repeated usefulness with real first-time users before adding scope.

## Council, method and confidence

The eight named seats are **AI reviewer personas**, each assigned a separate memo. They are not real people who used the app, and their agreement is not customer research. Reviews ran in bounded parallel rounds. Maya began without source or product documentation; Leo and Sam used the preview before inspecting relevant implementation. Other seats reviewed their domain's source, plans and references. Each was asked to form its conclusion before reading the other council memos. The chair checked their claims, reproduced selected pure-function failures, inspected current browser captures and assembled this proposal.

| Seat | Lens | Independent memo |
|---|---|---|
| Maya | Nontechnical operations manager; black-box comprehension and task recovery | [Black-box user review](blackbox-users.md) |
| Leo | Senior developer using several sessions; attention, identity and return to work | [Developer-user review](leo-developer-user.md) |
| Priya | Product audience, official competitor research, scope and continuation criteria | [Product strategy](priya-product-strategy.md) |
| Jun | Mac UI, hierarchy, design consistency and approved direction | [Design and product review](design-product.md) |
| Sam | Keyboard tasks, accessible feedback, task counts and native validation gaps | [Accessibility review](sam-accessibility.md) |
| Elena | Architecture, durability, maintainability and release evidence | [Technical review](technical-release.md) |
| Omar | Trust boundaries, permissions, execution, privacy and distribution | [Security and release review](omar-security-release.md) |
| Ines | Character, personality, motion, brand and daily usefulness | [Creative review](ines-creative.md) |

Evidence is labelled throughout:

- **Observed:** browser task behavior or direct execution of a pure source function.
- **Source-confirmed:** a concrete current code path, without claiming native reproduction.
- **Judgment/hypothesis:** a design or product interpretation that actual users can challenge.
- **Unverified:** an OS, live-tool, hardware or customer outcome this audit did not establish.

The existing Vite preview was reused. Its sample stores are not the installed app: mutations are mostly temporary, shell commands do not run, and dashboard/overlay preview pages are separate simulations. Native desktop capture was prohibited. Native VoiceOver, OS permission prompts, actual session focusing and reminder delivery after quit/sleep were not tested. No live Claude/Codex product CLI was invoked, and global agent configuration and user data were untouched.

The [verification ledger](VERIFICATION.md) records passing checks and their limits. Source locations below refer to this audited revision. The [probe script](probes.mjs) and [recorded results](probe-results.json) make the timing and approval classification examples reproducible without executing represented shell commands.

## Direct answers to the release questions

| Question | Council assessment |
|---|---|
| Is it user friendly? | The ordinary reminder form and dated notebook are approachable. The product as a whole still asks users to understand too many roles and trust boundaries. An uninformed person cannot safely infer what Pip, a project companion, a session, a connected tool and Full access each mean. |
| Is it easy to use? | Several individual tasks are short and reversible. End-to-end use is inconsistent: a window command can require completing a desktop bubble, async navigation loses keyboard focus, and failures do not always offer a durable recovery path. |
| Is the interface consistent? | Colors, typography, navigation, cards, state words and themes are broadly coherent. Behavior is less consistent: capture confirmation, authority modes, loading/error states, recurrence and focus transitions differ across surfaces. |
| Is it ugly? | No general visual restart is warranted. The weakest screens are over-explained or crowded: repeated request identity, decisions below the fold, two sidebars in notebooks, and five actions repeated on reminder rows. Those are hierarchy problems. |
| Are its features useful? | Reminders, accumulating dated notes and agent attention are plausible useful jobs. Their actual repeated value is unproven. A launcher, terminal, character importer, calendar and broad automation multiply explanation and support costs before that value is established. |
| Is the implementation good? | The basic Tauri/Rust/TypeScript split, modular domains, atomic writes, Markdown notes and installer backups are worth retaining. Approval, recovery, capability and lifecycle boundaries need targeted engineering. A passing test suite does not establish those contracts. |
| Is it production ready? | No for a supported public v1. A private beta becomes reasonable after data/authority defects and native core/distribution gates are closed. Current signing and native acceptance evidence are incomplete. |
| Should everything be deleted? | No. Narrow scope and replace weak boundaries. Do not discard functioning stores, art, tokens and UI to avoid specifying the hard behaviors. |

## What exists today, and what to preserve

Current source has Today, list-first Reminders, Notes, conditionally shown Sessions, utility Actions and categorized Settings. Setup has **three** steps, not the five still described in README. System/Light/Dark is implemented. There are ten built-in characters in two image-frame art styles; “3D” means rendered artwork, not a live 3D model. An embedded PTY terminal, calendar heads-up, briefs, summaries and character import are already present.

The current app deserves credit for:

- Local understanding and explicit review before ordinary command execution; unknown text is not silently sent to a model.
- Reminder date/time/time-zone fields, validation, visible interpretation, repeat editing, history, snooze and Undo.
- Dated Markdown notebooks that can be inspected outside the app; note edits check whether their source entry changed.
- Persistent request review, deliberate choices, sending/acknowledgement states and recovery after a failed answer.
- Optional AI setup and an explicit notebook-summary data/quota disclosure.
- Consistent design tokens, visible status words, labels, native dialogs, focus styling and both themes.
- Loopback binding, browser-Origin rejection, a private MCP token, restricted resource policy, and configuration installers with confirmation and backups.

The latest code is the audit target. Earlier PLAN-V2 descriptions of a missing Dock app, no repeats, a permanently open creation form or an eighteen-character procedural zoo are historical; they are not current defects. Conversely, “built” in a plan is not evidence that the native acceptance test passed.

## Findings that determine release readiness

**P1** means release of the affected stable capability should stop until the problem is corrected or that capability is removed from the release contract. **P2** means material usability, accessibility or support work whose disposition must be explicit. None of these findings establishes an internet-accessible compromise. Product opinions and unknown native behavior are not labelled reproduced bugs.

### F01 — Approval review and policy operate on an incomplete operation

**P1 · source-confirmed plus executable classification probe.** Claude Bash details and Codex approval details are clipped to 2,000 characters before they reach `handleAsk`, whose Full access policy inspects `ask.detail`. The displayed operation and the actual requested operation can differ. A harmless long prefix followed by a destructive suffix is flagged in full and missed after clipping. No dangerous operation was executed.

The shared display function also collapses whitespace inside quoted shell arguments, so even a short displayed command can differ from the requested bytes (`src-tauri/src/bus.rs:188`). Sources: `src-tauri/src/hooks.rs:149`, `src-tauri/src/codex.rs:339`, `src/companion.ts:174`. Probe ACCESS-CLIP; Elena T2 and Omar's dedicated review.

**Required outcome:** preserve immutable raw operation data independently from display excerpts. Never decide authority from an excerpt. Offer complete inspection or hand the decision back to the source when it cannot be represented accurately. A file-path list must not imply a reviewed file diff.

### F02 — Full access combines different policies and makes an unreliable promise

**P1 if delegation ships · observed interaction, source-confirmed semantics.** Clicking the status-looking Asks first control immediately enables Sidefolk auto-answering. A new-session checkbox instead launches Claude auto mode or Codex with `-a never -s workspace-write`. Turning Sidefolk's later switch off does not change those launch flags. The row cannot reliably summarize the native tool's actual policy.

“Risky commands still ask” is broader than the regex filter can ensure. String-only probes miss `git -C … push --force`, `git clean -fd`, long-option recursive removal and `find … -delete`. This is a false assurance within intentionally authorized automation, not a claim that session automation itself is unauthorized.

Sources: `src/dashboard/ui.ts:109`, `src-tauri/src/actions.rs:138`, `src/access.ts:9`, `src/companion.ts:185`; Maya's Sessions task and Leo's permission analysis.

**Required outcome:** ask-first v1 defaults; deliberate, explained authority changes; accurate backend-specific scope and revocation. Prefer withholding Sidefolk auto-answering from stable v1. Preserve the source tool's approval model. Do not try to guarantee arbitrary shell safety with a longer denylist.

### F03 — Damaged stored data can appear empty and later be replaced

**P1 · source-confirmed.** Reminder loading converts read/parse errors into an empty list. A later add writes that list over the existing file. Actions and crew have similar fallback patterns. Settings takes the opposite path: malformed JSON aborts startup, with no in-app recovery.

Sources: `src-tauri/src/reminders.rs:97`, `src-tauri/src/actions.rs:242`, `src-tauri/src/crew.rs:9`, `src-tauri/src/settings.rs:98`. Atomic file replacement is good but does not fix corrupt-input recovery.

**Required outcome:** distinguish missing files from damaged/unreadable ones, preserve original bytes, offer a last-good copy and understandable repair, and prevent destructive replacement. Verify disk/read/write failures in isolated data directories. This is more urgent than any visual polish.

### F04 — Time interpretation can be confidently wrong

**P1 for reminders · observed pure-function failures.** With fixed time **25 October 2026, 10:00 JST**, `at 3 to call mum` resolves to **26 October, 15:00**, rather than today at 15:00 under the app's own working-hours convention. Chrono chooses a forward date before the 03:00→15:00 adjustment. Exact ISO 03:00 is preserved by `parseWhen` but shifted to 15:00 by `parseReminder`.

`every Monday and Thursday at 9` is partially accepted as Monday-only, leaving Thursday in the task text. An explicit past date advances by a day but can remain past; new-reminder save guards prevent that example from being saved. Do not overstate the latter as persisted data corruption.

Sources: `src/when.ts:78`, `src/when.ts:118`; TIME-1–4 in the probe results.

**Required outcome:** consistent exact-time handling, correct bare-hour date selection, and clarification/rejection for unsupported compound schedules. Show the resolved date prominently. Keep parsing local; another model is not necessary to fix a deterministic date contract.

### F05 — Repeating reminders and snooze need one explicit contract

**P1 contract decision/correctness · source plus executed recurrence probe.** A repeat advances only when marked Done. Ignoring Monday's daily reminder does not independently schedule Tuesday's. That can be a recurring-task model, but “Every day” commonly implies a repeating alert. The settings explanation is distant from creation.

Snooze also changes `due`, which becomes the recurrence anchor on completion. A Monday weekly reminder snoozed to Tuesday then completed schedules the next Tuesday. The same effect can move the time of a daily reminder.

Sources: `src/reminders.ts:183`, `src/reminders.ts:232`, `src/dashboard/reminders.ts:227`, `src-tauri/src/notifications.rs:43`; TIME-5.

**Recommended contract:** preserve the series' intended wall-clock schedule separately from a snoozed occurrence. Define missed/ignored occurrences, skip/complete behavior and quit-time scheduling before implementation. Prefer scheduled alerts that do not silently stop because an earlier one was ignored; avoid creating an unlimited backlog. If a completion-dependent task is intentional, name it at creation and test whether people predict it.

### F06 — Notes can be silently routed to a different notebook

**P1 for accumulating memory · source-confirmed.** An ambiguous partial notebook name chooses the most recently updated match. “Evaluation” can route between H1 and H2 as either receives new entries. A transient “Noted in…” message is insufficient protection for a long-running work log.

Source: `src/notes.ts:23`. Jun DP-05; Priya's work-log analysis.

**Required outcome:** exact match or deliberate destination selection. Preserve the draft during clarification and offer move/recovery. The notebook must remain visible at capture, not only after saving.

### F07 — One task can require two separate surfaces

**P1 usability for the promised window/companion parity · source-confirmed.** The window Tell bar handles command/session review locally, but delegates other text to the companion. Reminder review and notebook clarification can then exist only in its bubble. A person working in the window must find the desktop companion to finish.

Sources: `src/dashboard/tell.ts:39`, `src/reminders.ts:82`, `src/notes.ts:101`. The preview's separate stores do not reproduce the whole native route; this finding follows the real delegation path, not a claim that sample pages should synchronize.

**Required outcome:** finish capture, clarification, review and save on the initiating surface. Share domain state and operations; allow the companion to act as a shortcut. Ordinary window use must work when the overlay is hidden or unavailable.

### F08 — “Connected” and “sessions appear” overstate actual capability

**P1 for developer claims · source-confirmed.** Integration status primarily checks configuration presence. It does not prove the current server, binary path, running CLI or expected events work. A fixed-port bind failure is printed to stderr while the app continues.

Claude event hooks, external Codex MCP reach-user tools and Sidefolk-owned Codex app-server threads are different capabilities. Starting a normal Codex CLI does not subscribe Sidefolk to its lifecycle. Ordinary external Codex sessions do not gain automatic monitoring merely because MCP is configured.

Sources: `src-tauri/src/prefs.rs:197`, `src-tauri/src/hooks.rs:44`, `src-tauri/src/mcp_setup.rs:52`, `src-tauri/src/actions.rs:142`, `src/dashboard/sessions.ts:36`.

**Required outcome:** a supported capability matrix; configured/reachable/activity-confirmed/repair-needed states; a cheap non-model test; clear recovery for missing/moved tools and occupied transport. Graduate each integration separately.

### F09 — Request identity, history and timeout outcomes need precision

**P1 for approval handling, P2 for monitoring depth · source-confirmed with preview fixtures.** Generic timeout copy says the tool will ask in its own window; Sidefolk-owned Codex actually declines on expiry. MCP questions lack session identity and displayed deadlines, so concurrent agents in one folder can be hard to distinguish. Live state is keyed per session, but completion outcomes are keyed per project: another completion replaces that project's previous recent result. The journal still retains recorded events; this is not a claim that all history is deleted.

Sources: `src/dashboard/requests.ts:120`, `src-tauri/src/codex.rs:379`, `src/agent-tools.ts:41`, `src/agents.ts:148`; Leo's memo.

**Required outcome:** source-specific expiry/cancel/defer wording; visible identity and deadlines; authoritative answer lifecycle; history capable of representing the supported concurrency. Differentiate stale/no recent signal from nothing running. Exact-tab opening must be promised only for supported hosts; others currently bring the app forward and ask the person to select the session.

### F10 — Errors and keyboard continuity undermine otherwise short tasks

**P1 for blocked core access; otherwise P2 · observed plus source-confirmed.** Sam reproduced focus falling to BODY after async notebook navigation, a request decision and reminder filter activation. Adding a note updates the visible list but supplies no success announcement. Jun found list failures converted into empty lists and initial async loads without an adequate local loading/error/retry presentation. Timed Undo is not a sufficient sole recovery mechanism for a person who needs more time.

Sources: `src/dashboard/app.ts:240`, `src/dashboard/notes.ts:30`, `src/dashboard/notes.ts:185`, `src/dashboard/reminders.ts:110`, `src/dashboard/actions.ts:21`. Sam records exact starting points and key counts; these are microflows, not customer speed benchmarks.

**Required outcome:** predictable focus destinations, accessible save/error feedback, real radio keyboard behavior where custom radios are used, durable recovery and a retained last-good/stale view when refreshing fails. Actual VoiceOver/keyboard users must validate the native experience. Native labels and good token contrast are useful foundations; they do not establish compliance.

### F11 — Execution and privacy promises exceed their visible lifecycle

**P1 if those promises ship; otherwise defer exposed features · source-confirmed, native consequences unverified.** Background shell runs need unique run identities, bounded output and cancellation; killing a shell is not proof all its descendants stopped. PTY close/quit semantics need testing. AI notebook drafting lacks a clear timeout/cancel path. Codex read-only filesystem mode is not isolation from inherited tools/configuration, so “nothing else” is too absolute without enforcement. Diagnostics contain raw errors, which cannot support an unconditional guarantee that names or notes never appear.

Sources and detailed trust distinctions are in Elena T7/T8 and Omar's memo. No orphaned process, covert transfer or secret leak was reproduced.

**Required outcome:** defer broad execution/drafting from stable v1 or complete their lifecycle and disclosure. Preview/redact support reports; explain journal/log/backup retention and user-initiated AI transfer. Do not confuse “local first” with “data can never leave the Mac.”

### F12 — Native and distribution evidence is not yet a release gate that has passed

**P1 for public v1 · confirmed artifact inspection plus unverified acceptance.** Current code builds. The artifact inspected is ARM64 and ad-hoc signed, with no Developer ID TeamIdentifier. Signing/notarization, clean downloaded installation, supported minimum OS, updates, native notifications, permission denial/recovery and an outside-user week are not established. README says macOS 14+ while bundle metadata declares 13.0; native calendar APIs require an explicit availability/support decision. No older-OS crash was reproduced.

The release script can skip WebKit when the preview is absent. A required check should fail closed as an unavailable gate, not quietly disappear. Package descriptions and several docs still describe older product shapes.

**Required outcome:** one supported platform contract; a signed, notarized downloadable artifact; native acceptance records; deterministic release checks; a real update/reinstall/uninstall/support path. Tauri's official documentation covers [macOS signing/notarization](https://v2.tauri.app/distribute/sign/macos/) and [signed updater artifacts](https://v2.tauri.app/plugin/updater/). A supervised beta can use explicit manual updates; the public maintenance plan cannot remain implicit.

## Interface and creative judgment

The chair inspected all thirteen current WebKit route captures in **both themes**, plus current Today/notebook images at full size. Jun assessed the approved design direction and implementation, and Ines supplies the dedicated creative review. These are browser observations, not a claim of every native state or animation being tested.

| Surface | What works | Targeted rework |
|---|---|---|
| Today | Clear attention priority; everyday navigation; compact two-column summary | Match the chosen audience; avoid competing invitations and unexplained session identities; add a quick dated-note entry route when it is the chosen core habit |
| Requests/review | Inspectable command/folder; deliberate choices; persistent acknowledgement | Reduce repeated identity/headings/side context; decisions currently fall below the first viewport at normal desktop sizes; make source-specific expiry and authority visible |
| Reminders | List first; date/time/zone; modal creation; repeat/history/Undo | Fewer repeated row controls; explicit recurrence/snooze contract; accessible filters and durable recovery |
| Notes/notebook | Dated entries; readable capture; Markdown portability | Avoid unexplained nested navigation; fix focus/loading/save feedback and ambiguous destinations; summary stays optional |
| Sessions | Running versus recent; project options disclosed | Capability and health first; session/task/host identity when needed; no silent mode change from status click |
| Actions/terminal | Useful to an informed developer | Move out of everyday onboarding; keep only the execution scope whose full lifecycle is supported |
| Settings | Search, nine categories, native-looking fields, useful theme tiles | Back remains reachable at larger text; native/custom radio semantics consistent; state effects and save failures explained |
| Setup | Three concise steps; useful local action before optional AI | Prove a personally meaningful result rather than only a Stretch demo; show actual delivery limitations and postpone unnecessary permissions |
| Characters | Appealing existing assets; coherent art families | Treat appearance as preference, not the primary value story; do not promote a technical authoring workflow as effortless customization |

The written approved design called for less common reminder actions in details/More, explicit/intentional per-session authority, ordinary labelled alternatives to typed syntax, and clear invalid/ambiguous time handling. Those are useful standards to finish. Mockups are references, not evidence that interaction is solved.

Ines adds three concrete **P2 signal/identity corrections**. Autonomous idle behavior sometimes chooses a thinking pose with the same blue signal used for actual work, which can make a decorative mannerism look like agent activity (`src/mind.ts:203`, `src/pip.ts:55`). The runtime status orb uses one bunny-ear coordinate for every species and can compete with an antenna or other decoration (`src/pip.ts:86`). A custom imported character's window picture falls back to Pip, breaking continuity with its desktop appearance (`src/roster.ts:33`). Preserve the artwork; reserve factual status signals for actual activity, validate per-character placement, and use the imported idle thumbnail across surfaces. Reading and working share frames, so do not promise visually distinct acting for every tool event.

**Keep the production logo and approved characters.** Do not commission another art reset. Use the same status words and tokens. Review the default companion and one worker at actual size on light/dark backgrounds with reduced motion, then stop expanding the roster until the core habit proves useful. Still images establish appearance, not convincing animation, calm interruption frequency or native performance. A friendly character must never stand in for safety evidence.

## Product choice and the useful dissent

Three options are genuinely different release contracts:

| Direction | First promise | Why it could win | Why it could fail |
|---|---|---|---|
| **A — Everyday work companion** | Remember small commitments and collect dated work notes | Low setup, no required AI quota, concrete continuing-notebook job; matches the user's stated priorities | Mature existing tools, another local store, no cross-device continuity, delayed payoff and possible novelty fade |
| **B — Developer attention companion** | Know which coding session needs you and return to the right work | Sharper specialist problem; several concurrent agents create visible attention cost | Integration churn, wrong/stale session state, complex setup, approvals and host limitations; first-minute trust depends on the hardest current code |
| **C — Broad assistant shell** | Reminders, notes, AI, commands, calendar, terminals and custom companions together | Rich demo and broad founder convenience | Many mental models and support obligations; language and safety expectations grow beyond demonstrated capability |

Maya favors **B**, provided it becomes a trustworthy awareness/return product. Leo, despite reviewing as a multi-session developer, favors **A with a narrow optional monitor** until identity, history and capability gaps are closed. Priya, Jun and Ines also favor A; Elena supports preserving the foundation and reducing the public contract. Sam identifies accessibility gates rather than claiming a customer positioning vote; Omar makes the authority/privacy/distribution conditions explicit. Those gates apply under either direction. There is no customer-derived mandate for either A or B, and averaging them into C would evade the decision.

**Chair's recommendation: test A first, using the continuing work-log habit as the beachhead. Keep B as the explicit alternative.** This follows the user's priority and avoids making changing agent integrations a prerequisite for first value. If only developers retain Sidefolk for attention recovery, switch the public promise toward B deliberately. Do not claim “for everyone.”

Priya's official-source comparison is worth reading in full. [Apple Reminders](https://support.apple.com/guide/reminders/add-or-change-reminders-remndc729e28/7.0/mac/26) already offers natural-language/repeating reminders; [Apple Quick Note](https://support.apple.com/guide/notes/create-a-quick-note-apdf028f7034/mac) and [Raycast Notes](https://manual.raycast.com/notes) compete for quick capture; [Raycast Script Commands](https://manual.raycast.com/script-commands) competes for small actions; [Claude notification hooks](https://code.claude.com/docs/en/hooks-guide) provide a lightweight attention alternative. **The possible advantage is a useful companion-led follow-through loop, not merely combining existing features.** That advantage is an inference to test, not evidence of market demand.

## Recommended version 1 contract

> Sidefolk is a small Mac companion for reminders and dated work notes. Capture quickly, see exactly where and when something is saved, and find it later. Optional developer connections show only the capabilities each supported tool actually provides.

The default experience should contain **Today, Reminders, Notes and Settings**, one companion, a discoverable summon/hide control, and a clear supported-actions input with structured alternatives. When a supported developer integration is enabled, Sessions appears as an extension. The main window must remain fully usable with the companion hidden.

| Capability | Proposed public v1 disposition | Requirement |
|---|---|---|
| One companion, existing looks, name/size/accent | Stable | Calm presence, keyboard/window alternative, native focus/hide/summon verified; no mandatory customization |
| One-off reminders, date/time/zone, edit/complete/snooze/history | Stable after hardening | Timing, durability and native delivery matrix passes |
| Repeating reminders | Stable only with explicit settled semantics | Series schedule survives snooze; ignored/late/quit/DST behavior matches promise |
| Topic notebooks, dated capture, search/edit/export | Stable after hardening | Exact/chosen destination, text preserved, portable files and recovery; add simple correction/move behavior |
| Today and shared quick capture | Stable | Complete on initiating surface; no implied general chat; visible supported task choices |
| System/Light/Dark, text/motion controls, optional sound | Stable | Focus, feedback, both themes and native accessibility validation; easy quiet control |
| Claude observation and return | Optional beta, graduate independently | Real supported tool/host/version matrix and healthy transport; passive value without granting authority |
| Codex MCP notify/ask/remind tools | Optional, accurately scoped beta | Genuine handshake and contextual identity/deadline; no automatic external-monitoring claim |
| Sidefolk permission answering | Separately gated optional capability | Full raw operation, correct source semantics, delivery acknowledgement, expiry/revocation and recovery |
| Broad auto-answer / Full access | Withhold from stable v1 | Reintroduce only with coherent authority contract; no general risky-command guarantee |
| Simple confirmed external-terminal commands | Advanced beta or deferred | Exact preview and host limits; no need for nontechnical first use |
| Background saved commands and embedded terminal | Defer public promise | Lifecycle, cancellation, concurrency/output and quit behavior must earn inclusion |
| AI notebook drafting | Optional later/beta | Explicit data/quota disclosure plus cancellation, timeout, enforceable scope and recoverable output |
| Calendar, morning/weekly briefs | Defer promotion/expansion | May remain opt-in beta with clear OS/permission boundaries if isolated from stable core |
| Character authoring/import/export | Advanced beta | Existing approved art retained; bounded safe imports; do not make it onboarding homework |
| More agents/teams, Windows, voice, screenshots, broad sync | Park | Add only in response to validated core-job limitations |

“Defer” does not mean erase someone's data or remove approved assets. Use clear capability gating and preserve migration paths. Existing code does not have to be deleted to stop promoting it. Publicly reachable unsafe or misleading behavior still needs repair or actual withholding; a beta label alone is insufficient.

## Engineering direction: evolve, with bounded replacement

Keep the Tauri shell, Rust stores and integrations, readable Markdown, existing frame renderer, tokens, logo and working components. The codebase is small enough to harden without a platform migration. Neither Electron nor a new framework addresses the observed date, recovery or permission problems.

The most valuable bounded rework is to put **authoritative operations and request lifecycle** behind a shared service boundary, with full input and explicit pending/succeeded/failed/expired states. Both window and companion render and invoke that model. Do not make the overlay bubble's availability the condition for finishing a reminder or knowing whether permission was delivered. Keep domain parsing deterministic and independently testable.

Also separate durable schedule/series data from temporary display/snooze state; separate installed configuration from observed integration health; separate raw security-relevant operation data from display text. These are concrete boundaries with regression cases. They are a better reason to refactor than a generic desire for cleaner architecture.

Only replace a subsystem wholesale when a scoped implementation plan shows that its current structure cannot reasonably meet these contracts. No finding here justifies starting the entire application again.

## Roadmap to a releasable v1

The [release backlog](RELEASE-BACKLOG.md) supplies concrete tasks, dependencies and exit evidence. This sequence is outcome-based; a date cannot substitute for a passed gate.

| Phase | Outcome | Exit gate |
|---|---|---|
| **0. Joint product decision** | Compare independent Codex/Claude reports; choose A or B, stable/beta/deferred inventory, recurrence and authority contracts, supported platforms/tools | One current release contract approved by the user; historical docs point to it; new features frozen |
| **1. Trust and correctness** | Full operation handling, truthful authority, corrupt-data recovery, correct time/series behavior, predictable notebook destination | Isolated failures preserve data; source regression probes behave intentionally; no misleading safety claims or accidental authority grant |
| **2. One understandable workflow** | Same-surface completion; consistent loading/error/retry; focus/announcements; clearer request hierarchy/capture boundary | Unaided core task preflight succeeds with overlay hidden; no lost draft or unexplained focus jump; real keyboard/VoiceOver validation |
| **3. Native and distribution proof** | Native reminder lifecycle, permissions, upgrade/data recovery, supported host/tool behavior if included; signed/notarized install | Recorded matrix on supported configurations and outside development machine; deterministic release checks; actual versioned maintenance path |
| **4. Private beta** | Real use against existing-tool baseline; quietness, repeat usefulness and support cost measured | Safety/reliability failures fixed; core loop repeated voluntarily; choose continue A, focused B test, or rethink |
| **5. Public v1** | Stable small scope, honest limits, support/data controls and update path | All stable-scope gates pass; no unexplained lost note, wrong destination, missed supported reminder, wrong-source approval or hidden authority mode |

The developer extension does not need to hold a dependable everyday product hostage. If the extension fails its gates, ship without that promise. Conversely, choosing B means its integration/native gates are the core, not optional checks to postpone.

A minimum supported configuration must be explicit: macOS version, Apple Silicon/Intel, notification requirements, supported CLI versions and supported session-opening hosts. Do not silently inherit macOS 13 support from stale metadata or imply universal host/tab selection.

## Research that can change the recommendation

Do not ask only whether people like Pip. Observe what they actually rely on.

Use **eight real testers as an initial pilot**, four fitting the continuing-work-note job and four multi-session developers; include people who did not build Sidefolk and people who use keyboard/assistive technology. Two or three colleagues are a rehearsal, not market validation. Establish each person's current-tool baseline. Collect task outcomes and optional diagnostics without collecting notebook or command contents unnecessarily.

Proposed thresholds are decision rules, not statistical proof:

- At least six of eight create a personally useful reminder and dated note within ten minutes without rescue; a pre-filled Stretch demo does not count.
- At least three of four everyday participants use a useful capture loop on three separate days and return on days six/seven voluntarily.
- At least three everyday participants build one notebook with several entries and retrieve a relevant one in thirty seconds at week's end. Extend successful use another three weeks; one week cannot validate a six-month work-log benefit.
- At least three of four developers use review/return on three days. Compare actual return-to-work friction with their existing notification/session setup. Record wrong-source, stale-state and duplicate-interruption failures.
- Record scheduled deliveries and supported native conditions. Zero unexplained missed core reminders, lost notes or wrong-notebook saves is a graduation requirement, not a proven population failure rate.
- Ask what people would keep: the everyday habit, session attention only, or neither. Count actual repeated useful outcomes and voluntary continued use; launches and time spent watching animation are weak success measures.

If only developer use persists, test B explicitly. If neither group repeatedly gets value, revisit the job before building more. If the companion is liked but hidden because it interrupts, repair the attention model before making more characters. If duplicated stores or absence from the phone drives abandonment, investigate interoperability before inventing a broader productivity suite.

## Verification and what remains unknown

Fresh checks passed: **TypeScript; 100 Vitest tests in 13 files; 34 Rust tests with three opt-in tests ignored; full existing WebKit interactions in both themes; frontend production build; and a current 9.27 MiB app bundle.** The audit shell initially lacked Cargo on PATH; adding its documented location allowed the build to complete. The app was not relaunched.

Those results support retaining the implementation. They do not prove native notification delivery, actual agent monitoring, clean installation, final-build performance, process cleanup, minimum-OS compatibility, update/uninstall, VoiceOver or customer demand. Historical ~1% CPU measurements are not a fresh final-build measurement. Review [VERIFICATION.md](VERIFICATION.md) for the full ledger and reproducible probes.

The largest remaining uncertainty is not whether another feature can be implemented. It is whether people trust and repeatedly use one small loop enough to keep a companion on their desktop. The roadmap is designed to answer that with a dependable product and real evidence.

## Final joint decision with Claude

Use [the comparison brief and worksheet](CLAUDE-COMPARISON.md). Claude should freeze its independent findings before reading this council's conclusions. Then reconcile disputed claims on the same source revision, preserve valid dissent, and write **one** release contract for the user to approve.

Confirmed data/authority defects should be resolved by evidence. Product direction should be settled by a declared bet and real use. Neither two agreeing AI reports nor eight simulated seats should be treated as the final users' vote. Until that joint decision, this audit remains a review proposal and does not supersede the approved plan.
