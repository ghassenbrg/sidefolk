import Foundation
@testable import SidefolkCore
import Testing

/// An extension using Sidefolk's tools (D110, SECURITY T43): what it can reach, what asks, and what a plan the person read lets through.
@Suite struct ExtensionActionsTests {
    /// Passes a notice to the host and returns its first reply, so a test can speak the program's side of the protocol.
    static let bridge = """
    import json, sys, uuid
    def send(m): sys.stdout.write(json.dumps(m) + "\\n"); sys.stdout.flush()
    answers = {"sidefolk/tools.list": "sidefolk/tools.listed", "sidefolk/tools.check": "sidefolk/tools.checked",
               "sidefolk/tools.call": "sidefolk/tools.result", "sidefolk/plan.approve": "sidefolk/plan.result"}
    tools = [{"name": "ask_host", "title": "Ask the host", "description": "", "inputSchema": {"type": "object", "properties": {"method": {"type": "string"}, "params": {"type": "object"}}}}]
    for line in sys.stdin:
        m = json.loads(line)
        if m.get("method") == "initialize":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "b", "version": "1"}}})
        elif m.get("method") == "tools/list":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"tools": tools}})
        elif m.get("method") == "tools/call":
            a = m["params"]["arguments"]
            p = dict(a.get("params", {})); p["request"] = str(uuid.uuid4())
            send({"jsonrpc": "2.0", "method": a["method"], "params": p})
            want = answers[a["method"]]
            for reply in sys.stdin:
                r = json.loads(reply)
                if r.get("method") == want and r["params"].get("request") == p["request"]:
                    send({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": json.dumps(r["params"])}]}})
                    break
        elif "id" in m:
            send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
    """

    final class World: @unchecked Sendable {
        let h: HostEnv
        let gateway: ExtensionActionGateway

        init() async throws {
            let env = try TestEnv()
            let gateway = ExtensionActionGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events)
            self.gateway = gateway
            h = try HostEnv(env: env) { $0.actions = gateway }
            h.env.registry.register(Probe(name: "notify.user", risk: .low, capabilities: [], mutates: false))
            h.env.registry.register(Probe(name: "notes.save", risk: .low, capabilities: [.notebook], mutates: true))
            h.env.registry.register(Probe(name: "notes.search", risk: .low, capabilities: [.notebook], mutates: false))
            h.env.registry.register(Probe(name: "web.fetch", risk: .low, capabilities: [.network], mutates: false, urlParameter: "url"))
            h.env.registry.register(Probe(name: "clipboard.read", risk: .low, capabilities: [.clipboard], mutates: false))
            h.env.registry.register(Probe(name: "skills.create", risk: .low, capabilities: [], mutates: true))
            h.env.registry.register(ExtensionPlanEndTool(host: h.host))
        }

        func install(_ permissions: JSONValue = ["act": ["purpose": "to run what you set up"]], name: String = "actor") async throws -> String {
            let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name.capitalized), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                       "permissions": permissions, "tools": ["ask_host": ["title": "Ask the host", "risk": "low", "mutates": false]]]
            try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": ExtensionActionsTests.bridge]))
            return "ext.\(name).ask_host"
        }

        /// What the host answered, asked from the program. `caller` is who started the tool.
        func ask(_ tool: String, _ method: String, _ params: JSONValue = .object([:]), caller: Caller = .user) async -> JSONValue {
            let outcome = await h.env.executor.execute(name: tool, input: ["method": .string(method), "params": params], caller: caller, timeout: 30)
            guard case .ok(let r) = outcome.status, let json = try? JSONValue.parse(Data(r.text.utf8)) else { return .null }
            return json
        }

        /// Answers the next card when it appears, and returns what it asked.
        func answerCard(_ decision: ApprovalDecision) async -> ApprovalRequest? {
            for _ in 0..<200 {
                if let card = await h.env.broker.pending().first {
                    await h.env.broker.resolve(id: card.id, decision: decision)
                    return card
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return nil
        }

        var morning: JSONValue {
            ["id": "morning", "title": "Morning", "when": "Weekdays at 8:30", "steps": [
                ["tool": "notes.search", "input": ["query": "today"]],
                ["tool": "notes.save", "input": ["text": "Brief: {{brief}}"]],
                ["tool": "notify.user", "input": ["title": "{{brief}}"]],
                ["tool": "web.fetch", "input": ["url": "{{where}}"]],
            ]]
        }

        func allowMorning(_ tool: String) async -> JSONValue {
            async let answer = ask(tool, "sidefolk/plan.approve", ["plan": morning])
            _ = await answerCard(.allowOnce)
            return await answer
        }
    }

    /// A built-in stand-in with the name and reach of the real one.
    struct Probe: Tool {
        var name: String
        var risk: Risk
        var capabilities: Set<Capability>
        var mutates: Bool
        var urlParameter: String?

        var spec: ToolSpec {
            ToolSpec(name: name, title: name, description: "", inputSchema: .object(["type": "object"]), risk: risk, capabilities: capabilities, category: .system, mutates: mutates)
        }

        func summary(for input: JSONValue) -> String { name }
        func scope(for input: JSONValue) -> ToolScope { urlParameter.flatMap { input.string($0) }.map { ToolScope(url: $0) } ?? .none }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult { ToolResult(text: "ran \(name)") }
    }

    // MARK: What it may reach

    @Test func onlyTheClosedListAndOtherSandboxedExtensionsAreOffered() async throws {
        let w = try await World()
        let tool = try await w.install()
        let names = await w.ask(tool, "sidefolk/tools.list")["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.contains("notes.save"))
        #expect(names.contains("notify.user"))
        #expect(!names.contains("skills.create"))
        #expect(!names.contains(tool), "its own tools aren't offered: it has its program")
        #expect(ExtensionActionPolicy.builtIn.isDisjoint(with: ["extensions.setting", "extensions.plan", "extensions.draft", "profile.remember", "profile.forget", "skills.create", "skills.delete"]))
    }

    @Test func everyOtherExtensionsToolIsOfferedAndOneOutsideASandboxAlwaysAsks() {
        let spec = ToolSpec(name: "ext.mcp.exec", title: "x", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        let mcp = ExtensionTool(spec: spec, extensionId: "mcp.x", extensionName: "x", remoteName: "exec", sandboxed: false) { _, _ in ToolResult(text: "") }
        #expect(ExtensionActionPolicy.offers(mcp, to: "com.example.other"))
        #expect(ExtensionActionPolicy.spec(mcp).risk == .high, "a card every time: it runs outside any sandbox")
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: mcp, spec: ExtensionActionPolicy.spec(mcp)), template: .object([:])), "and never in a plan")
        let sandboxed = ExtensionTool(spec: spec, extensionId: "com.example.x", extensionName: "x", remoteName: "exec") { _, _ in ToolResult(text: "") }
        #expect(ExtensionActionPolicy.offers(sandboxed, to: "com.example.other"))
        #expect(!ExtensionActionPolicy.offers(sandboxed, to: "com.example.x"))
        #expect(ExtensionActionPolicy.spec(sandboxed).risk == .medium)
        var runsAnything = spec
        runsAnything.capabilities.insert(.shell)
        let shell = ExtensionTool(spec: runsAnything, extensionId: "com.example.x", extensionName: "x", remoteName: "exec") { _, _ in ToolResult(text: "") }
        #expect(ExtensionActionPolicy.offers(shell, to: "com.example.other"))
        #expect(ExtensionActionPolicy.spec(shell).risk == .high)
        var page = spec
        page.offeredToModel = false
        let pageOnly = ExtensionTool(spec: page, extensionId: "com.example.x", extensionName: "x", remoteName: "exec") { _, _ in ToolResult(text: "") }
        #expect(ExtensionActionPolicy.offers(pageOnly, to: "com.example.other"), "kept from the model isn't kept from what the person builds")
    }

    @Test func anExtensionNeverGetsAlwaysForWhatAlwaysAsks() {
        let spec = ToolSpec(name: "watch.command", title: "x", description: "", inputSchema: .object([:]), risk: .high, capabilities: [.watch, .shell], category: .watch, mutates: true)
        let decision = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "x", scope: ToolScope(command: "/bin/echo hi"), caller: .extension(id: "com.example.a"), tainted: false,
                                                   policy: GuardPolicy(), grants: [], folders: [])
        guard case .ask(let request) = decision else {
            Issue.record("it asks")
            return
        }
        #expect(!request.canAlways)
    }

    @Test func noHostToolOfAnyExtensionsIsReachableThroughEitherGroup() throws {
        let env = try TestEnv()
        let internalTools = ["extensions.consent", "extensions.occurrences", "extensions.place_search", "extensions.plan", "extensions.plan_end", "extensions.setting", "extensions.ai_help", "extensions.activity"]
        for name in internalTools {
            env.registry.register(Probe(name: name, risk: .low, capabilities: [.extensions], mutates: true))
            #expect(env.registry.tool(named: name).map { ExtensionActionPolicy.offers($0, to: "com.example.a") } == false, "\(name) through act")
        }
        let gateway = ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events, access: { AgentAccess() })
        #expect(gateway.specs().isEmpty, "the group for other agents holds only tools an extension marked")
    }

    @Test func withoutThePermissionNothingIsAnswered() async throws {
        let w = try await World()
        let tool = try await w.install(.object([:]), name: "plain")
        let reply = await w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "input": ["text": "x"]])
        #expect(reply["ok"]?.boolValue == false)
        #expect((try await w.h.env.activity.recent(limit: 5, tool: "notes.save")).isEmpty)
    }

    // MARK: Cards

    @Test func aCallWithoutAPlanAsksEveryTimeAndNeverOffersAlways() async throws {
        let w = try await World()
        let tool = try await w.install()
        async let reply = w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "input": ["text": "x"]])
        let card = await w.answerCard(.allowOnce)
        #expect(card?.canAlways == false)
        #expect(card?.asker?.name == "Actor")
        #expect(await reply["status"]?.stringValue == "ok")
        async let again = w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "input": ["text": "y"]])
        #expect(await w.answerCard(.deny) != nil)
        #expect(await again["status"]?.stringValue == "denied")
        let rows = try await w.h.env.activity.recent(limit: 5, tool: "notes.save")
        #expect(rows.count == 2, "every call is in History, the refused one too")
    }

    @Test func reachingThePersonNeedsNoCardAndIsNamed() async throws {
        let w = try await World()
        let tool = try await w.install()
        let reply = await w.ask(tool, "sidefolk/tools.call", ["tool": "notify.user", "input": ["title": "Hello"]])
        #expect(reply["status"]?.stringValue == "ok")
    }

    @Test func oneCardAtATimeForAnExtension() async throws {
        let room = ApprovalBroker(events: EventBus())
        let caller = Caller.extension(id: "a")
        #expect(await room.hasRoom(for: caller))
        let request = ApprovalRequest(tool: "t", title: "t", summary: "s", risk: .medium, caller: caller, details: .none, canAlways: false)
        async let first = room.requestIfRoom(request, timeout: 5)
        while await room.pending().isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(await room.hasRoom(for: caller) == false)
        #expect(await room.hasRoom(for: .extension(id: "b")))
        await room.resolve(id: request.id, decision: .deny)
        _ = await first
    }

    // MARK: Plans

    @Test func aPlanIsReadInFullThenExactlyThatRunsWithoutACard() async throws {
        let w = try await World()
        let tool = try await w.install()
        async let answer = w.ask(tool, "sidefolk/plan.approve", ["plan": w.morning])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("the card must show the plan in full"); return }
        #expect(card?.summary == "Weekdays at 8:30")
        #expect(words.contains("filled in when it runs"))
        #expect(card?.canAlways == false)
        let reply = await answer
        #expect(reply["ok"]?.boolValue == true)
        #expect(reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true, true, true, false], "a filled-in address still asks")

        let saved = await w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "plan": "morning", "input": ["text": "Brief: rain at noon"]])
        #expect(saved["status"]?.stringValue == "ok")
        #expect(saved["standing"]?.boolValue == true)
        let row = try await w.h.env.activity.recent(limit: 1, tool: "notes.save").first
        #expect(row?.decision == .plan, "History says why there was no card")
    }

    @Test func aCallOutsideThePlanAsks() async throws {
        let w = try await World()
        let tool = try await w.install()
        _ = await w.allowMorning(tool)
        for input: JSONValue in [["text": "Not the plan's words"], ["text": "Brief: x", "collection": "Work"]] {
            async let reply = w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "plan": "morning", "input": input])
            #expect(await w.answerCard(.deny) != nil)
            #expect(await reply["standing"]?.boolValue == false)
        }
        async let moved = w.ask(tool, "sidefolk/tools.call", ["tool": "web.fetch", "plan": "morning", "input": ["url": "https://example.com/?q=notes"]])
        #expect(await w.answerCard(.deny) != nil, "an address filled in at run time is never without a card")
        _ = await moved
    }

    @Test func thePersonsAskEveryTimeOverridesAPlanAndSoDoesHighRisk() {
        let engine = PermissionEngine()
        let spec = ToolSpec(name: "notes.save", title: "t", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.notebook], category: .notes, mutates: true)
        let caller = Caller.extension(id: "a")
        func decide(_ policy: GuardPolicy, _ spec: ToolSpec) -> GuardDecision {
            engine.evaluate(spec: spec, input: .object([:]), summary: "", scope: .none, caller: caller, tainted: true, policy: policy, grants: [], folders: [], standing: true)
        }
        #expect(decide(GuardPolicy(), spec) == .allow(.plan))
        if case .ask = decide(GuardPolicy(mode: .askEveryTime), spec) {} else { Issue.record("Ask every time must ask") }
        var high = spec
        high.risk = .high
        if case .ask = decide(GuardPolicy(), high) {} else { Issue.record("high risk must ask") }
        if case .deny = decide(GuardPolicy(disabled: [.notebook]), spec) {} else { Issue.record("a capability turned off stays off") }
    }

    @Test func aModelsOrAnotherAgentsCallCantStartACard() async throws {
        let w = try await World()
        let tool = try await w.install()
        let steered = await w.ask(tool, "sidefolk/plan.approve", ["plan": w.morning], caller: .routine(id: "r"))
        #expect(steered["ok"]?.boolValue == false)
        #expect(steered["reason"]?.stringValue == "not_asked")
        #expect(await w.h.env.broker.pending().isEmpty)
    }

    @Test func anExtensionThatCanReachOutGetsNoPlans() async throws {
        let w = try await World()
        let tool = try await w.install(["network": true, "act": ["purpose": "to do things"]], name: "online")
        let reply = await w.ask(tool, "sidefolk/plan.approve", ["plan": w.morning])
        #expect(reply["reason"]?.stringValue == "not_contained")
    }

    @Test func thePersonEndsAPlanAndItAsksAgain() async throws {
        let w = try await World()
        let tool = try await w.install()
        _ = await w.allowMorning(tool)
        #expect(await w.h.host.info(id: "com.example.actor")?.plans.map(\.id) == ["morning"])
        let ended = await w.h.call(ExtensionPlanEndTool.name, ["extension": "com.example.actor", "plan": "morning"])
        #expect(ended.isOK)
        async let reply = w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "plan": "morning", "input": ["text": "Brief: x"]])
        #expect(await w.answerCard(.deny) != nil)
        _ = await reply
    }

    @Test func nobodyButThePersonEndsAPlanWithTheTool() async throws {
        let w = try await World()
        _ = try await w.install()
        let outcome = await w.h.env.executor.execute(name: ExtensionPlanEndTool.name, input: ["extension": "com.example.actor", "plan": "x"], caller: .extension(id: "com.example.actor"))
        #expect(!outcome.isOK)
    }

    // MARK: What a plan may leave open

    @Test func wordsAreFilledInOnlyWhereTheyStayInside() {
        func stands(_ name: String, _ input: JSONValue) -> Bool {
            ExtensionPlanRules.standing(tool: Probe(name: name, risk: .medium, capabilities: [], mutates: true), template: input)
        }
        #expect(stands("notes.save", ["text": "{{x}}"]))
        #expect(!stands("notes.save", ["text": "a", "collection": "{{x}}"]), "a selector stays written out")
        #expect(!stands("notes.save", ["text": "a", "remind": "{{x}}"]), "a time is parsed, so it stays written out")
        #expect(stands("reminders.create", ["title": "{{x}}", "when": "tomorrow"]))
        #expect(!stands("reminders.create", ["title": "x", "when": "{{x}}"]))
        #expect(stands("web.fetch", ["url": "https://example.com"]))
        #expect(!stands("web.fetch", ["url": "https://example.com/{{x}}"]))
        #expect(!stands("ext.other.translate", ["text": "{{x}}"]), "another extension's tool takes no filled-in words")
        #expect(stands("ext.other.translate", ["text": "hello"]))
        #expect(!stands("clipboard.read", [:]))
        #expect(!ExtensionPlanRules.standing(tool: Probe(name: "x", risk: .high, capabilities: [], mutates: true), template: .object([:])))
    }

    @Test func aFilledInValueKeepsTheWrittenParts() {
        #expect(ExtensionPlanRules.fits("Brief: rain", template: "Brief: {{x}}"))
        #expect(!ExtensionPlanRules.fits("Rain", template: "Brief: {{x}}"))
        #expect(ExtensionPlanRules.fits("a1b2c", template: "a{{x}}b{{y}}c"))
        #expect(!ExtensionPlanRules.fits("a1c2b", template: "a{{x}}b{{y}}cd"))
        #expect(ExtensionPlanRules.fits("same", template: "same"))
        let t: JSONValue = ["text": "n: {{x}}", "kind": "task"]
        #expect(ExtensionPlanRules.matches(["text": "n: y", "kind": "task"], template: t, fillable: ["text"]))
        #expect(!ExtensionPlanRules.matches(["text": "n: y", "kind": "note"], template: t, fillable: ["text"]))
        #expect(!ExtensionPlanRules.matches(["text": "n: y"], template: t, fillable: ["text"]))
        #expect(!ExtensionPlanRules.matches(["text": "n: y", "kind": "task"], template: t, fillable: []))
    }

    @Test func theInstallSheetSaysWhatItCanDoAndNothingFalse() {
        let summary = PermissionSummary.forExtension(ExtensionPermissions(act: ExtensionPurpose(purpose: "to run flows")))
        #expect(summary.lines.contains { $0.kind == .act && $0.caution && $0.text.contains("to run flows") })
        #expect(summary.texts.contains("No access of its own to your files or the internet"))
        #expect(!summary.texts.contains("No access to your files or the internet"))
        #expect(ExtensionPermissions(act: ExtensionPurpose(purpose: "x")).widens(ExtensionPermissions()), "gaining it holds the update for a look")
        let online = PermissionSummary.forExtension(ExtensionPermissions(network: true, act: ExtensionPurpose(purpose: "to x")))
        #expect(online.warnings.contains { $0.contains("every use asks you") })
    }

    @Test func aWatchItMadeTellsItAndNotThePerson() async throws {
        let env = try TestEnv()
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        let engine = WatcherEngine(store: WatcherStore(env.db), attention: attention, events: env.events, clock: env.clock, opener: { _ in })
        let stream = env.events.stream()
        let watcher = Watcher(kind: "url_change", title: "Page", config: .object([:]), condition: .object([:]), intervalS: 300, mode: .repeat,
                              source: "extension:com.example.actor", now: env.clock.now)
        await engine.announce(watcher, ProbeResult(state: .null, triggered: true, summary: "It changed"))
        var heard = false
        for await event in stream {
            if case .watchFired(let id, let watch, _, let summary) = event {
                #expect(id == "com.example.actor")
                #expect(watch == watcher.id)
                #expect(summary == "It changed")
                heard = true
                break
            }
        }
        #expect(heard)
        #expect(await attention.open().isEmpty, "it tells the person in its own way")
    }

    // MARK: Tools other agents may use (D112)

    private func agentWorld(access: AgentAccess = AgentAccess()) throws -> (TestEnv, ExternalToolGateway) {
        let env = try TestEnv()
        for (name, forAgents) in [("ext.flows.list", true), ("ext.flows.secret", false)] {
            env.registry.register(ExtensionTool(spec: ToolSpec(name: name, title: name, description: "", inputSchema: Schema.object([:]), risk: .low, capabilities: [.extensions], category: .extensions, mutates: false),
                                                extensionId: "com.example.flows", extensionName: "Flows", remoteName: "list", forAgents: forAgents) { _, _ in ToolResult(text: "listed", untrusted: true) })
        }
        return (env, ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events, access: { access }))
    }

    @Test func anAgentSeesOnlyWhatAnExtensionMarkedAndIsAskedEveryTime() async throws {
        let (env, gateway) = try agentWorld()
        #expect(gateway.specs().map(\.name) == ["ext.flows.list"])
        #expect(gateway.specs().first?.risk == .medium, "low in its manifest, it still asks")
        let refused = await gateway.call("ext.flows.secret", input: .object([:]), client: "claude-code")
        #expect(!refused.isOK)
        let answering = env.autoAnswer(.allowOnce)
        let outcome = await gateway.call("ext.flows.list", input: .object([:]), client: "claude-code")
        #expect(outcome.isOK)
        let card = await answering.value
        #expect(card?.canAlways == false)
    }

    @Test func thePersonTurnsThemOffAndAllowNeverSticks() async throws {
        var off = AgentAccess()
        off.extensions = .off
        let (_, gateway) = try agentWorld(access: off)
        #expect(gateway.specs().isEmpty)
        #expect(await gateway.call("ext.flows.list", input: .object([:]), client: "claude-code").isOK == false)
        let saved = try JSONDecoder().decode(AgentAccess.self, from: Data(#"{"extensions":"allow"}"#.utf8))
        #expect(saved.extensions == .ask, "Allow isn't a choice for them, however it got saved")
    }

    // MARK: What a code review found (T43)

    @Test func writtenMeansTheSameBytes() {
        let two: JSONValue = ["url": "https://example.com/caf\u{e9}"], other: JSONValue = ["url": "https://example.com/cafe\u{301}"]
        #expect(ExtensionPlanRules.matches(two, template: two, fillable: []))
        #expect(!ExtensionPlanRules.matches(other, template: two, fillable: []), "canonically equal isn't the same address")
        #expect(!ExtensionPlanRules.fits("cafe\u{301}: x", template: "caf\u{e9}: {{a}}"))
        #expect(ExtensionPlanRules.fits("caf\u{e9}: x", template: "caf\u{e9}: {{a}}"))
        #expect(ExtensionPlanRules.fits("a x b y c", template: "a {{p}} b {{q}} c"))
        #expect(!ExtensionPlanRules.fits("a x c", template: "a {{p}} b {{q}} c"))
        #expect(!ExtensionPlanRules.fits("ab", template: "ab{{p}}b"), "the written parts can't overlap")
    }

    @Test func whatTheCardCantShowCantStand() {
        let probe = Probe(name: "web.fetch", risk: .medium, capabilities: [.network], mutates: false)
        #expect(ExtensionPlanRules.standing(tool: probe, template: ["url": "https://example.com"]))
        #expect(!ExtensionPlanRules.standing(tool: probe, template: ["url": "https://example.com/\u{200B}x"]), "hidden characters")
        #expect(!ExtensionPlanRules.standing(tool: probe, template: ["url": .string(String(repeating: "x", count: 400))]), "past where the card stops")
        #expect(!ExtensionPlanRules.standing(tool: probe, template: ["nested": ["a": .string(String(repeating: "x", count: 400))]]))
    }

    @Test func oneCardForAPlanAtATime() async throws {
        let w = try await World()
        let tool = try await w.install()
        async let first = w.ask(tool, "sidefolk/plan.approve", ["plan": w.morning])
        while await w.h.env.broker.pending().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        // The program's own second notice, while the first card is up (the bridge above waits for one answer at a time).
        await w.h.host.handleAction("com.example.actor", method: "sidefolk/plan.approve", params: ["request": .string(UUID().uuidString),
            "plan": ["id": "other", "title": "Other", "steps": [["tool": "web.fetch", "input": ["url": "https://example.com"]]]]])
        #expect(await w.h.env.broker.pending().count == 1, "what's saved is what the person read")
        _ = await w.answerCard(.allowOnce)
        #expect(await first["ok"]?.boolValue == true)
        #expect(await w.h.host.info(id: "com.example.actor")?.plans.map(\.id) == ["morning"])
    }

    @Test func thePlansBudgetHoldsAcrossABurst() async throws {
        let w = try await World()
        let tool = try await w.install()
        async let answer = w.ask(tool, "sidefolk/plan.approve", ["plan": ["id": "one", "title": "One", "per_day": 1, "steps": [["tool": "notes.save", "input": ["text": "x"]]]]])
        _ = await w.answerCard(.allowOnce)
        #expect(await answer["ok"]?.boolValue == true)
        #expect(await w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "plan": "one", "input": ["text": "x"]])["standing"]?.boolValue == true)
        async let over = w.ask(tool, "sidefolk/tools.call", ["tool": "notes.save", "plan": "one", "input": ["text": "x"]])
        #expect(await w.answerCard(.deny) != nil, "past its budget it asks")
        _ = await over
    }

    @Test func aPlanThatEndsByItselfIsListedToo() async throws {
        let w = try await World()
        let tool = try await w.install()
        async let answer = w.ask(tool, "sidefolk/plan.approve", ["plan": ["id": "soon", "title": "Soon", "ttl": 600, "steps": [["tool": "notes.save", "input": ["text": "x"]]]]])
        _ = await w.answerCard(.allowOnce)
        _ = await answer
        #expect(await w.h.host.info(id: "com.example.actor")?.plans.first?.expiresAt != nil)
    }

    @Test func aNoticeSaysWhoItIsFrom() async throws {
        let env = try TestEnv()
        let store = AttentionStore(env.db), attention = AttentionCenter(store: store, events: env.events, clock: env.clock)
        env.registry.register(AgentFacingTools.make(attention: attention))
        AgentFacingTools.extensionNames.withLock { $0 = { _ in "Actor" } }
        defer { AgentFacingTools.extensionNames.withLock { $0 = nil } }
        let out = await env.executor.execute(name: "notify.user", input: ["title": "Sidefolk needs you"], caller: .extension(id: "com.example.actor"))
        #expect(out.isOK)
        #expect((try await store.recent()).first?.title == "Actor: Sidefolk needs you")
    }

    @Test func removingItRemovesItsWatches() async throws {
        let gone = Gone()
        let h = try HostEnv { $0.forgetWatches = { id in await gone.add(id) } }
        let manifest: JSONValue = ["id": "com.example.w", "name": "W", "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]]]
        try await h.host.install(from: h.source("w", manifest: manifest))
        try await h.host.uninstall(id: "com.example.w")
        #expect(await gone.ids == ["com.example.w"])
    }

    actor Gone {
        var ids: [String] = []
        func add(_ id: String) { ids.append(id) }
    }
}
