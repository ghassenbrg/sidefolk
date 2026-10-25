# Elena — principal engineer: technical release audit

Date: 25 October 2026. Seat: Elena, principal engineer, with architecture, reliability and security-boundary review. This is an expert review of the current implementation, not an interview study or a penetration test. No production code, global agent configuration, user data, permissions or live model calls were changed. No desktop capture was used. Other council reports were not consulted. Omar's independent review provides the dedicated security seat.

## Council decision

**Do not declare this a public, production-ready v1 yet. Keep the existing architecture and ship a narrower, dependable product after explicit release gates.** The code is a useful, relatively small foundation: domain modules, atomic file replacement, readable notes, optional AI, local commands, a real app window, and explicit installer confirmations are worth preserving. A rewrite would delay the real work: proving native behavior, making permissions truthful, preserving data on failures, and resolving integration promises.

The product currently offers a broader contract than its evidence supports. In particular, ordinary external Codex sessions do not have the lifecycle bridge implied by the Sessions screen; “risky commands still ask” is not a reliable property of the full-access implementation; and reminder recovery is not safe when a stored JSON file becomes unreadable. Green browser checks prove the preview flows, not the native transport or OS behaviors.

Suggested technical v1: one companion; reliable reminders; quick dated notes with Markdown portability; a restrained Today screen; optional Claude Code observation and permission handoff only after native verification; basic user-confirmed commands and session opening. Treat external Codex reach-user tools as a distinct, accurately labelled capability. Keep broad unattended execution, an embedded terminal, calendar integration, and AI summarization out of the initial public contract unless their additional gates are explicitly funded and passed. Existing work can remain behind deliberate feature switches during beta.

## Evidence and confidence

- **Confirmed, executable:** the real exported `stillAsk` function was imported with Node's TypeScript transformation and given strings only. No shell operation in those strings was executed. Ordinary destructive variants and a clipped dangerous suffix were missed, as detailed below.
- **Confirmed, source:** file and line citations describe paths present in current source. Findings about corruption, missing transport health, absent lifecycle wiring, and missing deadlines follow directly from those paths.
- **Requires native verification:** permission dialogs, notifications while quit/asleep, Spaces/focus/click-through, clean installation/uninstallation, signing/notarization, resource behavior and process-tree termination were not exercised by this council. The existing memory explicitly leaves native hand checks pending.
- **Parent's shared verification:** typecheck and 100 Vitest cases passed; 34 Rust cases passed and three opt-in tests remained ignored. The parent owns final WebKit/build results. These passing checks do not invalidate the source findings below.

## Priority findings

### T1 — P1: full-access safety wording exceeds the policy

The user intentionally authorizes session automation. That authorization is not the bug. The problem is the separate promise that risky commands still ask (`src/companion.ts:185–188`, `docs/GUIDE.md:69–71`). The implementation uses a short regex denylist (`src/access.ts:9–24`), then automatically approves anything it does not recognize (`src/companion.ts:174–180`).

Directly importing the real function produced:

| String given to the policy; never executed | Asks again? |
|---|---|
| `rm -rf /tmp/sidefolk-audit-only` | Yes |
| `git -C /tmp push --force` | No |
| `git clean -fd` | No |
| `rm --recursive /tmp/sidefolk-audit-only` | No |
| `find /tmp/sidefolk-audit-only -delete` | No |

This is not an exhaustive bypass list. It is enough to reject a safety guarantee based on recognizing shell text. The existing test even expects unflagged `rm notes.txt` to pass (`src/access.test.ts:9`). Non-command requests are deliberately allowed in full access (`src/access.ts:23`); that is broad authorization, not an independent privilege escalation.

There are also two different meanings of the same label. Starting a session with “Full access” chooses Claude auto mode or `codex -a never -s workspace-write` (`src-tauri/src/actions.rs:134–154`), while an existing session's toggle is Sidefolk's own frontend approval policy. They have different enforcement, lifetimes and risk properties. Neither should be described as a general OS security boundary.

**Release gate:** ship ask-first by default; use clear names for native agent modes versus Sidefolk automation. Prefer deferring high-impact approvals to the agent until there is a defensible, structured policy. If arbitrary session automation remains, explain its broad authority plainly, make revocation visible, and remove the guarantee that all risky actions will be intercepted. Regress the concrete variants above.

### T2 — P1: display truncation changes the approval decision

Claude command requests are clipped to 2,000 characters before becoming `PermissionAsk.detail` (`src-tauri/src/hooks.rs:25–26,146–153,286–309`). Codex approvals do the same (`src-tauri/src/codex.rs:335–354`). `handleAsk` feeds that display string into the full-access policy (`src/companion.ts:174–178`).

A 2,097-character string consisting of a long harmless `printf` argument followed by `; rm -rf /tmp/sidefolk-audit-only` returned `stillAsk=true` in full and `stillAsk=false` after the exact display-length clip. That is a real data-flow defect: the original operation and the approved presentation can differ. Manual permission review also lacks the complete command after the ellipsis. File approvals commonly show a path or a list of paths, without a content diff (`hooks.rs:150–151`, `codex.rs:344–354`).

**Release gate:** preserve the full, immutable operation separately from display excerpts; never classify an excerpt. Long or unrepresentable operations should require complete review or defer to the originating tool. State what is unknown when Sidefolk cannot present the change accurately. This matters even if the broader automation feature is deferred.

### T3 — P1: corrupted reminder data can be replaced with an empty collection

`Reminders::load` treats all read and parse failures as an empty list (`src-tauri/src/reminders.rs:97–107`). The next successful add writes that new list over `reminders.json` (`:158–161,232–234`). Therefore an unreadable or malformed existing file is indistinguishable from a new install and can be overwritten. Atomic writes protect against partial writes by this process; they do not solve corrupted input, disk/permission failures, incompatible future formats, or external edits.

Crew loading uses the same silent fallback (`src-tauri/src/crew.rs:9–13`). Saved actions similarly default to an empty list on any error (`src-tauri/src/actions.rs:242–244`) before mutations write it back (`:272–277,281–284`). Conversely, malformed settings abort startup (`src-tauri/src/settings.rs:98–103`, `src-tauri/src/main.rs:300–301,335–337`), leaving no in-app recovery route.

**Release gate:** distinguish missing data from damaged/unreadable data; preserve the original bytes; block destructive replacement while offering a clear recovery path. Maintain a last-known-good backup and explicit format/version handling. Test invalid JSON, unreadable files, disk-full writes, old-format migration, and restart after interrupted saves in an isolated directory. Do not introduce a database merely to address these manageable file-store issues.

### T4 — P1: external Codex monitoring is not implemented like Claude monitoring

The router accepts Claude event and permission hooks plus general MCP calls (`src-tauri/src/hooks.rs:32–36`). The Codex adapter emits lifecycle events for its own `codex app-server` threads (`src-tauri/src/codex.rs:131–163,261–324`), but starting a normal Codex session launches `codex` in a terminal (`src-tauri/src/actions.rs:138–150`). There is no corresponding external Codex event transport in this code. The MCP tools provide notify/ask/remind/spark/presence (`src-tauri/src/mcp.rs:35–87`); they are not automatic working/finished/session-discovery signals. The local command parser no longer exposes ordinary Codex dispatch (`src/commands.ts:7–30,57–101`), even though the old backend adapter remains.

Thus “Sessions appear here as soon as Claude Code or Codex starts working” (`src/dashboard/sessions.ts:35–36`) and setup's general “follow work sessions and review requests” (`src/dashboard/setup.ts:49`) are too broad. A Codex user can launch work successfully and still receive no automatic tracked session or completion. The configured MCP server's mere presence does not prove session observation.

**Release gate:** publish an actual capability matrix: Claude event observation/permission handoff; Codex reach-user tools; any Sidefolk-owned Codex execution. Either implement and test the missing lifecycle bridge, or narrow the UI and marketing claim. Verify launch → activity → permission → completion → reopen with real sessions on supported CLI versions. Do not let browser sample sessions stand in for these checks.

### T5 — P1: connection state represents configuration, not a healthy connection

The loopback server binds one fixed port. Failure only prints to stderr and leaves the app running (`src-tauri/src/hooks.rs:44–50`). Settings calls integrations “connected” by reading configuration (`src-tauri/src/prefs.rs:197–204`); MCP detection checks a server-name entry/header, not whether it points to this installed binary or works (`src-tauri/src/mcp_setup.rs:52–60`). The installer registers the current executable's path (`:92–95`), which may later move. A second instance or occupied port is not handled as an explicit user state. These create credible “connected, but nothing happens” failures without a repair affordance.

**Release gate:** surface transport startup status; enforce a single application instance or deliberate ownership; distinguish configured / reachable / recently seen / incompatible / repair needed. Check the installed binary path and provide a safe reconnect flow after moving or upgrading the app. Preserve the existing confirmation and backup behavior.

### T6 — P1 for broad release: native reliability and distribution remain unproven

`docs/RELEASE.md` explicitly says signing, notarization and auto-update have not been completed. The updater plugin is not present (`docs/RELEASE.md:40–53`; `src-tauri/Cargo.toml`). `scripts/release.sh:23–27` skips the WebKit gate if the preview is absent rather than enforcing its advertised “every check” release contract. There is no `.github` CI directory. Browser tests run the sample API (`src/dashboard/api.ts:6–9,68–80`; `scripts/webkit-check.mjs:5,40–58`).

Distribution metadata is inconsistent: README requires macOS 14+ (`README.md:15`), while the app declares 13.0 (`src-tauri/tauri.conf.json:51`). Calendar code directly invokes `requestFullAccessToEventsWithCompletion` without an older-OS availability branch (`src-tauri/src/calendar.rs:83–94`). This combination requires a real minimum-OS decision and validation; no crash on macOS 13 was reproduced here. README still promises a five-step setup (`README.md:48`), while the implementation has three (`src/dashboard/setup.ts:9–10`). App descriptions still call the sprite-based product “3D desktop pets” (`tauri.conf.json:54–55`), although current character rendering is image frames (memory decision 38).

**Release gate:** decide the supported macOS versions and CPU architectures, build the matching signed and notarized deliverables, and test a clean install on those systems. Complete quit/sleep/wake notifications, Automation permission denial/recovery, session opening, multi-monitor/Spaces/click-through, startup and uninstall checks. Make release checks non-skippable in a deterministic script or CI. A signed manual-update beta is acceptable if it is explicit; an updater is not a prerequisite for a small private beta, but a reliable versioned update path is required before ongoing public support.

### T7 — P2, elevate if retained in v1: execution needs a visible lifecycle

Saved background actions have a ten-minute deadline and kill-on-drop shell, which is a useful starting point (`src-tauri/src/actions.rs:315–333`). They have no user-facing cancellation handle or run identity, output grows without a size limit, and a run uses the same sanitized name for its log file. Concurrent runs of the same action overwrite/share output. There is no explicit process-group teardown, so the promise that a timeout “stopped it” needs descendant-process tests; no orphaning was reproduced here.

AI notebook drafting blocks on `wait_with_output` without a timeout or cancellation, and temporary cleanup is only on the ordinary success/failure return path (`src-tauri/src/notes.rs:293–320`). Codex JSON-RPC requests await indefinitely if the process remains alive but never replies (`src-tauri/src/codex.rs:220–225`). The latter adapter is largely legacy surface in the current normal UI, so prioritize it according to whether it stays.

The embedded PTY has reasonable per-terminal output retention, but the count of terminal instances is unbounded (`src-tauri/src/inside.rs:18–35,78–109`). Closing a terminal kills its direct shell, and app shutdown has no explicit confirmation/terminal cleanup in its RunEvent handler (`inside.rs:170–175`; `main.rs:338–345`). Whether descendants stop cleanly, and what users lose on quit, need native tests. A PTY smoke test does not establish a robust terminal product (`inside.rs:182–194`).

**Recommendation:** keep visible, user-confirmed external-terminal actions. Defer background execution, embedded terminals and AI drafts from the public v1 contract, or add bounded output, run history, stop controls, deadlines, concurrency limits, process-tree cleanup, and clear quit behavior before including them. Do not silently break installed users' existing workflows during a beta scope reduction.

### T8 — P2: tighten privacy promises and timeout semantics

Good: the MCP endpoint requires a random per-install token, rejects browser Origin headers and compares tokens without early byte exit (`src-tauri/src/mcp.rs:96–114,236–243`). Hook endpoints reject Origin and non-JSON content types and bind loopback (`hooks.rs:44,55–68`). The CSP restricts script/resource origins (`tauri.conf.json:34–35`); most user text enters via text nodes. Config installers ask first, back up bytes, preserve unrelated hook settings, and detect a change during the confirmation (`claude_setup.rs:146–167`; `mcp_setup.rs:83–106,142–169`). These are foundations to retain.

Trust limits: Claude hook messages are unauthenticated local assertions, including session ID and folder; possession of local execution is not a remote exploit and no such exploit was found. Nevertheless, do not present a claimed session name as a cryptographically authenticated sender. Unifying hook authentication during a compatible installer upgrade is a sensible hardening step. MCP's token is per install, not a distinct permission grant per tool/session.

The journal stores prompts, outcomes and permission details for thirty days (`src-tauri/src/journal.rs:1–3,16–25`; `hooks.rs:290`). Logs and config backups can contain sensitive paths, command fragments and secrets. “Copy report” includes raw recent error lines (`src-tauri/src/prefs.rs:244–248`), while UI and guide promise it will “never” contain notes or names (`src/dashboard/settings.ts:293`; `docs/GUIDE.md:84–85`). Arbitrary exception reasons are logged (`src/dashboard/app.ts:293–295`, `src/main.ts:26–28`). The literal guarantee is not established by redaction. AI drafting is explicitly labelled and disclosed before sending notes (`src/dashboard/notes.ts:374–376`), which is good; Codex's read-only filesystem mode is not a tools-off isolation contract (`notes.rs:300–301`).

MCP question timeout returns success text telling the agent to “Decide yourself or ask again later” (`mcp.rs:304–308`). That is not user authorization. Give callers an explicit no-answer/timed-out result and remove language that could be confused with permission. No downstream unauthorized operation was tested or alleged.

**Release gate:** document what is saved and for how long, how to remove it, and exactly when notes leave the machine; preview/redact copied reports; audit backup/log permissions and retention. Add a reversible disconnect/remove-CLI/uninstall guide. Token rotation, per-session tool policy and custom IPC least privilege are appropriate follow-ups, not evidence of an existing remote compromise.

## Feature disposition for v1

| Capability | Council vote | Acceptance condition |
|---|---|---|
| Companion, existing frame renderer, local state modules | Keep | Native input/focus/Spaces and resource checks; optional sound; reliable way to summon/hide |
| Reminders, repeat/snooze/history | Keep, harden first | Corruption recovery; exact recurrence semantics; sleep/quit/wake/denied-notification matrix |
| Dated notebooks and Markdown portability | Keep | Save errors visible; preserve text; recovery/export works; no AI dependency |
| Claude observation and ask-first handoff | Keep as optional beta capability, graduate after proof | Real supported-CLI end-to-end tests, accurate expiry and connection health, full operation review |
| Codex MCP reach-user tools | Keep with accurate separate labelling | Real MCP handshake/tools and no-answer semantics; no implied automatic observation |
| Codex general session observation | Rework or defer claim | An implemented, tested lifecycle source, not sample data |
| Full access / unattended approvals | Defer broad promise | Truthful scope, raw operation handling, revocation, one coherent policy model |
| External-terminal confirmed commands/session opening | Keep as advanced | Launch result and permission denial/recovery verified on supported terminals |
| Saved background actions | Defer or complete lifecycle | Stop, unique run/log IDs, limits, process-tree tests |
| Embedded terminal | Defer public promise | Quit/close/loss semantics, process lifecycle and input/output correctness tested |
| AI summary drafts | Optional later | Explicit transfer/quota consent already useful; add cancel/deadline/isolation and cleanup |
| Calendar, briefs, weekly wins | Defer until core trusted | Minimum-OS gate, opt-in permissions, false-positive and nuisance controls |
| Custom character importer/exporter | Advanced beta, not launch-critical | Bounded decoded dimensions/memory, invalid images, no-overwrite exports, repair path |

## Roadmap and measurable release gates

**Gate A — settle the release contract, before more features.** Choose one capability matrix, supported macOS/architectures, and named beta scope. Reconcile app/UI/help wording with it. Explicitly separate installed configuration from live health and Sidefolk permissions from native agent modes. Decide which existing advanced features are experimental rather than deleting them reflexively.

**Gate B — trust and data integrity.** Fix T1/T2/T3; preserve corrupt files and make recovery understandable. Exercise dangerous-string classification without execution. Confirm expired, cancelled and disconnected approvals cannot become a new allow. Persist enough authoritative request state in Rust to avoid treating the overlay's current DOM as the sole source of truth. Any rewrite should be limited to this boundary, not the entire product.

**Gate C — native core matrix.** On a signed, built app with isolated data: first launch, restart, denied notification permission, reminders while running/hidden/quit/asleep/locked; timezone and daylight-saving changes; repeat completion and overdue reminders; multi-monitor and Spaces; keyboard-only operation; Automation denial then recovery; real Claude/Codex capabilities according to the matrix; missing/uninstalled/upgraded CLI; occupied hook port; corrupted files; app quit during in-flight work. Record actual outcomes and exact supported versions. A manual check may be appropriate; it must be recorded, repeatable and distinguish failures from tests not run.

**Gate D — distribution/support.** Signing and notarization succeed; Gatekeeper accepts the downloaded artifact; minimum OS is correct; update/reinstall preserves data and integrations; uninstall disconnects safely without erasing unrelated settings. Release checks fail if a required check is unavailable. Offer a previewable, redacted report and an actionable recovery guide. CPU/RAM claims come from the final unlocked release build, not stale memory measurements.

**Gate E — real beta learning.** Have several people use their own machines and tasks for a week, including a nontechnical user and a developer who did not build Sidefolk. Predeclare success criteria: they create and receive a reminder unaided, recover a hidden companion, find/edit/export a note, explain any AI integration they enable, and revoke access. Log every missed reminder, lost input, stuck approval, unexpected quota use and repair requiring the developer. Any missed core reminder or lost persisted data blocks graduation until explained and fixed. A simulated expert council cannot substitute for this gate.

Sequence these gates by outcome, not an invented date estimate. The strongest engineering move is to freeze expansion and close the trust gaps. Preserve the functioning modules; replace narrow authority/lifecycle boundaries where evidence warrants it. There is no evidence here supporting a ground-up rewrite.
