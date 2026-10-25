# Sidefolk implementation and release readiness — 25 October 2026

**Decision: keep the existing Tauri/Rust product and ship a narrower, calmer v1 once the native
and distribution gates pass. This implementation is a development candidate, not a public release.**
The binding requirements, exclusions and gate definitions remain [V1.md](../V1.md). The council
ruling is [here](../audit-2026-10-25-claude/supreme/RULING.md). No agent passed G1–G5.

## Implemented scope

| Requirements | Implementation and observable behavior |
|---|---|
| U2/U7, P5, founder decision 47 | Adopted review-2026-10-25 window package: scoped 13 CSS px body, 12px metadata, paper/sidebar canvas, surface content, time-led agenda, actual recent writing, notebook index, compact capture, separate Settings. Overlay stays 16px with 44px controls; larger text and reduced motion remain. Pip and Spark both stay. |
| R2–R8 | Rust recurrence/overrides: multi-day weekly rules, yearly leap-day policy, This one/All future editing, all snooze presets and Pick, late aggregation, no hidden seven-day deletion of completed reminders. A two-minute fold keeps the request, held note and count without answering or re-nagging. |
| R13 | Exact-project completion conditions, confirmed canonical Git root, 24-hour expiry. Only an observed done event triggers; idle/end/failed do not. Waiting/expired conditions never become timed alarms or Overdue. Expiry remains visible with an explanation. |
| L2/L3/L7, Q1 | Exact-or-ask notebooks, draft-preserving same-window finishing, editable Log it from first prompt/project, complete timeline and Your week. Capture/errors remain on their initiating surface. |
| F33/F34, founder decision 47 | MCP status/control, reminder management and notebook read/append use native state. Existing notify/ask/remind/presence remain. No tool can approve operations, execute shell, install connections or edit global configuration. |
| F14/D2 | Codex lifecycle hooks, opt-in Beta, separate event-only socket dispatch. PermissionRequest reports status/Open only. The hook always exits zero with no stdout decision. Native-confirmed installer, exact backup, marked removal, repair/disconnect and manual /hooks trust. |
| P1/S8 | Bounded typed Rust session snapshots restore first prompt/latest state/outcomes after overlay reload, silently and with original timestamps. Pending MCP questions retain payload/deadline in Rust, reject late replies and cap concurrent calls. Notify/remind are never replayed. Journal remains first-line-only, seven UTC dates, opt-out/Clear. |
| X2/X3 | Skill installer previews paths, requires native consent, preserves exact original bytes/provenance and detects changed files. Uninstall restores managed originals, preserves user edits/unrelated files, reports conflicts, keeps data/backups and stays open on incomplete cleanup. Global paths are resolved only in runtime adapters; tests use explicit temporary Places. |
| X4–X7/X9/X10 | macOS 14 metadata, hardened runtime/AppleEvents, official updater, persistent monotonic minimum version, fail-closed hold creation/resolution, pending release, persisted Pause answers, release scripts/CI and dSYM archival path. Installation/restart each require native consent. |
| X11/X12 | Local-data privacy copy; report preview and explicit Copy. A small settings allowlist and diagnostic counts replace raw logs, paths, names, prompts and tokens. Nothing is sent automatically. |

## Agent controls and installation

In Settings → Agents, connect MCP for Claude Code or Codex. Install the Sidefolk skill with the
corresponding button; the native dialog identifies its files. The agent then discovers tool
schemas and authoritative status before acting. See [the skill](../../skills/sidefolk/SKILL.md).
The app installer was implemented and tested; **no real agent skill/config was installed by this work**.

| Tool | Supported actions |
|---|---|
| sidefolk_status | Companion preferences/native visibility and counts; excludes raw operations/secrets. |
| sidefolk_control | show, hide, summon, open_window, open_settings, set_look (pip/spark), rename (24 chars), set_quiet, set_size. |
| sidefolk_reminders | list, add with exact epoch milliseconds, complete one occurrence, snooze, delete. |
| sidefolk_notes | list_notebooks, read, append; exact ID/full name or default Log. No near-name guesses. |
| ask | User question with supplied session identity (or an explicit absence), visible deadline, bounded wait and reload continuity. This is separate from operation approvals. |

Codex watching and its MCP connection are independent. Installing hooks does not grant trust:
the person must review `/hooks` in Codex. Host targeting still follows the proven/fallback matrix
in [SPIKES-P4](../SPIKES-P4.md), not an assumed exact tab. Native host behavior remains unverified.

## Independent review and corrections

A bounded independent Codex review examined updater policy/consent, MCP capabilities,
installer/uninstall provenance, hook dispatch and release scripts. Three actionable findings:

1. **Minimum floor forgotten after quarantine/restart:** missing active policy plus surviving
   backup/quarantine now stays blocked; regression covers two subsequent reloads, a lower feed
   and explicit restoration. Resume cannot bypass the minimum.
2. **Missing Codex hooks file allowed profile-link retargeting:** snapshots now resolve the
   existing ancestor. A temporary A→B retarget regression verifies neither profile is written.
3. **Window scoping broke overlay Hide:** Hide now has a separate overlay-only native command;
   integration/history/recovery remain window-scoped and failures are surfaced.

The reviewer verified the first two corrections and the observational-only Codex boundary by
inspection. The lead integrated the narrow Hide correction. A final independent pass found no concrete trust
blocker in pending-question capping, atomic identity/deadline resolution or ask-only reload recovery. Native UI behavior is still a hand
check. Installer tests never call actual agent CLIs or touch global profiles.

## Automated evidence

Final complete run passed: **125 Vitest tests, 115 Rust tests (3 intentionally ignored),
strict all-target Clippy, 2 readiness rejection tests, 3 separately compiled policy tests and all
three WebKit suites**. The policy tests are also included in the Rust total, not additional unique
tests. Local logs are under /tmp/sidefolk-*.
The complete command is `PATH=$HOME/.cargo/bin:$PATH npm run release:check`.
No ignored/live CLI or model tests run; no desktop app launch or desktop screenshot was used.

- Typecheck and Vitest, including the 300-phrase corpus and voice table.
- Locked Rust tests including recurrence, storage, policy restart, sidecar deadlines, exact
  backups, skill restoration/conflicts, Codex merge/stale paths, session and question reloads.
- Strict Clippy on all targets, with no suppressed warnings.
- Offline release-readiness rejection tests and the policy module tests.
- Full WebKit journeys in light/dark plus narrow/larger-text; P5 setup/privacy/Undo/keyboard,
  silent session restore, folded reminder and six 150px Pip/Spark checks.
- Reminder WebKit harness at 640×480: retry, callbacks, weekly/yearly rules, scopes, snooze,
  history, exact event confirmation/expiry and no spurious timed delivery.
- Local release bundle build: **9.54 MiB**. Executable SHA-256:
  `9b972aa9a365fad3a1c3c17da460efeb1322ba4fdbfbe2dfc6735526398d81be`.
  **Not Developer ID signed/notarized distribution evidence.**

## Remaining release work and required evidence

| Gate / owner | Remaining concrete action | Evidence required |
|---|---|---|
| P6 credentials / founder | Supply Developer ID identity, real updater keypair/feed, notarytool profile/API key. Select the prepared candidate notes, minimum version and reviewed revision. | Readiness exits zero; no placeholder secrets/feed. See [RELEASE](../RELEASE.md). |
| G1/G2-agent / founder | Signed clean-account three-session/three-host routing: full operation read, Allow/Decline, focus release ≤1s, expiry, failed channel, app absent, Open and no duplicate resume. Include manual Codex hook trust/status, no Codex answers. | Build hash and outcome for every host matrix row. |
| G2-core / founder | Visible/hidden/window closed/quit/locked/asleep reminders, notification denied→enabled, DST/zone switch and corruption recovery. | Native notification timing and data preservation on the signed build. |
| G3/G4 / founder + design | Independent input/voice review; keyboard and VoiceOver J1–J5; five screens versus adopted package; recording/Mission Control protection decision. | Dated results and founder/design sign-off. Browser evidence does not substitute. |
| G5 / founder | Run credentialed candidate workflow; download DMG, Gatekeeper, real signed update preserving data, install/uninstall round trip. | Green hosted CI, notarization/stapling evidence, exact artifact checksums and native results. |
| P7 / founder + testers | Wave 1: 8 daily Claude developers + 3 non-agent users for two weeks; Wave 2: 20 people for two weeks if zero trust incidents. | Day 7/14 interviews and contract targets, with no invented cohort results. |
| P8 / founder | Public ownership/domain/repository/license decision; final version, site, launch notes and Homebrew cask only after gates/cohorts. | Approved public release artifacts and actual checksum/URL. No distribution was published. |

Keep founder checks to at most two verifiable items per day. First prepare the signed candidate;
then prioritize native trust/routing and reminder delivery. Resolve failures before widening beta.
No agent can supply the credentials, sign off VoiceOver/host observations or compress four weeks
of real beta usage into automated tests.

## Earlier configuration incident

The earlier P4 uninstall test incident was disclosed and fixed before P4 commit. Real Sidefolk
MCP connections/login item have **not been restored by this work**. Recovery needs the person's
explicit authorization and current paths; do not guess or reuse a stale temporary data directory.
Details: [P4-INCIDENT](P4-INCIDENT.md). Six unrelated staged film-duo files remain excluded.

## Implementation commits

- `ef8b103` — P6: add official updater dependencies and macOS release metadata
- `39b7946` — P6: persist update safety policy and preview redacted reports
- `0e1fee2` — Add bounded MCP companion controls and portable agent skill
- `0c09bfc` — Install and restore agent skills with confirmed exact backups
- `3afc58b` — Complete reminder occurrence overrides and project completion engine
- `91a3e6d` — Resolve exact project reminders and finish repeat grammar contracts
- `f04bb13` — Finish reminder scopes, snooze choices and calm folded delivery
- `e746273` — Add observational Codex hooks and safe connection cleanup
- `40277cf` — Wire native safety gates and preserve sessions and questions on reload
- `1c3701c` — Apply the adopted window design and preserve same-surface capture
- `09d739c` — P6: require complete checks before signed release candidates
