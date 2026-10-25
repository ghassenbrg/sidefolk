#!/usr/bin/env python3
"""Hello Folk: the smallest working Sidefolk extension. Copy this folder to start your own.

Sidefolk starts this script and talks to it over stdin/stdout, one JSON message per line (MCP).
Answer every message that has an "id"; ignore the ones that don't. Print nothing else to stdout
(use stderr for debugging: Sidefolk keeps the last few KB for its diagnostics).
"""
import json
import sys

TOOLS = [{
    "name": "hello",
    "description": "Say hello to someone by name.",
    "inputSchema": {
        "type": "object",
        "properties": {"name": {"type": "string", "description": "Who to greet."}},
        "required": ["name"],
        "additionalProperties": False,
    },
}]


def answer(method, params):
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}}, "serverInfo": {"name": "hello-folk", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call" and params.get("name") == "hello":
        name = (params.get("arguments") or {}).get("name", "friend")
        return {"content": [{"type": "text", "text": "Hello, %s!" % name}]}
    if method == "sidefolk/watch.check" and params.get("watcher") == "countdown":
        # Sidefolk keeps `state` between checks and hands it back next time.
        left = (params.get("state") or {}).get("left", params["config"].get("checks", 3)) - 1
        return {"triggered": left == 0, "state": {"left": left},
                "summary": "Countdown finished." if left == 0 else "%d checks to go." % max(left, 0)}
    raise LookupError("Unknown method: %s" % method)


for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        continue
    try:
        reply = {"jsonrpc": "2.0", "id": message["id"], "result": answer(message["method"], message.get("params") or {})}
    except Exception as e:
        reply = {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": str(e)}}
    print(json.dumps(reply), flush=True)
