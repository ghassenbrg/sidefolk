# Supreme council of Sidefolk: brief

Three seats decide, once and for all, what Sidefolk v1 (first public release) is. The founder
said: everything can change; even deleting everything and starting from scratch is allowed;
this council decides everything about the project. The CEO has the final word, but must
answer the other two seats' strongest objections in writing.

## Read (all of it, in this order)
1. /Users/ghassenbrg/git/sidefolk/docs/PLAN-V2.md section 1 ("What you asked for": the
   founder's own priorities) and section 11 (decisions already made with the founder).
2. /Users/ghassenbrg/git/sidefolk/docs/audit-2026-10-25-claude/COUNCIL-REPORT.md (Claude
   council, 8 seats) and its seats/*.md as needed.
3. /Users/ghassenbrg/git/sidefolk/docs/audit-2026-10-25/COUNCIL-REPORT.md and
   RELEASE-BACKLOG.md (independent Codex council, 8 seats) and its memos as needed.
4. /Users/ghassenbrg/git/sidefolk/docs/audit-2026-10-25-claude/ADDENDUM-COMPARISON.md
   (where the two audits agree/disagree, chair-verified).
You may read source code to settle a factual question (read-only). Do not edit the repo,
touch global configs, call models, or start servers. Write only under
/private/tmp/claude-501/-Users-ghassenbrg-git-sidefolk/79ad1c59-782a-4b01-be5b-e7d309827902/scratchpad/supreme/.

## Decisions this council must make (answer every one, concretely)
D1 Audience and the one-sentence v1 promise (A everyday work companion / B developer
   attention companion / a specific hybrid with an explicit gate; not "everything for everyone").
D2 Feature inventory: for EVERY feature that exists today (Pip companion; typed phrase input;
   Tell bar; reminders one-off/repeat/snooze/history; notes & notebooks; AI draft summary;
   quick shell commands; saved actions; open app/folder/URL; watching Claude Code; watching
   Codex; permission requests on the companion; per-session full access; start sessions;
   open/continue session; Sparks; terminal inside Sidefolk; calendar heads-up; morning brief;
   weekly wins; ten characters + 3D/2D; character import/export; accent colors; sounds; TTS
   voice; setup guide; settings; CLI `sidefolk here`; MCP tools notify/ask/remind/spark/presence;
   Dock app + window; menu bar icon; hide from screen recordings; Copy report) say
   STABLE v1 / BETA (flagged, off by default) / LATER / DELETE CODE, with one reason.
D3 Reminder contract: recurrence semantics, snooze vs series anchor, missed/ignored/late,
   app quit/sleep/DST, phone reach (Apple Reminders sync or not).
D4 Notes / work log contract: destinations, ambiguity, inbox, timeline, export, agent work
   feeding the log or not.
D5 Input model: what typing does (quick-add vs commands), unknown text, shell prefix, any
   on-device/LLM fallback, and the phrase coverage target.
D6 Developer capability contract (if any in v1): which tools (Claude Code, Codex), which hosts
   for exact-session open, request routing rule (fix "terminal frontmost skips Pip"), approval
   display (raw bytes/diff), full access (keep/withhold/delegate), hold timeout behaviour.
D7 Character, brand and voice: which Pip (ivory clay vs charcoal logo), Spark or not, other
   characters, styles, voice rules, what is frozen.
D8 App shell and UI: Dock vs menu-bar-first, window rebuild vs polish against the approved
   mockups, sidebar and settings structure, component kit, visual bar.
D9 Architecture: keep/refactor/replace per subsystem; state ownership (overlay vs Rust);
   data durability/migrations; error handling; tests to add.
D10 Security, privacy and distribution: hook transport, uninstall, signing/notarization,
   entitlements, updater, min macOS + CPU arch, crash reporting, license, price, channel.
D11 Release gates, beta plan, metrics and continue/switch/stop rules.
D12 Process guardrails for the agents building it.
D13 Roadmap: ordered phases with size estimates and exit gates, to public v1 and a sketch after.
