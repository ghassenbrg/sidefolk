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
path, verbatim command), never model prose. An extension's arguments are said in words (`ArgumentWords`: each value
the call's own, cleaned and clipped), with the exact request one click away (D71); a card after outside content says
what was read first and why it asks (`ApprovalReason`), never changing what Guard decided. A medium card's label says what the call can do
(`ApprovalRequest.Effect`: reads private data, reads files, uses the internet, opens a link or app, uses an
extension, changes files, runs a program, changes things), from what Sidefolk lets it do: for an extension
its sandbox's permissions, never the manifest's word that a tool changes nothing. Approval is bound to `SHA-256(tool, canonical args)`
and re-checked at execution. Allow is inert for 800 ms, Return never defaults to Allow on high,
a card waits 120 s and then counts as a no, except the cards of Sidefolk's own agent, which follow
the person's "If I don't answer" setting (skip the step or stop the task after N minutes, a day at
most; D37), and a run's cards are denied when the run ends (or its socket connection drops), so a
late Allow never acts for a caller that is gone. How often the person is asked is their approval
mode (D37); modes loosen Guard only for Sidefolk's own agent and never touch the rules below. Other agents
share one pending card: while it waits, their further requests are refused at once (their names
are self-chosen, so a per-name limit would be none). "Always" grants are never given for high
risk or to external callers, are scoped by caller kind, revocable, and expire after 90 days
unused. A site grant never covers a URL with a query or fragment; it names one site (`www.` and a final
dot don't matter, any other label does). *Residual:* the user approves
without reading.

**T2 Prompt injection (H/H).** Sources: web pages, watcher payloads, files, clipboard, drops,
command output, extension and MCP results *and tool descriptions*, Apple Notes and Reminders (every
`applenotes.*` and `applereminders.list` result, titles and folder names included), calendar events (`calendar.today`:
anyone who sends an invitation writes its title, T34), notes, memories, reminders and
watchers written by external agents (or by Sidefolk's agent in a tainted turn). Every `ToolResult`
carries `untrusted`; a list or read that quotes anyone else's words sets it (`reminders.*` and
`watch.*` when a title isn't user-sourced, notes, and `collections.list`, `notes.*` when a quoted
collection name isn't). Taint is sticky for the turn (or routine run) and
set only by code. While tainted, all medium/high calls ask (grants ignored), and so do clipboard
writes and memory/skill/routine creation. Auto changes none of this; Full access still asks, in a
tainted turn, for every call that could carry data out (network or open at an untyped address,
commands, file changes, extension and MCP tools, clipboard and memory writes) and lets the rest run
(D37). A tainted card for a step that can carry nothing out (not high risk, nothing to read in full)
offers "Allow for this request" instead of "Always": that tool runs without a card until the run ends. Network and open calls ask (medium) whenever their
normalized URL is not in the user's message for this run, tainted or not; a typed URL runs even
while tainted, and opening a site the user named runs in a clean turn (`UserMentions`: scheme,
`www.`, default port and a trailing slash don't matter; query and fragment do). Addresses on this
Mac or the local network get no card: fetching and watching refuse them for everyone but the
user, and opening one in the browser sends nothing beyond the LAN. External
agents follow T4 instead (their own context and network are already theirs).
*Using the internet (D47), for Sidefolk's own agent only.* Two kinds of call keep the person's grant
after outside content was read, because what a steered model writes into them reaches no one new: reading
a page (`web.fetch`) on a site the person allowed for good (a site grant: exact site, no query or fragment,
and the fetch may not be redirected off that site, so an open redirect there can't carry the path
elsewhere: `ToolContext.site`), and a call whose destination Sidefolk's own code fixes
(`NetworkReach.service`, an extension or service grant): the weather report (Open-Meteo) and the built-in
extensions in `BuiltInServices` (Weather → Open-Meteo, Currency → the ECB; only the app's own copies,
origin `bundled`, and a test checks every address in their programs against the list). Those grants come
from a clean turn or from Settings: "Always" is still never offered after outside content, and without a
grant these ask as before, in Full access too. A metric report reaches no network at all
(`NetworkReach.nowhere`). A new site, a query on any site, a watcher, an open, someone else's network
extension or MCP server ask as above. The person's internet rule: *Ask each time* (no grants, no "Always",
and no mode answers for an internet call; even a weather report asks), *Ask once for each site* (the
default), or *Don't ask before reading* (in a clean turn any public page and the built-in services go
without a card, logged `web_setting`, as Auto does for medium; after outside content the built-in services
and the allowed sites do, so a steered place name can reach Open-Meteo, and nothing else changes). Sites can
also be allowed in Settings.
Extension and MCP
tool descriptions never reach the model: it gets a neutral line built from the tool title and
extension name, and the schema without its free text (descriptions stay on the install sheet). The
exception is the extensions Sidefolk ships (origin `bundled`, installed only from the app's own signed
Resources, D39): their descriptions are first-party text and are reviewed like prompts.
Untrusted text is wrapped as `<untrusted source=…>` (closing tag escaped), stripped of invisible
and bidi characters (U+200B–200F, 202A–202E, 2060–2069, FEFF, E0000–E007F) and capped at 20 KB.
That is hygiene, not a boundary. Rendered Markdown never loads remote images; links show the full
host. *Residual:* injection can still steer low-risk actions; extension tool names and titles
(≤ 60 characters) still reach the model. A site the person allowed for good can receive, in a page's
path, whatever a steered model puts there: only that site's owner reads it, so the trade rests on the
person allowing sites they trust (a site where strangers can read who fetched what, a request bin, isn't
one). `BuiltInServices` is Sidefolk's word for its own code: the sandbox can't hold a program to host
names (§3), so a change to those programs must keep the address test passing.

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
together), `reminders.cancel` (only reminders that client name set; others read as not found),
notify/`ask_user`, `status`, non-command watchers (10 active for all clients together, each stopping
after 24 h; `WatcherEngine.add` counts and inserts in one actor step, so parallel calls can't
overshoot), and `watch.report` for this Mac's own metrics (cpu, memory, battery, disk, network: no
web values and no weather, which would reach a server; a fast one stops within the hour) (D42).
They see descriptions and schemas written for them (`ExternalToolPolicy.externalSpec`): no
`collection_kind`, no critical level, no command kinds, `source: metric` only. A reminder they tie
to a note or task (`item`, D49) needs its own title: the item's words are never its default, and the
result names the item by kind and id only.
Reading user data (notes, reminders, `agenda.today`) asks every time; an external caller never gets
"Always". `notes.update` and `notes.trash` change or trash one note by id (never in "About you",
never into a new collection, never deleting for good: only the person empties the Trash), each undoable
from Activity (D52). Settings › Privacy › Other agents (`AgentAccess`) sets each group (saving,
changing, reading) to Allow, Ask each time or Off; defaults: saving and changing allowed, reading asks.
"Allow" on reads is the person's explicit choice, shown with what it means; Off hides the tools and
refuses calls with a message that names the setting. The closed list itself never changes from Settings. Files, clipboard, open, web fetch, web and weather reports, command watchers, skills,
settings and extensions are not exposed. There is no per-client key: Connect only adds the MCP entry
(after confirmation and backup), any same-uid process can connect, and names are self-chosen and
shown as unverified, so the quotas that matter are the ones shared by all external clients. Rate limits: 60 calls/min and 4 concurrent per connection, 120 calls/min for all
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

**T28 What Sidefolk installs into other agents (M/M), D42.** Connect writes three kinds of things into
Claude Code's and Codex's folders: the MCP entry (T4), hooks (Claude Code's `settings.json`, Codex's
`hooks.json`) and the Sidefolk skill (`<agent folder>/skills/sidefolk/SKILL.md`), an instruction file both
agents load into their models' context.
- Only on the person's click, after a dialog listing every file, change and backup (D16); never at launch.
  Each file is backed up before it changes, except a skill exactly as Sidefolk writes it.
- The skill is fixed text from the app's signed Resources, the same for everyone: nothing personal, no
  paths, no secrets. It tells agents not to store secrets, not to spam, to respect quiet mode and not to
  write instructions for other AIs. It grants nothing: whatever it says, Guard, quotas and approvals decide
  (T4), and a model ignoring it gets exactly what one without it gets.
- Sidefolk knows its own skill by a marker line, and removes only a marked file, never through a symbolic
  link: a skill folder linked from a checkout (common) is left alone, so a Disconnect can't delete files in
  someone's repository, and an install can't write into one.
- Codex's hooks need Codex's own review: Codex lists new hooks as untrusted and asks the person; Sidefolk
  never writes Codex's trust hashes (`[hooks.state]` in `config.toml`). Hook payloads are untrusted input
  (T4: capped, fail open, 2 s budget). `--agent` takes only `claude-code` or `codex`.
- Sidefolk's own CLI brains skip all of it: Claude Code ignores user settings and runs with skills off, Codex
  runs with `--ignore-user-config`, no skill list and the `hooks` feature off (T7).
*Residual:* same-uid code can rewrite the installed skill to steer the person's agents (out of scope, §1;
Connect shows it as outdated and replaces it); the person's agent may follow the skill's examples a little
too literally (one notice per event is advice, not a limit: AttentionPolicy's limits are).

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
cannot flip grants, the approval mode, base URLs or extension state.

### C. Hands

**T9 Shell command watchers (M/H).** Created only by the user, or by Sidefolk's agent in a clean
turn (`user:agent`) with high-risk approval (or without one when the person turned on Full access,
D37); never by external callers, extensions, routines or a
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
  permissions (fixed folders or a `"write"` folder parameter) raise every tool to at least medium.
- `exec` entries without a path name a program Sidefolk knows (`git` only): resolved from the developer
  folder `xcode-select` points at, the Command Line Tools, Xcode or Homebrew (never `/usr/bin` shims,
  never by running xcrun), trusted like an interpreter (owner root or user, not group/world-writable,
  never the root as prefix), with its fixed helper list. It isn't "can run anything": the sandbox lets it
  exec only those helpers.
- `icon`: a regular file inside the folder (no links), `.png` or `.pdf`, ≤ 256 KiB; a PNG's signature and
  IHDR must say square 64–1024 px; a PDF must parse with CoreGraphics as one unencrypted, square page.
  Never SVG. Nothing in it is executed or fetched; the app draws the pinned, installed copy.
- The install screen names dangerous combinations, e.g. read ~/Documents + network = can upload
  them: as a red warning before the permissions, except for Sidefolk's own signed gallery extensions, where the
  same sentences are a calm "Good to know" (D71). Where it comes from is said first; an update that adds a
  permission is shown prominently whoever signed it.

**T14 Tamper and update (M/H).**
- Install copies the folder into `Extensions/<id>/`, read-only.
- Pin a SHA-256 manifest of every file (path, mode, size, hash). Symlinks, setuid bits and special
  files are rejected.
- Verify before each spawn (cached by inode+mtime, full check daily). A mismatch disables the
  extension and asks the user.
- Updates are reinstalls with a permission diff and a tool diff. Built-in extensions (D39) are
  reinstalled from the app's Resources when their files differ from the installed copy; one that gains
  a permission comes back switched off with a notice. They can't be uninstalled (they would return),
  only switched off. A hand-installed copy with the same id is replaced only by a strictly newer
  built-in version.
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
kills the tree at RSS > 512 MB, CPU > 50 % for 60 s, or more than 32 processes. A call that names a
folder (`tools.<name>.paths`, T27) runs in its own process whose profile adds only that folder; it is
tracked and stopped like the main one, and ends with the call. Three crashes in
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

**T27 Extensions the AI writes, and folders named per call (M/H), D39.** Two new ways in: Sidefolk's model
writes program code for the person (`extensions.draft`), and an extension's tool receives a folder the
person names in a request.
- *Drafting:* only `Caller.user` or Sidefolk's agent, and never in a tainted turn (`Tool.refusal`, before
  any card), so injected content can't commission code. Never offered to external agents. A draft is text
  only: at most 20 files and 1 MB, known text extensions, plain relative names (no `..`, no dot files, no
  links), written `O_CREAT|O_EXCL|O_NOFOLLOW` with mode 0600 into a staging folder and renamed into
  `ExtensionDrafts/local.<name>/` (0700, under Sidefolk's data, which file tools never touch, T10). Sidefolk
  sets `id` (`local.` prefix: never a company's or a built-in id) and `author`; `icon` is refused.
- *Before approval:* the draft is validated (T13) and started once in a sandbox with `permissions`
  replaced by `{}` (no network, no folders, no programs, no fork), in a throwaway Sidefolk home, for at most
  the 30 s call limit, under the watchdog. That is the only time unapproved model-written code runs.
- *Installing:* only the normal install preview (its own window when Sidefolk hands a draft over, a sheet
  in Settings otherwise: permission lines, warnings, sandbox, update
  diff, 800 ms arming), opened by `extensions.review` or by the person; the model has no install tool.
  Installed drafts are origin `draft`, labelled "Written for you", and their descriptions don't reach the
  model (T2, T3: they would persist into every run).
- *Folders named per call:* the parameter goes through Guard as a read or write path (T10: shared folders,
  protected subtrees, the folder card only for Sidefolk's agent and the user). Guard's allowed folders
  travel in `ToolContext.folders`; at run time the tool canonicalises the path again, checks it against
  those folders and the protected list, and passes the canonical path. The host refuses anything inside
  Sidefolk's own data, adds the path to a fresh profile (`READ_n`/`WRITE_n`), and stops that process when
  the call returns. A relative path is refused before any card.
*Residual:* a person can approve a draft without reading its code (the sheet names its permissions, not
its logic); a write folder lets an extension plant files there that other programs later trust (a git
hook in a repository it was asked to update; Git itself runs with `core.hooksPath=/dev/null`). A
sandbox escape in the trial would run unapproved code; the trial grants nothing and is short.

**T32 An extension's commands: the person's words, the extension's mapping (M/M), D50.** A manifest can
list sentences ("time in {place:place}") that call one of its tools without the AI, and can keep a tool from the
model. Two risks: a command that swallows what people say to Sidefolk (or to the AI), and a mapping that turns
a typed sentence into a call the person didn't mean.
- *Capture:* a sentence must hold a word of its own (two letters or more), may not start with a slot that takes
  any words (`text`, `word`, `place`, `list`), and no two such slots may touch; at most three slots, 80
  characters, twelve sentences a command, eight commands a tool, 64 sentences an extension; replies anyone
  types ("yes", "thanks", "stop", "help"…) are refused. The one sentence with no word of its own is a lone
  `{…:expression}`, which takes only digits, operators and a calculator's words. Slots are checked again after
  matching (an expression that is a date or a phone number, a place of more than six words, a day only the
  AI can read are no match). `ManifestValidator` refuses the rest with the field and a plain message.
- *Order:* every core intent first (reminders, notes, watches, quiet, conversations, play); then commands of
  switched-on extensions only (only their tools are registered), whole sentence after the same clean-up; a
  sentence two extensions claim goes to the AI. The hint under the field names the extension before Enter.
  Something dropped on the panel sends the request to the AI instead.
- *Who calls:* `Caller.command(extensionId:)`. The person typed the words but the extension chose the tool and
  every constant in its input (a folder, an operation), so Guard treats the call as Sidefolk's agent in a clean
  turn, never as the user's own click: a tool that only computes runs, a network, folder or risky tool asks
  (or uses a grant the person gave the AI for that tool; `Caller.grantKind` is "agent" both ways), and the
  person's approval mode and "Using the internet" rule (D47) apply. Mentions are the typed sentence, so an
  address the person typed counts as typed (T1). It can't draft extensions, write skills, or manage another
  caller's reminders or watchers. Activity records `command:<extension id>`.
- *Results:* shown to the person, never sent to a model. A tool that reports it couldn't answer hands the
  sentence to the AI (when one is set up), as if the command didn't exist.
- *The model:* a tool marked `"ai": false` is left out of every run's tool list (`ToolSpec.offeredToModel`), and
  the agent's toolbox refuses a name it wasn't offered.
*Residual:* a command sentence can still take words someone meant for the AI ("what time is it in my head"),
and the extension then reads them; the hint names it first, and the AI gets the sentence when the extension
can't answer. Command sentences are English, like the core parser (D28).

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
not ignored. Conversation history can also be deleted on its own, one conversation or all of it (Home ›
Conversations, Settings › Privacy, D45): the thread's runs stop first, then its exchanges go and the "last sent"
preview with them; Activity keeps its audit record. Retention is applied at launch and then daily while Sidefolk
runs: conversation history (7 days by default), Activity and AI run records (90), finished `sidefolk run` jobs with their stderr tails (14), sessions
(14), the notebook's Trash (30); log files after 7 days, at most 16 MB a day. Bound parameters only; FTS5 terms quoted. Encryption at rest
relies on FileVault (stated on the Privacy page). P1: a Keychain-keyed HMAC over grants, folders,
extension pins, command watchers and the Guard policy (the approval mode, D37), so tampered rows are
ignored.

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
| Fetch or watcher URLs (query, path, DNS label) | Taint rule; after outside content a fetch goes without a card only to a site allowed for good: exact site, no query or fragment, no redirect off it (D47) |
| Open URL | Same as T11 |
| Markdown images | Never loaded |
| Network extensions | Install warning; only the built-in services (`BuiltInServices`, address-checked) skip the taint rule (D47) |
| MCP servers | Labelled as unsandboxed |
| External agents | T4 |
| Clipboard | T12 |
| Calendar events | T34 |
| Writes into synced folders | Ask when tainted |
| Command watchers | T9 |
| Logs and diagnostics | T20 |

**T22 Privilege escalation (L/H).**
- No admin prompts and no privileged helpers; the login item uses `SMAppService.mainApp`.
- Hardened runtime without exceptions: no `disable-library-validation`, DYLD env, `get-task-allow`
  or JIT.
- Helpers are signed by the same team. The CLI link goes into `~/.local/bin` only.
- TCC: Notifications, Local Network only for user-created LAN watchers or a model server the person
  pointed at another computer (`NSLocalNetworkUsageDescription` says so), the microphone while the talk key
  is held (T26), and Automation for Notes and Reminders only (T25). Never Full Disk Access, Accessibility or
  Screen Recording.

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
- Watcher floors: web 5 min, site 60 s, command 60 s. Reports (D35): metrics 5 s, weather and web
  values 60 s (still one request a minute per host), command output 10 s; at most 4 live at once,
  ending after an hour or a day unless the user said "until I stop it". `watch.report` is offered
  to external agents for this Mac's metrics only: a web value would let them read pages through
  Sidefolk (T4). A web value or a
  command's output is untrusted in the tool result (T2). At most 50 active, with per-caller quotas.
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

**T30 Where the person is (M/M), D48.** Off until the person chooses in Settings › Privacy › Your location;
until then nothing about where they are leaves the Mac, and the AI is only told the place isn't known.
- *The Mac's location.* Location Services at a city's accuracy (3 km), significant changes only. macOS asks
  once, when the person picks it (`NSLocationUsageDescription`, and the hardened runtime's
  `com.apple.security.personal-information.location`); at launch Sidefolk resumes only what macOS already
  allowed, and reading the state never asks. A new position is named only when it is more than 5 km from the
  last or the name is a day old, at most every 10 minutes, by Apple's geocoder (MapKit, Core Location before
  macOS 26), which receives the position as any Mac app's lookup does.
- *A place chosen by name.* The typed words go to Open-Meteo's geocoder, the host the weather already uses.
- *What is kept.* The town, region, country, time zone and coordinates rounded to 0.01° (about a kilometre), in
  settings. Changing the choice clears the place; Off forgets it. The coordinates are used for one thing: asking
  Open-Meteo about the weather there, as for any place.
- *What the AI hears.* One line: town, region and country (and the time there when a chosen place keeps another
  clock), never coordinates. Every name, from Apple or Open-Meteo, is held to the place-name rule
  (`WeatherProbe.cleanPlace`: letters, spaces and a little punctuation, 60 characters), so a geocoder's answer
  can't carry instructions into the context. Other agents get no tool that reads it (their reports are this
  Mac's metrics only, T4); extensions see only what a model passes them, like any argument.
- *Logs and exports.* The log says that the place changed, never where; diagnostics drop the place. The person's
  own data export keeps it, and Delete all removes it with the settings.

**T31 Updating Sidefolk itself (M/H), D46.** The updater replaces the app with code from the internet, so the
only thing it believes about a download is its signature:
- *Where from.* The GitHub Releases of `ghassenbrg/sidefolk` (the API over https, no account or key; the request
  carries Sidefolk's version in its User-Agent and nothing about the person). Files come only from https on
  `github.com` or `*.githubusercontent.com`, redirects included, in an ephemeral session (no cookies, cache or
  credentials); a file larger than the release says is cut off.
- *What is checked, in order.* Size, and SHA-256 against the release's checksum file and GitHub's own digest,
  which must agree. The image is mounted read-only and hidden; the one app inside must carry the running app's
  bundle id and name itself the release it is offered as (`SidefolkRelease`), which must be newer: no downgrade.
  Its signature must meet a requirement built from the running app's own signature, never from the download:
  anchored at Apple, a Developer ID Application leaf from the Developer ID intermediate, the same Team ID and
  identifier, and `notarized`, validated strictly over every architecture and nested program. The same checks
  run again on the copy staged beside the app, the code that will actually open.
- *A stolen GitHub account* can publish a release but not one that passes: it would also need the team's
  Developer ID key and Apple's notarization. A stolen Developer ID key as well is a threat to every Developer ID
  app; Apple's revocation answers it.
- *Quarantine.* Removed from the staged copy only after those checks: otherwise Gatekeeper's "downloaded from
  the internet" question would wait for someone after Sidefolk had quit. A disk image left in Downloads keeps
  its mark.
- *The swap.* One same-volume exchange (`renamex_np`, `RENAME_SWAP`) beside the app, so the path always holds a
  complete signed app; a failure before it leaves the old one, and when reopening can't be arranged the swap is
  undone. The shell that waits for Sidefolk to quit gets the paths as arguments and removes only a folder
  named with the staging prefix (`.Sidefolk-update-`); leftovers are cleared at the next launch.
- *Who doesn't replace itself.* A copy built on the Mac (no `SidefolkRelease`), signed ad hoc or for development,
  translocated, on a read-only volume, or in a folder the account can't write: it leaves the checked image in
  Downloads and says why. Sidefolk never asks for admin rights to update.
*Residual:* a new version that crashes at launch isn't caught before the old one is gone (the person reinstalls
from the release page); the Developer ID certificate expires on 2027-02-01, and its replacement keeps the team,
so updates carry on.

**T33 Add-ons from the gallery (M/H), D55.** Companions and extensions are downloaded from the `gallery` release
of `ghassenbrg/sidefolk-addons`, so, as for updates (T31), nothing is believed about a download but its signature:
- *Where from.* Only `github.com` and GitHub's file hosts over https, redirects included, in an ephemeral session;
  a file larger than the catalog says is cut off. The request carries Sidefolk's version and nothing about the
  person; the catalog is fetched when the person opens a gallery, at launch when their chosen companion is
  missing, and for updates 90 s after launch and every six hours (D70).
- *The catalog* is itself a signed bundle (`dev.sidefolk.addons.catalog`). Every pack must be signed, strictly and
  over every file, with a Developer ID Application certificate of the team in the app's own Info.plist, and carry
  the exact identifier the catalog lists; its size and SHA-256 must match the catalog, and its Info.plist the id and
  version. A pack that is another signed pack can't stand in for the one asked for. Folder paths in the catalog are
  never used: files are named by pattern (`<name>-<version>.zip`, `previews/<name>.png|pdf`).
- *Companions* are four files, named after the companion, and nothing else; the 3D page serves only those four
  kinds of path from an installed companion's folder. Their character file is JavaScript run in the companion's
  WebKit page (no network, no file access, a private scheme): acceptable only because Sidefolk signed it.
  Anyone else's 3D companion waits for a data-only format.
- *Extensions* go through the install preview like any extension, with its permissions and warnings; origin
  `official` makes them first-party (T2's rule doesn't apply to Sidefolk's own words, D39) and drops the download
  mark after the checks, as for built-ins. They are never installed without the person's click. An update installs
  by itself only while "Update add-ons automatically" is on and only if it widens nothing the person agreed to
  (D70: no new permission, judged on the permissions themselves, no tool riskier than before, no `background`);
  otherwise it waits for the same install sheet. Its pack is fetched and checked exactly as a click would.
- *A stolen GitHub account* can replace files in the release but can't sign them. A stolen Developer ID key is
  answered by Apple's revocation, as for the app. Downgrades: an older signed pack the catalog lists would install
  only if the person chose it; the gallery offers Update only for a newer version.
*Residual:* the catalog's text (names, taglines, descriptions) is shown in Settings; only official entries' words
reach the model, as one line each.

**T34 The person's calendar (M/M), D57.** Off until the person chooses "Show my calendar" (Settings › Privacy ›
Your calendar, or Today); until then nothing is read, the AI isn't offered `calendar.today`, and macOS is never
asked. Choosing it asks macOS once for full access (`NSCalendarsFullAccessUsageDescription`, and the hardened
runtime's `com.apple.security.personal-information.calendars`); reading the state never asks.
- *Read-only.* EventKit is only queried; nothing in Sidefolk can create, change or delete an event.
- *Where events go.* Today and the morning brief, on this Mac. Attention items, where the brief lands, never reach
  the model's context.
- *What the AI hears.* Only through `calendar.today`: medium risk, "Reads private data", through Guard like any
  tool, so the person is asked (once per kind unless they choose otherwise). The result is untrusted (T2): an
  invitation's title is written by whoever sent it. Other agents get no tool that reads it (`external: false`).
*Residual:* once allowed for good, the AI may read the day's events in any later clean turn.

**T35 Themes (L/M), D58, D64.** A theme is data: `theme.json` (64 KB at most) and PNGs (2 MB and 2048 px at most,
inside its folder, decoded and written again by Sidefolk before use), never code, never words shown as the app's.
Its layout names only blocks the app draws; anything else is left out and said, and what needs you (Guard's
questions) always has a place, so no theme can hide a waiting approval. Ids under `dev.sidefolk.` and `harbor` are
taken only from the app's Resources and the signed gallery (T33), so a theme from a folder can't pass as Sidefolk's.
A followed theme folder is read once a second and only checked and copied; a broken save leaves the last good theme.

**T36 Extensions that record the screen and stream on the network (M/H), D69.** `permissions.screen` opens
ScreenCaptureKit (`com.apple.replayd`, `com.apple.windowserver.active`) and the video encoder
(`com.apple.coremedia.videoencoder`); `permissions.udp` (only with `network`) adds `network-bind` and `network-inbound`
for UDP. Measured on macOS 27: without them ScreenCaptureKit hangs and UDP's bind is refused (EPERM); with them a
display, a window, a picture and the Mac's sound are captured and H.264 goes out over WebRTC. macOS attributes the
recording to the responsible process, Sidefolk (tccd: `responsible=app.sidefolk.Sidefolk…`), and on macOS 27 doesn't
prompt: it lists Sidefolk, off, in Screen & System Audio Recording, and the extension says where to turn it on.
- *Shared grant:* once the person allows Sidefolk, every extension whose manifest has `screen` can record. The
  install sheet names it (with caution), raises every tool to medium, and warns when it comes with the network;
  nothing else opens those services.
- *Not the local network only:* SBPL accepts only `*` or `localhost` as a host (a private range doesn't compile,
  `theSandboxCantFenceOffTheInternet`), so an extension that means the LAN can reach the internet; the sheet says so,
  adding the author's `network_purpose` after it, never instead. UDP inbound is from any host that can reach the Mac.
- *Files named per call that must outlive the call* (a film on the TV): the call's own process clones the file into
  the data folder and hands it over; the clone is deleted at stop, and at the next start if Sidefolk quit first.
*Residual:* a screen-recording extension with the network could send the screen anywhere; the sheet says it in those
words. The TCC grant isn't per extension.

**T29 Crashing Sidefolk, or making it forget a setting, from outside (M/M), D41.** Other agents, extensions,
web pages and stored rows hand Sidefolk numbers and errors. A crash is a denial of service, and a crash caused by
a stored row is a loop at every launch; an error answered with a default can quietly undo a setting the person
chose. Found in the 0.1.0 review and fixed:
- *Numbers.* `Int(_:)` traps on a Double past Int.max and Int arithmetic traps on overflow. Typing "remind me on
  dec 99999999999999999999" crashed the hint line; another agent's `reminders.create` with
  `interval: 9e18` crashed Sidefolk at once (weekly) or when it fired, then at every launch; a giant `maximum`
  in an extension's schema crashed the message that quoted it. Numbers are bounded before any conversion
  (`WhenToken.isInteger` below 10⁹, spans below 100 000), a repeat is at most every 1000 units
  (`Recurrence.maxInterval`, in the schema, in `init` and again in `RecurrenceMath` for rows already stored),
  and network values are formatted without `Int(_:)`.
- *Fail closed.* Guard read the policy with `try?` and fell back to the default, in which nothing is switched
  off: a call from a stopped task (GRDB refuses work from a cancelled task) ran with Clipboard switched off, set
  the clipboard, and reported it hadn't. Guard now refuses when it can't read the person's settings, and
  `withTimeout` never starts work for a caller that is gone. The app changes the policy through
  `PermissionStore.updatePolicy` (read and write in one transaction, throws on a bad read), never by saving a
  default over a failed read.
- *Audit.* A step refused by Stop or Quit wasn't in Activity (its write was cancelled with the run); audit
  rows are now written from a detached task.
- *Shared room.* Other agents may show this Mac's load (D42), but live values have four places beside the
  companion; they together now hold at most two (`WatchLimits.maxActiveExternalReports`), so one steered by a
  hostile repo can't leave the person unable to show their own.
- *Disk.* `FileHandle.write(_:)` raises an Objective-C exception on a full disk, which nothing catches: the log
  writer and the `sidefolk` helper's error output use the throwing `write(contentsOf:)`. A day's log stops at
  16 MB.
*Residual:* a Swift trap anywhere else still ends the process (Swift has no catch for it); the fuzz and crash
regression suites (`NewSyntaxFuzzTests`, `CrashRegressionTests`, `FailClosedTests`) are the guard rails.
Extensions' and MCP servers' own crashes stay isolated in their processes (T15).

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

;; screen=true adds (ScreenCaptureKit and the encoder, measured on macOS 27, D69):
;; (allow mach-lookup (global-name "com.apple.replayd") (global-name "com.apple.windowserver.active")
;;   (global-name "com.apple.coremedia.videoencoder"))
;; udp=true, only with network=true, adds:
;; (allow network-bind (local udp "*:*")) (allow network-inbound (local udp "*:*"))

;; media=true adds (pictures on Apple silicon, measured on macOS 27; a VM's GPU is not among them):
;; (allow iokit-open (iokit-user-client-class "IOSurfaceRootUserClient" "AGXDeviceUserClient"))
;; (allow mach-lookup (global-name "com.apple.coremedia.videodecoder"))

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
- **A compiled Swift program** (every built-in extension, D39): nothing beyond the base rules; Swift and
  Foundation load from `/usr/lib/swift` and `/System`. With `network`, `URLSession` works on the base
  `trustd.agent` lookup and the mDNSResponder socket. Core Image and HEIC or PNG output need `media`.
- **sh:** `/bin/sh` reads `/private/var/select/sh` and execs `/bin/bash`, so allow both. A script's
  external commands must each be listed (`head` was denied).
- **python3:** framework builds (Homebrew and Xcode) re-exec
  `…/Python.framework/Versions/X/Resources/Python.app/Contents/MacOS/Python`; allow it. Homebrew
  needs `/opt/homebrew/{Cellar,opt,lib}` (`ssl` loads `opt/openssl@3`) but not `etc` or `var`.
- **node (Homebrew):** reads OpenSSL's settings, `/opt/homebrew/etc/openssl@<n>/openssl.cnf`, at every start
  and exits when it can't (found on GitHub's runner, whose node uses openssl@4). That one file is readable for
  any OpenSSL version under either Homebrew prefix; the certificate stores beside it stay network-only.
  `/usr/bin/python3` is an xcrun shim that fails in the sandbox; resolve it from the developer folder
  `xcode-select` points at (read from its link, never by running `xcrun`, which offers to install the
  developer tools on a Mac without them) + `realpath`.
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
   aborts. Approval modes (D37): every mode × risk × taint × caller, the invariants in every mode
   (switched-off capabilities, protected places, folder cards, other agents' rules), an unknown or
   old stored mode never loosening Guard, and every wait for an answer ending. Using the internet (D47,
   `InternetRuleTests`): after outside content a new site, a query or fragment, a look-alike host and a data
   label in front of an allowed site ask; an allowed site holds only for reading, only with a site grant, and
   the fetch can't leave it by redirect; a built-in service holds only with the person's grant and is never
   offered "Always" after outside content; someone else's network extension asks with its grant in every rule;
   a built-in service claim never covers files; each built-in service program reaches only its listed hosts;
   "Ask each time" asks in every mode; other callers keep their rules; an unknown stored rule reads as the default.
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
14. **Extensions the AI writes and folders named per call (T27):** drafts refuse non-text files, dot files,
    `..`, an icon and oversize content, and set id and author; drafting is refused in tainted turns and for
    every caller but the user and the agent; the trial can't read a folder the draft asks for; a folder
    named in a call is the only one its process can read, and only read for `"read"`; an unshared folder
    asks the agent and a "no" runs nothing; built-in extensions follow the app, keep the person's choice,
    come back off when they gain a permission, and refuse removal; icons are checked as images only.
15. **Other agents (T4, T28):** a fake MCP client over stdio against a whole Sidefolk sees exactly the
    exposed tools with their external schemas; can't set critical, create a collection, watch localhost,
    run a command watcher or read a web value; cancels only its own reminders; asks before every read
    (`agenda.today` denied reads nothing). Connect's skill: installed once, a foreign file backed up and
    never removed, a linked folder left alone, removed with its empty folder; Codex hooks merged beside the
    person's own, removed exactly, nothing written to Codex's trust state.
16. **Crashes and fail-closed (T29):** huge numbers typed, sent by another agent or stored in a row never trap;
    a stopped task's call is refused with every capability still off and nothing done, and is in Activity; a
    policy that can't be read is never replaced by the default; a seeded fuzz of the time and report syntax
    (`NewSyntaxFuzzTests`). End to end (`Tests/SidefolkCoreTests/E2E`): Full access against a page that tries
    every way out, an AI-built extension in a tainted turn, a skipped Notes copy run later from Now.
17. **Extension commands (T32):** `ExtensionCommandTests`: sentences that could swallow words are refused, slots
    are checked after matching, core intents win, two extensions claiming one sentence go to the AI, a network
    tool asks and honours the AI's grant, "Ask each time" holds, a command can't draft extensions, an `"ai":
    false` tool never reaches the model; `ExtensionCommandBuiltInTests` drives the built-ins' commands through
    the runner.

## 5. What Sidefolk never does

- Never lets the model, routines, external agents or extensions answer approvals, create grants,
  change settings, install extensions or touch Sidefolk's own data (the model's drafts folder is written
  only by `extensions.draft`, T27).
- Never runs model- or agent-written commands without the user approving the verbatim text, unless
  the person turned on Full access, and then never from a turn that read outside content (D37);
  never "always" for high risk. AI-written extension code runs only in a sandbox: once with nothing
  granted to check it, then only after the person installs it from the install preview (T27).
- Never hard-deletes, sets exec bits or strips quarantine, except from its own code: the built-ins it
  installs from its bundle (D39), add-ons after the checks of T33, and a new version of itself after the
  checks of T31.
- Never puts secrets or prompts in argv, logs, SQLite, UserDefaults, child env or exports; never
  sends a key to a host other than its provider's.
- Never listens on TCP in release, and never takes commands via URL schemes, AppleScript or
  distributed notifications.
- Never fetches non-http(s) URLs, or private addresses from model-built URLs; never loads remote
  images.
- Never asks for admin rights, Full Disk Access, Accessibility or Screen Recording; Automation only
  for Notes and Reminders, driven by fixed scripts (T25). Location Services only once the person chose
  their Mac's location, and never coordinates to an AI (T30).
- Never removes anything from another app unless its whole copy is in the notebook and the person
  approved that removal (T25).
- Never offers MCP sampling, roots or elicitation to extensions; never downloads extension code except
  Sidefolk's signed add-ons when the person clicks Get or Update (T33), and never updates one by itself.
- Never edits `~/.claude`, `~/.claude.json` or `~/.codex` without a click, a confirmation and a
  backup; never writes through a linked skill folder, and never answers Codex's hook trust review
  for the person (T28).
- Never runs the brain when isolation cannot be verified.
- Never sends telemetry.
