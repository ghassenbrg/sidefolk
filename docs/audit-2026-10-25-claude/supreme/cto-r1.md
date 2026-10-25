# CTO position paper, round 1 (Marcus, seat `cto`)

Source revision `76b38f1`. I re-read the source behind every fact I lean on: `hooks.rs:222-266`
(hold/defer), `reminders.rs:97-103` (corrupt file loads as empty), `src/reminders.ts:234`
(recurrence lives in the webview), `notifications.rs` (macOS owns only the *next* alarm),
`hooks/claude-settings.json` (nine HTTP hooks to a fixed port), `tauri.conf.json` (min macOS 13,
"crew of 3D desktop pets", no updater, no entitlements file), `settings.rs:24` (hide-in-recordings
off because of the Mission Control patch).

**My frame.** The team is AI agents plus one founder who is the only person who can see the
screen. So the bottleneck is not writing code, it is *verifying* it. Every decision below is
picked for what we can prove on a real Mac in weeks. Two rules I will not trade: **no false safety
claim ships, and no user data is ever silently lost.**

Legend: **[FIGHT]** I'd hold this against CEO/CPO. **[CONCEDE]** I'll take the other seat's call.

---

## D1. Audience and promise

**Audience: developers on a Mac who run Claude Code (Codex as beta), and who also want their own
reminders and a work log in the same place.** One persona: the founder and people like him. Not
"everyone", and not a non-technical desk buddy in v1.

**Promise:** *"Pip lives on your desktop, reminds you of what you told it, keeps a dated log of what
you got done, and tells you when a Claude Code session needs you, so you can answer it safely or go
straight to it."*

**The explicit gate (this is the engineering point).** The founder's #1 priority (reminders) is our
*lowest-risk* code, and the differentiator (agent attention) is our *highest-risk* code. So the
release train is built so the risky half can't hold the safe half hostage:

- **Core track (must pass for v1):** reminders, work log, quick-add, one Pip, release basics.
- **Agent track (must pass to be called stable):** Claude Code status, requests, open-session.
  If it fails its native matrix one week after its phase, v1 ships with Sessions as a labelled beta
  and **no approvals from Pip**. The promise sentence then drops its last clause.
- **Widening to non-developers** only if ≥30% of weekly beta users use reminders/log without an
  agent (Priya's gate) and only after Apple Reminders reach (D3).

[FIGHT] on the gate structure. [CONCEDE] the exact wording of the sentence to CEO/CPO.

## D2. Feature inventory

LATER = removed from `main`, recoverable from the tag; it comes back only by a dated decision.
DELETE CODE = removed, not expected back. BETA = in `main`, behind a flag, off by default.

| Feature | Verdict | Reason |
|---|---|---|
| Pip companion | STABLE | The product's face; ~1.3% CPU with sprites. |
| Typed phrase input (companion field) | STABLE (reworked) | Becomes forgiving quick-add (D5). |
| Tell bar | STABLE, merged | Same field, same service, finishes on the window (fixes F07). One code path. |
| Reminders one-off | STABLE | Store + native alarm are sound; fix corrupt-load and parsing. |
| Repeat | STABLE | Only with the series contract in D3. |
| Snooze | STABLE | Occurrence-only (D3). |
| History | STABLE | Simple list of past occurrences. |
| Notes & notebooks | STABLE | Plain Markdown, portable; fix ambiguous routing. |
| AI draft summary | LATER | Spawns a CLI with no timeout, spends quota, sends a notebook off-Mac. |
| Quick shell commands | STABLE, `$`/`run` prefix only | Opens *your* terminal with the exact command after a confirm. No guessing from English. |
| Saved actions | LATER | Background runs have no lifecycle (no cancel, no process-group kill). |
| Open app/folder/URL | STABLE | Small, no shell, https only. |
| Watching Claude Code | STABLE-gated | The differentiator; hooks code is sound. |
| Watching Codex | BETA | Ordinary Codex CLI isn't watched today. Status-only after a 1-day spike; claims limited to what's verified. |
| Permission requests on companion | STABLE-gated | Only with D6 (raw bytes, release rule, no truncated Allow). |
| Per-session full access | DELETE CODE | A deny-list can't be a safety boundary (26/31 bypasses). `src/access.ts` goes. |
| Start sessions | STABLE (Claude), BETA (Codex) | Add a prompt field; launch mode is the agent's own, labelled as such. |
| Open/continue session | STABLE | Exact tab in Terminal/iTerm; honest "bring forward" elsewhere; fix double resume. |
| Sparks | LATER (v1.1) | Second creature = more state; cheap only after state moves to Rust. |
| Terminal inside Sidefolk | DELETE CODE | TCC attribution, keystroke injection into live agents, PTY cleanup unproven. 8/8 seats. |
| Calendar heads-up | LATER | Needs calendars entitlement + a permission prompt; not on the core path. |
| Morning brief | LATER | Depends on journal; nice, not core. |
| Weekly wins | STABLE as a deterministic "This week" view; AI version LATER | Cheap (~2 days) list built from the log + finished sessions, no model. |
| Ten characters + 3D/2D | DELETE CODE (bundle keeps Pip, one style) | 5.2 MB of 8.6 MB is crew art; style switch reloads the overlay. Art stays in `art/`. |
| Character import/export | DELETE CODE | 698 lines of untrusted image parsing, no v1 value. |
| Accent colors | LATER | Cosmetic; comes back with Sparks. |
| Sounds | STABLE | 2–3 sounds, one quiet switch. |
| TTS voice | DELETE CODE | Breaks character; the accessibility need is met by VoiceOver announcements instead. |
| Setup guide | STABLE | Must prove a real round trip, not "config line exists". |
| Settings | STABLE, 4 sections | D8. |
| CLI `sidefolk here` | LATER | Tied to per-project Sparks; current install needs an admin password. |
| MCP notify / ask / remind / presence | STABLE-gated | Token-protected, best-built part. Add session identity and deadline to `ask`. |
| MCP spark | LATER | Goes with Sparks. |
| Dock app + window | STABLE | Founder decision 4. |
| Menu bar icon | STABLE | Recovery path when Pip is hidden; hosts Uninstall. |
| Hide from screen recordings | STABLE, default ON | The overlay now covers only the companions (`c2b6544`), so the Mission Control patch is small; founder hand-checks it. |
| Copy report | STABLE | With a preview and redaction before copy. |

Also DELETE CODE: `codex.rs` app-server driver (399 lines, no caller), and do **not** commit the
staged `art/blender/film-duo/` pipeline (unstage it). [FIGHT] on the terminal, full access, the
importer, the catalog. [CONCEDE] Weekly wins placement, sounds, accent colors to CPO.

## D3. Reminder contract

1. **A repeating reminder is a series of alerts, not a task that waits for Done.** The series stores
   `rule + anchor` (wall-clock time + IANA zone). Occurrences are computed. Each fires on its own;
   ignoring Monday never stops Tuesday. (Fixes F05.)
2. **Snooze moves one occurrence only** (an override record). The anchor never moves. "Skip next"
   exists. Editing the series asks "this one / all future".
3. **Missed (app quit, Mac asleep):** macOS fires the alarm when it can (we pre-schedule the next
   N occurrences with `UNUserNotificationCenter`, not just the next one). On launch/wake, Pip shows
   **only the latest missed occurrence per series**, labelled "missed at 9:00"; older ones collapse
   into history as missed. No backlog flood.
4. **Late:** an occurrence that fires late says its original time.
5. **Done** completes that occurrence. One-off reminders: Done ends them.
6. **Time zones / DST:** reminders follow local wall time where you are (floating) unless a zone
   was typed. Nonexistent times (spring forward) move to the next valid minute; repeated times
   (fall back) fire once, first instance. "Every month on the 31st" → last day in short months.
7. **Recurrence moves to Rust** (`reminders.rs`), out of `src/reminders.ts`, so the native
   scheduler, overlay and window share one engine.
8. **Login start ON by default**; setup asks for notifications and says plainly what happens if
   they're denied.
9. **Phone reach: none in v1, said honestly** ("on this Mac"). v1.1: one-way "also add to Apple
   Reminders" via EventKit (write-only, its own list, Sidefolk's own alert suppressed for those).
   **Two-way sync never in v1.x**: conflict resolution is a months-long problem. [FIGHT] on no
   two-way sync; [CONCEDE] whether one-way export is v1 or v1.1 if CPO shows it's the deal-breaker.

## D4. Notes / work log contract

- **Destinations:** named notebooks (Markdown files) plus one **Inbox**. "note: …" with no
  notebook goes to the Inbox, never to a guess.
- **Ambiguity:** exact name match (case-insensitive) or ask, with the draft kept. Never "most
  recently updated" (fixes F06). The destination is shown *before* save and "Move to…" exists after.
- **Timeline:** one dated view across notebooks; search matches dates ("last March", "2026-04").
- **Export:** per notebook and "everything" as Markdown in a folder; files are already the source
  of truth, so export is a copy.
- **Agent work feeds the log: yes, opt-in per project, as a separate "Agents" lane** (session
  title + finished-at + the agent's last summary line), never mixed into the user's own entries,
  never prompts or commands. This is what makes "This week" useful for a developer. Redacted
  before writing (D10).

## D5. Input model

- **Grammar, deterministic, on the Mac.** In order: `$ …`/`run …` → terminal confirm; `open …` →
  open; `note[ to X]: …` / `log …` → log; text with a resolvable time → reminder draft; anything else
  → **Inbox note draft** with buttons "Make it a reminder / Put in a notebook / Discard". No "I don't
  understand" dead end, and **English never becomes a shell command**.
- **Every reminder shows its resolved date and time before saving**; Enter confirms. That turns a
  wrong parse into a visible correction instead of a missed meeting.
- **Fixes:** bare hour picks today if still ahead (F04), use all chrono results ("standup 9:30"),
  "tonight" = 20:00, compound schedules ("Monday and Thursday") either fully supported or rejected
  with a clear message, never partially accepted. Drop `make` from the everyday-command list.
- **No model fallback in v1.** v1.1: Apple's on-device model only for the Inbox bucket, guided into
  the same typed `Command`, always confirmed. Cloud model only on explicit "uses Claude" labels.
- **Coverage target:** a checked-in corpus of **250 phrases** (CPO + Maya-style, fixed clock, two
  zones, DST dates). Gates: ≥95% correct intent and time; **100%** of non-`$` English never offered
  as a command; 0 reminders saved without a visible resolved date. It runs in `npm test`.

[FIGHT] on no-shell-from-English and no model in v1.

## D6. Developer capability contract

| Item | v1 decision |
|---|---|
| Tools | **Claude Code: stable-gated.** **Codex: beta**, status via Codex's own notify/hook mechanism after a 1-day spike, plus MCP `notify/ask/remind`. No Codex approvals from Pip in v1. Nothing in the UI or sample data claims more than the matrix. |
| Exact-session open | Terminal and iTerm: exact tab (tty match, exists). Ghostty 1.3+: exact if its AppleScript can address a terminal (spike), else bring forward. VS Code, Cursor, Warp, Claude desktop, others: bring the app forward and say "select the session there". tmux/ssh: copy the attach command, never resume a live session twice. |
| Routing (fixes B2) | Pip **holds** a request unless *that session's own tab* is in front: exact for Terminal/iTerm (frontmost + selected tty), for other hosts "its app is in front and it hosts only one live Claude session". While Pip holds, if the user brings that session forward, Pip **releases within 1 s** to the terminal's own prompt and the card turns into "Answer in Claude". WezTerm gets added. |
| Display | Rust keeps the **raw, immutable** tool input; display is derived from it, never the reverse. Commands shown byte-exact (no whitespace collapsing, no ligatures, control and bidi characters shown as visible escapes). Edit: real diff from `old_string/new_string`; Write: full content. MCP: full pretty JSON. Anything that doesn't fit on the card opens a full view, and **Allow is only offered once the whole operation has been shown**. |
| Buttons | Allow once · Deny · Answer in Claude. No "allow everything", no "always". |
| Full access | **Withheld.** Delete the deny-list. "Full access" exists only as the agent's own launch mode (Claude `--permission-mode`, Codex sandbox flags) chosen at start, named as the agent's setting, shown read-only on the session row from the hook payload. Sidefolk never auto-answers. [FIGHT] |
| Hold timeout | 60 s, then release to the agent's own prompt with "Asked in its terminal". An expired or released request can never later become an Allow (request lifecycle in Rust). |
| Session names | From the first prompt + project folder, not "Work session 04c1". |

## D7. Character, brand and voice

- **Pip: the shipped ivory clay Pip, one style.** It's what users have seen and what has the most
  poses. The charcoal logo gets redrawn to match ivory Pip later; no new art pipeline for it.
  [CONCEDE] which Pip to CPO/CEO, as long as it's one existing asset set with no new pipeline.
- **Additions, polish only:** a puzzled pose, cross-fades between poses, a soft outline/shadow for
  dark wallpapers, idle "thinking" must not use the blue agent-work signal (Ines-C).
- **Sparks:** v1.1, as recoloured Pips with an accessory, on Rust state. Other characters: no.
- **Voice rules:** short, warm, first person; never raw codes. A copy table in `src/states.ts` maps
  every error to words; a test fails if bubble text contains snake_case, "Error:", or `String(e)`.
- **Frozen until v1:** roster, styles, logo, art pipelines.

## D8. App shell and UI

- **Dock app + window + menu bar icon** (decided). Closing the window keeps Pip and reminders.
- **Polish toward the approved mockups, not a rewrite from zero**, but the window is **re-plumbed**
  onto Rust events (that's the real work; the pixels mostly stay).
- **Sidebar:** Today · Reminders · Notes · Sessions (appears once Claude is connected) · Settings
  (in the same sidebar, no second sidebar, no "Back to Sidefolk").
- **Settings, 4 sections:** General (login start, Dock, sounds, hide in recordings) · Companion
  (size, position, summon key) · Agents (Claude/Codex with real health states) · Privacy & data
  (history on/off, Clear, Export, Copy report, Disconnect & uninstall).
- **Component kit, ~8 pieces:** Button (primary/secondary/destructive), Row, Card, Field, Select,
  Toggle, Dialog, Toast with durable Undo. Styled date/time fields (fixes B7). Max 2 actions per row.
- **Visual bar:** both themes from `tokens.css` only (dark mode warmed), the WebKit check passing in
  both, and founder sign-off on 5 named screens against the mockups.
- **Accessibility:** summon key opens the field; cards focusable; VoiceOver announcements for Pip's
  bubbles; focus never drops to `BODY`.

## D9. Architecture

**Keep the stack. Move the truth into Rust. Delete ~2,500 lines.** No framework change fixes a date
bug or a permission contract.

| Subsystem / file | Verdict | Change |
|---|---|---|
| `settings.rs` | Keep, fix | Corrupt file → quarantine + defaults + banner; no `expect` at launch. |
| new `store.rs` | Add | One versioned envelope `{version, data}` for every JSON store; load = Missing / Ok / Corrupt; Corrupt is moved to `*.corrupt-<ts>` and **never overwritten**; last-good `.bak` on each good load; per-version migrations with fixture tests. |
| `reminders.rs` | Refactor | Series model (D3), recurrence from `src/reminders.ts`, uses `store.rs`. |
| `notifications.rs` | Keep, extend | Pre-schedule next N occurrences; click opens the reminder. |
| `notes.rs` | Keep, trim | Remove draft summary (no timeout); add Inbox, timeline index, export. |
| `hooks.rs` | Refactor | Request lifecycle moves to new `requests.rs`; hold/release rule (D6); clip only for display. |
| new `requests.rs` | Add | Authoritative pending/answered/released/expired, raw operation + derived display, per-session cap. |
| `bus.rs` | Refactor | Typed events pushed to both webviews; `clip` no longer touches decision data. |
| `sessions.rs` | Keep, fix | No double resume; names from first prompt; Ghostty/WezTerm. |
| `claude_setup.rs`, `mcp_setup.rs` | Keep, extend | Command hooks via sidecar (D10), uninstall, health states, mtime cache (stop re-reading `~/.claude.json` every 3 s). |
| `mcp.rs` | Keep | Drop `spark`; add identity + deadline to `ask`. |
| `journal.rs` | Refactor | Redaction, history off switch, Clear, periodic pruning. |
| `prefs.rs` | Refactor | Untyped JSON status snapshot → typed state; Copy report preview/redaction. |
| `actions.rs` | Trim | Keep `run_in_terminal`, open; remove background runs; CLI to `~/.local/bin` later. |
| `panel.rs`, `overlay.rs`, `tray.rs`, `app_menu.rs` | Keep | Tray adds Uninstall. |
| `crew.rs` | Replace | Becomes typed `companion` settings in `store.rs`. |
| `main.rs` | Fix | single-instance plugin, health on bind failure, async IO commands. |
| `codex.rs`, `inside.rs`, `characters.rs`, `voice.rs`, `calendar.rs` | Delete | Plus `portable-pty`, and `objc2-event-kit` until calendar returns. |
| `src/access.ts`, `terminal.ts`, `character-import.ts`, `dashboard/characters.ts`, `recolor.ts`, `calendar.ts`, `familiar.ts` | Delete | Dead or cut. |
| `src/companion.ts`, `agents.ts`, `workers.ts` | Refactor | Render Rust state; hold no domain state (workers LATER). |
| `src/commands.ts`, `when.ts` | Refactor | Grammar + corpus (D5). |
| `src/notes.ts` | Fix | Exact match or ask. |
| `src/dashboard/*` | Polish + re-plumb | `api.ts` typed (generated types, e.g. `ts-rs`), events not 1 s/3 s polling; `tell.ts` uses the shared service. |

**State ownership:** Rust owns reminders, notes index, requests, sessions, settings and connection
health. Webviews only subscribe and invoke. An overlay reload loses nothing.
**Error handling:** IO errors become states the UI shows; no `unwrap` on IO; mutex `unwrap` OK
under `panic=abort`; `eprintln` → log file; dSYMs archived per release.
**Tests to add:** (1) in-process hook flow: event → request → allow/deny/timeout/release/expire, and
"a long prefix can't change the outcome"; (2) corrupt/unreadable/disk-full per store; (3) recurrence
with fixed clocks across DST in two zones, month-end, snooze; (4) the 250-phrase corpus;
(5) install → uninstall round trip on temp `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, byte-identical
restore; (6) overlay reload with an open request (WebKit); (7) release script fails closed.

## D10. Security, privacy and distribution

| Item | Decision |
|---|---|
| Hook transport | **Replace the nine HTTP hooks with `command` hooks** calling a tiny signed sidecar `sidefolk-hook` (Tauri `externalBin`, starts in milliseconds, unlike the WebKit-linked main binary) that forwards stdin over a **Unix socket in the 0700 data folder**, with a same-uid peer check. App not running → events exit 0, PermissionRequest returns no decision → Claude asks in its terminal. **Fails closed; can't be squatted** (fixes B5). [FIGHT: before any outside user enables approvals.] |
| Uninstall | "Disconnect & uninstall…" in Settings and tray: removes only our hook and MCP entries (with backups), login item, CLI link; data kept by default with "Export first / Delete data". `sidefolk-hook uninstall` works even if the app was dragged to the Bin. |
| Signing | Developer ID, hardened runtime, `notarytool` keychain profile or App Store Connect API key (never `APPLE_PASSWORD` in env), stapled DMG. **Founder buys the Apple Developer account on day 1** (it's on the critical path). |
| Entitlements | `automation.apple-events` + `NSAppleEventsUsageDescription`. No calendars (cut). |
| Updater | `tauri-plugin-updater`, signed `latest.json` on GitHub Releases, key offline/CI secret, install on consent. `min_safe_version` in the feed: below it, Pip stops answering requests (kill switch). **Before the first outside user.** [FIGHT] |
| Platform | **macOS 14+, Apple Silicon only.** Fix the 13.0 metadata. Intel when someone with Intel can test. [CONCEDE] if CEO wants universal, but then it's "untested on Intel". |
| Crash reporting | Local crash.log + archived dSYMs; no network upload in v1. Opt-in upload later. |
| Privacy | One-page privacy statement in-app; journal redacts secret-looking strings, 30-day retention, off switch, Clear; summary features stay labelled "uses Claude". |
| License | **Open source, Apache-2.0.** A tool in the permission path earns trust by being readable. [CONCEDE to CEO] |
| Price | Free for v1. [CONCEDE to CEO] |
| Channel | Notarized DMG on GitHub Releases + website; Homebrew cask after v1. No Mac App Store (private API, Automation). |

## D11. Release gates, beta, metrics

**Gates (each a recorded file in `docs/checks/` with date, build hash, pass/fail per line):**
- **G1 Trust:** B1, B2, B5, B9, F01–F03, F05, F06 closed, each with a regression test.
- **G2 Native matrix** on a signed build in a clean macOS user account (~45 lines, ~2 h of founder
  time): reminders visible/hidden/window-closed/quit/locked/asleep, notification denied→enabled,
  DST via time-zone change, corrupt-file recovery, 3 concurrent Claude sessions across
  Terminal/iTerm/Ghostty/VS Code, hold/release, open-session per host, uninstall, update.
- **G3 Private beta:** 8 testers (6 developers on Claude Code, 2 who use only reminders/log), 2
  weeks, the updater live.
- **G4 Public v1:** zero lost data, zero missed supported reminders, zero wrong-session or
  auto-approved requests, zero unanswered P1 bugs older than 48 h.

**Metrics:** no telemetry. An opt-in "Copy weekly summary" of counts only (reminders fired /
acknowledged, log entries, requests answered on Pip vs released, open-session success/fail), plus a
day-7 and day-14 interview.
**Continue / switch / stop at beta end:** continue as planned if ≥4/6 developers answer ≥5
requests on Pip across ≥3 days *and* keep reminders/log; **switch** the promise to the core track
if they keep reminders/log but release most requests to the terminal; **stop feature work and
rethink** if fewer than half of testers are still using it on day 14.

## D12. Process guardrails for the agents

1. `docs/V1-CONTRACT.md` is the frozen list; additions need a dated DECISIONS entry naming what it
   displaces, and a 24 h wait. [FIGHT]
2. One feature in progress at a time; each commit names its backlog ID.
3. **Done = tests + a dated founder hand-check line with a build hash.** Preview ≠ done.
4. CI must pass: typecheck, vitest, cargo test, `clippy -D warnings`, WebKit check, corpus.
5. Any change to `hooks.rs`, `requests.rs`, installers, uninstall or store loading needs a second
   agent's review (Claude ↔ Codex) and adversarial cases.
6. No new dependency without a DECISIONS line. No art changes. Deleting a feature deletes its code.
7. STATUS.md ≤150 lines, rewritten (not appended) at each handoff; history to a log file.
8. No commit over ~600 net added lines (deletions exempt); no UI claim without a capability-matrix row.
9. Agents never touch global agent configs (already in AGENTS.md); dev uses temp config dirs.

## D13. Roadmap (sizes in agent-days; founder time separate)

| Phase | Work | Size | Founder | Exit gate |
|---|---|---|---|---|
| **P0 Reset & contract** | Unstage film-duo; tag; `V1-CONTRACT.md` + capability matrix; delete cut code (~2,500 lines, `portable-pty`); rename metadata; min OS 14 | 2 | 1 h review; buy Apple account | Green build, one Pip, STATUS rewritten |
| **P1 Foundation** | `store.rs`, `requests.rs`, typed events, state into Rust, single instance, health on bind, async IO | 7–9 | 1 h | Corruption + reload-with-open-request tests pass; no polling |
| **P2 Reminders & log** | Series engine in Rust, pre-scheduling, missed/late, notebooks exact-or-ask, Inbox, timeline, export, "This week" | 6–8 | 2 h matrix | Fixed-clock suite; native reminder lines of G2 |
| **P3 Input** | Grammar fixes, quick-add, 250-phrase corpus, same-surface completion | 3–4 | 30 min | Corpus gates (D5) |
| **P4 Claude Code trust** | Sidecar + socket, hold/release, raw display + diffs, session names, open-session fixes, setup round trip, health; Codex spike + honest limits | 8–11 | 3 h, 3 sessions | Adversarial tests; G1 closed; agent lines of G2 |
| **P5 Window & Pip polish** | Component kit, IA, mockup parity, keyboard/VoiceOver, durable Undo, copy table, puzzled pose | 6–8 | 2 h + VoiceOver | WebKit both themes; founder sign-off on 5 screens |
| **P6 Release engineering** (parallel from P1) | Signing, notarization, entitlements, updater + kill switch, CI, uninstall, privacy page, redaction | 4–5 | 2 h + Apple wait | Clean-account install from downloaded DMG; 0.9.0→0.9.1 update keeps data; uninstall restores configs byte-identical |
| **P7 Private beta** | 8 testers, 2 weeks, fixes | 3–5 | interviews | G3 → G4 |
| **P8 Public v1** | Website, cask later, notes | 1–2 | 1 h | G4 |

**Total: ~40–54 agent-days.** Agents are fast; founder verification and serial phases are the
limit. **Honest calendar: 7–8 weeks to private beta, 10–11 weeks to public v1.** Cut line if it
slips: P4 runs late → beta starts on the core track with Sessions as beta (D1 gate), not a later
date. I won't promise "4 weeks"; the Apple account, the native matrix and two-week beta alone take
three of them.

**After v1 (sketch):** v1.1 Sparks on Rust state, one-way Apple Reminders, on-device model for the
Inbox, calendar heads-up. v1.2 Codex depth (approvals if its hooks allow), `sidefolk here` CLI,
AI-written weekly wins (labelled). v2: team messaging, only for sessions Sidefolk launched.

## What I'd fight for, in one list

No Sidefolk auto-answering (delete the deny-list) · fail-closed socket hook transport and the
updater before any outside user · no silent data loss (`store.rs`) · no English → shell · state in
Rust before the window polish · the release gate structure that keeps agent risk from blocking
reminders · frozen scope with dated one-in-one-out.

**I concede:** which Pip and the logo, price, license, Weekly wins placement, sounds/accent, the
promise wording, universal binary, and whether one-way Apple Reminders is v1 or v1.1.
