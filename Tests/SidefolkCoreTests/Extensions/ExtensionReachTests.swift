import Foundation
import Testing
@testable import SidefolkCore

/// What a flow can reach beyond what was there before (D127 to D129): a whole job for the companion, Focus and Quiet, and hearing what happens.
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

    @Test func focusAndQuietMayStandOnAPlanButOnlyWrittenOut() async throws {
        let env = try TestEnv()
        let tool = AttentionSetTool(settings: await SettingsStore(db: env.db, events: env.events), attention: AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock))
        #expect(ExtensionActionPolicy.spec(tool).risk == .medium)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: tool, spec: ExtensionActionPolicy.spec(tool)), template: ["mode": "focus", "minutes": 30]))
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: tool, spec: ExtensionActionPolicy.spec(tool)), template: ["mode": "{{what}}", "minutes": 30]))
    }

    @Test func aPageSaysItsAccentAndAnythingElseIsDropped() throws {
        let page = try ExtensionPage.parse(["sections": [], "accent": ["#2A6FE8", "#6E4BF2", "#000000"]])
        #expect(page.accent == ["#2A6FE8", "#6E4BF2"])
        #expect(try ExtensionPage.parse(["sections": [], "accent": ["nonsense"]]).accent.isEmpty)
        #expect(try ExtensionPage.parse(["sections": [], "accent": ["#FFEE00"]]).accent.isEmpty, "too light to hold white words")
    }

    @Test func aJobIsNeverOfferedToTheModelAndAsksWithoutAPlan() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        #expect(!job.spec.offeredToModel, "it can't start one of itself")
        #expect(ExtensionActionPolicy.offers(job, to: "com.example.a"))
        #expect(ExtensionActionPolicy.spec(job).risk == .medium)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy my Downloads"]), "written out, the person reads it once")
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy {{agenda}}"]), "words from elsewhere ask each time")
    }

    @Test func theCardsLayoutCantHideALine() {
        let plan = ExtensionPlanWords.body(name: "Flows", lines: [(text: "Save a note · text: “Hello”", standing: true, new: false), (text: "Notify · body: “[filled in when it runs]”", standing: true, new: false),
                                                                  (text: "Delete it · id: “7”", standing: false, new: false)], when: "Every day", perDay: 200, ttl: nil, revised: false)
        let awkward = ["• starts with a mark\nand goes on", "Heading:\nplain line\n• a mark", "One line", "", "A\n\n\nB", "Heading:\n• one\n• two\n\n• alone", "• a\n• b"]
        for text in [plan] + awkward {
            #expect(ApprovalText.joined(ApprovalText.parts(text)) == text, "every line stays, in order: \(text)")
        }
        let parts = ApprovalText.parts(plan)
        #expect(parts.contains { $0.rows.contains("Save a note · text: “Hello”") })
        #expect(parts.contains { $0.rows.contains("Delete it · id: “7”") })
    }

    @Test func whatACardCantShowCantStand() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        let facade = ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job))
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": "Tidy\u{E0100}up"]), "a variation selector shows as nothing")
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": "Tidy\u{00AD}up"]), "nor does a soft hyphen")
        let long = String(repeating: "a", count: 290)
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["opts": ["a": .string(long), "url": "https://example.com/more"]]), "an object is clipped whole")
        #expect(ExtensionPlanRules.standing(tool: facade, template: ["opts": ["a": "short"]]))
    }

    @Test func peoplesOwnWritingIsPlainAndHiddenCharactersArent() {
        for words in ["Tidy up ❤️ today", "👩‍💻 at work", "❤️‍🔥 hot", "می‌خواهم", "क्‍ष", "Hello"] { #expect(ExtensionPlanRules.plain(words), "\(words)") }
        for words in ["a\u{200D}", "\u{200D}a", "a\u{200D}\u{200D}b", "a\u{200C} b", "\u{FE0F}a", "a\u{FE0F}\u{FE0F}b", "a\u{00AD}b", "a\u{E0100}b", "a\u{202E}b", "a\u{200B}b"] {
            #expect(!ExtensionPlanRules.plain(words), "\(words.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }

    @Test func aJobThatWouldBeRefusedDoesntStand() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        let facade = ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job))
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": .string(String(repeating: "a", count: CompanionJobTool.longest + 1))]))
        #expect(ExtensionPlanRules.standing(tool: facade, template: ["job": .string(String(repeating: "a", count: CompanionJobTool.longest))]))
    }

    @Test func aFailedJobNobodyReadStaysMarkedAsOutsideWords() async throws {
        let (world, runtime, _) = try await world([.failure(UserFacingError("No."))])
        let job = await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: false)))
        for await _ in job.events {}
        let first = try await world.exchanges.conversation(job.threadId).first
        #expect(first?.meta?["tainted"]?.boolValue == true)
    }

    @Test func aJobThatsTooLongOrHidesCharactersIsRefused() async throws {
        let tool = CompanionJobTool(agent: CompanionAgentSlot())
        let context = ToolContext(caller: .user, now: Date())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": .string(String(repeating: "a", count: CompanionJobTool.longest + 1))], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": "Tidy\u{202E}up"], context: context) }
    }

    @Test func whatAJobDoesDoesntCountAsSomethingHappening() {
        let activity = ToolActivity(id: "a", tool: "notes.save", title: "x", summary: "Saved", category: .notes, caller: .agent(runId: AgentRuntime.jobPrefix + "1"))
        #expect(Happening(activity) == nil)
    }

    @Test func noBrainMeansNoJob() async throws {
        let tool = CompanionJobTool(agent: CompanionAgentSlot())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": "Tidy up"], context: ToolContext(caller: .user, now: Date())) }
    }

    // MARK: A job, in a real turn

    private func world(_ steps: [ScriptedModel.Step]) async throws -> (SidefolkRuntime, AgentRuntime, ScriptedModel) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-job-\(UUID().uuidString)", isDirectory: true)
        let clock = ManualClock(TestEnv.referenceDate)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
        let model = ScriptedModel(steps)
        var settings = await runtime.settings.current
        settings.provider.kind = .anthropic
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, clock: clock)
        let agent = AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context, factory: factory, settings: { [settings] in settings }, clock: clock)
        return (runtime, agent, model)
    }

    @Test func aJobStaysOutOfThePersonsConversationAndSaysWhatItIs() async throws {
        let (world, runtime, _) = try await world([.turn(.reply("Nothing to report.")), .turn(.reply("Hi."))])
        let job = await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: true)))
        for await _ in job.events {}
        #expect(job.threadId.hasPrefix(AgentRuntime.jobPrefix))
        #expect(job.runId.hasPrefix(AgentRuntime.jobPrefix))
        let next = await runtime.submit(AgentRequest(text: "Hello"))
        for await _ in next.events {}
        #expect(next.threadId != job.threadId, "the person's next words don't continue it")
        let said = try await world.exchanges.conversation(job.threadId).first?.content
        #expect(said?.contains("Tidy up") == true && said != "Tidy up", "in the record as someone else's words")
    }

    @Test func aJobCantUseWhatAlwaysAsksButThePersonsOwnTurnStillCan() async throws {
        let (world, runtime, model) = try await world([.turn(.reply("Nothing to report.")), .turn(.reply("Hi."))])
        let spec = ToolSpec(name: "ext.mcp.exec", title: "x", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        world.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.x", extensionName: "x", remoteName: "exec", sandboxed: false) { _, _ in ToolResult(text: "") })
        for await _ in await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: true))).events {}
        for await _ in await runtime.submit(AgentRequest(text: "Hello", newThread: true)).events {}
        #expect(model.requests[0].tools.contains { $0.name == "ext.mcp.exec" } == false)
        #expect(model.requests[1].tools.contains { $0.name == "ext.mcp.exec" })
    }

    @Test func aJobNobodyReadStartsAsOutsideWordsAndOneOnAPlanDoesnt() async throws {
        func tainted(_ read: Bool) async throws -> Bool? {
            let (_, runtime, _) = try await world([.turn(.reply("Nothing to report."))])
            var said: Bool?
            for await event in await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: read))).events {
                if case .reply(let reply) = event { said = reply.tainted }
                if case .failed(let problem) = event { Issue.record("\(problem.message)") }
            }
            return said
        }
        #expect(try await tainted(false) == true)
        #expect(try await tainted(true) == false)
    }
}
