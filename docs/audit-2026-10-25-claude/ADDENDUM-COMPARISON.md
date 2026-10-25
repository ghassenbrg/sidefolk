# Addendum: Claude council vs Codex council

25 October 2026 · Written after [COUNCIL-REPORT.md](COUNCIL-REPORT.md) was frozen. Compares it
with the Codex audit ([../audit-2026-10-25/COUNCIL-REPORT.md](../audit-2026-10-25/COUNCIL-REPORT.md))
on the same revision (`76b38f1`). Each disputed or one-sided claim was re-checked in the source
by the chair (✔ = confirmed today).

## Where both audits agree (strong signal: reached independently)

| Topic | Both say |
|---|---|
| Restart? | **No full restart.** Keep Tauri + Rust core, stores, installers, Markdown notes, tokens, logo and existing art. |
| Full access | A deny-list can't guarantee safety. It's checked on clipped text and mixes Sidefolk auto-answering with the agents' own launch modes. Withhold it or delegate it to the agents' native modes. |
| Approval cards | Never decide or display from an excerpt. Show the full raw operation or hand the decision back to the tool. |
| Time parsing | Bare hours pick the wrong day ("at 3" → tomorrow 15:00). Keep parsing local and fix it deterministically. |
| Codex | Ordinary Codex CLI sessions are not monitored. Configured MCP ≠ monitoring. Claims must match the real capability. |
| Release | Not signed or notarized, no updater, no native acceptance evidence, platform contract unclear. Public v1 is blocked. |
| Scope | Too many concepts. Defer the embedded terminal, background actions, character authoring, calendar/briefs and AI drafting from the stable promise. Freeze scope. |
| Process | "Built" ≠ verified. Native hand checks and real outside users must gate each step. |
| Keyboard/accessibility | Window foundations are decent. Focus is lost on async steps, timed Undo isn't enough, and real VoiceOver checks are still needed. |

## Found only by Codex (confirmed, added to the requirements)

| Codex ID | Finding | Check |
|---|---|---|
| F03 | **Silent data loss.** A damaged or unreadable `reminders.json` loads as an empty list, and the next save overwrites the user's file. Actions and crew behave the same. Settings does the opposite and aborts launch. | ✔ `reminders.rs:100-103` (`.ok()…unwrap_or_default()`) |
| F05 | **Repeat and snooze semantics.** A repeat advances only when marked Done, so an ignored daily reminder never schedules the next day. Snoozing moves the series anchor (Monday weekly → Tuesday forever). | Source per Codex (`reminders.ts:183, 232`); accepted |
| F06 | **A note can land in the wrong notebook.** An ambiguous prefix ("evaluation") picks the most recently updated of several matches, silently. | ✔ `notes.ts:22-28` |
| F07 | **One task needs two surfaces.** The window's Tell bar handles run/start itself and sends everything else to the companion, so reminder confirmation and notebook choice can only finish in the desktop bubble. | ✔ `dashboard/tell.ts:39-45` |
| F08 | **"Connected" means a config line exists,** not that the hook server, binary path or events work. A failed port bind is only printed. | Consistent with Elena's port finding; accepted |
| F09 | **Timeout copy is wrong for Sidefolk-owned Codex** (it declines, it doesn't "ask in its window"). MCP questions carry no session identity or deadline. Recent results are keyed per project, so one replaces another. | Accepted |
| Ines-C | **Pip's idle "thinking" pose uses the same blue signal as real agent work,** so decoration can look like activity. The status orb uses a bunny-ear coordinate for every species. | Accepted |
| F12 | **Bundle metadata says macOS 13, README says 14+.** The release script silently skips the WebKit check when no preview is running. | Accepted |

## Found only by Claude (Codex missed or under-rated them)

| Claude ID | Finding | Check |
|---|---|---|
| B2 | **Requests skip Pip whenever any terminal, editor or Claude desktop is frontmost.** A developer's terminal is almost always in front, and the waiting session is often in another tab. This defeats the feature's main use. | ✔ `hooks.rs:222-266` |
| B5 | **No uninstall, and leftover hooks trust a dead port.** Any process that binds 127.0.0.1:47821 after Sidefolk is gone gets every prompt and tool input and can answer "allow". | Source (Omar); needs a native test |
| B6 | **English becomes shell commands.** "make coffee", "touch grass" and "less email please" offer "Run in terminal". Common phrasing without "remind me" fails: "call mom at 5pm", "dentist thursday 2:30". Codex lists "local understanding" as a strength; Claude rates the live parser a blocker for anyone who isn't a developer. | ✔ chair probe; Maya's 51 phrases |
| B7 | **The Add reminder date field shows a grey placeholder date with an empty value,** so Save fails. | Sam, observed in WebKit |
| B8 | **No keyboard or VoiceOver path to the companion.** The summon shortcut doesn't open the field, and cards are never focusable. | Sam, `main.ts:306`, `bubble.ts:14` |
| — | **Competitive landscape.** The agent-status pet is now common: notch monitors, several pets, and the Codex app ships its own pets. Codex's comparison stops at Apple, Raycast and Claude hooks. | Priya, web sources |
| — | **The window looks like a web admin panel** (Jun: 4/10). Heavy outlines everywhere, 44 px controls, unstyled native inputs, placeholder icons, Sessions and Review not matching the approved mockups. Codex: "not generally ugly; hierarchy problems". | Subjective. Both note five actions per row, decisions below the fold and two sidebars. |
| — | **Character identity churn** (four pipelines in three days; the shipped Pip doesn't match the charcoal logo). Voice leaks raw errors (`rate_limit`, `String(e)`). | Ines |
| — | **The overlay webview owns the domain state.** The window polls a JSON snapshot, and a look change reloads the overlay and drops open permission cards. 113 `unwrap()`s under `panic=abort`. Main-thread config reads every 3 s. The Codex driver is dead code. | Elena. Codex reaches the same conclusion ("shared service boundary") from F07. |

## The real disagreement: who is v1 for?

| | Codex council | Claude council |
|---|---|---|
| Recommended first promise | **A, everyday work companion:** dependable reminders + dated work notes; developer attention is an optional extension that must earn its own gate | **B, developer attention companion:** know which session needs you, answer safely, go back to it; work log and reminders as satellites (6 of 8 seats) |
| Main argument | Matches the founder's stated priorities (reminders #1, notes #2). First value doesn't depend on changing agent integrations. | The market for reminders and notes is saturated (Apple, Raycast); the agent problem is sharp and growing; the founder's own examples are developer habits. |
| Main risk | Mature competitors; reminders don't reach the phone; the payoff comes late | The hardest, most fragile code is the first-minute experience; a crowded niche |
| Persona votes | Its Maya favoured B, its Leo favoured A (inverted) | Our Maya wanted A with a dev mode; our Leo wanted B |

**Chair's reading.** The two councils' personas voted against type in opposite directions, so
the audience question is a real fork, not a factual dispute. It goes to the supreme council
with both cases presented fairly. Both councils agree it must not be averaged into option C
(everything for everyone).

## Corrections to the Claude report

- Claude B9 said "113 unwraps"; this was not re-verified as a crash path. Codex adds the
  data-loss side (F03), which is more urgent than the panic count.
- Claude's report listed "reminders that fire" without a recurrence contract. Codex F05 shows
  the contract itself is undecided, so it's added as a decision.
- Claude's "rebuild the window" camp should note Codex's point: the approved mockups and the
  tokens already exist, so a rebuild means re-implementing toward them, not a new design.

## Corrections to the Codex report

- Codex's "unknown text is never silently sent to a model" is true, but the parser *does* send
  plain English to the terminal confirmation card. That is a trust failure for direction A's
  own audience.
- Codex does not mention B2 (requests skip Pip whenever a terminal is in front). Any option
  that includes developer attention, even as an extension, has to fix it first.
- Codex's competitor scan misses the crowded agent-pet niche (including the Codex app's own
  pets). That strengthens Codex's caution about B but also means B needs a sharper wedge.
