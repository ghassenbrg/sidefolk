#!/usr/bin/env python3
"""Word Count, a Sidefolk extension template (Python 3.9 standard library: what Sidefolk runs).

MCP over stdio: one JSON-RPC message per line in, one per line out, nothing else on stdout (log to
stderr). Sidefolk runs it in a sandbox with only what sidefolk-extension.json asks for. `count_words`
gets the folder the person named, as a full path, opened for that one call.
"""
import json
import os
import sys

TOOLS = [
    {"name": "count_words", "title": "Count words in a folder",
     "description": "Counts the words in the .txt and .md files directly inside a folder.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["folder"], "properties": {
         "folder": {"type": "string", "maxLength": 1024, "description": "The folder, a full path."}}}},
    {"name": "greet", "title": "Say hello",
     "description": "Says hello to someone by name.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["name"], "properties": {
         "name": {"type": "string", "maxLength": 80, "description": "Who to greet."}}}},
]


class Problem(Exception):
    """Something the caller can fix: it becomes an isError result the model reads."""


def count_words(args):
    folder = args["folder"]
    if not os.path.isdir(folder):
        raise Problem("%s isn't a folder." % folder)
    counts = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith((".txt", ".md")):
            with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as f:
                counts[name] = len(f.read().split())
    if not counts:
        return "No .txt or .md files in %s." % folder
    lines = ["%s: %d words" % (name, n) for name, n in counts.items()]
    return "\n".join(lines + ["Total: %d words in %d files." % (sum(counts.values()), len(counts))])


def greet(args):
    return "Hello, %s!" % args["name"]


CALLS = {"count_words": count_words, "greet": greet}


def check_countdown(config, state):
    # Sidefolk keeps the state you return and hands it back at the next check (5 minutes or more later).
    left = (state or {}).get("left", config.get("checks", 3)) - 1
    return {"triggered": left == 0, "state": {"left": left},
            "summary": "Countdown finished." if left == 0 else "%d checks to go." % max(left, 0)}


def answer(method, params):
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                "serverInfo": {"name": "word-count", "version": "0.1.0"}}
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
    if method == "sidefolk/watch.check" and params.get("watcher") == "countdown":
        return check_countdown(params.get("config") or {}, params.get("state"))
    raise LookupError(method)


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if not isinstance(message, dict) or "id" not in message:
            continue  # notifications (notifications/initialized) need no answer
        reply = {"jsonrpc": "2.0", "id": message["id"]}
        try:
            reply["result"] = answer(message.get("method"), message.get("params") or {})
        except LookupError as error:
            reply["error"] = {"code": -32601, "message": "Method not found: %s" % error}
        except Exception as error:  # report, don't crash
            reply["error"] = {"code": -32603, "message": str(error)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
