# Sidefolk v1 audit: Claude council report (frozen)

25 October 2026 · Source revision `76b38f1` (plus uncommitted docs) · Chair: Claude Code (Opus 5.5)

Frozen before reading the Codex council's findings in `docs/audit-2026-10-25/`. The comparison
with that audit is in [ADDENDUM-COMPARISON.md](ADDENDUM-COMPARISON.md). The eight full seat
memos are in [seats/](seats/). Nothing here is a decision: the supreme council
([SUPREME-COUNCIL.md](SUPREME-COUNCIL.md)) and the founder decide.

## How the audit was done

- The chair walked the app as a first-time user in the browser preview (sample data) and captured
  70 WebKit screenshots of every view, both themes and the companion's key moments. The chair
  also ran the phrase parser on 28 everyday sentences.
- Eight simulated seats reviewed independently, each with its own rules. Maya, Leo, Jun and Sam
  started as black boxes: screenshots, the live preview driven by their own Playwright WebKit
  scripts, and the user guide. Leo, Jun and Sam then read the code that mattered to their seat.
  Priya, Elena, Omar and Ines had read-only access to the code and docs. None of them opened the
  Codex audit.
- The chair re-checked the most serious claims in the source (marked ✔ below).
- **Limits.** No native app, real VoiceOver, real Claude Code/Codex session or signed build was
  exercised, and no real user was involved. These are expert simulations, not customer evidence.
  The native behaviour still needs the hand checks listed in the release gates.

## Verdict in one paragraph

The pieces under the surface are good: the Rust core, the hook server, the session-host
detection, the backup-first installers, the reminder store and time parsing, the window's
accessibility basics, and a charming companion. The product on top is not ready and not
focused. It promises a chatbot and delivers a phrase list. It promises to watch Claude Code
and Codex, but Codex in a terminal is never watched, and requests skip Pip whenever a terminal
is in front. Its "full access" is a regex deny-list that misses most dangerous commands and
every file write. It has no signing, updater or uninstall. The process behind it re-adds
scope (ten characters, an in-app terminal, Blender film rigs) hours after a plan cut it. **No
seat voted to restart everything.** The council splits 4–4 between "evolve" and "rebuild the
UI on this core".

## Scores (1–10)

| Seat | Clarity | Ease | Visual | Useful | Trust | Release | Vote |
|---|---|---|---|---|---|---|---|
| Maya, non-technical ops manager | 4 | 5 | 8 | 3 | 4 | 3 | Restart UI on core |
| Leo, multi-session AI developer | 4 | 6 | 8 | 4 | 5 | 2 | Restart UI on core |
| Priya, head of product | 3 | 5 | 7 | 4 | 5 | 2 | Evolve |
| Jun, Mac UI designer | 5 | 5 | 4 | 4 | 5 | 3 | Restart UI on core |
| Sam, UX & accessibility | 4 | 4 | 7 | 4 | 6 | 3 | Evolve |
| Elena, principal engineer | 4 | 5 | 7 | 6 | 3 | 2 | Restart UI on core |
| Omar, security & release | 6 | 6 | 7 | 5 | 3 | 2 | Evolve |
| Ines, creative director | 4 | 5 | 7 | 5 | 6 | 3 | Evolve |
| **Average** | **4.3** | **5.1** | **6.9** | **4.4** | **4.6** | **2.5** | 4–4, none for a full restart |

Visual quality is the one area above average, and the credit goes to the companion. Jun scores
the window itself 4/10.

## Blockers (every one must be fixed before anyone outside relies on it)

| # | Blocker | Found by | Evidence |
|---|---|---|---|
| B1 | **"Full access" is unsafe.** Non-command requests (Write, Edit, WebFetch, MCP) are always auto-allowed. Commands are checked against 9 regexes: 26 of 31 dangerous variants passed (`rm --recursive --force`, `find . -delete`, `git push origin +main`, `bash -c $(base64…)`, `python -c rmtree`…). The check runs on the clipped text, so anything after the cut is never checked. "Allow everything from this session" is offered on every card, including one for `rm -rf`, and persists across restarts. | Omar, Elena, Leo | ✔ `src/access.ts:9-25`, `stillAsk` returns null when kind ≠ command; `hooks.rs:149` clips at `ACTION_MAX` |
| B2 | **Requests skip Pip whenever any terminal, editor or the Claude app is in front**, which for a developer is almost always. The waiting session can be in a hidden tab. | Leo | ✔ `hooks.rs:222-266` `should_hold` / `defer_to_app` |
| B3 | **Codex sessions in a terminal are not watched at all.** The app-server driver `codex.rs` is reachable only from a debug endpoint. The preview's sample data shows Codex sessions, which oversells it. | Leo, Elena | ✔ no TS caller of `dispatch`; STATUS "Codex CLI sessions … no hook" |
| B4 | **No signing, notarization, entitlements, updater, crash symbols or CI.** EventKit needs an entitlement under the hardened runtime. A tool in the permission path needs fast fixes and a kill switch. | Omar, Elena, Priya | `docs/RELEASE.md`: never run; no entitlements file |
| B5 | **No uninstall, and the leftover hooks trust a dead port.** After removal, Claude Code still posts every prompt and tool input to 127.0.0.1:47821, and any process that binds the port can answer "allow". | Omar | `claude_setup.rs`, nine HTTP hooks |
| B6 | **The phrase field looks like a chatbot and isn't one.** "call mom at 5pm", "dentist thursday 2:30", "show my notes", "snooze", "hi pip" are not understood. "make coffee", "touch grass" and "less email please" become "Run this in your terminal?". There are wrong times too: "tonight" → 9 AM, "tomorrow standup 9:30" → 9:00, "meeting at 3, 10 min before" → tomorrow. | Chair, Maya, Sam, Elena | Chair probe; Maya's 51 phrases; Elena traced 4 root causes in `commands.ts` / `when.ts` |
| B7 | **The Add reminder dialog shows a date but its value is empty.** It's WebKit's grey placeholder, so Save fails with "Choose a date and a time". | Sam | `sam-shots/t2-dialog-saved.png` |
| B8 | **The companion has no keyboard or VoiceOver path.** The summon shortcut moves Pip but doesn't open the field, and permission cards are never focusable. | Sam | `main.ts:306-311`, `bubble.ts:14` |
| B9 | **One corrupt settings file and the app won't launch.** There are 113 non-test `unwrap()`s (96 on mutexes) with `panic = "abort"`. A port that fails to bind is only logged. There is no single-instance guard. | Elena | `settings.rs:94` → `main.rs:337 expect` |

## Major problems (by theme)

**Product and scope**
- There's no single promise. The window opens on reminders and notes, the guide leads with a
  pet, and the pitch says "gives AI agents a body". The audience is split between a
  non-technical desk buddy (Maya) and a multi-session developer (Leo), and the UI serves neither
  fully.
- The agent-status pet is now table stakes. Notch and menu-bar monitors (Vibe Island, Notchcode,
  Claude Island…), several desktop pets, and the Codex app's own pets all show running, waiting
  and done (Priya; sources in her memo). A wedge has to be reliability plus something nobody else
  does.
- Process debt:
  - Phases 3–9 were committed in about four hours on one day, all marked "hand checks pending".
  - The plan's "not now" list (more characters) was undone the same day.
  - A fourth art pipeline is staged in git.
  - STATUS.md is about 600 lines of interleaved entries.

**Developer features**
- "Open session" reaches the exact tab only in Terminal and iTerm. Ghostty, VS Code and Claude
  desktop get "select it yourself". A live tmux/ssh session can be resumed a second time while
  it's still running (Leo, `sessions.rs:181-206, 288-300`).
- Pip holds Claude Code for up to 60 s with no prompt in the terminal. Nothing releases the hold
  when the user switches to that tab (Leo).
- Sessions are labelled "Work session 04c1", even though the first prompt is captured. With
  several projects the badge can't say which one is talking (Leo).
- Cards don't always show what gets approved. Edit and Write show only the path, never the diff.
  MCP arguments are raw JSON. Whitespace is collapsed and bidi/control characters aren't
  neutralized (Omar).
- "Start session" has no prompt field, so "hand them work" isn't delivered (Leo).

**UI and UX**
- The window reads as a re-skinned web admin panel:
  - every surface carries a heavy outline
  - all controls are 44 px
  - there are five button styles, and native selects and file inputs are left unstyled
  - icons are placeholders, and the same icon repeats across categories
  - dark mode is cold slate against a warm cream light theme
  - Sessions and Review don't match the approved mockups (Jun)
- Information architecture:
  - Settings replaces the sidebar with its own nine-item sidebar plus "Back to Sidefolk".
  - Actions sits next to Settings, and "AI tools" stays hidden until something is connected.
  - Connecting shows three separate items: hooks, MCP for Claude, MCP for Codex.
  - Characters and Terminal highlight the wrong sidebar item (Jun, Sam).
- Timed content and recovery:
  - Replies vanish after 6 s, and Undo after 9 s.
  - Focus drops to the body after a delete.
  - Saved actions are deleted with no undo.
  - Permission review puts "Allow once" below the fold (Sam).
- Wording and jargon. Maya counted about 11 unfamiliar terms on Today, about 12 on Sessions and
  about 15 in AI tools. Raw codes leak into the bubble: `rate_limit`, `(sky)`, `String(e)`
  (Maya, Ines, Jun).
- Notes are hard to find again: no inbox, no timeline, and search doesn't match dates (Sam).
- Reminders stay on this Mac, so they never reach the phone, which is a deal-breaker against
  Apple Reminders for a non-developer (Maya).

**Character and brand**
- Pip's identity changed four times in three days: Blender procedural, then the 2D charcoal body
  B, then generated clay pose sheets, then Blender film rigs (staged). The logo is a charcoal
  bunny and the shipped Pip is ivory (Ines, Jun).
- It's a catalog, not a character:
  - Ten characters are shown on equal terms, robot first.
  - Nothing describes who Pip is.
  - The 2D style is a trace of the 3D one.
  - Five characters vanish on dark wallpapers (Ines).
- The voice reads as log lines. There's no puzzled pose, so Pip sits relaxed while saying it
  didn't understand. Poses hard-cut between each other. The macOS TTS voice breaks the character
  (Ines).

**Engineering**
- The overlay webview owns the domain state: requests, full access in localStorage, sessions and
  Sparks. The window gets an untyped JSON snapshot polled every second. Changing the look reloads
  the overlay and drops open permission cards. No data file has a schema version (Elena).
- About 50 of 74 Tauri commands run synchronously on the main thread. Every 3 s the window
  re-reads `~/.claude.json` and `~/.codex/config.toml`. "Draft a summary" has no timeout (Elena).
- Leftovers from earlier pivots:
  - the dead Codex driver (399 lines)
  - "3D familiar" / "crew of pets" in the Cargo and Tauri metadata
  - mixed vocabulary: pet 235, companion 231, crew 93, Spark 97 uses
- Tests cover pure functions only. There is nothing for the hook HTTP flow, the timeouts or the
  overlay↔window protocol (Elena).
- Privacy:
  - The journal keeps prompts and full commands, which can contain secrets, for 30 days in plain
    text.
  - "Hide from screen recordings" is off, so cards show up in screen shares.
  - The in-app PTY terminal widens Sidefolk's TCC footprint and lets the page type into a live
    agent (Omar).

## What everyone agrees on

1. **Keep the companion and the Rust core.** No seat wants a full restart.
2. **Cut:**
   - the terminal inside Sidefolk (8/8)
   - the ten-character catalog with its 3D/2D styles, reduced to Pip (plus at most Spark) in one
     style (8/8)
   - the make-your-own importer (5 cut, 3 later)
3. **Rework per-session full access.** Use the agents' own permission modes or an allow-list,
   never a deny-list (8/8).
4. **Watching sessions plus answering permission requests is the most valuable thing.**
   Every seat keeps it, including Maya, who wants it hidden from her.
5. **Settings go from nine categories to three to five.** The parser has to stop failing
   silently and stop turning English into shell commands.
6. **Release basics are blockers:** signing, notarization, entitlements, updater and uninstall.
7. **Stop scope churn with written guardrails.**

## Where the council disagrees (preserved dissent)

| Question | Position A | Position B | Notes |
|---|---|---|---|
| **Who is v1 for?** | Developers running several Claude Code / Codex sessions: Leo, Priya, Elena, Omar, Jun, Sam (6) | Everyday Mac users with a developer mode: Maya; Ines is neutral on audience | Priya's gate: widen only if ≥30% of weekly users use reminders or notes without an agent |
| **Reminders and notes in v1?** | Keep as satellites (Priya: notes become a *work log* feeding weekly wins; Sam, Omar, Elena, Jun) | Cut, since Raycast, Obsidian and Apple already do it (Leo) | Maya keeps them only if reminders sync to iPhone (Apple Reminders) |
| **Weekly wins** | Priya: the *retention* feature, which no competitor has | Leo and Elena: cut as fluff; others: later | The supreme council must choose |
| **Quick commands / open-anything / saved actions** | Cut (Leo, Priya) | Keep behind an explicit `run`/`$` prefix or a developer mode (Omar, Sam, Ines, Jun) | Everyone agrees English must never become a shell command |
| **Tell bar** | Cut, it duplicates the pet (Leo, Priya) | Keep as quick-add / ⌘K (Sam, Jun, Omar, Ines) | — |
| **App form** | Menu-bar-first + popover + small window (Jun, Leo) | Dock app + window (Sam, Omar, Ines, Maya, Priya) | — |
| **Window UI** | Rebuild against the approved mockups with a small component kit (Jun, Elena, Leo, Maya) | Polish what exists (Sam, Omar, Ines, Priya) | Elena adds: move state into Rust and drive the window by events |
| **Sparks** | Later (5) | Cut (Sam) / one recoloured robot, max 3 (Ines) | Leo: one pet with a session list scales better than 7 creatures |
| **Parser fallback** | Deterministic grammar + on-device model for unknown text, always with a confirm (Elena) | Forgiving "quick add": a time makes a reminder draft, anything else an inbox note, never "I don't know" (Sam) | Compatible: do Sam's first, Elena's later |
| **Spoken voice** | Cut (Ines, Leo, Elena) | Keep, it helps accessibility (Sam) | — |

## The council's proposed v1 (majority view, for the supreme council to decide)

**Promise:** *For developers who run Claude Code and Codex on a Mac: Pip tells you which session
needs you, lets you answer it safely from anywhere, takes you to that exact session, and
remembers what you and your agents got done.*

Must-haves (majority):
1. Requests reach you unless *that session's* tab is in focus, and the hold is released when
   you go there. Cards show the exact command or diff, and nothing truncated can be allowed.
2. Exact-session "Open" in Terminal, iTerm, Ghostty, VS Code, Claude desktop and tmux, saying
   honestly where only "bring forward" is possible. A live session is never resumed twice.
3. Real Codex status (notify or rollout files), or "Codex" removed from every claim.
4. One honest authority model: the agents' own modes or an allow-list that ends with the
   session.
5. Reminders that fire, start at login by default, a forgiving quick-add with no dead ends, and
   no English that turns into shell commands.
6. A work log: agents' finished work plus "note: …", with Friday weekly wins and Markdown
   export. This is Priya's retention wedge; it's contested, so the supreme council decides.
7. Signed, notarized, auto-updating, with uninstall, entitlements and a privacy page.
8. One Pip with a written character bible, a puzzled pose, dark-wallpaper legibility and a
   voice without raw errors.
9. Keyboard and VoiceOver paths to everything the companion does.

Cut or defer: the in-app terminal, the character catalog, the importer, the 2D style, TTS
voice, "Allow everything" on the card, background saved actions, Sparks (later), calendar,
morning brief and AI summary (later), and the admin-password CLI install.

Effort (Elena): about 4–6 engineer-weeks before a beta, then 2 weeks with 3–5 outside users.

## Guardrails proposed (Priya, Ines, Elena)

- The v1 list is frozen. Any addition needs a dated decision naming what it displaces (one in,
  one out) and a 24-hour wait.
- One feature in progress at a time. "Done" means a dated check in the real app, not in the
  preview.
- Art is frozen until v1 ships, except polish for Pip. No new art pipelines.
- Outside users before new features: 5 in the first week, 20 by week 4.
- STATUS.md is rewritten at each handoff and kept to 150 lines or fewer, with history moved to
  a log.
- Deleting a feature deletes its code, not just hides it.
