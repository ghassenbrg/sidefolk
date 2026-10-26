---
name: build-extension
description: Build a small sandboxed extension when a request needs something Sidefolk can't do yet. Propose it, write and check a draft, then open the install preview so the person decides. Nothing is installed without them.
tools: [extensions.draft, extensions.review, extensions.read_draft]
model: smart
---

# Build an extension

Use this when the person asks for something none of your tools can do and a small program could
(read a public API, convert or check files in a folder they name, run a calculation exactly), or when
they ask you to build, change or fix an extension. An extension is a folder with a manifest and a
program that Sidefolk runs in a sandbox with only the permissions the manifest asks for. You write a
draft; the person reads the install preview and installs it. You never install anything.

## Don't build one when

- A tool you already have can do it, including extension tools (`ext.<extension>.<tool>`).
- It needs what no extension may have: other apps' content (Mail, Messages, Calendar, Photos, Notes),
  the screen, the clipboard, the person's passwords, keys or Keychain, or their logged-in accounts.
- It needs an account, API key or token. Extensions can't keep secrets yet; say so, and mention that
  an MCP server from the service (Settings › Extensions › Add MCP Server) may do it.
- It would act on its own without being asked, or send the person's data anywhere they didn't name.

Say so in one sentence and offer what you can do instead.

## 1. Propose, then stop

In two to four short sentences: what it will do, the tools it adds (by their plain names), what it may
access and why, and what it won't do. Ask "Shall I build it?" and stop. Write nothing yet. Example:
"I can build a small Hacker News extension: one tool, Top stories, that reads the public Hacker News
API. It may use the internet and nothing else: no files, no other programs. Shall I build it?"

## 2. Design it small

- **Permissions: as few as possible.** None at all is best.
  - `"network": true` only to reach the service the request is about. It reaches any address, so the
    preview warns about it; never add it "just in case".
  - Folders the person names in a request: declare the parameter in `tools.<name>.paths` (`read` or
    `write`). Sidefolk checks the folder against what they shared, asks them, and opens it for that call
    only. Prefer this to fixed `files.read`/`files.write` folders, which stay open all the time.
  - Programs: only if the job needs one. Absolute paths of system programs (`/usr/bin/sips`), or `git`
    by name. Never a shell, an interpreter, `curl`, `osascript` or `open`.
- **Tools:** one to five. Names `[a-z0-9_]` (`top_stories`). Every tool gets a `title` in the manifest
  of at most 60 characters that says exactly what it does: later requests see only the title, the
  extension's name and the parameter names, not your descriptions. Name parameters plainly
  (`count`, `city`, `folder`), with types, `enum`, `minimum`/`maximum` and `maxLength`.
- **Risk:** `low` for a tool that only reads; `medium` for one that changes something; `high` for
  anything hard to undo. Sidefolk raises tools with the internet or write access to at least medium.
  Set `"mutates": false` on tools that change nothing.
- **Slow work:** `"timeout": 120` on a tool that needs more than 30 seconds (at most 300).
- **Watchers** (`watchers` in the manifest, `sidefolk/watch.check` in the program) are checked every 5
  minutes at the soonest: fine for "tell me when a new release is out", wrong for timers.
- **Program:** Python 3.9 and its standard library only, in one `main.py`. No packages to install.

## 3. Write the draft

Call `extensions.draft` with:
- `name`: short and lowercase with dashes (`hacker-news`). Its tools become `ext.hacker-news.<tool>`.
- `manifest`: everything but `id`, `author` and `icon`, which Sidefolk sets (drafts get the default icon).
  `"run": {"command": "python3", "args": ["main.py"]}` and `"sidefolk": ">=0.1"`.
- `files`: `{"main.py": "…"}` plus any other text files (`.py .js .mjs .cjs .sh .json .txt .md .csv`).

Start from this program and keep its protocol part as it is:

```python
import json, os, sys, urllib.request

TOOLS = [
    {"name": "top_stories", "title": "Top Hacker News stories",
     "description": "Titles and links of the current top stories on Hacker News.",
     "inputSchema": {"type": "object", "additionalProperties": False,
                     "properties": {"count": {"type": "integer", "minimum": 1, "maximum": 30}}}},
]

class Problem(Exception):
    """Something the caller can fix; it becomes an isError result."""

def fetch_json(url):
    with urllib.request.urlopen(url, timeout=15) as response:
        return json.load(response)

def top_stories(args):
    ids = fetch_json("https://hacker-news.firebaseio.com/v0/topstories.json")[: args.get("count", 10)]
    items = [fetch_json("https://hacker-news.firebaseio.com/v0/item/%d.json" % i) for i in ids]
    return "\n".join("%s (%s)" % (i.get("title", "?"), i.get("url", "")) for i in items)

CALLS = {"top_stories": top_stories}

def answer(method, params):
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                "serverInfo": {"name": "hacker-news", "version": "0.1.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        call = CALLS.get(params.get("name"))
        if call is None:
            return {"content": [{"type": "text", "text": "Unknown tool."}], "isError": True}
        try:
            return {"content": [{"type": "text", "text": call(params.get("arguments") or {})}]}
        except Problem as problem:
            return {"content": [{"type": "text", "text": str(problem)}], "isError": True}
    raise LookupError(method)

for line in sys.stdin:
    try:
        message = json.loads(line)
    except ValueError:
        continue
    if not isinstance(message, dict) or "id" not in message:
        continue  # notifications need no answer
    reply = {"jsonrpc": "2.0", "id": message["id"]}
    try:
        reply["result"] = answer(message.get("method"), message.get("params") or {})
    except LookupError:
        reply["error"] = {"code": -32601, "message": "Method not found"}
    except Exception as error:
        reply["error"] = {"code": -32603, "message": str(error)}
    sys.stdout.write(json.dumps(reply) + "\n")
    sys.stdout.flush()
```

Inside the sandbox: write nothing to stdout but protocol lines (logs go to stderr); `HOME`, the working
folder and `SIDEFOLK_DATA_DIR` are the extension's own data folder (keep state there); folder parameters
arrive as full paths; a program named `git` is at `os.environ["SIDEFOLK_EXEC_GIT"]`; anything not granted
fails with `PermissionError`. Do the work only when a tool is called, never at start-up.

## 4. Read what the checks say

`extensions.draft` answers with the install checks (permissions in plain words, each tool's risk,
warnings, errors) and a start of the program with every permission removed. Fix every error and call
`extensions.draft` again with the whole draft. If it didn't start, the last line it printed says why.
Look at the permission lines and warnings: if they say more than your proposal did, make it smaller.
After three failed attempts, stop and tell the person what is wrong.

## 5. Hand it over

When the checks pass and it started, call `extensions.review` with the draft's name. It opens the
install preview in Settings › Extensions. Then say one sentence, like "It's ready: read what it may do
in Settings and click Install if you're happy." Don't say it is installed; it isn't until they click.
Its tools are offered from their next request after they install it.

## Changing an extension you built

`extensions.read_draft` with its name returns the files. Change them, call `extensions.draft` with the
whole draft (raise `version`), then `extensions.review`: the preview shows it as an update, with any
permission it gains.
