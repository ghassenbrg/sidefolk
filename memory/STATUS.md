# Status

Kept below 150 lines. History is in [LOG.md](LOG.md).

## Contract and references

[docs/V1.md](../docs/V1.md) is binding; agents never pass gates G1–G5. Audit/ruling:
[docs/audit-2026-10-25-claude/](../docs/audit-2026-10-25-claude/).
Pip and Spark always stay (founder decision #41); bible: creative-design/PIP.md.
UI: approved review-2026-10-24; newer review-2026-10-25 remains a proposal where it conflicts
with the contract (especially 13 CSS px versus 13 pt). Read DECISIONS and LEARNINGS first.

## Current work (25 October 2026, Codex)

P0–P4 committed: `5e411dc`, `91327a5`, `ad8d98a`, `b69a91e`, `65e3f99`.
Their details are in LOG.md. P4 native sidecar/focus/Repair hand checks remain pending.

**P5 foundation verified; next iteration applies the founder-adopted new design package.** See [checks/P5.md](../docs/checks/P5.md).

- Separate native Settings window (`preferences`); main window keeps legacy label `settings`.
  Settings opens via CmdComma without replacing the main window. Async commands return native
  builder/focus errors. Four searchable panes, old deep links preserved.
- One window stylesheet (`window.css`) replaces dashboard.css + redesign.css, on tokens:
  28px controls, contracted 13pt base, same light/dark palette, compact sidebar and agenda,
  at most two row actions, keyboard overflow menus, native sheets/radios and retry states.
- Persistent Undo stack within the open window, across navigation/later messages; failed Undo
  remains retryable; busy actions cannot run twice. CmdZ outside text editors and native Edit
  menu bridge; text editors retain text Undo. Closing/reloading ends that webview's stack.
  Notebook capture drafts survive navigation. Modal errors appear inside the modal.
- One Claude hooks + MCP confirmed connection flow, exact backups, missing/moved components
  show Repair. Persisted pending-disconnect direction prevents reconnecting on retry/restart.
- Setup requires a saved reminder with visible time/zone; notifications/login/protection choices;
  connection finishes only on a live first event, or explicit Skip. First-heard broadcasts health.
- Summon focuses Quick add and preserves its draft; reserved CmdShiftReturn focuses newest
  card container without selecting Allow. Changing summon leaves the card shortcut alone.
- Quiet by default for new installs; configurable snooze used on both surfaces.
- New history: seven UTC calendar dates, first prompt line only (500 characters), no tool,
  answer or agent-output detail. Off switch and confirmed Clear. Cleanup also runs while
  recording is off. Existing older detail expires or can be cleared, not silently rewritten.
- Shared voice/error table with tests; native installer dialogs use static recovery copy and
  log diagnostics. Existing raw operation display remains byte-exact.
- Both characters: distinct puzzled behavior uses approved folded-ear listen frame, pose fades,
  subtle dark rim; immediate reduced-motion swaps; no idle/listening/puzzled activity light;
  accessible companion name + state. No new generated assets or art-pipeline change.
- Codex review (two passes): six findings fixed: persisted disconnect direction, independent
  shortcut rebind, draft-preserving summon, live first-event health, first-line extraction
  before whitespace clipping, expiry while history is off. Added temp-only fault tests for
  initial persistence, stale hook write, MCP failure/restart and final persistence, including
  a try_lock assertion that external work never holds the settings mutex.

Verification so far:
- Typecheck; 91 Vitest; 68 Rust passed / 3 ignored. No live agent CLI/model calls or native app
  launch. All installer tests target temporary paths and fake MCP work.
- Full WebKit journeys pass light/dark and narrow/large text on the final source.
- P5 WebKit regressions passed setup waiting→event/Skip, history confirmation, failed/busy Undo,
  Quick add draft/Tab, safe card focus and six 150px character/wallpaper checks.
- Final release build succeeds at 5.16 MiB, including the corrected CLI Settings path.
- Clippy completes: six existing production warnings and one existing test warning.
- No G2/G4/G5 gate passed. No desktop capture attempted (repo rule).

## Exact next step

1. Founder now explicitly adopts review-2026-10-25 and requests MCP + skill control, then all
   remaining release work. Apply the package, including scoped 13 CSS px, and record authority.
2. Commit verified milestones without Co-Authored-By. Exclude staged art/blender/film-duo and leave
   them staged exactly as found. No global agent config writes.
3. P5 founder checks in checks/P5.md: native Settings coexistence, shortcuts/focus restoration,
   Edit/text Undo, VoiceOver and design comparison, real isolated Claude install/focus/Repair.
   Recording-protection spike needs Mission Control/screen-share observation by the founder;
   default stays off until a result is recorded.
4. Then P6 distribution/Codex beta per V1.md; do not silently expand Codex approval handling.

## Incident requiring explicit restore authorization

An earlier P4 uninstall test removed real Sidefolk MCP connections and its login LaunchAgent
(Claude confirmed; Codex likely). It was fixed before P4 commit; tests now use explicit Places,
temp paths and no real agent list. The user was informed at the start of this continuation.
**No restoration performed.** See [P4-INCIDENT.md](../docs/checks/P4-INCIDENT.md) and LEARNINGS.
Do not guess the removed Codex configuration or reuse a stale temporary data-directory entry.

## Waiting on founder / external inputs

- G2/G4 native and design checks; recording-protection result. Browser layout evidence is not
  proof of native focus, notifications, sidecar routing, VoiceOver or screen protection.
- Codex hooks spike found documented hooks (SPIKES-P4.md); V1-D2 still forbids answering Codex
  approvals on Pip. Keep that boundary unless explicitly changed.
- Apple Developer Program enrollment, testers, domain, repo public/MIT decision for G5.
- Art/blender/film-duo files remain staged and excluded; moving to art/film-duo needs founder word.
- Six existing production clippy warnings and one old test warning remain for P6 CI cleanup.

## Design handoff preserved

creative-design/review-2026-10-25 contains 34 boards, five native-size references, editable
prototype, behavior/component specs and manifest from the founder-requested UI/UX team.
P5 uses compatible principles, retains 13pt and frozen Pip/Spark art; founder sign-off pending.
