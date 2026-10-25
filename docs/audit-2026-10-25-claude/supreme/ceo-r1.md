# Supreme council, round 1: CEO position (Nadia, seat `ceo`)

25 October 2026. Read: PLAN-V2 §1 and §11, both council reports, the backlog, the addendum, and
the Priya, Maya, Leo, Ines, Omar and Elena memos. Marks: **[FIGHT]** means I will hold it in round 3
unless I'm shown evidence. **[CONCEDE]** means I'll trade it for a better argument.

## The bet in one paragraph

Being an agent-status pet is now table stakes: the Codex app gives pets away free, and notch monitors
cost $0–20. Reminders and notes on their own lose to Apple and Raycast, and they never reach the
phone. Only one thing here is ours: **one companion that holds both your commitments and your
agents' asks, and remembers what got done.** The founder's four priorities (reminders, a
note that collects, quick commands, AI sessions) describe a developer's workday. Even the "evaluation
notes" example is a brag doc. So v1 serves that person well and stops pretending to serve
everyone. No restart: both councils, 16 of 16 seats, keep the core.

---

## D1. Audience and promise. **[FIGHT]**

**Choice:** B-led hybrid with an explicit gate.

> **For developers who work alongside Claude Code and Codex on a Mac: Pip taps you when an agent
> or a reminder needs you, takes you straight there, and keeps a dated log of what you and your
> agents got done.**

- **Acquisition wedge:** answering agent requests safely from anywhere, and the exact-session jump.
- **Retention wedge:** the work log plus the Friday "your week" view, fed by your notes and your
  agents' finished sessions. No competitor I've seen does this.
- **Daily habit:** reminders, including agent-aware ones ("remind me when api finishes").
- Reminders and the work log fully work with no agent connected, so the founder's #1 and #2 stay
  first-class. Only the *positioning* and the first-run order lead with agents.
- **Gate for widening to everyday users (direction A):** ≥30% of weekly beta actives use reminders
  or the log with no agent connected for 2 straight weeks. Until then, no "for everyone" copy.
- **Rejected:** C (everything for everyone). A as the headline is also rejected: it has no channel,
  it's Mac-only against an iPhone default, and it pays off late.

I'm overruling one founder wish: "for developers *and* people who aren't technical" in v1. The
reason is that the non-technical seats' first deal-breaker (phone sync) isn't solvable in v1 without
EventKit sync, which is a second product.

## D2. Feature inventory

**Definitions.**

- **STABLE:** in v1 and promised.
- **BETA:** shipped behind Settings → Labs, off by default, never in marketing.
- **LATER:** not in the v1 build. The code is removed from the UI, and it's deleted unless it's
  scheduled within the next two releases.
- **DELETE:** code is removed and tagged `v0.2-pre-cut` for recovery.

| Feature | Call | Reason |
|---|---|---|
| Pip companion | STABLE **[FIGHT]** | The body is the brand, and the only visual difference from notch dots |
| Typed phrase input (companion) | STABLE, reworked | The one input; quick-add grammar (D5) |
| Tell bar | STABLE as the window's quick-add (⌘N) | Same parser, but it must finish in the window (Codex F07) **[CONCEDE]** to cutting it if CPO insists |
| Reminders: one-off | STABLE | Founder's #1, and the daily habit |
| Reminders: repeat | STABLE | Only under the D3 contract |
| Reminders: snooze | STABLE | Moves the occurrence, never the series |
| Reminders: history | STABLE (simple list) | Recovery and trust |
| Notes & notebooks | STABLE as **Work log** + optional topics | Founder's #2 and the retention wedge **[FIGHT]** |
| AI draft summary | LATER (v1.1) | No timeout, spends quota; prove the habit first |
| Quick shell commands | BETA ("Quick actions"), `$` prefix only, opens in the user's terminal with a confirm | Founder's #3, kept honest. English never becomes a command again |
| Saved actions | DELETE | Background runs lack a lifecycle (R18); Raycast does this |
| Open app/folder/URL | BETA, inside Quick actions | Safe and cheap, but off-promise **[CONCEDE]** |
| Watching Claude Code | STABLE **[FIGHT]** | The acquisition wedge |
| Watching Codex | STABLE *if* real status (notify + rollout files) passes its gate in phase 3; otherwise BETA, and "Codex" comes out of the copy | It isn't watched today, and we won't claim what we don't do |
| Permission requests on the companion | STABLE (Claude Code) **[FIGHT]** | The signature moment, rebuilt per D6 |
| Per-session full access | DELETE (the deny-list and "Allow everything") | Unsafe and unfixable by a longer list; 16 of 16 seats agree |
| Start sessions | LATER (v1.1, with a prompt field and native modes) | Founder's #4, but not why people install **[CONCEDE]** to BETA |
| Open/continue session | STABLE | The reason to click; host matrix in D6 |
| Sparks | LATER (gate: beta users run 3+ sessions and ask for them) | In v1, a project name and color on Pip's session list does the identity job |
| Terminal inside Sidefolk | DELETE | 8 of 8 seats; TCC and keystroke-injection surface |
| Calendar heads-up | LATER, first item of v1.1 | Honors founder decision #6, and keeps the EventKit entitlement out of v1 |
| Morning brief | DELETE | Replaced by "While you were away" on Today (LATER) |
| Weekly wins | STABLE as **"Your week"**: a plain dated list, copy as Markdown, no AI | This is retention **[FIGHT]** |
| Ten characters + 3D/2D | DELETE (art stays in git history) | Churn; 5.2 MB; overlay reloads |
| Character import/export | DELETE | 698 lines of untrusted-file parsing, no v1 value |
| Accent colors | STABLE as Pip's scarf color only, with no overlay reload | Cheap delight **[CONCEDE]** to LATER if it costs a reload fix |
| Sounds | STABLE: one "needs you" chime and one reminder chime, plus Quiet | It matters more than visuals |
| TTS voice | DELETE | Breaks the character (3 seats) |
| Setup guide | STABLE, rebuilt (D8) | Must prove a round-trip |
| Settings | STABLE, 4 sections | Down from 9 |
| CLI `sidefolk here` | LATER (with Sparks); delete the admin-password install now | Depends on Sparks |
| MCP notify / ask / remind | STABLE | Agents reach you; `ask` gains session identity and a deadline |
| MCP spark / presence | DELETE | They go with Sparks |
| Dock app + window | STABLE | Founder decision #4 |
| Menu bar icon | STABLE: Show/Hide Pip, Pause answers, Quiet, Quit | — |
| Hide from screen recordings | STABLE, **on by default** | Approval cards hold secrets |
| Copy report | STABLE, with a redaction preview | Support channel |
| Codex app-server driver (`codex.rs`) | DELETE | Dead code |

## D3. Reminder contract **[FIGHT]**

1. **A series is a schedule; an occurrence is an event.** A series stores its rule and its
   wall-clock anchor. Occurrences are derived from that.
2. **Repeats are alerts, not tasks.** Every occurrence fires on schedule, whether or not you
   handled the last one. Done completes that occurrence only. "Skip next" exists. A
   completion-based repeat ("3 days after done") is LATER.
3. **Snooze** moves the current occurrence only, by 10 min, 1 h, tonight or tomorrow 9:00. The
   series anchor never moves.
4. **Missed or late.** If the Mac was asleep or the app was quit, a reminder fires once on wake or
   launch as "Missed at 9:00", one per series, with no backlog. An unhandled reminder auto-files to
   history after 24 h as "ignored".
5. **Quit and login.**
   - Start at login is **on by default**.
   - The next occurrence of every series, plus all one-offs within the OS limit, are handed to
     macOS notifications, so they fire with the app quit.
   - Clicking one opens the details.
6. **Time zones and DST.**
   - Reminders follow the Mac's current time zone (floating), unless an explicit zone is set.
   - A time that doesn't exist (spring forward) fires at the first valid minute after it.
   - A time that repeats (fall back) fires once, at the first instance.
7. **Phone reach.** None in v1, and the UI says "on this Mac" plainly. One-way export to Apple
   Reminders is LATER, triggered only if the beta shows phone reach is a top-3 reason to leave.
   For a desk-bound developer audience, Mac-only is acceptable.

## D4. Work log contract

- **Destination.**
  - "note: …" goes to **Work log**, the default notebook that is also the inbox.
  - "note for X: …" needs an exact or unique-alias match, case-insensitive.
  - If it's ambiguous, Pip asks, keeps the draft, and offers choices. If it's new, Pip asks
    "Start X?". It never silently guesses (Codex F06).
- **Feedback.** The destination is visible *before* saving. After saving: "Noted in Work log", plus
  a persistent Undo and Move in the entry's menu, not a 9-second toast.
- **Timeline.** The Work log view is a dated timeline, filterable by topic and project.
  - Search matches text and dates ("last week", "March").
- **Agent work feeds the log as suggestions, never automatically.**
  - A finished Claude Code or Codex session offers "api: add rate limiting, finished 14:02". One
    click keeps it.
  - Only the project and the first prompt line are stored, never commands or outputs.
- **Your week.** Every Friday at 16:00 (configurable), Pip offers your kept entries plus the
  reminders you completed.
- **Export.** The store stays plain Markdown files, as it is today. "Copy week/month as Markdown"
  is the export.

## D5. Input model

1. **Typing is quick-add, not chat.** A local grammar only, in order:
   - card answers ("allow", "decline")
   - session verbs ("open api", "sessions")
   - reminders (any text with a time or date)
   - notes
   - help
   - about 20 canned small-talk replies
2. **A time means a reminder draft.** Enter saves and shows Undo, with no extra confirm card.
   "call mom at 5pm" and "dentist thursday 2:30" work.
3. **Unknown text with no time** gets "Save to Work log?" with Enter, plus "Did you mean…" options.
   Never "I don't know that one yet", and never a shell offer.
4. **Shell** only with an explicit `$` prefix, only with Quick actions (beta) on, always confirmed,
   and always run in the user's terminal.
5. **Time rules.**
   - A bare hour (1–11) is the soonest future of h:00 or h+12:00 that falls between 07:00 and
     21:59.
   - "tonight" is 20:00. "end of day" is 17:00. "morning" is 9:00. "afternoon" is 15:00.
   - "Mon and Thu" is supported. Anything unsupported gets a question, never partial acceptance.
6. **No LLM in v1.** Apple's on-device model is a v1.1 experiment for unknown text, always with a
   confirm. Founder decision #3's layering is honored; layer 1 just has to be excellent first.
7. **Target.** A 200-phrase corpus (100 everyday, 100 developer) checked into the tests.
   - ≥95% correct or a safe clarification.
   - **0** wrong times. **0** English turned into a shell command.

## D6. Developer capability contract **[FIGHT on routing, display and withholding full access]**

- **Tools.**
  - Claude Code: hooks, in full.
  - Codex: status through its `notify` program plus the rollout JSONL files.
  - Codex approvals stay in Codex, and the UI says so.
  - Codex MCP `ask` and `notify` work for both tools.
- **Routing rule.**
  - A request goes to Pip unless *that session's own tab* is frontmost and focused. Sidefolk knows
    this from the host app plus the tty.
  - If the focus is unknown, it shows on Pip.
  - When you focus that session's tab, the hold is released at once, and the tool's own prompt
    takes over.
- **Exact-session hosts.**
  - Exact tab: Terminal, iTerm2, Ghostty (AppleScript tty/cwd match, verified in phase 3) and tmux
    (switch-client by tty).
  - Bring forward and say so: VS Code, Cursor, Claude desktop, Warp and WezTerm.
  - A live session is never resumed twice. Pip says "running in tmux on ttys004" instead.
- **Approval display.**
  - The exact raw bytes, in monospace, with whitespace kept and control/bidi characters shown
    escaped.
  - Edit shows a diff (old → new). Write shows the content up to a size cap.
  - MCP calls show pretty-printed arguments.
  - Over the cap, or anything that can't be shown, gets **no Allow button**, only "Answer in
    terminal" and Open.
  - Policy is never decided from an excerpt. A destructive-looking command gets Decline as the
    default button.
- **Full access.** Withheld from v1 and deleted. Native permission modes come back in v1.1 with
  Start session, chosen at launch, labeled with the tool's own terms and ending with the session.
- **Hold timeout.**
  - Pip holds for up to 45 s. After that, the hook returns no decision, the tool's own prompt
    appears, and the card turns into "Waiting in terminal · Open".
  - The copy for each source matches what that source actually does.
- **Identity.** Each session is labeled project plus first prompt line. Clicking Pip shows a session
  list (needs you / working / done).

## D7. Character, brand and voice **[FIGHT on freeze; CONCEDE on logo execution]**

- **Pip** is the ivory clay 3D Pip that ships today (pre-rendered frames). Every seat gave the
  visuals 7–8 because of it.
- **Logo.** The charcoal logo is redrawn as the ivory Pip on a charcoal tile, so the logo and the
  character are one creature. A single pass, not a new pipeline.
- **Spark.** LATER. The art is frozen in `art/`, with no runtime in v1.
- **Other characters and styles.** All other characters and the 2D style are deleted from the app.
- **Blender film-duo.** The staged work does not land on `main`; it moves to a branch.
- **Character bible.** Adopt Ines's bible as written:
  - quiet messenger, not an AI
  - attentive, earnest, unbothered
  - the ears carry emotion
  - add a **puzzled** pose
  - status signals reserved for real activity, so the idle "thinking" pose loses its blue orb
  - dark-wallpaper legibility through a soft shadow, not an outline
- **Voice rules.**
  - At most 12 words, then buttons.
  - No raw errors, through an error translation table.
  - No guilt, no emoji.
  - Plain copy on permission cards.
- **Frozen until public v1:** the look, the name, the roster (Pip only) and the voice rules. The
  allowed art work is the puzzled pose, the micro-frames and the legibility fixes, nothing more.

## D8. App shell and UI

- **Shell.**
  - Dock app plus window, by default. Closing the window keeps Pip and the reminders running.
  - Menu bar icon kept. "Hide from Dock" in Settings. (Founder decision #4, five seats.)
  - Menu-bar-first is rejected.
- **Window.** Re-implement each view against the approved mockups on a small component kit, view by
  view on top of the new Rust state layer (D9). It's a re-implementation toward designs that already
  exist, not a new design, and not a big-bang rewrite. **[CONCEDE]** on how much code is reused.
- **Sidebar.** Four items, with no utility group:
  - **Today**: Needs you → Running → Today's reminders → Recent log.
  - **Sessions**: shown once an agent is connected.
  - **Reminders**.
  - **Work log**.
- **Settings.** A standard ⌘, Settings window with four sections:
  - General: login, Dock, sounds.
  - Companion: name, scarf, size, motion.
  - Agents: connect or disconnect with health status, default terminal, how sessions open.
  - Privacy & data: history retention, screen recordings, Copy report, uninstall.
- **Component kit.** Three button styles (primary, secondary, destructive), one field, one select,
  a list row, a card, a sheet, and a toast with Undo, which is backed by persistent recovery.
  - One icon set.
  - 1 px hairlines, not heavy outlines.
  - Mac-sized controls of 28–32 px.
  - A warm dark theme that matches the cream light theme.
- **Setup.** Three steps:
  1. Pip waves, and you set one real reminder.
  2. Connect Claude Code or Codex, with a live test request round-trip. This step is skippable.
  3. Notifications plus start at login, both on.
- **Visual bar.** A design re-review scores the window ≥7/10 in both themes. Every companion action
  has a keyboard path, and VoiceOver passes.

## D9. Architecture

| Subsystem | Call |
|---|---|
| Tauri shell, Rust core, NSPanel overlay, host detection, installers, Markdown notes, tokens, frame renderer | KEEP |
| Domain state (requests, sessions, reminders, notes, settings) | MOVE into Rust. The webviews only render, driven by pushed events; no 1 s or 3 s polling |
| Request lifecycle | NEW: one authoritative state machine (pending → answered/deferred/expired) with raw operation bytes stored apart from the display |
| Hook transport | REPLACE (D10) |
| Parser (`commands.ts`, `when.ts`) | REFACTOR against the corpus; stays pure TypeScript |
| Window views | RE-IMPLEMENT per D8 |
| Character import, recolor, voice, inside terminal, calendar, `codex.rs`, saved actions, extra characters | DELETE (~2,000 lines) |

- **Durability.**
  - Every file gets a `schema_version` and a migration.
  - A file that can't be read is quarantined (`.corrupt-<ts>`, bytes kept). The app falls back to
    `.bak` last-good, says so, and never overwrites it with an empty list.
  - Bad settings never block launch.
- **Errors.**
  - No mutex `unwrap` under `panic = abort`.
  - A single-instance guard.
  - A socket bind failure is shown in the UI.
  - Async commands run off the main thread.
  - A timeout on every external process.
- **Tests to add.**
  - Hook flow integration: hold, answer, focus-release, timeout, app-not-running.
  - Request lifecycle.
  - The 200-phrase corpus.
  - Recurrence and DST with fixed clocks.
  - Corrupt-store recovery.
  - Installer and uninstaller round-trip in a temp `CLAUDE_CONFIG_DIR` / `CODEX_HOME`.
  - A window↔overlay event contract.
- **CI.** The WebKit check can't be skipped.

## D10. Security, privacy, distribution

- **Hook transport.**
  - A small bundled command-hook binary talks to a 0600 Unix socket using a per-install secret.
  - If Sidefolk isn't running, the hook exits with no decision, so the tool asks as normal. That
    removes the dead-port attack (B5).
  - **[CONCEDE]** on mechanism to the CTO. The requirement is fail-to-native and no answer from an
    impostor.
- **Uninstall.**
  - "Disconnect & uninstall" in Settings reverses hooks, MCP entries, LaunchAgent and CLI, with
    data optional.
  - Documented manual steps.
  - Every installer keeps its backup-first confirm.
- **Signing.**
  - Developer ID, notarized, hardened runtime.
  - Apple Events usage strings and notifications. No calendar entitlement until v1.1.
  - No App Sandbox, not the Mac App Store.
- **Updater.** The Tauri updater with signed artifacts and an offline key.
  - Each update check also reads a signed "blocked versions" file. A blocked version stops holding
    requests, and the tool's own prompt takes over.
  - Plus a local "Pause answers" item in the menu bar.
- **Platform.** macOS 14+, Apple Silicon only, for v1. Intel only on demand. Bundle metadata gets
  fixed.
- **Crash reporting.** No third-party SDK. A local crash log plus Copy report, opt-in and redacted.
- **History.** The journal stores no command bodies or prompts beyond the first line. Retention is
  7 days by default, with a Clear button.
- **License.** The code is **MIT**, because trust matters for a tool in the permission path, and it
  enables Homebrew. Pip's art and name are **all rights reserved**, to protect the brand and a
  future paid pack.
- **Price and channel.** **Free.** A signed DMG on GitHub Releases plus a Homebrew cask. A one-time
  cosmetic pack (Spark and friends) is the revenue idea after v1, not before.

## D11. Gates, beta, metrics, rules

**Release gates.** All must pass and be recorded with a date by the founder on a real Mac.

- **G1 Trust.**
  - No Allow on truncated or unrenderable input.
  - No deny-list remains.
  - Zero wrong-session approvals in a 3-session test.
  - Corrupt-store tests pass.
- **G2 Native.**
  - The reminder matrix: visible, hidden, window closed, quit, locked, asleep/wake, notifications
    denied then enabled.
  - The host matrix from D6.
- **G3 Ship.**
  - A clean install from the DMG on a second Mac passes Gatekeeper.
  - After uninstall, no hooks remain.
  - An update preserves data.
- **G4 Input.** The corpus passes the D5 targets.
- **G5 Access.** Keyboard-only and VoiceOver runs through the core flows.

**Private beta.** Two weeks.

- 10 developers who use agents daily, not friends who love pets.
- 4 work-log-only users, to test the gate.
- Opt-in, local counters only, never content.

**Metrics.**

| Metric | Target |
|---|---|
| Connect an agent during setup | ≥70% |
| Answer one request through Pip on day 1 | ≥60% |
| Still running on day 14 | ≥60% |
| Open-session success | ≥95% |
| Keep ≥3 log entries per week | ≥40% |
| Open "Your week" on Friday | ≥50% |
| Trust incidents | 0 |

**Rules.**

- **Continue to public** if ≥6 of 10 developers are still running it voluntarily on day 14, ≥3 use
  it on 3+ days a week, and there are zero trust incidents.
- **Switch** to direction A if developers drop but ≥3 of the 4 log users stick.
- **Stop** feature work and rethink if fewer than 3 of 10 keep it.
- **Any trust incident** (a wrong-session approval, a lost note, a missed supported reminder)
  freezes the beta until a fix lands with a regression test.

## D12. Process guardrails **[FIGHT, all of them]**

1. **`docs/V1.md` is the single contract.** It holds this inventory with item IDs, and it supersedes
   PLAN-V2 and ROADMAP.
2. **Adding to v1.** One in, one out, with a dated DECISIONS entry, a 24-hour wait, and the founder's
   yes. "The user asked" means write it down, not build it that hour.
3. **WIP = 1.** "Done" means the founder recorded a dated real-app check in `memory/CHECKS.md`.
   Agents can't mark anything done. Each day's output is sized to what the founder can verify (at
   most 2 items).
4. **Art and pipelines.** Art is frozen and no new pipelines are allowed. Nothing staged in git goes
   in without a V1 item ID.
5. **Cutting means deleting the code**, tagged first.
6. **Honest copy and sample data.** Sample and preview data may not show capabilities that don't
   exist (no fake Codex sessions). README and GUIDE change in the same commit as the behavior.
7. **STATUS.md** is rewritten at each handoff, ≤150 lines. History moves to `memory/LOG.md`.
8. **No new dependency, permission or entitlement** without a decision entry.

## D13. Roadmap

Sizes are in focused agent-plus-founder weeks, gated on verification, not on dates.

| Phase | Work | Size | Exit gate |
|---|---|---|---|
| 0 Freeze & cut | Tag; write V1.md; move film-duo to a branch; delete the DELETE list; fix metadata and copy; enroll in Apple Developer | 2–3 days | It builds; only v1 surfaces are reachable; founder check |
| 1 Trust core | State into Rust; request lifecycle; socket hooks; raw bytes and diffs; routing and focus-release; corrupt-store recovery; schema versions; single instance | 2 wks | G1 plus the integration tests |
| 2 Daily loop | D3 reminders; D5 parser and corpus; work log; agent suggestions; Your week | 1.5 wks | G4; the reminder half of G2 |
| 3 Agent reach | Codex notify/rollout; host matrix; session list and labels; MCP `ask` identity and deadline | 1 wk | The host half of G2; Codex goes STABLE or BETA |
| 4 Face & window | Component kit; views; setup; settings; Pip puzzled pose and voice table; accessibility | 1.5 wks | G5; window design ≥7 |
| 5 Ship plumbing | Signing, notarization, updater, kill file, uninstall, CI, privacy page, license | 1 wk (can overlap 3–4) | G3 |
| 6 Private beta | 14 users, 2 weeks, plus 1 week of fixes | 3 wks | The D11 rules |
| 7 Public v1 | Show HN, r/ClaudeAI, Homebrew | — | All gates still passing |

- **Timeline.** About 6–7 weeks to beta, about 9–10 to public v1.
- **After v1.**
  - **v1.1:** calendar heads-up (founder decision #6); Start session with a prompt and native
    modes; AI drafts of "Your week" through the user's own CLI; the on-device fallback experiment.
  - **v1.2:** Sparks and `sidefolk here`, if their gate passes; more agents (Gemini CLI, OpenCode);
    Apple Reminders export, if phone reach drove churn.
  - **v2:** the paid character pack; teams ("ask the reviewer to check this"); the everyday
    positioning, if the D1 gate passes.

## Where I overrule the founder, and why

| Founder position | My ruling | Reason |
|---|---|---|
| v1 is for non-technical users too | Developers first, with a gate | No phone sync and no channel; a split audience made the "maze" |
| MVP order: Reminders → … | Trust core first | Every outside user's first minute hits the permission path |
| Pip and Spark | Pip only | One pet with a session list scales to 6 sessions; 7 creatures don't |
| Quick actions as pillar #3 | Beta behind `$` | English became shell commands; that's a trust failure |

**What I respect.** Reminders and the log stay first-class. The Dock app stays. Calendar is next
(v1.1). AI stays layered and optional. Sessions open the way the founder chooses in Settings.
