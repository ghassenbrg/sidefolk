# Writing Sidefolk extensions

An extension gives Sidefolk new **tools** (things the companion can do when you ask) and new
**watcher kinds** (things it can keep an eye on). It is a folder with a manifest and a small program
that speaks [MCP](https://modelcontextprotocol.io) over stdin/stdout. Sidefolk runs that program in
a macOS sandbox built from the permissions the manifest asks for, and you see those permissions in
plain words before you install it.

Examples live in this repository:

| Folder | What it shows |
|---|---|
| [`extensions/hello-folk`](../extensions/hello-folk) | The smallest working extension: one tool, one watcher, ~50 lines of Python. Copy it to start. |
| [`extensions/system-vitals`](../extensions/system-vitals) | Battery, disk, memory and "about this Mac", `battery_low` and `disk_low` watchers, one program in `exec`. |
| [`extensions/git`](../extensions/git) | Folders named per call (`paths`), `git` found by name, the internet, a long `timeout`. |
| [`extensions/images`](../extensions/images) | A file read and a folder written per call, and `media` for the graphics hardware. |
| [`extensions/currency`](../extensions/currency) | The internet only, a cache in its data folder, and a watcher that fires once per crossing. |
| [`skills/sidefolk-extension/templates`](../skills/sidefolk-extension/templates) | Starting points in Python, Node and sh. |

Every folder with a `Sources/` ships with Sidefolk ([Built-in extensions](#built-in-extensions)): those are
Swift programs built on [`extensions/Kit`](../extensions/Kit), so they need nothing installed on the Mac. For a guided path
through this page, install the [`sidefolk-extension` skill](../skills/sidefolk-extension/SKILL.md) in
Claude Code or Codex. You can also add any existing MCP server (see
[Plain MCP servers](#plain-mcp-servers)); it runs without a sandbox and is labelled that way.

## Contents

1. [Quick start](#quick-start)
2. [The manifest](#the-manifest)
3. [Icons](#icons)
4. [Permissions and the sandbox](#permissions-and-the-sandbox)
5. [The protocol](#the-protocol)
6. [Tools, risk and approvals](#tools-risk-and-approvals)
7. [Answering without the AI: commands](#answering-without-the-ai-commands)
8. [Watchers](#watchers)
9. [Pages](#pages)
10. [Testing locally](#testing-locally)
11. [Installing, updating, removing](#installing-updating-removing)
12. [Built-in extensions](#built-in-extensions)
13. [Extensions Sidefolk writes for you](#extensions-sidefolk-writes-for-you)
14. [Plain MCP servers](#plain-mcp-servers)
15. [Troubleshooting](#troubleshooting)
16. [Limits](#limits)

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
  "sidefolk": ">=0.1",
  "description": "Battery, disk and memory at a glance, and a nudge when the battery or the disk runs low.",
  "tagline": "Battery, disk and memory at a glance",
  "folk": "byte",
  "author": "Sidefolk",
  "icon": "icon.pdf",
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
| `sidefolk` | no | Minimum Sidefolk version, written `>=0.1`. |
| `description` | no | At most 300 characters. What it does, in full: Settings shows it under Details, and the install preview shows it whole. |
| `tagline` | no | One line of at most 60 characters, shown under the name in Settings › Extensions (and later in the library). Without one, the description's first sentence is shown. |
| `folk` | no | The folk that appears while it works, e.g. `byte`. |
| `author` | no | At most 100 characters. |
| `icon` | no | A square PNG (64–1024 px) or one-page square PDF in the folder, at most 256 KiB. See [Icons](#icons). |
| `run.command` | yes | `python3`, `node` or `sh`, or a compiled program inside the folder (`bin/server`). Nothing else: no absolute paths, no other interpreters. |
| `run.args` | depends | For `python3`/`node`/`sh` the first argument is the script, a path inside the folder (`main.py`, `src/server.js`). At most 32 arguments. |
| `permissions.network` | no | `true` lets it use the internet. Missing means `false`. |
| `permissions.files.read` | no | Folders it may read, absolute or starting with `~/`. |
| `permissions.files.write` | no | Folders it may read and change. |
| `permissions.exec` | no | Absolute paths of programs it may run, like `/usr/bin/pmset`, or `git` by name ([Programs by name](#programs-by-name)). |
| `permissions.clipboard` | no | `true` lets it read and change the clipboard (D63). Its tools can't be below medium risk: what someone copies is theirs. |
| `permissions.power` | no | `true` lets it keep the Mac awake (macOS power assertions) and ask Sidefolk to keep the person active (`sidefolk/nudge`, D63). |
| `permissions.media` | no | `true` opens the Mac's graphics hardware and media decoders, which image code needs on Apple silicon (Core Image, writing HEIC or PNG from a photo). No files or network come with it. |
| `permissions.network_purpose` | no | With `network`: what you use it for, one line starting with "to" or "for" (≤ 120 characters), e.g. "to find TVs on your local network and stream to them". The sheet adds it to "Can use the network, the internet included": the sandbox can't keep you to the local network (D69). |
| `permissions.udp` | no | With `network`: a UDP port of your own and the packets that come back to it, which live audio and video (WebRTC) needs; `network` alone refuses the bind. No listening TCP server. |
| `permissions.screen` | no | `true` lets it record the screen and the sound the Mac plays (ScreenCaptureKit) and compress it with the hardware video encoder (D69). macOS asks the person to allow **Sidefolk** in Screen Recording: an extension runs as Sidefolk's child, so the permission is Sidefolk's, and this line is what keeps other extensions from using it. Pictures in IOSurfaces need `media` too. Its tools can't be below medium risk. |
| `tools.<name>` | no | Sidefolk's metadata for a tool your program lists: `title`, `risk` (`low`, `medium`, `high`), `category` (`notes`, `memory`, `time`, `watch`, `files`, `web`, `system`, `agents`, `extensions`) and `mutates` (`false` if it only reads). Tool names: `^[a-z0-9_]{1,64}$`. |
| `tools.<name>.paths` | no | Parameters that name a folder or file the person chooses, each `"read"` or `"write"` (at most 4). See [Folders named per call](#folders-named-per-call). |
| `tools.<name>.timeout` | no | Seconds one call may take, 1–300; 30 if missing. For slow work like cloning. |
| `tools.<name>.commands` | no | Sentences that call the tool at once, without the AI: `[{ "say": [...], "input": {...} }]`. See [Answering without the AI](#answering-without-the-ai-commands). |
| `tools.<name>.ai` | no | `false` keeps the tool from Sidefolk's AI: only its commands reach it, and it costs no tokens. Missing means `true`. |
| `words.<list>` | no | Word lists a command's slots can take (`"unit": ["km", "miles", "°F"]`), at most 16 lists and 2,000 words. |
| `watchers.<name>` | no | A watcher kind: `title` (≤ 60), `description` (≤ 300) and `config`, its settings. |
| `pages.<name>` | no | A page in Home (D62): `title` (≤ 40), `symbol` (an SF Symbol), `refresh` (seconds while it is open, 2–3600, 5 if missing), `history` (also read once a minute in the background so its charts reach back a day) and `widget` (its summary is a tile on Today). At most 4. See [Pages](#pages). |
| `background` | no | `true` keeps it running while it is on: it starts with Sidefolk, never stops for being idle, and comes back after a crash (up to the crash limit). For work that must watch all the time (the clipboard, a power assertion). The install preview says so. |
| `palettes.<name>` | no | A pop-up list on a keyboard shortcut (D63): `title` (≤ 40), `hotkey` (`shift+cmd+c`: cmd, ctrl or option, then one key; the person can change it) and `placeholder`. At most 2. See [Palettes](#palettes). |
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

## Icons

`"icon": "icon.png"` (or `"icon.pdf"`) names a file in the extension's folder. Sidefolk shows it in
Settings › Extensions, on the install sheet, and on the approval and result cards of the extension's
tools.

- **PNG:** square, 64 to 1024 pixels on a side (512 is best).
- **PDF:** exactly one page, square (within 5 %), not encrypted: vector shapes stay sharp at any size.
- **At most 256 KiB.** SVG isn't accepted: it is XML that can point at other files and addresses. Export
  it as PDF.
- Draw it **full-bleed**; Sidefolk rounds the corners and adds a hairline border.

The file is checked as an image only (its header, its size, one square page) at install and on every
load, pinned with the other files, and drawn from the installed, read-only copy. Nothing in it is run,
fetched or followed. An extension without an icon, an MCP server, or a draft gets a tile in its folk's
colour (`folk`; one is picked from its name otherwise) with its initial.

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
  Python comes from Apple's developer tools (the folder `xcode-select` points at, currently Python 3.9), which may
  be older than the `python3` you use in Terminal; Homebrew or python.org Pythons are used only if
  the developer tools are missing. Use the standard library, or vendor packages into your folder.
- **Node** is looked up in `/opt/homebrew/bin` and `/usr/local/bin`. **sh** is `/bin/sh`; every
  external command a script runs (even `head`) must be in `exec`.
- **Environment:** only `HOME`, `TMPDIR`, `PATH=/usr/bin:/bin`, `LANG`, `PYTHONDONTWRITEBYTECODE`,
  `SIDEFOLK_EXTENSION_ID` and `SIDEFOLK_DATA_DIR`. Nothing from Sidefolk's own environment.
- **Descriptors:** only stdin, stdout and stderr are inherited.
- **Pictures need `media`.** On Apple silicon Core Image renders on the GPU even when asked for its software
  renderer, and ImageIO reads a photo the hardware decoded through the video decoder service; both fail in the
  sandbox without `"media": true`, which opens exactly those (two IOKit user clients and one service). A
  virtual machine's GPU isn't among them.
- **System services for specific programs.** Some system programs need a system service to work.
  Sidefolk opens it only when that program is in `exec`: `/usr/bin/pmset` gets
  `com.apple.PowerManagement.control` (battery state).
- **Folders that macOS protects** (Documents, Desktop, Downloads): macOS asks *you* whether
  Sidefolk may access them the first time your extension reads them.

### Folders named per call

A fixed `files.read`/`files.write` folder is open whenever the extension runs, and has to be known when
you write the manifest. Most tools work on a folder the person names instead ("clone this into ~/git",
"count the words in ~/Writing"). Declare which parameters are such folders:

```json
"tools": {
  "clone": { "title": "Clone a repository", "paths": { "destination": "write" }, "timeout": 300 },
  "status": { "title": "Repository status", "paths": { "repository": "read" } }
}
```

For a call with such a parameter:

1. Guard treats the path like a built-in file tool's: it must be inside a folder the person shared with
   Sidefolk (Settings › Privacy & Permissions), with write access for `"write"`. If it isn't, Sidefolk's
   agent gets the card "Let Sidefolk work in ~/git?" (other agents and extensions are refused).
   Protected places (system folders, `~/Library`, hidden folders, Sidefolk's own data) are refused
   whatever was shared. Then the tool's own risk decides whether it asks.
2. Your program receives the parameter as a **full, canonical path** (`/Users/ada/git/project`, never
   `~/…`), re-checked right before the call.
3. The call runs in **a process of its own** whose sandbox adds exactly those paths (read-only for
   `"read"`), started for this call and stopped when it returns. Your long-running process never gets
   them. Each such call starts your program afresh (`initialize`, `tools/list`, the call), so keep start-up
   quick.
4. A relative path is refused before any card.
5. That process runs no background work (`SIDEFOLK_ONE_CALL=1`; the Kit skips `ext.background`). Work that must
   outlive the call, like playing a film, can clone the file into the data folder (`clonefile`, no extra space on
   the same disk) and hand it to the main process there, deleting the clone when done; Miraya does (D69).

The install sheet says "Can read and change files in a folder you name, for that request only, once you
approve it". A `"write"` parameter raises every tool to at least medium risk, like a fixed write folder.

### Programs by name

Some programs live in different places on different Macs, and `/usr/bin/git` is a shim that fails inside
the sandbox. Write `"exec": ["git"]` and Sidefolk finds the real one at install: in the developer folder
`xcode-select` points at, the Command Line Tools, Xcode, or Homebrew (never by running `xcrun`, which can
offer to install the developer tools). It pins the program and the helpers it starts itself (git's
`git-remote-http`), opens its installation read-only in the sandbox, and passes its path to your
program as `SIDEFOLK_EXEC_GIT`. `git` is the only name Sidefolk knows today. If it isn't installed,
validation says so and suggests `xcode-select --install`.

A program found by name isn't "can run anything": it may start only its own helpers. Git in the shipped
extension still runs with `core.hooksPath=/dev/null`, https only, no credentials and no system or
global configuration.
- **Resources:** a watchdog stops your program (and everything it started) if it uses more than
  512 MB of memory, or more than half a CPU core for a minute.

## The protocol

Your program reads JSON-RPC 2.0 messages from stdin, one per line, and writes one JSON message per
line to stdout. **Write nothing else to stdout.** Logs and debugging go to stderr; Sidefolk keeps
the last 16 KB for its diagnostics.

**Answer every message that has an `id`** (requests); ignore those that don't (notifications).

### Startup

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Sidefolk","version":"0.1.0"}}}
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
The one exception is Sidefolk's own [built-in extensions](#built-in-extensions): their descriptions
ship inside the signed app, so the model reads them (D39).

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
floor: if the extension has `network`, any `files.write` folder, a `"write"` folder parameter, or an exec entry
that can run anything, every tool is at least medium. A manifest can raise a tool's risk, never lower it.
Plain MCP servers are always at least medium.

Tool results are marked **untrusted**: the model sees them as outside content, and while untrusted
content is in play every medium or high action asks you, whatever "Always allow" says. Invisible
characters are stripped and results are capped at 20 KB, descriptions at 1 KB and input schemas at
16 KB (larger schemas are refused).

**Tool changes are held.** At install Sidefolk pins a hash of each tool's name, title, description
and schema. If a later run reports something different (or a new tool), that tool is put on hold
until you approve the change in Settings › Extensions. This stops an extension from changing what
a tool claims to do after you installed it.

## Answering without the AI: commands

Some requests need no thinking: "what's 12*7", "time in Tokyo", "new uuid". Waiting seconds for an AI to
decide to call your tool is slower and costs the person's quota. A tool can list **commands**: whole
sentences that call it at once, with no AI, and you decide per tool who may reach it:

| You write | Who reaches the tool |
|---|---|
| nothing | The AI only (the default). |
| `commands` | Both: the sentences you listed run at once, and the AI calls it for everything else. |
| `commands` and `"ai": false` | Only your sentences. The model never sees the tool, so it costs no tokens. |

```json
"tools": {
  "current_time": {
    "title": "Time around the world",
    "commands": [
      {
        "say": ["time in {place:place}", "what time is it in {place:place}"],
        "input": { "places": ["{place}"] }
      }
    ]
  },
  "flip": {
    "title": "Flip a coin", "ai": false,
    "commands": [ { "say": ["flip a coin", "heads or tails"] } ]
  }
}
```

**Sentences.** Each `say` sentence matches a whole request, in any case, after Sidefolk drops polite words
("please", "hey Mochi,", "thanks") and the final punctuation. Write the variants people say ("what's",
"whats", "what is"). Sentences are English, like the rest of Sidefolk's own understanding.

**Slots.** `{name}` takes any words; `{name:kind}` takes one kind. The tool gets the value typed:

| Kind | Matches | The tool gets |
|---|---|---|
| `text` (or no kind) | Any words, up to 200 characters | a string |
| `word` | One word or code: `usd`, `km/h` | a string |
| `number` / `integer` | `12`, `-3.5`, `1,000` / `42` | a number |
| `expression` | Arithmetic: digits, `+ - * / ^ % × ÷`, parentheses, `of`, `sqrt`, `round`, `pi`… (not a date or a phone number) | a string |
| `place` | A town, country or time zone: up to six words of letters | a string |
| `url` | A web address, with or without `https://` | a string with `https://` |
| `date` | `today`, `tomorrow`, `2026-12-25`, `25 December 2026`, `December 25` | a string as typed |
| `list` | Two to twenty things: `tea, coffee or juice` | an array of strings |
| a list in `words` | Exactly one of your words (`{from:unit}` with `"words": { "unit": [...] }`) | the word as typed |

Your own word lists are the way to keep two extensions apart: Calculator's `{from:unit}` and Currency's
`{from:currency}` make "5 pounds in kg" a unit conversion and "5 pounds in euros" money.

**Input.** Without `input`, each slot fills the argument of the same name. With it, write the arguments: a
value `"{slot}"` is replaced by the slot's value (a `list` slot inside an array joins it), and anything else
is passed as written (`"kind": "uuid"`, `"folder": "~/Desktop"`). Every slot must be used, and every sentence
of one command must have the same slots. If the slot's type doesn't fit your schema (a number where you want
a string), Sidefolk converts it.

**What Sidefolk refuses** (`sidefolk ext validate` says which field and why), so no command can swallow what
people say:
- a sentence without a word of its own (two letters or more). The one exception is a lone
  `{…:expression}`, so "12*7" can be a sum;
- a sentence that starts with a slot taking any words (`text`, `word`, `place`, `list`), or two of them with
  nothing but a space between;
- replies anyone types: "yes", "no", "ok", "thanks", "stop", "cancel", "help", "undo", "hello"…;
- more than 3 slots or 80 characters a sentence, 12 sentences a command, 8 commands a tool, 64 sentences an
  extension; a sentence that says the same as another; `"ai": false` on a tool without commands.

**When a sentence is yours.** Sidefolk's own understanding goes first (reminders, notes, watches, quiet,
"new conversation"…): a command never replaces them. Then the commands of switched-on extensions. If two
extensions both claim a sentence, the AI gets it. While the person types, the line under the field says
which extension answers ("World Clock · The time in Tokyo · no AI"). The answer appears in the Ask panel as a
card and is read aloud for a spoken request.

**Guard still decides.** A command is the person's words, but your manifest chose the tool and its input, so
the call goes through Guard as Sidefolk's agent in a clean turn would: a tool that only computes runs; one
that uses the internet, a folder or anything risky asks first (and "Always allow" given to the AI for that
tool covers commands too). An address the person typed counts as typed.

**When the tool can't answer.** Return an error (`isError`, or `Problem` in the Kit) for input you don't
understand ("I don't know the place “my head”"). Sidefolk then hands the sentence to the AI, as if your
command didn't exist; without an AI the person sees your message.

**Commands, the AI, or both?**
- *Commands only* (`"ai": false`): the answer never needs judgement, and the AI gains nothing from the tool
  (a coin flip, a UUID, a fixed status). It costs no tokens on any request.
- *Both*: the common requests have a clear shape ("100 usd in eur") but people also ask in ways no list of
  sentences covers ("is it a good time to call my sister in Tokyo?").
- *AI only*: what to do depends on context, or the inputs are free text that needs reading (summaries,
  searches, anything that writes).

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

## Pages

An extension can add a whole page to Home (D62): a line in the sidebar under **Extensions**, the page itself, and,
when the manifest asks, a tile on Today. You say what is true; Sidefolk draws it with its own parts, in the
person's theme, light or dark, and right to left. No HTML, no drawing of your own: a page can't look like Sidefolk's
own controls (an approval card, say), and it works the same in every theme.

```json
"pages": {
  "mac": { "title": "Your Mac", "symbol": "gauge.with.dots.needle.67percent", "refresh": 3, "history": true, "widget": true }
}
```

Sidefolk asks for it with `sidefolk/page.render {page, language}` (`language` is the person's, `en`, `fr`, `ar`,
for an extension that speaks it) and expects `{page: {summary, sections}}`. In the Kit:

```swift
ext.page("mac") { args in
    Page(summary: Summary("All good", detail: "CPU 12% · 214 GB free", tone: .good),
         sections: [Section("Right now", [.gauge("CPU", "12%", fraction: 0.12, tone: .good, caption: "Most: Xcode"),
                                          .chart(id: "cpu", "Processor", unit: "%", max: 100, series: [Series("total", "CPU", 12)])])])
}
```

- **`summary`**: `title`, `detail`, `tone`, `symbol`. The banner on top of the page, and the Today tile.
- **Parts** (`type`): `gauge` (a ring: `label`, `value`, `fraction` 0–1, `caption`), `stat` (`label`, `value`, `caption`),
  `chart` (`id`, `title`, `unit`, `max`, `caption`, `series` of `{key, label, value, display}`, at most 4), `bars`
  (`title`, `caption`, `items` of `{label, value, fraction}`), `facts` (`title`, `items` of `{label, value}`), `note`
  (`text`), and `ask` (`label`, `ask`: a button that asks Sidefolk the sentence, as if typed in Ask, so it reaches
  your commands, or the AI, through Guard). Most take a `tone`: `good`, `warn`, `bad`, `info` or `neutral`.
- **Charts say only the value now.** Sidefolk keeps the past: every value for 15 minutes, then one a minute (the
  minute's highest) for a day, under `PageHistory/`, removed with the extension. The person picks 10 minutes, an
  hour or a day. Keep a chart's `id` and its series' `key`s stable, or its past is lost.
- **When it runs.** While the page is open, every `refresh` seconds. With `history` or `widget`, also once a minute
  while Sidefolk runs, and the install preview says so. Keep a render quick: it is a 30-second call like any other.
- **Switches and buttons** (D63): `switch` (`label`, `detail`, `on`, `tool`, `input`) and `button` (`label`, `tool`,
  `input`, `style`: `primary`, `secondary` or `destructive`, `symbol`) run one of your own tools as the person, through
  Guard, then read the page again. A switch adds `on` (its new state) to `input`. `tool` is your tool's own name
  (`set_option`), never another extension's. A tool only switches and buttons use can be `"ai": false`.
- **Heads-ups.** Under the page, each of your watchers is a switch: on, it checks every five minutes in `repeat`
  mode and the companion tells the person when it triggers. So a watcher should trigger on change (see Watchers).
- **What Sidefolk refuses or drops.** A page over 128 KB, or one without `sections` or `summary`, fails. Within it, a
  part Sidefolk doesn't know is skipped (so a newer extension still shows on an older Sidefolk), as is a part
  missing what it needs; at most 16 sections, 24 parts a section, 24 items a list. Every text is cleaned of hidden
  characters and clipped. A page is your text: it is never shown to a model.
- Pages came during 0.1.0's snapshots: a snapshot from before them (489 and older) refuses the manifest, because it doesn't
  know `pages`. Write `"sidefolk": ">=0.1"` as usual.

## Running in the background, palettes and nudges

Some features can't wait to be asked: a clipboard history has to see every copy, keeping a Mac awake has to hold
for hours. With `"background": true` your program runs while the extension is on. In the Kit, `ext.background { … }`
runs beside requests (it shares the main actor, so it must `await`, never spin); stdin is read off the main actor.

**Palettes** pop up over any app on their shortcut, like Spotlight, without taking focus from the app in front. As
the person types, Sidefolk asks `sidefolk/palette.query {palette, query}` → `{items: [{id, title, detail, kind,
pinned, actions}], note}` (`kind`: `text`, `link`, `image`, `file`, `color`, `code`; at most 200 items). Return,
Shift-Return, ⌘P and ⌘⌫ send `sidefolk/palette.choose {palette, item, action}` with `choose`, `plain`, `pin` or
`delete` (the last three only when the item lists them in `actions`) → `{close, paste, message}`. With `paste`,
Sidefolk closes the palette and presses ⌘V in the app in front: put what to paste on the clipboard first (that needs
`permissions.clipboard`). Pasting needs Accessibility for Sidefolk; until the person allows it, what they chose is on
the clipboard. Your page shows the shortcut, and the person can change it there.

```swift
ext.palette("history", query: { query in PaletteList(items(matching: query)) },
            choose: { id, action in copy(id); return PaletteChoice(close: true, paste: true) })
```

**Nudges.** `ext.send("sidefolk/nudge")` asks Sidefolk to keep the person active: it moves the pointer by nothing
where it is, which resets macOS's idle time (what chat and meeting apps watch) without anything moving on screen.
Only with `permissions.power`, at most one every 20 seconds whatever you send, and only once the person allowed
Accessibility. (macOS's own "user is active" call doesn't reset the idle time those apps read.)

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

**Turn off / on:** the switch in Settings › Extensions. **Uninstall** (under the extension's details)
removes the extension, its data folder and its settings.

**Finding one:** Settings › Extensions lists what is installed one line each (name, what it does, its
switch); a click, Space or Return opens the details (where it came from, what it may do, its tools,
the request to try, Review and Uninstall). One whose tools changed opens by itself. The search reads
names, descriptions, tool titles and names, what each may do ("internet" finds those that can reach
it; "No access to…" isn't searched), examples, authors, ids and server commands, ignoring case, accents
and width, and says under a row what matched when its line doesn't show it. All / On / Off narrow the
list, with how many each holds for the words typed; the choice is remembered. Drafts and skills,
neither on nor off, are under All. ⌘F searches; ↑ and ↓ move between rows, → and ← open and close.

**When it runs:** a process starts the first time one of its tools or watchers is used and stops
after 5 minutes without use. If it stops unexpectedly 3 times within 5 minutes, Sidefolk turns it
off and tells you.

## Built-in extensions

These ship with Sidefolk (`extensions/catalog.json`). Each is a small Swift program built with the app on
[`extensions/Kit`](../extensions/Kit) and signed inside it (`Contents/Resources/Extensions/<folder>/bin/`),
so none needs Python, Node or anything else installed; Git needs git, which it exists to use.

Several answer common sentences at once, without the AI (D50): Calculator ("what's 12*7", "15% of 80", "convert
5 km to miles", "days until 25 December"), World Clock ("time in Tokyo"), Currency ("100 usd in eur", "usd to
eur"), Playtime ("pick a number between 1 and 6", "pick one: tea, coffee or juice"), Dev Toolbox ("new uuid",
"3 uuids", "timestamp 1730000000"), QR Codes ("qr code for example.com", saved on the Desktop) and System
Vitals ("about this mac"). Settings › Extensions lists each one's sentences under Details. Text transforms and
checksums have none on purpose: Sidefolk tidies a typed sentence (quotes, final punctuation, spaces), and a
hash of tidied text would be the wrong answer.

| Extension | Starts | Permissions | What it does |
|---|---|---|---|
| Git | On | The internet, `git`, a folder named per call | Clone, status, pull, log |
| World Clock | On | None | The time anywhere, conversions with daylight saving |
| System Vitals | On | `pmset` | Battery, disk, memory, about this Mac; low battery and disk watchers |
| Weather | On | The internet (Open-Meteo) | Forecasts, sunrise, sunset and the moon, where the person is when they share it (D48); a rain watcher |
| Calculator | On | None | Exact sums and percentages, units, date maths |
| Currency | On | The internet (the ECB's daily file) | Money between the euro and 30 currencies; a rate watcher |
| Playtime | On | None | A trivia quiz with a score, a random number or pick from a list (coins, dice and rock, paper, scissors are the companion's own `companion.toss`) |
| Images | On | A folder named per call, `media` | Photo details; copies converted, smaller or without location |
| PDF Tools | Off | A folder named per call | Details, text, combine, take pages out |
| QR Codes | Off | A folder named per call, `media` | Make a QR code picture, read one |
| Archives | Off | `zip`, `ditto`, a folder named per call | Zip files and folders, open zip files |
| Dev Toolbox | Off | A file named per call | JSON, base64, URL and hex, JWTs, timestamps, UUIDs, checksums |
| Feeds | Off | The internet | Latest posts from RSS and Atom; a new-post watcher |

Every tool of an extension that is on reaches the model with each request, so only the everyday ones start
on. The ones that are off cost one line: the model is told their names and what they do, and suggests
switching one on in Settings › Extensions when it would help. Nothing writes over an original: pictures,
PDFs and zips are always new files.

They are installed at launch like any extension (validated, copied, locked, pinned, started once), with
three differences:

- **They can be switched off, not uninstalled**: they would come back with the next launch.
- **They follow the app.** At every launch Sidefolk compares the shipped files with the installed copy
  and reinstalls when they differ (an update, or a damaged copy), keeping whether the person had it on.
  An update that asks for more (a new permission) is installed switched off, with a notice.
- **Their tool descriptions reach the model**: first-party text from the app, not a stranger's.

If you install your own copy of a built-in extension (same id) from a folder, Sidefolk keeps it until the
app brings a strictly newer version, then replaces it and says so. A built-in extension this Mac can't run
(no git) is listed in Settings with the reason and a Try Again button. There is no locked "core" tier:
see docs/research/extensions-catalog.md.

## Extensions Sidefolk writes for you

When a request needs something no tool does, Sidefolk's AI can offer to build an extension (the
`build-extension` skill, D39). It proposes it in plain words and waits for a yes, then:

1. `extensions.draft` writes the draft into `ExtensionDrafts/local.<name>/` under Sidefolk's data folder:
   text files only (`.py .js .mjs .cjs .sh .json .txt .md .csv`, at most 20 files and 1 MB), never
   executable, no icon. Sidefolk sets its id (`local.<name>`) and author ("Sidefolk, for you").
2. The draft is checked exactly like an install, and started once **with every permission removed**
   (no network, no folders, no programs), to see that it answers. The AI reads the result and fixes it.
3. `extensions.review` opens the normal install preview in a window of its own. The person reads what
   it may do and installs it, or doesn't. Nothing is installed any other way.

Only Sidefolk's own agent (or the person) can use these tools, never in a request that read outside
content, and they are never offered to other agents. Drafts are listed under Settings › Extensions ›
Drafts (Review…, Show in Finder, Move to Trash). An installed draft is "Written for you"; like any
extension not shipped with the app, its descriptions don't reach the model, so its tools are known by
their titles and parameter names, from the person's next request.

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
| "… needs Python, which isn't on this Mac", "Git needs Git, …" | Install Apple's command line tools: `xcode-select --install` (or git with Homebrew). The built-ins other than Git need nothing. |
| "~/x isn't shared with Sidefolk for this." | A folder parameter named a folder outside what the person shared, or one replaced by a link since Guard looked. |
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
| Icon | 256 KiB; PNG 64–1024 px square, or a one-page square PDF |
| Folder parameters per tool | 4 |
| `files.read`, `files.write`, `exec` entries | 32 each |
| Message (one line) | 1 MiB; a longer line counts as a crash |
| Requests in flight | 16 |
| Time per request | 30 s; up to 300 s with `tools.<name>.timeout` |
| Tool description / input schema | 1 KB / 16 KB |
| Tool result shown to the model | 20 KB (an `isError` explanation: 4 KB) |
| Processes running at once | 32, the program included |
| Watcher interval | at least 5 minutes, 15 by default |
| Palettes | 2 per extension; 200 items a list; 10 s per query or choice |
| Nudges | one every 20 seconds, with `permissions.power` |
| Pages | 4 per extension; 128 KB each; refresh 2–3600 s; 16 sections, 24 parts each, 24 items a list, 4 lines a chart |
| Watcher summary / state | 200 characters / 64 KB |
| Memory / CPU | 512 MB / half a core sustained for 60 s |
| Idle stop | 5 minutes |
| Crash limit | 3 in 5 minutes |
