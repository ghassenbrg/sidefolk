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
| sidefolk-addons [`extensions/system-vitals`](https://github.com/ghassenbrg/sidefolk-addons/tree/main/extensions/system-vitals) | Battery, disk, memory and "about this Mac", `battery_low` and `disk_low` watchers, one program in `exec`, on the Kit. |
| sidefolk-addons [`extensions/git`](https://github.com/ghassenbrg/sidefolk-addons/tree/main/extensions/git) | Folders named per call (`paths`), `git` found by name, the internet, a long `timeout`. |
| sidefolk-addons [`extensions/images`](https://github.com/ghassenbrg/sidefolk-addons/tree/main/extensions/images) | A file read and a folder written per call, and `media` for the graphics hardware. |
| sidefolk-addons [`extensions/currency`](https://github.com/ghassenbrg/sidefolk-addons/tree/main/extensions/currency) | The internet only, a cache in its data folder, and a watcher that fires once per crossing. |
| sidefolk-addons `extensions/playtime`, `keep-awake`, `clipboard`, `miraya` | Games, pages, palettes and background work ([Pages](#pages), [Games](#games)). |
| [`skills/sidefolk-extension/templates`](../skills/sidefolk-extension/templates) | Starting points in Python, Node and sh. |

Sidefolk's own extensions are Swift programs on [`extensions/Kit`](../extensions/Kit), so they need nothing installed on
the Mac, and they all live in the gallery ([Seed packs and the gallery](#seed-packs-and-the-gallery)). For a guided path
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
10. [Games](#games)
11. [Surfaces and scenes](#surfaces-and-scenes)
12. [Rich pages, commands in every language, entries, settings, AI help](#rich-pages-commands-in-every-language-entries-settings-ai-help)
13. [Speaking the person's language](#speaking-the-persons-language)
14. [Testing locally](#testing-locally)
15. [Installing, updating, removing](#installing-updating-removing)
16. [Seed packs and the gallery](#seed-packs-and-the-gallery)
17. [Extensions Sidefolk writes for you](#extensions-sidefolk-writes-for-you)
18. [Plain MCP servers](#plain-mcp-servers)
19. [Troubleshooting](#troubleshooting)
20. [Limits](#limits)

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

Then install it from **Settings › Add-ons › Install from folder…** (or drop the folder on the
companion), read the permission sheet, and click Install. Ask Sidefolk to use it: "say hello to Ada".

## The manifest

`sidefolk-extension.json` at the top of the folder, at most 64 KiB. Decoding is strict: **any key
not listed on this page is an error**, so a typo never silently changes what an extension may do.

```json
{
  "id": "dev.example.pocket-vitals",
  "name": "Pocket Vitals",
  "version": "1.0.0",
  "sidefolk": ">=0.1",
  "description": "Quick answers on battery, disk and memory, and a nudge when the battery or the disk runs low.",
  "tagline": "Quick answers on battery, disk and memory",
  "folk": "byte",
  "author": "You",
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
| `id` | yes | Reverse-DNS, lowercase: `^[a-z0-9]+(\.[a-z0-9-]+)+$`, at most 64 characters. The installed copy lives in `Extensions/<id>/`. The last part (`pocket-vitals`) names its tools, so it must be unique among your extensions. |
| `name` | yes | 1–60 characters of plain text, shown everywhere. "Sidefolk" and the companions' names, however written, in any language, are kept for Sidefolk's own signed packs. |
| `version` | yes | `1.0` or `1.0.0`, optionally with `-beta.1`. |
| `sidefolk` | no | Minimum Sidefolk version, written `>=0.1`. |
| `description` | no | At most 300 characters. What it does, in full: Settings shows it under Details, and the install preview shows it whole. |
| `tagline` | no | One line of at most 60 characters, shown under the name in Settings › Add-ons and the Gallery. Without one, the description's first sentence is shown. |
| `examples` | no | Up to 3 requests to try, one line of at most 120 characters each: a button under the extension in Settings › Add-ons that fills the Ask panel (nothing is sent until the person presses Return), and searched there. Translated in `strings/`. |
| `services` | no | The public services the program talks to: `[{"name": "Open-Meteo", "hosts": ["api.open-meteo.com"]}]`, needs `permissions.network`. Up to 8, each with up to 16 lower-case host names. Shown on the install sheet and in Settings › Trust. The sandbox can't hold a program to it, so anyone else's is said as their word; only a pack Sidefolk signed is believed (D47, D98). |
| `replaces` | no | Ids of extensions this one does everything of: while this one is on, they rest (their tools step aside, D67). Only between Sidefolk's own signed packs. |
| `folk` | no | The folk that appears while it works, e.g. `byte`. |
| `author` | no | At most 100 characters; the frame of your surface says it, unless it is one of those names and the pack isn't Sidefolk's. |
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
| `permissions.output_mute` | no | Allows an extension to ask Sidefolk to temporarily mute the Mac's default sound output, affecting every app. The install/update sheet names this separately; tools are at least medium risk. A helper owned by Sidefolk restores the previous mute state when the extension or Sidefolk stops. Unsupported devices report a failure. Send `sidefolk/output_mute` with `request` (a UUID), `enabled` (a boolean) and an increasing positive `sequence`; `sidefolk/output_mute.result` returns that request and `ok`, and `sidefolk/output_mute.failed` reports later device errors with the enabling `sequence`, so ignore failures for an older request. Do not claim the output is muted before confirmation. |
| `tools.<name>` | no | Sidefolk's metadata for a tool your program lists: `title`, `risk` (`low`, `medium`, `high`), `category` (`notes`, `memory`, `time`, `watch`, `files`, `web`, `system`, `agents`, `extensions`) and `mutates` (`false` if it only reads). Tool names: `^[a-z0-9_]{1,64}$`. |
| `tools.<name>.paths` | no | Parameters that name a folder or file the person chooses, each `"read"` or `"write"` (at most 4). See [Folders named per call](#folders-named-per-call). |
| `tools.<name>.timeout` | no | Seconds one call may take, 1–300; 30 if missing. For slow work like cloning. |
| `tools.<name>.commands` | no | Sentences that call the tool at once, without the AI: `[{ "say": [...], "input": {...} }]`. See [Answering without the AI](#answering-without-the-ai-commands). |
| `tools.<name>.ai` | no | `false` keeps the tool from Sidefolk's AI: only its commands reach it, and it costs no tokens. Missing means `true`. |
| `tools.<name>.reach` | no | `"paired"`: the tool's calls go only to a device the person paired (a TV whose code they compared), which your program confirms per call (`sidefolk/paired.check`). **Honoured for Sidefolk's own extensions only** (D72); anyone else's is accepted and ignored. See [A device the person paired](#a-device-the-person-paired). |
| `tools.<name>.device` | no | With `reach`: the parameter naming the device (`"tv"`), not a `paths` one. Missing means the device in use now (stop, pause). |
| `words.<list>` | no | Word lists a command's slots can take (`"unit": ["km", "miles", "°F"]`), at most 16 lists and 2,000 words. |
| `watchers.<name>` | no | A watcher kind: `title` (≤ 60), `description` (≤ 300) and `config`, its settings. |
| `pages.<name>` | no | A page in Home (D62): `title` (≤ 40), `symbol` (an SF Symbol), `refresh` (seconds while it is open, 2–3600, 5 if missing), `history` (also read once a minute in the background so its charts reach back a day) and `widget` (its summary, with its main switch if it has one, is a tile on Today). At most 4. See [Pages](#pages). |
| `background` | no | `true` keeps it running while it is on: it starts with Sidefolk, never stops for being idle, and comes back after a crash (up to the crash limit). For work that must watch all the time (the clipboard, a power assertion). The install preview says so. |
| `palettes.<name>` | no | A pop-up list on a keyboard shortcut (D63): `title` (≤ 40), `hotkey` (`shift+cmd+c`: cmd, ctrl or option, then one key; the person can change it) and `placeholder`. At most 2. See [Palettes](#palettes). |
| `watchers.<name>.config.<key>` | no | `type` (`integer`, `number`, `string`, `boolean`), and optionally `description`, `default`, `required`, `minimum`, `maximum`. |
| `tools.<name>.summary` | no | The sentence for a call, with its arguments ([A call in one sentence](#a-call-in-one-sentence)); believed for Sidefolk's own. |
| `permissions.ai` | no | `purpose` and `daily_cap`: the person's AI, for words only ([AI help](#ai-help)). |
| `games` | no | Old, until Sidefolk snapshot B (D101): [Games](#games). |
| `assets` | no | The name of one folder of pictures and sounds ([Pack assets](#pack-assets)). |
| `surfaces` | no | Panels and overlays you draw ([The manifest](#the-manifest-1)). |
| `choices`, `parts`, `carry` | no | What commands' sentences are made of ([Commands with slots](#commands-with-slots-in-every-language)). |
| `settings` | no | What the host keeps for you ([Settings](#settings)). |
| `entries`, `drops` | no | Items in Sidefolk's menus and Ask, and offers for a drop ([Entries and drop actions](#entries-and-drop-actions)). |
| `settings_from`, `carries` | no | What the app used to keep for this work, for Sidefolk's own ([Settings](#settings)). |

**Other languages.** The manifest is English; its words in other languages are files of their own,
`strings/<language>.json` beside it (see [Speaking the person's language](#speaking-the-persons-language)). A copy of
Sidefolk from before them ignores the folder; a key in the manifest itself would make it refuse the manifest.

**Folder name.** When you validate a folder, its name should be the id or the id's last part
(`pocket-vitals`); otherwise you get a warning (usually a copied template with an old id).

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
Settings › Add-ons, the Gallery, the install sheet, and the permission slips and result cards of the extension's
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
   Sidefolk (Settings › Trust › Folders Sidefolk can use), with write access for `"write"`. If it isn't, Sidefolk's
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

**Answer every message that has an `id`** (requests). Notifications have no `id` or reply; handle the ones your
extension uses, even while a request is waiting. The Swift Kit serializes requests while continuing to deliver notices.

### Startup

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Sidefolk","version":"0.1.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"pocket-vitals","version":"1.0.0"}}}
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
a tool from the extension “Pocket Vitals”", plus your input schema with its free text
(`description`, `title`, `examples`, `default`) removed. Give tools clear titles (the manifest's
`tools.<name>.title`, else the program's `title`) and parameters self-explanatory names
(`below_percent`, not `n`); types, `enum`, `minimum`/`maximum` and `maxLength` stay and are enforced.
The one exception is Sidefolk's own [signed packs](#seed-packs-and-the-gallery): their descriptions come under Sidefolk's
signature, so the model reads them (D39, D98).

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

### A device the person paired

For a tool whose manifest says `"reach": "paired"`, in one of Sidefolk's own extensions, Sidefolk may ask before it
decides whether to ask the person: only for its own agent, after the run read outside content, in Auto or Full access.

```json
→ {"jsonrpc":"2.0","id":5,"method":"sidefolk/paired.check",
   "params":{"tool":"share_screen","arguments":{"tv":"living room"}}}
← {"jsonrpc":"2.0","id":5,"result":{"paired":true,"device":"6f1c2b9a-1111-4222-8333-944455556666"}}
```

`arguments` holds only the parameter `device` names (nothing for a tool without one). Find the device exactly as the
call will, and answer `paired` with its `device` id only when the person paired it and the connection will demand its
pinned key; `{"paired": true}` with no device when the call reaches no device at all (stopping what isn't running);
`{"paired": false}` otherwise. Sidefolk then puts the id in that parameter, so the call reaches what you confirmed:
take an id there. On the Kit: `ext.paired { tool, args in … }` returning `.device(id)`, `.nothing` or `.unpaired`.
A call confirmed this way runs without a card in Auto and Full access even after outside content, unless it also
carries a link the person didn't type, or a file whose folder they didn't allow for that call (D72).

### What Sidefolk never answers

Sidefolk advertises no client capabilities. If your program sends requests of its own,
`sampling/createMessage` (using the user's AI), `roots/list` (listing their folders),
`elicitation/create` and anything else get error `-32601`; only `ping` gets an answer. Every request
has 30 seconds; at most 16 are in flight at once.

## Tools, risk and approvals

Your tool `battery` in extension `dev.example.pocket-vitals` becomes **`ext.pocket-vitals.battery`**
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
until you approve the change in Settings › Add-ons. This stops an extension from changing what
a tool claims to do after you installed it.

### A call in one sentence

`tools.<name>.summary` says what a call is about to do, for its approval card and History: `"Clone {url} into {destination}"`
rather than the title and its arguments. Each `{parameter}` is the call's own argument: text and numbers as they are,
a list of texts joined in the person's language, a parameter in `paths` shown as a short path. Several forms choose by
what the call says, the first that holds:

```json
"summary": [{ "unless": "from", "text": "Convert {time} here" }, { "text": "Convert {time} in {from}" }]
```

`if` wants the argument there and not false, `unless` missing or false. At most 4 forms of 120 characters, plain text, the
only braces being parameters. A language's `tools.<name>.summary` gives one text per form with the same parameters. If an
argument it needs is missing or isn't words, the card shows the title and the arguments. Only a pack Sidefolk signed is
shown this way (D98, T1): anyone else's approval card keeps the title and the exact arguments, whatever the manifest says.

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
- more than 3 slots or 80 characters a sentence, 24 sentences a command, 32 commands a tool, 400 sentences an
  extension; a sentence that says the same as another; `"ai": false` on a tool without commands.

**When a sentence is yours.** Sidefolk's own understanding goes first (reminders, notes, watches, quiet,
"new conversation"…): a command never replaces them. Then the commands of switched-on extensions. If two
extensions both claim a sentence, the AI gets it. While the person types, the line under the field says
which extension answers ("World Clock · The time in Tokyo · no AI"). The answer appears in Ask as a
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
- `summary` is one line for the card (at most 200 characters; longer is cut). It is shown as
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

Sidefolk asks for it with `sidefolk/page.render {page, language}` (`language` is the person's: `en`, `fr`, `pt-BR`,
`zh-Hans`, `ar`…, see [Speaking the person's language](#speaking-the-persons-language)) and expects
`{page: {summary, sections}}`. In the Kit:

```swift
ext.page("mac") { args in
    Page(summary: Summary("All good", detail: "CPU 12% · 214 GB free", tone: .good),
         sections: [Section("Right now", [.gauge("CPU", "12%", fraction: 0.12, tone: .good, caption: "Most: Xcode"),
                                          .chart(id: "cpu", "Processor", unit: "%", max: 100, series: [Series("total", "CPU", 12)])])])
}
```

- **`summary`**: `title`, `detail`, `tone`, `symbol`, and `control`. The banner on top of the page, and the Today tile.
  `control` is your extension's main switch or button (a `switch` or `button` part, below; D67): Sidefolk puts it on
  the banner, on the Today tile and, for a switch, beside the page's row in the sidebar, so a feature that is mostly
  on or off (Keep Awake) is one click from where people are. The tile and the sidebar show the last reading, so give
  a page with a `control` a `widget`, which is read once a minute. In the Kit:
  `Summary("Awake until 18:00", detail: "25 min left", control: .toggle("Keep awake", on: true, tool: "keep_awake"))`.
- **How it fills the window** (D67): a section with numbers (`gauge`, `stat`), two or more cards (`chart`, `bars`,
  `facts`), only notes, or only buttons and questions runs across the page; any other (one card with its note, a few
  switches) sits beside its neighbours, two or three to a row in a wide window. Cards in a row share its width and
  height. A page with numbers or cards may grow wide (centred); a page of switches stays a readable column. So group
  what belongs together into one section, and give a long detail its own section.
- **A page is optional.** The person can take a page out of the sidebar (it stays in one menu row at the sidebar's foot) and a
  tile off Today. Give an extension a page when it has something to look at or several choices; a feature that is mostly an
  on/off switch needs a `widget` with a summary `control` more than a page of its own.
- **Parts** (`type`): `gauge` (a ring: `label`, `value`, `fraction` 0–1, `caption`), `stat` (`label`, `value`, `caption`),
  `chart` (`id`, `title`, `unit`, `max`, `caption`, `series` of `{key, label, value, display}`, at most 4), `bars`
  (`title`, `caption`, `items` of `{label, value, fraction}`), `facts` (`title`, `items` of `{label, value}`), `note`
  (`text`), and `ask` (`label`, `ask`: a button that asks Sidefolk the sentence, as if typed in Ask, so it reaches
  your commands, or the AI, through Guard). Most take a `tone`: `good`, `warn`, `bad`, `info` or `neutral`.
  Tones have meanings (ARCHITECTURE › Colour meaning): `good` green for done, healthy, on; `warn` amber for waiting or
  needs a look; `bad` red only for an error, a failure or a real risk; `info` the accent, for news; `neutral` for
  off, paused, nothing happened. Paused or off is `neutral`, not `warn`; a tone always comes with words.
- **Charts say only the value now.** Sidefolk keeps the past: every value for 15 minutes, then one a minute (the
  minute's highest) for a day, under `PageHistory/`, removed with the extension. The person picks 10 minutes, an
  hour or a day. Keep a chart's `id` and its series' `key`s stable, or its past is lost.
- **When it runs.** While the page is open, every `refresh` seconds. With `history` or `widget`, also once a minute
  while Sidefolk runs, and the install preview says so. Keep a render quick: it is a 30-second call like any other.
- **Switches and buttons** (D63): `switch` (`label`, `detail`, `on`, `tool`, `input`) and `button` (`label`, `tool`,
  `input`, `style`, `symbol`, `detail`, `disabled`) run one of your own tools as the person, through Guard, then read
  the page again. A switch adds `on` (its new state) to `input`. `tool` is your tool's own name (`set_option`), never
  another extension's. A tool only switches and buttons use can be `"ai": false`. **Emphasis** (D74): `primary` is the
  one thing to do here, filled in the accent colour and larger; Sidefolk keeps only the first primary of a page (the
  summary's control first, when the banner shows it) and draws any later one as `secondary`, so a page always has one
  answer to "what do I do?". `secondary` is framed, `destructive` red (filled when nothing on the page is primary:
  "Stop sharing" while sharing), `plain` quiet accent text for what's rarely needed ("Look again", "Forget"; an older
  Sidefolk draws it `secondary`). `disabled: true` dims a button that can't run yet, its `detail` saying why.
- **Choices, fields and lists** (D68): `choice` (`label`, `detail`, `options` of `{value, label}`, 2–8, `selected`, `tool`,
  `input`, `key`, `disabled`; drawn side by side up to four, a menu above) runs your tool with the picked option's
  value added to `input` under `key` (`value` by default, never `on`);
  `field` (`label`, `detail`, `placeholder`, `button`, `tool`, `input`, `key`) runs it with what was typed added under
  `key` (`text` by default, never `on`); `list` (`title`, `caption`, `items` of `{title, detail, image, color, symbol,
  button: {label, tool, input, symbol}}`) shows rows with a picture, a `#RRGGBB` swatch or a symbol, each with a button
  that runs one of your tools. Like switches, all of these go through Guard as the person, then the page is read again.
- **A page that reads like an app screen** (D74). For a feature with states and a main action, build the page per state
  and lead it with a **`hero`**: `eyebrow` (the state in a few words, ≤ 30 characters), `title` (≤ 80), `detail`
  (≤ 300), `tone`, `symbol`, `code` (a pairing code or PIN, drawn very large: ≤ 12 of `0-9 A-Z`, spaces and dashes),
  `image` (a picture, as below), `busy` (a spinner), `facts` (up to four `{label, value}` live numbers) and `actions`
  (up to three buttons, drawn large). A hero first on the page takes the summary banner's place there (the summary still
  makes the Today tile and the sidebar row). Anywhere else it is drawn where it is, across the page.
  - **`choice` with a `style`**: `segmented` (as above), `cards` (2–6 equal cards, each option's `detail` as a line under
    it: quality presets), `tiles` (1–24 pictures in a grid, each option's `image`, or its `symbol` while there's none:
    displays, windows, photos) or `rows` (1–24 rows with a `symbol` or `image`, a `badge` `{text, tone}` and a small
    `action` button each: devices, accounts). Options of `tiles` and `rows` take labels up to 60 characters, and
    `detail` up to 60. The picked one is marked in the accent colour; picking another runs your tool. Pick inline: don't
    make choosing reveal more buttons. An older Sidefolk draws a styled choice as a plain one (first 8 options, 2 at least).
  - **`transport`**: something playing. `title`, `detail`, `position` and `duration` in seconds (Sidefolk writes the
    times), `state` (`playing`, `paused`, `buffering`, `stopped`) and up to five `buttons`, each with a `symbol` (one
    without is left out), drawn round, the primary one (play or pause) larger.
  - **Section `place` and `collapsed`**: `"place": "side"` puts a section in a column at the start edge beside the
    main ones when the window is wide enough (a list of devices, as in an app's sidebar). `"place": "bottom"` ends
    the columns: that section and the following sections span the page beneath both columns. Narrower, sections keep the
    page's order. A titled section may have a short `detail` summarizing its current setting. `"collapsed": true` folds a titled section under its title until the person opens it (`false`: open,
    but foldable): advanced settings, connection details.
  - An older Sidefolk skips `hero` and `transport` and ignores `place`, `collapsed`, `plain` and `disabled`, so keep the
    summary meaningful (with its `control`) for those copies.
  - In the Kit: `.hero(Hero("Share your screen to Living Room", eyebrow: "Ready", image: "shots/1/display.jpg",
    actions: [Action("Start sharing", tool: "share_screen", style: .primary, symbol: "play.fill")]))`,
    `.picker("Share to", style: .rows, [Option(id, "Living Room", badge: Badge("Paired", tone: .good))], selected: id,
    tool: "choose_tv", key: "tv")`, `Section("TVs", blocks, place: .side)`, `Section("More", blocks, collapsed: true)`.
    Miraya (sidefolk-addons `extensions/miraya/Sources/MirayaPage.swift`) builds a page per state this way.
- **Pictures** (D68) on list rows, palettes, heroes and tiles (D74) are files your program wrote in its own data
  folder (`Paths.data`), named relative to it: `thumbs/ab12.png`, a PNG or JPEG, up to four folders deep, no part
  starting with a dot. Sidefolk opens the file without following links, checks that what it opened is inside that
  folder with one link, and reads at most
  4 MB for a row (25 MB for a palette preview); anything else shows a placeholder. Make thumbnails once, small (a few
  hundred pixels), rather than pointing at big originals: a palette lists up to 200 rows as the person types.
  Sidefolk keeps a picture by its name while it runs, so a picture that changes (a window's still) needs a new name;
  delete the old file once a newer one is on the page.
- **Heads-ups.** Under the page, each of your watchers is a switch: on, it checks every five minutes in `repeat`
  mode and the companion tells the person when it triggers. So a watcher should trigger on change (see Watchers).
- **What Sidefolk refuses or drops.** A page over 128 KB, or one without `sections` or `summary`, fails. Within it, a
  part Sidefolk doesn't know is skipped (so a newer extension still shows on an older Sidefolk), as is a part
  missing what it needs; at most 16 sections, 24 parts a section, 24 items a list or a list-like choice. Every text is
  cleaned of hidden characters and clipped. A page is your text: it is never shown to a model.
- Pages came during 0.1.0's snapshots: a snapshot from before them (489 and older) refuses the manifest, because it doesn't
  know `pages`. Write `"sidefolk": ">=0.1"` as usual.
- **A game extension's page is its Game Center** (D93). The first page of an extension that declares `games` is drawn
  by Sidefolk: the companion, today's dailies, every game as a card with its art, the person's numbers, last games,
  badges and the games' settings. Send the `summary` as usual (the Today tile) and, beside it, what only you know:
  `"games": {"records": {"<game>": {"played", "won", "lost", "drawn", "streak", "best_streak", "best": "Best: 9 moves",
  "today": {"text": "Solved in 4", "done": true, "streak": 3}}}, "recent": [{"game", "at": "<ISO 8601>", "outcome":
  "won|lost|draw|solved", "text": "You 7 · Mochi 6"}]}` (the Kit: `Page(summary:games:)` with `GameRecords`). Any
  `sections` are drawn under the center. A game without a record is counted from Sidefolk's own Activity.

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
the clipboard. Your page shows the shortcut, and the person can change it there, with where the palette opens (the
top of the screen, the pointer or the middle); the menu bar icon's right-click menu (or the Pocket's ⋯) lists every palette too, opening it under the icon.

Palettes do more since D68, all optional (an older Sidefolk ignores them):
- **Items** can carry `image` (a picture in your data folder, see Pictures under Pages), `color` (`#RRGGBB`, drawn as a
  swatch) and `section` (a heading drawn above the item when it differs from the item before: "Pinned", "History").
- **Keys.** The first nine rows show ⌘1–⌘9. Maccy's keys work beside Sidefolk's: ⌘1–9 choose a row, ⌥↩ and ⌥1–9 send
  `alternate` (do the other thing: paste when choosing copies, copy when it pastes), ⇧↩, ⌥⇧↩ and ⌥⇧1–9 `plain`, ⌘P or
  ⌥P `pin`, ⌘⌫ or ⌥⌫ `delete` (each only when the item lists it in `actions`).
- **List actions.** `{actions: ["clear", "clear_all"]}` on the list lets ⌥⌘⌫ and ⇧⌥⌘⌫ send `choose` with an empty
  `item` and that action, once the person pressed the keys twice (Sidefolk asks in between).
- **Preview.** With `{preview: true}` on the list, the palette is wider and shows the picked item in full beside it:
  Sidefolk asks `sidefolk/palette.preview {palette, item}` → `{title, text, code, image, facts: [{label, value}]}`
  (text up to 20,000 characters, selectable; `code` sets it in a fixed-width font; `image` a picture in your data folder).

```swift
ext.palette("history", query: { query in PaletteList(items(matching: query), preview: true, actions: ["clear"]) },
            choose: { id, action in copy(id); return PaletteChoice(close: true, paste: true) },
            preview: { id in PalettePreview(text: fullText(id), facts: [("Copied", "Today 14:02")]) })
```

**Which app a copy came from** (D68). With `permissions.clipboard`, `ext.send("sidefolk/clipboard.source")` right after
you see the clipboard change; Sidefolk answers with the same notice, `{change, app, name}` (the clipboard's change count,
the bundle id and name of the app in front), which `ext.on("sidefolk/clipboard.source") { args in … }` receives. It
answers once per change of the clipboard: asking again before the next copy gets nothing, so an extension can't follow
which apps the person uses. The sandbox keeps Launch Services closed (it would also open apps and links), so this is the
only way to know.

**Nudges.** `ext.send("sidefolk/nudge")` asks Sidefolk to keep the person active: it moves the pointer by nothing
where it is, which resets macOS's idle time (what chat and meeting apps watch) without anything moving on screen.
Only with `permissions.power`, at most one every 20 seconds whatever you send, and only once the person allowed
Accessibility. (macOS's own "user is active" call doesn't reset the idle time those apps read.)

## Games

An extension can add games played in Sidefolk's **Play panel** beside the companion (D75). As for pages, you say what
is on the board and Sidefolk draws it, keeps the time, plays the companion's reactions and the sounds, and writes one
Activity row when the game ends.

```json
"games": {
  "trivia": { "title": "Trivia", "symbol": "questionmark.bubble.fill", "levels": ["easy", "fair", "hard"],
              "say": ["let's play trivia", "quiz me"], "ai": true, "look": "quiz", "tagline": "Questions on every topic" }
}
```

- `say`: whole sentences that open the game at once, without the AI (the command rules, no slots). Every game is also
  in the companion's Play menu and in `games.open`, the tool Sidefolk's AI uses to offer a round (`"ai": false` keeps
  it from the AI). Up to 24 sentences, so a game can be opened in each of Sidefolk's ten languages ("let's play
  tic-tac-toe", "jouons au morpion", "来玩井字棋"); the game's title is translated in `strings/` (`games.<name>.title`).
  `levels`: up to five names, easiest first. `look` dresses the game in one of Sidefolk's looks (D79 amended: its
  colour, illustrated scene and menu icon; `cups`, `dance`, `arcade`, `sticks`, `quiz`, `grid`, `numbers`, `animals`,
  `balloons`, `cards`, `hands`, `words`, and the puzzles' `plots`, `seesaw`, `sudoku`, `blossoms`, listed under "Puzzles";
  a game without one gets the plain look); `tagline` is one line (60 characters)
  under its title on the Play panel's menu, translated as `games.<name>.tagline`. A game never sends a picture.
- **The channel:** `sidefolk/game.start {game, level, language, options}` answers `{session, board}`;
  `sidefolk/game.move {game, session, move}` answers `{board}`; `sidefolk/game.end {game, session, reason}` (`closed`,
  `timeout`, `finished`) needs no answer. `options` holds `tone` (gentle, cheeky, competitive), `sneaky` and
  `companion` (its name), and what the person said about the game when they did (D93, Sidefolk's own sentences in ten
  languages, or the AI through `games.open`): `topic` (a quiz's subject, 40 characters) and `count` (1–50) for a game
  whose look is `quiz`, `min`, `max` (a range up to 1,000,000) and `mode` (`mine`: the person guesses; `yours`: the
  companion guesses) for `numbers`. Use what you know and ignore the rest. Sidefolk also steers every game without
  your help: "rematch", "make it harder", "play tic-tac-toe on hard", "pause the game", "show my stats"; a level the
  person picks is sent each time the game opens. With two people playing each other on this Mac (D96), `players` (2)
  and `names` (the two names last played under); while the person lets their AI make trivia questions (D95),
  `ai_trivia` (the AI's name). Answer within **2 seconds** and under **64 KB**, or Sidefolk ends the game. Moves come only
  for a part the board on screen offered, at most 20 a second: `{answer: i}`, `{cell: [r, c]}`, `{button: "next"}`,
  `{choice: {name, value}}`, `{timeout: true}`, `{letter: "e"}`, `{word: "crane"}`, `{number: 42}`, `{pad: 2}`,
  `{press: {ms: 243}}`, `{early: true}` (with a two-key reflex, `{press: {ms, key}}` and `{early: {key}}`),
  `{text: {name, value}}`, `{next: true}` (a board's `after_ms` passed), and on a
  puzzle `{area: [r, c, r2, c2]}` (a rectangle dragged) and `{place: {cell: [r, c], value, note}}` (a number, 0 clears). Moves
  are not tool calls: a game changes only its own state. Anything that acts on the world stays a tool behind Guard.
- **Board parts:** `prompt` (text, `eyebrow`, `chip`), `answers` (2–4 `items` with `label`, `state` none, picked,
  right, wrong or faded, `companion` for its pick, `art` rock, paper or scissors; `layout` grid, row or column;
  `locked`), `board` (rows × columns ≤ 8 × 8 of `cells` with `mark`, `value`, `companion`, `state`, `label`, `animate`),
  `score` (`you`, `companion`, `streak`, `best`, `rounds` to win, `companion_picked` for its sealed card; `players`, two
  names, when two people play each other: `you` is the first's points and `companion` the second's, each drawn with
  their name and a colour of their own, D96), `result`
  (`figure`, `line`, `ribbon`, `tone` good, bad or neutral, `facts`, up to three `actions`), `timer` (`id`, `seconds`:
  Sidefolk counts and sends `{timeout: true}`), `reveal` (`kind` coin, dice or hands), `note`, `facts`, `button`
  (`label`, `move`, `style` primary, secondary or plain, `symbol`, `key` a letter; one primary a board; `companion: true`
  makes the companion in the scene the button: clicking it presses it, no button is drawn, its key still works), `choice`
  (`name`, `style` cards or segmented, `options`, `selected`). Unknown parts are skipped; `"over": true` ends the game.
  A tile may carry its own `key` (a letter, a digit or `?`); a 3 × 3 `board` with `"keys": "numpad"` takes the digits
  as a number pad does.
- **Parts for the later games** (Sidefolk draws, times and takes the input; the Kit's `.play(...)`, GameParts.swift):
  `pads` (2–5 `items` of `shape`, `color`, `label`, the companion's `move`, `art` Sidefolk's picture of the move: `wave`,
  `hop`, `spin`, `bow`, `wave_both`, drawn instead of the shape; `play` a sequence of up to 64 that Sidefolk
  shows first at `step_ms` 250–2000, a pad lit with its note and the companion's move, then `{pad: i}`), `cups` (2–5:
  the gem under `hide`, then `swaps` of positions, up to 40, at `swap_ms`; a pick is `{cell: [0, i]}`; `gem` (or `null`
  for none) lifts them), `reflex` (`wait`, `go`, `early` words, `after_ms` 300–10000, `window_ms`; Sidefolk shows the
  signal and times the press from the key's own timestamp; `shows` once played; `keys`, two letters, when two people
  share it: each presses their own key, found by where it sits on any layout, the first key decides, and clicks don't
  count), `meter` (0–1, `label`, `low`, `high`),
  `number` (`min`, `max`, `history` of `{value, mark}` higher, lower or right; Sidefolk's digit pad), `letters` (`rows` of
  tiles `{text, mark, group}` marked right, elsewhere, absent or hidden; `style` rows or slots; `flip` the row just
  played; `draft` shows what is typed in the next row), `keys` (`pages` of rows of single letters with marks; `mode`
  letter or spell with `length`; `script` latin, kana, hangul or arabic, so Korean jamo typed group into syllables),
  `entry` (a text field, so the input method types Chinese idioms; `kind` word or text, `max` up to 120), `sticks`
  (`total`, `left`, `take`, `groups`, `hint`, the last `taken` and `taken_by`), `lives` (`total`, `left`, `symbol`
  balloon or heart), `puzzle` (a logic puzzle's grid, 2–10 cells a side: `cells` with `symbol` heart, star, blossom or dot,
  `text` a number of up to two characters, `given`, pencil `notes` 1–9, `region` 0–11 (coloured, heavier lines between),
  `state` conflict (drawn in the calm loss tone with a !), hint or target (the move shown faintly), `fresh`, `label`;
  `input` tap (`{cell}`), drag (`{area}`, a click alone `{cell}`) or digits with `digits` 1–9 (`{place}`, Sidefolk's pad,
  N for notes); `box` [rows, columns] for Sudoku's thicker lines; `edges` of `{cell, down, clue}` same (=) or different
  (×), up to 200; `plots` of `{row, column, height, width, state, tint}`, up to 100; `clock` `{seconds, running}`, which
  Sidefolk counts on; drawn left to right in every language). **`after_ms`** (100–6000) on a board: Sidefolk shows it that long, then asks for the next with
  `{next: true}`: the companion thinking before its move, two cards left face up. The game never keeps time.
- **The companion's cue** (`"companion"` on a board), every value from a fixed list, anything else dropped: `move`
  (think, cheer, celebrate, sulk, bow, nod, shrug, giggle, wince, gasp, tease, sweat, dizzy, ready, shuffle, hop, spin,
  wave, dance, accent:wave/hop/spin/bow), `effect` (confetti, sparkles, hearts, question, exclaim, sweat, stars, frost,
  flame), `prop` (balloons(1–9), hat, crown, magnifier, cards, sealed_card, gem, none), `line` (a **key**: hello,
  your_turn, my_turn, thinking, close_one, you_win, i_win, draw, record, streak, encourage, tease, caught_cheating,
  hint_intro, bye; Sidefolk says its own words for it), `sound` (tap, flip, rattle, pop, ding, boop, tick, whoosh,
  stamp, shuffle, snap, cork, fanfare, trombone), `look` (panel, you, away, `[row, column]`). One cue a board; moves
  0.8 s apart, a line every 2 s, four sounds a second.
- **Suspense and colour are Sidefolk's:** send the board with its verdict in it (judged tiles, the companion's pick,
  the new score, a cue); when it would give a result away Sidefolk shows a build-up first (the reveal playing, or the
  pick pressed beside the sealed card) and the verdict after. Right is drawn in success green, wrong as a calm loss
  tone, a draw neutral, each with its symbol: don't encode a result in your own words' colour.

**Two people on one Mac** (D96): a game may offer "vs <companion>" or "2 players" on its first board. Then the
companion only referees: use no `i_win` or `you_win` line, give the end card the `info` tone for a winner (neutral ink and a
trophy: the winner is named, nobody's loss is coloured) or `neutral` for a draw, put both names in `score.players` (Sidefolk records the game apart from
the person's results against the companion and remembers the names), and pass a secret with a cover board that holds
nothing of it ("Pass the Mac to Sam. Ana, look away!" and a ready button) before the other person's turn.

**Trivia from the person's AI** (D95, Sidefolk's own extensions only): send the notice `sidefolk/trivia.request` with
`request` (a UUID), `topic` (up to 60 characters, empty for the AI's choice), `count` (10–20), `level` (easy, fair,
hard) and `language`; Sidefolk answers with the notice `sidefolk/trivia.pack`: `request`, `ok`, then `topic`, `made_by`
and `questions` (each `question`, four `choices`, `answer` the right one's index, `difficulty` 1–3, `fact`), or a
`reason` (off, busy, limit, unusable, failed, denied). Ask only while `options.ai_trivia` is set, show who made the
questions and that they aren't checked, keep the board's `after_ms` turning while you wait (the answer can take a
minute), and fall back to your own questions when none come.

In the Kit, `ext.game(name, start:, move:, end:)` with `Board`, `BoardPart`, `Tile`, `Cell`, `GameButton`,
`ChoiceOption`, `Reveal`, `Cue` and `Move` (extensions/Kit/Game.swift):

```swift
ext.game("coin", start: { request in
    GameReply(session: UUID().uuidString, board: Board([.prompt("Heads or tails?"), .answers([Tile("Heads"), Tile("Tails")])]))
}, move: { request in
    let heads = Bool.random(), right = request.move == .answer(heads ? 0 : 1)
    return Board([.reveal(.coin(heads: heads)), .answers([Tile("Heads", state: heads ? .right : .wrong),
                                                           Tile("Tails", state: heads ? .wrong : .right)], locked: true)],
                 companion: Cue(move: right ? "sulk" : "tease", line: right ? "you_win" : "tease"), over: true)
})
```

Playtime (sidefolk-addons `extensions/playtime`) is the example: its rules are pure engines (`Sources/GameKit`:
`GameEngine` for the rules over a Codable state, `GameScreen` for the boards, `GameTable` keeping each session's state
in the data folder so a game survives the program stopping while idle). A 0.1.0 snapshot from before games refuses a
manifest with `games` at install (an unknown key), as with pages.

## Surfaces and scenes

A **surface** is a panel or an overlay beside the companion that Sidefolk frames for your extension (D99); a **scene** is
what it shows: pictures from your own pack, text and shapes, with animations Sidefolk runs by itself, areas and keys that
send you typed moves. It is the general form of the Play panel: anything you could draw as a board you can draw as a
scene, in your own look, and it ships with your extension alone. The game channel below it keeps working until snapshot
B (D101), then only this remains.

A worked example is `samples/scene-sample/` (a shuffle of three pack images with a click to pick, a free drag and a grid
drag, a keyboard, a coin flip overlay). To run it: `swift build --product ext-scene-sample`, copy its
`sidefolk-extension.json`, `assets/` and `.build/debug/ext-scene-sample` as `bin/ext-scene-sample` into a folder, then in the
debug app `swift scripts/dev.swift installFolder:<folder>` and `surface:dev.sample.scenes/shuffle`.

### The manifest

```json
"assets": "assets",
"surfaces": {
  "board": { "title": "Find the star", "symbol": "star.fill", "width": 420, "height": 380,
             "say": ["find the star"], "ai": true },
  "coin":  { "title": "Flip a coin", "kind": "overlay", "width": 220, "height": 260 }
}
```

- **`surfaces.<name>`**: `title` (1–40 characters, translated in `strings/` as `surfaces.<name>.title`), `symbol`, `kind`
  (`panel`, the default, or `overlay`), `width` and `height`, the canvas you ask for: 120–720 × 120–676 points for a
  panel, 120–460 × 120–420 for an overlay. A scene larger than this is cut to it; on a small screen Sidefolk scales the
  canvas down and takes the scale off every point you hear back. `say`: sentences that open it, by the command rules,
  no slots, and they come after everything Sidefolk itself understands. `ai`: `true` lets the AI open it through `surfaces.open`
  (off by default). `arguments`: what the AI may pass when it does, each name with the values it may take
  (`{"level": ["easy", "hard"]}`, `"true"` for a yes): nothing else from a model reaches your program this way, because a model
  can be steered by what it read (T40). A person's click, or your own tool's reply, passes anything. `speaker_setting`: a `switch`
  among your `settings` that the frame's speaker reads and writes, so one setting and the frame agree; without it the host keeps
  the choice for this surface. `activity`: `false` when your program writes its own History row (`sidefolk/activity.add`), so
  Sidefolk writes no "Used …" row.
- **`assets`**: the name of one folder in your pack; everything in it must be a picture or a sound, or the validator
  refuses the pack (`sidefolk ext validate` names each file).

### Pack assets

Scenes draw from your `assets` folder alone, by a path relative to it (`cups/red.png`). Nothing outside the pack can be
named: no absolute paths, no `..`, no hidden files, no URLs, no links in the folder. Files are pinned with the install, and
checked again each time one is loaded; if it changed, the node simply draws nothing.

| | Allowed | Caps |
|---|---|---|
| Pictures | PNG, JPEG, WebP, HEIC; one still frame; the content must be what its name says | 4 MiB; 3000 px a side; 6 million pixels |
| Sounds | WAV, AIFF, CAF, M4A; mono or stereo, up to 96 kHz | 2 MiB; 10 s |
| All together | | 512 files; 48 MiB; at most 96 MiB decoded in memory at once (older pictures are dropped) |

A picture that can't be decoded draws nothing; it never stops the surface. Give a picture another for the dark with
`dark`, and draw it as a stencil in a theme colour with `tint`. Sounds are played at one fixed volume, at most four a
second, only when the person's speaker in the frame is on (off by default), never in Quiet, over a fullscreen app, or
with macOS's interface sounds off.

### The channel

| Request | You get | You answer |
|---|---|---|
| `sidefolk/surface.open` | `surface`, `language`, `arguments` (what opened it passed: up to twelve small plain values) | `{session, scene}` |
| `sidefolk/surface.move` | `surface`, `session`, `move` | `{scene}` |
| `sidefolk/surface.close` | `surface`, `session`, `reason` (`closed`, `timeout`, `finished`) | anything |

Your `settings` and the AI's name go with these as with every request.

The limits are the game channel's: an answer within 2 s and within 64 KB or the surface ends ("X didn't answer, so this
closed"), at most 20 moves a second (past that a move is dropped, and a key held down adds nothing while the last press is still on
its way), and only for the one surface open in its place (one panel, one overlay). You can't
push a scene: you answer moves, and `after_ms` asks Sidefolk to come back for the next (600 times in a row with nobody
touching it, then it stops asking). You keep no clock. You aren't told the companion's name or anything about the person.
Moves are not tool calls: anything that acts on the world stays a tool, behind Guard.

**Moves** (Kit: `SurfaceMove`), each sent only if the scene on screen offered it:

```json
{"click": {"area": "pick", "value": "2", "ms": -40}}      // value and ms if the area has them; ms below 0 is before its moment
{"drag":  {"area": "field", "mode": "cells",  "from": [0, 1], "to": [2, 3]}}
{"drag":  {"area": "pin",   "mode": "points", "from": [40, 70], "to": [300, 110]}}
{"key":   {"id": "hint", "char": "h", "ms": 120}}
{"entry": {"id": "word", "text": "hello"}}
{"timer": "round"}   {"next": true}   {"back": true}
```

**Opening one from anything else.** A tool's reply can carry `sidefolk` beside `content`: so a menu item, a command with slots, a page's
button or a tool the AI called can start a surface, for your own only, as your manifest declares them:

```json
{"content": [{"type": "text", "text": "Opening sudoku"}],
 "sidefolk": {"open_surface": {"surface": "board", "arguments": {"game": "sudoku"}},
              "close_surface": "board", "open_page": "stats", "hold_answer_ms": 1500}}
```

`open_surface` (or just its name): the person's own click or command takes the keyboard; the AI's call opens only a surface marked
`ai`, and waits for a click; a routine, another agent or a watcher opens nothing. `close_surface` (a name, or `true` for whichever of
yours are open) puts it away, kept. `open_page` shows your page in Home, for the person's own click or command only. `hold_answer_ms`
(up to 5000) keeps the AI's words back while an animation is still showing the result. Anything else is left out. Kit:
`ext.tool(…, reply: { args in ToolReply("Opening").opening(surface: "board", arguments: […]) })`. An entry can also name a surface directly
(`"surface": "board"`, `input` being what it starts with). This is never a push: it only ever answers a call someone made through Guard.

### A scene

```json
{ "size": [400, 340], "title": "Round 2", "back": true, "background": "surface_sunken",
  "styles": { "cell": { "type": "shape", "fill": "surface_raised", "w": 40, "h": 40 } },
  "nodes": [ … ], "animations": [ … ], "keys": [ … ], "timers": [ {"id": "round", "ms": 15000} ],
  "react": {"move": "think"}, "after_ms": 900, "input_after_ms": 200, "transition_ms": 160,
  "mirror": true, "announce": "Your turn", "over": true, "outcome": "win", "tally": [7, 6],
  "close": true, "close_after_ms": 2500 }
```

Everything but `nodes` may be left out. In the Kit: `Scene(width:height:) { … }.animating(…).key(…).timer(…).title(…)`.

- **`title`** is the frame's first line (your surface's title otherwise). **`back`** shows the frame's Back (⌘[), which sends
  `{back: true}`; ✕, Esc and ⌘W are always the frame's and put the surface away, kept ten minutes.
- **`styles`** are keys a node takes with `"style": "cell"` (its own keys win), to keep a large board under 64 KB. A 9 × 9 board
  with pencil notes in every cell, built with the Kit, fits.
- **`after_still_ms`** is `after_ms` under Reduce Motion, when what it waits for doesn't play; you aren't told that setting.
  **`speaker`**: a switch among your settings that the frame's speaker is while this scene shows.
- **`after_ms`** (100–10000), **`input_after_ms`** (no moves for so long), **`transition_ms`** (a node that changed since the last
  scene eases to its new place, its new size showing at once, up to 1000), **`announce`** (what VoiceOver hears), **`mirror`** (false: never mirrored).
- **`over`** says it ended; Sidefolk stops its clocks and writes its one Activity row in its own words. `outcome` (`win`,
  `loss`, `draw`) and `tally` (two numbers) are what it may say. **`close`** puts the surface away, after `close_after_ms` (at
  most 30 s). An overlay goes by itself a minute after the person last touched it: your clocks don't count. Each `over` scene after
  the first writes a row only if the person made a move since. Timers and `after_ms` together stop after 600 with nobody touching it.
  Put away, a surface runs nothing: moves not sent are dropped, a reply still on its way is what it shows when it comes back, and its
  clocks and animations go on from where they were.
- A value that is off is dropped, a node of a type this version doesn't know is skipped, and each drop is logged for you
  (`surfaces` in the log). Going past a cap below refuses the whole scene.

### Nodes

Every node: `id` (give one to anything you animate or that should stay the same layer across scenes; otherwise its place in
the tree names it), `x`, `y`, `w`, `h` (its box in its parent, from the top left), `anchor` ([0.5, 0.5]: what scale and rotation
act around), `scale`, `sx`, `sy`, `rotate` (degrees), `opacity`, `z` (order among siblings), `clip`, `corner`, `shadow`
({color, radius, dx, dy}), `children`, `ltr`, `label`, `area`.

| `type` | Keys | Kit |
|---|---|---|
| `group` | `children`; with no size it is its parent's | `Node.group { }` |
| `image` | `image`, `dark`, `fit` (`contain`, `cover`, `fill`), `tint` | `Node.image("a.png")` |
| `text` | `text`, `size`, `weight` (to `black`), `design` (`default`, `rounded`, `serif`, `mono`, `theme`: the person's theme's face and scale), `color`, `align`, `valign`, `lines`, `min_scale` (shrinks to fit its box), `italic`, `tabular`, `strike`, `runs` ([{`text`, `color`, `weight`}], parts wrapping as one) | `Node.text("Hi", size: 17).textLook(italic: true)`, `Node.runs(…)` |
| `shape` | `shape` (`rect`, `ellipse`, `capsule`, `path`), `path` (`M x y`, `L x y`, `Q cx cy x y`, `C a b c d x y`, `Z`), `fill`, `gradient` ({colors, from, to}), `stroke`, `line_width`, `dash`, `corner` | `Node.rect(fill: .accent, corner: 12)` |
| `symbol` | `name` (an SF Symbol), `color`, `weight`, `mode` (`mono`: one flat colour, every layer, so a mark cut out of a disc is lost), `secondary` (a second layer's colour: a mark in the colour under it keeps it) | `Node.symbol("star.fill").symbolLook(weight: "black", mono: true)` |
| `scroll` | `content_h` (what its children take up), `scroll_to` (a node to keep in view); wheel and trackpad move it in the app, with nothing sent, and it stays where it was across scenes by its `id` | `Node.scroll(contentHeight:scrollTo:) { }` |
| `flip` | `front`, `back` (nodes), `showing`, `axis` (`y`, `x`); the `flip` value turns it in half turns | `Node.flip(front:back:)` |
| `row`, `column` | `items`, `gap`, `align`, `pack`; each item needs a size | `Node.row(gap: 4) { }` |
| `grid` | `columns`, `cell` [w, h], `gap`, `items`; an item with no size takes the cell's | `Node.grid(columns:cell:) { }` |
| `keyset` | `name`, `rows` of {`key`, `label`, `spoken`, `typed`, `fill`, `ink`, `w`, `faded`, `disabled`, `no_key`}, `key` [w, h], `gap`, `corner`, `size`, `fill`, `ink`, `lip`, `lip_color`, `sound` | `Node.keyset(name:rows:)` |
| `companion` | `pose` (`idle`, `listening`, `thinking`, `waiting`, `success`, `alert`, `celebrating`), `figure` (`face`: its profile picture), `align` (`bottom`: stands on the box's edge), `duotone` (in shades of a colour) | `Node.companion(pose:).figure(face:bottom:duotone:)` |
| `person` | `align`, `duotone`; with no account picture Sidefolk draws its friendly stand-in | `Node.person()` |
| `entry` | `name`, `placeholder`, `max` (up to 120), `locked`, `size`, `focus` (takes the keyboard as it appears, if the surface has it), `plain` (no box of its own), `weight`, `design`. Always inside the canvas. | `Node.entry(name:).fieldLook(focus:plain:)` |
| `clock` | `seconds`, `running`, `down`, and a text's style (`tabular` unless you say not); h:mm:ss past an hour | `Node.clock(seconds:)` |

- **Colours:** by the theme's name, which follow the person's theme and dark mode: `ink`, `ink_muted`, `ink_faint`, `surface`,
  `surface_sunken`, `surface_raised`, `line`, `well`, `accent`, `on_accent`, `accent_soft`, `link`, `info`, `success`,
  `success_soft`, `warning`, `warning_soft`, `clear`; the verdicts, what a result means for the person: `win`, `loss` (a calm
  tone, never red), `draw`; a theme colour tuned, `{"token": "accent", "alpha": 0.75, "brightness": -0.14}`; or plain, `#RRGGBB`,
  `#RRGGBBAA`, `{"light": "#…", "dark": "#…"}`. Never say a result with colour
  alone (D78): a symbol or a word goes with it.
- **The person's companion and the person** are nodes you can place, up to 32 in a scene, and never read: Sidefolk draws
  them, and nothing about them comes back to you. `{companion}` in any of your words Sidefolk shows (a text, an area's label, a
  placeholder, `title`, `announce`, a page, a setting's title or detail, a menu item, an Activity row) is its name, filled in on
  Sidefolk's side.
- **A keyset** lays out centred rows of caps, each an area and its key: a press, on screen or on the keyboard, is
  `{click: {area: <name>, value: <key>}}`. `typed` is the keyboard's key when it differs (`return`, `delete`).
- **Right to left:** in Arabic each box is measured from the far side, with its animations, text alignment and rotations; a
  column or a dragged point comes back to you in your own terms. `ltr` keeps a node's contents as they are (a picture, a
  puzzle, a word's tiles), and `"mirror": false` the whole scene.
- **Limits:** 1500 nodes, 16 deep, 400 pictures of 64 different files, 400 areas, 160 keys, 8 timers, 2 entries, 4 clocks,
  24,000 characters (400 a text), 240 path commands; coordinates within ±4000; **96 MiB of bitmaps** (every text, clock, symbol,
  gradient, figure and tinted picture is `w × h × 16` bytes, a picture counts once at its largest) and **6000 animated points**, a
  `flip` counting as 8 samples a half turn. Past any of them the scene is refused. Only whole sentences and whole values are trusted:
  every cap in characters also holds at most 8 marks on a character.

### Areas and keys

`"area": {"id": "pick", "value": "2", "label": "Tile 2", "key": "2", "hover": {"scale": 1.03}, "press": {"dy": 2}, "highlight": ["a", "b"],
"sound": "tick.wav", "always": true, "disabled": false, "timed_from_ms": 2300, "seat": false, "selected": false,
"drag": {"mode": "grid", "rows": 4, "columns": 8, "ghost": "preview"}}`

- **`label` is required**: it is what VoiceOver reads and presses, and an area without one isn't offered. Text nodes are read
  as they are; give anything else that means something a `label`.
- **`hover`** and **`press`** (`scale`, `dx`, `dy`, `opacity`, `rotate`) are drawn at once by Sidefolk; `highlight` names other nodes that take
  `hover` too (the sticks that would go), or gives them a look of their own, `{"id": "badge", "dy": -1, "opacity": 1}`, whose `opacity`
  is the value itself, so a node at 0 can appear. Without `hover` the area itself stays still. An area's box stays where it rests
  whatever its own look does. Under Reduce Motion a press dims rather than moves. **`sound`** plays on the press itself. **`selected`** tells VoiceOver.
  **`submits`**: the name of an `entry`; a press sends what is typed there, as Return does, and while the field is empty it takes no press and is drawn at half its opacity.
- **`always`** works while an animation holds moves (the companion clicked mid-shuffle).
- **`timed_from_ms`** is a moment of the scene from which the press is timed, from the input event's own time: the move carries
  `ms`, below 0 before it. Show the signal with an animation delayed to the same moment and you have a reflex test, with no
  clock of yours and no stream.
- **`drag`**: `grid` reports cells and stretches `ghost` from the first to the one under the pointer; `free` reports canvas points and
  moves `ghost` with it. A click without moving is a drag from a cell to itself. Neither waits for you while it goes.

`"keys": [{"key": "h", "id": "hint"}, {"key": "letter", "id": "type"}, {"key": "digit", "id": "num"}, {"key": "a", "id": "left", "seat": true, "timed_from_ms": 2300}]`

A key is a letter, a digit or `?` as the person's keyboard types it (an Arabic letter, é), a name (`return`, `space`, `delete`, `left`, `right`,
`up`, `down`, `escape`), or a class (`letter`, `digit`: the move carries it). `seat` goes by where the key sits on a US keyboard,
whatever the layout (two players' sides). With `area` it presses that area, with its look and sound. Keys reach you only
while the surface has the keyboard, which it takes only when the person opened it; the AI's waits for a click, and an overlay
never takes it. Command keys never reach you, and Esc only if you name it, and pressed twice it closes anyway.

### Animations

Sidefolk runs them, so nothing is streamed; at rest a surface runs nothing at all. A scene can't animate for ever: at most 40
repeats and 120 seconds a timeline.

```json
"animations": [
  {"id": "round", "essential": true, "blocks_input": true, "sequence": [
     {"wait_ms": 900},
     {"sound": "whoosh.wav"},
     {"together": [{"target": "a", "to": {"flip": 1}, "ms": 360}, {"target": "b", "to": {"flip": 1}, "ms": 360}]},
     {"target": "a", "keys": [{"t": 0, "x": 14, "z": 2}, {"t": 0.5, "x": 80, "y": 105, "scale": 1.1}, {"t": 1, "x": 140, "z": 0}], "ms": 360},
     {"react": {"move": "cheer"}, "announce": "Ready"}
  ]},
  {"stagger": {"targets": ["t0", "t1", "t2"], "step_ms": 140}, "to": {"flip": 1}, "ms": 340},
  {"target": "die", "frames": ["d3.png", "d1.png", "d6.png"], "frame_ms": 70},
  {"target": "ball", "to": {"y": 40}, "ms": 200, "repeat": 3, "autoreverse": true, "ease": "out", "delay_ms": 100}
]
```

- **A step** names a `target` and goes `to` values, or through `keys` (each with `t` from 0 to 1), in `ms`: `x`, `y`, `scale`, `sx`, `sy`,
  `rotate`, `opacity`, `flip` (half turns: 11 lands on the back), `z`. It starts from wherever the last step left it, or from its first key if that has `t` 0. `ease`: `linear`,
  `in`, `out`, `in_out`, `spring`. `delay_ms`, `repeat`, `autoreverse`.
- **Groups:** `sequence`, `together`, `stagger`, with `wait_ms`. **`frames`** swaps a picture from the pack, the last one staying.
- **Events** at a point in a sequence: `sound`, `react`, `announce`.
- **`id`** makes a top-level item its own run: the next scene sending it unchanged carries on rather than starting again, so a
  move during a shuffle doesn't restart it. Without one it plays anew with its scene.
- **`blocks_input`** holds moves until it has played, except `always`.
- **Reduce Motion:** a step simply isn't played, and the end shows at once; what blocked moves lets go. **`essential`** keeps a step
  moving when it is the point (a shuffle). Your scene's final state is always what the animation ends on, so nothing depends on it.
- **Companion reactions** (`react`, `{move, effect, prop, look}`): `move` from the fixed list (`think`, `cheer`, `celebrate`, `sulk`, `bow`, `nod`,
  `shrug`, `giggle`, `wince`, `gasp`, `tease`, `sweat`, `dizzy`, `ready`, `shuffle`, `hop`, `spin`, `wave`, `dance`, `accent:wave`, `accent:hop`,
  `accent:spin`, `accent:bow`, `pump`, `flick`, `roll`), `effect` (`confetti`, `sparkles`, `hearts`, `question`, `exclaim`, `sweat`, `stars`, `frost`, `flame`),
  `prop` (`hat`, `crown`, `magnifier`, `cards`, `sealed_card`, `gem`, `none`, `balloons(n)`), `look` (`panel`, `you`, `away`). Paced as cues are, only while
  the surface is on screen. **There are no words:** an extension's words appear only inside its own surface, and the
  companion never says them, on the desktop or aloud.

The steps a reader needs for a shuffle are in the Kit as `Anim.swap`, and the whole of the above as `Anim.to`, `.move`, `.scale`, `.fade`,
`.rotate`, `.flip`, `.keys`, `.frames`, `.sequence`, `.together`, `.stagger`, `.wait`, `.sound`, `.react`, `.announce`, with `.delay`, `.repeating`, `.essential`,
`.blocksInput` and `.named`.

### What the frame is for

Sidefolk always frames a surface: a panel has a header with your icon, the title and your name (with your `author`, or "not from Sidefolk", unless the pack is Sidefolk's own), Back when you asked for it, the
speaker if your pack has sounds, and ✕; an overlay has a small chip with your icon, your name and ✕ under its canvas. You draw only
inside. A surface stands below Sidefolk's own panels and cards in the window order and keeps clear of them; while an approval
waits, it dims and takes nothing, so it can't catch a press meant for the card. It goes with your extension: turned off or removed,
it is closed at once, as it is when an update replaces your program or the crash limit turns it off. Removed, its sounds, its speaker
choice and its settings go too. See SECURITY T40.

## Rich pages, commands in every language, entries, settings, AI help

What any extension can declare, and Sidefolk keeps or draws for it (D100). All of it goes when the extension goes.
[`extensions/hello-abilities`](../extensions/hello-abilities) uses one of each in plain Python. A manifest with these keys needs a Sidefolk that knows
them: name it in `addon.json`'s `minimum_sidefolk` (D83).

### Richer page parts

For a look no part offers, a **scene inside the page**: `{"type": "scene", "scene": { … }, "actions": {"<area id>": {"tool": "open", "input": { … }}}}`. It is the same as a surface's scene, up to 960 × 720, fitted to the page's width: pictures from your pack, the same caps, hover and press. Each area runs its action's tool as the person, with the area's `value` as `value`; a reply can open a surface. It takes no keys and has no session: anything that plays is a surface. Kit: `.scene(PageSceneBlock(scene, actions: […]))`.

```json
{"type": "hero", "title": "Bird Log", "detail": "…", "symbol": "bird", "scene": {"pack": "garden.png", "dark": "garden-night.png"},
 "figure": {"companion": "full"}, "says": "Anything new today?", "actions": [{"type": "button", "label": "Log", "tool": "log", "style": "primary"}]}
{"type": "stats", "items": [{"label": "Species", "value": "48", "symbol": "bird.fill", "tone": "good"}]}
{"type": "cards", "size": "large", "items": [{"title": "Robin", "detail": "…", "meta": "Seen 212 times", "at": "2026-11-01T08:30:00Z",
  "picture": {"pack": "robin.png"}, "badge": {"text": "Regular", "tone": "good"}, "done": false,
  "actions": [{"type": "button", "label": "Log", "tool": "log"}], "menu": {"label": "Season", "items": [{"label": "Spring", "tool": "season"}]}}]}
{"type": "tabs", "selected": "garden", "tabs": [{"id": "garden", "label": "Garden", "symbol": "leaf", "badge": "3", "sections": [ … ]}, { … }]}
{"type": "badges", "title": "Milestones", "items": [{"title": "Fifty species", "symbol": "rosette", "earned": false, "value": 48, "goal": 50}]}
{"type": "recent", "title": "Lately", "items": [{"title": "Robin at the feeder", "at": "2026-11-01T08:30:00Z", "tone": "good"}]}
{"type": "settings", "title": "Settings", "keys": ["sounds", "region"], "ai": true}
```

Caps: 6 stats, 48 cards (3 buttons and a menu of 8 each), 2–6 tabs (no tabs inside; switching asks nothing of the program), 32 badges, 20 recent; a section
may have a `picture` beside its title. A picture is addressed, never fetched: `{"pack": path, "dark": path}` in the folder the manifest's `assets` names
(pinned at install; a card's `color` then is the tile it stands on), `{"data": name}` in the data folder, `{"companion": "face"|"full"}`, `{"person": true}` (Sidefolk places these; you never read them). A hero with a
`scene` carries the page's title itself. In the Kit: `.stats`, `.cards`, `.tabs`, `.badges`, `.recent`, `.settings`, `Hero(scene:figure:says:)`, `Picture`.

### Commands with slots, in every language

```json
"choices": {"level": {"easy": ["easy", "beginner"], "hard": ["hard", "expert"]}},
"parts": {
  "level": {"say": ["{level:level}", "on {level:level}"]},
  "count": {"say": ["{count:integer:1-50} questions"]},
  "topic": {"say": ["about {topic:text:40}"]},
  "friend": {"say": ["with a friend", "two players"], "input": {"players": 2}}
},
"carry": {"words": ["let's", "play", "a", "the"], "lead": ["play", "let's"]},
"tools": {"open": {"commands": [
  {"name": "quiz", "names": ["quiz", "riddles"], "with": ["level", "count", "topic", "friend"], "input": {"what": "quiz"}},
  {"name": "harder", "say": ["make it harder", "too easy"], "input": {"step": "harder"}}
]}}
```

`strings/fr.json` holds the same in French, and Sidefolk matches every language you have, whatever the app's language is:

```json
{"commands": {"quiz": {"names": ["devinettes"]}, "harder": ["plus difficile", "trop facile"]},
 "parts": {"count": ["{count:integer:1-50} questions"], "topic": ["sur {topic:text:40}"]},
 "choices": {"level": {"hard": ["difficile"]}},
 "carry": {"words": ["jouons", "au", "un"], "lead": ["jouons"], "inside": [], "endings": []}}
```

A whole sentence (`say`) matches as before (D50). A command with `names` takes its parts anywhere around the name, in any order: "play a quiz about the sea, hard, 10 questions" gives
`{"what": "quiz", "level": "hard", "topic": "sea", "count": 10}`. Once the parts and carrying words are out, exactly its name must be left, and a bare name needs a `lead` word or a part, so another extension's word
stays theirs. `inside` lists carrying words taken out wherever they are (Japanese, Chinese), `endings` those off a word's end (Korean particles). Two numbers in a phrase read low to high. Slots: every kind in
[commands](#answering-without-the-ai-commands), bounds (`{n:integer:1-50}`, `{t:text:40}`), `{x:list}` from `words`, `{x:enum}` from `choices` (the tool gets the value). A part's slots fill the argument of their name; one left out is left out.
The tool decides what "harder" means: Sidefolk keeps no state about it.

**Who wins.** Sidefolk's own understanding comes first: `sidefolk ext validate` lists your sentences it answers (`Sidefolk's own sentences`). A word that answers an approval (yes, oui, はい…) can't be a command. A sentence two
extensions claim goes to the AI, and the install sheet says so. Within one extension, the first tool in name order.

### Entries and drop actions

```json
"entries": [
  {"id": "log", "title": "Bird Log", "symbol": "bird", "places": ["companion", "pocket", "ask"], "page": "log"},
  {"id": "quick", "title": "Quick log", "places": ["companion"], "items": [
    {"id": "robin", "title": "Robin", "tool": "log", "input": {"bird": "robin"}}
  ]}
],
"drops": [
  {"id": "clip", "title": "Add a birdsong", "detail": "Keeps the clip with your log.", "symbol": "waveform", "kinds": ["link"],
   "patterns": ["https://*.mp4", "https://*.m4a"], "tool": "add_clip", "input": {"url": "{value}"}}
]
```

`places`: `companion` (its menu), `pocket` (the Pocket's ⋯ and the menu bar's right click), `ask` (a tab, one an extension; it opens a tool or a page). 8 entries, 32 items each, two levels. `kinds`: `file`, `folder`, `link`, `text`; `patterns` are globs on a link's address without its query, or a file's name; none means any of the kind. A file or
folder goes under an argument the tool lists in `paths`. At most three offers show on the card, after Sidefolk's own, each with your name; a link's first offer takes its reminder's place. Words in `strings/`: `entries.<id>`, `drops.<id>.title|detail`. Everything runs your own tool as the person, through Guard.

### Settings

```json
"settings": [
  {"key": "sounds", "type": "switch", "title": "Birdsong", "detail": "Play a song when you log.", "default": false},
  {"key": "region", "type": "choice", "title": "Region", "options": [{"value": "north", "title": "North"}, {"value": "south", "title": "South"}], "default": "north"},
  {"key": "goal", "type": "number", "title": "Weekly goal", "minimum": 1, "maximum": 50, "step": 1, "default": 10},
  {"key": "name", "type": "text", "title": "Name on your log", "length": 40}
]
```

Up to 64. `"listed": false` keeps one out of Settings › Add-ons and its search, for what you hold per thing you have many of: it shows only where you name it (a `settings` part's `keys`, a scene's `speaker`). Sidefolk stores them, shows them under Settings › Add-ons and with a `settings` part on your page, finds them in Settings' search, backs them up, keeps them through updates, and removes them with the extension. Every `tools/call` and `sidefolk/` request carries `settings`, all of them, defaults filled; a change sends the notice `sidefolk/settings.changed`. Change one of your own with the notice `sidefolk/settings.set {key, value}` (a speaker button on your surface): it's checked and goes in History. The AI can't change them: offer a tool for that. Words: `settings.<key>.title|detail|options.<value>`. Kit: `ExtensionSettings.bool("sounds")`, `ExtensionSettings.set(…)`, `ext.settingsChanged`.

`settings_from: "<section>"` and `carries: {"store": [...], "history": [...]}` (Sidefolk's own extensions only): once, Sidefolk's request `sidefolk/settings.carry {from, values, store, history}` gives what the app kept for this work: the section, values of its store by name, and a copy of what History has of a tool (up to 2,000 rows, each `at`, `summary`, `args`). Your `{settings: {…}}` are stored, and `{"ai": false}` sets the person's AI switch off, for someone who had said no. It can't turn it on. Kit: `ext.carry { section, values in … }`, `ext.carryAll { section, values, store, history in … }`.

### AI help

```json
"permissions": {"ai": {"purpose": "to write a line about a bird you name", "daily_cap": 10}}
```

Any extension may declare it. The person sees the purpose and the cap on the install sheet, has a switch per extension, and each request in History; it counts in their usage. The purpose starts with "to" or "for"; the cap is 1–200, 20 if you leave it out; raising it holds your update for review. The notice `sidefolk/ai.request {request: <uuid>, prompt, label, language}` (at most 8,000 characters, one at a time) is answered by one notice `sidefolk/ai.answer {request, ok, text, made_by}` or `{request, ok: false, reason}`: `off`, `busy`, `limit`, `unusable`, `failed`, `denied`. Requests carry `ai` (the AI's name) while you may ask. The AI has no tools and nothing of the person's; it gets your words marked as untrusted. **Validate the answer as anything from outside**, and say who wrote it. Identical words the same day cost nothing. Kit: `AI.available`, `await AI.ask(prompt, label:)`.

A request is at most 8,000 characters and 32,000 bytes. **Codex:** it always adds the person's own `AGENTS.md`, and has no switch for it, so while that file is there nothing is asked for an extension: the reason is `off`, and the switch says why.

### One row in History

`sidefolk/activity.add {text, key, result}`: `text` up to 120 characters; `key` your own name for it; `result` `win`, `loss`, `draw` or `done`, to count later. At most one every five seconds. When your extension is removed, these rows, being your own words, go with it; rows of what its tools did stay, as the record of what ran. `sidefolk/settings.set` is held to one a second, the last value winning, and writes nothing for a value it already has. Kit: `Activity.add("Logged a robin", key: "robin", result: "done")`.

## Speaking the person's language

Sidefolk speaks ten languages (`en`, `fr`, `es`, `de`, `it`, `pt-BR`, `ja`, `ko`, `zh-Hans`, `ar`), and so can your
extension (D76). Two parts:

**What the manifest shows people**, before your program ever runs (Settings, the install sheet, the gallery, Home's
sidebar, heads-ups): put each language's words in `strings/<language>.json` beside the manifest.

```json
{
  "name": "Wach halten",
  "tagline": "Dein Mac wach und du aktiv, so lange du willst",
  "description": "…",
  "network_purpose": "um Fernseher im lokalen Netzwerk zu finden und dorthin zu streamen",
  "examples": ["halte meinen Mac 2 Stunden wach"],
  "tools": { "keep_awake": { "title": "Den Mac wach halten", "summary": "Den Mac {duration} wach halten" } },
  "watchers": { "ended": { "title": "Wach halten beendet", "description": "…" } },
  "pages": { "awake": { "title": "Wach halten" } },
  "palettes": { "history": { "title": "Zwischenablage", "placeholder": "Kopiertes durchsuchen" } },
  "games": { "trivia": { "title": "Quiz" } },
  "text": { "Keep awake": "Wach halten", "{count} apps": { "one": "{count} App", "other": "{count} Apps" } }
}
```

Every field is optional and translates the manifest's own: a key the manifest doesn't have (a tool it doesn't list, a
tagline it lacks) is an error, and so is any other key. Each must be plain text within the manifest's limit, or half as
long again (languages run longer than English): a name up to 90 characters, a tagline 90, a description 450. `examples`
has one text for each of the manifest's, and a tool's `summary` one text for each of its forms with the same parameters (D98). Sidefolk
shows the person's language, the closest one you have (`pt` finds `pt-BR`, `zh-CN` finds `zh-Hans`), else the
manifest. Commands are translated with `commands`, `parts`, `choices` and `carry` (below, D100). Tool descriptions from
`tools/list` stay as they are too (they're pinned at install; a description that changed with the language would put
the tool on hold).

**What your program says** (answers, errors, page parts, palette rows, watcher summaries): Sidefolk sends `language`
with every `tools/call`, `sidefolk/watch.check`, `sidefolk/page.render` and `sidefolk/palette.*` request (as a param
beside the others; a plain MCP server gets requests as MCP has them). Keep your sentences under `text` in the same
files, keyed by their English, with `strings/en.json` listing the English of every one (`{"text": {...}}` and nothing
else: the manifest is the English of the rest):

- **Placeholders** are named, `{app}`, `{count}`: each translation keeps the same ones (Sidefolk's check refuses a file
  that drops or adds one), in whatever order the language wants.
- **Counts** take the language's plural forms (CLDR): `one` and `other` for most, `other` alone in Japanese, Korean and
  Chinese, `zero`, `one`, `two`, `few`, `many` and `other` in Arabic; `one`, `two` and `zero` may leave the number out
  ("تطبيقان"). `other` is required; a form the language doesn't have is refused.
- **Numbers, sizes, durations, dates** are formatted with the person's language, never by hand; times on a 24-hour
  clock, as Sidefolk writes them.
- **No direction marks.** Sidefolk removes them (they can disguise a name or a path), except a first-strong isolate
  (U+2068 … U+2069) in pairs, in what it shows: the Kit's `L` puts one around each value it fills in, so "{name} counts…"
  in Arabic still reads right to left with the name first. From Python or Node, do the same around a filled-in value.
  When it lays out right to left, Sidefolk keeps a value that is only numbers and signs ("3024 × 1964", "12 %") and
  paths, addresses and sizes inside a sentence ("~/Desktop/qr.png") left to right itself.
- **Sentences people type stay English**: an `ask` button's sentence, an example in a note (“keep me active for an
  hour”). Its label is translated.

In the Kit (`Language.swift`):

```swift
L("Keep awake")                                                 // "Wach halten"
L("{app} is using {cpu}", ["app": name, "cpu": Format.percent(0.4)])
L(one: "{count} app", other: "{count} apps", count: n)           // the language's own form, its digits
Format.bytes(n)  Format.duration(seconds)  Format.time(date)  Format.date(date, weekday: true)  Format.list(names)
Format.sentences([a, b])                                        // with a space, or none in Japanese and Chinese
Language.with("ar", strings: "extensions/x/strings") { … }      // a test in one language, beside others
```

The Kit reads `strings/` beside its program (`<folder>/bin/<program>`), keeps each request's `language` for that
request (and for background work after it), and falls back to English, then to the key. Underneath, `L` reads plain
words through the Kit's `Localized(language, tables)` (D75), the lower layer: one normalization for both (`pt` is
`pt-BR`, any Chinese, `zh-Hant` included, is `zh-Hans`, the nearest Sidefolk speaks, as for the manifest's words; an
unknown language is English) and one English fallback. Reach for `Localized` yourself only for a table that isn't your
extension's words; numbers go through `Format` (grouped as the language groups them), placeholders are named. Playtime's
words, the games' phrases included, live in its `strings/`, a game's title under `games`.
From Python or Node, read the same files: `params.get("language")`, then `json.load(open("strings/%s.json" % lang))`.

`scripts/extension-strings.py sync <folder>` writes `strings/en.json` from your `L("…")` calls (and drops texts no
longer used from every language); `extension-strings.py check <folder>` lists what each language still needs.
`sidefolk ext validate` checks the rest and prints `Languages: en, fr, …`. The gallery's `build.py` packs `strings/`
and copies the name, tagline and description per language into the catalog (`localized`), so the gallery speaks the
person's language before anything is installed; an older Sidefolk ignores the key.

## Testing locally

1. **Run your program by hand.** Pipe messages in and read what comes out:
   ```sh
   cd extensions/hello-folk
   printf '%s\n' \
     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"hello","arguments":{}}}' \
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

**Install:** Settings › Add-ons › Install from folder…, or drop the folder on the companion.
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

**Turn off / on:** the switch in Settings › Add-ons. **Uninstall** (under the extension's details)
removes the extension, its data folder and its settings.

**Finding one:** Settings › Add-ons lists what is installed one line each (name, what it does, its
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

## Seed packs and the gallery

The app builds in no extension (D98). Everything Sidefolk makes is in the add-on gallery (D55,
[sidefolk-addons](https://github.com/ghassenbrg/sidefolk-addons)): signed packs Home's Gallery downloads when the person
picks one, then installed through the same sheet, each a small Swift program on [`extensions/Kit`](../extensions/Kit),
so none needs Python, Node or anything else installed.

Four are also **seed packs**: World Clock, System Vitals, Weather and Calculator. The app carries their signed packs and
a list (`Resources/SeedPacks/seed-packs.json`), and a fresh Mac installs them once, offline, so the first run has
something to try. From then on they are gallery extensions like the rest: the gallery updates them (on the default Releases
channel, once a plain version is released; until then a copy stays at the version it has), removing one is remembered, an app update
never touches them. Publish the gallery before releasing the app, since a release takes the
packs from it (`scripts/seed-packs.py`).

Several answer common sentences at once, without the AI (D50): Calculator ("what's 12*7", "15% of 80", "convert
5 km to miles", "days until 25 December"), World Clock ("time in Tokyo"), System Vitals ("about this mac"), and from
the gallery Currency ("100 usd in eur"), Playtime ("pick a number between 1 and 6", "pick one: tea, coffee or
juice", and a sentence that opens each game), Dev Toolbox ("new uuid", "timestamp 1730000000") and QR Codes ("qr code
for example.com"). Settings › Add-ons lists each one's sentences under Details. Text transforms and checksums have
none on purpose: Sidefolk tidies a typed sentence (quotes, final punctuation, spaces), and a hash of tidied text
would be the wrong answer.

| Extension | Where | Permissions | What it does |
|---|---|---|---|
| World Clock | Gallery, seed pack, on | None | The time anywhere, conversions with daylight saving |
| System Vitals | Gallery, seed pack, on | `pmset` | Battery, disk, memory, about this Mac; low battery and disk watchers. Rests while Your Mac is on, which does all of it (D67) |
| Weather | Gallery, seed pack, on | The internet (Open-Meteo) | Forecasts, sunrise, sunset and the moon, where the person is when they share it (D48); a rain watcher |
| Calculator | Gallery, seed pack, on | None | Exact sums and percentages, units, date maths |
| Git | Gallery | The internet, `git`, a folder named per call | Clone, status, pull, log |
| Currency | Gallery | The internet (the ECB's daily file) | Money between the euro and 30 currencies; a rate watcher |
| Playtime | Gallery | None | Eleven games and four puzzles in the Play panel, trivia, a random number or pick (D75, D79) |
| Images | Gallery | A folder named per call, `media` | Photo details; copies converted, smaller or without location |
| PDF Tools | Gallery | A folder named per call | Details, text, combine, take pages out |
| QR Codes | Gallery | A folder named per call, `media` | Make a QR code picture, read one |
| Archives | Gallery | `zip`, `ditto`, a folder named per call | Zip files and folders, open zip files |
| Dev Toolbox | Gallery | A file named per call | JSON, base64, URL and hex, JWTs, timestamps, UUIDs, checksums |
| Feeds | Gallery | The internet | Latest posts from RSS and Atom; a new-post watcher |
| Your Mac | Gallery | None | A page in Home with live gauges and charts of this Mac (System Vitals+, D62) |
| Clipboard | Gallery | `clipboard`, `background` | Clipboard history in a palette (⌥P), pictures included (D63, D68) |
| Keep Awake | Gallery | `power`, `background` | Keeps the Mac awake, a switch on its page and Today's tile (D63) |
| Miraya | Gallery | The network, `udp`, `screen`, `media`, `output_mute` | Shares the screen to a TV the person paired (D69, D81) |

Every tool of an extension that is on reaches the model with each request. The ones that are off cost one line:
the model is told their names and what they do, and suggests switching one on in Settings › Add-ons when it would
help. Nothing writes over an original: pictures, PDFs and zips are always new files.

A signed pack differs from anyone else's extension in what Sidefolk believes of it (`origin` `official`): its tool
descriptions reach the model, its `summary` speaks for a call on the approval card, its `services` count as where its
calls go (D47), `replaces` lets it rest a smaller one (D67). A copy someone installs from a folder under the same id gets
none of that. A gallery extension updates from the gallery (D65, D70: by itself when the new version asks for nothing
more, else after a look) and may need a newer Sidefolk snapshot (`minimum_sidefolk` in its `addon.json`, D83).

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
content, and they are never offered to other agents. Drafts are listed under Settings › Add-ons ›
Drafts (Review…, Show in Finder, Move to Trash). An installed draft is "Written for you"; like any
extension Sidefolk didn't sign, its descriptions don't reach the model, so its tools are known by
their titles and parameter names, from the person's next request.

## Plain MCP servers

Settings › Add-ons › Add MCP Server… takes a name, a command and its arguments, for example
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
| A program named in `exec` or `run` isn't found | Install it: Apple's command line tools (`xcode-select --install`) bring Python and git. Sidefolk's own Swift programs need nothing. |
| "~/x isn't shared with Sidefolk for this." | A folder parameter named a folder outside what the person shared, or one replaced by a link since Guard looked. |
| "… must be a compiled program" | `run.command` points at a script. Use `"command": "python3", "args": ["main.py"]`. |
| `ModuleNotFoundError` for your own module | Python's isolated mode; add your folder to `sys.path` (see above). |
| `PermissionError: [Errno 1] Operation not permitted` | The sandbox blocked it. Add the folder to `files`, the program to `exec`, or set `network`. |
| A program in `exec` runs but returns nothing useful | It may need a system service the sandbox doesn't open; tell us which program. |
| "… didn't start (it exited with status 1)" | The program crashed or printed something that isn't JSON before answering `initialize`. The message shows the last line it wrote to stderr; `sidefolk ext validate <folder>` starts it in the same sandbox and prints the rest. |
| `OSError: [Errno 1]` from `fork` or `subprocess` | Only extensions that list programs in `exec` may start processes. |
| "… changed since you approved it, so it is on hold" | The tool's description or schema changed. Review and approve in Settings › Add-ons. |
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
| Palettes | 2 per extension; 200 items a list; 10 s per query, choice or preview; preview text 20,000 characters |
| Pictures (palettes, list rows, heroes, tiles) | a PNG or JPEG in the data folder: 4 MB a row, 25 MB a preview |
| Nudges | one every 20 seconds, with `permissions.power` |
| Languages | `strings/<language>.json`: 256 KiB each, 2,000 texts; translated words up to half as long again as the manifest's |
| Surfaces | 16 per extension; canvas up to 720 × 676 (an overlay 460 × 420); 64 KB a scene; 2 s a reply; 20 moves a second; 1500 nodes (above) |
| Pack assets | 512 files, 48 MiB; a picture 4 MiB, 3000 px a side, 6 million pixels; a sound 2 MiB, 10 s |
| Pages | 4 per extension; 128 KB each; refresh 2–3600 s; 16 sections, 24 parts each, 24 items a list, 4 lines a chart; one primary button; a hero's 4 facts and 3 actions; a transport's 5 buttons; 6 cards, 24 tiles or rows a choice |
| Watcher summary / state | 200 characters / 64 KB |
| Memory / CPU | 512 MB / half a core sustained for 60 s |
| Idle stop | 5 minutes |
| Crash limit | 3 in 5 minutes |

### Miraya pairing in a disposable emulator

With a separately created Android TV emulator running Miraya and port 7421 forwarded to a local test port, run
`SIDEFOLK_MIRAYA_EMULATOR_SERIAL=emulator-5584 SIDEFOLK_MIRAYA_EMULATOR_PORT=17421 swift test --no-parallel --filter MirayaEmulatorTests`.
Set `ANDROID_USER_HOME` and `ANDROID_ADB_SERVER_PORT` to the isolated emulator's values. The test refuses a physical
serial, uses a fresh Sidefolk home, compares the displayed pairing codes and approves the emulator's TV dialog. It does
not record the screen or change the Mac's audio; it doesn't verify playback.
