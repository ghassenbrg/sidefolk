# Sidefolk v1: binding ruling of the supreme council

25 October 2026 · Chair and final word: Nadia (CEO) · Seats: Marcus (CTO), Aiko (CPO) · Source
revision `76b38f1`

This record replaces PLAN-V2 §6–§10 and ROADMAP as the v1 contract. Phase 0 copies it into the repo
as `docs/V1.md`, with item IDs. Every point is decided. Where a fact is unknown, the ruling names
the spike, its length, and the fallback that ships if the spike fails. Three things change it:

- the founder's veto, in writing, on the items in §17;
- a beta rule in D11;
- a dated one-in-one-out decision (D12).

---

## The bet

**Keep the codebase and cut the product.** All 16 audit seats and all three supreme seats reject
a restart.

An agent-status pet is now table stakes: the Codex app gives pets away, and notch monitors cost
$0–20. Reminders and notes on their own lose to Apple and Raycast. The one thing that's ours is
**a single companion that holds your commitments and your agents' asks, takes you to them, and
remembers what got done.** The founder's four priorities describe a developer's workday, so v1
serves that person well.

## D1. Audience and promise

**Who it's for:** Mac developers who run Claude Code (with Codex as a beta) and want their own
reminders and a work log in the same place.

> **Pip sits on your desktop, taps you when Claude Code or a reminder needs you, takes you to that
> exact session, and keeps a dated log of what you got done.**

**Two release tracks.** The risky half can't hold the safe half hostage.

- **Core track** (required for v1): reminders, the work log, quick-add, one Pip, release basics.
- **Agent track** (required to be called *stable*): Claude Code status, requests on Pip, Open
  session.
- If the agent track fails its native gate (G2-agent) **one week** after its phase ends, v1 ships
  with:
  - Sessions as a labelled beta;
  - **no approvals from Pip**;
  - the promise without its "session" clause.

**A calm path without AI tools.** "Skip, I don't use AI tools" in setup gives Today, Reminders and
Work log, with no developer vocabulary anywhere. That's a beta gate, not marketing.

**Widening gate to everyday users (direction A).** Both conditions must hold:

- ≥30% of weekly beta actives use reminders or the log with no agent connected, for 2 weeks
  running;
- the Apple Reminders export (v1.1) has shipped.

Until then nothing says "for everyone". Rejected: C ("everything for everyone") and A as the
headline.

## D2. Final feature inventory

**What each call means:**

- **STABLE:** promised, gated by D11.
- **BETA:** in `main`, under Settings → Labs, off by default, never in marketing.
- **LATER:** no UI in v1. Whether the code is kept or deleted is stated per row. Deleted code can
  be recovered from tag `v0.2-pre-cut`.
- **DELETE:** removed, and not expected back.

| # | Feature | Ruling | Code | Reason |
|---|---|---|---|---|
| 1 | Pip companion | STABLE | keep | The face and the brand |
| 2 | Typed phrase input (companion) | STABLE, reworked as Quick add (D5) | refactor | One engine, never a dead end |
| 3 | Tell bar | STABLE as the window's Quick add field plus ⌘K | refactor | Must finish in the window (F07) |
| 4 | Reminders: one-off | STABLE | refactor | Founder's #1 |
| 5 | Reminders: repeat | STABLE under D3 | rewrite into Rust | Series contract |
| 6 | Reminders: snooze | STABLE | refactor | Moves the occurrence only |
| 7 | Reminders: history | STABLE, inside the reminder's details | keep | Recovery |
| 8 | Notes & notebooks | STABLE as **Work log** with topic notebooks | refactor | Founder's #2; retention |
| 9 | AI draft summary | LATER (v1.1, rebuilt with timeout and cancel) | **delete** | No timeout; spends quota |
| 10 | Quick shell commands | BETA, `$` prefix only, always shown in the user's terminal after an exact preview | keep `run_in_terminal` | Founder's #3, kept honest |
| 11 | Saved actions | LATER | **delete** (store, UI, background runs) | No lifecycle (R18); Raycast does it |
| 12 | Open app/folder/URL | STABLE (https only, no shell, runs *after* time detection) | keep | Cheap, safe, ordinary speech |
| 13 | Watching Claude Code | STABLE (agent track) | refactor | Acquisition wedge |
| 14 | Watching Codex | **BETA, whatever the spike finds** | new code after the spike | Nothing watches Codex CLI today |
| 15 | Permission requests on Pip | STABLE for Claude Code (agent track); none for Codex | refactor | Signature moment, under D6 |
| 16 | Per-session full access | DELETE | **delete** `src/access.ts` and "Allow everything" | A deny-list can't be honest |
| 17 | Start sessions | BETA: Claude Code only, with a prompt field, launch mode = Claude's own | refactor | Founder's #4; not why people install |
| 18 | Open/continue session | STABLE (host matrix in D6) | refactor | The reason to click |
| 19 | Sparks | LATER (v1.2, gated) | **delete runtime** (`workers.ts`, crew bindings); keep art in `art/` and `public/crew/spark` | Rebuilt on Rust state if earned |
| 20 | Terminal inside Sidefolk | DELETE | **delete** `inside.rs`, `terminal.ts`, `portable-pty`, xterm | TCC and keystroke-injection surface |
| 21 | Calendar heads-up | LATER (first item of v1.1) | **keep** behind a Cargo feature `calendar`, off in v1 builds; no EventKit entitlement in v1 | Honors founder decision #6 |
| 22 | Morning brief | DELETE | **delete** | Replaced by "While you were away" (v1.1, new code) |
| 23 | Weekly wins | STABLE as **Your week**: a plain dated list with Copy, no AI | new small view | Retention; the evaluation use case |
| 24 | Ten characters | DELETE from the app; art stays in `art/` and the tag | **delete** `characters.rs`, roster, bundled crew art except Pip | Catalog churn; 5.2 MB |
| 25 | 3D/2D styles | DELETE 2D; Pip ships in 3D clay frames only | **delete** | Doubles the art cost |
| 26 | Character import/export | DELETE | **delete** (698 lines) | Untrusted parsing, no v1 value |
| 27 | Accent colors | LATER (v1.1, as Pip's scarf) | **keep** `recolor.ts` (Spark reuses it); remove the UI | A look change reloads the overlay today (`main.ts:264`) |
| 28 | Sounds | STABLE: soft blips, one "needs you" chime, one reminder chime, one Quiet switch | keep | Matters more than visuals |
| 29 | TTS voice | DELETE | **delete** `voice.rs` | Breaks the character; VoiceOver covers access |
| 30 | Setup guide | STABLE, rewritten (D8) | rewrite | Must prove a round trip |
| 31 | Settings | STABLE, a ⌘, window with 4 panes | rewrite | Down from 9 |
| 32 | CLI `sidefolk here` | LATER (with Sparks) | **delete** (the admin-password install too) | Only means something with Sparks |
| 33 | MCP notify / ask / remind | STABLE; `ask` gains session identity and a visible deadline | refactor | Agents reach you |
| 34 | MCP presence | STABLE | keep | It's idle/away detection, the "hold when away" signal |
| 35 | MCP spark | LATER | **delete** with Sparks | — |
| 36 | Dock app + window | STABLE | keep | Founder decision #4 |
| 37 | Menu bar icon | STABLE: status dot, Show/Hide Pip, Quick add, Pause answers, Quit | keep, extend | Recovery path |
| 38 | Hide from screen recordings | STABLE; the default depends on a spike (D10) | keep | Trade-off with Mission Control |
| 39 | Copy report | STABLE with a preview and redaction | refactor | Support channel |
| 40 | `codex.rs` app-server driver | DELETE | **delete** (399 lines, no caller) | Dead |
| 41 | Blender film-duo pipeline (staged) | Not on `main`; moved to branch `art/film-duo` | — | Art freeze |

## D3. Reminder contract

1. **Two kinds.**
   - A **one-off**.
   - A **repeating alert**, which works like a calendar repeat.
   - "Repeat after I finish" is LATER.
2. **Series vs occurrence.**
   - A series stores its rule plus a wall-clock anchor (floating local time, or an explicit IANA
     zone if the user picked one).
   - Occurrences are computed, and overrides (snooze, skip) are stored per occurrence.
   - The engine lives in Rust (`reminders.rs`). It leaves `src/reminders.ts`.
3. **Firing.**
   - Every occurrence fires on schedule, whether or not the last one was handled.
   - **Done** completes that occurrence. **Skip next** exists.
   - Editing a series asks "This one / All future".
4. **Snooze.**
   - Offered as 10 min, 1 h, This evening (18:00), Tomorrow 9:00, or Pick.
   - It moves one occurrence. **The anchor never moves**, so a Monday weekly reminder snoozed to
     Tuesday stays on Mondays.
5. **Unhandled.**
   - **A one-off stays Overdue on Today until it's handled. It is never auto-hidden.**
   - A repeat occurrence folds into history as *missed* only when the next occurrence fires.
   - There is one sound and one card. After 2 minutes the card folds, and Pip keeps holding the
     note with a count badge. No re-nag.
6. **Quit, sleep and late.**
   - macOS owns the alarms. On every change, Sidefolk pre-schedules, in this order:
     - all one-offs;
     - the next occurrence of every series;
     - further occurrences round-robin, up to 60 pending (under the OS limit of 64).
   - On launch or wake, one card says "While you were away: N reminders". Each shows its original
     time and a *late* tag, and only the latest missed occurrence per series appears.
   - Start at login is **on** from setup.
   - If notifications are denied, setup says plainly: "Reminders show only while Sidefolk is
     running."
7. **DST and month ends.**
   - A time that doesn't exist (spring forward) fires at the next valid minute.
   - A time that happens twice (fall back) fires once, the first time.
   - "Every month on the 31st" means the last day of shorter months.
8. **Phone reach.**
   - None in v1. Setup and the editor say "Reminders appear on this Mac."
   - v1.1 adds a per-reminder **"Also add to Apple Reminders"**: EventKit, write-only, in its own
     list, with Sidefolk's own alert suppressed for those reminders.
   - Two-way sync: never in v1.x.
9. **Agent-aware reminder:** "remind me when api finishes" fires on that project's next
   *done* event. It's STABLE when the agent track ships, and it expires after 24 h with a note.

## D4. Work log contract

- **Name and shape.**
  - The sidebar item is **Work log**.
  - It holds a default notebook, **Log**, which is the inbox, plus any topic notebooks the user
    creates ("any memory topic", founder's #2).
  - Files stay plain Markdown on disk.
- **Destinations.**
  - "note: …" goes to Log without a question.
  - "note for X: …" needs an exact name or alias match, case-insensitive. Otherwise:

    | Situation | What Pip does |
    |---|---|
    | One near match | Asks "Add to *Evaluation H2 2026*?" |
    | Several matches | Shows a choice list |
    | No match | Offers "New notebook 'X'" or Log |

  - The draft is never lost while the user decides.
  - The most-recently-updated guess is deleted (F06).
- **Visible.**
  - The destination shows in the preview before saving.
  - After saving: "Noted in X · Move · Undo". Undo stays until dismissed, and ⌘Z works.
  - Move is available on every entry.
- **Timeline and search.**
  - "All entries" is one dated stream, grouped by week, filterable by notebook and project.
  - Search matches both text and dates ("October", "last week", "2026-04").
- **Agent work.**
  - A finished Claude Code session offers **Log it** on its done card and session row.
  - It's prefilled with "api: <first prompt line>", and the user can edit it.
  - Only the project and the first prompt line are stored, never output, commands or summaries.
  - Nothing is written automatically.
- **Your week.**
  - Friday at 16:00 (configurable, or off), Pip holds up "Your week: N entries".
  - The view shows that week's entries plus completed reminders, with **Copy as Markdown**.
  - No AI in v1.
- **Export.** Copy as Markdown for each notebook, for each week, and for everything (copies the
  folder). Show in Finder.

## D5. Input rules

The field is labelled **Quick add**, with the placeholder "Remind me…, note…, open…". There is
one engine (`commands.ts` + `when.ts`, pure TypeScript), used by both the companion and the
window. A task finishes on the surface where it started.

**Precedence, in this order:**

1. **Card answers** while a card is focused ("allow", "decline", "snooze").
2. **`$ …`**
   - A terminal preview, but only when Labs → Quick actions is on.
   - Otherwise: "Commands are off. Turn on in Settings → Labs".
   - There is **no `run …` prefix**.
3. **App and session verbs:** "what's today", "show notes", "sessions", "open api session",
   "continue docs", "undo".
4. **`note[ for X]: …`** and **`log …`** go to the work log (D4).
5. **Any resolvable date or time** makes a reminder draft. This runs **before** `open`, so "open
   enrollment closes friday 5pm" becomes a reminder.
6. **`open …`** opens an app, a folder or an https URL, after a preview.
7. **About 20 canned in-voice small-talk replies,** each with a pose.
8. **Everything else** becomes a Log note draft, with "Make it a reminder… / Discard".
   - There is never an "I don't know", and **English never becomes a shell command**.
   - An unknown first word is never treated as a command.

**Times:**

| Phrase | Means |
|---|---|
| A bare hour, "at 3" | The soonest future of 3:00 or 15:00 that falls between 07:00 and 21:59 |
| "tonight" | 20:00 |
| "this evening" | 18:00 |
| "end of day" | 17:00 |
| "morning" | 09:00 |
| "afternoon" | 15:00 |

- **All** of chrono's results are used, so "standup 9:30" keeps 9:30.
- Compound weekday lists ("Monday and Thursday") are supported. Anything unsupported gets a
  question, never a partial accept.
- **The resolved date and time always show before saving.**
  - Unambiguous: Enter saves, and Undo appears.
  - Ambiguous: inline choices ("3 PM today · 3 AM tomorrow").

**No model in v1.** In v1.1, Apple's on-device model may only propose a structured draft for the
step-8 bucket, always with a confirmation. Cloud models run only behind a visible "uses Claude"
label. (This is founder decision #3's layering, with layer 1 made excellent first.)

**Corpus:** 300 phrases checked into `npm test` (150 everyday, 100 developer, 50 adversarial). It
runs on a fixed clock, in two time zones, across DST dates. The gates:

- ≥95% correct intent and time overall;
- **100%** with no shell offered without `$`;
- **0** reminders saved without a visible resolved time;
- **0** silently wrong times (ambiguous input asks).

Every miss found in the beta becomes a corpus line.

## D6. Developer contract

**Tools:**

- **Claude Code** (stable, agent track): hooks, requests on Pip, MCP.
- **Codex** (beta): status plus MCP `notify`/`ask`/`remind`. **Pip never answers Codex
  approvals**; the card reads "Codex needs you in api · Open".
- **Codex spike:** 2 days in P4, to find Codex's *documented* signals for its installed version
  (the `notify` program, plus any hook mechanism).
  - Undocumented rollout-file parsing is not allowed.
  - Fallback: "turn finished" via `notify` only, with no "needs you" claim.
  - Codex goes stable in v1.x only after a matrix pinned to Codex versions.

**Host capability matrix.** What ships in v1; spikes run in P4.

| Host | "Open" in v1 | "Is that session focused?" (routing) | Spike, and its fallback |
|---|---|---|---|
| Terminal.app | Exact tab (tty, exists) | Exact: frontmost + selected tab's tty | — |
| iTerm2 | Exact tab (tty, exists) | Exact | — |
| Ghostty 1.3+ | Bring forward + "select the session there" | Focused only if Ghostty is frontmost **and** hosts just one live Claude session | 1 day: can AppleScript read each terminal's tty or cwd? If yes, exact tab and exact routing; if not, the fallback stands |
| WezTerm | Bring forward | Same as Ghostty; added to the host list (it's missing today) | 0.5 day: `wezterm cli list` / `activate-pane`. If it works, exact |
| VS Code / Cursor | Bring forward that project's window if `open -a` with the folder does it; otherwise the app | Same as Ghostty | 0.5 day |
| Warp | Bring forward | Never "focused"; always show on Pip | — |
| Claude desktop | Bring forward | Never "focused" | — |
| tmux / ssh / unknown | "Running in tmux on ttys004 · Copy attach command" | Never "focused" | Exact tmux targeting: v1.1 |
| Ended session | `claude --resume <id>` in the default terminal | — | — |

- A live process is **never** resumed a second time.
- Settings → Agents shows this matrix to the user, word for word.

**Routing.**

- A request is held on Pip unless *that session* counts as focused, using the column above. If
  focus is unknown, the request shows on Pip.
- If the user then focuses that session, Pip **releases within 1 s** to Claude's own prompt, and
  the card turns into "Moved to your terminal · Open".
- `presence` decides nothing about routing. It only stops the chime when the user is away.

**Hold.**

- Keep today's **60 s** (`PERMISSION_WAIT`), under the installed 90 s hook timeout.
- The card says "Claude waits about a minute, then asks in your terminal".
- When time runs out, the request is released and never allowed or declined.
- A released or expired request can never later become an Allow (enforced in `requests.rs`).

**Display.**

- Rust stores the **raw, immutable** tool input, and the display is derived from it.
- Commands show byte-exact: whitespace kept, no ligatures, control and bidi characters as visible
  escapes.
- Edit shows the real diff from `old_string`/`new_string`. Write shows the full content. MCP calls
  show pretty-printed JSON.
- Anything over the card opens a full view. **Allow appears only once the whole operation has
  been shown.** Anything that can't be shown gets "Answer in terminal" and Open only.
- Risk labels are warnings only. On a flagged command, Decline is the default button.

**Buttons:** Allow once · Decline · Answer in terminal. There is no "always" and no "allow
everything".

**Full access.**

- Sidefolk never auto-answers. `access.ts` is deleted.
- Start session (beta) offers Claude's own permission modes, each named in Claude's terms and
  explained in one line. The session row shows the mode as a read-only badge.

**Identity.**

- Sessions are labelled project + first prompt line + host.
- Clicking Pip opens a compact session list ("api · needs you / web · working / docs · done").
  Done and failed events queue behind an open request; they're never dropped.

**If Sidefolk isn't running, or was deleted,** Claude Code behaves exactly as it would without
Sidefolk installed (D10 wrapper).

## D7. Character, brand and voice (frozen until public v1)

- **Pip** is the shipped ivory clay bunny: charcoal ear tips, mint scarf, pre-rendered 3D frames,
  one style.
- **The logo is unchanged.** The charcoal Pip Signal stays the app icon and wordmark, as DECISIONS
  #37 and the review README require. My round-1 redraw is withdrawn. Wherever Pip *speaks*
  (request cards, the sidebar avatar, setup), the ivory character appears, not the glyph.
- **Spark** comes later; its art is frozen in the repo. No other species.
- **Allowed art work, and nothing else:**
  - a **puzzled** pose (head tilt, one ear folded);
  - up to six micro-frames: look left, look right, ear twitch, tilt, anticipation crouch, hold up
    note;
  - cross-fades between poses;
  - an automatic warm rim on dark wallpapers.
- Every visual change needs a 150 px check on light, mid and dark wallpapers and a written reason.
- **Signals.** The blue work signal appears only during real agent activity; the idle "thinking"
  pose loses it (Ines-C). Orb placement is fixed for Pip.
- **Character bible:** `creative-design/PIP.md`, written in P0 from Ines's draft and CPO D7.
  - Pip is a quiet desk-mate and messenger, **not an AI**.
  - Traits: attentive, earnest, unbothered. The ears carry the grammar.
  - The pose map is the CPO's table, including puzzled.
  - Pip never nags twice, never walks around the desktop, and never celebrates something that
    didn't succeed.
- **Voice rules:**
  - One sentence of ≤12 words, then the buttons.
  - "I" for Pip's acts; the agent is named for its own.
  - No guilt, no emoji. Exclamation marks only on done.
  - When Pip misses something, it owns the miss and offers the nearest thing.
  - Permission cards stay plain.
  - Every error goes through a table in `src/states.ts`. A test fails if any bubble or window
    string contains snake_case, "Error:" or `String(e)`.
- **Frozen:** the roster, styles, logo, silhouette, palette, name, voice rules and art pipelines.

## D8. App shell and UI

- **Shell:**
  - Dock app, window and menu bar icon (founder decision #4).
  - Closing the window keeps Pip and reminders running.
  - "Hide from Dock" is in Settings.
- **Window: re-implement the view layer on a component kit, against the approved mockups**
  (`creative-design/review-2026-10-24`).
  - It starts **after P1**, so views are built on the Rust state layer.
  - `dashboard.css` and `redesign.css` are replaced by one stylesheet built on `tokens.css`.
  - Tokens, status words and accessibility semantics are kept.
- **Sidebar**, one level:
  - **Today** (Needs you → Running → Today's reminders → Recent log);
  - **Sessions**, which appears once Claude Code is connected;
  - **Reminders**;
  - **Work log** (notebooks are a list/detail pair inside it).
  - Actions is gone.
- **Settings.** A standard ⌘, window with a category sidebar. This keeps mockup 05's structure and
  drops its "Back to Sidefolk" link, a deliberate change to the approved mockup. Four panes:

  | Pane | What it holds |
  |---|---|
  | **General** | Login, Dock, theme, reduced motion, text size, shortcut, sounds, default snooze, Your week |
  | **Companion** | Name, size, position, sleep |
  | **Agents** | One "Connect Claude Code" switch (hooks and MCP together, with a backup), real health states, default terminal, the host matrix, Codex (beta) |
  | **Privacy & data** | Recording protection, history retention, Clear, Export, Copy report, Disconnect & uninstall |

  A **Labs** row under General holds Quick actions and Start session.
- **Component kit** (about 12 pieces):
  - Buttons: primary, secondary, destructive, plus an overflow ⋯ menu.
  - A list row with at most 2 visible actions.
  - Text field, and real date and time fields that hold a value (fixes B7).
  - Popup, segmented control, toggle, sheet.
  - A toast with persistent Undo.
  - Status dot + word.
  - Empty, loading, error and stale states with Retry. Damaged data never shows as "No reminders
    yet".
- **Visual bar:**
  - window controls 24–28 px (44 px only on overlay cards);
  - hairlines, not outlines; 13 pt base type;
  - one icon set at one stroke weight;
  - a warm dark theme that matches cream;
  - one locale-aware date format.
- **Setup** has three steps:
  1. Pip waves, and the user sets one real reminder, which saves with its time showing.
  2. Notifications and start at login, with the results stated honestly.
  3. "Do you use Claude Code?" Connect and wait for a **live first event**, or "Skip, I don't use
     AI tools".
- **Accessibility:**
  - The summon key opens Quick add, and a second shortcut focuses the newest card.
  - Cards are reachable by Tab and announced by VoiceOver.
  - Focus never drops to `BODY`.
  - Nothing important disappears on a timer.

## D9. Architecture

Keep the stack (Tauri 2, Rust, TypeScript, frame renderer) and **move the truth into Rust**. The
webviews only subscribe to typed events and invoke commands. An overlay reload loses nothing.

| Module | Ruling |
|---|---|
| new `store.rs` | ADD. One versioned envelope `{version, data}` for every JSON store. Each load is Missing, Ok or Corrupt. A corrupt file moves to `*.corrupt-<ts>` and is **never overwritten**; the last good copy is written to `.bak` on each good load. Migrations come with fixture tests. |
| new `requests.rs` | ADD. One authoritative lifecycle: pending → answered / released / expired. It holds the raw operation, the derived display, and a per-session cap. |
| `hooks.rs` | REFACTOR. The lifecycle moves out; it gets the D6 routing; clipping is for display only. |
| `bus.rs`, `prefs.rs` | REFACTOR into typed events and typed state (generated TS types, `ts-rs`), with no 1 s or 3 s polling. Config files are watched by mtime. |
| `reminders.rs`, `notifications.rs` | REFACTOR. The series engine from D3, plus pre-scheduling. |
| `notes.rs`, `src/notes.ts` | REFACTOR. Log/inbox, exact-or-ask matching, timeline index, export. The draft summary is removed. |
| `settings.rs` | FIX. A corrupt file is quarantined, defaults load, and a banner appears. No `expect` at launch. |
| `sessions.rs` | FIX. No double resume, first-prompt names, the D6 matrix. |
| `claude_setup.rs`, `mcp_setup.rs` | EXTEND. A sidecar hook, uninstall, health states; installers refuse to run when the app is translocated. |
| `mcp.rs` | KEEP. `spark` is dropped; `ask` gains identity and a deadline. |
| `journal.rs` | REFACTOR. First prompt line only, 7-day retention, an off switch, Clear. |
| `actions.rs` | TRIM to `run_in_terminal` and open. |
| `crew.rs` | REPLACE with typed companion settings in `store.rs`. |
| `panel.rs`, `overlay.rs`, `tray.rs`, `app_menu.rs` | KEEP. The tray gains Pause answers and Uninstall. |
| `main.rs` | FIX. A single-instance plugin; a socket bind failure shows in the UI; IO commands run async. |
| `codex.rs`, `inside.rs`, `characters.rs`, `voice.rs` | DELETE. Also `portable-pty` and xterm. |
| `calendar.rs`, `calendar.ts` | KEEP behind the `calendar` feature, off by default. |
| `src/access.ts`, `terminal.ts`, `character-import.ts`, `dashboard/characters.ts`, `familiar.ts`, `workers.ts` | DELETE. |
| `src/companion.ts`, `agents.ts` | REFACTOR to render Rust state and hold none. |
| `src/commands.ts`, `when.ts` | REFACTOR to the D5 grammar and corpus. |
| `src/dashboard/*` | RE-IMPLEMENT the views (D8) after P1. `tell.ts` uses the shared service. |

**Error handling.**

- IO and parse errors become UI states. There's no `unwrap` on IO or parsing.
- `lock().unwrap()` stays: under `panic = abort` a lock can't be poisoned (CTO).
- `eprintln` output goes to a log file. dSYMs are archived for each release.

**Tests to add:**

1. The in-process hook flow: allow, decline, release on focus, expiry, app not running, and "a
   long prefix can't change the outcome".
2. Corrupt, unreadable and disk-full cases for each store.
3. Recurrence on fixed clocks: DST in two zones, month ends, snooze, skip.
4. The 300-phrase corpus.
5. An install → uninstall round trip on temporary `CLAUDE_CONFIG_DIR` and `CODEX_HOME`, with a
   byte-identical restore.
6. An overlay reload with an open request (WebKit).
7. The voice-table string check.
8. A release script that fails closed when WebKit or any other check is missing.

## D10. Security, privacy, distribution

| Item | Decision |
|---|---|
| Hook transport | The nine HTTP hooks become **`command` hooks** calling a small signed sidecar, `sidefolk-hook` (Tauri `externalBin`). It forwards stdin over a **Unix socket in the 0700 data folder**, with a check that the peer has the same uid. The hook line is a guarded wrapper: `test -x <sidecar> && exec <sidecar> hook \|\| exit 0`. If the app isn't running or was deleted, events exit 0 and PermissionRequest returns no decision, so Claude asks normally. **The socket can't be taken over** (fixes B5). |
| Uninstall | "Disconnect & uninstall…" in Settings and in the tray. It removes only our hook and MCP entries (with backups), the login item and the CLI link. Data is kept by default, with "Export first / Delete data". `sidefolk-hook uninstall` works even after the app is in the Bin. |
| Signing | Developer ID, hardened runtime, `notarytool` with a keychain profile or an API key (never `APPLE_PASSWORD` in the environment), and a stapled DMG. |
| Entitlements | `automation.apple-events` plus `NSAppleEventsUsageDescription`. No calendars until v1.1. No App Sandbox. |
| Updater | `tauri-plugin-updater` with a signed `latest.json` on GitHub Releases. The key stays offline or in a CI secret. Updates install with consent and show release notes in Pip's voice. The feed carries **`min_safe_version`**: below it, Pip stops holding requests (kill switch). There is also a local Pause answers. |
| Hide from recordings | A 0.5-day spike in P5: the founder checks Mission Control with the protection on now that the overlay only covers the companions (`c2b6544`). If that's acceptable, the default is **on**. If not, it stays off, and setup step 3 offers "Hide Pip's cards from screen shares?". |
| Platform | **macOS 14+, Apple Silicon only.** The 13.0 metadata gets fixed. Intel ships only when someone can test it. |
| Crash reporting | A local crash log plus dSYMs. No network upload in v1. Copy report shows a preview and redacts. |
| Privacy | A one-page in-app statement: what stays local, what the journal keeps (first prompt line, 7 days), and when data leaves (only a "uses Claude" action the user clicks). |
| License | Code: **MIT**. Pip's art, name and logo: **all rights reserved**. |
| Price | Free. A paid cosmetic pack is an idea for after v1, not a plan. |
| Channel | A notarized DMG on GitHub Releases plus a one-page site. A Homebrew cask right after public v1. Not the Mac App Store. |

**The precondition for outside users.** No one outside the team enables approvals until four
things ship: the fail-closed sidecar, Disconnect & uninstall, the signed updater and the kill
switch.

## D11. Release gates, beta and decision rules

Each gate is a file in `docs/checks/`, with the date, the build hash, and pass/fail per line,
recorded by the founder on a signed build in a clean macOS user account.

| Gate | Pass condition |
|---|---|
| **G1 Trust** | B1, B2, B5, B9 and F01–F03, F05, F06 are closed, each with a regression test. No code path auto-answers. 0 wrong-session approvals in a 3-session, 3-host test. |
| **G2-core Native** (about 25 lines) | Reminders while visible, hidden, window closed, quit, locked and asleep/wake; notifications denied then enabled; a DST change through a time-zone switch; corrupt-file recovery for each store. |
| **G2-agent Native** (about 20 lines) | Every row of the D6 matrix: hold, release within 1 s, 60 s expiry, Open per host, no double resume, and the setup round trip. |
| **G3 Input** | The D5 corpus gates. |
| **G4 Access & design** | Keyboard-only and VoiceOver runs of journeys J1–J4 pass. The founder signs off 5 screens side by side with the mockups in both themes. A design re-review scores ≥7/10. The voice check passes. |
| **G5 Ship** | A clean install from the downloaded DMG passes Gatekeeper. An update from 0.9.0 to 0.9.1 keeps the data. Uninstall restores configs byte-identically. Release CI is green. |

Journeys J1–J7 are the CPO's set: first ten minutes with and without agents, Needs you,
the reminder lifecycle, log and read-back, Come back, and Uninstall. They're adopted as written,
except that J6 "Come back" is v1.1.

**Private beta.** It needs G1–G5.

- **Wave 1:** 8 developers who use Claude Code daily (not pet fans), plus 3 people with no agents.
  It runs 2 weeks with the updater live.
- **Wave 2:** if wave 1 had zero trust incidents, grow to 20 people for 2 more weeks.

**Measurement.** There is no telemetry.

- An opt-in "Copy weekly summary" with counts only:
  - reminders fired and acknowledged on time;
  - log entries kept;
  - requests answered on Pip vs released;
  - Open successes and misses (one-tap thumbs-down);
  - Quick add misses;
  - hides and quits, each with a one-tap reason.
- Interviews on day 7 and day 14.

**Targets** (wave 1, judged at day 14):

| Metric | Target |
|---|---|
| Activation on day 1: a reminder created, Claude connected, and one request answered or session opened from Pip | ≥6/8 developers |
| Developers using it on ≥3 days a week in week 2 | ≥5/8 |
| Open success | ≥95% |
| Users keeping ≥3 log entries a week | ≥4 of 11 |
| Trust incidents (wrong-session approval, lost note, missed supported reminder) | **0** |

**Rules:**

- **Any trust incident freezes the beta** until a fix ships with a regression test.
- **Continue to public v1:** all targets met, and G1–G5 still pass on the release build.
- **Switch the promise to the core track:** developers release most requests to the terminal but
  keep reminders and the log. Then approvals are dropped from the promise.
- **Switch to direction A:** users without agents retain better than developers.
- **Stop feature work and rethink:** fewer than half of all testers are still using it on day 14.

## D12. Guardrails for the agents

1. **`docs/V1.md` is the only contract**, with item IDs. PLAN-V2 §6–§10 and ROADMAP point to it.
2. **Additions:** one in, one out, through a dated DECISIONS entry that names what it displaces, a
   24-hour wait, and the founder's yes. "The user asked" means *write it down*, not build it that
   hour.
3. **Work in progress = 1.** "Done" means tests plus a dated founder hand-check line with a build
   hash in `docs/checks/`.
   - Agents never mark anything done.
   - Output is capped at **2 verifiable items a day**.
4. **CI:**
   - typecheck, vitest, cargo test, `clippy -D warnings`;
   - the WebKit check (it can't be skipped);
   - the corpus and the voice check.
5. **Changes to `hooks.rs`, `requests.rs`, the sidecar, installers, uninstall or `store.rs`** need
   a second agent's review (Claude ↔ Codex) with adversarial cases.
6. **Code discipline:**
   - no new dependency, permission or entitlement without a DECISIONS line;
   - no commit over about 600 net added lines (deletions don't count);
   - cutting a feature deletes its code.
7. **Art and pipelines are frozen.** Nothing staged goes in without a V1 item ID.
8. **No claim without a matrix row.** No UI claim, sample data or preview may show a capability
   that has no row in the matrix. README and GUIDE change in the same commit as the behavior.
9. **STATUS.md** is rewritten at each handoff and kept to ≤150 lines. History goes to
   `memory/LOG.md`.
10. **Global agent configs:** agents never touch them (AGENTS.md). Development uses temporary
    config dirs.

## D13. Roadmap

Sizes are in agent-days, plus founder time. Everything runs in sequence unless marked parallel.

| Phase | Work | Size | Founder | Exit gate |
|---|---|---|---|---|
| **P0 Reset** | Commit and tag `v0.2-pre-cut` (on the founder's word); move film-duo to its branch; write `docs/V1.md` and the capability matrix; write `PIP.md`; delete the D2 list (about 2,500 lines); fix the metadata, copy and sample data; set min OS to 14 | 2–3 | 1 h; buy the Apple account | Green build; only v1 surfaces reachable; STATUS rewritten |
| **P1 Foundation** | `store.rs`, `requests.rs`, typed events, state into Rust, single instance, bind health, async IO | 8–10 | 1 h | Corruption and reload-with-open-request tests pass; no polling |
| **P2 Reminders & log** | Series engine, pre-scheduling, missed/late, Log + notebooks exact-or-ask, timeline, export, Your week | 6–8 | 2 h | Fixed-clock suite; G2-core |
| **P3 Quick add** | Grammar, precedence, finishing on the same surface, the 300-phrase corpus | 3–4 | 30 min | G3 |
| **P4 Claude Code trust** | Sidecar + socket, routing/release, raw display + diffs, identity, session list, Open fixes, setup round trip, health; spikes for Codex, Ghostty, WezTerm and VS Code | 9–12 | 3 h, 3 sessions | G1; G2-agent (or the two-track fallback) |
| **P5 Window & Pip** | Component kit, view re-implementation, Settings window, setup, keyboard/VoiceOver, durable Undo, voice table, puzzled pose and micro-frames, recordings spike | 7–9 | 2 h + VoiceOver | G4 |
| **P6 Release engineering** (in parallel from P1, by a second agent, touching only release files) | Signing, notarization, entitlements, updater + kill switch, uninstall, privacy page, redaction, CI | 4–5 | 2 h + Apple wait | G5 |
| **P7 Private beta** | Waves 1 and 2, fixes | 4 weeks | Interviews | D11 rules |
| **P8 Public v1** | Site, release notes, launch (Show HN, r/ClaudeAI), cask | 1–2 | 1 h | All gates on the release build |

**Calendar:**

- about **7–8 weeks to private beta**;
- about **11–12 weeks to public v1** (wave 2 adds two weeks).

**If it slips:** if P4 runs more than a week late, the beta starts on the core track with Sessions
in beta. The scope moves, not the date.

**After v1:**

- **v1.1:** calendar heads-up (the founder answers Mac vs web calendar); Apple Reminders export;
  scarf colors; "While you were away"; tmux exact targeting; the AI "Your week" draft through the
  user's own CLI, with a timeout; the on-device model for the Log bucket.
- **v1.2:** Sparks on Rust state plus `sidefolk here`, gated on beta users running 3+ sessions and
  asking for it; Codex stable after a version-pinned matrix; more agents (Gemini CLI, OpenCode).
- **v2:** teams ("ask the reviewer to check this", only for sessions Sidefolk launched); the
  everyday positioning if the D1 gate passes; a cosmetic pack.

---

## 15. Answers to the CTO's and CPO's objections

| # | Objection | Ruling | Why |
|---|---|---|---|
| CTO-1 | Codex can't be stable in v1; the rollout format isn't ours | **Accepted** | Codex is BETA whatever the spike finds; only documented signals are allowed. My round-1 claim of existing rollout code was wrong. |
| CTO-2 | Exact tab for tmux and Ghostty is promised without code | **Accepted** | The matrix ships bring-forward and copy-attach; exact only after a passed spike; tmux exact in v1.1. |
| CTO-3 | The CPO's parallel phases break WIP=1 | **Accepted** (the CPO agreed) | P1 state comes before the P5 views. Only release engineering runs in parallel, on separate files. |
| CTO-4 | The CEO's schedule is a week short | **Accepted** | P1 is now 8–10 days and P4 is 9–12. Public v1 lands in about 11–12 weeks. |
| CTO-5a | "No mutex unwrap" is busywork under abort | **Accepted** | IO and parse unwraps go; lock unwraps stay. |
| CTO-5b | "As if never installed" needs a guarded wrapper | **Accepted** | Now in D10. |
| CTO-5c | The hold is 60 s today; my 45 s was a change | **Accepted** | Keep 60 s, under the 90 s hook timeout. |
| CTO-F | `presence` is idle/away detection, not Sparks | **Accepted** | It's STABLE. My round-1 delete was a factual error. |
| CTO-F | Accent colors cost an overlay reload today | **Accepted** | LATER (v1.1), with `recolor.ts` kept. That also fixes my D2/D9 contradiction. |
| CTO-F | The hide-from-recordings default is a Mission Control trade-off | **Accepted** | A spike plus the founder's check decides it (D10). |
| CTO-F | "16 of 16 seats" was inexact (Omar voted rework) | **Accepted** | The conclusion stands: no seat defends the deny-list. |
| CTO-F | Quit-time firing for "about a week" is a plan, not a fact | **Accepted** | It's P2 work, with a gate line in G2-core. |
| CPO-O1 | A logo redraw reverses DECISIONS #37 | **Accepted** | The logo stays unchanged; the ivory character appears where Pip speaks. |
| CPO-O2 | The `run …` prefix and open-before-time bring back "make coffee" | **Accepted** | `$` only; time detection before `open`; commands in BETA. The CTO's `run` and STABLE-commands are rejected. |
| CPO-O3 | Auto-filing an unhandled one-off after 24 h is silent loss | **Accepted** | One-offs stay Overdue until handled. |
| CPO-O4 | The automatic Agents lane stores agent output | **Accepted** (the CTO agreed) | One-click Log it; project + first prompt line only. |
| CPO-O5 | The pixels are the problem, so re-implement rather than polish | **Accepted** (the CTO agreed) | Re-implement after P1. |
| CPO-r2 | Start session must not be LATER (founder's #4) | **Accepted** | BETA, Claude Code only, with a prompt field. |
| CPO-r2 | Decision 38 is missing from my overrule table | **Accepted** | Listed in §16. |
| CPO-r2 | Calendar LATER contradicts deleting its code | **Accepted** | Code kept behind a feature flag. |
| CPO-r2 | Mockup 05 shows a settings sidebar with Back; dropping it changes an approved design | **Accepted as a named change** | A ⌘, window keeps the category sidebar and drops only Back. The CTO's "same sidebar as the app" is rejected: a Mac settings window is the norm, and the CPO preferred it. |
| CPO-r1 | Five settings panes | **Rejected** | Four. Reminders & Notes settings fold into General; fewer places to look. |
| CPO-r1 | Open app/folder/URL is STABLE (against my BETA) | **Accepted** | Two seats to one, and it's safe once time detection runs first. |
| CPO-r1 | Beta of 5 → 20 over 4 weeks | **Partly accepted** | Wave 1 of 11 for 2 weeks, then wave 2 of 20 for 2 weeks, only with zero incidents. |
| CTO-r1 | Corpus of 250 | **Rejected for 300** | Both seats moved to 300, with 50 adversarial lines. |
| CTO-r1 | Journal kept 30 days | **Rejected** | 7 days, first line only (the CTO agreed in round 2). |

## 16. Where this overrules the founder's earlier decisions

The founder told the council it may change everything. Each reversal below is deliberate, and the
founder can veto any of them in writing (§17).

| Founder decision | Ruling | Reason |
|---|---|---|
| PLAN-V2 §1: v1 "for developers and people who aren't technical" | Developers first, with a widening gate (D1) | The non-technical deal-breaker is phone reach, which v1 can't deliver; a split audience caused the "maze" the founder disliked. |
| PLAN-V2 §11.2 / DECISIONS #36 MVP order (reminders → session basics → notes → Sparks → actions) | Trust and state first (P1), then reminders and the log, then Quick add, then agents | Every outside user's first minute touches stored data and the permission path; those carry the P1 defects. |
| DECISIONS #36: Sparks as colour-coded workers per project | LATER (v1.2), runtime deleted | One Pip with a session list scales to 6 sessions; 7 creatures don't. |
| DECISIONS #36: "per-session full access" | Deleted; Claude's own modes only | 26 of 31 dangerous variants passed the deny-list. |
| PLAN-V2 §1 priority #3: quick actions as a pillar | `$` commands in BETA; saved actions deleted | Plain English was becoming shell commands. |
| DECISIONS #38: ten characters, a 3D/2D choice, easier custom characters (with the founder's reference photos) | Pip only, 3D frames only, importer deleted; the other art and photos are kept in `art/` | Catalog churn (four pipelines in three days), 5.2 MB, overlay reloads, untrusted parsing. Returns only as a post-v1 pack. |
| 24 Oct request: terminal inside Sidefolk (`76b38f1`) | Deleted | 8 of 8 seats; it widens TCC, can type into live agents, and competes with the user's own terminal. |
| 24 Oct request: accent color for Pip (`7228650`) | LATER (v1.1) | It reloads the overlay and drops open cards until P1 lands. |
| Spoken voice (TTS) from the "voices" request (STATUS, DECISIONS #24 era) | Deleted; soft blips stay | It breaks the character; VoiceOver covers the access need. |
| PLAN-V2 §11.3: AI layers 2–3 in the MVP | Layer 1 only in v1; layers 2–3 in v1.1 | Layer 1 still fails everyday phrases. |
| DECISIONS #21: "No token on the hook endpoint, yet" | Replaced by the sidecar + Unix socket | Leftover hooks trust a dead port (B5). |
| PLAN-V2 morning brief and the calendar-adjacent briefs | Morning brief deleted; calendar kept as decided (v1.1) | Off-promise. |
| CLI `sidefolk here` (PLAN-V2 §1: "a terminal command in the folder") | LATER with Sparks | It only means something per project. |

**What stands from the founder's decisions:**

- reminders and notes as first-class features;
- the Dock app (#4);
- the calendar right after v1 (#6);
- layered, optional AI;
- the logo unchanged (#37);
- the approved mockups as the design target (#37);
- Pip as the photo's bunny (#38);
- how sessions open, chosen in Settings.

## 17. Decisions only the founder can make

1. **Approve this ruling, or veto items from §16 in writing.** Agents start P0 only after this.
2. **The P0 commit and tag.** Commits happen only on the founder's word (AGENTS.md), and that
   includes the staged film-duo files moving to their branch.
3. **Apple Developer Program.** Enroll on day 1 ($99/year, as an individual or an organization),
   and create the Developer ID certificate and notary credentials. This is on the critical path
   for G5.
4. **Beta testers.** Name the 8 developers and 3 people without agents for wave 1, including at
   least one keyboard or VoiceOver user if possible, and accept the day-7 and day-14 interviews.
5. **Make the repository public** under MIT, and confirm that Pip's art, name and logo stay
   reserved.
6. **Hand checks.** Only the founder can record G2 and G4 lines, the screen-recording spike
   (D10), and the five-screen design sign-off.
7. **The v1.1 calendar question:** is the work calendar on the Mac (Calendar.app or Outlook for
   Mac) or only on the web?
8. **The "Side Fork" from-zero brainstorm** (STATUS, 25 October, for example the rehearsal
   partner) does not enter v1. The founder decides whether it becomes a separate project after
   public v1.
9. **The project domain and site name** for the download page.
