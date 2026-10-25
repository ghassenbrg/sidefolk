# Evidence and verification ledger

25 October 2026 (Asia/Tokyo). Current source at `76b38f1`; audit documents are additional uncommitted files. Existing staged film-duo artwork was present before the audit and left untouched.

## Checks executed by the council chair

| Check | Result | What it establishes |
|---|---|---|
| `npm run typecheck` | Passed | Current TypeScript checks |
| `npm test` | 100 passed in 13 files | Existing frontend unit coverage, not observed participant behavior |
| `~/.cargo/bin/cargo test --manifest-path src-tauri/Cargo.toml` | 34 passed, 3 ignored | Existing enabled backend tests; ignored installer/live-tool tests were not run |
| `npm run check:webkit` | Passed | Existing preview routes and interactions in light/dark, including reminders, notes, request acknowledgement, themes, settings, terminal preview and narrow layouts |
| `npm run web:build` | Passed | Production frontend bundle compiles |
| `npm run build` | Initial attempt could not locate Cargo | Audit shell PATH issue, already described in memory/LEARNINGS; no application defect inferred |
| `PATH="$HOME/.cargo/bin:$PATH" npm run build` | Passed | Current release app bundles successfully; 9.27 MiB reported by bundler |
| `codesign -dv --verbose=2 .../Sidefolk.app` | Ad-hoc, ARM64, no TeamIdentifier, no sealed resources | This local artifact is not a Developer ID signed release; notarization/Gatekeeper acceptance were not established |
| `TZ=Asia/Tokyo node docs/audit-2026-10-25/probes.mjs` | Completed; discrepancies recorded | Direct source function calls for parsing and approval-string classification; no represented shell operations were executed |
| `git diff --check` and explicit new-artifact validation | Passed | Tracked whitespace; all 14 audit files checked for whitespace, JSON syntax and local link existence |

Rust emitted one unused-variable warning in the notes test (`first` at `src-tauri/src/notes.rs:350`). It did not affect test completion.

The release bundle was rebuilt in its standard output location. It was **not launched**, and the user's existing running app was not quit or replaced as a process. No signing credentials, global agent configuration, user notes/reminders, notification permission, calendar permission or Automation permission were changed.

## Browser evidence

The pre-existing Vite preview at `http://127.0.0.1:1420` was reused. Each independent browser reviewer used its own browser context/session. Preview mutations affect sample stores; they do not establish native persistence or command execution. The dashboard preview and overlay preview are separate in-memory simulations; lack of cross-page state propagation there is not, by itself, a production defect.

Current WebKit screenshots (33 files) were copied to `output/audit-2026-10-25/webkit/`. Maya's initial and task screenshots/snapshots are under `output/audit-2026-10-25/blackbox*`. Additional seat evidence uses its seat prefix. These output files are local, gitignored evidence; the durable findings and probe results are kept with this report. No screenshot is a native desktop capture.

The full WebKit suite is more than a route smoke test: it includes meaningful interaction assertions. It still exercises `src/dashboard/api.ts`'s sample API, and cannot establish actual transport, native dialogs, notifications, file recovery, PTY lifecycle or agent integration semantics.

## Reproducible source probes

See [probes.mjs](probes.mjs) and [probe-results.json](probe-results.json). The script requires the Node 24 runtime used on this audit host, reads the real TypeScript modules, transforms copies under ignored output, and invokes pure functions. It does not modify product source or execute the commands supplied to `stillAsk`.

| Probe | Observed discrepancy | Confidence and consequence |
|---|---|---|
| TIME-1 | At 10:00 JST, `at 3 to call mum` becomes tomorrow 15:00, not today 15:00 | Executed parser discrepancy against its working-hours convention; save preview displays the incorrect interpretation and a user may accept it |
| TIME-2 | `2026-10-26T03:00` stays 03:00 through `parseWhen`, becomes 15:00 in `parseReminder` | Executed cross-entry inconsistency; unify exact-time handling |
| TIME-3 | `every Monday and Thursday at 9` becomes Monday-only weekly repeat, with the Thursday phrase in task text | Executed unsupported compound schedule accepted partially; reject or clarify unsupported recurrence instead |
| TIME-4 | Explicit old date moves forward by one day but remains in the past | Executed parser issue; new-reminder save guards prevent saving it, so do not claim a past reminder was actually persisted |
| TIME-5 | Weekly Monday snoozed to Tuesday, then completed, advances to following Tuesday | Executed recurrence function plus source trace of callers using mutated `due`; product must decide whether snooze changes the series |
| LANGUAGE | `meeting at 3`, `I have a meeting at 3`, `remember I shipped…` are unknown commands; supported `note for Ideas: …` is a note | Executed grammar boundaries; these are UX/expectation issues, not arbitrary AI routing |
| ACCESS | Several destructive variants are not recognized by `stillAsk` | Executed classification only; contradicts a blanket risky-command assurance, not evidence that a real destructive command ran |
| ACCESS-CLIP | A dangerous suffix is detected in the full string and missed in the production display-algorithm excerpt | Executed classifier contrast + source clipping trace; script separately reproduces the ASCII whitespace/truncate/ellipsis algorithm |
| DISPLAY-WHITESPACE | `echo "a  b"` displays as `echo "a b"` | Source-confirmed quoted-whitespace mutation; reproduced algorithm for ASCII fixture, not actual shell execution |

Maya's Chromium preview recorded a console error without diagnosing it. It is not counted as a confirmed product defect; the complete current WebKit check passed. Where a seat's report discusses historical captures, it labels that provenance. The chair also inspected current light Today and dark notebook WebKit screenshots.

## Not established by this audit

- Real customer demand, participant comprehension, retention, willingness to pay, or comparative task speed.
- Native VoiceOver, notification delivery while quit/locked/asleep, first-install permission denial and recovery, or notification click routing.
- Exact tab/session focus across Terminal, Ghostty, iTerm and Claude/Codex apps, or actual vendor-protocol compatibility on clean installations.
- Multi-monitor movement, full-screen Spaces, focus theft/click-through, screen-recording behavior, or all character states on actual desktop wallpapers.
- Signed/notarized download acceptance, Intel or older-macOS support, updating/rolling back with real data, or uninstall restoration.
- Current final-build CPU, memory, battery, long-session stability, execution descendant cleanup or crash recovery under OS faults.
- Absence of vulnerabilities. The security review is bounded source analysis and safe probes, not a full penetration test.

These are named release gates, not implied passes. The audit did not invoke a live Claude/Codex product CLI or spend quota to exercise Sidefolk's AI features.
