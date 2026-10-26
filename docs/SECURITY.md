# Sidefolk Security Model (V1)


## 1. Scope

**Assets:** notebook, memories, history, granted folders, Keychain secrets, the user's AI quota
and attention, and the Mac itself (code execution, persistence).
**In scope:** authors of anything Sidefolk reads (web, files, clipboard, drops, repos an external
agent works in); malicious extensions or MCP servers; prompt-injected external agents; other
local users; malicious dependencies.
**Out of scope:** same-uid malware, root, physical access. Sidefolk must still never become an
escalation or persistence vehicle for *less* privileged code (a sandboxed extension, an injected
model).
**Trust:** caller trust runs user (UI/slash) > agent > routine > external client > extension.
Content trust is separate: anything the user did not type is untrusted.

## 2. Threats and mitigations

Each entry gives likelihood/impact, the V1 mitigation, and the residual risk.

### A. Agent and tools

**T1 Arbitrary tool execution (H/H).** `ToolExecutor` is the only path. Inputs are validated
against the tool's JSON Schema before `Guard` (`InputSchema`: types, `enum`, bounds, unknown keys
under `additionalProperties:false`, string and list caps, 1 MiB per call); messages are written so
the model can fix its call. Each caller sees only the tools it may use. Risk floors: exec = high;
file writes, custom-scheme open and network to a model-built URL = at least medium (a URL counts
as user-given only when it, or for opening a link its site, appears in the user's own message:
`UserMentions`); manifest risk can raise but never lower them.
Approval cards render the tool's deterministic `summary(input)` and raw args (full URL, absolute
path, verbatim command), never model prose. Approval is bound to `SHA-256(tool, canonical args)`
and re-checked at execution. Allow is inert for 800 ms, Return never defaults to Allow on high,
timeout 120 s → deny for every caller, and a run's cards are denied when the run ends (or its
socket connection drops), so a late Allow never acts for a caller that is gone. Other agents
share one pending card: while it waits, their further requests are refused at once (their names
are self-chosen, so a per-name limit would be none). "Always" grants are never given for high
risk or to external callers, are scoped by caller kind, revocable, and expire after 90 days
unused. A site grant never covers a URL with a query or fragment. *Residual:* the user approves
without reading.

**T2 Prompt injection (H/H).** Sources: web pages, watcher payloads, files, clipboard, drops,
command output, extension and MCP results *and tool descriptions*, Apple Notes and Reminders (every
`applenotes.*` and `applereminders.list` result, titles and folder names included), notes, memories, reminders and
watchers written by external agents (or by Sidefolk's agent in a tainted turn). Every `ToolResult`
carries `untrusted`; a list or read that quotes anyone else's words sets it (`reminders.*` and
`watch.*` when a title isn't user-sourced, notes, and `collections.list`, `notes.*` when a quoted
collection name isn't). Taint is sticky for the turn (or routine run) and
set only by code. While tainted, all medium/high calls ask (grants ignored), and so do clipboard
writes and memory/skill/routine creation. Network and open calls ask (medium) whenever their
normalized URL is not in the user's message for this run, tainted or not; a typed URL runs even
while tainted, and opening a site the user named runs in a clean turn (`UserMentions`: scheme,
`www.`, default port and a trailing slash don't matter; query and fragment do). Addresses on this
Mac or the local network get no card: fetching and watching refuse them for everyone but the
user, and opening one in the browser sends nothing beyond the LAN. External
agents follow T4 instead (their own context and network are already theirs). Extension and MCP
tool descriptions never reach the model: it gets a neutral line built from the tool title and
extension name, and the schema without its free text (descriptions stay on the install sheet).
Untrusted text is wrapped as `<untrusted source=…>` (closing tag escaped), stripped of invisible
and bidi characters (U+200B–200F, 202A–202E, 2060–2069, FEFF, E0000–E007F) and capped at 20 KB.
That is hygiene, not a boundary. Rendered Markdown never loads remote images; links show the full
host. *Residual:* injection can still steer low-risk actions; extension tool names and titles
(≤ 60 characters) still reach the model.

**T3 Persistent injection (M/H).** Items, collections, memories, reminders, watchers, skills and
routines record `source` (`user | user:agent | agent | external:<client> | extension:<id>`;
watchers made by a routine keep `routine:<id>`; notes copied from Apple Notes record `app:notes`
whoever asked, D38): Sidefolk's agent records `user:agent` in a clean turn and plain `agent` in a
tainted one (`ToolContext.provenanceTag`). Collections named before
their source was recorded count as the user's. The context builder auto-includes only user-sourced
notes and memories and places a note by its collection's name only when the user named it, and
"Right now" quotes only user-sourced reminder and watcher titles; the rest are counted. Job titles
(command lines from the socket) are counted, and agent sessions show only a known agent name and
state, never the folder or title from a hook payload. Others arrive through explicit search or
lists, which taint the turn. Memories, skills and routines created by non-user callers or in
tainted turns need approval showing the full text.

**T4 Confused deputy via external MCP clients (H/H).** An agent in a hostile repo uses Sidefolk's
folder grants, network or commands to escape its own sandbox. The `.external` profile allows,
without asking: `notes.save` (Inbox or a collection that already exists, tagged; they never create
a collection), `reminders.create` (at most `attention`, 20 active per client and 50 for all clients
together), notify/`ask_user`, `status`, and non-command watchers (10 active for all clients
together, each stopping after 24 h; `WatcherEngine.add` counts and inserts in one actor step, so
parallel calls can't overshoot).
Reading user data (notes, memories, reminders) asks, with an optional per-client grant that is off
by default. Files, clipboard, open, web fetch, command watchers, skills, settings and extensions
are not exposed. Clients pair during one-click connect (per-client key, after confirmation and
backup). That gives revocation and quotas, not a boundary against same-uid code. Names are shown
as unverified. Rate limits: 60 calls/min and 4 concurrent per connection, 120 calls/min for all
external clients together, and 600 session/job/status messages a minute for the whole socket.
External callers can never answer approvals. E9 ("ping me when tests pass") needs only notify or a
process-exit watcher, not command watchers.

`sidefolk run -- <cmd>` (D12) must exec the command itself, in the caller's process and sandbox,
and only report start and exit over the socket; the app never runs it. Claude Code hook payloads
(D12) are untrusted input: they are parsed with size caps, the hooks fail open, and they never
block or slow the session. Their host app (`host_pid`, `host_bundle_id`, what "Open" brings to the
front) is self-reported, so `HostTrust` keeps a pid only when it is an ancestor of the connection's
`LOCAL_PEERPID` (checked while the sender waits for its reply) and then reads the bundle id from that
process; otherwise only a well-known terminal or editor bundle id is kept, and nothing else is
focused. "Open" uses a stored pid only while it still runs that app (pids get reused).

*Residual:* data the user lets an agent read goes to that agent's provider. Same-uid code can
still name its own ancestor, or a known terminal, as a session's host.

**T5 Tool loops (M/M).** 10 steps / 120 s, 25 calls per turn. A third identical call (tool + args)
stops the run. Routines get a daily run and token budget.

### B. Local interfaces

**T6 Unix socket (M/H).**
- Refuse paths over 103 bytes (`sun_path`).
- `mkdir(run, 0700)`, then `lstat`: must be a real directory owned by `getuid()` with
  `mode & 077 == 0`, otherwise refuse.
- Stale socket: must be `S_IFSOCK` and owned by the user. If `connect` succeeds, another instance
  is live: focus it and exit. On `ECONNREFUSED`, unlink.
- `umask(0o077)` at launch, before any threads, so the socket is created 0600; `chmod` again after
  bind. Children (command watchers, extensions, the brain) get the usual 022: `posix_spawn` has no
  umask attribute, so `SpawnLock.spawn` lowers it for the spawn call itself, under the spawn lock.
  Sidefolk's own files use explicit modes inside 0700 folders, so that instant widens nothing.
- On accept: `getsockopt(SOL_LOCAL, LOCAL_PEERCRED)` must show `cr_uid == getuid()`. PIDs are for
  logs only (they get reused).
- Brain token: 32 bytes from `SecRandomCopyBytes`, delivered to the bridge in a 0600 file under
  `brain/run-<id>/`, never in argv, prompts or logs. It is valid only while the run is active,
  binds to the first connection, and is compared with `timingsafe_bcmp`. No token → `.external`;
  bad or expired token → disconnect. No message can produce `Caller.user`.
- JSON lines ≤ 1 MiB, ≤ 8 connections, versioned `hello` first, 10 min idle timeout.
- The bridge checks run-dir ownership and mode and the server's peer uid before sending.

*Residual:* same-uid code can steal a token and gets agent trust, never user trust.

**T7 Claude Code brain (M/H).** `--tools ""` removes the built-in tools, but hooks are lifecycle
commands, not tools. User or project settings can still run hooks that see and inject context,
load plugins, MCP servers, skills or `CLAUDE.md`, and set `env` (`ANTHROPIC_BASE_URL`).
Mitigations:
- Resolve `claude` from fixed locations (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`).
  It must be owned by the user or root and not group/world-writable. Show the path in Settings.
- Probe `--version` and `--help` and fail closed if the isolation flags are missing.
- Argv: `-p --input-format stream-json --output-format stream-json --tools "" --strict-mcp-config
  --mcp-config <0600 file> --disable-slash-commands --no-session-persistence
  --permission-prompts none --allowedTools mcp__sidefolk`, plus `--restricted` (or
  `--setting-sources` with no file sources) so user, project and local settings are ignored.
  `--bare` also skips hooks and `CLAUDE.md` but disables OAuth, so subscriptions cannot use it
  *(verified, help text)*.
- The prompt goes over stdin: every process's argv is visible to other local users through `ps`
  *(verified)*.
- Env allow-list: `HOME USER LOGNAME LANG`, `TMPDIR` per run, fixed `PATH`. Never `DYLD_*`,
  `NODE_OPTIONS` or `ANTHROPIC_*`. cwd is a fresh empty 0700 run dir.
- Self-check on every run: if the `system/init` event lists a tool not prefixed
  `mcp__sidefolk__` or any MCP server other than `sidefolk`, kill the process group and disable
  the backend.
- Canary test (ignored by default, one tiny call, rerun whenever the CLI version changes): plant a
  hook, `.mcp.json` and `CLAUDE.md` in the run dir and its parent, and assert none take effect.

*Residual:* managed (enterprise) settings and hooks always apply, by design; CLI semantics can
drift between versions.

**T7 Codex brain (M/H).** The same threat as Claude Code above, with a CLI that has more of its own. Codex has its own shell, file edits (`apply_patch`), web search, browser
and computer use, image generation, sub-agents, hooks, plugins, apps, skills, `AGENTS.md` and
execpolicy rules, and it doesn't report its tool list in its event stream. Mitigations (each switch
verified against codex-cli 0.160.0 by recording the requests it sends to a stand-in Responses
server, so no quota was spent):
- Resolve `codex` like `claude` (settings path, then `~/.local/bin`, `~/.codex/bin`, Homebrew,
  `/usr/local/bin`, npm/Volta/Bun/pnpm/nvm folders, then the app's PATH); the binary must pass the
  same ownership checks and its folder (and a link's target folder) must not be writable by others.
- Probe `--version`, `exec --help` (every flag below must be listed) and `features list` (every
  feature Sidefolk switches off must exist): otherwise fail closed. `codex login status` must say
  signed in before a run (signed out, `exec` retries for 20 s).
- Argv: `exec --json --strict-config --ephemeral --skip-git-repo-check --ignore-user-config
  --ignore-rules --sandbox read-only --cd <run dir>`, `-c approval_policy="never"`,
  `-c web_search="disabled"`, `-c project_doc_max_bytes=0`, skills, environment, permission, app and
  collaboration instructions off, `request_user_input` off, `history.persistence="none"`, and
  `--disable` for every feature that is on by default except the plumbing the brain needs
  (`code_mode_host`, which runs the sandboxed JavaScript newer models call tools from, retries,
  compression, MCP sign-in prompts). Features a later Codex adds are switched off too.
  `--strict-config` makes a renamed key an error instead of a silently ignored one.
- Exactly one MCP server via `-c mcp_servers.sidefolk.*`: the `sidefolk mcp` helper with the run
  folder (token file) and `SIDEFOLK_HOME` in its env, `required = true`,
  `default_tools_approval_mode = "approve"` (Guard decides; with approvals off Codex would refuse
  every call). The user's own `[mcp_servers]` are never loaded (`--ignore-user-config`).
- The system prompt goes into a 0600 `instructions.md` used as `model_instructions_file` (it replaces
  Codex's coding-agent instructions); the conversation goes over stdin. Never argv.
- Env allow-list as above, plus `CODEX_HOME` only when Sidefolk itself has one; never
  `OPENAI_API_KEY` (the plan is the point).
- Self-check on every event: messages, reasoning, plans, warnings and `mcp_tool_call` on server
  `sidefolk` are allowed. A `command_execution`, `file_change`, `web_search` or another server's
  tool kills the process group and disables the backend until restart (the switches failed);
  `collab_tool_call` (some models always get sub-agent tools) or an item type Sidefolk doesn't know
  kills the run. T5 limits (25 calls, 3 identical) apply.

*Residual:* Codex always adds the user's global `$CODEX_HOME/AGENTS.md` (there is no switch; the
brain is told it doesn't apply). `apply_patch` stays offered to Codex's own models; the read-only
sandbox with approvals off rejects every write (verified), and a `file_change` event stops the run.
Models with sub-agent tools can try to use them; the run stops. Codex still writes its own state
(SQLite indexes, logs) in `CODEX_HOME`, but `--ephemeral` keeps the conversation out of its session
files (verified). Managed configuration and requirements always apply; CLI semantics can drift
between versions (the probe and `--strict-config` catch removed switches, not changed meanings).

**T8 Other IPC (L/M).** No TCP listener in release. Debug endpoints are `#if DEBUG`, bound to
127.0.0.1, require a token, and reject an `Origin` header or a non-loopback `Host` (DNS
rebinding). No AppleScript dictionary, no XPC, no data in distributed notifications. A
`sidefolk://` scheme only navigates. `UserDefaults` holds cosmetics only, so `defaults write`
cannot flip grants, base URLs or extension state.

### C. Hands

**T9 Shell command watchers (M/H).** Created only by the user, or by Sidefolk's agent in a clean
turn (`user:agent`) with high-risk approval; never by external callers, extensions, routines or a
tainted turn (`agent`), which is refused before any card is shown (`Tool.refusal`, logged as
blocked). The probe checks the source again before every run. The grant is bound to
`SHA-256(command + "\0" + canonical cwd)` (no cwd is its own value), so any change voids it;
grants saved before the binding match nothing. Run as `posix_spawn /bin/sh -c` with
`POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT`, stdin `/dev/null`, no TTY (sudo cannot
prompt), fixed env, cwd a granted folder or an empty dir. Timeout 30 s → `SIGTERM` to the process
group, `SIGKILL` 2 s later. Output capped at 64 KiB and untrusted; floor 60 s; at most 5 active.
*Residual:* an approved command is arbitrary code and inherits Sidefolk's TCC grants.

**T10 Filesystem (H/H).** `PathPolicy`:
1. Grants come only from `NSOpenPanel` or Settings. That is user intent, and it also satisfies TCC
   for Documents, Desktop and Downloads. Store the `realpath(3)` plus a bookmark; a bookmark that
   moves requires a new grant.
2. Denied as whole subtrees, even inside broader grants (`FolderAccess.forbiddenReason`):
   `/System`, `/Library`, `/usr` (with `/usr/local`), `/bin`, `/sbin`, `/opt` (Homebrew's `bin`,
   `lib`, `Cellar`: a planted `claude` or stdlib file would run as the user), `/Applications`,
   `/cores`, `/dev`, `/private` except `/private/tmp` and `/private/var/folders`, other users'
   homes and `/Users/Shared`, `~/Library` (LaunchAgents, Keychains), `~/Applications`, `~/bin`,
   `$HOME` dot-dirs (`~/.ssh`, `~/.claude`, `~/.codex`, `~/.local`), and the Sidefolk data root and
   `$SIDEFOLK_HOME`. Never grantable as a whole: `/`, `/Users`, `/Volumes` and each volume's root,
   `$HOME` itself, `/private/tmp`, `/private/var/folders`. The same check gates extension
   `files.read`/`files.write` and file watchers.
3. Check: reject NUL, relative paths and `.`/`..` components. Do not collapse them lexically:
   `standardizedFileURL` turns `granted/link/../x` into `granted/x`, but the kernel resolves
   `link` first. Walk up to the deepest existing ancestor using **lstat** semantics, `realpath`
   it, and append the rest. Allow iff `canon == grant || canon.hasPrefix(grant + "/")`.
   - `FileManager.fileExists` follows links, so a dangling `granted/x -> ~/.ssh/authorized_keys`
     looks like a new file inside the grant, and the write then creates the outside file. This
     works against the `FolderAccess.canonical` logic now in the tree *(verified on a scratch
     copy)*. Treat any symlink in the non-existing tail as a denial.
   - Prefer `realpath` to `URL.resolvingSymlinksInPath`, which strips `/private` (`/tmp/…` where
     `realpath` gives `/private/tmp/…`) *(verified)*. `realpath` returns on-disk case on
     case-insensitive APFS *(verified)*.
4. Use: `open(canon, O_NOFOLLOW_ANY|O_CLOEXEC|O_NONBLOCK)` fails if any component became a
   symlink *(verified)*. Then `fstat` (regular file or directory only; no FIFOs, devices or
   sockets), re-check with `fcntl(F_GETPATH)`, and do I/O on the fd. Reads capped at 10 MiB.
5. Writes:
   - No dot components (`.git/hooks`, `.envrc`, `.vscode`).
   - New files use `O_CREAT|O_EXCL` with mode 0644 and never exec bits.
   - Refuse `.app .command .tool .terminal .webloc .fileloc .scpt .workflow .pkg .mobileconfig`,
     for new names and for moving existing items.
   - Moves check both ends and use `renamex_np(RENAME_EXCL | RENAME_NOFOLLOW_ANY)`, so a folder
     swapped for a link after the check fails the move.
   - Deletes go only through `FileManager.trashItem`.
   - A regular file with more than one link (`st_nlink > 1`) is never read, moved or renamed: it
     may be the same file as one outside every grant.
6. Dotfile reads (`.env`) ask; listings hide them.
7. `LSFileQuarantineEnabled = YES`; never strip `com.apple.quarantine`.

*Residual:* children inherit Sidefolk's TCC grants (the responsible process); a file with a single
name that was swapped in after the check is still read through `O_NOFOLLOW_ANY` and `F_GETPATH`.

**T11 Unsafe URLs and SSRF (H/M).** `URLPolicy` serves web fetch, URL watchers and open URL.
- Fetch: http(s) only, no userinfo, ≤ 2048 chars, punycode shown.
- Resolve with `getaddrinfo` and check every address; this also normalizes `127.1`,
  `2130706433` and `0x7f.1`. Block 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12,
  192.0.0/24, 192.168/16, 198.18/15, 224/4, 240/4, `::`, `::1`, fc00::/7, fe80::/10, ff00::/8,
  and embedded v4 in `::ffff:0:0/96` and `64:ff9b::/96`. Also block `localhost`, `*.localhost`,
  `*.local` and single-label hosts.
- Rebinding: if `URLSessionTaskTransactionMetrics.remoteAddress` is private, discard the
  response. The redirect delegate re-checks every hop (max 5, no https→http).
- `.ephemeral` session with no cookies or credentials, auth challenges cancelled, 15 s timeout,
  2 MiB streamed cap, text, HTML, JSON or XML only.
- Watchers the user asks for themselves (typed in the Ask panel or made with a button: caller
  `user`, untainted) may target localhost, the LAN and `.local` hosts with no further question
  (DECISIONS D21). The `allow_local` flag is set by the tool from the caller, never read from tool
  input; agents (Sidefolk's own in a clean turn, `user:agent`, too), external clients, extensions
  and tainted turns are refused with a message saying to ask directly, and the probes honour the
  flag only on a watcher whose source is exactly `user`.
- Open URL: http(s) low (medium when tainted); `mailto` medium; `file:` goes through `PathPolicy`
  and an executable-type block; `javascript:`, `data:`, `blob:` and `about:` never. Any other
  scheme is high risk and shows the handler app (`NSWorkspace.urlForApplication(toOpen:)`), e.g.
  `shortcuts://run-shortcut`, `vscode://`, `ssh://`.

*Residual:* an approved request still reaches its target.

**T12 Clipboard and drops (M/M).** Clipboard reads are user-initiated or medium, always untrusted.
Writes are low, but medium when tainted (pastejacking `curl … | sh`), and show the exact text. A
dropped file grants a one-turn read of that file only; dropped items are never opened or run.

**T25 The Mac's own apps through Apple Events (M/H), D38.** Apple Notes and Reminders are read with
Apple Events once the person has said yes to macOS's Automation prompt; from then on any Apple Event
Sidefolk sends to that app works, so what is sent is fixed:
- Only Sidefolk's own JavaScript for Automation programs run (`NotesScripts`, `RemindersScripts`); the model
  fills typed tool inputs that reach a program as one ASCII-escaped JSON value (`AutomationScript`), never
  spliced into code. `/usr/bin/osascript` runs as a child in its own process group with only fds 0–2, a fixed
  environment, the script on stdin (nothing personal in argv), a 75 s deadline, and 16 MiB of output at most.
- Capability `mac.apps` can be switched off. Reading and copying are medium, removing is high; nothing is
  offered to external callers or extensions. Every result is untrusted (T2), and so is a copy read back
  later (`app:notes`, T3).
- Read only by default. `applenotes.copy` never changes Notes. `applenotes.remove` is refused before any card
  for a note that wasn't copied, lists every note by title on its card, and at run time keeps in Notes any note
  whose copy is missing, trashed, cut or left attachments behind, that changed after it was copied, that is
  locked, or whose account has no Recently Deleted folder (where deleting would be for good). It reports a note
  as moved only when Notes then shows it in Recently Deleted.
- Embedded images are dropped inside the script (`src="data:…"`), so a photo never travels as base64;
  attachments are named, never read or copied. Bodies are capped (400 KB of HTML, 100 000 characters copied).
- A refusal by macOS shows a button to Privacy & Security › Automation; `PrivacyPane` is the only non-web
  address a card may open.

*Residual:* the Automation grant covers anything Sidefolk sends to that app, so a flaw in a fixed script, or
a child of Sidefolk that sends Apple Events itself (an approved command watcher, an MCP server the person
added), reaches the app with Sidefolk's grant. Recently Deleted is recognised by its name (English, and Notes'
word for the Mac's language); a person's own top-level folder with exactly that name would be taken for it,
and its notes would not be listed.

### D. Extensions and MCP servers

**T13 Manifest validation (M/H).** Strict `Decodable`: unknown keys rejected, a missing `network`
means false, ≤ 64 KiB.
- `id`: `^[a-z0-9]+(\.[a-z0-9-]+)+$`, ≤ 64 chars, equal to the folder name.
- `run.command`: either an interpreter from `{python3,node,sh}` resolved and pinned at install,
  or a relative path whose `realpath` starts with `extDir+"/"` and is a regular executable file.
  The script argument must also resolve inside `extDir`.
- `files` paths: absolute or `~/`, canonicalized, T10 deny-list applied, no quotes, backslashes or
  control characters.
- `exec`: absolute regular files outside every writable path. Flag shells, `osascript`, `open`,
  interpreters, `curl`, `security`, `sqlite3` and `launchctl` as "can run anything".
- Tool names: `^[a-z0-9_]{1,64}$`, namespaced, no shadowing of built-ins. Network or write
  permissions raise every tool to at least medium.
- The install screen names dangerous combinations, e.g. read ~/Documents + network = can upload
  them.

**T14 Tamper and update (M/H).**
- Install copies the folder into `Extensions/<id>/`, read-only.
- Pin a SHA-256 manifest of every file (path, mode, size, hash). Symlinks, setuid bits and special
  files are rejected.
- Verify before each spawn (cached by inode+mtime, full check daily). A mismatch disables the
  extension and asks the user.
- Updates are reinstalls with a permission diff and a tool diff.
- Pin a hash of `tools/list` (names, descriptions, schemas). A tool that changes at runtime (rug
  pull) is quarantined until approved.
- Data lives in `ExtensionData/<id>/`. Sidefolk never loads code, skills or config from there.

**T15 Extension process (M/H).** Spawn
`/usr/bin/sandbox-exec -f <profile> -D K=V… <absolute exec>` (profile in §3) via `posix_spawn`
with `POSIX_SPAWN_CLOEXEC_DEFAULT`, passing only fds 0–2: an inherited fd (DB, socket) bypasses
the sandbox. Use a new process group and a scrubbed env: `HOME`/`TMPDIR` in the data dir,
`PATH=/usr/bin:/bin`, `PYTHONDONTWRITEBYTECODE=1`, and no `NODE_OPTIONS`, `PYTHONPATH`,
`BASH_ENV`, `ENV` or `DYLD_*`. Run Python with `-I`. The profile allows `fork` only when the
manifest lists `exec` programs (or the program is `sh`). Every descendant is tracked by pid and
start time (parent links walked every second, plus the group), so a child that calls `setsid()` is
still stopped on disable, uninstall, quit, crash and by the watchdog. A `proc_pid_rusage` watchdog
kills the tree at RSS > 512 MB, CPU > 50 % for 60 s, or more than 32 processes. Three crashes in
5 min → disabled. *Residual:* a grandchild whose parent exits within the second it was forked is
reparented to launchd before it is seen; it keeps the sandbox, and only extensions whose sheet says
they run programs can fork at all.

**T16 User-added MCP servers (M/H).** They run unsandboxed with the user's rights and Sidefolk's
TCC grants, labelled as such, with the command shown at add time. Tools default to medium and
output is untrusted. Warn on unpinned `npx -y`/`uvx` (new remote code every launch). Per-server
secrets live in the Keychain and go only into that server's env.

**T17 MCP protocol abuse (M/M).** Advertise no client capabilities. Reject server-initiated
`sampling/createMessage` (quota theft), `roots/list` (leaks grants) and `elicitation`. Messages
≤ 1 MiB and nested ≤ 64 levels (deeper JSON from any outside source, the socket, model replies
and watched pages included, is refused before decoding: it would overflow a task's stack; a watched
page that deep is compared as plain text), ≤ 16 in flight, 30 s per
call. Descriptions ≤ 1 KB, schemas ≤ 16 KB, invisible characters stripped; descriptions are shown
to the user, never to the model (T2). An `isError` result's text reaches the model as untrusted
content (≤ 4 KB). Watcher summaries ≤ 200 chars; manifest watcher titles never reach the model.
Extensions get at most `attention`, never `critical`.

### E. Data

**T18 Credentials (M/H).**
- Keychain generic passwords, service `app.sidefolk.secrets` (dev builds use `.dev`, so ad-hoc
  builds never touch release items), non-synchronizable, created by the signed app so the ACL
  trusts its designated requirement.
- A `Secret` type redacts itself in `description`, `Mirror` and `Encodable`.
- Never in SQLite, UserDefaults, argv, child env, prompts, exports or diagnostics.
- A key is bound to its provider host: a base-URL host change needs re-confirmation, and plain
  `http://` to a non-loopback host is refused. Loopback means literally `localhost`, `::1` or an
  IPv4 address in 127/8; `127.0.0.1.example.com` is a public name.

**T19 Local storage (M/M).** Data and log dirs 0700; db, `-wal`, `-shm` and logs 0600. User files
in grants get an explicit 0644. `PRAGMA secure_delete=ON`. Delete-all also removes logs,
ExtensionData, the read-only installed extensions (unlocked first), run state and Keychain items:
provider keys with their host bindings and each MCP server's `mcp.<id>` item, collected before the
extension rows go (`DataPorter.deleteEverything(secrets:)`). Whatever it can't remove is reported,
not ignored. Bound parameters only; FTS5 terms quoted. Encryption at rest
relies on FileVault (stated on the Privacy page). P1: a Keychain-keyed HMAC over grants, folders,
extension pins and command watchers, so tampered rows are ignored.

**T20 Logging leaks (H/M).** `os.Logger` values are `.private`; messages are fixed text and
anything that came from outside (extension ids, methods, tool and skill names) goes in fields. A
JSONL `Redactor` catches `sk-ant-`, `sk-`, `Bearer `, `gh[pousr]_`, `github_pat_`, `xox[abpr]-`,
`AKIA`, `AIza`, `npm_`, JWTs, PEM private keys and opaque tokens ≥ 32 chars mixing upper case,
lower case and digits. No prompt or response bodies by default; activity keeps `args_redacted`;
runs keep counts only; diagnostics exclude user content, and the logs in the diagnostics zip go
through `Redactor.diagnostics` (`Log.copySanitized`): home becomes `~`, paths below it and URL
paths and queries are dropped, hosts stay.

**T21 Exfiltration paths.**

| Path | Control |
|---|---|
| AI provider | By design; the Privacy page shows the last payload |
| Fetch or watcher URLs (query, path, DNS label) | Taint rule |
| Open URL | Same as T11 |
| Markdown images | Never loaded |
| Network extensions | Install warning |
| MCP servers | Labelled as unsandboxed |
| External agents | T4 |
| Clipboard | T12 |
| Writes into synced folders | Ask when tainted |
| Command watchers | T9 |
| Logs and diagnostics | T20 |

**T22 Privilege escalation (L/H).**
- No admin prompts and no privileged helpers; the login item uses `SMAppService.mainApp`.
- Hardened runtime without exceptions: no `disable-library-validation`, DYLD env, `get-task-allow`
  or JIT.
- Helpers are signed by the same team. The CLI link goes into `~/.local/bin` only.
- TCC: Notifications, Local Network only for user-created LAN watchers, and Automation for Notes
  and Reminders only (T25). Never Full Disk Access, Accessibility or Screen Recording.

**T23 Supply chain (L/H).** GRDB and KeyboardShortcuts use `from:` ranges, and
`Package.resolved` is committed. Release builds run `swift build -c release
--only-use-versions-from-resolved-file` *(flag verified)*. Review revision diffs on bumps; no
binary targets or build plugins from dependencies.

**T24 Attention spam and runaway watchers (M/M).**
- Attention: at most 3 items per source per 10 min, and 6 for all sources of one self-named kind
  together (every external agent, every session, every extension), then held; gentle bubbles 6 per
  source (or kind) and 12 in all per 10 min, then badge only. A slot is reserved in the same actor
  step as the decision, so concurrent posts can't all pass. `critical` only from reminders,
  watchers and the user's own actions (`AttentionPolicy.criticalSources`; callers never post under
  those names), and only user-created reminders and watchers are stored as critical (for reminders,
  `user` and `user:agent`, enforced in `ReminderScheduler.create` whatever the caller asked). Only
  the user's own reminders fire as `reminder`, which skips spacing so they arrive on time; anyone
  else's fire as `reminder:<kind>` (`reminder:external`, `reminder:agent`…), wait their turn and
  never say "You asked" (the bubble keys on `refKind`, which stays `reminder`). A second answer to
  the same item is dropped. The `com.apple.screenIsLocked`/`Unlocked` notifications are only a
  hint, since any process can post them: the app must confirm with `ScreenLock.isLocked`
  (`CGSessionCopyCurrentDictionary`) before holding or releasing items. Identical titles within
  10 min are not yet deduplicated.
- Watcher floors: web 5 min, site 60 s, command 60 s. At most 50 active, with per-caller quotas.
- At most 1 request per minute per host, backoff up to 6 h, default expiry 30 days (24 h for
  external agents' watchers, whatever expiry they asked for). Quotas are counted in the same actor
  step that makes a watcher active.

**T26 Voice: the microphone and a cloud voice (M/M), D34.** The microphone opens only while the
person holds the talk key or the companion (off until voice input is turned on; macOS asks on the
first hold), so the orange dot is an honest sign; nothing listens otherwise and there is no wake
word. Recognition runs on the Mac (SpeechAnalyzer, or the older recognizer forced on device); audio
is never written anywhere, and the words go through the normal Ask pipeline as the user's own
request, so Guard, approvals and Undo apply unchanged and voice is never the confirmation for
anything. Spoken replies with ElevenLabs send the words being said, including reminder and note
titles read back, to api.elevenlabs.io: chosen explicitly in Settings › Voice, which says so. Its
key lives in the Keychain bound to that host (as T18), requests are never redirected, and the key is
removed with everything else. Replies stay silent while another app records and in quiet mode.

## 3. Extension sandbox profile

Values are passed only as `-D` parameters, never spliced into SBPL. A value of
`") (allow default) ("` stays inert *(verified)*. Every referenced `param` must be passed (a
missing one fails profile compilation), so the builder emits one rule per `READ_n`/`EXEC_n` it
supplies. Values must be `realpath`s: with `/tmp/…` instead of `/private/tmp/…`, node could not
read its own script *(verified)*. This exact profile ran python3 (Homebrew), node and sh
*(verified)*.

```scheme
(version 1)
(deny default)                                   ; network, mach, IPC, files: all denied

;; process basics
(allow signal (target same-sandbox))
(allow sysctl-read)
(allow mach-lookup
  (global-name "com.apple.system.logger")
  (global-name "com.apple.system.notification_center")
  (global-name "com.apple.system.opendirectoryd.libinfo")
  (global-name "com.apple.system.DirectoryService.libinfo_v1")
  (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent")
  (global-name "com.apple.trustd.agent") (global-name "com.apple.logd"))
(allow ipc-posix-shm-read* (ipc-posix-name "apple.shm.notification_center"))

;; what dyld/libSystem/interpreters need
(allow file-read-metadata)                       ; stat for path resolution (leaks existence)
(allow file-read*
  (literal "/")                                  ; required: without it even /bin/echo aborts
  (subpath "/usr/lib") (subpath "/usr/share") (subpath "/System") (subpath "/Library/Apple")
  (subpath "/private/var/db/timezone") (literal "/private/etc/localtime")
  (literal "/private/etc/passwd") (literal "/private/etc/services") (literal "/private/etc/protocols")
  (literal "/private/var/select/sh")
  (literal "/dev/null") (literal "/dev/zero") (literal "/dev/random") (literal "/dev/urandom")
  (subpath "/dev/fd"))
(allow file-map-executable (subpath "/usr/lib") (subpath "/System") (subpath "/Library/Apple"))
(allow file-write-data (literal "/dev/null") (literal "/dev/zero"))

;; interpreter runtime (read-only), e.g. /opt/homebrew/{Cellar,opt,lib}
(allow file-read* file-map-executable
  (subpath (param "RT_0")) (subpath (param "RT_1")) (subpath (param "RT_2")))

;; the extension (read-only), manifest reads, its data dir (read-write)
(allow file-read* (subpath (param "EXT_DIR")))
(allow file-read* (subpath (param "READ_0")))
(allow file-read* file-write* (subpath (param "DATA_DIR")))

;; exec allow-list: interpreter (+ its re-exec target) + manifest exec entries
(allow process-exec
  (literal (param "RUN_EXEC")) (literal (param "RUN_EXEC_2"))
  (literal (param "EXEC_0")))

;; only with exec entries (or for sh): children inherit this sandbox
(allow process-fork)

;; network=true adds (all-or-nothing, see limits):
;; (allow system-socket) (allow network-outbound (remote ip "*:*"))
;; (allow network-outbound (literal "/private/var/run/mDNSResponder"))  ; DNS
;; (allow file-read* (subpath "/private/etc/ssl") (subpath "/opt/homebrew/etc/ca-certificates"))
```

**What runtimes need to start** *(verified)*:
- **Every runtime:** read on `/` itself (without it even `/bin/echo` aborts), `/usr/lib`,
  `/System` (holds the dyld shared cache) and `/usr/share`; map-executable on `/usr/lib` and
  `/System`; `/dev/null` and `/dev/urandom`; timezone files; broad `file-read-metadata`;
  `sysctl-read`.
- **sh:** `/bin/sh` reads `/private/var/select/sh` and execs `/bin/bash`, so allow both. A script's
  external commands must each be listed (`head` was denied).
- **python3:** framework builds (Homebrew and Xcode) re-exec
  `…/Python.framework/Versions/X/Resources/Python.app/Contents/MacOS/Python`; allow it. Homebrew
  needs `/opt/homebrew/{Cellar,opt,lib}` (`ssl` loads `opt/openssl@3`) but not `etc` or `var`.
  `/usr/bin/python3` is an xcrun shim that fails in the sandbox; resolve it at install with
  `xcrun --find python3` + `realpath`.
- **node:** a standalone binary needs only itself. Homebrew node also needs its dylibs in
  `/opt/homebrew/opt`.

**Observed under this profile:**
- Blocked: network and unix-socket connects (EPERM); reads of `~/.ssh`, `/etc/hosts` and
  `~/.zshrc`; writes to the extension dir; reading through a symlink created in the data dir; hard
  links to outside files; exec through a symlink; listing `$HOME`.
- Still allowed: `stat ~/.ssh`.

**Limits:**
- Deprecated, undocumented SBPL (Chromium, Codex and Claude Code still use it). Re-run the sandbox
  integration test on every macOS release.
- Network is all-or-nothing: `(deny network-outbound (remote ip "localhost:*"))` does **not**
  carve localhost out of `*:*` *(verified)*. Hosts can only be `*` or `localhost`, so a network
  extension reaches the LAN and local services. P1: allow only
  `(remote ip "localhost:<port>")` (per-port works *(verified)*) to a Sidefolk egress proxy that
  enforces domain lists and the T11 IP rules.
- Metadata (existence, size, mtime) leaks. Each allowed mach service is attack surface; never allow
  the pasteboard, LaunchServices or Apple Events.
- No CPU, memory or fd limits (watchdog, T15). No defence against kernel escapes, misuse of granted
  resources (read + network = exfiltration) or injection through output.
- Allowing a shell or interpreter in `exec` makes the exec list meaningless.

## 4. Security unit tests

1. **PathPolicy:**
   - Symlink escape, including a *dangling* link in a write target, and `link/../x`.
   - Prefix confusion (`Doc` vs `Documents2`), case-mangled input, `/tmp` vs `/private/tmp`.
   - The Sidefolk root and `~/Library/LaunchAgents` under a `$HOME`-wide grant.
   - A dot-path write; a FIFO.
   - A directory swapped for a symlink after the check: `O_NOFOLLOW_ANY` fails.
2. **URLPolicy:**
   - Rejected: `file:`, `javascript:`, `data:` and custom schemes.
   - Rejected: `127.1`, `2130706433`, `0177.0.0.1`, `[::1]`, `[::ffff:127.0.0.1]`,
     `169.254.169.254`, RFC1918, `100.64/10`, `x.localhost`.
   - Rejected: a stub resolver returning a private IP, and a redirect to one.
   - Allowed: a localhost watcher the user created.
3. **Guard:** taint makes the next medium call ask and ignores grants; a non-user URL asks; an
   exact-command grant rejects `cmd; rm -rf ~` and whitespace variants; external callers cannot
   reach file, clipboard or command tools; the extension risk floor holds; an args-hash mismatch
   aborts.
4. **Socket:** foreign uid rejected (seam over `LOCAL_PEERCRED`); no token → `.external`; bad,
   expired or reused token → disconnect; oversized line rejected; symlinked, foreign-owned or 0755
   run dir refused; a live socket is never unlinked; mode is 0600; a session event's host pid that
   isn't an ancestor of the sender is dropped.
5. **Manifest:** bad id; id/folder mismatch; `run.command` escape (`../`, absolute, symlink);
   unknown key; exec inside a writable path; deny-listed path; quote or newline in a path.
6. **Integrity:** an edited extension file disables the extension; a changed `tools/list`
   quarantines the tool.
7. **Sandbox:** snapshot of the SBPL and `-D` list; an integration test that the sample extension
   gets EPERM for network, `~/.ssh`, writes outside its data dir and unlisted exec.
8. **Spawn hygiene:** extension, command and brain children see only fds 0–2 and an allow-listed
   env; a timeout kills `sh -c 'sleep 100 & sleep 100'` completely.
9. **Secrets:** a canary `sk-ant-CANARY…` never reaches logs, DB, UserDefaults, exports, child env
   or argv; `Secret` prints redacted.
10. **Brain:** argv has the isolation flags and no prompt or token; a failed probe refuses to run;
    an extra tool in the init event kills the run. Codex: a renamed feature switch or missing flag
    refuses to run; a recorded `command_execution`, `web_search`, `file_change` or another server's
    tool kills the run and disables the backend; signed out never starts `exec`; a key saved for one
    host is never sent to another preset's host.
11. **DoS:** watcher floors and quotas (parallel external creations stop at the cap); attention rate
    limit; step and call caps; repeated-call breaker; one pending approval per caller.
12. **Storage:** modes 0700/0600 including wal and shm; delete-all removes everything, Keychain
    included.
13. **Mac apps (T25):** tool inputs never become script (quotes, `</script>`, U+2028 echo back unchanged
    through osascript); a refusal by macOS becomes the Settings card; reads taint and ask again while
    tainted; removing is refused for notes not copied, kept for cut, changed or attachment-bearing copies
    and for accounts without Recently Deleted; the scripts run against a stand-in, never the real apps.

## 5. What Sidefolk never does

- Never lets the model, routines, external agents or extensions answer approvals, create grants,
  change settings, install extensions or touch Sidefolk's own data.
- Never runs model- or agent-written commands without the user approving the verbatim text; never
  "always" for high risk; no AI-generated executable code.
- Never hard-deletes, sets exec bits or strips quarantine.
- Never puts secrets or prompts in argv, logs, SQLite, UserDefaults, child env or exports; never
  sends a key to a host other than its provider's.
- Never listens on TCP in release, and never takes commands via URL schemes, AppleScript or
  distributed notifications.
- Never fetches non-http(s) URLs, or private addresses from model-built URLs; never loads remote
  images.
- Never asks for admin rights, Full Disk Access, Accessibility or Screen Recording; Automation only
  for Notes and Reminders, driven by fixed scripts (T25).
- Never removes anything from another app unless its whole copy is in the notebook and the person
  approved that removal (T25).
- Never offers MCP sampling, roots or elicitation to extensions; never downloads or auto-updates
  extension code.
- Never edits `~/.claude`, `~/.claude.json` or `~/.codex` without a click, a confirmation and a
  backup.
- Never runs the brain when isolation cannot be verified.
- Never sends telemetry.
