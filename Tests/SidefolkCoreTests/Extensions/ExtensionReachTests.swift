import Foundation
import Testing
@testable import SidefolkCore

/// What a flow can reach beyond what was there before (D120 to D123): a whole job for the companion, Focus and Quiet, and hearing what happens.
@Suite("An extension's wider reach", .serialized)
struct ExtensionReachTests {
    private static let listener = """
    import json, os, sys
    def send(o): sys.stdout.write(json.dumps(o) + "\\n"); sys.stdout.flush()
    for line in sys.stdin:
        m = json.loads(line)
        if m.get("method") == "initialize":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
        elif m.get("method") == "tools/list":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"tools": [{"name": "heard", "description": "", "inputSchema": {"type": "object", "properties": {}}}]}})
        elif m.get("method") == "sidefolk/happened":
            open(os.path.join(os.environ["SIDEFOLK_DATA_DIR"], "heard.json"), "w").write(json.dumps(m["params"]))
        elif m.get("method") == "tools/call":
            path = os.path.join(os.environ["SIDEFOLK_DATA_DIR"], "heard.json")
            words = open(path).read() if os.path.exists(path) else "nothing"
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": words}]}})
        elif "id" in m:
            send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
    """

    private func heard(_ permissions: JSONValue, name: String) async throws -> String {
        let h = try HostEnv()
        let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                   "permissions": permissions, "tools": ["heard": ["title": "Heard", "risk": "low", "mutates": false]]]
        try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": Self.listener]))
        _ = await h.call("ext.\(name).heard")
        await h.host.tell(Happening(name: "reminder.fired", title: "Call the bank"))
        for _ in 0..<40 {
            if let text = (await h.call("ext.\(name).heard")).okText, text != "nothing" { return text }
            try await Task.sleep(for: .milliseconds(50))
        }
        return ""
    }

    @Test func anExtensionThatCantReachOutHearsTheWords() async throws {
        let words = try await heard(["events": ["purpose": "to start what you set up"]], name: "inside")
        #expect(words.contains("reminder.fired"))
        #expect(words.contains("Call the bank"))
    }

    @Test func oneThatCanReachOutHearsOnlyWhatAndWhen() async throws {
        let words = try await heard(["network": true, "network_purpose": "to look things up", "events": ["purpose": "to start what you set up"]], name: "outside")
        #expect(words.contains("reminder.fired"))
        #expect(!words.contains("Call the bank"))
    }

    @Test func withoutThePermissionNothingIsHeard() async throws {
        let h = try HostEnv()
        let manifest: JSONValue = ["id": "com.example.deaf", "name": "deaf", "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                   "tools": ["heard": ["title": "Heard", "risk": "low", "mutates": false]]]
        try await h.host.install(from: h.source("deaf", manifest: manifest, files: ["server.py": Self.listener]))
        _ = await h.call("ext.deaf.heard")
        await h.host.tell(Happening(name: "reminder.fired", title: "Call the bank"))
        try await Task.sleep(for: .milliseconds(200))
        #expect((await h.call("ext.deaf.heard")).okText == "nothing")
    }

    @Test func whatAnExtensionDidDoesntCountAsSomethingHappening() {
        func activity(_ caller: Caller, _ tool: String) -> ToolActivity { ToolActivity(id: "a", tool: tool, title: tool, summary: "Saved", category: .notes, caller: caller) }
        #expect(Happening(activity(.user, "notes.save"))?.name == "note.saved")
        #expect(Happening(activity(.agent(runId: "r"), "reminders.create"))?.name == "reminder.created")
        #expect(Happening(activity(.extension(id: "com.example.a"), "notes.save")) == nil, "or a flow could set itself off")
        #expect(Happening(activity(.user, "web.fetch")) == nil)
    }

    @Test func theInstallSheetSaysItHearsAndWhetherItGetsTheWords() {
        let inside = PermissionSummary.forExtension(ExtensionPermissions(events: ExtensionPurpose(purpose: "to start what you set up")))
        let line = inside.lines.first { $0.kind == .events }
        #expect(line?.caution == true)
        #expect(line?.note?.contains("titles") == true)
        let outside = PermissionSummary.forExtension(ExtensionPermissions(network: true, events: ExtensionPurpose(purpose: "to start what you set up")))
        #expect(outside.lines.first { $0.kind == .events }?.note?.contains("never the words") == true)
    }

    @Test func aPlanCantStandOnAnUpdateThatAddsHearing() throws {
        #expect(ExtensionPermissions(events: ExtensionPurpose(purpose: "to x")).widens(ExtensionPermissions()))
    }

    @Test func focusAndQuietAlwaysEnd() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        let tool = AttentionSetTool(settings: settings, attention: attention)
        let context = ToolContext(caller: .user, now: Date())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["mode": "quiet"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["mode": "focus", "minutes": 100_000], context: context) }
        _ = try await tool.run(["mode": "quiet", "minutes": 30], context: context)
        #expect(settings.current.quietUntil != nil)
        #expect(settings.current.quietUntil != Date.distantFuture)
        _ = try await tool.run(["mode": "open"], context: context)
        #expect(settings.current.quietUntil == nil)
    }

    @Test func aJobIsNeverOfferedToTheModelAndAsksWithoutAPlan() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        #expect(!job.spec.offeredToModel, "it can't start one of itself")
        #expect(ExtensionActionPolicy.offers(job, to: "com.example.a"))
        #expect(ExtensionActionPolicy.spec(job).risk == .medium)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy my Downloads"]), "written out, the person reads it once")
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy {{agenda}}"]), "words from elsewhere ask each time")
    }

    @Test func noBrainMeansNoJob() async throws {
        let tool = CompanionJobTool(agent: CompanionAgentSlot())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": "Tidy up"], context: ToolContext(caller: .user, now: Date())) }
    }
}
