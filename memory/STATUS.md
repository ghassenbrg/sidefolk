# Status

Kept below 150 lines. History is in [LOG.md](LOG.md).

## Contract and current authority

Read [docs/V1.md](../docs/V1.md), DECISIONS and LEARNINGS before changing covered behavior.
Founder adopted **creative-design/review-2026-10-25** (decision 47): scoped 13 CSS px window
body / 12px metadata; overlay remains 16px / 44px targets. Both Pip and Spark stay (decision 41).
No agent may pass G1–G5. Native/clean-account evidence and founder sign-off remain required.

## Completed implementation in this continuation

Earlier commits: P0 5e411dc, P1 91327a5, P2 ad8d98a, P3 b69a91e, P4 65e3f99;
P5 foundation bbd1905. Current verified batch: ef8b103 through 09d739c, with the full list in the readiness report.

- Adopted paper/surface window, agenda/recent writing, notebook index/compact capture,
  footer companion + Quiet, responsive/larger text, separate Settings. Same-surface Quick add
  preserves drafts on cancel/failure. Pip/Spark art unchanged; both remain selectable.
- Completed multi-day/yearly recurrence, leap policy, occurrence/all-future scopes, all snooze
  choices, completed history, late tags/aggregation and two-minute fold preserving note/count.
- R13 project completion reminder: exact canonical Git root, native done event only, 24-hour
  expiry, visible explanation, no alarm/Overdue before trigger. Waiting/expired stay in Reminders.
- MCP status/control/reminders/notes use Rust state; no shell, permission answers or integration
  writes. Portable skill lives in skills/sidefolk; app installation requires native confirmation,
  path preview and exact backups. Durable provenance restores originals and preserves conflicts.
- Codex watcher is opt-in Beta, native-confirmed hooks.json merge/removal, exact backups,
  manual /hooks trust. Separate socket branch always silent; approvals remain in Codex.
  Host targeting retains the proven/fallback matrix; native checks remain pending.
- Native bounded session snapshots restore first prompts/latest states/outcomes after overlay
  reload without replayed notices. Rust retains pending MCP questions/deadlines, caps calls,
  rejects late replies; only ask replays, never notify/remind. Ask shows session/absence + expiry.
- Official native updater with specific retained offers, notes + native install/restart consent,
  monotonic persisted minimum, creation/resolution gates and pending release. Pause answers is
  persisted. Corrupt policy stays blocked across repeated restarts until explicit recovery.
- Native-confirmed uninstall restores managed skill files, preserves conflicts/data/backups and
  stays open on incomplete cleanup. Sensitive integration/history/recovery commands window-scoped;
  Hide has a separate overlay-only command. Report preview uses allowlisted settings/counts only.
- macOS14/hardened runtime/AppleEvents; fail-closed CI/release scripts; dSYM archive/notarization
  path prepared. Real key/feed/cert configuration is deliberately absent. Nothing published.

## Verification

Full `PATH=$HOME/.cargo/bin:$PATH npm run release:check` passed on the final implementation:
125 Vitest; 115 Rust passed / 3 intentionally ignored; strict all-target Clippy; 2 readiness
rejection tests; policy tests; full WebKit light/dark/narrow/larger text; P5 + reminder suites.
The 3 separately compiled policy tests are also in the Rust total. No live CLI/model tests.
Local release build passes: 9.54 MiB. No native app launch or desktop capture attempted.
Executable SHA-256: 9b972aa9a365fad3a1c3c17da460efeb1322ba4fdbfbe2dfc6735526398d81be.

Independent Codex review corrected policy restart-floor loss, missing-file Codex profile-link
retargeting and overlay Hide scoping. Final Replies/MCP pass found no concrete trust blocker.
All workers closed; no worktree/cherry-pick pending. Detailed evidence and requirements map:
[RELEASE-READINESS-2026-10-25.md](../docs/checks/RELEASE-READINESS-2026-10-25.md).

## Exact next step and remaining release gates

1. Founder supplies Developer ID identity, real updater keypair/feed and notarytool profile/API
   key. Select minimum, prepared docs/releases/0.1.0-candidate.md and reviewed revision attestation.
   `npm run release:ready` currently exits nonzero, correctly. Commands: docs/RELEASE.md.
2. Build signed review artifacts, then native G1/G2 trust/routing and reminder checks in a clean
   account. No claim from browser preview substitutes for focus/notifications/sleep/locked behavior.
3. Founder/design run keyboard/VoiceOver, five screens and recording/Mission Control protection
   choice (G3/G4). At most two verifiable founder items per day.
4. Downloaded DMG Gatekeeper, real signed update preserving data, uninstall round trip and hosted
   CI evidence (G5). Workflows prepared locally but never dispatched/published.
5. P7 real two-wave/four-week cohorts and measurement/interviews, then P8 public ownership,
   domain/repository/license decision, version/site/launch/cask. Do not invent cohort evidence.

## Unresolved earlier incident / unrelated work

Earlier P4 uninstall test removed real Sidefolk MCP connections/login item (Claude confirmed;
Codex likely). Fixed before P4 commit, disclosed; **no restoration performed**. Recovery needs
explicit authorization/current paths, never guessed entries or stale temp data directories.
See docs/checks/P4-INCIDENT.md and LEARNINGS. Tests use explicit temporary Places/profiles.
Six art/blender/film-duo additions remain staged unchanged and excluded from every commit.
Use path-limited commits; never add Co-Authored-By. No global agent config edits.
