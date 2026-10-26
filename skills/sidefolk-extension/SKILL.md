---
name: sidefolk-extension
description: Design, build, test and ship an extension for Sidefolk, the macOS desktop companion. An extension is a folder with a manifest (sidefolk-extension.json) and a program that speaks MCP over stdio, run in a sandbox limited to the permissions it asks for. Use when asked to build a Sidefolk extension, connect a product or service to Sidefolk, add an icon to one, or fix one that `sidefolk ext validate` rejects.
---

# Building a Sidefolk extension

Sidefolk is a native macOS companion. Its AI acts only through tools, and an extension adds tools and
watchers ("tell me when …") by running a small program Sidefolk starts in a `sandbox-exec` sandbox built
from the extension's manifest. The person sees those permissions in plain words and approves the
install; every call then goes through Sidefolk's Guard (risk levels, approvals, an audit log).

The reference is **docs/EXTENSIONS.md** in the Sidefolk repository: every manifest key, the sandbox
rules, the protocol, watchers, limits and troubleshooting. This skill is the path through it. When the
two disagree, the reference wins.

## Install this skill

From a checkout of the Sidefolk repository (or wherever this folder was copied):

- **Claude Code**, for you everywhere: `mkdir -p ~/.claude/skills && cp -R skills/sidefolk-extension ~/.claude/skills/`.
  For one project only, copy it into that project's `.claude/skills/` instead. Claude Code picks it up
  in new sessions; ask "build a Sidefolk extension that …" or type `/sidefolk-extension`.
- **Codex**: `mkdir -p ~/.codex/skills && cp -R skills/sidefolk-extension ~/.codex/skills/` (or into
  `$CODEX_HOME/skills` if you set `CODEX_HOME`). Start a new session; `/skills` lists it, or just ask.

## 1. Decide that an extension is the right shape

Build an extension when the job fits a sandbox: call a web API, work on files in a folder the person
names, run a well-known command-line program, check something every few minutes. Don't, when it needs:

| Needs | Use instead |
|---|---|
| Other apps' content (Mail, Notes, Calendar, Music), the screen, the clipboard | Nothing yet: those are Sidefolk built-in tools to propose to the Sidefolk team |
| The person's account or API token | An MCP server (Settings › Extensions › Add MCP Server): extensions can't hold secrets yet |
| A Unix socket or a long-running background job | An MCP server, for now |

Sidefolk's own AI can also write small extensions for its person (the `build-extension` skill in the
app); this skill is for developers, companies and agents building ones to share.

## 2. Design: the smallest permissions that do the job

Write down, before any code: the tools (verbs), the watchers, and what each needs.

- **No permissions** is the goal. An extension always has its own data folder (`HOME`,
  `SIDEFOLK_DATA_DIR`) and its own files, read-only.
- **`"network": true`** only to reach your service. It is all-or-nothing (any host, the LAN too), so the
  install sheet warns when it is combined with folders.
- **Folders the person picks per request**: `tools.<name>.paths: {"<parameter>": "read" | "write"}`.
  Guard checks that folder against the ones the person shared with Sidefolk (asking them if needed), and
  the call runs in a process of its own whose sandbox opens just that folder. The parameter arrives as a
  full, canonical path. Prefer this to fixed folders.
- **Fixed folders**: `permissions.files.read` / `.write`, absolute or `~/…`. Open the whole time; never
  `~`, `~/Library`, hidden folders or system folders.
- **Programs**: `permissions.exec` takes absolute paths (`/usr/bin/sips`) or `git` by name, which Sidefolk
  finds in Apple's developer tools or Homebrew and passes as `SIDEFOLK_EXEC_GIT`. A shell, an interpreter,
  `curl`, `osascript` or `open` makes the list meaningless and the sheet says "can run anything".
- **Tools**: names `[a-z0-9_]`; a manifest `title` per tool that says exactly what it does. Users and
  Sidefolk's model see tools from a third-party extension by title, extension name and parameter names
  only (your descriptions stay on the install sheet: DECISIONS D24), so name parameters plainly and use
  types, `enum`, `minimum`/`maximum`, `maxLength`.
- **Risk** per tool: `low` reads, `medium` changes things, `high` is hard to undo. Network, write access or
  a "can run anything" program raises every tool to at least medium. Mark read-only tools `"mutates": false`.
- **`timeout`** (seconds, up to 300) for a tool that needs more than the default 30.
- **Watchers** for "tell me when": checked every 5 minutes at the soonest; trigger on change, not level,
  keeping what you need in `state`.

## 3. Build from a template

Copy one of `templates/` into a folder named after your id's last part, then change the id
(`com.yourcompany.thing`), name, author, tools and code:

| Template | Runs as | Shows |
|---|---|---|
| `templates/python` | `python3` (Apple's developer tools Python 3.9, standard library) | A folder named per call, a plain tool, a watcher, a PNG icon |
| `templates/node` | `node` (Homebrew's or `/usr/local/bin`) | The internet, `fetch`, error results |
| `templates/sh` | `/bin/sh` | Built-ins only, one listed program (`/bin/date`) |

A compiled program works too: put it in the folder (`bin/server`) and set `"run": {"command": "bin/server"}`.

Rules every program follows:
- stdout carries only JSON-RPC lines; logs go to stderr. Answer every message with an `id`; ignore the rest.
- Answer `initialize`, `tools/list`, `tools/call`, `ping`, and `sidefolk/watch.check` if you have watchers.
- Report a failure the model can fix as a result with `"isError": true` and a short explanation.
- Do work only when called; never at start-up.
- Python runs with `-I -B`: add your folder to `sys.path` for multi-file code; vendor any packages.
- Write only in `SIDEFOLK_DATA_DIR` (or a folder named per call). `HOME` is that data folder, so `~` in
  your code means it, not the person's home.

## 4. Give it an icon

`"icon": "icon.png"` or `"icon.pdf"`, a file in the folder: a square PNG of 64 to 1024 pixels (512 is
best) or a one-page square PDF, at most 256 KiB. SVG isn't accepted (export it as PDF). Draw it
full-bleed: Sidefolk rounds the corners. It is shown in Settings, on the install sheet and on approval and
result cards. Without one, Sidefolk draws a tile in your folk's colour (`"folk"`) with your initial.

## 5. Test

1. **The protocol by hand**, from a scratch folder (anything your program writes next to its source would
   ship with it):
   ```sh
   cd "$(mktemp -d)"
   printf '%s\n' '{"id":1,"jsonrpc":"2.0","method":"initialize","params":{}}' \
     '{"id":2,"jsonrpc":"2.0","method":"tools/call","params":{"name":"greet","arguments":{"name":"Ada"}}}' \
     | python3 -I ~/word-count/main.py
   ```
2. **The checks and a start in the real sandbox**: `sidefolk ext validate ~/word-count`. It prints the
   permission sheet, each tool's risk, warnings, errors, then installs a throwaway copy, starts it and
   lists its tools (or why it didn't start). Fix until it says `Valid.` and lists your tools with no
   warning. The `sidefolk` helper is in `Sidefolk.app/Contents/Helpers/` and, once installed from
   Settings › Agents, in `~/.local/bin`.
3. **In Sidefolk**: Settings › Extensions › Install from Folder…, read the sheet, install, then ask for
   something only your tools can do. Sidefolk's log (`~/Library/Logs/Sidefolk/`, category `extensions`)
   shows start-up errors and your stderr; sandbox denials appear in Console.app (filter `Sandbox`).

A denied file or program shows up as `PermissionError` / `EPERM`: add it to the manifest only if the
job truly needs it.

## 6. Ship it

- Bump `version` for every change. Installing a new version shows the person what it gains and loses;
  a tool whose description or schema changes without a reinstall is held until they approve it.
- Distribute the folder (a zip or a git repository). Tell people to unzip it and use Install from Folder…
  There is no directory, signing or automatic update yet; docs/research/extensions-catalog.md describes
  the plan (signed packages, a directory of verified publishers, trust levels).
- Keep the id stable forever: it names the installed copy, its data folder and its tools
  (`ext.<last part of id>.<tool>`).

## Checklist before you hand it over

- [ ] `sidefolk ext validate` says `Valid.`, lists every tool, shows no warning.
- [ ] Permissions are the smallest that work; the sheet's lines and warnings match what you'd tell a user.
- [ ] Every tool has a clear title and plainly named parameters with limits.
- [ ] Failures come back as `isError` results that say what to do.
- [ ] It has an icon, a description of at most 300 characters, and an author.
- [ ] Nothing it sends leaves for an address the person didn't ask about.
