#!/usr/bin/env python3
"""System Vitals, a sample Sidefolk extension (Python 3, standard library only).

It speaks MCP over stdio: one JSON-RPC 2.0 message per line in, one per line out. Sidefolk runs it in
a sandbox: no network, no files outside its own folder and its data folder, and only the programs
listed under permissions.exec in sidefolk-extension.json (pmset, vm_stat, sysctl).
"""
import json
import os
import pwd
import re
import subprocess
import sys

PROTOCOL = "2025-06-18"
NO_INPUT = {"type": "object", "properties": {}, "additionalProperties": False}

TOOLS = [
    {"name": "battery", "title": "Battery status", "inputSchema": NO_INPUT,
     "description": "Battery charge in percent, whether it is charging, and the time remaining."},
    {"name": "disk", "title": "Disk space", "inputSchema": NO_INPUT,
     "description": "Free and total space on the startup disk (and the home disk if it is a different one)."},
    {"name": "memory", "title": "Memory use", "inputSchema": NO_INPUT,
     "description": "How much memory is installed and in use, and the system's memory pressure."},
]


def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout


# --- Readings -----------------------------------------------------------------------------------

def battery():
    out = run(["/usr/bin/pmset", "-g", "batt"])
    source = re.search(r"Now drawing from '([^']+)'", out)
    reading = {"source": source.group(1) if source else None, "present": False}
    m = re.search(r"(\d+)%;\s*([^;]+);", out)
    if m:
        remaining = re.search(r"(\d+:\d+) remaining", out)
        reading.update(present=True, percent=int(m.group(1)), state=m.group(2).strip(),
                       remaining=remaining.group(1) if remaining and remaining.group(1) != "0:00" else None)
    return reading


def battery_text(b):
    if not b["present"]:
        return "This Mac has no battery; it runs on %s." % (b["source"] or "power")
    text = "Battery at %d%%, %s" % (b["percent"], b["state"])
    if b.get("remaining"):
        text += " (%s left)" % b["remaining"]
    return text + "."


def home_dir():
    try:
        return pwd.getpwuid(os.getuid()).pw_dir
    except KeyError:
        return "/System/Volumes/Data"


def disk():
    volumes = []
    for label, path in (("Startup disk", "/"), ("Home", home_dir())):
        st = os.statvfs(path)  # needs only metadata access, which the sandbox allows
        free, total = st.f_bavail * st.f_frsize, st.f_blocks * st.f_frsize
        if any(v["total_bytes"] == total for v in volumes):
            continue  # same APFS container: same space, counted once
        volumes.append({"label": label, "free_bytes": free, "total_bytes": total,
                        "free_gb": round(free / 1e9, 1), "total_gb": round(total / 1e9, 1)})
    return {"volumes": volumes}


def disk_text(d):
    return " ".join("%s: %.1f GB free of %.1f GB." % (v["label"], v["free_gb"], v["total_gb"]) for v in d["volumes"])


def memory():
    total_line, pressure_line = run(["/usr/sbin/sysctl", "-n", "hw.memsize", "kern.memorystatus_vm_pressure_level"]).split()[:2]
    vm = run(["/usr/bin/vm_stat"])
    page = int(re.search(r"page size of (\d+) bytes", vm).group(1))

    def pages(name):
        m = re.search(r"^%s:\s+(\d+)\." % re.escape(name), vm, re.M)
        return int(m.group(1)) if m else 0

    # The same sum Activity Monitor shows as "Memory Used": app memory + wired + compressed.
    used_pages = pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down") + pages("Pages occupied by compressor")
    total = int(total_line)
    pressure = {"1": "normal", "2": "warning", "4": "critical"}.get(pressure_line, "unknown")
    return {"total_gb": round(total / 2**30, 1), "used_gb": round(used_pages * page / 2**30, 1), "pressure": pressure}


def memory_text(m):
    return "%.1f GB of %.1f GB in use; memory pressure is %s." % (m["used_gb"], m["total_gb"], m["pressure"])


READINGS = {"battery": (battery, battery_text), "disk": (disk, disk_text), "memory": (memory, memory_text)}


# --- Watchers -----------------------------------------------------------------------------------
# Each check returns triggered, the state to keep for next time, and a one-line summary. Both
# watchers fire once when the reading crosses the line, not on every check while it stays low.

def check_battery_low(config, state):
    b = battery()
    below = config.get("below_percent", 20)
    low = b["present"] and b["percent"] < below and b["state"] not in ("charging", "charged", "finishing charge", "AC attached")
    was_low = bool((state or {}).get("low"))
    return {"triggered": low and not was_low, "state": {"low": low}, "summary": battery_text(b)}


def check_disk_low(config, state):
    startup = disk()["volumes"][0]
    low = startup["free_gb"] < config.get("below_gb", 10)
    was_low = bool((state or {}).get("low"))
    summary = "Only %.1f GB free on the startup disk." % startup["free_gb"] if low else disk_text({"volumes": [startup]})
    return {"triggered": low and not was_low, "state": {"low": low}, "summary": summary}


WATCHERS = {"battery_low": check_battery_low, "disk_low": check_disk_low}


# --- Protocol -----------------------------------------------------------------------------------

def call_tool(name, arguments):
    if name not in READINGS:
        return {"content": [{"type": "text", "text": "Unknown tool: %s" % name}], "isError": True}
    read, describe = READINGS[name]
    data = read()
    return {"content": [{"type": "text", "text": describe(data)}], "structuredContent": data}


def answer(message):
    method, params = message.get("method"), message.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                "serverInfo": {"name": "system-vitals", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return call_tool(params.get("name"), params.get("arguments") or {})
    if method == "sidefolk/watch.check":
        check = WATCHERS.get(params.get("watcher"))
        if check is None:
            raise LookupError("Unknown watcher: %s" % params.get("watcher"))
        return check(params.get("config") or {}, params.get("state"))
    raise NotImplementedError(method)


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if not isinstance(message, dict) or "id" not in message or "method" not in message:
            continue  # notifications (notifications/initialized) and stray responses need no answer
        reply = {"jsonrpc": "2.0", "id": message["id"]}
        try:
            reply["result"] = answer(message)
        except NotImplementedError as e:
            reply["error"] = {"code": -32601, "message": "Method not found: %s" % e}
        except Exception as e:  # report, don't crash: one bad reading shouldn't stop the extension
            reply["error"] = {"code": -32603, "message": str(e)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
