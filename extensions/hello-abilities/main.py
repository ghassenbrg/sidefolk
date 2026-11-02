#!/usr/bin/env python3
"""Hello Abilities: one of each ability of Sidefolk D100, in plain Python and the plain protocol, to copy from.
It doesn't ship. Swift extensions get all of it from the Kit (`Block.cards`, `ExtensionSettings`, `AI.ask`, `Activity.add`)."""
import json
import sys
import uuid

SCHEMA = {"type": "object", "additionalProperties": True}
TOOLS = [{"name": n, "description": d, "inputSchema": SCHEMA} for n, d in [
    ("greet", "Greets someone."), ("again", "Greets again."), ("riddle", "Asks the person's AI for a line about a word."),
    ("note", "Adds one row to History."), ("keep", "Keeps a link."), ("quiet", "Greets quietly and turns the loud setting off.")]]

settings = {}      # They come with every request, and with sidefolk/settings.changed.
ai_name = None     # The person's AI by name, while this extension may ask.
carried = None     # What sidefolk/settings.carry gave, once.
kept = []


def send(method, params):
    print(json.dumps({"jsonrpc": "2.0", "method": method, "params": params}), flush=True)


def ask_ai(prompt, label):
    """A notice out, and one notice back with the same request id: the answer comes to this program alone. Check it before use."""
    request = str(uuid.uuid4())
    send("sidefolk/ai.request", {"request": request, "prompt": prompt, "label": label})
    for line in sys.stdin:
        message = json.loads(line)
        if message.get("method") == "sidefolk/ai.answer" and message["params"].get("request") == request:
            return message["params"]
    return {"ok": False, "reason": "failed"}


def page():
    return {"summary": {"title": "Hello", "tone": "good"}, "sections": [
        {"blocks": [{"type": "hero", "title": "Hello", "detail": "One of each part", "symbol": "hand.wave",
                     "scene": {"pack": "scene.png"}, "figure": {"companion": "full"}, "says": "Hi there!",
                     "actions": [{"type": "button", "label": "Greet me", "tool": "greet", "input": {"who": "you"}, "style": "primary"}]}]},
        {"blocks": [{"type": "stats", "items": [{"label": "Kept", "value": str(len(kept)), "symbol": "film"}]}]},
        {"blocks": [{"type": "tabs", "tabs": [
            {"id": "cards", "label": "Cards", "sections": [{"blocks": [{"type": "cards", "items": [
                {"title": "A card", "detail": "With a picture from the pack", "picture": {"pack": "scene.png"}, "badge": {"text": "New", "tone": "info"},
                 "actions": [{"type": "button", "label": "Greet", "tool": "greet", "input": {"who": "the card"}}]}]}]}]},
            {"id": "badges", "label": "Badges", "sections": [{"blocks": [{"type": "badges", "items": [
                {"title": "First hello", "earned": True}, {"title": "Ten hellos", "value": 3, "goal": 10}]}]}]}]}]},
        {"blocks": [{"type": "recent", "title": "Lately", "items": [{"title": "Said hello", "at": "2026-11-01T09:00:00Z", "tone": "good"}]}]},
        {"blocks": [{"type": "settings", "title": "Settings", "ai": True}]}]}


def call(name, args):
    if name == "greet":
        who = args.get("who") or settings.get("name", "friend")
        mark = "!" if settings.get("loud") else "."
        times = int(args.get("times") or settings.get("times", 1))
        about = " about " + args["topic"] if args.get("topic") else ""
        return " ".join(["Hello, %s%s%s" % (who, about, mark)] * times) + " (%s)" % (args.get("tone") or settings.get("tone"))
    if name == "again":
        return "Hello again."
    if name == "riddle":
        reply = ask_ai("Write one short line about: " + args.get("word", ""), "A line about a word")
        return "%s, by %s" % (reply["text"], reply["made_by"]) if reply.get("ok") else "No: " + reply.get("reason", "?")
    if name == "note":
        send("sidefolk/activity.add", {"text": args.get("text", "Said hello"), "key": "hello", "result": "done"})
        return "Noted."
    if name == "keep":
        kept.append(args.get("url", ""))
        return "Kept " + args.get("url", "")
    if name == "quiet":
        send("sidefolk/settings.set", {"key": "loud", "value": False})
        return "Quietly."
    raise LookupError(name)


def answer(method, params):
    global settings, ai_name, carried
    if "settings" in params:
        settings = params["settings"]
    if method == "tools/call" or method.startswith("sidefolk/"):
        ai_name = params.get("ai")
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                "serverInfo": {"name": "hello-abilities", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return {"content": [{"type": "text", "text": call(params["name"], params.get("arguments") or {})}]}
    if method == "sidefolk/page.render":
        return {"page": page()}
    if method == "sidefolk/settings.carry":
        # What the app used to keep for this work, once: keep what still means something.
        carried = params["values"]
        return {"settings": {"tone": carried.get("mood"), "times": carried.get("repeat")}}
    raise LookupError("Unknown method: %s" % method)


for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        if message.get("method") == "sidefolk/settings.changed":
            settings = message["params"]["settings"]
        continue
    try:
        reply = {"jsonrpc": "2.0", "id": message["id"], "result": answer(message["method"], message.get("params") or {})}
    except Exception as e:
        reply = {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": str(e)}}
    print(json.dumps(reply), flush=True)
