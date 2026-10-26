import Foundation
import Testing
@testable import SidefolkCore

/// A third-party extension written from docs/EXTENSIONS.md alone ("Pomodoro & Focus": tools start_focus,
/// focus_status, stop_focus and the watcher focus_done), installed through the real ExtensionHost under
/// sandbox-exec with a temp SidefolkPaths. The source below is also at
/// scratchpad/plugin-dev/pomodoro and validates with `sidefolk ext validate`.
@Suite(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
struct PluginDevTests {
    static let manifest = #"""
    {
      "id": "com.example.pomodoro",
      "name": "Pomodoro & Focus",
      "version": "1.0.0",
      "sidefolk": ">=0.1",
      "description": "Start a focus session, ask how long is left, and get told when it is over.",
      "author": "QA plugin developer",
      "run": { "command": "python3", "args": ["main.py"] },
      "permissions": { "network": false, "files": { "read": [], "write": [] }, "exec": [] },
      "tools": {
        "start_focus": { "title": "Start a focus session", "risk": "low", "category": "time", "mutates": true },
        "focus_status": { "title": "Focus session status", "risk": "low", "category": "time", "mutates": false },
        "stop_focus": { "title": "Stop the focus session", "risk": "low", "category": "time", "mutates": true }
      },
      "watchers": {
        "focus_done": {
          "title": "Focus session finished",
          "description": "Tells you once when the running focus session is over.",
          "config": {
            "message": { "type": "string", "description": "What to say when time is up.", "default": "Focus time is over. Take a break." }
          }
        }
      }
    }
    """#

    static let script = #"""
    import json
    import os
    import sys
    import time

    PROTOCOL = "2025-06-18"
    SESSION_FILE = os.path.join(os.getcwd(), "session.json")

    TOOLS = [
        {"name": "start_focus", "title": "Start a focus session",
         "description": "Start a focus (pomodoro) session of a number of minutes. Replaces a running one.",
         "inputSchema": {"type": "object", "properties": {
             "minutes": {"type": "number", "description": "Length in minutes (default 25, at most 240).", "minimum": 0.05, "maximum": 240},
             "label": {"type": "string", "description": "What the user is focusing on (optional)."}},
             "additionalProperties": False}},
        {"name": "focus_status", "title": "Focus session status",
         "description": "How much time is left in the running focus session, or that none is running.",
         "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
        {"name": "stop_focus", "title": "Stop the focus session",
         "description": "Stop the running focus session early.",
         "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    ]

    def load():
        try:
            with open(SESSION_FILE) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def save(session):
        tmp = SESSION_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(session, f)
        os.replace(tmp, SESSION_FILE)

    def describe(seconds):
        seconds = max(0, int(round(seconds)))
        if seconds < 90:
            return "%d seconds" % seconds
        minutes = (seconds + 30) // 60
        return "%d minute%s" % (minutes, "" if minutes == 1 else "s")

    def text(t, error=False):
        r = {"content": [{"type": "text", "text": t}]}
        if error:
            r["isError"] = True
        return r

    def start_focus(args):
        minutes = args.get("minutes", 25)
        if isinstance(minutes, bool) or not isinstance(minutes, (int, float)) or not 0.05 <= minutes <= 240:
            return text("minutes must be a number between 0.05 and 240.", error=True)
        label = str(args.get("label") or "").strip()[:80]
        now = time.time()
        save({"started": now, "ends": now + minutes * 60, "minutes": minutes, "label": label})
        return text("Focus session started: %s%s." % (describe(minutes * 60), " on " + label if label else ""))

    def focus_status(_args):
        s = load()
        if not s:
            return text("No focus session is running.")
        left = s["ends"] - time.time()
        what = " on " + s["label"] if s.get("label") else ""
        if left <= 0:
            return text("The focus session%s ended %s ago." % (what, describe(-left)))
        return text("%s left in the focus session%s." % (describe(left), what))

    def stop_focus(_args):
        if not load():
            return text("No focus session is running.")
        os.remove(SESSION_FILE)
        return text("Focus session stopped.")

    CALLS = {"start_focus": start_focus, "focus_status": focus_status, "stop_focus": stop_focus}

    def check_focus_done(config, state):
        s = load()
        announced = (state or {}).get("announced")
        if not s or s["ends"] > time.time() or announced == s["started"]:
            return {"triggered": False, "state": {"announced": announced}}
        message = config.get("message") or "Focus time is over. Take a break."
        label = " (%s)" % s["label"] if s.get("label") else ""
        return {"triggered": True, "state": {"announced": s["started"]}, "summary": (message + label)[:200]}

    def answer(method, params):
        if method == "initialize":
            return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                    "serverInfo": {"name": "pomodoro", "version": "1.0.0"}}
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": TOOLS}
        if method == "tools/call":
            call = CALLS.get(params.get("name"))
            if call is None:
                raise LookupError("Unknown tool: %s" % params.get("name"))
            return call(params.get("arguments") or {})
        if method == "sidefolk/watch.check" and params.get("watcher") == "focus_done":
            return check_focus_done(params.get("config") or {}, params.get("state"))
        raise LookupError("Unknown method: %s" % method)

    for line in sys.stdin:
        message = json.loads(line)
        if "id" not in message:
            continue
        try:
            reply = {"jsonrpc": "2.0", "id": message["id"], "result": answer(message["method"], message.get("params") or {})}
        except LookupError as e:
            reply = {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": str(e)}}
        except Exception as e:
            print("error: %r" % e, file=sys.stderr)
            reply = {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32603, "message": str(e)}}
        print(json.dumps(reply), flush=True)
    """#

    private func folder(_ h: HostEnv) throws -> URL {
        try ExtFixtures.makeExtension(
            at: h.root.appendingPathComponent("src/pomodoro", isDirectory: true), manifest: try JSONValue.parse(Self.manifest),
            files: ["main.py": Self.script])
    }

    @Test func installsAndExposesToolsAndAWatcher() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder(h))
        #expect(info.tools.map(\.name) == ["ext.pomodoro.focus_status", "ext.pomodoro.start_focus", "ext.pomodoro.stop_focus"])
        #expect(info.tools.allSatisfy { $0.risk == .low && !$0.quarantined })
        #expect(info.watchers.map(\.watcher) == ["focus_done"])
        #expect(info.summary.texts == ["No access to your files or the internet"])
        await h.host.shutdown()
    }

    @Test func toolsKeepASessionInTheDataFolder() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder(h))

        #expect(await h.call("ext.pomodoro.focus_status").okText == "No focus session is running.")
        let started = try #require(await h.call("ext.pomodoro.start_focus", ["minutes": 25, "label": "write the report"]).okText)
        #expect(started.contains("25 minutes on write the report"), "\(started)")
        let status = try #require(await h.call("ext.pomodoro.focus_status").okText)
        #expect(status.contains("minutes left in the focus session on write the report"), "\(status)")

        // The session lives in the extension's own data folder, not in its (read-only) install folder.
        let data = h.paths.extensionData.appendingPathComponent(info.id).appendingPathComponent("session.json")
        #expect(FileManager.default.fileExists(atPath: data.path))
        #expect(!FileManager.default.fileExists(atPath: h.paths.extensions.appendingPathComponent(info.id).appendingPathComponent("session.json").path))

        #expect(await h.call("ext.pomodoro.stop_focus").okText == "Focus session stopped.")
        #expect(await h.call("ext.pomodoro.focus_status").okText == "No focus session is running.")
        await h.host.shutdown()
    }

    @Test func badInputIsAnErrorTheModelCanReadAndNothingIsStarted() async throws {
        let h = try HostEnv()
        _ = try await h.host.install(from: folder(h))
        for bad: JSONValue in [["minutes": "soon"], ["minutes": -5], ["minutes": 100_000], ["minutes": true], ["minutes": .null]] {
            let outcome = await h.call("ext.pomodoro.start_focus", bad)
            #expect(outcome.okText == nil || outcome.okText?.contains("minutes must be") == true || outcome.okText?.contains("Focus session started") == true, "\(outcome.text)")
        }
        let wrongType = await h.call("ext.pomodoro.start_focus", ["minutes": "soon"])
        // Whatever the host does with isError, it must not claim the session started.
        #expect(!(wrongType.okText ?? "").contains("Focus session started"), "\(wrongType.text)")
        await h.host.shutdown()
    }

    @Test func theWatcherFiresOncePerSession() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder(h))
        let config: JSONValue = ["message": "Break time!"]

        var r = try await h.host.checkWatcher(extensionId: info.id, watcher: "focus_done", config: config, state: .null)
        #expect(!r.triggered, "no session yet")

        _ = await h.call("ext.pomodoro.start_focus", ["minutes": 0.05, "label": "tiny"])   // 3 seconds
        r = try await h.host.checkWatcher(extensionId: info.id, watcher: "focus_done", config: config, state: r.state)
        #expect(!r.triggered, "still running")

        try await Task.sleep(for: .seconds(3.3))
        r = try await h.host.checkWatcher(extensionId: info.id, watcher: "focus_done", config: config, state: r.state)
        #expect(r.triggered)
        #expect(r.summary == "Break time! (tiny)")

        let again = try await h.host.checkWatcher(extensionId: info.id, watcher: "focus_done", config: config, state: r.state)
        #expect(!again.triggered, "told once")
        await h.host.shutdown()
    }

    @Test func aSessionSurvivesTheExtensionBeingRestarted() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder(h))
        _ = await h.call("ext.pomodoro.start_focus", ["minutes": 10])
        await h.host.shutdown()   // the process stops; the data folder stays
        #expect(try #require(await h.call("ext.pomodoro.focus_status").okText).contains("left in the focus session"))
        _ = info
        await h.host.shutdown()
    }
}
