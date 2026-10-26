#!/usr/bin/env python3
"""Git, a Sidefolk extension that ships with the app (Python 3.9, standard library only).

It speaks MCP over stdio: one JSON-RPC 2.0 message per line in, one per line out. Sidefolk runs it in a
sandbox with the internet and one program, git, which Sidefolk found on this Mac and names in
SIDEFOLK_EXEC_GIT. It sees no folder of yours until a call names one: Sidefolk checks that folder
against the ones you shared, asks you, and opens just that folder for that one call.

Git here is deliberately small: https remotes only (no SSH keys, no saved passwords, so public
repositories), no hooks, no submodules, no system or global configuration.
"""
import json
import os
import pwd
import subprocess
import sys
import urllib.parse

PROTOCOL = "2025-06-18"
GIT = os.environ.get("SIDEFOLK_EXEC_GIT", "")
HOME = pwd.getpwuid(os.getuid()).pw_dir

# Settings every git command gets, whatever a repository's own configuration says: nothing runs but git
# and its https helper (the sandbox enforces that too), and nothing asks for a password it can't get.
SAFE = [
    "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "credential.helper=",
    "-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "submodule.recurse=false",
]
ENV = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null", GIT_TERMINAL_PROMPT="0",
           GIT_ASKPASS="", SSH_ASKPASS="", GIT_PROTOCOL_FROM_USER="0", LC_ALL="C")


def path_schema(text):
    return {"type": "string", "minLength": 1, "maxLength": 1024, "description": text}


TOOLS = [
    {"name": "clone", "title": "Clone a repository",
     "description": "Clones a public Git repository from an https address into a new folder, for example "
                    "https://github.com/owner/project into ~/git/project. The folder must not exist yet; the folder it goes "
                    "in must. Private repositories and SSH addresses (git@…) can't be cloned here.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["url", "destination"], "properties": {
         "url": {"type": "string", "minLength": 9, "maxLength": 2048, "description": "The repository's https address."},
         "destination": path_schema("The new folder to clone into, a full path like ~/git/project."),
     }}},
    {"name": "status", "title": "Repository status",
     "description": "The branch of a Git repository, how far it is ahead of or behind its remote as of the last fetch, and "
                    "which files are changed, staged or new.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["repository"], "properties": {
         "repository": path_schema("The repository's folder, a full path like ~/git/project."),
     }}},
    {"name": "pull", "title": "Pull the latest changes",
     "description": "Brings a repository's current branch up to date with its https remote, only when that needs no merge "
                    "(fast-forward). Changes nothing when it would.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["repository"], "properties": {
         "repository": path_schema("The repository's folder, a full path like ~/git/project."),
     }}},
    {"name": "log", "title": "Recent commits",
     "description": "The latest commits on a repository's current branch: short hash, author, when, and subject.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["repository"], "properties": {
         "repository": path_schema("The repository's folder, a full path like ~/git/project."),
         "count": {"type": "integer", "minimum": 1, "maximum": 50, "description": "How many commits (10 if not given)."},
     }}},
]


class Problem(Exception):
    """Something the model should read and can act on: becomes an isError result."""


def show(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


def full_path(raw):
    # Sidefolk passes folder parameters as full paths; "~" is for trying the protocol by hand
    # (HOME is this extension's data folder, so expanduser would point there).
    path = HOME + raw[1:] if raw == "~" or raw.startswith("~/") else raw
    if not os.path.isabs(path):
        raise Problem("Give the folder as a full path, like ~/git/project.")
    return os.path.normpath(path)


def git(args, timeout=60, check=True):
    if not GIT:
        raise Problem("Sidefolk didn't pass the location of git, so nothing can run.")
    try:
        result = subprocess.run([GIT] + SAFE + args, env=ENV, cwd=os.environ.get("HOME"), capture_output=True,
                                text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise Problem("Git took longer than %d seconds, so it was stopped." % timeout)
    if check and result.returncode != 0:
        raise Problem(explain(result.stderr))
    return result


def explain(stderr):
    """Git's error, in words that say what to do; the last line of its own output otherwise."""
    text = stderr.strip()
    lowered = text.lower()
    if "could not read username" in lowered or "authentication failed" in lowered or "terminal prompts disabled" in lowered:
        return ("It needs a sign-in: the repository is private, or the address is wrong. Git here can only reach public "
                "repositories, because it can't use your saved passwords or keys.")
    if "repository not found" in lowered or ("not found" in lowered and "http" in lowered):
        return "There's no public repository at that address."
    if "could not resolve host" in lowered:
        return "Couldn't reach that address: check it, and the internet connection."
    if "transport" in lowered and "not allowed" in lowered:
        return ("This repository's remote isn't an https address (it may use SSH, which needs your keys). Git here only "
                "reaches https remotes.")
    if "not possible to fast-forward" in lowered or "diverging branches" in lowered:
        return ("The branch and its remote have both moved on, so it can't simply be brought up to date. Nothing changed; "
                "merge or rebase it yourself.")
    if "would be overwritten" in lowered:
        return "Some changed files would be overwritten. Nothing changed; commit or stash them first."
    if "no tracking information" in lowered:
        return "This branch doesn't follow a branch on a remote, so there's nothing to pull."
    if "not a git repository" in lowered:
        return "That folder isn't a Git repository."
    last = [line for line in text.splitlines() if line.strip()]
    return last[-1].strip()[:300] if last else "Git failed without saying why."


def check_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or not parts.hostname or url.startswith("-") or any(c.isspace() for c in url):
        raise Problem("Only https addresses can be cloned here, like https://github.com/owner/project.")
    if parts.username or parts.password:
        raise Problem("Leave sign-in details out of the address; Git here only clones public repositories.")
    return parts


def head_line(repository):
    out = git(["-C", repository, "log", "-1", "--pretty=format:%h\x1f%s\x1f%ar"], check=False).stdout.strip()
    if not out:
        return "no commits yet"
    short, subject, when = (out.split("\x1f") + ["", ""])[:3]
    return "latest commit %s “%s” (%s)" % (short, subject[:120], when)


def branch(repository):
    name = git(["-C", repository, "rev-parse", "--abbrev-ref", "HEAD"], check=False).stdout.strip()
    return name or "an unborn branch"


# --- Tools --------------------------------------------------------------------------------------

def clone(args):
    url = args.get("url", "")
    parts = check_url(url)
    destination = full_path(args.get("destination", ""))
    parent = os.path.dirname(destination)
    if not os.path.isdir(parent):
        raise Problem("%s doesn't exist yet. Create it first, then clone into %s." % (show(parent), show(destination)))
    if os.path.exists(destination):
        raise Problem("%s already exists. Choose a new folder name." % show(destination))
    git(["clone", "--quiet", "--", url, destination], timeout=290)
    name = parts.path.strip("/")
    name = name[:-4] if name.endswith(".git") else name
    return "Cloned %s into %s: branch %s, %s." % (name or parts.hostname, show(destination), branch(destination),
                                                  head_line(destination))


def status(args):
    repository = full_path(args.get("repository", ""))
    out = git(["--no-optional-locks", "-C", repository, "status", "--porcelain=v2", "--branch", "--untracked-files=normal"]).stdout
    head, upstream, ahead, behind = "", "", 0, 0
    tracked, staged, untracked, conflicted, names = 0, 0, 0, 0, []
    # Porcelain v2: "1 XY … path", "2 XY … score path<TAB>old path", "u XY … path", "? path".
    for line in out.splitlines():
        if line.startswith("# branch.head "):
            head = line[len("# branch.head "):]
        elif line.startswith("# branch.upstream "):
            upstream = line[len("# branch.upstream "):]
        elif line.startswith("# branch.ab "):
            a, b = line[len("# branch.ab "):].split()
            ahead, behind = int(a), -int(b)
        elif line[:2] in ("1 ", "2 "):
            tracked += 1
            staged += line.split(" ", 2)[1][0] != "."
            names.append(line.split("\t")[0].split(" ", 9)[-1] if line.startswith("2 ") else line.split(" ", 8)[-1])
        elif line.startswith("u "):
            conflicted += 1
            names.append(line.split(" ", 10)[-1])
        elif line.startswith("? "):
            untracked += 1
            names.append(line[2:])
    where = "%s on %s" % (show(repository), "a detached HEAD" if head == "(detached)" else head)
    if upstream:
        if ahead or behind:
            where += ", %d ahead and %d behind %s (as of the last fetch)" % (ahead, behind, upstream)
        else:
            where += ", even with %s (as of the last fetch)" % upstream
    if not names:
        return where + ". Nothing changed."
    counts = []
    if tracked:
        counts.append("%d changed (%d staged)" % (tracked, staged))
    if conflicted:
        counts.append("%d with conflicts" % conflicted)
    if untracked:
        counts.append("%d new and untracked" % untracked)
    shown = ", ".join(names[:15]) + (", and %d more" % (len(names) - 15) if len(names) > 15 else "")
    return "%s. %s: %s." % (where, "; ".join(counts), shown)


def pull(args):
    repository = full_path(args.get("repository", ""))
    before = git(["-C", repository, "rev-parse", "HEAD"]).stdout.strip()
    git(["-C", repository, "pull", "--ff-only", "--no-rebase", "--quiet"], timeout=290)
    after = git(["-C", repository, "rev-parse", "HEAD"]).stdout.strip()
    if before == after:
        return "%s on %s is already up to date." % (show(repository), branch(repository))
    count = git(["-C", repository, "rev-list", "--count", "%s..%s" % (before, after)]).stdout.strip()
    return "Pulled %s new commit%s into %s on %s; %s." % (count, "" if count == "1" else "s", show(repository),
                                                         branch(repository), head_line(repository))


def log(args):
    repository = full_path(args.get("repository", ""))
    count = args.get("count", 10)
    out = git(["-C", repository, "log", "-n", str(count), "--pretty=format:%h\x1f%an\x1f%ar\x1f%s"]).stdout
    lines = []
    for row in out.splitlines():
        short, author, when, subject = (row.split("\x1f") + ["", "", ""])[:4]
        lines.append("%s  %s  %s: %s" % (short, when, author, subject[:160]))
    if not lines:
        return "%s has no commits yet." % show(repository)
    return "Latest commits on %s in %s:\n%s" % (branch(repository), show(repository), "\n".join(lines))


CALLS = {"clone": clone, "status": status, "pull": pull, "log": log}


# --- Protocol -----------------------------------------------------------------------------------

def call_tool(name, arguments):
    if name not in CALLS:
        return {"content": [{"type": "text", "text": "Unknown tool: %s" % name}], "isError": True}
    try:
        text = CALLS[name](arguments)
    except Problem as problem:
        return {"content": [{"type": "text", "text": str(problem)}], "isError": True}
    return {"content": [{"type": "text", "text": text}]}


def answer(message):
    method, params = message.get("method"), message.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                "serverInfo": {"name": "git", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return call_tool(params.get("name"), params.get("arguments") or {})
    raise NotImplementedError(method)


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if not isinstance(message, dict) or "id" not in message or "method" not in message:
            continue  # notifications need no answer
        reply = {"jsonrpc": "2.0", "id": message["id"]}
        try:
            reply["result"] = answer(message)
        except NotImplementedError as e:
            reply["error"] = {"code": -32601, "message": "Method not found: %s" % e}
        except Exception as e:  # report, don't crash: one bad call shouldn't stop the extension
            reply["error"] = {"code": -32603, "message": str(e)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
