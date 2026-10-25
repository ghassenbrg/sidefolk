# Writing Sidefolk extensions

An extension gives Sidefolk new **tools** (things the companion can do when you ask) and new
**watcher kinds** (things it can keep an eye on). It is a folder with a manifest and a small program
that speaks [MCP](https://modelcontextprotocol.io) over stdin/stdout. Sidefolk runs that program in
a macOS sandbox built from the permissions the manifest asks for, and you see those permissions in
plain words before you install it.

Two examples live in this repository:

| Folder | What it shows |
|---|---|
| [`extensions/hello-folk`](../extensions/hello-folk) | The smallest working extension: one tool, one watcher, ~50 lines of Python. Copy it to start. |
| [`extensions/system-vitals`](../extensions/system-vitals) | A real one: battery, disk and memory tools, `battery_low` and `disk_low` watchers, and an exec allow-list. |

You can also add any existing MCP server (see [Plain MCP servers](#plain-mcp-servers)); it runs
without a sandbox and is labelled that way.

## Contents

1. [Quick start](#quick-start)
2. [The manifest](#the-manifest)
3. [Permissions and the sandbox](#permissions-and-the-sandbox)
4. [The protocol](#the-protocol)
5. [Tools, risk and approvals](#tools-risk-and-approvals)
6. [Watchers](#watchers)
7. [Testing locally](#testing-locally)
8. [Installing, updating, removing](#installing-updating-removing)
9. [Plain MCP servers](#plain-mcp-servers)
10. [Troubleshooting](#troubleshooting)
11. [Limits](#limits)

## Quick start

```sh
cp -R extensions/hello-folk ~/my-folk
cd ~/my-folk
# 1. Edit sidefolk-extension.json: give it your own id (com.yourname.my-folk) and name.
# 2. Edit main.py: add your tools.
# 3. Try the protocol by hand, from a scratch folder (install copies everything in ~/my-folk,
#    so files your program writes while you test would ship with it):
cd "$(mktemp -d)" && printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | python3 -I ~/my-folk/main.py
# 4. Check the manifest, then start it in its sandbox and list its tools:
sidefolk ext validate ~/my-folk
```

The `sidefolk` helper is built with `swift build --product sidefolk` (then `.build/debug/sidefolk`);
the app also installs it in `~/.local/bin`.

Then install it from **Settings › Extensions › Install from folder…** (or drop the folder on the
companion), read the permission sheet, and click Install. Ask Sidefolk to use it: "say hello to Ada".

## The manifest

`sidefolk-extension.json` at the top of the folder, at most 64 KiB. Decoding is strict: **any key
not listed here is an error**, so a typo never silently changes what an extension may do.

```json
{
  "id": "dev.sidefolk.system-vitals",
  "name": "System Vitals",
  "version": "1.0.0",
  "sidefolk": ">=1.0",
  "description": "Battery, disk and memory at a glance.",
  "folk": "byte",
  "author": "Sidefolk",
  "run": { "command": "python3", "args": ["main.py"] },
  "permissions": {
    "network": false,
    "files": { "read": [], "write": [] },
    "exec": ["/usr/bin/pmset", "/usr/bin/vm_stat", "/usr/sbin/sysctl"]
  },
  "tools": {
    "battery": { "title": "Battery status", "risk": "low", "category": "system", "mutates": false }
  },
  "watchers": {
    "battery_low": {
      "title": "Battery low",
      "description": "Tells you once when the battery drops below a level.",
      "config": { "below_percent": { "type": "integer", "default": 20, "minimum": 1, "maximum": 99 } }
    }
  }
}
```

| Key | Required | Rules |
|---|---|---|
| `id` | yes | Reverse-DNS, lowercase: `^[a-z0-9]+(\.[a-z0-9-]+)+$`, at most 64 characters. The installed copy lives in `Extensions/<id>/`. The last part (`system-vitals`) names its tools, so it must be unique among your extensions. |
| `name` | yes | 1–60 characters of plain text, shown everywhere. |
| `version` | yes | `1.0` or `1.0.0`, optionally with `-beta.1`. |
| `sidefolk` | no | Minimum Sidefolk version, written `>=1.0`. |
| `description` | no | At most 300 characters. |
| `folk` | no | The folk that appears while it works, e.g. `byte`. |
| `author` | no | At most 100 characters. |
| `run.command` | yes | `python3`, `node` or `sh`, or a compiled program inside the folder (`bin/server`). Nothing else: no absolute paths, no other interpreters. |
| `run.args` | depends | For `python3`/`node`/`sh` the first argument is the script, a path inside the folder (`main.py`, `src/server.js`). At most 32 arguments. |
| `permissions.network` | no | `true` lets it use the internet. Missing means `false`. |
| `permissions.files.read` | no | Folders it may read, absolute or starting with `~/`. |
| `permissions.files.write` | no | Folders it may read and change. |
| `permissions.exec` | no | Absolute paths of programs it may run, like `/usr/bin/pmset`. |
| `tools.<name>` | no | Sidefolk's metadata for a tool your program lists: `title`, `risk` (`low`, `medium`, `high`), `category` (`notes`, `memory`, `time`, `watch`, `files`, `web`, `system`, `agents`, `extensions`) and `mutates` (`false` if it only reads). Tool names: `^[a-z0-9_]{1,64}$`. |
| `watchers.<name>` | no | A watcher kind: `title` (≤ 60), `description` (≤ 300) and `config`, its settings. |
| `watchers.<name>.config.<key>` | no | `type` (`integer`, `number`, `string`, `boolean`), and optionally `description`, `default`, `required`, `minimum`, `maximum`. |

**Folder name.** When you validate a folder, its name should be the id or the id's last part
(`system-vitals`); otherwise you get a warning (usually a copied template with an old id).

**Paths in `files`.** They are resolved with `realpath`, so links are followed at install time and
the resolved folder is what you grant. They can't contain quotes, backslashes or control characters,
can't be `.`/`..` tricks, and can't be anything Sidefolk protects: the whole disk, `$HOME` itself,
`~/Library`, hidden folders (`~/.ssh`, `~/.config`, …), system folders, or Sidefolk's own data.

**Exec entries** must be real files (not links: list what the link points to), owned by root or
you, not writable by other users, and outside every folder the extension or Sidefolk can write to.
Shells, interpreters and tools such as `osascript`, `open`, `curl`, `security`, `sqlite3` or
`launchctl` are flagged on the install sheet as "can run anything": listing one makes the exec
list meaningless.

## Permissions and the sandbox

Sidefolk starts your program like this:

```
/usr/bin/sandbox-exec -f <profile> -D EXT_DIR=… -D DATA_DIR=… … <python3> -I -B <your folder>/main.py
```

The profile denies everything by default and then allows only what the manifest grants. What your
program **can** do:

- Read its own folder (read-only: Sidefolk installs a locked copy).
- Read and write its **data folder**, `~/Library/Application Support/Sidefolk/ExtensionData/<id>/`.
  `HOME` and `TMPDIR` point inside it, and so does the working directory. It survives updates and is
  deleted when the extension is uninstalled.
- Read the folders in `files.read`; read and write the folders in `files.write`.
- Run the interpreter, and the programs in `exec`. Children inherit the same sandbox. Only an
  extension whose manifest lists programs in `exec` may start processes at all (`fork`, and
  `subprocess` in Python, fail with `EPERM` otherwise; `sh` extensions may fork for pipelines).
  Every process it starts is stopped with it, including ones that leave its process group, and at
  most 32 may run at once.
- Read system libraries, time zone data and `/dev/urandom`; `stat` any path.
- Use the network, if `network` is `true`.

What it **can't** do (verified on macOS 27): open network or Unix-socket connections without
`network`; read anything else in your home (including `~/.ssh` and dotfiles) or list your home
folder; write outside its data folder and `files.write` folders, including its own folder; run any
program not listed (`/bin/ls` fails with `EPERM`); escape through a symlink or hard link it
creates in its data folder; talk to the pasteboard, Apple Events or LaunchServices.

Good to know:

- **Network is all or nothing.** A network extension can reach any host, including your local
  network and services on `localhost`. The install sheet says so.
- **Python runs with `-I -B`** (isolated mode, no bytecode). Isolated mode doesn't put your script's
  folder on `sys.path`, so for multi-file Python add this before your imports:
  `sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))`.
  Python comes from Apple's developer tools (`xcrun --find python3`, currently Python 3.9), which may
  be older than the `python3` you use in Terminal; Homebrew or python.org Pythons are used only if
  the developer tools are missing. Use the standard library, or vendor packages into your folder.
- **Node** is looked up in `/opt/homebrew/bin` and `/usr/local/bin`. **sh** is `/bin/sh`; every
  external command a script runs (even `head`) must be in `exec`.
- **Environment:** only `HOME`, `TMPDIR`, `PATH=/usr/bin:/bin`, `LANG`, `PYTHONDONTWRITEBYTECODE`,
  `SIDEFOLK_EXTENSION_ID` and `SIDEFOLK_DATA_DIR`. Nothing from Sidefolk's own environment.
- **Descriptors:** only stdin, stdout and stderr are inherited.
- **System services for specific programs.** Some system programs need a system service to work.
  Sidefolk opens it only when that program is in `exec`: `/usr/bin/pmset` gets
  `com.apple.PowerManagement.control` (battery state).
- **Folders that macOS protects** (Documents, Desktop, Downloads): macOS asks *you* whether
  Sidefolk may access them the first time your extension reads them.
- **Resources:** a watchdog stops your program (and everything it started) if it uses more than
  512 MB of memory, or more than half a CPU core for a minute.

## The protocol

Your program reads JSON-RPC 2.0 messages from stdin, one per line, and writes one JSON message per
line to stdout. **Write nothing else to stdout.** Logs and debugging go to stderr; Sidefolk keeps
the last 16 KB for its diagnostics.

**Answer every message that has an `id`** (requests); ignore those that don't (notifications).

### Startup

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Sidefolk","version":"1.0.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"system-vitals","version":"1.0.0"}}}
→ {"jsonrpc":"2.0","method":"notifications/initialized"}
```

### Listing tools

```json
→ {"jsonrpc":"2.0","id":2,"method":"tools/list"}
← {"jsonrpc":"2.0","id":2,"result":{"tools":[
    {"name":"battery","title":"Battery status",
     "description":"Battery charge in percent, whether it is charging, and the time remaining.",
     "inputSchema":{"type":"object","properties":{},"additionalProperties":false}}]}}
```

`nextCursor` pagination is supported. If your tool list can change while running, send
`{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}`.

**The model doesn't see your descriptions.** A tool description is offered to every request before
anything has been read, so a hostile one could steer the model unnoticed. Sidefolk shows the user
your descriptions on the install sheet and in Settings, but tells the model only "“Battery status”,
a tool from the extension “System Vitals”", plus your input schema with its free text
(`description`, `title`, `examples`, `default`) removed. Give tools clear titles (the manifest's
`tools.<name>.title`, else the program's `title`) and parameters self-explanatory names
(`below_percent`, not `n`); types, `enum`, `minimum`/`maximum` and `maxLength` stay and are enforced.

**Inputs are checked against your schema** before the call reaches you: wrong types, values outside
an `enum` or a bound, strings longer than `maxLength` (100,000 characters at most), and, with
`"additionalProperties": false`, unknown keys are refused with a message the model can act on.

**Manifest metadata is matched by tool name.** A manifest `tools` entry the program doesn't offer,
or a tool the manifest doesn't describe (which then runs as medium risk with default settings), is
reported by `sidefolk ext validate` and at install.

### Calling a tool

```json
→ {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"battery","arguments":{}}}
← {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Battery at 72%, discharging (3:12 left)."}]}}
```

Return text content. For a failure the model should see, return `"isError": true` with a short
explanation as text: the model reads it (as untrusted content, cut at 4 KB) and can fix its call,
the user sees "“Start a focus session” reported a problem", and the call counts as failed without
claiming that nothing changed. For a broken request, return a JSON-RPC `error`; its message goes
only to the log. Image and audio content is not shown to the model yet.

### Checking a watcher (Sidefolk extension to MCP)

```json
→ {"jsonrpc":"2.0","id":4,"method":"sidefolk/watch.check",
   "params":{"watcher":"battery_low","config":{"below_percent":20},"state":{"low":false}}}
← {"jsonrpc":"2.0","id":4,"result":{"triggered":true,"state":{"low":true},
   "summary":"Battery at 15%, discharging (0:40 left)."}}
```

`config` has been checked against the manifest and has defaults filled in. `state` is whatever you
returned last time (`null` on the first check). See [Watchers](#watchers).

### What Sidefolk never answers

Sidefolk advertises no client capabilities. If your program sends requests of its own,
`sampling/createMessage` (using the user's AI), `roots/list` (listing their folders),
`elicitation/create` and anything else get error `-32601`; only `ping` gets an answer. Every request
has 30 seconds; at most 16 are in flight at once.

## Tools, risk and approvals

Your tool `battery` in extension `dev.sidefolk.system-vitals` becomes **`ext.system-vitals.battery`**
(at most 64 characters in total). Every call goes through Sidefolk's Guard like any built-in tool:

| Risk | What happens when the agent calls it |
|---|---|
| `low` | Runs. |
| `medium` | Asks you first; you may choose "Always allow" for that tool. |
| `high` | Asks you every time. |

A tool's risk is what the manifest says, **medium if it says nothing**, and never below Sidefolk's
floor: if the extension has `network`, any `files.write` folder, or an exec entry that can run
anything, every tool is at least medium. A manifest can raise a tool's risk, never lower it.
Plain MCP servers are always at least medium.

Tool results are marked **untrusted**: the model sees them as outside content, and while untrusted
content is in play every medium or high action asks you, whatever "Always allow" says. Invisible
characters are stripped and results are capped at 20 KB, descriptions at 1 KB and input schemas at
16 KB (larger schemas are refused).

**Tool changes are held.** At install Sidefolk pins a hash of each tool's name, title, description
and schema. If a later run reports something different (or a new tool), that tool is put on hold
until you approve the change in Settings › Extensions. This stops an extension from changing what
a tool claims to do after you installed it.

## Watchers

A watcher kind turns settings and the previous state into "did something happen?". Sidefolk's
watcher engine decides when to check and what to do when a check says `triggered`.

- **Checks are minutes apart.** The agent starts a watcher with the `watch.extension` tool
  (`extension`, `watcher`, `settings` (the manifest calls them `config`), `interval_minutes`,
  `mode`). The interval is **at least 5 minutes and 15 by default**, never faster, so don't use a
  watcher as a timer: a 25-minute focus session would be noticed up to 15 minutes late. For
  something due at a time, let the user set a reminder instead.
- `mode` is `once` (the default: the watcher ends after its first trigger) or `repeat` (it keeps
  checking, and your `state` carries over between checks).
- Extensions read the real clock, so a test of a time-based watcher has to wait or pass the time
  in its settings.
- Make checks **quick and deterministic**; 30 seconds is the hard limit.
- **Trigger on change, not on level.** Keep what you need in `state` (at most 64 KB of JSON) and
  return `triggered: true` only when something new happened: `battery_low` fires once when the
  battery crosses the line, not on every check while it stays low.
- `summary` is one line for the bubble (at most 200 characters; longer is cut). It is shown as
  outside content.
- Extension watchers can ask for the user's attention, but never at the "critical" level.

## Testing locally

1. **Run your program by hand.** Pipe messages in and read what comes out:
   ```sh
   cd extensions/system-vitals
   printf '%s\n' \
     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"disk","arguments":{}}}' \
     | python3 -I main.py
   ```
   Run it from a scratch folder (`cd "$(mktemp -d)"`), as in the quick start: anything it writes
   next to your source would be copied in at install.
2. **Validate and start it:** `sidefolk ext validate <folder>` prints the resolved interpreter, the
   permission sheet, each tool's effective risk, warnings and errors. If the manifest is valid it
   then installs a throwaway copy, starts it in its real sandbox (`initialize`, `tools/list`), and
   prints the tools it offers, any mismatch with the manifest's `tools`, or why it didn't start
   (exit status and the last line it printed to stderr). It exits non-zero on errors; `--no-run`
   skips the start.
3. **Install it** and watch Sidefolk's log (`~/Library/Logs/Sidefolk/`, or `<SIDEFOLK_HOME>/Logs`
   when `SIDEFOLK_HOME` is set; category `extensions`) for start-up errors and your program's stderr.
4. **Reproduce the sandbox.** The profile Sidefolk generated is in
   `~/Library/Application Support/Sidefolk/Sandbox/<id>.sb`; with debug logging on, the log shows the
   full `sandbox-exec` command line. Denials appear in Console.app (filter on `Sandbox`).

## Installing, updating, removing

**Install:** Settings › Extensions › Install from folder…, or drop the folder on the companion.
The sheet shows the name, what it can do in plain words ("Can run /usr/bin/pmset", "No access to
your files or the internet"), warnings about dangerous combinations ("It can read ~/Documents and
use the internet, so it could upload those files"), its tools and watchers. Installing then:

1. validates the manifest and resolves the interpreter;
2. copies the folder (without `.git`, `.DS_Store` and `__pycache__`) into
   `~/Library/Application Support/Sidefolk/Extensions/<id>/` and makes it read-only. Links,
   setuid/setgid files and special files are refused;
3. records the SHA-256, size and mode of every file;
4. starts the program once to list its tools, and pins them.

Before every start Sidefolk checks the files against those hashes. If anything changed (even a
`chmod`), the extension is turned off until you install it again.

**Update:** install the new version's folder the same way. The sheet shows what changes:
permissions gained and lost, tools added and removed. The data folder is kept.

**Turn off / on:** the switch in Settings › Extensions. **Uninstall** removes the extension, its
data folder and its settings.

**When it runs:** a process starts the first time one of its tools or watchers is used and stops
after 5 minutes without use. If it stops unexpectedly 3 times within 5 minutes, Sidefolk turns it
off and tells you.

## Plain MCP servers

Settings › Extensions › Add MCP server takes a name, a command and its arguments, for example
`npx -y some-mcp-server@1.2.3`. Such servers:

- run **without a sandbox, with your full permissions** (and Sidefolk's), which the sheet says;
- get a normal environment (`HOME`, `PATH` with Homebrew, your user name) plus any secrets you
  stored for that server, and start in their own empty data folder;
- have tools named `ext.<name>.<tool>`, at least **medium** risk, with untrusted results;
- trigger a warning when the command downloads new code at every launch (`npx -y package`,
  `uvx package` without a pinned version). Pin a version.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| "python3 isn't installed on this Mac" | Install Apple's command line tools: `xcode-select --install`. |
| "… must be a compiled program" | `run.command` points at a script. Use `"command": "python3", "args": ["main.py"]`. |
| `ModuleNotFoundError` for your own module | Python's isolated mode; add your folder to `sys.path` (see above). |
| `PermissionError: [Errno 1] Operation not permitted` | The sandbox blocked it. Add the folder to `files`, the program to `exec`, or set `network`. |
| A program in `exec` runs but returns nothing useful | It may need a system service the sandbox doesn't open; tell us which program. |
| "… didn't start (it exited with status 1)" | The program crashed or printed something that isn't JSON before answering `initialize`. The message shows the last line it wrote to stderr; `sidefolk ext validate <folder>` starts it in the same sandbox and prints the rest. |
| `OSError: [Errno 1]` from `fork` or `subprocess` | Only extensions that list programs in `exec` may start processes. |
| "… changed since you approved it, so it is on hold" | The tool's description or schema changed. Review and approve in Settings › Extensions. |
| "… was changed on disk, so I turned it off" | Files in the installed copy changed. Install the extension again. |
| "… kept crashing, so I turned it off" | It exited 3 times in 5 minutes, used too much memory or CPU, or wrote a line over 1 MiB. Check the log, fix, turn it back on. |
| "… took too long" | A call ran past 30 seconds. |

## Limits

| What | Limit |
|---|---|
| Manifest | 64 KiB |
| Files in an extension | 10,000 files, 200 MB |
| Tools / watchers per extension | 128 / 32 (a server may list at most 256 tools) |
| `files.read`, `files.write`, `exec` entries | 32 each |
| Message (one line) | 1 MiB; a longer line counts as a crash |
| Requests in flight | 16 |
| Time per request | 30 s |
| Tool description / input schema | 1 KB / 16 KB |
| Tool result shown to the model | 20 KB (an `isError` explanation: 4 KB) |
| Processes running at once | 32, the program included |
| Watcher interval | at least 5 minutes, 15 by default |
| Watcher summary / state | 200 characters / 64 KB |
| Memory / CPU | 512 MB / half a core sustained for 60 s |
| Idle stop | 5 minutes |
| Crash limit | 3 in 5 minutes |
