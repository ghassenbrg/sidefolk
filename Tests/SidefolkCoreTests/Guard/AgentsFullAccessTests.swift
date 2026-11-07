import Foundation
import Testing
@testable import SidefolkCore

/// "Also let other apps act without asking" (D240, SECURITY T70): the person's own choice, in the Full access sheet, off unless made there, only in Full access and only until it
/// ends. What Guard holds for every caller holds with it.
@Suite struct AgentsFullAccessTests {
    private func cards(_ env: TestEnv) -> (CallCounter, Task<Void, Never>) {
        let counter = CallCounter()
        let stream = env.events.stream()
        let broker = env.broker
        return (counter, Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                counter.bump()
                await broker.resolve(id: r.id, decision: .deny)
            }
        })
    }

    private static func fullWithAgents() -> GuardPolicy {
        var policy = GuardPolicy()
        policy.choose(.fullAccess, agentsToo: true)
        return policy
    }

    // MARK: The flag

    @Test func theFlagIsOffByDefaultAndMeansSomethingOnlyInFullAccess() {
        #expect(!GuardPolicy().agentsFullAccess && !GuardPolicy().agentsMayActFreely)
        var policy = GuardPolicy(mode: .auto)
        policy.agentsFullAccess = true
        #expect(!policy.agentsMayActFreely, "a stale flag does nothing outside Full access")
        for mode in GuardMode.allCases where mode != .fullAccess {
            policy.mode = mode
            #expect(policy.mode(for: .external(client: "codex")) == (mode == .askEveryTime ? .askEveryTime : .askOncePerKind), "\(mode)")
        }
        let full = Self.fullWithAgents()
        #expect(full.agentsMayActFreely && full.mode(for: .external(client: "codex")) == .fullAccess)
        // Nobody else gains from it: a routine, an extension and the person's own call keep what they had.
        for caller in [Caller.routine(id: "r"), .extension(id: "x"), .user] {
            #expect(full.mode(for: caller) == (Caller.agent(runId: "r") == caller ? .fullAccess : .askOncePerKind), "\(caller)")
        }
        var plain = GuardPolicy()
        plain.choose(.fullAccess)
        #expect(plain.mode(for: .external(client: "codex")) == .askOncePerKind, "Full access alone is not for other apps")
    }

    @Test func theFlagEndsWithFullAccessAndIsNeverKeptForTheNextTime() {
        var policy = Self.fullWithAgents()
        policy.fullAccessEnds = Date().addingTimeInterval(60)
        #expect(policy.current(at: Date().addingTimeInterval(120)).agentsFullAccess == false, "its end ends it")
        policy.endFullAccess()
        #expect(!policy.agentsFullAccess && !policy.agentsMayActFreely)
        var again = Self.fullWithAgents()
        again.choose(.auto)
        #expect(!again.agentsFullAccess, "another mode forgets it")
        again.choose(.fullAccess)
        #expect(!again.agentsFullAccess, "turning Full access on again starts from the sheet's choice, off")
    }

    @Test func aPolicySavedBeforeOrWithAnUnreadableValueReadsAsOff() throws {
        let old = try JSONDecoder().decode(GuardPolicy.self, from: Data(#"{"mode":"fullAccess"}"#.utf8))
        #expect(!old.agentsFullAccess)
        let odd = try JSONDecoder().decode(GuardPolicy.self, from: Data(#"{"mode":"fullAccess","agentsFullAccess":"yes"}"#.utf8))
        #expect(!odd.agentsFullAccess && !odd.agentsMayActFreely)
        let on = try JSONDecoder().decode(GuardPolicy.self, from: JSONEncoder().encode(Self.fullWithAgents()))
        #expect(on.agentsMayActFreely, "what the person chose is kept while it lasts")
    }

    // MARK: Guard

    @Test func anotherAgentsCallAsksInEveryModeAndRunsOnlyInFullAccessWithTheSwitch() async throws {
        var staleFlag = GuardPolicy(mode: .auto)
        staleFlag.agentsFullAccess = true
        var fullOnly = GuardPolicy()
        fullOnly.choose(.fullAccess)
        let asking: [(String, GuardPolicy)] = [("Ask every time", GuardPolicy(mode: .askEveryTime)), ("Ask once", GuardPolicy(mode: .askOncePerKind)), ("Auto", GuardPolicy(mode: .auto)),
                                               ("Full access", fullOnly), ("a flag with no Full access", staleFlag)]
        for (name, policy) in asking {
            let env = try TestEnv()
            env.registry.register(ProbeTool(name: "notes.update", risk: .medium, capabilities: [.notebook]))
            try await env.permissions.setPolicy(policy)
            let (counter, listener) = cards(env)
            defer { listener.cancel() }
            let out = await env.executor.execute(name: "notes.update", input: ["x": "a"], caller: .external(client: "codex"), tainted: true)
            guard case .denied = out.status else { Issue.record("\(name): another agent's call asks: \(out.status)"); continue }
            #expect(counter.value == 1, "\(name): one card")
        }
        // The person's choice: no card, and the row says Full access and who asked.
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "notes.update", risk: .medium, capabilities: [.notebook]))
        try await env.permissions.setPolicy(Self.fullWithAgents())
        let (counter, listener) = cards(env)
        defer { listener.cancel() }
        let out = await env.executor.execute(name: "notes.update", input: ["x": "a"], caller: .external(client: "codex"), tainted: true)
        guard case .ok = out.status else { Issue.record("with the switch it runs: \(out.status)"); return }
        #expect(counter.value == 0)
        let row = try await env.activity.recent().first
        #expect(row?.decision == .fullAccess && row?.caller == "external:codex", "who asked is on the row: \(String(describing: row))")
        // And once the switch is off, it asks again at once.
        try await env.permissions.updatePolicy { $0.agentsFullAccess = false }
        let after = await env.executor.execute(name: "notes.update", input: ["x": "a"], caller: .external(client: "codex"), tainted: true)
        guard case .denied = after.status else { Issue.record("off again: \(after.status)"); return }
        #expect(counter.value == 1)
    }

    @Test func whatHoldsForEveryCallerHoldsForAgentsWithTheSwitch() async throws {
        let home = NSHomeDirectory()
        let cases: [(String, ProbeTool, Bool)] = [
            ("text to read in full", ProbeTool(name: "skills.save", risk: .medium, capabilities: [.notebook], scope: { _ in ToolScope(text: "a skill") }), true),
            ("an unshared folder", ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite], scope: { _ in ToolScope(writePaths: ["\(home)/sf-agents-\(UUID().uuidString)/a.txt"]) }), false),
            ("a protected place", ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite], scope: { _ in ToolScope(writePaths: ["\(home)/.ssh/authorized_keys"]) }), false),
        ]
        for (name, tool, asksOnACard) in cases {
            let env = try TestEnv()
            env.registry.register(tool)
            try await env.permissions.setPolicy(Self.fullWithAgents())
            let (counter, listener) = cards(env)
            defer { listener.cancel() }
            let out = await env.executor.execute(name: tool.spec.name, input: ["x": "a"], caller: .external(client: "codex"), tainted: true)
            guard case .denied = out.status else { Issue.record("\(name): still refused or asked: \(out.status)"); continue }
            #expect(counter.value == (asksOnACard ? 1 : 0), "\(name): \(counter.value)")
        }
        // What the person turned off stays off.
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "notes.update", risk: .medium, capabilities: [.notebook]))
        var policy = Self.fullWithAgents()
        policy.disabled = [.notebook]
        try await env.permissions.setPolicy(policy)
        let out = await env.executor.execute(name: "notes.update", input: ["x": "a"], caller: .external(client: "codex"), tainted: true)
        guard case .denied = out.status else { Issue.record("a capability switched off stays off: \(out.status)"); return }
    }
}
