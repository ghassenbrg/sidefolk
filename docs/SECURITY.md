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
and re-checked at execution. Allow is inert for 800 ms, Return never defaults to Allow on high, and on Today's queue no key says yes at all (D130),
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
writes and memory/skill/routine creation. After D185: Auto asks, in a tainted turn, for every call that
could carry data out (network or open at an untyped address, commands, file changes outside a folder shared
with write access, extension and MCP tools, calendar writes, clipboard and memory writes) and for high risk,
and runs the rest; Full access asks only for text to read in full, by the person's choice (T48). A tainted
card for a step that can carry nothing out (not high risk, nothing to read in full), or for an extension's own
tool that runs no program and names no address or service, offers "Allow for this request" instead of
"Always": that tool runs without a card until the run ends. Network and open calls ask (medium) whenever their
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
(`NetworkReach.service`, an extension or service grant): the weather report (Open-Meteo) and extensions whose
signed manifest names their `services` (D98: only packs Sidefolk signed, origin `official`; anyone else's list is shown
as their word and changes nothing here; a test checks every address in those programs against the list). Those grants come
from a clean turn or from Settings: "Always" is still never offered after outside content, and without a
grant these ask as before, except in Full access (D185, T48). A metric report reaches no network at all
(`NetworkReach.nowhere`). A new site, a query on any site, a watcher, an open, someone else's network
extension or MCP server ask as above. The person's internet rule: *Ask each time* (no grants, no "Always",
and no mode answers for an internet call; even a weather report asks), *Ask once for each site* (the
default), or *Don't ask before reading* (in a clean turn any public page and those services go
without a card, logged `web_setting`, as Auto does for medium; after outside content those services
and the allowed sites do, so a steered place name can reach Open-Meteo, and nothing else changes). Sites can
also be allowed in Settings.
*A device the person paired (D72), for Sidefolk's own agent in Auto and Full access only.* After outside content,
a call that reaches only a device the person paired goes without a card: Full access answers it (`full_access_paired`
in Activity), Auto too unless it's high risk (`auto_mode_paired`); "Ask every time" and "Ask once per kind" ask as
before. What a steered model writes into it reaches the person's own TV and no one else, as with an address the person
typed. It holds only when all of this does: the tool declares `"reach": "paired"` and its extension is Sidefolk's own
(origin `official`, signed by Sidefolk's team; anyone else's declaration is ignored, since the sandbox
can't hold a program to it, as with D47's services); Sidefolk asked the running program (`sidefolk/paired.check`,
never through the model, with only the words naming the device) and it named a device the person paired, whose key
the connection then demands; and Sidefolk bound the call to that device's id before Guard looked, so what runs is
what was confirmed, not whatever answers to the same name by then. A link in the call that the person didn't type
(a video address the TV would fetch), a file not in a folder the person allowed for that very call, a program, a
file change, text to read in full, or high risk keep the card. No answer, a slow one (5 s), or "not paired" leave
everything as before.
Extension and MCP
tool descriptions never reach the model: it gets a neutral line built from the tool title and
extension name, and the schema without its free text (descriptions stay on the install sheet). The
exception is Sidefolk's own signed packs (origin `official`, D39, D55, D98): their descriptions are first-party text and
are reviewed like prompts. The same signature is what lets a tool's `summary` speak for a call on its approval card,
built only from the call's exact arguments; anyone else's summary is never shown (T1). An extension's `examples`, whoever
wrote them, only fill the Ask panel with words the person reads: nothing is sent until they press Return.
Untrusted text is wrapped as `<untrusted source=…>` (closing tag escaped), stripped of invisible
and bidi characters (U+200B–200F, 202A–202E, 2060–2069, FEFF, E0000–E007F) and capped at 20 KB.
That is hygiene, not a boundary. Rendered Markdown never loads remote images; links show the full
host, and open only as web pages (`webLinksOnly`: http and https without a user part; `file:` and app
schemes are ignored, audit F12), in answers and release notes alike. Words that aren't Sidefolk's own, an
extension's error included, are shown verbatim (`Text(ext:)`), never read as Markdown. *Residual:* injection can still steer low-risk actions; extension tool names and titles
(≤ 60 characters) still reach the model. A site the person allowed for good can receive, in a page's
path, whatever a steered model puts there: only that site's owner reads it, so the trade rests on the
person allowing sites they trust (a site where strangers can read who fetched what, a request bin, isn't
one). A signed manifest's `services` is Sidefolk's word for its own code: the sandbox can't hold a program to host
names (§3), so a change to those programs must keep the address test passing. In Full access or Auto, an injected
instruction can put the Mac's screen, a window, or a video the person allowed for that call on a TV the person paired,
or stop, pause or seek what plays there (D72): that is what those modes accept for the person's own devices, with
each such call in Activity as done because of a paired device. Miraya's pin is its own code's word, checked by its tests.

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

*Agents' transcripts (D118).* `transcript_path` comes from a hook, so `ConversationTitles` believes it only inside the agent's own folder and never through a link, reads only the end of the file, parses only lines that declare a title, and keeps only that title, plain and clipped. It reaches the person and not the model.

**T4 Confused deputy via external MCP clients (H/H).** An agent in a hostile repo uses Sidefolk's
folder grants, network or commands to escape its own sandbox. The `.external` profile allows,
without asking: `notes.save` (Inbox or a collection that already exists, tagged; it never creates
a collection), `reminders.create` (at most `attention`, 20 active per client and 50 for all clients
together), `reminders.cancel` (only reminders that client name set, without a card; D160: anyone else's, the person's among them, on a card every time, with "Change notes" not Off, naming the reminder and the one change, and never "Always"; what runs is what the card showed; an important one is never touched; a hostile repo can ask to silence an ordinary reminder, and the card is where the person says no; the person editing the reminder while the card waits runs the card's change on what they wrote),
`reminders.update`, `reminders.snooze` and `reminders.complete` (D157: the same; a reminder tied to an open task can't be finished unless "Change notes" is on Allow, since that finishes the task), `notes.restore` by id under "Change notes", notify/`ask_user`, `status`, non-command watchers (25 active for all clients together, more only when the
person says yes to `watch.more_room`, which always asks, D116; each stopping
after 24 h, or at `until` if it said so when made, up to 7 days (D160: a watch of another agent's can now run that long with no card, and a page it watches is checked for that long; the room is the same, and a live value keeps its own ends. The week is for one start: an agent can resume or make a watcher again, within the room, as it always could, so what bounds it is the room and the floors, not the clock); `WatcherEngine.add` counts and inserts in one actor step, so parallel calls can't
overshoot), their own watchers' pause, resume, display, order and formatting and, by `watch.update`, their name, interval, level and what they look for (`canManage`; D157: no floor, level or lifetime moves that way), and `watch.report` for this Mac's own metrics (cpu, memory, battery, disk, network: no
web values and no weather, which would reach a server; a fast one stops within the hour) (D42).
They see descriptions and schemas written for them (`ExternalToolPolicy.externalSpec`): no
`collection_kind`, no critical level, no command kinds, `source: metric` only. A reminder they tie
to a note or task (`item`, D49) needs its own title: the item's words are never its default, and the
result names the item by kind and id only.
`collections.create` (D160, reversing D42's "never"): another agent can now make a project, topic or list, on a card every time whatever Settings say, and never with "Always". Its name is recorded as that agent's, so it is quoted to Sidefolk's model as outside words (T3). What can't be seen is removed before the card and before the check against About you and the Inbox; letters from another script that look the same aren't caught, and the card shows them as they are. `notes.collection`'s card now says a new name. Reading adds `collections.list` (D160): another agent can now see the names of the person's projects, topics and lists with their counts, under the reading setting, so a card by default; never About you.
The `sidefolk` command's `notify`, `ask`, `remind`, `note` and `call` (D159) are this same client by another door: through `ExternalToolGateway`, with these rules and nothing else, as `sidefolk-cli`. A program running as the person could already start `sidefolk mcp`.
Reading user data (notes, reminders, `notes.get`, `agenda.today`) asks every time; an external caller never gets
"Always". `notes.collection` (D117) always asks too, since naming a collection is what they otherwise can't do; the
name it gives reads as theirs. `notes.update` and `notes.trash` change or trash one note by id (never in "About you",
never into a new collection, never deleting for good: only the person empties the Trash), each undoable
from Activity (D52). Neither may end or reword an important reminder on the note: marking it done, trashing it or changing its title is refused, card or no card (D160, T24); a title also while that reminder has ended, since it would come back with the new words. Settings › Trust › What other agents may do (`AgentAccess`) sets each group (saving,
changing, reading) to Allow, Ask each time or Off; defaults: saving and changing allowed, reading asks.
"Allow" on reads is the person's explicit choice, shown with what it means; Off hides the tools and
refuses calls with a message that names the setting. The closed list itself never changes from Settings. Files, clipboard, open, web fetch, web and weather reports, command watchers, skills,
settings and extensions are not exposed. There is no per-client key: Connect only adds the MCP entry
(after confirmation and backup), any same-uid process can connect, and names are self-chosen and
shown as unverified, so the quotas that matter are the ones shared by all external clients. Rate limits: 60 calls/min and 4 concurrent per connection, 120 calls/min for all
external clients together, and 600 session/job/status messages a minute for the whole socket.
External callers can never answer approvals. E9 ("ping me when tests pass") needs only notify or a
process-exit watcher, not command watchers.

*Sidefolk's own agent reading History (D160).* `history.recent` lets the companion read short lines of what each agent and Sidefolk did and what the person was told: not arguments, outcomes, a notice's body or conversations. A row's summary can quote what a tool was given (a copied text, a command, an address), which History never meant for a model, so summaries are quoted only for tools whose words the AI can read anyway, with secrets out (T20) and only words shaped like plain words kept, so a slash, an at sign, a colon or a query inside a word with an ASCII letter takes the word out, in any spelling the compatibility forms fold; for the rest the line says only which tool ran, and a notice from a command, a watch, a session or an extension is told by its kind. New data for the model, so medium risk with a card (once per kind unless they choose otherwise; by D37, none in a clean turn under Auto or Full access), and always outside content, since other agents and pages wrote those words (T2). A self-chosen client name can't read as the person: anything but a known agent's name shows as calling itself that; a client naming itself "claude" still shows as Claude Code, unverified like every name here. Accepted, for now: an agent's notice and question titles are in these lines though the AI couldn't read them otherwise, since "what did it tell me" is the point, and `Redactor` is patterns, so a secret it doesn't know in such a title or a note's title can reach the model, as can a bare host name, a secret on its own that reads as a word, or anything with no ASCII letter and no slash, such as a host and port with a query, or a sign-in in another script or in accented letters only. `sidefolk notify "$(cmd)"` makes a command's output such a title. Other agents never get it: `ExternalToolPolicy` is by name and closed. `agents.sessions` likewise lets it see which agents are running, their project folder's name and their state, on a card, as outside content; a conversation's title, its first prompt and what a session last said stay out (D118).

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
- Only from the copy on the person's own data folder. A copy on any other `SIDEFOLK_HOME` (dev, QA) writes
  stand-ins inside that folder (D86), the `sidefolk` command link included: its helper goes away with the
  folder, and the person's agents pointed at it would fail on every start.
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
1. Grants come only from the person: `NSOpenPanel`, Settings, a folder card, or a page's `share` question (D180). That is user intent. The panel also satisfies TCC
   for Documents, Desktop and Downloads; otherwise TCC asks on the first read. The `realpath(3)` is stored; `isInside` resolves it again at each check, so a grant follows a link swapped in at its own path.
2. Denied as whole subtrees, even inside broader grants (`FolderAccess.forbiddenReason`):
   `/System`, `/Library`, `/usr` (with `/usr/local`), `/bin`, `/sbin`, `/opt` (Homebrew's `bin`,
   `lib`, `Cellar`: a planted `claude` or stdlib file would run as the user), `/Applications`,
   `/cores`, `/dev`, `/private` except `/private/tmp` and `/private/var/folders`, other users'
   homes and `/Users/Shared`, `~/Library` (LaunchAgents, Keychains), `~/Applications`, `~/bin`,
   `$HOME` dot-dirs (`~/.ssh`, `~/.claude`, `~/.codex`, `~/.local`), and the Sidefolk data root and
   `$SIDEFOLK_HOME`. Never grantable as a whole: `/`, `/Users`, `/Volumes` and each volume's root,
   `$HOME` itself, `/private/tmp`, `/private/var/folders`. The same check gates extension
   `files.read`/`files.write` and file watchers.
   - *One hidden file by its facts (D180).* A `watch.create` of kind `file_changes` or `file_appears` may name a path with a hidden part, which `ToolScope.factsOnly`
     says. It reads size and time only: no text is read or kept (`FileChangesProbe`), nothing is offered to open, and every other rule in this list still refuses it (other
     homes, `~/Library`, the Sidefolk root). Guard asks on a card with no "Always", or the call fits a plan the person read that names the path; the person's own request
       runs; other agents are refused. A hidden folder is never watched, and never grantable. `folder_new_file` stays refused, since names are more than facts. Nothing in the
     stores of keys and agents' settings (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.config`, `~/.local`, `~/.claude`, `~/.codex`) is watched even so.
     What's asked comes from the path as named (`isNamedHidden`). After the yes `prepare` checks what it asked about: really hidden, with no link anywhere on the way below home,
     not a folder, and no store as named or resolved. A folder coming to be there stops it, and editing a watch keeps what it resolved to. Protected places count as named too,
     for every tool, so a link in an extension's own data folder is refused before anything follows it. What's still told: a caller that can write a link somewhere it's allowed
     to, outside those, can learn from `ask` or `deny` whether its target exists and whether it's a protected or hidden place. That's T10's refusal as it has always been, names
     no words, and is accepted. A link swapped in after a watch is made stops it at the next look. Accepted: a process already writing as the person can swap the file for a link between the card and the watch being made, and the plan holds the
     path as written. Each look after that stops if a link appeared (`WatchedPath.resolved`).
     Reviewed independently in rounds. The last read passed with notes; made after it, and read by no one independent: `isNamedHidden` as a condition in `prepare`, the check when a
     stopped watch is brought back, and store names and protected places matched case-blind and, for stores, on any part of a path. All of these only refuse more.
   - *A folder asked for from a page (D180).* A page's `share` names a path; Sidefolk works out the folder with `suggestedFolder` (so the rules above apply) and asks in its
     own words, naming the extension. The extension's words aren't in the question, it can't press the button itself, and only `.user` reaches `folders.share`, which
     `grantFolder` checks again. It's a grant like Settings', without the open panel: TCC still asks for Documents, Desktop and Downloads on the first read. Before the click
     `sidefolk/tools.check` tells an extension only that the path it named needs sharing, from the path as written: one bit beyond `why` remains for a link right under a too-broad folder that resolves to one.
   - *A watch's rest (D180).* `cooldown_minutes` lets Sidefolk's agent and other agents (T4) shorten a watch's quiet after it fires from 30 minutes to 5, no further; an extension's
     own watch, which rings no one, has none unless it asks. Each still keeps its kind's shortest interval.
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
- Watchers the user asks for themselves (typed in Ask or the Say bar, or made with a button: caller
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
dropped file grants a one-turn read of that file only; dropped items are never opened or run. An extension is a second possible reader, for one call and only after the person chooses its offer (T43, D141).

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
added), reaches the app with Sidefolk's grant. The same goes for Finder once the person has said yes for the ring's shortcut (T49). Recently Deleted is recognised by its name (English, and Notes'
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
- Updates are reinstalls with a permission diff and a tool diff. An app update never touches an installed extension
  (D98): the seed packs it carries are installed once, and only on a Mac that hasn't had them.
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
they run programs can fork at all. The data folder's contents are the program's, but the folder itself is Sidefolk's: the profile denies creating or removing that path, and whatever isn't a folder there is removed at start and never followed.

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
not ignored. Conversation history can also be deleted on its own, one conversation or all of it (History,
Settings › Trust, D45): the thread's runs stop first, then its exchanges go and the "last sent"
preview with them; Activity keeps its audit record. A result pinned in Ask is kept on purpose until it is unpinned, cleared or its conversation deleted, past the retention below, as a note would be (D136). Retention is applied at launch and then daily while Sidefolk
runs: conversation history (7 days by default), Activity and AI run records (90), finished `sidefolk run` jobs with their stderr tails (14), sessions
(14), the notebook's Trash (30); log files after 7 days, at most 16 MB a day. Bound parameters only; FTS5 terms quoted. Encryption at rest
relies on FileVault (stated on the Privacy page). P1: a Keychain-keyed HMAC over grants, folders,
extension pins, command watchers and the Guard policy (the approval mode, D37), so tampered rows are
ignored.

*Backups (D91).* A `.sidefolkbackup` holds the person's data in the clear (like the JSON export): it is written 0600
and the sheet says what it holds. Keys are left out unless the person chooses a password: then AES-GCM under
PBKDF2-SHA256 (600,000 rounds, random salt), and Sidefolk never stores the password. A restore trusts nothing it hasn't
checked: entries that would leave the folder are refused before unpacking (`zipinfo`), links and special files are
refused, every file must match the manifest's SHA-256 and no other file may be there, and a database whose migrations
this copy doesn't know is refused. What can act is never restored as is: gallery add-ons are fetched again and their
signatures checked (T33); extensions and companions from a folder wait for the install sheet or D60's question; MCP
servers come back switched off; only key names Sidefolk uses are written to the Keychain, and the values they replace
wait for Undo restore sealed in the undo folder under a random key kept in the Keychain, never in the clear; only an
allow list of the app's own defaults is set (`BackupPreferences`), never its language or macOS's keys. Skills and notes come back as
data, so the sheet says "Restore only a backup you made yourself" (a stranger's backup is a stranger's text in prompts,
T2). The swap happens before the database opens, and what it replaced is kept 7 days for Undo restore; agent configs
are never touched (D86).

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
| Markdown links | Web pages only (`webLinksOnly`); other text verbatim |
| Network extensions | Install warning; only signed manifests' services (`services`, address-checked, D98) skip the taint rule (D47), and Sidefolk's own extensions' calls to a device the person paired, confirmed and bound per call, in Auto and Full access (D72) |
| MCP servers | Labelled as unsandboxed |
| External agents | T4 |
| Clipboard | T12 |
| Calendar events (read, and written once allowed) | T34 |
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
  is held (T26), and Automation for Notes and Reminders (T25) and for Finder once the person presses the ring's shortcut (T49). Never Full Disk Access, Accessibility or
  Screen Recording.

**T23 Supply chain (L/H).** GRDB and KeyboardShortcuts use `from:` ranges, and
`Package.resolved` is committed. Release builds run `swift build -c release
--only-use-versions-from-resolved-file` *(flag verified)*. Review revision diffs on bumps; no
binary targets or build plugins from dependencies.

**T24 Attention spam and runaway watchers (M/M).**
- Attention: at most 3 items per source per 10 min, and 6 for all sources of one self-named kind
  together (every external agent, every session, every extension), then held; whispers 6 per
  source (or kind) and 12 in all per 10 min, then the count only. A slot is reserved in the same actor
  step as the decision, so concurrent posts can't all pass. `critical` only from reminders,
  watchers and the user's own actions (`AttentionPolicy.criticalSources`; callers never post under
  those names), and only user-created reminders and watchers are stored as critical (for reminders,
  `user` and `user:agent`, enforced in `ReminderScheduler.create` whatever the caller asked). Only
  the user's own reminders fire as `reminder`, which skips spacing so they arrive on time; anyone
  else's fire as `reminder:<kind>` (`reminder:external`, `reminder:agent`…), wait their turn and
  never say "You asked" (the card keys on `refKind`, which stays `reminder`). A second answer to
  the same item is dropped. The `com.apple.screenIsLocked`/`Unlocked` notifications are only a
  hint, since any process can post them: the app must confirm with `ScreenLock.isLocked`
  (`CGSessionCopyCurrentDictionary`) before holding or releasing items. Identical titles within
  10 min are not yet deduplicated.
- Watcher floors: web 5 min, site 60 s, command 60 s. Reports (D35): metrics 5 s, weather and web
  values 60 s (still one request a minute per host), command output 10 s; at most 3 shown beside the companion (the rest run hidden, D116),
  ending after an hour or a day unless the user said "until I stop it". `watch.report` is offered
  to external agents for this Mac's metrics only: a web value would let them read pages through
  Sidefolk (T4). A web value or a
  command's output is untrusted in the tool result (T2). The person's own have no count since D116: these floors and the four checks at once bound them. Other agents have a shared room (T4).
- At most 1 request per minute per host, backoff up to 6 h, default expiry 30 days (24 h for
  external agents' watchers, or `until` up to 7 days, D160). Quotas are counted in the same actor
  step that makes a watcher active.
- A watch's history (D87) stays on the Mac in the database (T19): its checks for 30 days and at most 500 rows,
  and the last two versions of the text it compared, 32,000 characters each, extracted text only (never a page's
  HTML; a file only when it is a small plain text file in a folder it may watch), with invisible and
  bidirectional controls removed (T2). It is deleted with the watch, exported and deleted with "Your data", and
  never given to a model: `watch.list` says when a watch last changed, and repeats the notice's words only for
  kinds whose summary is built from the watch's own settings. *Amended 2026-11-05 for questions:* a question (`refKind` "ask") has a caller waiting on its answer with a time limit of its own, so the 90-second spacing and the notice budgets could make it run out unseen. Questions skip the spacing and have their own budget, `questionsPerSourceLimit` (12 per source per 10 minutes, twice that per family, so a new client name doesn't buy more), and past it they wait, reachable from the count. Each question holds its caller until it is answered, dismissed or timed out, and a question in front isn't folded by a new card. *What's left:* within the budget, a program can still put a dozen questions a window in front of the person, counted apart from notices so that they can't use up what notices may do; a notice card behind a question waits for it, at most until its time limit, while a reminder or an occurrence comes up in front of it and it comes back after; dismissing one more than a few times can't turn a source down, since `Interruptions.mustReach` keeps questions from being lowered.

**T26 Voice: the microphone and a cloud voice (M/M), D34.** The microphone opens only while the
person holds the talk key or the companion (off until voice input is turned on; macOS asks on the
first hold), so the orange dot is an honest sign; nothing listens otherwise and there is no wake
word. Recognition runs on the Mac (SpeechAnalyzer, or the older recognizer forced on device); audio
is never written anywhere, and the words go through the normal Ask pipeline as the user's own
request, so Guard, approvals and Undo apply unchanged and voice is never the confirmation for
anything. Spoken replies with ElevenLabs send the words being said, including reminder and note
titles read back, to api.elevenlabs.io: chosen explicitly in Settings › Brain › Voice, which says so. Its
key lives in the Keychain bound to that host (as T18), requests are never redirected, and the key is
removed with everything else. Replies stay silent while another app records and in Quiet.

**T30 Where the person is (M/M), D48.** Off until the person chooses in Settings › Trust › Your location;
- *What extensions may be told (D106).* An extension may have the person's place only after their yes to Sidefolk's question, per extension, bound to its pinned purpose and whether it has the internet; an update changing either asks again. It gets the same two-decimal coordinates and town name the weather uses. A program with `network` can send them anywhere, and one of its tool replies can put them before a model: the question says the first, and the install sheet too. This is the one exception to "only weather lookups use them".
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
  mark after the checks. They are never installed without the person's click, except the seed packs (D98): a fresh
  Mac installs the few on the app's list once, from packs inside the app, whose list the app's signature seals, each
  still checked for size, digest and the gallery's signature and on a Mac that has never had them; refused ones aren't
  installed. A removal is remembered, so they never come back by themselves. An update installs
  by itself only while "Update add-ons automatically" is on and only if it widens nothing the person agreed to
  (D70: no new permission, judged on the permissions themselves, no tool riskier than before, no `background`);
  otherwise it waits for the same install sheet. Its pack is fetched and checked exactly as a click would.
- *A stolen GitHub account* can replace files in the release but can't sign them. A stolen Developer ID key is
  answered by Apple's revocation, as for the app. Downgrades: an older signed pack the catalog lists would install
  only if the person chose it; the gallery offers Update only for a newer version.
*Residual:* the catalog's text (names, taglines, descriptions) is shown in Settings; only official entries' words
reach the model, as one line each.

**T34 The person's calendar (M/M), D57, D97.** Off until the person chooses "Show my calendar" (Settings › Trust ›
Your calendar, or Today); until then nothing is read, the AI isn't offered `calendar.today`, and macOS is never
asked. Choosing it asks macOS once for full access (`NSCalendarsFullAccessUsageDescription`, and the hardened
runtime's `com.apple.security.personal-information.calendars`); reading the state never asks.
- *Changes only once allowed (D97).* Until the person allows changes (a sheet at the first change, or Settings ›
  Trust › Your calendar), EventKit is only queried. Then `calendar.create` (medium), `calendar.update` (medium) and
  `calendar.delete` (high, asked every time, never "always"), capability `calendar.write`, are the only code that
  writes, through `ToolExecutor`, for the person's own drags and clicks too: Guard decides, History logs, Undo puts it
  back (a deleted event is recreated from its kept copy). They refuse an event with attendees (a change sends notices
  to other people), a calendar that can't be changed, and anything but one time of a series; Sidefolk never adds
  attendees, so no change of its own invites or tells anyone.
- *The AI.* Offered the write tools only while changes are allowed. After outside content (an invitation's title is
  outside content) no mode answers for the person: `calendar.write` is in `couldCarryOut`, because a calendar syncs to
  the person's accounts and may be shared, so an event's title or notes can carry words out. Other agents get none of
  these tools (`external: false`).
- *Hidden calendars* are left out of everything that reads (Today, the brief, `calendar.today`).
- *Where events go.* Today and the morning brief, on this Mac. Attention items, where the brief lands, never reach
  the model's context.
- *What the AI hears.* Only through `calendar.today` and `calendar.find` (D158, any stretch up to 90 days, or by its words): medium risk, "Reads private data", through Guard like any
  tool, so the person is asked (once per kind unless they choose otherwise). The result is untrusted (T2): an
  invitation's title is written by whoever sent it. Other agents get no tool that reads it (`external: false`).
*Residual:* once allowed for good, the AI may read the day's events in any later clean turn, and add or move events
in a clean turn; a calendar someone else shares with the person and lets them edit is changeable like their own (its
owner sees the change, as with Calendar).

**T35 Themes (L/M), D58, D64, D84.** A theme is data: `theme.json` (64 KB at most) and PNGs (2 MB and 2048 px at most,
inside its folder, decoded and written again by Sidefolk before use), never code, never words shown as the app's.
Since D84 a theme only dresses the app: each place has one layout, so what needs you (Guard's questions) is always
in the same place and no theme can hide a waiting approval; older layout keys are decoded and ignored. Ids under `dev.sidefolk.` and `harbor` are
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
- *A paired TV* (D72): Miraya pairs by the six digits on both screens, pins the TV's certificate (SHA-256 of the
  whole certificate) and checks it on every later connection before its token or anything else is sent; a TV it
  can't match by key is a first contact, and nothing is shared until the person compares the code. A device that
  advertises a paired TV's name never stands in for it (a paired TV comes first for the same words), and one that
  advertises its id or takes its address fails the pin. That is what lets Guard answer, after outside content, a call
  Miraya confirmed reaches only a paired TV.
*Residual:* a screen-recording extension with the network could send the screen anywhere; the sheet says it in those
words. The TCC grant isn't per extension. In Auto and Full access, an injected instruction can show the screen on the
person's own paired TV (D72).

**T37 Games in the Play panel (closed, D101).** The game channel and its panel are gone: everything Playtime shows is a surface (T40), its AI help T41, and the companion's reactions the fixed lists of `CompanionCue`, with no words. A cue's `line` had no form on a surface, so an extension can't make the companion speak on the desktop or aloud.

**T38 Temporary output mute (M), D81.** An extension can request Sidefolk's device-wide output mute only when its
pinned install permission `output_mute` is true; the install sheet names the effect on other apps and an update adding
it is not automatic. This capability does not open CoreAudio or process-fork in the extension sandbox. A Sidefolk-owned
helper holds the lease outside the extension's killed process tree, restores the prior mute state on stdin EOF, and
tracks default-output changes. The host releases the lease when that extension stops or crashes, serializes ownership,
rejects stale request sequences, and limits starts to five per ten seconds. Trial installs disable this capability. A mute request is not a substitute for
ToolExecutor: page and agent actions still invoke the extension's tools through Guard and audit. Since this is an install
permission, an extension with it may request muting while running; the sheet must not claim that Sidefolk enforces the
extension's own promise about when to ask. If the helper or an output cannot restore, Sidefolk reports the failure and
does not grant another lease while restoration remains uncertain. The helper was also checked against the Mac's actual
default output: its original state was restored on normal closure and after killing the parent process.


**T39 Trivia from the person's AI (closed, D101).** The narrow path for one extension is gone; every extension's use of the AI is T41, and the program itself checks what comes back (Playtime: `TriviaPackCheck`).

**T40 Extensions' surfaces, scenes and pack assets (M/M), D99.** An extension can now show its own pictures and words
in a window beside the companion, play its own sounds and take clicks and keys there. Three things could go wrong.
Mitigations:
- *Spoofing:* a surface is always framed by Sidefolk with the extension's icon and name (and, unless it is Sidefolk's own, its
  author or "not from Sidefolk"), drawn outside the canvas it can reach (`SurfaceFrame`); the extension can't remove it or draw on it:
  layers clip to the canvas, and a text field, the one real view a scene can have, is cut to it (`SurfacePolicy.fieldFrame`). Only a
  signed pack may be named Sidefolk or a companion (`ExtensionReservedNames`, in every language it carries). It can still draw a picture of an approval card
  inside its canvas, so what makes that harmless is where it stands and what it can catch: its window level is below
  Sidefolk's own panels and cards (one under `.floating`), so it can never cover one; it is placed clear of them
  (`SurfacePolicy.place`); opening Ask, where permission slips stand, puts a surface panel away; and while an approval
  waits (`mood.approvals`), every surface dims and takes no click, key or field (`SurfacePolicy.takesInput`), so it can't
  catch a press meant for the card. Its keys go to it only while it has the keyboard, which it takes only when the person
  opened it (D75: the AI's waits for a click; an overlay never takes it). Command keys never reach a scene; ⌘W, ✕ and Esc are
  the frame's, and if a scene takes Esc, two in a second still close it. Back is the app's control. The danger red
  has no token name in a scene (D78). *Its words stay inside its surface:* a reaction has no text at all, cues carry no
  line, and `{companion}` is filled in at draw time, so the name never comes back. What it says through VoiceOver is said with its
  name, at most every 2 s, and only while it is on screen. Activity's row is in Sidefolk's words
  from typed values (an outcome, two numbers).
- *No side door:* `surfaces.open` is low risk with no card because it carries nothing a model chose: from a model only the values
  `surfaces.<n>.arguments` lists, and a tool's reply opens only what its manifest declares, in answer to a call Guard already weighed, with
  the AI's opening only what is marked `ai`. A routine, another agent or a watcher opens nothing.
- *Unattended:* only the person's moves count as attention (`SurfaceAttention`): clocks can't keep an overlay up past its minute, stop after 600
  with no one there, and nothing runs, sounds or is said once a surface is put away, whatever reply is still on its way. It closes when an
  update replaces its program or the crash limit turns it off, as when it is removed.
- *Resources:* a scene's bitmaps are capped at 96 MiB and a flip's samples count in the 6000 points, on the reader's side, so a small scene
  can't take the app down or stall the main thread; pictures in a page's data folder reach ImageIO only if they start as PNG or JPEG, since the
  program can change them at any moment.
- *Decode safety:* an asset is read only from the extension's installed, locked copy, by a path that `PackAssets.clean`
  accepts (plain relative names, no `..`, nothing hidden, no scheme), each part `lstat`ed so a link is refused, its
  bytes matching the install's pin (T14) every time. Before any pixel is decoded, ImageIO reads the header alone: the
  content type must match the name (PNG, JPEG, WebP, HEIC; SVG, PDF, GIF and TIFF are refused, as they can point out or
  animate), one frame, at most 3000 px a side and 6 million pixels, 4 MiB; a decode goes through a thumbnail at the size
  drawn (never larger than the caps, whatever the header claimed), off the main thread where it can, and a failure draws
  nothing. Sounds: WAV, AIFF, CAF or M4A, up to 2 MiB, 10 s, 96 kHz, stereo, converted to the mixer's format. The validator
  runs the same checks at install. Sounds follow the person's speaker (off by default), Quiet, a fullscreen app and
  macOS's interface sounds, at one fixed volume, four a second.
- *Resource caps:* a scene is at most 64 KB (the channel's limit, as are 2 s a reply, 20 moves a second, one surface in
  each place), 1500 nodes, 16 deep, 400 pictures of 64 files, 400 areas, 160 keys, 8 timers, 24,000 characters, 6000
  animation points, 40 repeats, 120 s a timeline: going past one refuses the scene, and it ends. No animation runs for
  ever, so a surface always comes to rest, and at rest no timer or display link runs (measured in D99). Decoded pictures
  are held within 96 MiB and dropped when it closes. An extension can't push: it answers moves, and `after_ms` is
  capped at 600 in a row with no one touching it. An overlay goes after a minute. A pack's assets are at most 48 MiB, 512 files.
- *It is no side door:* a scene is data; moves are typed and sent only if the scene on screen offered them
  (`SurfaceSession`, `SurfaceMove.offered`), never tools. Text is cleaned as on pages and never reaches a model. The
  person's companion and the person are nodes it can place, drawn by Sidefolk, with no channel back: no snapshot, no
  pointer (only a press's area, a drag's ends and a typed entry). `surfaces.open` goes through `ToolExecutor`; the AI can
  open only a surface whose manifest says `ai`. Turned off or removed, the surface closes at once.
*Residual:* ImageIO and AVFoundation decode files the extension's author chose, in Sidefolk's own process; the caps and
pinning narrow that, and a gallery pack is signed, but a flaw in those frameworks would be reachable from a local pack the
person installed. A clever picture inside the frame can still look like something it isn't; the frame always says
whose it is, and it can catch nothing while a real card waits. An overlay's transparent pixels pass clicks through by AppKit's
own rule, which wasn't tested with a real pointer.

A tool's reply can open its surface with arguments of its own, which `surfaces.open`'s filter on a model's words doesn't touch: a model could otherwise start something by itself with free words from a page it read (a topic that spends the person's AI, in Playtime's case). `trusted_only` on a tool drops such arguments in a tainted turn, in `ExtensionTool.run`, before the program hears them (D101). History's row and a Guard card still show what the model asked.

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
- *Shared room.* Other agents may show this Mac's load (D42), but live values have three places beside the
  companion (D116); they together hold at most two (`WatchLimits.maxExternalBeside`), and past that theirs run hidden,
  so one steered by a hostile repo can't leave the person unable to show their own. What they set around a value is
  at most 8 plain characters.
- *Disk.* `FileHandle.write(_:)` raises an Objective-C exception on a full disk, which nothing catches: the log
  writer and the `sidefolk` helper's error output use the throwing `write(contentsOf:)`. A day's log stops at
  16 MB.
*Residual:* a Swift trap anywhere else still ends the process (Swift has no catch for it); the fuzz and crash
regression suites (`NewSyntaxFuzzTests`, `CrashRegressionTests`, `FailClosedTests`) are the guard rails.
Extensions' and MCP servers' own crashes stay isolated in their processes (T15).

**T41 What any extension declares: commands, entries, settings, a History row, the person's AI (M/M), D100.** New reach for every extension, so each has its limit.
*Commands can't shadow Sidefolk or an approval.* Sidefolk's own understanding runs first, always; a command or a surface's sentence is only what is left, whole sentences only. A sentence that answers an approval, in any of the ten languages, is refused at install (`CommandSentence.approvalWords`), warned about in a copy already here, and never matched, so typing it never reaches an extension. A translation follows the same rules and may name only its English sentence's slots. A sentence two extensions claim goes to the AI, not to either. A free-text slot still can't start a sentence, a part must have words of its own beside anything but an enum, and a command runs as `Caller.command`: Guard asks as it does for Sidefolk's agent, and a command can't approve anything.
*Entries and drops can't pass for Sidefolk.* Titles are plain, clipped text in Sidefolk's own menus and Ask's tabs, and anyone but Sidefolk's own extensions shows its name beside them (`shownTitle`, a tooltip for all in the menus); the drop card names the extension. A click runs only that extension's own tool, as the person, through Guard; a file reaches it only through a parameter the tool lists in `paths`, so Guard checks it and the sandbox opens it for that call. Patterns are globs matched in linear time, never regular expressions.
*Settings aren't a channel.* Values are checked against the schema, stored by the host where the extension can't write, given only to that extension. `extensions.setting` takes the person's click or the extension for itself; models and other agents are refused and never offered it, because keys and titles are author text (T2). `settings_from` and `carries` are honoured only for `origin.firstParty` (signing identity, D98): a section of Sidefolk's settings, a value of its store or a row of History is never given to anyone else. An unsigned copy taking a signed one's id starts with no settings and no grants, and the sheet says so.
*The AI, cost:* `permissions.ai` is on the install sheet as a caution, with purpose and cap; a raised cap holds the update (D70). The host counts per day in its own store (a relaunch doesn't reset it, a failed call counts), one request at a time, a hard ceiling of 200 a day and 8,000 characters and 32,000 bytes each, identical words free for the day. The person's switch is per extension and every request is in History and in usage.
*The AI, exfiltration:* the model gets Sidefolk's fixed frame and the extension's words, marked as untrusted data, and nothing else of Sidefolk's. One exception would have been Codex, which always adds the person's own `AGENTS.md` with no switch (T7's residual), and here the answer goes to a program: so while that file holds anything, requests aren't sent (`CodexBackend.hasUserInstructions`, reason `off`, and the switch says why). That leaves: no tools (`oneShot`, an empty toolbox and one step), no memory, notes, conversation or location; so there is nothing of the person's to steal through it, and no way to make it act. An extension can only learn what it sent, which it already had. The answer goes back to that program alone, cleaned and capped, never to the conversation, a model or the companion's mouth (D98's rule 4); `extensions.ai_help`'s own result carries only who wrote it, and History keeps the label and the first 200 characters. It can spend quota, within the cap, in the background: accepted, because the row shows it and the switch ends it. Injection through the prompt reaches a model with no tools whose words return to the same untrusted program. The answer is untrusted for the extension too: the Kit's docs and the skill say to validate it, and a page's text limits apply when shown.
*History rows are marked.* `extensions.activity` writes one row at most every five seconds, `sidefolk/settings.set` one setting a second (none for an unchanged value), a surface's `over` a row only after a person's move; each cleaned and clipped, with at most 8 marks on a character so a cap in characters bounds bytes too, named as the extension's and reachable only as itself; rows are never offered to a model as instructions. Those in its own words go when it is removed; those of what its tools did stay, as the record.
*Pictures.* A page names a pack picture by a plain relative path (no `..`, no address, no hidden part) in the pack's `assets`, read only if its bytes match the install's pin, at most 4 MiB, one frame, decoded to the size drawn. `{"companion"}` and `{"person"}` are placed by Sidefolk: the extension never receives those pictures.

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
  (global-name "com.apple.system.opendirectoryd.libinfo")
  (global-name "com.apple.system.DirectoryService.libinfo_v1")
  (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent")
  (global-name "com.apple.logd"))

;; what dyld/libSystem/interpreters need
(allow file-read-metadata)                       ; stat for path resolution (leaks existence outside /Users)
(deny file-read-metadata file-test-existence (subpath "/Users") (subpath "/System/Volumes/Data/Users"))   ; opened again for what it was given and the folders above that
;; last, under both names: other extensions' data stays closed, and the folder that holds it can't be listed
;; (deny file-read-metadata file-test-existence (subpath ALL_DATA)) (allow ... (literal ALL_DATA) (subpath DATA_DIR)) (deny file-read-data (literal ALL_DATA))
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
;; (allow mach-lookup (global-name "com.apple.coremedia.videodecoder") (global-name "com.apple.trustd.agent")
;;   (global-name "com.apple.audio.AudioComponentRegistrar"))

;; network=true adds (all-or-nothing, see limits):
;; (allow system-socket) (allow network-outbound (remote ip "*:*"))
;; (allow network-outbound (literal "/private/var/run/mDNSResponder"))  ; DNS
;; (allow mach-lookup (global-name "com.apple.trustd.agent"))
;; (allow file-read* (subpath "/private/etc/ssl") (subpath "/opt/homebrew/etc/ca-certificates"))
```

**What "can't use the internet" promises** *(tested on macOS 27, 2026-11-03)*: an extension without `network`, `media`, `ai` or `place` has no way found to connect off the Mac on its own: TCP, UDP, DNS, URL loaders and every Mach service it can reach were tried. Real packets leaving the Mac, directory-bound Macs and interpreted runtimes weren't. The promise has limits, stated here so that no sheet or card says more:

- **`media` keeps the certificate service.** Writing HEIC or AVIF needs it (the encoder's signature is checked), and it can fetch from an address a certificate names, so data can leave that way. Those extensions show a warning instead of the promise.
- **`ai` and `place` carry words out through Sidefolk,** by design: up to 8,000 characters to the person's AI, and 80 to the place search. Sidefolk warns about both on the drop card.
- **Two extensions working together** can pass data through a process's command line, which other processes of the same user can read. No sandbox rule stopped it. If one of them has `network`, data can leave. That's why the drop card says an extension can't go online *by itself*.
- **Anything can read** other same-user processes' command lines, the Mac's serial number and its MAC addresses. An extension with `network` could send those.
- **Other processes' paths:** an extension can read the working folders and open files of other processes of the same user. No sandbox rule fully stopped it.
- **File names outside `/Users`:** a lookup by inode number still resolves names elsewhere on the disk, such as in `/Applications` and `/private/var`, though no file's contents. Under `/Users` it finds only what the extension was given and the folders above that, though it can tell a used file number from an unused one, so files can be counted, not named. Under `/Users`, a path that reaches something through a link outside what the extension was given no longer works. A home outside `/Users` gets none of this. `/Users` and the home folder always resolve by name; a link outside `/Users` that points to a given file still works; and two places outside the extension's own can always be read, `/private/var/db/timezone` and `/private/var/select/sh`.

**What runtimes need to start** *(verified)*:
- **Every runtime:** read on `/` itself (without it even `/bin/echo` aborts), `/usr/lib`,
  `/System` (holds the dyld shared cache) and `/usr/share`; map-executable on `/usr/lib` and
  `/System`; `/dev/null` and `/dev/urandom`; timezone files; broad `file-read-metadata`;
  `sysctl-read`.
- **A compiled Swift program** (every one of Sidefolk's own extensions, D39): nothing beyond the base rules; Swift and
  Foundation load from `/usr/lib/swift` and `/System`. With `network`, `URLSession` works on the
  `trustd.agent` lookup and the mDNSResponder socket. Core Image, HEIC or PNG output, and writing compressed sound need `media`.
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
   A paired device (D72, `PairedDeviceTests`, `MirayaPairedCheckTests`, and Miraya's own tests in sidefolk-addons):
   answered after outside content only in Full access and Auto, only for Sidefolk's own extension, only once its
   program confirmed it and the call is bound to that device; a link the person didn't type, a file from a folder
   shared for good, a program, a file change and high risk still ask; a copy installed from a folder is never asked;
   a device with a paired TV's name never stands in for it, and a different key fails the pin.
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
    asks the agent and a "no" runs nothing; seed packs install once and stay gone when removed (D98); icons
    are checked as images only.
15. **Other agents (T4, T28):** a fake MCP client over stdio against a whole Sidefolk sees exactly the
    exposed tools with their external schemas; can't set critical, create a collection, watch localhost,
    run a command watcher or read a web value; cancels only its own reminders; asks before every read
    (`agenda.today` denied reads nothing). Connect's skill: installed once, a foreign file backed up and
    never removed, a linked folder left alone, removed with its empty folder; Codex hooks merged beside the
    person's own, removed exactly, nothing written to Codex's trust state.
16. **Surfaces and pack assets (T40, D99, `Tests/SidefolkCoreTests/Surfaces`):** the validator's caps, hostile pictures
    (a wrong type, an SVG with a link, truncated, a header claiming 60000 × 60000, too large), sounds past their caps, links
    and hidden files in the folder, the total budget, a file changed after install; node, depth, picture, area, key and timer
    limits; an area without a label isn't offered; moves only for what the scene on screen offered, down to the
    channel; the focus rules (the keyboard only when the person opened it, an overlay never, Esc twice always closes,
    command keys never); placement clear of cards; a surface going with its extension.
16. **The calendar's changes (T34, D97, `CalendarWriteTests`):** nothing is written until the person allows
    changes; an event with attendees, a read-only calendar and a calendar that can't take changes are refused;
    create, update and delete each undo (a deleted event comes back with its alerts) and each is in History; the AI
    is offered the write tools only once changes are allowed; a tainted turn in Auto still asks, and Full access runs it (D185); hidden
    calendars are left out of every read.
16. **Crashes and fail-closed (T29):** huge numbers typed, sent by another agent or stored in a row never trap;
    a stopped task's call is refused with every capability still off and nothing done, and is in Activity; a
    policy that can't be read is never replaced by the default; a seeded fuzz of the time and report syntax
    (`NewSyntaxFuzzTests`). End to end (`Tests/SidefolkCoreTests/E2E`): Auto against a page that tries
    every way out (each waits), and Full access against the same page (only a skill waits, D185), an AI-built extension in a tainted turn, a skipped Notes copy run later from Now.
17. **Extension commands (T32):** `ExtensionCommandTests`: sentences that could swallow words are refused, slots
    are checked after matching, core intents win, two extensions claiming one sentence go to the AI, a network
    tool asks and honours the AI's grant, "Ask each time" holds, a command can't draft extensions, an `"ai":
    false` tool never reaches the model; `ExtensionCommandBuiltInTests` drives Sidefolk's own extensions' commands through
    the runner.

17. **What extensions declare (T41, D100, `Tests/SidefolkCoreTests/Extensions/ExtensionAbilitiesTests.swift`, `CommandFrameTests.swift`):** Sidefolk's sentences come first and are reported, approval words refused in ten languages, a shared sentence goes to the AI; entries and drops vanish with the extension; settings refused for models, agents and other extensions; `settings_from` ignored for a folder install; AI refused without the permission, past the cap, with the switch off or no AI, the frame unclosable, the answer absent from History; a tampered or escaping picture draws nothing.

## 5. What Sidefolk never does

- Never lets the model, routines, external agents or extensions answer approvals, create grants,
  change settings, install extensions or touch Sidefolk's own data (the model's drafts folder is written
  only by `extensions.draft`, T27).
- Never runs model- or agent-written commands without the user approving the verbatim text, unless
  the person turned on Full access, and then never from a turn that read outside content (D37);
  never "always" for high risk. AI-written extension code runs only in a sandbox: once with nothing
  granted to check it, then only after the person installs it from the install preview (T27).
- Never hard-deletes, sets exec bits or strips quarantine, except from its own code: add-ons and seed packs after the
  checks of T33, and a new version of itself after the
  checks of T31.
- Never puts secrets or prompts in argv, logs, SQLite, UserDefaults, child env or exports; never
  sends a key to a host other than its provider's.
- Never listens on TCP in release, and never takes commands via URL schemes, AppleScript or
  distributed notifications.
- Never fetches non-http(s) URLs, or private addresses from model-built URLs; never loads remote
  images.
- Never asks for admin rights, Full Disk Access, Accessibility or Screen Recording; Automation only
  for Notes and Reminders, and for Finder on the ring's shortcut, driven by fixed scripts (T25, T49). Location Services only once the person chose
  their Mac's location, and never coordinates to an AI (T30).
- Never removes anything from another app unless its whole copy is in the notebook and the person
  approved that removal (T25), or it is a calendar event the person deleted or approved deleting, whose copy Undo
  puts back (T34).
- Never offers MCP sampling, roots or elicitation to extensions; never downloads extension code except
  Sidefolk's signed add-ons when the person clicks Get or Update, or by themselves under D70's rule (T33).
- Never edits `~/.claude`, `~/.claude.json` or `~/.codex` without a click, a confirmation and a
  backup; never writes through a linked skill folder, and never answers Codex's hook trust review
  for the person (T28).
- Never runs the brain when isolation cannot be verified.
- Never sends telemetry.

**T42 Reading on from a page leaks what the model holds (M/M, D119).** After outside content is read, a steered model could
put the person's data in an address it fetches (T2). "Read a few pages without asking" lets pages go without a card, so it
must not widen that. *Holds:* only links on a page read since the person's yes, compared byte for byte (`ResearchMode`, the
fragment aside), never an address the model wrote or respelled; GET only through `web.fetch`, no cookies, no local addresses
(T11, an encoded host refused); the person's click on a card, for this conversation, 12 pages and an hour at most; ended for
good by any tool but reading pages and a few named harmless ones; not in a conversation from before a restart; off-site links
echoing the fetched address not counted; each visit in History; Sidefolk's own agent only; not under "Ask each time". Tested
limit by limit in `ResearchModeTests`. *Residual:* a hostile page can list one link per letter and tell a steered model to
spell what's already in the prompt (About you, matching notes), about six bits a link. It needs no knowledge of the person.
The budget bounds that to about nine characters per yes, then the person is asked again, and History shows the visits.

**T45 An extension's result saved by Sidefolk, and its data folder (H/H), D140.** New reach, held by Sidefolk: at a program's asking, Sidefolk itself, with the person's full privileges, moves a file out of the program's data folder into one of the person's folders. The attacker is a malicious extension, which controls its data folder and its reply, and may have a second copy running while this happens. A double ending counts as one in the name rule, so `package.tar.gz` can name `package.json` beside it, as `package.zip` could; a name in use is never overwritten.
- *Reading through Sidefolk:* the data file is reached by walking down from the data folder with no link followed at any step, so nothing the program does to the folder, even during the walk, leads elsewhere. The data folder's parent is the only part resolved. It must be a regular file with one hard link. FIFOs and devices are refused without hanging. A clone taken later than the measurement is measured again, and a copy stops at the measured size.
- *Writing:* only beside a file in `ToolContext.handedOver`, which only Sidefolk's panel and drop code can set, never tool input, a model, a retry or a plan. Never a protected or hidden folder. An exclusive rename means nothing is overwritten, and the name starts with the source's whole name, so a program can't plant `CLAUDE.md` or `package.json` beside an unrelated file in a project. A bare name with an ending the tool declared and that's on `allowedEndings`, which leaves out anything that runs, runs script (HTML, SVG) or holds macros in the formats that do (DOC, ODT, ODS, ODP). Invisible and direction characters and blank names are refused.
- *The saved file:* `0644`, today's dates, no flags but a disk's own compression, no attributes from the program, and macOS's quarantine mark.
- *Exhaustion:* 64 files, 32 GB each, 64 GB a call, and room checked on another disk. It runs off the host's actor, and stops between files if the person stops it.
- *Races:* the destination folder is opened with no link followed at any level, judged by where the system says it is, then used only through that handle. A program able to write above the folder can't redirect a save by swapping it.
- *Records:* placing runs after the call and outside its timeout, so a file saved in a running Sidefolk has its own row in History. A crash between the rename and the row leaves none. The tool counts as changing things whatever its manifest says. Adding `outputs` in an update asks again.
- *The data folder itself* was already a risk before this: a program could remove its folder and put a link there, and the next start's profile, built from the real path, would open the link's target read-write with no one asked. The profile now denies creating or removing that one path, and a link found there at start is removed (`prepareDataFolder`).

- *Open, Show and Undo (D142):* Sidefolk's own actions on a file it placed, on a click, never available to a program. Open has a short list (images, audio, video, PDF, plain text, CSV) checked by ending and by contents, and re-checks at each click that this is the same file (device and inode), so a link or a replacement isn't launched, including from a card saved in an old conversation. Undo acts only if size and time match too.

**T46 A file's card (M/L), D150.** Sidefolk draws an extension's file offers, working card and saved-file card on a frost from the person's own file. The picture comes from the system's thumbnail service, out of process, and the card waits at most two seconds for it. It's in Sidefolk's memory only for the card's life and never reaches the extension. Only a regular file that Guard wouldn't keep private is drawn, and files another app sent with no click behind them get no picture. Sidefolk's own lines stay outside the frame in its own type and colours. Two manifest keys feed it: `tag`, a format's name from a fixed list, and `mark`, a pack picture read through the same checks as any other, shown small inside the frame or beside the extension's name.

**T47 Extension icons (L).** Drawing an icon is bounded and out of process. A PDF icon is drawn once by a system tool in its own tightly sandboxed process, under limits on its CPU and memory, and everything else shows only the resulting picture. An icon past its limits can't be installed. An extension already installed is never turned off over its icon, which at worst shows blank.

*Residual:* a source already named `CLAUDE.txt` still allows `CLAUDE.md`. A saved file is the program's content under an honest name, and could still be false or exploit a bug in whatever opens it, as with any download. Hence the quarantine mark, and D142's short list of what Open may launch. A program may keep its own copy if removing the data file fails.

**T48 Full access and Auto after outside content (H/H), D185.** The person chose these modes knowing a page can steer a model; the risk is theirs, said on the sheet in plain words, and this is what it is. *Attackers considered:* a web page, file, extension or MCP answer whose text steers Sidefolk's own agent in a turn that read it; a model's own mistake. *In Full access* nothing asks after outside content except text to read in full (saving a skill, because it outlasts the mode, and removing Apple Notes, which shows its list); so a steered turn can do everything the mode does without a card, within what stays closed: capabilities the person switched off, protected places (T10, which also refuses hidden files and folders, other users' homes and everything outside the home for this mode), command watchers from a turn that read outside content, and the internet's "Ask each time" if chosen. *In Auto,* after outside content, what could carry data out still asks (an address the person didn't type, a program, an extension or MCP tool, the clipboard, memory, the calendar) as does high risk and any folder not shared; a change to files inside a folder shared with write access, reads of private data that stay on the Mac (clipboard, calendar, History, Apple Notes, sessions) and a medium step that stays in Sidefolk now run; a step that changes how Sidefolk itself behaves (Focus or Quiet, its voice, an update, a job for the companion) still asks. *Held:* only the person's own click turns Full access on (no tool, other agent, extension, routine or plan can change Guard's policy: tests scan for it); other agents, extensions and routines never get a mode, and neither Full access's folders nor a typed extension command (whose folder the extension names); "Allow for this request" after outside content covers an extension's tool only if it reaches nothing (no network, no program), and a folder card that came after outside content says so and shares for good only by a deliberate choice; protected places match without regard to case; every call is in Activity with its decision; Undo and the Trash stay; turning it off, by banner, Pocket or expiry, returns to the mode it replaced. *Residual:* in Full access a steered turn can send what the context holds to an address of its choosing, run commands and programs, move or trash files in the home, write the clipboard and the calendar, and use extensions and MCP servers, with the person told only by Activity, the red chip, the orange icon and the bubble; in Auto after outside content it can change or move files between shared folders (one may sync to a service), copy notes from Apple Notes into the notebook and write the notebook, with a card still standing before anything carried off the Mac. A skill saved in a mode that asked about it still outlasts that mode. A `companion.job` a flow starts runs under the person's mode, so in Full access its turn finishes alone (T44).

**T49 The ring (M/L), D152.** Off by default, though the companion notes the same change count on every press, so its corner can take a drag. On, Sidefolk looks at the drag pasteboard's change count and the modifier state while the left button is down, and reads the file list only once the chosen key is held with the pointer at rest. Nothing is kept once it closes, and nothing reaches an extension until a file is let go on a slice or a slice is clicked: the same read of exactly those files for one call as a drop on the card (D141), through Guard, whose forbidden places hold per file, and with links refused as on the card, again when the choice runs.
- *An ordinary ⌥-drag* (the first review's S1): ⌥ is Finder's copy key, so the ring only opens at rest, the pointer must then move onto a slice and rest there, and the first 0.4 s don't count, for drops as for clicks (`RingAim`). What's under the pointer at opening chooses nothing, at a screen's edge too, and a turn to the other set starts over. It never answers a drop as a move. A hand that pauses a third of a second during a copy does meet the ring, which it leaves by letting go of the key off any slice; Finder's copy is then a plain move unless ⌥ is pressed again, as the cursor shows. After a turn, nothing is lit until the pointer moves, so a click can only choose what was seen, under the line about it, and letting go anywhere but that slice takes the click back.
- *A drag another app starts* can carry more than its picture shows. The middle gives the first name and how many more, and every name over the middle, one to a line, as far as the card shows it (120 characters); past five, or with a name too wide for its line by its measured width, the ring offers nothing and the card shows them all. Only what the ring read when it opened runs: a different list at the drop closes it.
- *What's seen is what runs:* the ring stays left to right in every language, since its slices are found by a fixed geometry.
- *The shortcut* reads Finder's selection by Apple Events only on the person's press, with Finder in front, from a child process with a deadline, and macOS asks once. It needs a click or Return to run anything. Names arrive as addresses in JSON, and nothing is built from them.
- *That yes outlasts the shortcut* (residual): Automation for Finder covers anything Sidefolk sends it, and by T25's reading anything a child of Sidefolk sends, such as a command watcher or an MCP server the person added. Finder can do far more than Notes can: move and trash files, open them. No new macOS question comes first, and in Full access a clean turn can make such a watcher without a card (T48). Taken only by those who press the shortcut and say yes, told first in plain words what it's for; what Finder can do, a child of Sidefolk can already do by shell as the same user, so the grant adds convenience, not rights. Open measurement: whether macOS credits a child's events to this grant. If that's measured as yes, the shortcut goes off by default again, with a note saying why.
- *A slice or an offer is a read.* A dropped file goes only under an argument the tool lists as `read`, so a choice can't become a card about sharing its whole folder for good, which Return may answer (D185). A copy installed before this rule gets no offers for files.
- *Full access and Auto* don't reach a slice or an offer for files: it runs as the person (`.user`), never with a mode, with the same one read and the same refusals of hidden and protected files. Offers for links, text and folders run as an extension's command (D185's rules for that caller), and the ring has none.
- *A picture in the ring* comes from the system's thumbnail service, under the same rules as the card (T46). The panel never activates Sidefolk. Words on a slice are the extension's, within a ring Sidefolk draws, under Sidefolk's own line: from its permissions, naming it, with the amber warning when it applies, and following the slice under the pointer. Extensions take turns on the ring, so one with many offers can't push another off it, whatever its id.
- *Choosing what's dragged* (measured 2026-11-04, a real program in the real profile): an extension with `clipboard` can clear and rewrite the system's drag pasteboard, since `com.apple.pasteboard.1` carries every pasteboard. Without it, it can't. It could swap a file being dragged for one of its choosing, and the read would then be its own on a careless release. So an extension allowed the clipboard gets no offers for dropped files, on the card or the ring (`canWriteDrags`). None shipped has both. What remains: such an extension can still change what's dragged for another extension's offer, whose grant it doesn't get. The name shows in the middle, and on the card.
- *Not covered:* VoiceOver during a drag (the card stays the complete way). An extension's slice can use persuasive words, as an offer on the card can. A file swapped for a link after the choice's own check, in the moment before Guard's, is limited by Guard's forbidden places.

**T52 A plan holds for the extension that offered the tool (M/M), D110.** A plan the person read for another extension's tool named the tool by its short name and its shape, not by who offers it, and an extension's short name is free again once it is taken away: a different extension installed later with the same name and the same tool could have been taken for the one that was read, and a run under the old plan would have used it without a card. *Held:* each step of a plan keeps who offered its tool (`ExtensionPlan.Step.provider`: the extension's id and what it was installed as: the kind of pack, and whether signed or written by Sidefolk's AI), and a call stands only if its tool has that provider and the same definition and reach as before. A newer version of the same pack is the same provider; a different id, a copy installed as something else, or another command is not, and the call asks a card. The card names whose tool each step is. A plan saved before this has no provider kept, so its steps on another extension's tool ask until the plan is approved again; Sidefolk's own tools are not affected. *Residual:* a provider is its declared id and how it was installed, not its author or version: an update keeps its plans (the tool's definition and reach still have to match, and the update was the person's), and a different pack installed the same way under the same id counts as the same provider, so the protection is as good as the install check on ids and the person's own approval of an install; an extension whose program changes behind an unchanged definition is not seen by plans, as before (T44). A plan saved before this still shows its steps as standing in Settings and to its program until it is approved again, though they ask; the call itself is what decides. The tool is looked up again when the call runs, a moment after the check, as before.

**T53 A flow's one approval: outside words, servers, and Full access (H/M), D186–D189** (the founder's explicit yes to its five decisions, 2026-11-05, is quoted in D189)**.** A flow the person approved once runs without more cards, so a page, file or program the flow reads can steer the *values* it passes on unattended. *Attackers considered:* a web page, file or another program's answer whose words reach a later step; an AI step that writes from them; a malicious or compromised extension; a steered turn of Sidefolk's own agent asking for a plan; an agent-authored flow. *Held:* the tool, server, fields and the number of calls are fixed by what the person read (the order is not: any call may come in any order, so the card's warning counts every other step of the plan, written before or after a line), and the host matches each call to its step (the same keys, written values byte for byte, words only in the slots, a whole-value slot taking a value of any kind or none); what the card shows is the bytes (one plain space between words, no hidden or odd space, joiners only in writing that has them, marks capped), and written nulls and empty lists show as that; a server's program (a compiled file, hashed, checked at each call) is pinned with its definition and provider (T52), and a launcher, interpreter of any version, script, or a program started with a file or folder it loads is not and asks each time; where outside words may go is a closed rule, first the card and second a name list read as words (plurals, camel case, acronyms, digits, schema formats): only a plain string field with a name for words people read (body, message, title) takes them (a field that is one slot may be given a list or a record at run time, but a string-typed field refuses those before Guard sees the call, `InputSchema`, tested); any other field (a place, a choice, a whole object) asks, and stands only in Full access; a field whose name says it runs code (command, script, sql, shell, args, read as words and as stems inside one word, overlap-safe) takes no filled value at all, from anyone, in any mode; the host takes every filled value as outside unless it is the person's own typed answer (an `ask.user` step) or the clock, a step's name is the host's to read (a name used twice, with a dot or bracket, or `today`/`now`, is refused), and an edit that points the same words at another step (another tool, another input, or two steps trading names) is new, through a step that only passes words on too (the fingerprint follows what it reads, down to the steps that run something), and a signed extension's claim that a value is the person's is believed everywhere except where code runs, while a typed answer or the clock, which the host reads from names the program writes, fills a place or a choice only in Full access; the card names where outside words go, line by line, and warns in plain words when a plan reads the person's own things and outside content and fills a server line from them, naming the server; a day and a run limit stop a call without a card and History says so; every call's History row says where its filled words came from; the person's switch turns passing words to servers off, for plans already read too; coverage of an edit is the host's (words written and now filled in are new), and a covered re-approval keeps the end the plan had. Full access answers only a signed extension's plan, for the person's own click (a click or their own typed command to that extension, used once, only while the call that click made is still running and for at most ten seconds: a button that has returned leaves nothing to answer another plan with), and a plan answered that way, which nobody read, stands only while Full access is on and asks for a card in any other mode; another extension's plan, and a turn of Sidefolk's agent, keep the card in every mode. Only a signed extension's AI, set-off and pass-on (`value`) steps are accepted; the names a step reads must all be valid, each valid, at most 32 (a name repeated in one list is read once; nothing else is dropped), and what a pass-on step is fed by is worked out once per name, so a chain of them can't be made to take the host forever. The card names an AI step's sources by title and tool, down through pass-on steps, and shows the same line once with "× N" only when the tool and every byte of it are the same. Looking at a plan (`plan.check`) has a minute's budget of its own, approving plans another, and a plan is capped in size. A plan unused for 60 days ends and its extension is told; Settings › Trust lists every approved plan with what the person read and a Revoke. The warning for a plan that reads the person's own things and outside content counts any server's or other extension's tool as a reader of the person's own things, because a server's own word that it only writes is never known, and counts every other step of the plan, written before the line or after it. *Residual:* a free-text field a server treats as an address or an instruction can still be steered, within the pinned tool, program and limits: the person approved the sentence that says outside words go there, and the switch is the strict option. A person's own words and private things can go to the server a flow names if a page steers what the AI writes; the destination is written, but what a server does with its fields is its own. The name list will miss a name, and a tool that runs words by its own design under a plain name is not seen. A program hash covers the main executable only. A click on a signed extension counts for one plan it asks for while that click's call runs (at most ten seconds, once): which plan is the extension's choice, so a call of the person's that stays open is a window in which that extension, or a compromised signed update, may ask for any plan, a job for the companion included (in Full access running is the approval), and two calls that overlap can be crossed (an agent's turn answered by a click running beside it); ambient speech that matches its commands is the person's to trust. The run limit relies on a run id the program sends: the day limit is the real bound, and it is counted before an await, so calls that start at the same moment can each count from the same number and pass it by the few that were in flight (at most the minute's call budget). A signed extension's claims about where a value came from, and what an AI step reads, are taken at their word. A plan approved under Full access may hold more than Auto would allow until Full access ends, and those lines stand again when it is turned back on. Two calls to one tool at the same moment share the registry's tool, so a stopped call and a standing one can trade places for a moment (it asks, never runs unasked; a limit flag can be lost, and a denial may land on the other extension's call; the plan tool is registered under a shared name too, so another extension can swap its own in between and show an odd card or a denial). The rule for fields that run code is a list of names (command, script, args, arguments, executable, binary, cmdline, flags, options, env, prompt, task, run, sh, statement and their kin), so 'refused in every mode' is as strong as the list, and a code-taking field with another name is a free-text or place field. A server's program is hashed when the plan is read and when a call is matched, and started later, so a swap by the same user in between is not seen; the launcher list (interpreters, shells, make, just, task, rake, bundler, poetry, nix, timeout, gradle, mvn, pip and the Mac's own command-line tools) is best effort, not an allow-list, because a program the person added can be anywhere. A stop that arrives before its call is registered is remembered (the most recent few) and applied when the call turns up; one request id runs one call at a time; there may be a sub-millisecond gap between the person's Stop and the end of that call in which a click still counts; a plan card is not withdrawn when its extension stops, but an Allow while it is off saves nothing (turn it on again and the program asks again); a stop is remembered for the most recent 32 request keys and dropped first-in first-out; a program that sends a request id already running gets "already running". A person's typed answer is theirs, but a QUESTION written from outside words (an `ask.user` question filled by a page) is not: the person may type a code or a secret in answer, and a later server line may send it where the card said; the card names the destination, not what the answer will be. The weakest trust left is the add-on's own: a signed extension's `inside`, `from`, `today` and `now` claims are believed, so a flow input, trigger payload or loop variable that its program lets be named so would label page-steered words as the person's own; Sideflow is asked to guarantee and test that on its side. A Full access answer over a plan that was read flags the whole plan unread (over-claims, fails safe). A silent pass needs a LOSSLESS record: what Full access or Auto let through with no card is named on the approval's row as one entry for the plan's limits (and its end, if it has one) and warning, one for its title (and whether the program asked to run it or turn it on) and one for the words the extension gives for when it runs (empty, said as empty), which the card also shows, so a changed `when` is in History and not only on a card nobody saw, a header for EVERY line (a tool's, a hand-over to the person's AI, a flow it sets off), an entry for each source its fields' slots read from (told once for the line, as the card says its producers; a slot refers to it by its name, and two names that read alike make the card the record), and an entry for EVERY field of it, each carrying the line's number (as the card shows the lines, with no gap; the tool is named once, on the header, with ×N for a line repeated) so a destination stays with its body, the kind of its source first, every written part between slots in quotes, every item of a list with the count, and the producers of every slot in full (in its source's entry). If that cannot be kept whole (more than 64 entries, an entry over 300 characters, a name that had to be cut (an add-on's, a tool's, a field's, a flow's; the plan's own title and its `when` are cut upstream, to 80 and 600 characters, and the card and the row show the same cut text, so that never forces a card), or History's Redactor would change one: a literal that looks like a secret, a field named like one, a long mixed-case word) the plan shows its card, in every mode, Full access included: a flow too large or odd to be recorded in full on one History row always shows its card. A change of ONLY a plan's title or of the verb the program asked with (run or turn on), on a plan whose lines and `when` are covered, is not a widening: what runs does not change, only the label, so it passes in every mode with no new card, and the row shows it only where a record is written (a silent pass in Full access or Auto). The row is a summary and not the bytes: its text is cleaned like any author's words (joiners and extra spaces go, curly quotes become single ones), where the card keeps what it can. Settings › Add-ons says when a plan's actions run without asking (always; only while Full access is on, and nobody read it; some only in Full access, only in Auto, or either), with no count. History's Redactor can blank or lengthen a literal that looks like a secret (`token: abcdef…`, a long mixed-case token such as a host written like one); a plan with such a literal can't be recorded in full, and shows its card. A switch that is present in the policy file but unreadable reads off, an absent one on. A flow that sends page-steered words to a server off the Mac leaves History with where the words came from (one short entry per field, up to twenty, then how many more), not the words, so the person cannot read afterwards what was sent; what Full access or Auto let through with no card is named line by line on the approval's row, or the plan shows its card (see the lossless record above). A plan is bound to the extension's permissions and origin, not to its code, so an update of a signed sandboxed add-on that keeps its tools' definitions keeps every plan standing (the founder's "ask once"; only a server's program is hashed and asks again when it changes). A plan saved before the host worked out where words come from has no sources, and there a slot outside the closed table is a plain written value. Forward references (a slot or an AI step's `reads` naming a later step) are read as outside and not refused, because refusing could break flows that are written that way; a name is refused in any case if it is the clock's, whatever its case. Card and coverage work is quadratic in the rows of a plan on the host's own actor (unmeasured beyond the edge test). `plan.check` tells an extension with act permission which lines stand or ask, which says the person's mode and whether passing words to servers is on, to unsigned ones too. Comparison of a written text is by bytes, and of keys and a flow's name too; joiners and selectors are refused in a field's name and in what a list or an object holds (the card shows those cleaned); confusables inside one script (Latin look-alikes in Latin) are not seen, a word that mixes writing systems (known by Unicode block, so an unlisted script counts as one) is refused as plain, joiners are accepted only between emoji or in Arabic and the Indic scripts, Myanmar and Khmer, a list and a plain value of one item look alike on the card, an author's title and `when` have their blanks left out but are otherwise the author's words, an edit that points an open field's words from one outside source to another is covered, a name used in a slot or an AI step's reads before the step that makes it is outside, but two later steps that trade names leave an earlier consumer covered, and the card shows a curly quote of an author's words as a single one so it can't end its own quote. The Trust switch holds back everything a flow read or wrote that the host takes as outside, not the person's typed answers, the clock or anything a signed extension says is theirs (the switch is the only control the person has, and a signed extension's claim is believed); a signed extension that moves a field from outside words to its own claim is shown as new, but a compromised one that is already believed keeps passing what it calls the person's own. If the person's policy can't be read, Guard refuses every action and nothing is passed on; a policy file with an unreadable passing-on switch reads it as off (the Settings switch shows off then); the other defaults of an unreadable policy file (the mode, what is disabled, the internet rule) are the app's long-standing fail-open ones and are not changed here. Lines Auto let through with no card (what only writes or tells inside Sidefolk: a note, a notice, a reminder, a change or removal of one of those; never a read whose answer goes back to the add-on, which shows a card) were read by nobody and stand only while Auto is on.

**T43 Pages that act without tools, places and planned moments (M/M), D105, D106, D107, D108.** New reach, each held by something the program can't touch:
- *`go`* only changes state the host keeps for that open page, 4 KB at most, and asks for another reading; nothing else happens, and nothing is in History because nothing was done.
- *`copy`* runs `clipboard.write` as the person: the capability switch applies, History and the page show the exact words, and it hangs only on a button with a label, never a scene's area, so a command can't be planted for pasting behind nothing (T12).
- *`file`* opens the system's panel; only then does a path exist, with a read of that one file for that one call. Other path parameters are stripped. Guard's forbidden places still hold.
- *A drop on a file offer* (D141) is treated the same: Sidefolk's drag code hands over the paths the system gave it, and the call runs as the person with a read of those files alone, for that one call. Other path parameters are stripped, and the list parameter is overwritten rather than merged, so a template or a menu choice can't plant a path. Each file is followed to what it really is and must be a regular file outside forbidden places, so a dropped link to `~/.ssh` is refused. A panel shows what was chosen, but a drag can carry more than its picture shows and another app can start one. So **the card is the yes**: Sidefolk's own words, not the extension's, name the extension, the exact count and every name (reachable), and say if it could send the files on. The extension's titles sit apart under its name, nothing is pre-selected, Return doesn't choose, and clicks are ignored for a moment after the card appears, because it opens under a mouse that has just let go. A drop with no choice runs nothing. Finder's Send to Sidefolk (D151) arrives on the same card, and any app could send files through it, as any app can start a drag. A refusal from a drop stops there: the caption is a file's name or a link, not the person's words, so it never goes on to the AI as if typed. Menu items and page controls carry no paths, so only a `file` button or a drop can name a file for the person. Applies to every file offer, as the founder chose ("All drops"), so a local third-party extension gets a read of any dropped file with only this card as the yes.
- *Finder's Send to Sidefolk* (D151) leads to the same card, but a Service needs no click: any app can call one. So it never takes the keyboard, doesn't replace a file already waiting or join words being typed, and nothing runs until the person chooses on the card.
- *`allow`* shows Sidefolk's own question, with the extension's purpose marked as what it says; the extension can't answer it. `extensions.consent` refuses every caller but the person. *`settings`* opens a fixed pane.
- *Occurrences:* the host's timer, the person's yes checked again at each telling, 256 pending, 64 a day, one plan in ten seconds, ids never told twice, revisions never going back. The words are the extension's, so its name is always with them and they never reach a model: nothing in `ContextBuilder` or the live state reads attention items' words, and `critical` stays out of reach (`extension:` isn't a critical source). See D107 for what this changes in T24.
- *`extensions.place_search`* goes through Guard with its one service named, and its answer goes to that program alone.
- *Who reaches these tools.* `extensions.consent` answers only the person (`caller == .user`); `extensions.occurrences` and `extensions.place_search` only the extension for itself (`.extension(own)`, `own` being the id in the call). None is offered to a model (`offeredToModel: false`), and each refuses by caller in the tool itself, so no agent, routine or access group can reach them, whatever a group lists.
- *`dress`:* a ground or card the theme's ink can't be read on is left out, and Sidefolk's own question is drawn by the window, not the dressed page. A bare page still says whose it is.

**T44 An extension using Sidefolk's tools, and plans (H/M), D110, D111, D112.** New reach, the largest an extension has had: its program can ask for tools it doesn't own. Attackers considered: a malicious or compromised extension, a steered model, a hostile page whose text flows into a run, and an agent in a hostile repository.
- *Exactly what an extension can do with `permissions.act` (as first built; widened below):* list a closed set of tools (named built-ins and other sandboxed extensions' model-facing tools, never an MCP server's, memory, skills, settings, command watchers or `.shell`); ask Guard what it would do, with nothing run; and call them as `.extension(id)`. Every call goes through `ToolExecutor`, so Guard and History see it. There is no other path, and a call can't run as the person or as Sidefolk's agent.
- *Exactly what it can't, as first built (D127 later opened programs, MCP servers and another extension's tool kept to its commands, always on a card):* run anything as the person or as Sidefolk's agent; answer a card; reach `extensions.*` (settings, consent, occurrences, plans, drafts), skills, memory, command watchers, programs, MCP servers, its own tools by this path, or another extension's tool kept to its commands; give itself "Always"; start a plan from a timer or from something a model read.
- *What a plan may leave open:*

| Tool | May be filled in when it runs | Why that's contained |
|---|---|---|
| `notes.save` | `text` | Stays in the notebook, marked with the extension as its source |
| `notes.search` | `query` | Not contained: words from elsewhere choose which notes come back, the founder's choice (D127) |
| `voice.say` | `text` | Said with the extension's name, in the Mac's own voice, never in Focus or Quiet, with spoken replies off, when the person has that extension off their desktop, over the person, or while something is using the microphone |
| `reminders.create` | `title` | Shown to the person, under the extension's reminder. Not `notes`: they'd show in History when it fires, past the founder's answer, which was about the title |
| `notify.user` | `title`, `body` | Shown to the person, with the extension's name |
| `ask.user` | `question` | Shown to the person, with the extension's name |
| Anything else | Nothing: every value is written out, or the step asks each time | A value could pick a target, be parsed, or carry words off the Mac; Sidefolk can't tell what another extension's tool does with its text |

- *Asking.* Every tool is at least medium for this caller, except `notify.user` and `ask.user`, whose only reach is the person; they're named with the extension. Medium and up are evaluated as tainted, as for other agents, so a card comes each time and never offers "Always". Taint isn't tracked by run: a run id would be the program's to change. One card at a time per extension; 60 calls a minute. Folders outside the person's shared ones are refused, not asked.
- *Amended by T53 (D186–D189):* an edit asks only about what is new, a signed extension's plan may hold a server's tool, steps with no tool (an AI step, another flow) are read as lines, and Full access answers a signed extension's plan for the person's own click. Everything here about who may ask for a plan, the 30 seconds, the closed table and contained-only holds.
- *Plans.* The card is `extensions.plan`, text to read in full: Auto and Full access never answer it, and "Always" isn't offered (`answeredByMode`). One at a time per extension, so what is saved is what was read. It is drawn from what the program sent, by the tool's own title with every written value; `title` and `when` are shown as the author's. A written value with hidden characters, or past where the card stops (300 characters), asks each time. A call stands only if it has the same keys, every written value equal byte for byte (canonically equal strings aren't the same address), words only in the closed `fillable` table, the tool's definition unchanged, and the same scope (`reach`), so a filled-in value can't move where a call goes. High risk, `clipboard.read`, "Ask every time", "ask each time" online, a turned-off capability and a folder boundary hold whatever the plan says. Budget per plan per day.
- *Laundering through the program.* A plan's reads return to the program. So plans go only to an extension that can't reach out by itself, and from there words reach only the closed table. Such an extension can still read what its plan lists: the card says so ("What these return goes to …"), and queries must be written out, except a note search's, which the founder chose to leave open (D127).
- *Steered approvals (T3).* `plan.approve` is refused unless the person clicked or typed to this extension, or a clean turn of Sidefolk's agent called it, within 30 seconds. A steered model, a routine, a timer and other agents get `not_asked`.
- *Other agents (D112).* A tool marked `agents` is asked every time, under the person's group (Ask or Off, never Allow). What an agent can do with Sideflow is write drafts, on a card; nothing it writes runs.
- *Deleting several flows (D199).* Only Sideflow's own page button deletes from a selection. The press carries a private token the page holds (`page_token`), comes at least 0.6 seconds after the confirmation appeared, and names exactly the flows the confirmation listed; anything else is ignored. This guards against another extension calling the page's `ui` tool, which is low risk and asks nothing. Its way to delete is `delete_flow`: high risk, one flow, a card each time.
- *Saving to a file (D200).* A page's `save` control runs the extension's own tool as the person, and it names no file: path parameters come off its input as on any control. The tool writes a file in its own data folder and answers its name. Then the person picks the path in the system save panel, and Sidefolk copies the file there, marked as downloaded. It reads that file the way it reads a page's pictures: a plain name, the file opened without following a link or waiting on a pipe, one name only, its real place checked inside the folder on the open file, and 1 MB at most. It removes nothing: a folder on the way could be a link the program made, so a delete on its word could reach anywhere. The extension never learns the path. A file can't be a kind that opens by running: only D140's list of content types, or an ending nothing on this Mac opens when it's asked. An app installed later could claim one, so the mark is what's left then: a mark that a volume can't hold fails with no word. The file's name is one plain line with its ending in sight. Nothing is written without the person's press and their choice in the panel, and a program can't aim it. What's written is the program's own words, so `note` and the page are its word for what's in it.
- *Files of flows (D200).* A `.sideflow` file comes from anywhere, so it's outside content. It's read and shown first, and comes in only on the page's own button (its private token, as D199), always as a draft and off, with no approval or state. Unknown step kinds, triggers, keys or a newer format are refused whole. A name that's taken makes a copy. The page's list of what a flow does is what Sideflow can tell, and says that its real safeguard is the card when it's turned on: anything not marked as only reading is called changes or sends, and "deletes" is a hint from the tool's name. What a file says it needs is ignored and worked out again from its steps.
- *Watches (D111).* Only the extension's own, gone with it, and their summary is outside words: it reaches the closed table only.
- *Notices.* `notify.user` and `ask.user` carry the extension's name in their words, wherever they show.
- *Practice runs.* `reads_only` is Sidefolk's word (built-ins, signed extensions), never a manifest's; notices aren't reads. Plans for practice end by themselves within the hour.
- *What the founder widened (D127, D128, D129, 2026-11-03), in plain words.* With `act`, an extension can now ask for every other extension's tools, including those kept from the model and high-risk ones, every MCP server's, programs that can run anything, and nearly all of Sidefolk's own: it still can't reach `extensions.*`, `skills.*`, `profile.*`, `watch.read` or `watch.command`. MCP servers and anything that can run a program are a card every single time: high risk for this caller, never in a plan, no "Always". Checked with a real MCP server and a real shell command in the debug app: each showed its own card, ran only on Allow, and is in History; "Not now" stops the run. A card can't really say what a command will do: that risk is the person's, by the founder's choice.
- *In the table, by the founder's choice:* `notes.search` with its `query` filled in at run time. Words from a page can choose which notes come back, so a steered flow can fetch a note's content and pass it on through another step it stands on. What a step filled in stays out of History: its row keeps the step as written and how long the words were (D127). A notice or question it filled in shows in full where it reaches the person, and in History only as "<extension>: a notice"; so does the card that sums up held ones, by its title alone. Its words stay in the attention table until that's pruned. If the person set that source to History only, they show nowhere: their setting. *Residual, accepted:* all this keeps words out for an extension that isn't trying to put them there. One that is trying can still write its own words in places made for them: `sidefolk/activity.add` (120 characters, a row of its own, under its name), a watcher's summary, an occurrence with schedule consent. Those say they are the extension's, and closing them means taking general abilities away. The written parts and slot names in such a row are the extension's own (`Groceries {{x}}`, `{{weather}}`), so a row is what it said it wrote, with "filled in, length N" beside it; the action, target and every other value are the real ones. A call with no plan may say what it filled in (`written` on `tools.call`): Sidefolk checks it fits and is in the table, so all that can do is keep those words out of History, words that have gone to a place the person can see. A reminder made this way fires with its own title, and History shows that as it does any reminder, the founder's choice (D127), so note text can land there. A typed command's answer stays out too (D136's row), and any call's failure words, for an extension with `permissions.act`, `permissions.events` or clipboard access, since what it says can carry what it read, heard or copied: "how did this flow go" would otherwise put a note's words there. `voice.say`'s `text` is in the table too: it's said with the extension's name, and not in Focus or Quiet.
- *How it looks (D127).* `appearance.set` changes light or dark, the theme and the companion, and nothing else; it may stand on a plan. No tool changes trust, connections, the AI or add-ons.
- *Focus and Quiet (D127).* `attention.set` may stand on a plan, the founder's word: a flow the person turned on can turn down what reaches them without asking again, and so can hold a notice back. Exactly that: Open, Focus or Quiet, always with an end of at most a day, its mode and length written out on the card. Per-source interrupt levels (D88) and quiet hours have no tool, and no extension can change them. A flow on a schedule can set it again when it ends, and it replaces a Focus or Quiet the person set themselves.
- *A job for the companion (D128).* `companion.job` runs a turn of Sidefolk's own agent under the person's mode, so in Auto or Full access it can finish alone, and what it reads can steer it within what those modes allow: the founder's choice. What holds: its words prove nothing about what the person asked (no typed links, `AgentRequest.Job`); only a job read word for word on a plan starts clean, any other starts as having read something from outside; it is never offered to the model; it can use what the person's own turn can, MCP servers and programs included, so in Auto or Full access text it reads could steer it into running a command with no card: the founder's choice; 200 plain characters at most, nothing invisible, so a card shows all of it; it has a conversation of its own, marked as an extension's words, which the person's next words don't continue; it needs `permissions.ai` and counts toward that cap; a timeout cancels it. An extension that can reach out hears only "Done."; a contained one hears the answer, and that answer can hold anything the companion read.
- *Hearing what happens (D129).* `permissions.events` tells a running program, with no card each time, the title of a reminder, a saved note's row in History's words, a meeting's title, a connected agent and its project. The founder chose titles. An extension that can reach out by itself hears them too, so it could send them off the Mac without a card: the founder's choice, and the install sheet says so. A companion's answers are never told, only that it finished. What an extension or a job did to a note or a reminder doesn't count, so a flow can't set itself off that way; Focus or Quiet changing does count, whoever changed it, and a reminder a flow set still fires, so those can loop until the 30-an-hour stop.

*Contained, and `media`:* an extension with `media` isn't contained: the certificate service HEIC and AVIF need can fetch from an address, so what it read could leave that way. It gets cards instead of plans, and the install sheet says it could send what it hears on. No shipped extension has `media` with `act` or `events`.

*Residual (D127-D129, after a second review):* the cards a job's own steps raise say the companion wants to, not which extension handed it the job. What a job says through `notify.user`, `ask.user` or `voice.say` keeps to that extension's level in Attention (its id is in the job's run id, which only `AgentRuntime.submit` writes). A plan's title and its "when" are the extension's words, unquoted, though what it will do is the host's list below them. A card's text scrolls past its height, and Allow doesn't wait for that. Nobody has run a live model against invisible text; it's refused, not tested against one.  a contained extension can keep the titles it hears in its data folder, and an update that adds a reach re-asks but doesn't say what it already holds. A plan's line for `notes.trash` or `notes.update` shows the note's id, not its name. A flow that listens for `attention.changed` or `reminder.fired` and causes one can set itself off: the 30-runs-an-hour stop is what holds it, at up to 30 AI requests an hour if it holds a job, within the day's cap. Stopping an extension doesn't stop a job already running; its timeout does.

*Residual:* `tools.check` tells an extension whether a card would come, so it can learn whether a folder is shared; it can't learn what's in it. A contained extension with reads and a written-out outward step in one plan could say something by which of them it calls and when: the destination is one the person read, and the budget bounds it. While an extension is off its watch still checks, and what it saw is dropped. A plan's filled-in words can put outside text in a note, a reminder or a notice, marked as the extension's: someone who writes a web page a flow reads can write those words. An author can pick a misleading title; the steps beneath it are the host's. `act` plus AI help means outside words can reach the person's AI, as the frame already allows (T41): it has no tools, and its answer reaches only the same table.

