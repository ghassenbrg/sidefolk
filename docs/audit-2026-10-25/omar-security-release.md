# Omar — security and release

Independent source audit, 25 October 2026. No other council reports were read before this conclusion. Scope: loopback transport, approval authority, local execution, AI drafting, private storage, installers and distribution. No live model calls, global configuration changes, user-data reads, desktop screenshots or implementation changes were made.

## Verdict

**Do not distribute the current artifact as a general-purpose assistant with reliable destructive-action safeguards or notebook-only AI access.** A tightly scoped, signed macOS beta is plausible after the gates below, or by excluding the affected execution features. I found a confirmed approval-fidelity defect and several source-level gaps between user promises and enforcement. I did **not** establish a remote-code-execution path from an ordinary website.

The coordinator supplied passing typecheck, 100 Vitest tests, 34 Rust tests with three intentionally ignored, WebKit sample flows and a successful 9.27 MiB release build. Those are useful regression evidence, not independent proof of native permissions, subprocess termination, notebook isolation or distribution acceptance. Its artifact inspection found an ad-hoc ARM64 signature without a TeamIdentifier; I did not reproduce a signed distribution run.

## Strongest existing defenses

The HTTP listener binds specifically to `127.0.0.1` (`src-tauri/src/hooks.rs:44`). Both hooks and MCP reject any Origin header; hooks require JSON, and no CORS permission is added (`hooks.rs:55–68`, `mcp.rs:236–245`). Development control endpoints compile only in debug builds (`hooks.rs:37–42`). MCP uses a freshly generated 192-bit token, a constant-work equal-length comparison and private atomic creation (`mcp.rs:97–113`, `settings.rs:143–156`). This is a meaningful browser-to-local-service boundary.

There is an inherited body bound: the locked Axum `Bytes` extractor calls `into_limited_body`, whose default is 2,097,152 bytes (local dependency `axum-core-0.5.6`, `extract/request_parts.rs:107`, `ext_traits/request.rs:319–326`). Absence of an explicit application limit is **not** an unlimited-body vulnerability. Concurrent requests and pending-state counts remain unbounded.

Agent text uses text nodes (`src/dashboard/dom.ts:11–21`); the packaged CSP restricts scripts and connections to local content/IPC (`src-tauri/tauri.conf.json:35`). Session IDs are restricted before interpolation and folders are quoted (`sessions.rs:219`, `sessions.rs:265–287`). User-authored shell commands deliberately execute shell syntax; treating that capability itself as injection would misstate the product.

Hook installation is unusually careful: native confirmation, byte-for-byte private backups, validation of config shape, preservation of existing symlinks, comparison against the pre-dialog snapshot, and removal of only recognized handlers (`claude_setup.rs:112–167`, `claude_setup.rs:225–260`). MCP changes also require native confirmation and backup, then use the agent's CLI (`mcp_setup.rs:83–106`, `mcp_setup.rs:142–173`).

## Attack boundaries

| Boundary | Current authority | Assessment |
|---|---|---|
| Website → loopback | Origin refused; hooks require JSON; no CORS | Strong ordinary browser defense; no remote exploit demonstrated. |
| Local process → hooks | No token; caller supplies session/folder | Explicit trust decision in memory/DECISIONS.md §21. Forgery/spam is possible locally; this is not authenticated agent identity. |
| MCP shim → app | Private bearer token, clipped fields, timeout | Protects API access from callers lacking the token; not an isolation boundary against same-user agents that can read it. |
| Agent request → approval | Agent describes intent; frontend decides full access | Confirmed loss of relevant command content before consent and risk checking. |
| Packaged frontend → native commands | Trusted renderer can resolve approvals/run commands | CSP/text rendering matter. No independent backend capability bound to a specific reviewed payload. No XSS established. |
| Shell/CLI → host | User account plus the selected CLI's sandbox | Broad authority is intentional; ownership, cancellation and privacy promises need stronger enforcement. |
| Publisher → installed app | Developer ID/notarization planned; updater absent | Distribution readiness remains unproved; no automatic update supply chain is currently active. |

Loopback is shared across OS users. The unauthenticated hook endpoint also lacks protection against another local account forging activity or prebinding the fixed port. Adding a hook credential requires a migration and does not alone authenticate a replacement server to the client. Address this when claiming hostile-local-process resistance; do not advertise that property for this beta. Surface bind failure to the user (`hooks.rs:50`) instead of leaving apparently connected integrations silent.

## Five release gates

### 1. Preserve the approval payload and narrow the full-access promise — high, confirmed

Claude Bash commands are clipped at 2,000 characters (`hooks.rs:149`); Codex commands and file-change descriptions are similarly clipped (`codex.rs:339–354`). The shared `clip` function also collapses whitespace, including within shell quotes (`bus.rs:188–195`). The frontend performs `stillAsk` on this already changed `ask.detail`, then auto-allows the request (`src/companion.ts:174–179`). Thus both manual review and full-access checks lose the actual operation's meaningful suffix. The dashboard's Copy action cannot recover information the backend discarded (`src/dashboard/requests.ts:90`).

Pure string probes against the real exported `stillAsk` confirmed: a literal destructive suffix asks; the same suffix beyond a 2,050-character harmless prefix does not ask after the production clipping algorithm. Long-option deletion and `git -C … reset --hard` variants also return no reason to ask (`src/access.ts:9–24`). Nothing was executed. Even quoted double spaces are changed by `clip`.

Broad session authorization is an intentional feature. The defect is the contradictory promise “Risky commands still ask” (`companion.ts:188`), plus incomplete ordinary consent. Preserve raw immutable command/input and a separate summary. Render the complete payload with safe wrapping/scrolling; defer or deny requests that cannot be completely reviewed. Evaluate policy on the original data in Rust, bound to the pending request. For v1, disable Sidefolk's automatic approval, or explicitly explain genuinely unrestricted session authority. Expanding a regex denylist cannot reliably classify arbitrary shell programs. File approvals should expose available diffs/input, rather than only filenames (`hooks.rs:150–151`).

### 2. Own and verify subprocess shutdown — high for execution features

Quiet actions launch a shell and use `kill_on_drop(true)` with a ten-minute wait (`actions.rs:318–333`). There is no process-group management, descendant tracking, explicit kill-and-wait, or user cancellation. On timeout the message says the work was stopped before termination is verified. Detached children can outlive an immediate shell; this is a source-level lifecycle gap, not proof that every action survives.

PTY Close similarly removes the terminal and ignores the shell kill result (`inside.rs:170–175`); its reader retains the terminal state until EOF (`inside.rs:80–108`). The locked portable-pty implementation signals the shell PID, then may kill that PID, rather than the process group. The UI promises everything stops (`src/dashboard/terminal.ts:112`). App exit has no explicit terminal cleanup handler (`main.rs:338–345`). AI drafting waits without a timeout/cancel path and buffers output (`notes.rs:304–315`).

Introduce explicit run ownership, cancellation, bounded output, termination escalation and reaping. Confirm surviving children with harmless native fixtures before promising “stopped.” Until then, omit quiet execution and embedded terminals from the beta, or remove unsupported stop guarantees and disclose surviving-work risk. Normal process shutdown must remain usable when a CLI stalls.

### 3. Enforce the notebook privacy boundary — high before AI drafting

The draft panel promises it sends the notebook's notes “and nothing else” (`src/dashboard/notes.ts:375`). Sidefolk constructs that prompt, which is good. But an empty working directory plus Codex `-s read-only` (`notes.rs:295–306`) does not establish notebook-only read access or remove inherited user configuration and integrations. OpenAI's [approval and security documentation](https://learn.chatgpt.com/docs/agent-approvals-security) explicitly describes read-only mode as able to read files and run commands. Read-only controls mutation; it is not proof of prompt-only data access.

No additional read/exfiltration was demonstrated, and Claude's tool-disabling flags offer a stronger starting point. The gate is an unenforced confidentiality claim, especially when notebook text contains hostile instructions. Use a verified tool-free, nonpersistent adapter for each supported CLI, isolate integrations without changing the user's global config, and constrain/cancel the process. Test with synthetic out-of-notebook canaries and no network secrets. If that cannot be established, hide the feature for v1; a vague privacy disclaimer does not make the existing claim true. Guarantee temp cleanup on all errors, not only the successful wait path (`notes.rs:296–315`).

### 4. Make local logs private, bounded and reviewable — medium/high privacy gate

Journal creation requests mode 0600 (`journal.rs:75–81`), and atomic notebook/config writes do likewise. Quiet action logs instead use `File::create`, and error logs use ordinary create/append (`actions.rs:313–316`, `prefs.rs:313–321`). Under this environment's ordinary umask, an isolated synthetic example produced 0644 files and 0755 directories. Actual cross-account readability depends on ancestor permissions; I did not read user files or prove another account accessed anything.

Quiet logs have no size/retention bound. Error logs rotate, but raw error text and panic data flow into Copy report without redaction (`prefs.rs:234–258`, `prefs.rs:327–337`). The UI's “never your reminders, notes or names” promise is therefore unsupported if an error includes such data (`src/dashboard/settings.ts:293`). Journal commands/prompts can also contain secrets (`hooks.rs:96`, `hooks.rs:290`); pruning runs at journal open, not periodically (`journal.rs:61`, `journal.rs:99`).

Create private data/log directories, force sensitive file permissions, cap/rotate action output, publish retention rules and provide deletion. Preview reports before copying; either redact sensitive fields consistently or replace the absolute exclusion promise. Same-user malware remains outside this storage protection boundary.

### 5. Ship a verified distribution and recovery path — blocking for external release

The release script checks credentials and invokes signed bundling plus `spctl` (`scripts/release.sh:11–34`), but silently skips WebKit if no preview is listening. Make release checks fail closed or record an explicit waiver. The present artifact's ad-hoc signature is local-build evidence only. [Tauri's macOS signing guidance](https://v2.tauri.app/distribute/sign/macos/) distinguishes Developer ID/notarization from ad-hoc signing and its remaining installation warnings.

Require a pinned source revision, locked dependency installation, archived hashes, verified Developer ID identity/hardened runtime, notarization ticket/staple and a fresh quarantined-machine launch. Declare ARM64-only support until Intel has evidence. No updater plugin, endpoint or public key is installed (`Cargo.toml`, `tauri.conf.json`, `docs/RELEASE.md:42–53`). That is a defensible v1 scope choice: publish an honest manual update and rollback procedure. If an updater is added, verify signatures, tampered artifacts and key recovery; [Tauri requires update signatures](https://v2.tauri.app/plugin/updater/), separately from Apple signing.

## Scope and acceptance

Recommend v1 as a signed local companion with reminders, notebooks, observable sessions and explicit complete request review. Keep broad agent autonomy, notebook AI, quiet jobs and embedded terminals behind separate acceptance gates. Do not add background model calls or an updater merely to expand the checklist.

Before approval, record these acceptance results:

- **Transport/authority:** reject Origin requests, missing/wrong MCP token and oversized bodies; verify no release `/dev/*`; test hidden suffixes, quoted whitespace, simultaneous requests, expiry, duplicate/stale answers and restart/session authority. Lower body limits and queue caps are useful hardening.
- **Privacy:** synthetic secrets in prompts, errors, notes and job output; verify private file modes, retention/deletion, report preview and notebook canary isolation. No live personal data needed.
- **Execution/recovery:** harmless child/grandchild fixtures through cancel, timeout, PTY Close and app Quit; verify no survivors, reaped processes, bounded output and useful errors after failure.
- **Configuration:** temp Claude/Codex homes; cancel/install/reinstall/remove, malformed config, symlink and concurrent edit; compare exact backups. Restore unrelated settings after CLI failure. Document restoring the original absent-file state as well as bytes.
- **Install/update:** inspect an existing `/usr/local/bin/sidefolk` before replacement; current `ln -sf` has no destination backup or uninstall counterpart (`actions.rs:357`). Document safe CLI/login-item/hook/MCP removal, preserve user notebooks, test previous-version rollback and deliver a fresh-machine signed-build receipt.

Native permissions, the real CLI/version combinations, process cleanup and Gatekeeper remain acceptance work, not confirmed failures. The approval string probes and permission-default example above are the only additional dynamic checks in this seat.
