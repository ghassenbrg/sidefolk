# CPO position paper, round 1 (Aiko, seat `cpo`)

I own what a person actually lives through: the first ten minutes, the daily loop, the window, the
companion. Markers: **[FIGHT]** = I will hold this in round 2; **[CONCEDE]** = my preference, but I
will trade it.

## D1 Audience and the v1 promise

**Decision: B-led hybrid with an explicit gate.** The promise is for people who work alongside AI
coding agents on a Mac. Reminders and the dated log are first-class, but they serve that person's
day; they are not a second product.

> **Sidefolk v1: Pip sits on your desktop, taps you when Claude Code needs you, takes you to that
> exact session, and keeps your reminders and a dated log of what you got done.**

Why B and not A:
- A non-technical user's dealbreaker is phone reach (Maya, both councils). Without Apple Reminders
  sync, A loses to Siri on day one, and that sync is real work we haven't scoped.
- The founder's own examples (RT results, a brag doc for evaluations, sessions per repo) describe
  a developer's day.
- The agent-pet niche is crowded. Our wedge is the full loop done reliably: right session, exact
  tab, safe answer, plus a log that compounds. Nobody else ships that loop.

**The gate.** "Skip AI tools" in setup must still give a calm, jargon-free app: Today, Reminders,
Notes, and no Sessions, commands or developer examples. We market to everyday users only when two
things are true: Apple Reminders export ships, and at least 30% of weekly beta actives use
reminders or notes with no agent connected. **[FIGHT]** for the no-jargon path. **[CONCEDE]** the
exact threshold.

## D2 Feature inventory

LATER = no UI entry point in v1. Code that touches processes, security or the agent path is
deleted and can be restored from a tag. CTO's call on the rest.

| Feature | Verdict | Reason |
|---|---|---|
| Pip companion | **STABLE** | The soul. The only thing reviewers screenshot. |
| Typed phrase input (companion field) | **STABLE, reworked** | Becomes Quick add (D5); never a dead end. |
| Tell bar (window) | **STABLE, reworked** | Same Quick add as a toolbar field plus ⌘K. Finishes in the window (F07); the keyboard path that doesn't need the overlay. |
| Reminders: one-off | **STABLE** | Founder priority #1. |
| Reminders: repeat | **STABLE** | Only with the D3 contract. |
| Reminders: snooze | **STABLE** | A menu: 10 min, 1 h, this evening, tomorrow 9:00, pick. |
| Reminders: history | **STABLE** | Inside the reminder's details, not a page. |
| Notes and notebooks | **STABLE, reshaped** | Inbox + notebooks + timeline (D4). |
| AI draft summary | **LATER** | Markdown export covers v1; it needs timeout/cancel and a quota story. |
| Quick shell commands | **BETA** | Founder priority #3. Only with an explicit `$`, always opens visibly in your terminal with an exact preview, off until enabled. |
| Saved actions | **LATER**; delete "run quietly" | A sidebar item for one row; background runs have no lifecycle. |
| Open app/folder/URL | **STABLE** | "open teams" is ordinary speech; cheap and safe with a preview. |
| Watching Claude Code | **STABLE** | Core. |
| Watching Codex | **BETA** | Status only (working / needs you / done), and only once notify or rollout status is real. Until then remove "Codex" from every claim. |
| Permission requests on companion | **STABLE** (Claude Code) | The signature moment, with the D6 routing and display rules. |
| Per-session full access | **DELETE CODE** | A deny-list can't be made honest. Use the agents' own modes instead (D6). |
| Start sessions | **BETA** | Only with a prompt field ("hand them work"), Claude Code first, asks-first. |
| Open/continue session | **STABLE** | Honest per-host matrix; never resume a live session. |
| Sparks | **LATER** | One Pip plus a session list is calmer and scales. Art stays in the repo. |
| Terminal inside Sidefolk | **DELETE CODE** | 8/8 cut; widens the TCC footprint. |
| Calendar heads-up | **LATER** (first v1.1 item) | The founder already placed it after the MVP; needs the EventKit entitlement and the Outlook answer. |
| Morning brief | **DELETE**, merged | Becomes the stable "welcome back" line (J6). |
| Weekly wins | **STABLE, simple** | Friday read-back from the log, no AI. Retention, and the founder's evaluation use case. |
| Ten characters + 3D/2D | **DELETE CODE** except Pip 3D | Catalog, not a character. 2D doubles art cost for nothing. |
| Character import/export | **DELETE CODE** | Worst screen in the app; IP and likeness risk. |
| Accent colors | **STABLE** (scarf, six presets) | Personal at no cost to identity. **[CONCEDE]** |
| Sounds | **STABLE** | Soft blips plus one distinct "needs you" chime, all off with one switch. |
| TTS voice | **DELETE CODE** | Breaks the character. Spoken output for access goes through VoiceOver live regions instead. |
| Setup guide | **STABLE, rewritten** | Three steps (J1). |
| Settings | **STABLE, rebuilt** | A real ⌘, window with five panes (D8). |
| CLI `sidefolk here` | **LATER** | Means something only with Sparks. Delete the admin-password install. |
| MCP notify/ask/remind | **STABLE** | Agents reach you through Pip. `ask` gains session identity and a visible deadline. |
| MCP spark/presence | **LATER** | Ship with Sparks. |
| Dock app + window | **STABLE** | Founder decision 4. |
| Menu bar icon | **STABLE** | Status dot, Show/Hide Pip, Quick add, Quit. |
| Hide from screen recordings | **STABLE, ON by default** for the overlay | Cards carry commands and paths. Copy states its limits honestly. |
| Copy report | **STABLE** | Shows a preview and redacts before copying. |

## D3 Reminder contract

| Case | Behaviour |
|---|---|
| Kinds | **One-off** and **repeating alert** (calendar-like). "Repeat after I finish" is LATER. |
| Series vs occurrence | The series rule (wall-clock time + pattern) is stored apart from the current occurrence. **Snooze moves only the occurrence**, never the anchor. Done completes that occurrence; the next comes from the rule. A "Skip next" action exists. |
| Ignored | The next occurrence fires on schedule whether or not the last was handled. Only one live occurrence per series: when the next fires, the old one goes to history as *missed*. No backlog. |
| Time zone | Floating local time by default: 9:00 means 9:00 wherever the Mac is. A fixed zone only when the user picks one in the editor. |
| DST | Wall-clock is kept. A time that doesn't exist (02:30 at spring-forward) fires at the next valid minute. A time that occurs twice fires once, the first time. |
| Month ends | "Every month on the 31st" fires on the last day of shorter months. |
| Quit | macOS owns the alarms. Schedule the next occurrence of every series, then later ones up to the OS's pending limit, so a quit app keeps firing for about a week. Start at login is ON from setup. |
| Sleep / late | On wake, things that came due show as **one** card: "While you were away: 2 reminders", each with its original time and a *late* tag. Missed repeats show only the latest occurrence. |
| Unacknowledged | One sound and one card. After about two minutes the card folds and Pip keeps holding the note with a count badge, and the reminder stays in Today as **Overdue** until handled. Pip never re-nags. |
| Phone | **Not in v1.** Copy says "Reminders appear on this Mac" in setup and the editor. v1.1: a per-reminder "Also in Apple Reminders" option (EventKit write); this is the widening gate in D1. **[CONCEDE]** it to v1.1 if the CEO keeps B; **[FIGHT]** for it the moment we market to everyday users. |
| Parsing | "at 3" means the next 3 o'clock between 07:00 and 22:00. "tonight" = 20:00, "this evening" = 18:00, "end of day" = 17:00, "morning" = 09:00. Compound or unsupported schedules get a clarification; never a partial accept. The resolved date and time always show before saving. |

## D4 Notes and work log contract

- **Destinations.** `note: …` goes to the **Inbox** with no question. `note for X: …` needs a
  case-insensitive exact name or alias. One near match asks "Add to *Evaluation H2 2026*?". Several
  matches show a choice list. No match offers "New notebook 'X'" or the Inbox. The text is never
  lost while you decide.
- **Visible.** The destination shows in the preview before saving and in the confirmation after
  ("Noted in Evaluation H2 2026 · Move · Undo"). Undo stays until dismissed, and ⌘Z works.
- **Inbox.** Triage is optional: "Move to…" from any entry; nothing nags you to empty it.
- **Timeline.** "All notes" is one dated stream across notebooks, grouped by week. Search matches
  dates ("October", "last week") and text.
- **Export.** Plain Markdown files on disk (kept). Each notebook offers Copy as Markdown and Show in
  Finder; there is also a "This week" export.
- **Agent work.** Suggested, never written automatically. A finished Claude Code session offers
  **Log it** on its done card and session row, prefilled "api: <first prompt line>" and editable.
  The log stays the user's own voice. **[FIGHT]**, because this one click is what makes the log
  compound for our audience.
- **Weekly wins.** On Friday at 16:00 (configurable or off) Pip holds up "Your week: 7 entries".
  Opening it shows the week's timeline with Copy. No AI in v1.

## D5 Input model

The field is labelled **Quick add**. Placeholder: "Remind me…, note…, open…". It is the same
engine in the companion and in the window.

The order for deciding what text means:
1. **Explicit forms:**
   - `$ …` runs a command (beta, developers only)
   - `note` / `note for X:` saves a note
   - `remind` saves a reminder
   - `open …` opens an app, folder or URL
   - session verbs: "open api session", "continue docs"
   - app verbs: "what's today", "show notes", "snooze", "undo"
2. **Any parseable date or time** makes a reminder draft ("call mom at 5pm", "dentist thu 2:30").
3. **Small talk** ("hi pip", "thanks", "good morning") gets about 20 canned in-voice replies with a
   pose.
4. **Everything else** becomes an Inbox note draft, with "Make it a reminder…" as the alternative.
   Pip never says "I don't know", and English never becomes a shell command.

When the draft is unambiguous, Enter saves and shows Undo. When it's ambiguous, inline choices
appear ("3 PM today · 3 AM tomorrow"). An unknown first word is never treated as a command, even
in developer mode, unless it has `$`. **[FIGHT]**

No LLM fallback in v1. Apple's on-device model is v1.1 at the earliest: it only proposes a
structured draft and always asks for confirmation.

**Coverage target.** A checked-in corpus of 300 phrases: 150 everyday, 100 developer and 50
adversarial ("make coffee", "touch grass", "less email please", embedded `rm -rf`). The bar:
- ≥95% correct intent and time across the corpus
- 100% on "no shell without `$`"
- 100% on "never silently wrong time" (an ambiguous time asks)

Every beta miss becomes a corpus line. Only the miss itself is logged locally; the phrase text is
shared only if the user chooses to.

## D6 Developer capability contract

- **Tools.** Claude Code is stable: status, requests, MCP. Codex is beta and status only. Pip never
  answers Codex approvals in v1: "Codex needs you in api · Open". The dead app-server driver goes.
- **Hosts (exact session).** A Settings → AI tools table shows the truth per host:

  | Host | What "Open" does |
  |---|---|
  | Terminal, iTerm2 | Exact tab |
  | Ghostty | Exact tab if the tty/cwd match is verified; otherwise "brings Ghostty forward" |
  | tmux | Exact window/pane |
  | VS Code / Cursor | The project window |
  | Claude desktop | Brings the app forward |

  A live session is never resumed a second time: "It's running in tmux on ttys004 · Copy".
- **Routing (fixes B2).** A request goes to Pip unless *that session's own* tab or pane is
  focused (host + tty match). If focus can't be determined, it shows on Pip. When you focus that
  tab, Pip releases the hold and the card says "Moved to your terminal".
- **Approval display.** The card shows the full raw operation:
  - whitespace preserved, scrollable
  - control and bidi characters made visible
  - Edit/Write show the diff; MCP calls show readable arguments

  If Sidefolk can't show all of it, there's no Allow button, only "Answer in terminal". Risk
  labels are warnings, never permission. Decline is never styled weaker than Allow on a flagged
  command.
- **Full access.** Sidefolk never auto-answers. Starting a session (beta) offers Claude's own
  permission modes, each explained in one line, and the session row shows the mode as a read-only
  badge. "Allow everything from this session" is deleted. **[FIGHT]**
- **Hold timeout.** The card says plainly "Claude waits about a minute, then asks in your
  terminal". When time runs out, the card becomes "Moved to your terminal · Open". Pip never
  allows or declines by timeout. MCP `ask` shows its deadline.
- **If Sidefolk is not running,** Claude Code must behave exactly as if it were never installed.
  The CTO picks the transport, but this is the user-facing rule. **[FIGHT]**
- **Identity.** A session is labelled by project plus the first prompt line plus host, never
  "Work session 04c1". Clicking Pip shows a compact list: "api · needs you / web · working /
  docs · done".

## D7 Character, brand and voice

- **Pip is the ivory clay bunny:** charcoal ear tips, mint scarf, 3D renders only.
- **The logo stays the charcoal Pip Signal, unchanged.** It's the user's confirmed constraint in
  the approved review README; the silhouette is Pip's stamp. In the window, wherever Pip is
  *speaking* (request cards, sidebar), the avatar is the ivory character, not the logo glyph.
  **[FIGHT]** against any further redesign.
- **Spark: LATER.** The art stays frozen in the repo. No other species in v1.
- **Frozen:** silhouette, palette, proportions, name and the pose set. The only allowed additions
  are **puzzled** (head tilt, one ear folded) and up to six micro-frames for Pip: look left, look
  right, ear twitch, tilt, anticipation crouch, hold up note.
  - No new art pipelines. The film-duo Blender work leaves the app repo.
  - Any visual change needs a 150 px test on light, mid and dark wallpapers, a written reason and
    a one-week cooldown.
- **Legibility.** A warm rim appears automatically on dark wallpapers.
- **Status signals are reserved for real activity.** Idle "thinking" must not use the work colour.

**Character bible (v1, to be written as `creative-design/PIP.md`):**

- **Who.** Pip is a quiet desk-mate and messenger, **not an AI**. Pip holds things for you
  (reminders, notes, agents' questions) and brings them at the right moment. Traits: attentive,
  earnest, unbothered. Pip speaks in the first person, so copy never needs a pronoun.
- **The ears are the grammar:**
  - up = attention
  - twitch = heard you
  - one folded = puzzled
  - both down = asleep or sad
- **Pose map:**

  | State | Pose |
  |---|---|
  | idle | breathing, blinks |
  | listen | while you type |
  | work | an agent is busy |
  | alert | "!" card |
  | done | only on real success, under 1.2 s |
  | sad | an agent failed; never because *you* did something |
  | puzzled | Pip didn't understand |
  | write | note saved |
  | hold-up | a reminder fires |

  Plus wave, sit, sleep and dangle.
- **Voice:**
  1. One sentence of 12 words or fewer, then the buttons.
  2. Say "I" for Pip's acts and name the agent for theirs.
  3. No raw errors. An error table translates every code (`rate_limit` → "Claude hit its usage
     limit in api.").
  4. No guilt, no urgency theatre, no emoji. Exclamation marks only on done.
  5. When Pip misses, it owns it and offers the nearest thing.
  6. Permission cards are plain; the personality lives in the pose.
  7. Recurring phrases: "Got it." / "Noted." / "Here if you need me."
- **Pip never:** nags twice, walks around the desktop, celebrates something that didn't succeed,
  shows an activity light while idle, or claims to have done an agent's thinking.

## D8 App shell and UI

- **Form.** Dock app + window + menu bar icon, as the founder decided. Not menu-bar-first.
  Closing the window keeps Pip and reminders running.
- **Window: rebuild the view layer against the approved mockups with a small component kit.**
  Keep the tokens, the data/API layer and the accessibility semantics. Today's screens are close
  in layout (I compared `light-home` with `01-today`), so this is a re-implementation toward an
  approved design, not a new design. The craft gap is real, though: outlines everywhere, 44 px
  controls, five button styles, unstyled native inputs, placeholder icons, cold dark mode. That
  CSS can't be polished out because two layers are fighting.
- **Sidebar:**
  - Today, Reminders, Notes
  - Sessions, shown once Claude Code is connected
  - Actions removed

  One navigation level; notebooks are a list/detail pair inside Notes.
- **Settings** is a separate standard window (⌘,) with five toolbar panes, each with one
  distinct icon:

  | Pane | What it holds |
  |---|---|
  | General | Login, Dock, shortcut, theme, reduced motion, text size |
  | Companion | Name, scarf, size, sounds, sleep |
  | Reminders & Notes | Notification status, default snooze, weekly wins |
  | AI tools | One "Connect Claude Code" switch installing hooks + MCP together, the host table, Codex beta |
  | Privacy & Data | Capture protection, journal retention, export, Copy report, Disconnect & Uninstall |
- **Component kit.** About 12 components:
  - one primary, one secondary and one destructive button, plus an overflow ⋯ menu
  - list row (check · title · time · chevron)
  - text field, popup button, segmented control, sheet, toast with persistent Undo
  - status dot + word, empty/loading/error state
- **The visual bar:**
  - window controls 24–28 px; 44 px only on overlay cards
  - hairline separators instead of outlines
  - 13 pt base type
  - SF-Symbol-style icons at one stroke weight
  - a warm dark palette matching the cream light theme
  - sidebar vibrancy
  - one locale-aware date format ("Today 15:00", "Thu 2:30 PM", "Oct 3")
- **Sign-off.** A side-by-side review against `review-2026-10-24/*.png` at three widths and both
  themes, signed off by the founder before beta. **[FIGHT]** rebuild over polish. **[CONCEDE]**
  how it's sequenced.

## D9 Architecture (product requirements; CTO owns the how)

- **The window must be fully usable with the overlay hidden.** Every task finishes on the
  surface that started it, so domain state lives in one authority (Rust), and window and overlay
  are views of it.
- A look or theme change never drops an open request card.
- Damaged data is never shown as "No reminders yet". The user sees "I couldn't read your
  reminders file. Your data is safe · Restore last good copy".
- Every user-visible error comes from the voice table.
- **Tests I need:**
  - the phrase corpus (D5)
  - fixed-clock reminder contract tests (D3: snooze, DST, month end, sleep)
  - each journey below as a WebKit script, plus a dated native hand-check script
  - keyboard-only scripts for J1–J4

## D10 Security, privacy, distribution (user-facing asks)

- Connect and Disconnect take one switch each, with backups.
  - **Uninstall** in Privacy & Data removes the hooks first, then offers to keep or delete data.
  - Leftover hooks must never trust a dead port (CTO).
- Signed and notarized, with an in-app updater that shows release notes in Pip's voice.
- macOS 14+. Architecture is the CTO's call (universal if cheap).
- Crash reports: opt-in, with a preview.
- **Free.** The license is the CEO's call; I lean MIT because a tool in the permission path earns
  trust by being readable.
- Channel: DMG plus a Homebrew cask. No App Store; the sandbox doesn't fit.
- **The privacy page** says in plain words what stays local, what the journal keeps and for how
  long (default 7 days, prompts redacted), and when data leaves (only a "uses Claude" action you
  click).

## D11 Release gates, beta, metrics

**My gates for beta:**
1. All seven journeys pass on a native build by the founder's dated hand check.
2. Zero raw identifiers or error codes in any string (a grep-based check on the voice table).
3. The phrase corpus meets its D5 bar.
4. One VoiceOver session and one keyboard-only session complete J1–J4.
5. Three outside people complete J1 unaided within ten minutes.

**Beta:**
- 5 developers in week 1, then 20 by week 4.
- Plus 3 people with no agents connected, to test the calm path; they test the gate, not the
  promise.

**Metrics** (local counters, shared only with consent):
- Activation in the first day: reminder created + Claude connected + one request answered or
  session opened from Pip.
- Weekly:
  - requests answered from Pip
  - "Open" landing on the right session (a user thumbs-down on a miss)
  - reminders acknowledged on time
  - log entries
  - Quick add misses
- The calm metric: how often Pip is hidden or quit, and why (one-tap reason).

**Continue / switch / stop:**
- Continue if ≥50% of beta developers use it on 3+ days in week 3.
- Switch toward A if users with no agents connected retain better than developers.
- Rethink if week-3 retention is under 30% in both groups.
- Any wrong-session approval, lost note or missed supported reminder stops the beta until fixed.

## D12 Process guardrails (my additions to the councils' list)

- The v1 list is frozen; one in, one out, with a dated decision and a 24-hour wait. WIP = 1.
  - "Done" = the journey passes in the real app, with a date.
  - Art is frozen.
  - STATUS.md stays at 150 lines or fewer.
- **No string ships unless it's in the voice table.** No screen merges without a side-by-side
  comparison with its mockup in both themes.
- An agent that wants to add a pose, character, setting or sidebar item must write the
  displacement first.
- The founder reviews each journey, not each commit.

## D13 Roadmap (CPO view)

| Phase | What | Size | Exit gate |
|---|---|---|---|
| 0 Cut | Delete per D2, freeze, write PIP.md, voice table, phrase corpus | 1 wk | Build has only v1 surfaces; corpus checked in |
| 1 Trust | D3/D4/D6 contracts, data recovery, routing, raw display, delete full access | 2 wks | Contract tests and corpus pass; no auto-answer path exists |
| 2 Experience | Window rebuild + kit, Settings window, Quick add, puzzled + micro-frames, keyboard/VO paths | 2–3 wks (parallel with 1 after week 1) | Mockup sign-off; J1–J7 pass in WebKit |
| 3 Native + ship | Sign, notarize, update, uninstall, native hand checks, host matrix | 1–2 wks | Clean install by an outsider; matrix recorded |
| 4 Private beta | 5 → 20 users | 4 wks | D11 rules |
| 5 Public v1 | — | — | All gates green |
| After | v1.1: Apple Reminders export, calendar heads-up, Codex approvals. v1.2: Sparks (if 3+ sessions is common), on-device model for drafts | | |

## Core journeys v1 must nail

**J1 First ten minutes, developer.**
1. Pip hops in and waves: "Hi, I'm Pip. I hold things for you."
2. "Tell me one thing to remember." The user types "in 2 minutes stretch". The preview shows the
   resolved time, Enter saves, and Pip writes.
3. Allow notifications: the result is shown honestly, and the login item is on.
4. "Do you use Claude Code?" One switch connects hooks and MCP with a backup. The status reads
   *Connected, waiting for the first session*.
5. Open Claude Code. The first event turns the status to *Working in api*, and Pip types.
6. At 2:00 Pip holds up "stretch" with Done / Snooze / Open.

**J2 First ten minutes, no agents.** The same steps 1–3, then "Skip, I don't use AI tools". The
user gets Today, Reminders and Notes, with everyday Quick add examples. No word from the developer
vocabulary appears anywhere.

**J3 Needs you.**
1. The user is in Ghostty tab 2 while api waits in tab 5.
2. Pip's ears go up, the "!" card appears, and the chime plays once. The card shows the project,
   the first prompt line and the full command.
3. Allow once → "Sent to Claude." Or Open → tab 5, the card says "Moved to your terminal" and the
   hold is released.
4. Keyboard path: the shortcut focuses the newest card, and Tab moves Decline → Allow.

**J4 Reminder lifecycle.**
1. "dentist thu 2:30" → preview "Thu, Oct 29, 2:30 PM · dentist" → Enter → "Got it. Thursday
   2:30." with Undo.
2. It fires; Snooze → 1 h.
3. A weekly reminder snoozed to Tuesday stays on Mondays.
4. The Mac sleeps through 9:00; on wake: "While you were away: 1 reminder (9:00)".

**J5 Log and read back.**
1. "note for evaluation: led the RT migration" → Pip asks "Evaluation H2 2026?" → yes → "Noted
   in Evaluation H2 2026 · Move".
2. A Claude session finishes; on the done card, Log it → edit → saved.
3. Friday: "Your week: 6 entries" → timeline → Copy as Markdown.
4. Six months later, searching "evaluation October" finds the entries.

**J6 Come back.** After being away for an hour, Pip wakes with a wave and one line: "While you
were away: api finished, web needs you, 1 reminder." Each item is clickable.

**J7 Uninstall.** Privacy & Data → Disconnect & Uninstall. Hooks are removed and verified, the
data is kept or deleted as chosen, and Claude Code behaves as before.
