# Status

Kept to 150 lines or fewer (docs/V1.md §13.9). History is in [LOG.md](LOG.md).

## The plan

[docs/V1.md](../docs/V1.md) is the binding v1 contract (25 October 2026). It covers every
feature's status, the requirements by ID, the gates G1–G5, the roadmap P0–P8 and the guardrails
in §13. Read it first. How it was decided:
[docs/audit-2026-10-25-claude/](../docs/audit-2026-10-25-claude/) (Claude's eight-seat council,
the comparison with Codex's audit, and the supreme council's papers and RULING.md).
[creative-design/PIP.md](../creative-design/PIP.md) is Pip's character bible, frozen for v1.

## Where we are (25 October 2026, Claude Code)

- **P0 Reset and P1 Foundation are committed** (`5e411dc`, `91327a5`); the details are in
  [LOG.md](LOG.md):
  - deleted features
  - store.rs data safety
  - `$`-only commands
  - requests in Rust, with Codex's review fixes
  - no polling, single instance
  - Pip and Spark
- **P2 and P3 are committed** (`ad8d98a`, `b69a91e`); their notes moved to [LOG.md](LOG.md). P4 is below.
- Release build 5.11 MiB at P4; not relaunched on the user's Mac.

## P4 Claude Code trust (25 October, Claude Code): built, verified, reviewed by Codex

- **Sidecar over a Unix socket** (`socket.rs`, DECISIONS #45):
  - Claude Code runs `test -x '<exe>' && exec '<exe>' hook || exit 0 # sidefolk-hook`.
  - `sidefolk hook` forwards stdin to `<data>/hook.sock` (folder 0700, socket 0600,
    same-uid peer). It prints only a well-formed permission answer, else nothing, and always
    exits 0 (about 10 ms with no app).
  - MCP calls go over the socket with the token. HTTP on 47821 is kept for legacy hooks and
    `/dev/*`.
- **Setup** (`claude_setup.rs`): installs command hooks and knows Missing, Current and
  NeedsRepair (legacy HTTP or a moved app). Repair is in Settings, and setup refuses a
  translocated app.
- **Uninstall** (`uninstall.rs`): window (About & data), menu bar, `sidefolk uninstall
  [--delete-data]`. It removes only our hooks and MCP entries (with backups) and the login
  item; data goes to the Bin only when asked.
- **Routing:**
  - Requests are held on Pip unless that session is focused (`Hosts::focused`, the host
    matrix in V1 §7.2).
  - While held, a 500 ms watch releases the request when the user goes there. Pip says "Moved
    to your terminal".
  - Open releases too.
- **Identity:** clicking Pip lists up to 4 live sessions (folder, first prompt line, state)
  above the field. The window's session rows say where each runs ("in Ghostty").
- **Health:** Settings → AI tools shows one state (Connected / Working / Needs repair / Can't
  listen) with Repair.
- **Spikes:** docs/SPIKES-P4.md. Ghostty has no tty in its dictionary, so the fallback stays;
  WezTerm isn't installed here. **Codex 0.160 has stable documented hooks, including
  `PermissionRequest`**: F-14 can use the sidecar in P6 (founder decision needed on V1-D2).
- **Codex review:** 11 findings. Fixed with tests:
  - exact answer schema;
  - `CLAUDE_CONFIG_DIR`;
  - osascript 2 s deadline with a shared 400 ms cache;
  - one hook deadline with a 64 KB reply cap;
  - only a stale socket is ever replaced, never through a link;
  - 32 connections;
  - uninstall keeps data on any failure and moves it only as the app quits; the CLI refuses
    while the app runs;
  - pid reuse, wrapper shells, SessionEnd forgets;
  - per-event install check;
  - the ignored test canonicalizes.

  Accepted (DECISIONS #45): same-user trust, and an older binary at the hook path.
- **Verified:** typecheck, 88 Vitest, 64 Rust, clippy (only the 6 older warnings), release
  build 5.11 MiB (hook mode with no app: silent, exit 0, 10 ms),
  WebKit (health pill, "Can't listen", uninstall sheet keeps data by default, Pip's session
  list).
  - **Not hand-checked:** a real Claude Code session going through the sidecar, release on
    focus, and Repair after moving the app (G2-agent).

## Next step (exact)

**P5 Window & Pip** (V1 §8, §14):
1. Component kit and re-implemented views on `src/tokens.css`. Read the design handoff in
   `creative-design/review-2026-10-25/` first.
2. A separate Settings window with 4 categories, setup, keyboard/VoiceOver, durable Undo.
3. Pip's voice table, the puzzled pose, micro-frames; the recordings spike (V1-X8).
4. Before P5, ask the founder about V1-D2 (Codex approvals on Pip) and the Ghostty working
   directory check (docs/SPIKES-P4.md).

## Waiting on the founder (V1 §16)

- Veto any reversal in V1 §15, or let it stand.
- The staged `art/blender/film-duo/` files are kept out of the phase commits and stay staged;
  V1 F-41 says they move to branch `art/film-duo`, on the founder's word.
- Apple Developer Program enrolment (critical path for G5); the wave-1 testers (8 developers +
  3 people with no agents); a domain; making the repo public under MIT.
- Hand checks in the real app once P1–P5 land (gates G2, G4), and the Mission Control spike
  for "Hide from screen recordings" (V1-X8).

## Known gaps (not done, do not claim)

- Codex sessions are not watched; the spike found documented hooks (P6).
- The window is still the old CSS (P5). Settings still has 8 categories, not 4 (P5).
- No signing or updater (P6). Existing HTTP hooks show "Needs repair" until Repair is pressed.
- Clippy shows 6 older warnings; CI with `-D warnings` comes in P6.

## Design handoff (25 Oct, Codex; founder requested a UI/UX team)

- New proposal: `creative-design/review-2026-10-25/` — 34 WebKit-rendered boards, 5 native-size
  references, editable local prototype, HANDOFF.md, component/behavior specs and asset manifest.
- Keep Pip Signal/Pip/Spark/palette; new Today/agenda/notebook composition, separate Settings.
  Scoped 13 CSS px window type is an explicit proposal versus V1's 13 pt; no gate passed.
- Verified: 34 exports, 48 native-size/theme combinations, 10 focused prototype scenarios.
  Domain/native services are disconnected. No production source edits or commits by this task.
- Handoff: read the package README/HANDOFF for P5; current P2 backend priority is unchanged.
