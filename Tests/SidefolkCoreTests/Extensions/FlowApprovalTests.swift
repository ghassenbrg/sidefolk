import Foundation
@testable import SidefolkCore
import Synchronization
import Testing

/// One approval for a flow (D186–D189, T53): the plan the person read covers what an edit leaves alone, asks only about what is new, and Full access
/// answers a signed extension's plan for the person's own click. Server calls stand when named and checked. Words from outside never choose where a
/// call goes or what it runs.
@Suite struct FlowApprovalTests {
    final class World: @unchecked Sendable {
        let h: HostEnv
        let gateway: ExtensionActionGateway
        let external: ExternalToolGateway
        let tool: String

        init(origin: ExtensionOrigin? = .official, name: String = "flow") async throws {
            let env = try TestEnv()
            let gateway = ExtensionActionGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events)
            self.gateway = gateway
            let permissions = env.permissions, clock = env.clock
            h = try HostEnv(env: env) {
                $0.actions = gateway
                $0.flowPolicy = {
                    let policy = try? await permissions.policy(now: clock.now)
                    return ExtensionHost.FlowPolicy(policy: policy)
                }
                $0.askEachTimeOnline = { (try? await permissions.policy(now: clock.now))?.internet == .askEachTime }
            }
            for (name, risk, caps, mutates) in [("notes.save", Risk.low, Set<Capability>([.notebook]), true), ("notes.search", .low, [.notebook], false),
                                                ("notify.user", .low, [], false), ("ask.user", .low, [], false), ("web.fetch", .low, [.network], false), ("watch.create", .low, [.watch, .network, .filesRead], true), ("reminders.create", .low, [.time], true), ("applenotes.copy", .medium, [.macApps, .notebook], true),
                                                ("files.read", .low, [.filesRead], false), ("clipboard.read", .low, [.clipboard], false), ("applenotes.read", .low, [.macApps], false),
                                                ("calendar.today", .low, [.calendar], false), ("voice.say", .low, [], true), ("files.trash", .high, [.filesWrite], true)] {
                h.env.registry.register(ExtensionActionsTests.Probe(name: name, risk: risk, capabilities: caps, mutates: mutates, urlParameter: name == "web.fetch" ? "url" : nil))
            }
            h.env.registry.register(ExtensionPlanEndTool(host: h.host))
            h.env.registry.register(PlanCodeTool(host: h.host))
            external = ExternalToolGateway(registry: h.env.registry, permissions: permissions, broker: h.env.broker, activity: h.env.activity, events: h.env.events)
            let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name.capitalized), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                       "permissions": ["act": ["purpose": "to run what you set up"]], "tools": ["ask_host": ["title": "Ask the host", "risk": "low", "mutates": false]]]
            try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": ExtensionActionsTests.bridge]), origin: origin)
            tool = "ext.\(name).ask_host"
        }

        func setMode(_ mode: GuardMode) async throws { try await h.env.permissions.updatePolicy { $0.mode = mode } }

        /// The way a real agent comes: through the external gateway, with the facade, the external spec and the rows it writes.
        func confirmThroughTheGateway(_ code: String, as client: String = "Claude Code") async -> (ok: Bool, text: String) {
            let outcome = await external.call(PlanCodeTool.name, input: ["code": .string(code)], client: client)
            switch outcome.status {
            case .ok(let result): return (!result.isError, result.text)
            case .denied(let why): return (false, why)
            case .failed(let error): return (false, "\(error)")
            default: return (false, "\(outcome.status)")
            }
        }

        /// An agent gives a code (`plans.approve_with_code`): whether it worked, and what the agent is told.
        func confirm(_ code: String, as client: String = "Claude Code", caller: Caller? = nil) async -> (ok: Bool, text: String) {
            let outcome = await h.env.executor.execute(name: PlanCodeTool.name, input: ["code": .string(code)], caller: caller ?? .external(client: client), timeout: 10)
            switch outcome.status {
            case .ok(let result): return (!result.isError, result.text)
            case .denied(let why): return (false, why)
            case .failed(let error): return (false, "\(error)")
            default: return (false, "\(outcome.status)")
            }
        }

        func ask(_ method: String, _ params: JSONValue = .object([:]), caller: Caller = .user) async -> JSONValue {
            let outcome = await h.env.executor.execute(name: tool, input: ["method": .string(method), "params": params], caller: caller, timeout: 30)
            guard case .ok(let r) = outcome.status, let json = try? JSONValue.parse(Data(r.text.utf8)) else { return .null }
            return json
        }

        /// The next card, answered, or nil when none came.
        func answerCard(_ decision: ApprovalDecision, wait: Int = 200) async -> ApprovalRequest? {
            for _ in 0..<wait {
                if let card = await h.env.broker.pending().first {
                    await h.env.broker.resolve(id: card.id, decision: decision)
                    return card
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return nil
        }

        /// Approves `plan`, answering its card yes if there is one. Returns the reply and whether a card came.
        func approve(_ plan: JSONValue, caller: Caller = .user) async -> (reply: JSONValue, asked: Bool) {
            // Answers a card whenever one comes, until the reply is in: a card that comes late is still seen, and "no card" means none came.
            let done = Mutex(false)
            let reply = Task { () -> JSONValue in
                let answer = await ask("sidefolk/plan.approve", ["plan": plan], caller: caller)
                done.withLock { $0 = true }
                return answer
            }
            var asked = false
            while !done.withLock({ $0 }) {
                if let card = await h.env.broker.pending().first {
                    await h.env.broker.resolve(id: card.id, decision: .allowOnce)
                    asked = true
                } else {
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            return (await reply.value, asked)
        }

        func check(_ plan: JSONValue) async -> JSONValue { await ask("sidefolk/plan.check", ["plan": plan]) }

        func rows(_ tool: String) async throws -> [ActivityEntry] { try await h.env.activity.recent(limit: 10, tool: tool) }
    }

    static func plan(_ steps: [JSONValue], id: String = "digest", when: String = "Every Monday", perDay: Int = 200, perRun: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id), "title": "Digest", "when": .string(when), "per_day": .number(Double(perDay)), "steps": .array(steps)]
        if let perRun { fields["per_run"] = .number(Double(perRun)) }
        return .object(fields)
    }

    static let save: JSONValue = ["tool": "notes.save", "input": ["text": "Digest: {{digest}}"]]
    static let fetch: JSONValue = ["tool": "web.fetch", "input": ["url": "https://news.example.com/feed"]]

    // MARK: One card, and an edit that adds nothing asks nothing

    @Test func theSamePlanAgainAsksNothingAndHistoryHasTheRow() async throws {
        let w = try await World()
        let first = await w.approve(Self.plan([Self.save, Self.fetch]))
        #expect(first.asked && first.reply["ok"]?.boolValue == true)
        let again = await w.approve(Self.plan([Self.save, Self.fetch]))
        #expect(!again.asked, "nothing is new")
        #expect(again.reply["ok"]?.boolValue == true && again.reply["silent"]?.boolValue == true && again.reply["new"]?.intValue == 0)
        let row = try await w.rows("extensions.plan").first
        #expect(row?.decision == .plan, "History still has what was allowed")
    }

    @Test func wordsChangedWhereTheyStayInsideAndAStepTakenOutAskNothing() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save, Self.fetch]))
        let edited = await w.approve(Self.plan([["tool": "notes.save", "input": ["text": "A better digest: {{digest}}"]]]))
        #expect(!edited.asked, "a note's words may change, and a step may go")
        #expect(edited.reply["silent"]?.boolValue == true)
    }

    @Test func aNewLineAsksWithOnlyWhatIsNew() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save, Self.fetch]))
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save, Self.fetch, ["tool": "web.fetch", "input": ["url": "https://other.example.com"]]])])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card, read in full"); return }
        #expect(words.contains("https://other.example.com"))
        #expect(!words.contains("news.example.com"), "what they read before isn't shown again: \(words)")
        #expect(words.contains("Lines already allowed, unchanged: 2"), "\(words)")
        #expect(await reply["new"]?.intValue == 1)
    }

    @Test func aFixedValueChangedInAFieldOutsideTheTableIsNew() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.fetch]))
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([["tool": "web.fetch", "input": ["url": "https://news.example.com/other"]]])])
        #expect(await w.answerCard(.deny) != nil)
        #expect(await reply["ok"]?.boolValue == false)
    }

    @Test func widerTermsAskAgain() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save], perDay: 100))
        #expect(await !w.approve(Self.plan([Self.save], perDay: 50)).asked, "fewer actions is narrower")
        async let more = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save], perDay: 500)])
        #expect(await w.answerCard(.deny) != nil, "more actions a day is something to read")
        _ = await more
        async let when = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save], when: "Every minute", perDay: 50)])
        #expect(await w.answerCard(.deny) != nil, "so is another way of starting")
        _ = await when
    }

    @Test func anAiStepAndASetOffFlowCountAsNewWhenAddedButNotAgain() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let ai: JSONValue = ["kind": "ai", "as": "write", "reads": ["digest"]]
        async let added = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save, ai])])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("goes to your AI"), "\(words)")
        _ = await added
        #expect(await !w.approve(Self.plan([Self.save, ai])).asked)
        let flow: JSONValue = ["kind": "flow", "name": "Morning brief"]
        async let set = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save, ai, flow])])
        let second = await w.answerCard(.allowOnce)
        guard case .text(let setWords)? = second?.details else { Issue.record("a card"); return }
        #expect(setWords.contains("Morning brief”, which keeps its own approval"), "\(setWords)")
        _ = await set
        #expect(await !w.approve(Self.plan([Self.save, flow])).asked, "taking the AI step out asks nothing")
    }

    @Test func aPlanSavedBeforeProvidersAndNamesAsksOnceForWhatItCantPlace() {
        let old = ExtensionPlan.Step(tool: "ext.x.y", input: ["a": "b"], definition: "d", reach: "r", standing: true)
        let now = ExtensionPlan.Step(tool: "ext.x.y", input: ["a": "b"], definition: "d", reach: "r", standing: true, provider: "p")
        #expect(!ExtensionPlanRules.covers(old, now), "no provider kept: it can't be told who the person read")
        let builtIn = ExtensionPlan.Step(tool: "notes.save", input: ["text": "x"], definition: "d", reach: "r", standing: true, provider: "")
        let builtInBefore = ExtensionPlan.Step(tool: "notes.save", input: ["text": "y"], definition: "d", reach: "r", standing: true)
        #expect(ExtensionPlanRules.covers(builtInBefore, builtIn), "Sidefolk's own tools carry on, the open field's words aside")
    }

    @Test func coverageNeverGrowsWhatStoodUnderAnotherMode() {
        func step(_ full: Bool, source: String = "inside") -> ExtensionPlan.Step {
            ExtensionPlan.Step(tool: "ext.x.y", input: ["to": "{{a}}"], definition: "d", reach: "r", standing: true, provider: "p", sources: ["to": source], fullAccessOnly: full ? true : nil)
        }
        #expect(ExtensionPlanRules.covers(step(false), step(true)), "narrower: it stands in fewer places")
        #expect(!ExtensionPlanRules.covers(step(true), step(false)), "wider: it stood only in Full access")
        #expect(!ExtensionPlanRules.covers(step(false, source: "inside"), step(false, source: "outside")), "a value coming from further out is new")
        #expect(ExtensionPlanRules.covers(step(false, source: "outside"), step(false, source: "inside")))
    }

    // MARK: plan.check

    @Test func planCheckSaysWhatWouldStandAndWhatIsNewWithNoCard() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let steps: [JSONValue] = [Self.save, Self.fetch, ["tool": "watch.create", "input": ["interval_minutes": "{{n}}"]], ["kind": "ai"]]
        let checked = await w.check(Self.plan(steps))
        #expect(checked["ok"]?.boolValue == true)
        let states = checked["steps"]?.arrayValue?.compactMap { $0["state"]?.stringValue }
        #expect(states == ["stands", "stands", "stands_in_full_access", "listed"], "\(checked)")
        #expect(checked["steps"]?.arrayValue?[2]["why"]?.stringValue == "reach_field")
        #expect(checked["new"]?.arrayValue?.compactMap(\.intValue) == [1, 2, 3])
        #expect(checked["silent"]?.boolValue == false)
        #expect(await w.h.env.broker.pending().isEmpty, "no card")
        #expect(await w.check(Self.plan([Self.save]))["silent"]?.boolValue == true)
    }

    // MARK: Modes

    @Test func fullAccessAnswersASignedPlanForThePersonsOwnClick() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        let first = await w.approve(Self.plan([Self.save, Self.fetch]))
        #expect(!first.asked && first.reply["ok"]?.boolValue == true, "their click is the approval")
        #expect(try await w.rows("extensions.plan").first?.decision == .fullAccessPlan, "History says Full access answered it and nobody read it")
    }

    @Test func fullAccessNeverAnswersForAnAgentOrAnUnsignedExtension() async throws {
        let signed = try await World()
        try await signed.setMode(.fullAccess)
        let steered = await signed.approve(Self.plan([Self.save]), caller: .agent(runId: "r1"))
        #expect(steered.asked, "a turn of Sidefolk's own agent is not the person's hand")
        let clicked = await signed.approve(Self.plan([Self.save], id: "mine"))
        #expect(!clicked.asked, "their own click is")
        let after = await signed.approve(Self.plan([Self.save], id: "later"), caller: .agent(runId: "r2"))
        #expect(after.asked, "and it was used up: the next one without a click asks")
        let other = try await World(origin: nil, name: "stranger")
        try await other.setMode(.fullAccess)
        #expect(await other.approve(Self.plan([Self.save])).asked, "another's program is untrusted (T44)")
    }

    @Test func askEveryTimeShowsTheCardEvenForWhatIsCovered() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        try await w.setMode(.askEveryTime)
        #expect(await w.approve(Self.plan([Self.save])).asked)
    }

    @Test func autoSkipsTheCardForAnEditThatStaysInsideSidefolkOnly() async throws {
        let w = try await World()
        try await w.setMode(.auto)
        let first = await w.approve(Self.plan([Self.save]))
        #expect(first.asked, "the first time, the card")
        let inside = await w.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]]))
        #expect(!inside.asked && inside.reply["ok"]?.boolValue == true, "a notice stays in Sidefolk")
        let row = try await w.rows("extensions.plan").first
        #expect(row?.decision == .autoPlan, "History says Auto let it through unread, not that a plan was read")
        #expect(row?.args?["lines"]?.arrayValue?.contains { $0.stringValue?.contains("Done") == true } == true, "and names the line: \(String(describing: row?.args))")
        #expect(await w.approve(Self.plan([Self.save, Self.fetch])).asked, "an address leaves the Mac: the card")
    }

    @Test func whatStandsOnlyInFullAccessStopsWhenItEnds() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        let count: JSONValue = ["tool": "watch.create", "input": ["interval_minutes": "{{n}}"]]
        let approved = await w.approve(Self.plan([count]))
        #expect(approved.reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true])
        let call: JSONValue = ["tool": "watch.create", "plan": "digest", "input": ["interval_minutes": 5]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true, "a number fills a whole-slot field")
        try await w.setMode(.askOncePerKind)
        async let after = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.deny) != nil, "Full access ended: it asks again")
        #expect(await after["standing"]?.boolValue == false)
    }

    @Test func aWholeSlotTakesAnyValueOrNone() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        _ = await w.approve(Self.plan([["tool": "watch.create", "input": ["interval_minutes": "{{n}}", "title": "{{t}}"]]]))
        for input: JSONValue in [["interval_minutes": 5, "title": "x"], ["title": "x"], ["interval_minutes": .null, "title": ["a", "b"]], [:]] {
            let reply = await w.ask("sidefolk/tools.call", ["tool": "watch.create", "plan": "digest", "input": input])
            #expect(reply["standing"]?.boolValue == true, "\(input)")
        }
        async let extra = w.ask("sidefolk/tools.call", ["tool": "watch.create", "plan": "digest", "input": ["interval_minutes": 5, "title": "x", "kind": "y"]])
        #expect(await w.answerCard(.deny) != nil, "a key the plan didn't name asks")
        _ = await extra
    }

    // MARK: Server calls

    /// A server the person added, whose program is a copy of a real binary (so it can be checked), and a tool of it.
    func server(_ w: World, program: String? = nil) throws -> String {
        let path = program ?? w.h.root.appendingPathComponent("hub-server").path
        if program == nil { try? FileManager.default.copyItem(atPath: "/bin/ls", toPath: path) }
        let spec = ToolSpec(name: "ext.hub.post", title: "Create an issue", description: "", inputSchema: Schema.object([
            "repo": Schema.string("Repository"), "title": Schema.string("Title"), "body": Schema.string("Body"), "command": Schema.string("Command")]),
                            risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        w.h.env.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.hub", extensionName: "GitHub", remoteName: "post", program: path, sandboxed: false) { _, _ in
            ToolResult(text: "posted")
        })
        return path
    }

    static func post(_ fields: [String: JSONValue]) -> JSONValue {
        ["tool": "ext.hub.post", "as": "issue", "input": .object(["repo": "me/digest", "title": "Weekly digest"].merging(fields) { $1 })]
    }

    static let page: JSONValue = ["tool": "web.fetch", "as": "page", "title": "Read the page", "input": ["url": "https://news.example.com/feed"]]

    @Test func aNamedServerLineStandsAndTheCardSaysWhatItPassesOn() async throws {
        let w = try await World()
        _ = try server(w)
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.page, Self.post(["body": "{{page}}"])])])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("It sends out:") && words.contains("a server on this Mac, program "), "\(words)")
        #expect(words.contains("body: “[from “Read the page · web.fetch”; it may also be a list, a record, a number, or left out]”"), "\(words)")
        #expect(words.contains("Outside content: Words from “Read the page · web.fetch” go into body of “Create an issue”"), "\(words)")
        #expect(await reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true, true])
        let run = await w.ask("sidefolk/tools.call", ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "page words"]])
        #expect(run["standing"]?.boolValue == true && run["text"]?.stringValue == "posted", "\(run)")
        #expect(await w.h.env.broker.pending().isEmpty)
        let row = try await w.rows("ext.hub.post").first
        #expect(row?.args?["_filled_from"]?.arrayValue?.compactMap(\.stringValue) == ["outside content: body from step page"], "History says where the words came from: \(String(describing: row?.args))")
    }

    @Test func aServerWhoseProgramChangedAsksAgain() async throws {
        let w = try await World()
        let path = try server(w)
        _ = await w.approve(Self.plan([Self.post([:])]))
        let call: JSONValue = ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest"]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0, 1, 2, 3]))
        try handle.close()
        async let changed = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.deny) != nil, "the program the person read is gone")
        #expect(await changed["standing"]?.boolValue == false)
    }

    @Test func aServerThatCantBeCheckedAsksEveryTimeAndTheCardSaysWhyForThatLine() async throws {
        let dir = try ExtFixtures.tempDir("unpinned")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Each way a program can't be checked, with what the card says about that very line.
        func copy(_ name: String) throws -> String {
            let path = dir.appendingPathComponent(name).path
            try FileManager.default.copyItem(atPath: "/bin/ls", toPath: path)
            return path
        }
        let script = dir.appendingPathComponent("server.sh")
        try "#!/bin/sh\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let cases: [(program: String, check: ProgramPin.Result, says: String)] = [
            (try copy("npx"), .unchecked(.launcher), "it starts through a launcher, interpreter or build tool"),
            (try copy("make"), .unchecked(.launcher), "it starts through a launcher, interpreter or build tool"),
            ("/usr/bin/env", .unchecked(.launcher), "it starts through a launcher, interpreter or build tool"),
            (script.path, .unchecked(.script), "its program is a script, not a compiled program"),
            ("hub-server", .unchecked(.path), "its program is named without a full path"),
        ]
        for (program, check, says) in cases {
            #expect(ProgramPin.check(of: program) == check, "\(program)")
            let w = try await World()
            _ = try server(w, program: program)
            let checked = await w.check(Self.plan([Self.post([:])]))
            let step = checked["steps"]?.arrayValue?.first
            #expect(step?["state"]?.stringValue == "asks" && step?["why"]?.stringValue == "server_unpinned", "\(program): \(checked)")
            async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.post([:])])])
            let card = await w.answerCard(.allowOnce)
            guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
            #expect(words.contains(says), "\(program): \(words)")
            _ = await reply
        }
        let loads = try copy("hub-server")
        #expect(ProgramPin.check(of: loads, arguments: ["--root", dir.path]) == .unchecked(.loads))
        if case .pinned = ProgramPin.check(of: loads) {} else { Issue.record("a compiled program with nothing to load is pinned") }
    }

    @Test func wordsFromOutsideNeverChooseWhereACallGoesOrWhatItRuns() async throws {
        let w = try await World()
        _ = try server(w)
        func state(_ fields: [String: JSONValue]) async -> (state: String?, why: String?) {
            let checked = await w.check(Self.plan([Self.page, Self.post(fields)]))
            let step = checked["steps"]?.arrayValue?.last
            return (step?["state"]?.stringValue, step?["why"]?.stringValue)
        }
        #expect(await state(["body": "{{page}}"]).state == "stands", "free words may go in, as the card says")
        let reach = await state(["repo": "{{page}}"])
        #expect(reach.state == "stands_in_full_access" && reach.why == "reach_field", "where it goes: only in Full access")
        let code = await state(["command": "{{page}}"])
        #expect(code.state == "refused" && code.why == "code_field")
        try await w.setMode(.fullAccess)
        #expect(await state(["repo": "{{page}}"]).state == "stands")
        #expect(await state(["command": "{{page}}"]).state == "refused", "refused in every mode")
    }

    @Test func aPersonsOwnAnswerMayFillAPlaceButOutsideWordsMayNot() {
        let ask: [(name: String?, tool: String)] = [("who", "ask.user"), ("page", "web.fetch")]
        let inside = ExtensionPlanRules.sources(of: ["repo": "{{who}}", "body": "{{page}} and {{today}}", "title": "{{form.name}}"], earlier: ask, inside: ["form"])
        #expect(inside == ["repo": "inside", "body": "outside", "title": "claimed"], "the clock and a typed answer are inside; a signed extension's word is claimed")
        #expect(ExtensionPlanRules.sources(of: ["repo": "{{form.x}}"], earlier: ask, inside: [])["repo"] == "outside", "a name the host can't place is outside")
        #expect(ExtensionPlanRules.sources(of: ["repo": "{{x}}"], earlier: ask, inside: [], fromPerson: ["repo"])["repo"] == "claimed")
    }

    @Test func theSwitchTurnsOffPassingWhatItReadsOnToServers() async throws {
        let w = try await World()
        _ = try server(w)
        _ = await w.approve(Self.plan([Self.page, Self.post(["body": "{{page}}"])]))
        let call: JSONValue = ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "words"]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true)
        try await w.h.env.permissions.updatePolicy { $0.flowsMayPassToServers = false }
        async let off = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.deny) != nil, "the person said not to, and that holds for a plan already read")
        _ = await off
    }

    @Test func readingYourOwnThingsAndOutsideWordsThenSendingThemOnStandsWithAWarning() async throws {
        let w = try await World()
        _ = try server(w)
        let notes: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
        let plan = Self.plan([notes, Self.page, Self.post(["body": "{{page}}"])])
        let asked = await w.check(plan)
        let last = asked["steps"]?.arrayValue?.last
        #expect(last?["state"]?.stringValue == "stands" && last?["warning"]?.stringValue == "crossing", "it stands, and the editor can warn: \(asked)")
        async let reply = w.ask("sidefolk/plan.approve", ["plan": plan])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("reads things of yours and outside content") && words.contains("they go to GitHub"), "\(words)")
        _ = await reply
        // Drop one leg and there is nothing to warn of.
        #expect(await w.check(Self.plan([Self.page, Self.post(["body": "{{page}}"])]))["steps"]?.arrayValue?.last?["warning"] == nil)
        // The person's switch turns it back to asking.
        try await w.h.env.permissions.updatePolicy { $0.flowsMayPassToServers = false }
        #expect(await w.check(plan)["steps"]?.arrayValue?.last?["state"]?.stringValue == "asks")
        try await w.h.env.permissions.updatePolicy { $0.flowsMayPassToServers = true }
        // An AI step is a conduit: it counts as reading what it names, and everything before it when it names nothing.
        try await w.setMode(.askOncePerKind)
        let named: JSONValue = ["kind": "ai", "as": "write", "reads": ["page"]]
        #expect(await w.check(Self.plan([Self.page, named, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["state"]?.stringValue == "stands")
        let everything: JSONValue = ["kind": "ai", "as": "write"]
        #expect(await w.check(Self.plan([notes, Self.page, everything, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing")
        #expect(await w.check(Self.plan([Self.page, everything, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing",
                "no names: it may have read your own things too")
    }

    @Test func anotherExtensionsPlanNeverHoldsAServerLine() async throws {
        let w = try await World(origin: nil, name: "stranger")
        _ = try server(w)
        let checked = await w.check(Self.plan([Self.post([:])]))
        #expect(checked["steps"]?.arrayValue?.first?["state"]?.stringValue == "asks", "\(checked)")
    }


    // MARK: What the reads found (T53)

    @Test func aNameTwoStepsShareOrTheClocksNameIsNeverTakenForTheirs() async throws {
        let w = try await World()
        _ = try server(w)
        let fetchAsNow: JSONValue = ["tool": "web.fetch", "as": "now", "input": ["url": "https://news.example.com/feed"]]
        #expect(await w.check(Self.plan([fetchAsNow, Self.post(["repo": "{{now.x}}"])]))["reason"]?.stringValue == "unusable", "a step can't be called the clock")
        let ask: JSONValue = ["tool": "notify.user", "as": "q", "input": ["title": "x"]]
        let again: JSONValue = ["tool": "web.fetch", "as": "q", "input": ["url": "https://news.example.com/feed"]]
        #expect(await w.check(Self.plan([ask, again]))["reason"]?.stringValue == "unusable", "one name for two steps")
        let named = ExtensionPlanRules.sources(of: ["repo": "{{q.x}}"], earlier: [("q", "ask.user"), ("q", "web.fetch")], inside: [])
        #expect(named["repo"] == "outside", "even if one of them is a question")
    }

    @Test func aSignedExtensionsWordForTheMostIsBelievedExceptWhereCodeRuns() async throws {
        let w = try await World()
        _ = try server(w)
        func state(_ key: String) async -> String? {
            var step = Self.post([key: "{{form.x}}"])
            step = .object(["tool": "ext.hub.post", "as": "issue", "input": step["input"] ?? .null, "from": .object([key: "person"])])
            return await w.check(Self.plan([step]))["steps"]?.arrayValue?.first?["state"]?.stringValue
        }
        #expect(await state("body") == "stands")
        #expect(await state("repo") == "stands", "a place the person typed")
        #expect(await state("command") == "refused", "never where code runs")
    }

    @Test func fieldNamesAreReadAsWordsNotAsLetters() {
        for place in ["urls", "paths", "URLPath", "HTTPEndpoint", "url2", "targetUrl", "recipients_list", "chat_id", "attendees", "workspace"] {
            #expect(ExtensionPlanRules.fieldClass(place, schema: ["type": "string"]) == .other, "\(place)")
        }
        for code in ["command", "commands", "applescript", "osascript", "shellcommand", "runscript", "subcommand", "sql_statement", "SQLStatement", "args", "run_script", "jsCode"] {
            #expect(ExtensionPlanRules.fieldClass(code, schema: ["type": "string"]) == .code, "\(code)")
        }
        for text in ["body", "message", "issue_body", "title", "commentText"] {
            #expect(ExtensionPlanRules.fieldClass(text, schema: ["type": "string"]) == .freeText, "\(text)")
        }
        #expect(ExtensionPlanRules.fieldClass("body", schema: ["type": "string", "format": "uri"]) == .other, "the schema says it is an address")
        #expect(ExtensionPlanRules.fieldClass("body", schema: ["type": "string", "enum": ["a"]]) == .other)
        #expect(ExtensionPlanRules.fieldClass("body", schema: ["type": "object"]) == .other, "a value of any other kind may carry a place inside")
        #expect(ExtensionPlanRules.fieldClass("payload", schema: ["type": "string"]) == .other, "a name for words nobody reads is not free text")
    }

    @Test func aWholeObjectIsNeverFreeText() async throws {
        let w = try await World()
        let spec = ToolSpec(name: "ext.hub.request", title: "Send a request", description: "", inputSchema: Schema.object(["message": ["type": "object"]]),
                            risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        w.h.env.registry.register(ExtensionTool(spec: spec, extensionId: "com.example.hub", extensionName: "Hub", remoteName: "request") { _, _ in ToolResult(text: "") })
        let step: JSONValue = ["tool": "ext.hub.request", "input": ["message": "{{page}}"]]
        let state = await w.check(Self.plan([Self.page, step]))["steps"]?.arrayValue?.last?["state"]?.stringValue
        #expect(state == "stands_in_full_access", "a whole value can hold anything, nested places included")
    }

    @Test func whatTheCardShowsIsTheBytesThatRun() {
        for odd in ["a\u{00A0}b", "a\tb", "a\nb", "a  b", " a", "a ", "a\u{3000}b", "e\u{200D}vil", "a\u{200C}b"] {
            #expect(!ExtensionPlanRules.plain(odd), "\(odd.unicodeScalars.map { String($0.value, radix: 16) })")
        }
        #expect(ExtensionPlanRules.plain("Reports final") && ExtensionPlanRules.plain("👩‍💻 at work") && ExtensionPlanRules.plain("می‌خواهم"))
        #expect(!ExtensionPlanRules.plain("a" + String(repeating: "\u{0301}", count: 12)), "a pile of marks the card would cut")
        let line = ExtensionPlanWords.line(tool: ExtensionActionsTests.Probe(name: "notes.save", risk: .low, capabilities: [], mutates: true), template: ["tags": .null, "list": [], "id": "7"])
        #expect(line.contains("tags: nothing") && line.contains("list: an empty list"), "\(line)")
    }

    @Test func aCoveredReapprovalKeepsTheEndItHad() async throws {
        let w = try await World()
        var plan = Self.plan([Self.save]).objectValue ?? [:]
        plan["ttl"] = 600
        _ = await w.approve(.object(plan))
        let first = await w.h.host.info(id: "com.example.flow")?.plans.first?.expiresAt
        try await Task.sleep(for: .milliseconds(1100))
        #expect(await !w.approve(.object(plan)).asked)
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.first?.expiresAt == first, "asking again is not a new yes")
    }

    @Test func oneCardAtATimeEvenWhileTheFirstIsBeingWorkedOut() async throws {
        let w = try await World()
        await w.h.host.notePersonCall("com.example.flow", caller: .user, tainted: false)
        func ask(_ id: String) async {
            await w.h.host.handleAction("com.example.flow", method: "sidefolk/plan.approve", params: ["request": .string(id), "plan": Self.plan([Self.save, Self.fetch], id: id)])
        }
        async let one: Void = ask("one")
        async let two: Void = ask("two")
        _ = await (one, two)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await w.h.env.broker.pending().count == 1, "the second ask met the first's flag, not a second card")
        _ = await w.answerCard(.allowOnce)
        try await Task.sleep(for: .milliseconds(300))
        let plans = await w.h.host.info(id: "com.example.flow")?.plans.map(\.id)
        #expect(plans?.count == 1, "\(String(describing: plans))")
    }

    @Test func lookingIsBudgetedLikeCalling() async throws {
        let w = try await World()
        var busy = 0
        for _ in 0..<70 where await w.check(Self.plan([Self.save]))["reason"]?.stringValue == "busy" { busy += 1 }
        #expect(busy == 10, "70 looks in a minute: the first 60 are served and the other 10 are not: \(busy)")
        let huge = String(repeating: "a", count: 300_000)
        #expect(await w.check(Self.plan([["tool": "notes.save", "input": ["text": .string(huge)]]]))["ok"]?.boolValue == false)
    }

    @Test func aCommandSentToAnotherExtensionIsNotThePersonsClick() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        #expect(await w.approve(Self.plan([Self.save]), caller: .command(extensionId: "com.example.other")).asked)
        #expect(await !w.approve(Self.plan([Self.save], id: "own"), caller: .command(extensionId: "com.example.flow")).asked, "their own typed command to it is")
    }

    @Test func theCardShowsEveryWrittenNoticeAndSaysWhoseAndWhy() async throws {
        let w = try await World()
        let notices: [JSONValue] = [["tool": "notify.user", "input": ["title": "Backup done"]], ["tool": "notify.user", "input": ["title": "Your Mac is infected, call 555"]]]
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan(notices + [Self.save])])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("Backup done") && words.contains("infected"), "each written notice shows: \(words)")
        #expect(words.contains("It tells or asks you:"), "a notice isn't a read: \(words)")
        _ = await reply
        try await w.setMode(.askEveryTime)
        async let again = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save], id: "fresh")])
        let second = await w.answerCard(.allowOnce)
        guard case .text(let askWords)? = second?.details else { Issue.record("a card"); return }
        #expect(askWords.contains("You asked to be asked every time") && !askWords.contains("won't ask again"), "\(askWords)")
        _ = await again
    }

    @Test func aLineThatStandsOnlyInFullAccessSaysSoWhereItAsks() async throws {
        let w = try await World()
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.page, ["tool": "watch.create", "input": ["interval_minutes": "{{n}}"]]])])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("It will still ask you each time:") && words.contains("only while Full access is on"), "\(words)")
        _ = await reply
    }

    @Test func wordsChangedFromWrittenToFilledInAreNew() {
        let before = ExtensionPlan.Step(tool: "notify.user", input: ["title": "Done"], definition: "d", reach: "r", standing: true, provider: "")
        let after = ExtensionPlan.Step(tool: "notify.user", input: ["title": "{{page}}"], definition: "d", reach: "r", standing: true, provider: "")
        #expect(!ExtensionPlanRules.covers(before, after), "what was written is now whatever a page says")
        #expect(ExtensionPlanRules.covers(after, before))
    }

    @Test func aServerProgramThatLoadsAFileOrIsAVersionedInterpreterCantBePinned() throws {
        let dir = try ExtFixtures.tempDir("pin")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ruby = dir.appendingPathComponent("ruby3.2").path
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: ruby)
        #expect(ProgramPin.hash(of: ruby) == nil, "a versioned interpreter")
        let plain = dir.appendingPathComponent("hub-server").path
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: plain)
        #expect(ProgramPin.hash(of: plain) != nil)
        #expect(ProgramPin.hash(of: plain, arguments: ["--flag", dir.path]) == nil, "it loads a folder, which the hash doesn't cover")
        #expect(ProgramPin.hash(of: plain, arguments: ["--port", "8080"]) != nil)
    }

    @Test func onlyAServersHighRiskToolMayStandAndOnlyForTheHostsOwnAnswer() {
        let engine = PermissionEngine()
        func decide(unsandboxed: Bool, name: String = "ext.hub.post", can: Set<Capability> = [.network, .extensions], mode: GuardMode = .askOncePerKind, standing: Bool = true) -> GuardDecision {
            let spec = ToolSpec(name: name, title: "t", description: "", inputSchema: .object([:]), risk: .high, capabilities: can, category: .extensions, mutates: true)
            return engine.evaluate(spec: spec, input: .object([:]), summary: "", scope: ToolScope(extensionId: "mcp.hub", unsandboxed: unsandboxed), caller: .extension(id: "com.x"), tainted: true,
                                   policy: GuardPolicy(mode: mode), grants: [], folders: [], standing: standing)
        }
        #expect(decide(unsandboxed: true) == .allow(.plan))
        for (label, answer) in [("sandboxed", decide(unsandboxed: false)), ("shell", decide(unsandboxed: true, can: [.shell])), ("not standing", decide(unsandboxed: true, standing: false)),
                                ("ask every time", decide(unsandboxed: true, mode: .askEveryTime))] {
            if case .ask = answer {} else { Issue.record("\(label) must ask: \(answer)") }
        }
    }

    @Test func aPlanAnswerOnAnyOtherToolOrInTheWrongModeIsIgnored() {
        let engine = PermissionEngine()
        func decide(name: String, answer: PlanAnswer, mode: GuardMode) -> GuardDecision {
            let spec = ToolSpec(name: name, title: "t", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.extensions], category: .extensions, mutates: true)
            return engine.evaluate(spec: spec, input: .object([:]), summary: "", scope: ToolScope(extensionId: "com.x", text: "words", planAnswer: answer), caller: .extension(id: "com.x"),
                                   tainted: false, policy: GuardPolicy(mode: mode), grants: [], folders: [])
        }
        #expect(decide(name: ExtensionPlanTool.name, answer: .fullAccess, mode: .fullAccess) == .allow(.fullAccessPlan))
        #expect(decide(name: ExtensionPlanTool.name, answer: .covered, mode: .askOncePerKind) == .allow(.plan))
        for (label, answer) in [("another tool", decide(name: "ext.x.y", answer: .fullAccess, mode: .fullAccess)), ("not Full access", decide(name: ExtensionPlanTool.name, answer: .fullAccess, mode: .auto)),
                                ("ask every time", decide(name: ExtensionPlanTool.name, answer: .covered, mode: .askEveryTime))] {
            if case .ask = answer {} else { Issue.record("\(label) must ask: \(answer)") }
        }
    }


    // MARK: Round three

    private func words(_ w: World, _ plan: JSONValue, answer: ApprovalDecision = .allowOnce, caller: Caller = .user) async -> (words: String?, reply: JSONValue) {
        async let reply = w.ask("sidefolk/plan.approve", ["plan": plan], caller: caller)
        let card = await w.answerCard(answer)
        guard case .text(let text)? = card?.details else { return (nil, await reply) }
        return (text, await reply)
    }

    @Test func anEditThatPointsTheSameWordsAtAnotherKindOfStepIsNewInEveryMode() async throws {
        for mode in [GuardMode.askOncePerKind, .auto] {
            let w = try await World(name: "rebind\(mode == .auto ? "a" : "o")")
            _ = try server(w)
            try await w.setMode(mode)
            let fetch: JSONValue = ["tool": "web.fetch", "as": "src", "input": ["url": "https://news.example.com/feed"]]
            let notes: JSONValue = ["tool": "notes.search", "as": "src", "input": ["query": "plans"]]
            let post: JSONValue = ["tool": "ext.hub.post", "input": ["repo": "me/digest", "title": "Digest", "body": "{{src}}"]]
            _ = await w.approve(Self.plan([fetch, post]))
            let edited = await words(w, Self.plan([notes, post]))
            #expect(edited.words?.contains("Create an issue") == true, "the Slack-like line is fed by something else now, so it shows: \(String(describing: edited.words)) in \(mode)")
            // An AI step that reads everything, with a private read added before it, is new too.
            let ai: JSONValue = ["kind": "ai", "as": "write"]
            _ = await w.approve(Self.plan([fetch, ai], id: "ai"))
            let other: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
            let more = await words(w, Self.plan([other, fetch, ai], id: "ai"))
            #expect(more.words != nil, "the AI step reads something it didn't: \(mode)")
        }
    }

    @Test func aPlanFullAccessAnsweredStandsOnlyWhileFullAccessIsOn() async throws {
        let w = try await World()
        _ = try server(w)
        try await w.setMode(.fullAccess)
        let plan = Self.plan([Self.page, Self.post(["body": "{{page}}"])])
        #expect(await !w.approve(plan).asked, "their click is the approval")
        let call: JSONValue = ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "words"]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true)
        try await w.setMode(.askOncePerKind)
        async let after = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.deny) != nil, "nobody read it: it asks once Full access has ended")
        _ = await after
        // Approving it again in this mode shows the whole card, once, and then it stands.
        let again = await words(w, plan)
        #expect(again.words?.contains("It sends out:") == true)
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true)
    }

    @Test func aNameWithADotOrABracketIsRefused() async throws {
        let w = try await World()
        let named: JSONValue = ["tool": "web.fetch", "as": "q.title", "input": ["url": "https://news.example.com/feed"]]
        #expect(await w.check(Self.plan([named]))["reason"]?.stringValue == "unusable")
        let third = try await World(origin: nil, name: "other")
        #expect(await third.check(Self.plan([["kind": "ai"]]))["reason"]?.stringValue == "unusable", "only a signed extension's word for what it does goes under Sidefolk's headings")
    }

    @Test func aFieldIsFreeTextOnlyWhenEveryWordOfItsNameIsAndTheSchemaSaysSo() {
        let string: JSONValue = ["type": "string"]
        for other in ["appName", "functionBody", "queryText", "name", "label", "shortcutName", "htmlBody"] {
            #expect(ExtensionPlanRules.fieldClass(other, schema: string) != .freeText, "\(other)")
        }
        #expect(ExtensionPlanRules.fieldClass("body", schema: nil) == .other, "a field no schema declares")
        #expect(ExtensionPlanRules.fieldClass("body", schema: ["type": "string", "$ref": "#/x"]) == .other)
        #expect(ExtensionPlanRules.fieldClass("long_description", schema: string) == .freeText && ExtensionPlanRules.fieldClass("messages", schema: string) == .freeText)
        #expect(ExtensionPlanRules.fieldClass("addresses", schema: string) == .other)
        #expect(ExtensionPlanRules.fieldClass("description", schema: string) == .freeText, "a description is words, though it holds the letters of `script`")
        for innocent in ["manuscript", "prescription", "subscription", "inscription", "descriptions", "transcripts"] {
            #expect(ExtensionPlanRules.fieldClass(innocent, schema: string) != .code, "\(innocent)")
        }
        for overlap in ["commandescription", "scriptranscript", "shellcommandescription"] {
            #expect(ExtensionPlanRules.fieldClass(overlap, schema: string) == .code, "a stem that overlaps an innocent word is still a stem: \(overlap)")
        }
        #expect(ExtensionPlanRules.fieldClass("transcript", schema: string) == .other && ExtensionPlanRules.fieldClass("transcript", schema: string) != .code, "nor is a transcript code")
    }

    @Test func anEditAnsweredWithoutACardInAutoKeepsTheEndThePlanHad() async throws {
        let w = try await World()
        try await w.setMode(.auto)
        var plan = Self.plan([Self.save]).objectValue ?? [:]
        plan["ttl"] = 600
        _ = await w.approve(.object(plan))
        let first = await w.h.host.info(id: "com.example.flow")?.plans.first?.expiresAt
        try await Task.sleep(for: .milliseconds(1100))
        plan["steps"] = .array([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])
        #expect(await !w.approve(.object(plan)).asked)
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.first?.expiresAt == first, "nothing was read, so nothing was renewed")
    }

    @Test func aProgramStartedWithAFlagPointingAtAFileCantBePinned() throws {
        let dir = try ExtFixtures.tempDir("pin2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("hub-server").path
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: plain)
        #expect(ProgramPin.hash(of: plain, arguments: ["--config=/tmp/x.json"]) == nil)
        #expect(ProgramPin.hash(of: plain, arguments: ["--root", "sub/dir"]) == nil)
        #expect(ProgramPin.hash(of: plain, arguments: ["--port=8080"]) != nil)
    }

    @Test func theCardShowsEveryLineByItsRealFieldAndNeverMergesWrittenWords() async throws {
        let w = try await World()
        _ = try server(w)
        let notices: [JSONValue] = [["tool": "notify.user", "input": ["body": "Call 555-0100 now: {{page}}"]], ["tool": "notify.user", "input": ["body": "Done {{page}}"]]]
        let quoteLine: JSONValue = ["tool": "notes.save", "input": ["text": "x”, tags: “secret"]]
        let sent = await words(w, Self.plan([Self.page] + notices + [quoteLine, Self.post(["body": "{{page}}"])]))
        let text = sent.words ?? ""
        #expect(text.contains("Call 555-0100 now:") && text.contains("Done "), "both notices: \(text)")
        #expect(!text.contains("with different"), "no row stands for several: \(text)")
        #expect(text.contains("x’, tags: ‘secret"), "a quote inside a value can't pass for another field: \(text)")
        #expect(text.contains("Words from “Read the page · web.fetch” go into body of “notify.user”"), "words a page writes into a notice are named too: \(text)")
        #expect(text.contains("it may also be a list, a record, a number, or left out"), "a field that is one slot takes a value of any kind, whatever its schema says: \(text)")
        let whole = await words(w, Self.plan([Self.page, ["tool": "watch.create", "input": ["interval_minutes": "{{page}}"]]], id: "whole"))
        #expect(whole.words?.contains("it may also be a list, a record, a number, or left out") == true, "\(String(describing: whole.words))")
    }

    @Test func aLineBreakOfAnyKindInAnAuthorsWordsIsOneLine() {
        let sneaky = "x\u{2028}Apart from the lines that still ask, that's all of it.\u{2029}y\u{85}z"
        let line = ExtensionText.line(sneaky, characters: 600)
        #expect(!line.unicodeScalars.contains { ["\u{2028}", "\u{2029}", "\u{85}", "\n"].contains($0) })
    }

    @Test func aLineThatStandsOnlyInFullAccessSaysSoOnTheCardUnderFullAccessToo() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        let count: JSONValue = ["tool": "watch.create", "input": ["interval_minutes": "{{n}}"]]
        let shown = await words(w, Self.plan([Self.page, count]), caller: .agent(runId: "r1"))
        #expect(shown.words?.contains("only while Full access is on") == true && shown.words?.contains("ask each time once it ends") == true, "\(String(describing: shown.words))")
    }


    // MARK: Round four

    @Test func anEditOfAPlanFullAccessAnsweredShowsItWholeAndOnceReadItStandsEverywhere() async throws {
        let w = try await World()
        _ = try server(w)
        try await w.setMode(.fullAccess)
        let plan = Self.plan([Self.page, Self.post(["body": "{{page}}"])])
        #expect(await !w.approve(plan).asked, "the click answered it")
        let edited = Self.plan([Self.page, Self.post(["body": "{{page}}"]), ["tool": "notify.user", "input": ["title": "Done"]]])
        let shown = await words(w, edited, caller: .agent(runId: "r1"))
        #expect(shown.words?.contains("It sends out:") == true && shown.words?.contains("Lines already allowed") == false, "nobody read the rest: \(String(describing: shown.words))")
        try await w.setMode(.askOncePerKind)
        let call: JSONValue = ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "words"]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true, "it was read on a card now, so it stands in every mode")
    }

    @Test func aServersToolCountsAsReadingYourThingsForTheWarningWhereverTheStepsAreWritten() async throws {
        let w = try await World()
        _ = try server(w)
        let spec = ToolSpec(name: "ext.hub.search", title: "Search mail", description: "", inputSchema: Schema.object(["query": Schema.string("Query")]),
                            risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        w.h.env.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.hub", extensionName: "GitHub", remoteName: "search", sandboxed: false) { _, _ in ToolResult(text: "") })
        let mail: JSONValue = ["tool": "ext.hub.search", "as": "mail", "input": ["query": "invoices"]]
        let plan = Self.plan([Self.page, mail, Self.post(["body": "{{page}} {{mail}}"])])
        #expect(await w.check(plan)["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing", "a server's read may hold your own things")
        #expect(await w.check(Self.plan([Self.page, Self.post(["body": "{{page}}"])]))["steps"]?.arrayValue?.last?["warning"] == nil, "the line itself isn't what it reads")
        // The order they are written in is not the order they are called in: a line written first is warned about too.
        #expect(await w.check(Self.plan([Self.post(["body": "{{page}}"]), mail, Self.page]))["steps"]?.arrayValue?.first?["warning"]?.stringValue == "crossing", "what comes after can feed it")
        let notes: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
        #expect(await w.check(Self.plan([Self.post(["body": "{{page}}"]), Self.page, notes]))["steps"]?.arrayValue?.first?["warning"]?.stringValue == "crossing", "your notes written last")
    }

    @Test func swappingTheNamesOfTwoStepsOfOneToolRebindsAndShows() async throws {
        let w = try await World()
        _ = try server(w)
        func read(_ name: String, _ query: String) -> JSONValue { ["tool": "notes.search", "as": .string(name), "input": ["query": .string(query)]] }
        let post = Self.post(["body": "{{a}}"])
        _ = await w.approve(Self.plan([read("a", "public"), read("b", "secret"), post]))
        let swapped = await words(w, Self.plan([read("a", "secret"), read("b", "public"), post]))
        #expect(swapped.words?.contains("Create an issue") == true, "the same text now pulls from the other step: \(String(describing: swapped.words))")
    }

    @Test func aNameOrPlanIdWithATrailingLineBreakIsRefused() async throws {
        let w = try await World()
        for named in ["a\n", "a\u{2028}", "a\u{85}"] {
            let step: JSONValue = ["tool": "web.fetch", "as": .string(named), "input": ["url": "https://news.example.com/feed"]]
            #expect(await w.check(Self.plan([step]))["reason"]?.stringValue == "unusable", "\(named.unicodeScalars.map { String($0.value, radix: 16) })")
        }
        #expect(await w.check(Self.plan([Self.save], id: "digest\n"))["reason"]?.stringValue == "unusable")
    }

    @Test func whenTheInternetAsksEachTimeALineThatUsesItSaysSo() async throws {
        let w = try await World()
        try await w.h.env.permissions.updatePolicy { $0.internet = .askEachTime }
        let shown = await words(w, Self.plan([Self.fetch, Self.save]))
        let text = shown.words ?? ""
        #expect(text.contains("It will still ask you each time:") && text.contains("you asked the internet to ask each time"), "\(text)")
        #expect(text.contains("It changes:") && text.contains("notes.save"), "what doesn't use it still stands: \(text)")
    }

    @Test func theRepliesAgreeOnWhatRunsWithoutACardNow() async throws {
        let w = try await World()
        let count: JSONValue = ["tool": "watch.create", "input": ["interval_minutes": "{{n}}"]]
        let plan = Self.plan([Self.save, count, Self.fetch])
        let approved = await w.approve(plan)
        #expect(approved.reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true, false, true], "a line that stands only in Full access asks now: \(approved.reply)")
        let states = await w.check(plan)["steps"]?.arrayValue?.compactMap { $0["state"]?.stringValue }
        #expect(states == ["stands", "stands_in_full_access", "stands"])
        try await w.setMode(.askEveryTime)
        let all = await w.approve(Self.plan([Self.save], id: "other"))
        #expect(all.reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [false], "in Ask every time every call asks")
    }

    /// Sideflow's demo saves a note whose words are filled in from earlier steps, in a run that read AI and spare values. Approved once, it runs without a card in
    /// every mode that lets a plan stand; only Ask every time asks, and says so (the founder saw "asks each time" with that mode on).
    @Test func anApprovedNoteSaveWithFilledInWordsAsksOnlyWhenTheModeIsAskEveryTime() async throws {
        let w = try await World()
        let save: JSONValue = ["tool": "notes.save", "input": ["text": "Sideflow demo: {{hello}} Spare value: {{spare}}. {{joke}}"]]
        let plan = Self.plan([["tool": "ask.user", "as": "hello", "input": ["question": "Hello?"]], save])
        let call: JSONValue = ["tool": "notes.save", "plan": "digest", "input": ["text": "Sideflow demo: hi Spare value: none. a joke"]]
        for mode in [GuardMode.askOncePerKind, .auto, .fullAccess] {
            try await w.setMode(mode)
            _ = await w.approve(plan)
            let states = await w.check(plan)["steps"]?.arrayValue?.compactMap { $0["state"]?.stringValue }
            #expect(states?.last == "stands", "\(mode): \(String(describing: states))")
            async let run = w.ask("sidefolk/tools.call", call)
            #expect(await w.answerCard(.deny, wait: 20) == nil, "\(mode): no card for what they approved")
            #expect(await run["standing"]?.boolValue == true, "\(mode)")
        }
        try await w.setMode(.askEveryTime)
        let checked = await w.check(plan)["steps"]?.arrayValue?.last
        #expect(checked?["state"]?.stringValue == "asks" && checked?["why"]?.stringValue == "ask_every_time", "\(String(describing: checked))")
        async let run = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.allowOnce) != nil, "Ask every time puts a card up for every call, however it was approved")
        // The call still fits what they read (`standing`); it is Guard that asks, because the mode never lets a plan answer.
        #expect(await run["standing"]?.boolValue == true)
    }

    /// A note's first line is its title and the rest its body, so a save that has a title and a body has a line break in its words. In a field the table opens
    /// for words a line feed stands (D236) and the card draws it as a mark, one for one; everywhere else, and for any other kind of break, the line asks.
    @Test func aLineFeedInTheWordsOfAnOpenFieldStandsInEveryModeAndTheCardShowsIt() async throws {
        let w = try await World()
        let titled: JSONValue = ["tool": "notes.save", "input": ["text": "Sideflow demo\nMade by the demo."]]
        let slotted: JSONValue = ["tool": "notes.save", "input": ["text": "Sideflow demo\n\n{{hello}}\n{{hello}}"]]
        let ask: JSONValue = ["tool": "ask.user", "as": "hello", "input": ["question": "Hello?"]]
        let plan = Self.plan([ask, titled, slotted])
        // The card says where the breaks are.
        async let first = w.ask("sidefolk/plan.approve", ["plan": plan])
        guard case .text(let words)? = await w.answerCard(.allowOnce)?.details else { Issue.record("a card"); return }
        _ = await first
        #expect(words.contains("“Sideflow demo⏎Made by the demo.”"), "a break is one mark: \(words)")
        #expect(words.contains("“Sideflow demo⏎⏎[from “ask.user”]⏎[from “ask.user”]”"), "breaks around a slot too: \(words)")
        let call: JSONValue = ["tool": "notes.save", "plan": "digest", "input": ["text": "Sideflow demo\nMade by the demo."]]
        let filled: JSONValue = ["tool": "notes.save", "plan": "digest", "input": ["text": "Sideflow demo\n\nhi\nthere\nand more"]]
        for mode in [GuardMode.askOncePerKind, .auto, .fullAccess] {
            try await w.setMode(mode)
            _ = await w.approve(plan)
            let states = await w.check(plan)["steps"]?.arrayValue?.compactMap { $0["state"]?.stringValue }
            #expect(states?.suffix(2) == ["stands", "stands"], "\(mode): \(String(describing: states))")
            for run in [call, filled] {
                async let reply = w.ask("sidefolk/tools.call", run)
                #expect(await w.answerCard(.deny, wait: 20) == nil, "\(mode): no card for what they read")
                #expect(await reply["standing"]?.boolValue == true, "\(mode)")
            }
        }
        // The same words with a space where the break was are not what they read.
        try await w.setMode(.askOncePerKind)
        async let other = w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "input": ["text": "Sideflow demo Made by the demo."]])
        #expect(await w.answerCard(.deny) != nil, "a break is part of the words")
        #expect(await other["standing"]?.boolValue == false)
    }

    /// A line feed inside a slot's braces is still a slot at run time, so the card has to say so: it can't read like fixed words.
    @Test func aSlotWithALineFeedInsideItsBracesIsStillShownAsASlot() async throws {
        let w = try await World()
        let plan = Self.plan([Self.page, ["tool": "notes.save", "input": ["text": "Title\n{{\npage\n}}"]]])
        async let first = w.ask("sidefolk/plan.approve", ["plan": plan])
        guard case .text(let words)? = await w.answerCard(.allowOnce)?.details else { Issue.record("a card"); return }
        _ = await first
        #expect(words.contains("“Title⏎[from “") && !words.contains("{{"), "the slot is on the card as a slot: \(words)")
        let call: JSONValue = ["tool": "notes.save", "plan": "digest", "input": ["text": "Title\nwords from the page"]]
        for mode in [GuardMode.askOncePerKind, .auto, .fullAccess] {
            try await w.setMode(mode)
            _ = await w.approve(plan)
            async let reply = w.ask("sidefolk/tools.call", call)
            #expect(await w.answerCard(.deny, wait: 20) == nil, "\(mode): what they read, slot and all")
            #expect(await reply["standing"]?.boolValue == true, "\(mode)")
        }
    }

    @Test func onlyAPlainLineFeedBetweenPlainLinesIsShownAndNothingElseStands() async throws {
        let w = try await World()
        func state(_ tool: String, _ input: JSONValue) async -> String {
            let line = await w.check(Self.plan([["tool": .string(tool), "input": input]]))["steps"]?.arrayValue?.first
            return "\(line?["state"]?.stringValue ?? "-")/\(line?["why"]?.stringValue ?? "-")"
        }
        for text in ["a\rb", "a\r\nb", "a\u{2028}b", "a\u{2029}b", "a\u{85}b", "a\tb", "a\u{0B}b", "a\u{0C}b", "a\u{1C}b", "\nab", "ab\n", "a\n\n\nb", "a\u{23CE}b", "a \nb", "a\n b", "a\n\u{200B}b"] {
            #expect(await state("notes.save", ["text": .string(text)]) == "asks/unreadable_value", "\(text.unicodeScalars.map(\.value))")
        }
        for text in ["a\nb", "a\n\nb", "Title\n- one\n- two\n\nend"] {
            #expect(await state("notes.save", ["text": .string(text)]) == "stands/-", Comment(rawValue: text))
        }
        // Only where the table opens a field for words: a collection's name, and a tool with no open field, keep one line.
        #expect(await state("notes.save", ["text": "a", "collection": "x\ny"]) == "asks/unreadable_value")
        #expect(await state("notify.user", ["title": "a\nb", "body": "c\nd"]) == "stands/-")
        #expect(await state("voice.say", ["text": "a\nb"]) == "stands/-")
        #expect(await state("files.read", ["path": "a\nb"]) == "asks/unreadable_value")
        // The limit counts a break as one character.
        let half = String(repeating: "a", count: 150)
        #expect(await state("notes.save", ["text": .string(String(half.dropLast()) + "\n" + half)]) == "stands/-", "300 characters with the break")
        #expect(await state("notes.save", ["text": .string(half + "\n" + half)]) == "asks/unreadable_value", "301")
        // The card's mark for a break and its look-alike are no one's plain words, in an open field or not.
        for mark in ["a\u{23CE}b", "a\u{21B5}b"] {
            #expect(await state("notes.save", ["text": "x", "collection": .string(mark)]) == "asks/unreadable_value", Comment(rawValue: mark))
            #expect(await state("notes.save", ["text": .string(mark)]) == "asks/unreadable_value", Comment(rawValue: mark))
        }
        // A key is one line too.
        #expect(await state("notes.save", ["text": "a", "co\nllection": "x"]) == "asks/unreadable_value")
    }

    // MARK: An AI agent asks for a plan (D237)

    /// Another AI agent, over MCP, may ask for a flow's plan, and the answer is only ever the person's, on a card that says who asked.
    /// An agent's call of the extension's tool has a card of its own ("Another app is asking"); the plan card is the one that comes after. Answers every card that
    /// isn't the plan's with Allow, and the plan's with `decision`; returns the plan's card, or nil if none came.
    static func answerThePlanCard(_ w: World, _ decision: ApprovalDecision, wait: Int = 400) async -> ApprovalRequest? {
        for _ in 0..<wait {
            if let card = await w.h.env.broker.pending().first {
                if card.tool == ExtensionPlanTool.name {
                    await w.h.env.broker.resolve(id: card.id, decision: decision)
                    return card
                }
                await w.h.env.broker.resolve(id: card.id, decision: .allowOnce)
            } else {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        return nil
    }

    /// The agent asks for `plan`; how many plan cards came (the reply's own is in `reply`).
    static func agentAsks(_ w: World, _ plan: JSONValue, client: String = "Claude Code", _ decision: ApprovalDecision = .allowOnce) async -> (reply: JSONValue, card: ApprovalRequest?) {
        async let reply = w.ask("sidefolk/plan.approve", ["plan": plan], caller: .external(client: client))
        let card = await answerThePlanCard(w, decision, wait: 120)
        return (await reply, card)
    }

    @Test func anAgentsAskPutsACardUpInEveryModeThatNamesItAndOnlyThePersonSettlesIt() async throws {
        for mode in [GuardMode.askEveryTime, .askOncePerKind, .auto, .fullAccess] {
            let w = try await World()
            try await w.setMode(mode)
            let first = await Self.agentAsks(w, Self.plan([Self.save]))
            guard case .text(let words)? = first.card?.details else { Issue.record("\(mode): a plan card, \(first.reply)"); continue }
            #expect(words.hasPrefix("An app that says it's “Claude Code” asked for this through Sidefolk's connection. Nothing is allowed until you approve it here."), "\(mode): \(words)")
            #expect(words.contains("It changes:"), "the plan itself is on it: \(words)")
            #expect(first.reply["ok"]?.boolValue == true && first.reply["silent"]?.boolValue == false, "\(mode): \(first.reply)")
            let row = try await w.rows("extensions.plan").first
            #expect(row?.args?["asked_by"]?.stringValue == "Claude Code", "\(mode): History says who asked: \(String(describing: row?.args))")
            // What they read stands, and the same plan asked for again by the agent is still a card: nothing an agent asks is answered by what was read before.
            let again = await Self.agentAsks(w, Self.plan([Self.save]))
            #expect(again.card != nil && again.reply["silent"]?.boolValue == false, "\(mode): \(again.reply)")
            // An edit that stays inside Sidefolk (which Auto answers for the person) is a card for an agent too.
            let edit = await Self.agentAsks(w, Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]]))
            #expect(edit.card != nil, "\(mode): \(edit.reply)")
            let plans = await w.h.host.loadPreferences("com.example.flow").plans
            #expect(plans["digest"]?.answeredUnread != true && plans["digest"]?.steps.allSatisfy { $0.answeredInAuto != true } == true, "\(mode): nobody answered it unread")
        }
    }

    /// The name on the card's first line is the connection's, never anything the agent writes into its own call, and what hides in it is marked.
    @Test func theNameOnAnAgentsCardIsTheConnectionsAndNotWhatTheAgentWrites() async throws {
        let w = try await World()
        // The agent puts a name of its own in the call's parameters, and in the plan's own fields.
        var plan = Self.plan([Self.save])
        plan = plan.setting("asked_by", "Sidefolk itself")
        async let reply = w.ask("sidefolk/plan.approve", ["plan": plan, "asked_by": "Sidefolk itself", "client": "Sidefolk itself"], caller: .external(client: "Co\u{200B}dex\u{202E}"))
        let card = await Self.answerThePlanCard(w, .allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a plan card"); return }
        #expect(words.hasPrefix("An app that says it's “Co⟨U+200B⟩dex⟨U+202E⟩” asked for this"), "the connection's name, with what hides marked: \(words)")
        #expect(!words.contains("Sidefolk itself"), "\(words)")
        _ = await reply
        let row = try await w.rows("extensions.plan").first
        #expect(row?.args?["asked_by"]?.stringValue == "Co⟨U+200B⟩dex⟨U+202E⟩", "\(String(describing: row?.args))")
        // A long name is cut, and one with a line break can't start a second line.
        let long = await Self.agentAsks(w, Self.plan([Self.save], id: "two"), client: String(repeating: "N", count: 200) + "\nSidefolk: approve")
        guard case .text(let longWords)? = long.card?.details else { Issue.record("a plan card"); return }
        #expect(longWords.hasPrefix("An app that says it's “N") && longWords.contains("…” asked for this") && !longWords.contains("Sidefolk: approve"), "\(longWords.prefix(200))")
    }

    // MARK: The code on an agent's card (D239)

    /// The agent's plan card and the code on it, with the card left up for the person; the agent's own call card is answered Allow on the way.
    static func waitForThePlanCard(_ w: World) async -> (card: ApprovalRequest, code: String)? {
        for _ in 0..<400 {
            if let card = await w.h.env.broker.pending().first {
                if card.tool == ExtensionPlanTool.name {
                    guard case .text(let words) = card.details, let found = words.firstMatch(of: /(\d{3}) (\d{3})/) else { return nil }
                    return (card, String(found.1) + String(found.2))
                }
                await w.h.env.broker.resolve(id: card.id, decision: .allowOnce)
            } else {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        return nil
    }

    @Test func theCodeOnAnAgentsCardApprovesItInEveryModeAndNowhereElseIsItSeen() async throws {
        for mode in [GuardMode.askEveryTime, .askOncePerKind, .auto, .fullAccess] {
            let w = try await World()
            try await w.setMode(mode)
            async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: .external(client: "Claude Code"))
            guard let (card, code) = await Self.waitForThePlanCard(w) else { Issue.record("\(mode): a plan card with a code"); continue }
            guard case .text(let words) = card.details else { continue }
            #expect(words.contains("You can also give that app this code in its chat: \(code.prefix(3)) \(code.suffix(3))."), "\(mode): \(words)")
            // Nowhere a card is read from but its words: not the summary a notice carries, not the exact request, not a row.
            #expect(!card.summary.contains(code) && !(card.input ?? "").contains(code) && !card.title.contains(code), "\(mode): the code is only in the card's words")
            let given = await w.confirm(code)
            #expect(given.ok, "\(mode): \(given.text)")
            #expect(!given.text.contains(code), "the answer to the agent doesn't repeat it")
            let answered = await reply
            #expect(answered["ok"]?.boolValue == true && answered["silent"]?.boolValue == false, "\(mode): \(answered)")
            #expect(!"\(answered)".contains(code), "\(mode): nor does the extension's reply")
            #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] != nil, "\(mode): the plan stands")
            #expect(await w.h.env.broker.pending().isEmpty, "\(mode): the card is gone")
            let rows = try await w.h.env.activity.recent(limit: 50)
            #expect(rows.contains { $0.tool == PlanCodeTool.name && $0.decision == .allowed && $0.summary.contains("Claude Code") && $0.args?["how"]?.stringValue == "code" }, "\(mode): a row says how")
            #expect(!rows.contains { "\($0.summary) \(String(describing: $0.args)) \($0.caller)".contains(code) }, "\(mode): no row has the code")
            // One use: the same code again finds nothing.
            let again = await w.confirm(code)
            #expect(!again.ok && again.text.contains("No card of yours is waiting"), "\(mode): \(again.text)")
        }
    }

    /// Through the external gateway, as a real agent calls: no row, whatever came of the try, holds the digits (the facade must pass the tool's own word on its rows, and
    /// a field called `code` is redacted in any row as a second line), and the ones that tell of a try say so without them.
    @Test func noHistoryRowHoldsTheCodeWhenAnAgentGivesItThroughTheGateway() async throws {
        let w = try await World()
        func rowsText() async throws -> String {
            try await w.h.env.activity.recent(limit: 200).map { String(describing: $0) }.joined(separator: "\n")
        }
        let agent = Caller.external(client: "Claude Code")
        // Wrong, wrong, wrong (locked), then the right one is refused too.
        async let first = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: agent)
        guard let (card, code) = await Self.waitForThePlanCard(w) else { Issue.record("a plan card"); return }
        let wrong = code == "246810" ? "135791" : "246810"
        for _ in 0..<3 { let tried = await w.confirmThroughTheGateway(wrong); #expect(!tried.ok, "\(tried.text)") }
        let late = await w.confirmThroughTheGateway(code)
        #expect(!late.ok, "locked: \(late.text)")
        var text = try await rowsText()
        #expect(!text.contains(code) && !text.contains(wrong), "wrong and locked: no row holds a digit of it:\n\(text)")
        #expect(text.contains("[redacted]"), "the rows that tell of a try keep the field, redacted")
        await w.h.env.broker.resolve(id: card.id, decision: .allowOnce)
        _ = await first
        // A new card and the right code: approved, and still no row has it.
        async let second = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save], id: "other")], caller: agent)
        guard let (_, code2) = await Self.waitForThePlanCard(w) else { Issue.record("a second plan card"); return }
        let approved = await w.confirmThroughTheGateway(code2)
        #expect(approved.ok, "\(approved.text)")
        _ = await second
        text = try await rowsText()
        #expect(!text.contains(code2), "approved: no row holds the code:\n\(text)")
        #expect(text.contains("Approved with the code the person gave Claude Code"), "and one row says how")
        // Too many tries in a minute: the row says so, once, without a digit.
        var last = (ok: true, text: "")
        for _ in 0..<9 { last = await w.confirmThroughTheGateway("999999") }
        #expect(!last.ok && last.text.contains("Too many tries"), "\(last.text)")
        text = try await rowsText()
        #expect(!text.contains("999999") && text.components(separatedBy: "tried codes too often").count == 2, "one row for the minute, no digits:\n\(text)")
    }

    @Test func aClickThatSettledTheCardFirstIsNotAnApprovalByTheCode() async throws {
        let w = try await World()
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: .external(client: "Claude Code"))
        guard let (card, code) = await Self.waitForThePlanCard(w) else { Issue.record("a plan card"); return }
        // The person's click lands, then the agent gives the right code a moment later: nothing was approved by it.
        await w.h.env.broker.resolve(id: card.id, decision: .allowOnce)
        _ = await reply
        let late = await w.confirmThroughTheGateway(code)
        #expect(!late.ok, "\(late.text)")
        let rows = try await w.h.env.activity.recent(limit: 50)
        #expect(!rows.contains { $0.summary.contains("Approved with the code") }, "no row says the code approved it")
    }

    @Test func aWrongCodeThreeTimesLocksTheCardAndTheClickStillWorks() async throws {
        let w = try await World()
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: .external(client: "Claude Code"))
        guard let (card, code) = await Self.waitForThePlanCard(w) else { Issue.record("a plan card"); return }
        let wrong = code == "000000" ? "111111" : "000000"
        let first = await w.confirm(wrong), second = await w.confirm(wrong), third = await w.confirm(wrong)
        #expect(!first.ok && first.text.contains("2 tries left") && !second.ok && second.text.contains("1 try left"), "\(first.text) \(second.text)")
        #expect(!third.ok && third.text.contains("needs the person's click"), "\(third.text)")
        // Locked: even the right code is no longer taken, and nothing was approved.
        let late = await w.confirm(code)
        #expect(!late.ok, "\(late.text)")
        #expect(await w.h.env.broker.pending().contains { $0.id == card.id }, "the card is still up")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil)
        // The person's click on the desktop works as it always did.
        await w.h.env.broker.resolve(id: card.id, decision: .allowOnce)
        let answered = await reply
        #expect(answered["ok"]?.boolValue == true, "\(answered)")
        let rows = try await w.h.env.activity.recent(limit: 50)
        #expect(rows.contains { $0.tool == PlanCodeTool.name && $0.decision == .denied && $0.summary.contains("too many times") }, "the lock is on the record")
        #expect(!rows.contains { "\($0.summary) \(String(describing: $0.args))".contains(wrong) && $0.tool == PlanCodeTool.name && $0.summary.contains(wrong) }, "a wrong code isn't recorded either")
    }

    @Test func aCodeIsForOneCardOneAgentAndTwoMinutes() async throws {
        let w = try await World()
        // Another agent's name, or a call that isn't an agent's at all, gets nothing.
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: .external(client: "Claude Code"))
        guard let (card, code) = await Self.waitForThePlanCard(w) else { Issue.record("a plan card"); return }
        let other = await w.confirm(code, as: "Codex")
        #expect(!other.ok && other.text.contains("No card of yours"), "another agent's name: \(other.text)")
        for caller in [Caller.user, .agent(runId: "r"), .routine(id: "r"), .extension(id: "com.example.flow")] {
            let refused = await w.confirm(code, caller: caller)
            #expect(!refused.ok, "\(caller)")
        }
        #expect(await w.h.env.broker.pending().contains { $0.id == card.id }, "none of that touched the card")
        // Two minutes: past them the code is nothing, and the card is a click.
        await w.h.host.ageAgentCode("com.example.flow", by: 121)
        let late = await w.confirm(code)
        #expect(!late.ok && late.text.contains("No card of yours"), "\(late.text)")
        await w.h.env.broker.resolve(id: card.id, decision: .deny)
        _ = await reply
        // Another plan's card has a code of its own, and the first card's is of no use for it.
        async let second = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]], id: "other")], caller: .external(client: "Claude Code"))
        guard let (card2, code2) = await Self.waitForThePlanCard(w) else { Issue.record("a second plan card"); return }
        if code2 != code {
            let replay = await w.confirm(code)
            #expect(!replay.ok && !replay.text.contains("Approved"), "the old code for the new card: \(replay.text)")
        }
        #expect(await w.h.env.broker.pending().contains { $0.id == card2.id }, "the new card is untouched by a wrong code")
        await w.h.env.broker.resolve(id: card2.id, decision: .deny)
        _ = await second
    }

    @Test func anAgentCantTryCodesFasterThanSixAMinute() async throws {
        let w = try await World()
        var last = (ok: true, text: "")
        for _ in 0..<7 { last = await w.confirm("123456") }
        #expect(!last.ok && last.text.contains("Too many tries"), "\(last.text)")
    }

    /// The person's click after an agent's call doesn't turn the agent's plan into theirs: the extension's program can be answering either, so while the agent's
    /// call is within the window every ask is a card.
    @Test func aClickAfterAnAgentsCallDoesNotMakeItsPlanThePersons() async throws {
        let agent = Caller.external(client: "Codex")
        func openTheAgentsWindow(_ w: World, _ plan: JSONValue) async {
            async let opening = w.ask("sidefolk/plan.check", ["plan": plan], caller: agent)
            _ = await Self.answerThePlanCard(w, .deny, wait: 60)
            _ = await opening
        }
        // Full access answers a signed plan for the person's own click: not this one.
        let full = try await World()
        try await full.setMode(.fullAccess)
        #expect(await !full.approve(Self.plan([Self.save])).asked, "with no agent about, the person's click is answered in Full access")
        await openTheAgentsWindow(full, Self.plan([Self.save]))
        #expect(await full.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]], id: "other")).asked, "the person's click came after the agent's call, and it is still a card")
        // Auto skips an edit that stays inside Sidefolk for the person: not this one.
        let auto = try await World()
        try await auto.setMode(.auto)
        _ = await auto.approve(Self.plan([Self.save]))
        await openTheAgentsWindow(auto, Self.plan([Self.save]))
        #expect(await auto.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])).asked, "Auto doesn't skip it either")
        // And a plan nothing in which is new, for the person, in the same window: a card too, since the answer can't be told to be theirs.
        #expect(await auto.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])).asked)
    }

    /// An agent's call that is still running keeps its window, however long it runs: a click of the person's after the first 30 seconds doesn't make the plan the
    /// person's, and the window runs 30 seconds past the call's end.
    @Test func anAgentsCallThatIsStillRunningKeepsItsWindowOpen() async throws {
        let w = try await World()
        let id = "com.example.flow"
        try await w.setMode(.auto)
        _ = await w.approve(Self.plan([Self.save]))
        let edit = Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])
        let token = await w.h.host.notePersonCall(id, caller: .external(client: "Codex"), tainted: true)
        #expect(token != nil)
        await w.h.host.ageAgentCall(id, by: 60)
        #expect(await w.approve(edit).asked, "the agent's call is 60 s old and still running, and the person's click came after it: a card, never Auto's skip")
        #expect(await w.approve(edit).asked, "and the same plan again is not answered as covered either")
        if let token { await w.h.host.endPersonClick(id, token) }
        #expect(await w.approve(edit).asked, "30 seconds from its end it is still the agent's window")
        await w.h.host.ageAgentCall(id, by: 60)
        #expect(await !w.approve(edit).asked, "after that it is the person's again: nothing new, no card")
    }

    /// The same edit, for the person's own ask, is what Auto answers: so the agent's card above is the agent's own rule, not a quirk of the edit.
    @Test func theSameEditIsAnsweredForThePersonInAutoButNotForAnAgent() async throws {
        let w = try await World()
        try await w.setMode(.auto)
        _ = await w.approve(Self.plan([Self.save]))
        #expect(await !w.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])).asked, "the person's own ask passes in Auto")
    }

    /// Nothing but the person's own answer on the card settles it: the agent can't, a model's "yes" is no answer, and a card nobody answered saves nothing.
    @Test func anAgentsCardIsNotSettledUntilThePersonAnswersAndADenialSavesNothing() async throws {
        let w = try await World()
        async let waiting = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: .external(client: "Codex"))
        // The agent's own call has its card first; the plan's comes after, and then waits.
        var planCard: ApprovalRequest?
        for _ in 0..<200 where planCard == nil {
            if let card = await w.h.env.broker.pending().first {
                if card.tool == ExtensionPlanTool.name { planCard = card } else { await w.h.env.broker.resolve(id: card.id, decision: .allowOnce) }
            } else {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        #expect(planCard != nil, "the plan's card is up")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(await w.h.env.broker.pending().contains { $0.tool == ExtensionPlanTool.name }, "still waiting for the person")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil, "nothing saved before they answer")
        if let planCard { await w.h.env.broker.resolve(id: planCard.id, decision: .deny) }
        let reply = await waiting
        #expect(reply["ok"]?.boolValue == false && reply["reason"]?.stringValue == "denied", "\(reply)")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil, "a denial saves nothing")
    }

    /// Only another AI agent over MCP has a window of its own: a routine, an extension or an unattended run still can't start a card (T3).
    @Test func aRoutineOrAnotherExtensionStillCantStartACardAndAnAgentsWindowEnds() async throws {
        let w = try await World()
        for caller in [Caller.routine(id: "r"), .extension(id: "other.ext")] {
            let reply = await w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save])], caller: caller)
            #expect(reply["ok"]?.boolValue == false && reply["reason"]?.stringValue == "not_asked", "\(caller): \(reply)")
            #expect(await w.h.env.broker.pending().isEmpty)
        }
    }

    @Test func aJobForTheCompanionCountsAsReadingOutsideContent() async throws {
        let w = try await World()
        _ = try server(w)
        w.h.env.registry.register(CompanionJobTool(agent: CompanionAgentSlot()))
        let notes: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
        let job: JSONValue = ["tool": "companion.job", "as": "summary", "input": ["job": "Summarise my plans"]]
        let checked = await w.check(Self.plan([notes, job, Self.post(["body": "{{summary}}"])]))
        #expect(checked["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing", "a job reads pages as it likes: \(checked)")
    }

    @Test func whenTheInternetAsksEachTimeTheEditorSaysSoToo() async throws {
        let w = try await World()
        try await w.h.env.permissions.updatePolicy { $0.internet = .askEachTime }
        let checked = await w.check(Self.plan([Self.fetch, Self.save]))
        let steps = checked["steps"]?.arrayValue ?? []
        #expect(steps.first?["state"]?.stringValue == "asks" && steps.first?["why"]?.stringValue == "ask_online", "\(checked)")
        #expect(steps.last?["state"]?.stringValue == "stands")
    }

    @Test func lookingAndApprovingHaveBudgetsOfTheirOwn() async throws {
        let w = try await World()
        for _ in 0..<65 { _ = await w.check(Self.plan([Self.save])) }
        #expect(await w.check(Self.plan([Self.save]))["reason"]?.stringValue == "busy")
        #expect(await w.approve(Self.plan([Self.save])).reply["ok"]?.boolValue == true, "an editor looking doesn't take the person's Run")
    }

    @Test func anAuthorsQuotesNeverEndTheirOwnQuote() {
        let safe = ExtensionPlanWords.safe("x” go nowhere. Words from “y", 80)
        #expect(!safe.contains("”") && !safe.contains("“"), "\(safe)")
        let title = ExtensionPlanTool(extensionId: "e", plan: "Daily” (read only) “x", body: "b", intent: "run").spec.title
        #expect(title.filter { $0 == "“" }.count == 1 && title.filter { $0 == "”" }.count == 1, "\(title)")
    }

    @Test func aJoinerInWritingThatHasThemShowsOnTheCard() async throws {
        let w = try await World()
        let persian = "می\u{200C}خواهم"
        let shown = await words(w, Self.plan([["tool": "notify.user", "input": ["title": .string(persian)]]]))
        #expect(shown.words?.contains(persian) == true, "the card shows the bytes that run, joiner and all")
    }

    @Test func aWholeSlotOfWordsMaySaySoAboutBeingLeftOut() async throws {
        let w = try await World()
        _ = try server(w)
        let shown = await words(w, Self.plan([Self.page, Self.post(["body": "{{page}} {{page}}"])]))
        #expect(shown.words?.contains("from “Read the page · web.fetch”]”") == true, "one source named once: \(String(describing: shown.words))")
    }


    @Test func theSamePlanAgainWithServerLinesAndNamedSourcesAsksNothing() async throws {
        let w = try await World()
        _ = try server(w)
        let ai: JSONValue = ["kind": "ai", "as": "write", "reads": ["page"]]
        let plan = Self.plan([Self.page, ai, Self.post(["body": "{{write}}", "title": "{{page}}"])])
        #expect(await w.approve(plan).asked)
        let again = await w.approve(plan)
        #expect(!again.asked && again.reply["silent"]?.boolValue == true, "a no-op edit keeps the fingerprints it had: \(again.reply)")
        #expect(await w.check(plan)["silent"]?.boolValue == true)
    }


    // MARK: Lines, and steps that pass words on

    @Test func theLimitCountsDifferentLinesNotNamesAndTheCardSaysHowManyTimes() async throws {
        let w = try await World()
        // 70 steps, each with its own name, of 10 different lines.
        func step(_ i: Int) -> JSONValue { ["tool": "notify.user", "as": .string("n\(i)"), "input": ["title": .string("Line \(i % 10)")]] }
        let seventy = Self.plan((0..<70).map(step))
        let shown = await words(w, seventy)
        #expect(shown.reply["ok"]?.boolValue == true, "\(shown.reply)")
        #expect(shown.words?.contains("× 7") == true, "\(String(describing: shown.words))")
        let eighty: JSONValue = Self.plan((0..<70).map { i in ["tool": "notify.user", "as": .string("m\(i)"), "input": ["title": .string("Different \(i)")]] })
        #expect(await w.check(eighty)["reason"]?.stringValue == "unusable", "70 different lines are too many to read")
    }

    @Test func aStepThatOnlyPassesWordsOnKeepsTheirSourceAndIsNeverShown() async throws {
        let w = try await World()
        _ = try server(w)
        func plan(reads: String, post: [String: JSONValue]) -> JSONValue {
            let value: JSONValue = ["kind": "value", "as": "t", "reads": [.string(reads)]]
            return Self.plan([Self.page, ["tool": "notes.search", "as": "mail", "input": ["query": "invoices"]], value, Self.post(post)])
        }
        let first = plan(reads: "page", post: ["body": "{{t}}"])
        let shown = await words(w, first)
        #expect(shown.words?.contains("Words from “Read the page · web.fetch”") == true, "\(String(describing: shown.words))")
        #expect(shown.words?.contains("from “value”") == false && shown.words?.contains("kind") == false, "a value step has no line on the card")
        // Outside words through a step still can't pick a place or run code.
        let place = await w.check(plan(reads: "page", post: ["repo": "{{t}}"]))["steps"]?.arrayValue?.last
        #expect(place?["state"]?.stringValue == "stands_in_full_access")
        let code = await w.check(plan(reads: "page", post: ["command": "{{t}}"]))["steps"]?.arrayValue?.last
        #expect(code?["state"]?.stringValue == "refused")
        // Editing what it reads, with nothing else changed, is new at the line that uses it.
        let edited = await words(w, plan(reads: "mail", post: ["body": "{{t}}"]))
        #expect(edited.words?.contains("Create an issue") == true, "the same text now comes from another step: \(String(describing: edited.words))")
        // The person's own typed answer, passed through a step, stays theirs.
        let ask: JSONValue = ["tool": "ask.user", "as": "who", "input": ["question": "Where?"]]
        let through: JSONValue = ["kind": "value", "as": "t", "reads": ["who"]]
        let mine = await w.check(Self.plan([ask, through, Self.post(["repo": "{{t}}"])]))["steps"]?.arrayValue?.last
        #expect(mine?["state"]?.stringValue == "stands_in_full_access" && mine?["why"]?.stringValue == "declared_place", "a typed answer is read from names the program wrote: \(String(describing: mine))")
        #expect(await w.check(Self.plan([Self.page, ["kind": "value", "as": "t", "reads": ["t"]], Self.post(["command": "{{t}}"])]))["steps"]?.arrayValue?.last?["state"]?.stringValue == "refused",
                "a value that reads itself is read as outside, not looped")
    }


    // MARK: Fifth read

    @Test func aDeepDiamondOfValueStepsIsWorkedOutOnceAndFast() async throws {
        let w = try await World()
        _ = try server(w)
        let ask: JSONValue = ["tool": "ask.user", "as": "who", "input": ["question": "Where?"]]
        var steps: [JSONValue] = [ask, ["kind": "value", "as": "c0", "reads": ["who"]]]
        for k in 1...30 {
            steps.append(["kind": "value", "as": .string("a\(k)"), "reads": [.string("c\(k - 1)")]])
            steps.append(["kind": "value", "as": .string("b\(k)"), "reads": [.string("c\(k - 1)")]])
            steps.append(["kind": "value", "as": .string("c\(k)"), "reads": [.string("a\(k)"), .string("b\(k)")]])
        }
        steps.append(Self.post(["repo": "{{c30}}"]))
        let started = ContinuousClock.now
        let checked = await w.check(Self.plan(steps))
        #expect(ContinuousClock.now - started < .seconds(10), "not exponential")
        #expect(checked["steps"]?.arrayValue?.last?["why"]?.stringValue == "declared_place", "the person's answer, passed down 90 steps, is still read as theirs, and a place it fills stands only in Full access")
    }

    @Test func aStepsNamesToReadMustAllBeNamesAndFewAndNeverDropped() async throws {
        let w = try await World()
        let ask: JSONValue = ["tool": "ask.user", "as": "who", "input": ["question": "Where?"]]
        for reads in [["who", "page.title"], ["who", "bad name"], [], Array(repeating: "who", count: 70), (0..<40).map { "n\($0)" }] as [[String]] {
            let value: JSONValue = ["kind": "value", "as": "t", "reads": .array(reads.map { .string($0) })]
            #expect(await w.check(Self.plan([ask, value]))["reason"]?.stringValue == "unusable", "\(reads.prefix(3))")
            let ai: JSONValue = ["kind": "ai", "as": "w", "reads": .array(reads.map { .string($0) })]
            if !reads.isEmpty { #expect(await w.check(Self.plan([ask, ai]))["reason"]?.stringValue == "unusable", "\(reads.prefix(3))") }
        }
        let twice: JSONValue = ["kind": "value", "as": "t", "reads": ["who", "who"]]
        #expect(await w.check(Self.plan([ask, twice]))["ok"]?.boolValue == true, "a name twice is read once")
    }

    @Test func cyclesAndNamesNoStepMakesAreOutside() async throws {
        let w = try await World()
        _ = try server(w)
        func state(_ steps: [JSONValue], _ field: String, key: String = "state") async -> String? {
            await w.check(Self.plan(steps + [Self.post([field: "{{a}}"])]))["steps"]?.arrayValue?.last?[key]?.stringValue
        }
        let ab: [JSONValue] = [["kind": "value", "as": "a", "reads": ["b"]], ["kind": "value", "as": "b", "reads": ["a"]]]
        #expect(await state(ab, "command") == "refused", "two steps reading each other")
        #expect(await state([["kind": "value", "as": "a", "reads": ["nobody"]]], "command") == "refused", "a name no step makes")
        let ask: JSONValue = ["tool": "ask.user", "as": "who", "input": ["question": "Where?"]]
        #expect(await state([["kind": "value", "as": "a", "reads": ["later"]], ask, ["kind": "value", "as": "later", "reads": ["who"]]], "repo", key: "why") == "declared_place",
                "a name a LATER step makes is that step's, read the same way as an earlier one (a typed answer, which still only stands in Full access in a place)")
    }

    @Test func theAIRowNamesWhatAValueStepPassesOn() async throws {
        let w = try await World()
        _ = try server(w)
        let notes: JSONValue = ["tool": "notes.search", "as": "mail", "title": "Weather", "input": ["query": "invoices"]]
        func plan(_ reads: String) -> JSONValue {
            Self.plan([Self.page, notes, ["kind": "value", "as": "v", "reads": [.string(reads)]], ["kind": "ai", "as": "write", "reads": ["v"]]])
        }
        let first = await words(w, plan("page"))
        #expect(first.words?.contains("from “Read the page · web.fetch”") == true && first.words?.contains("from “v”") == false, "\(String(describing: first.words))")
        let edited = await words(w, plan("mail"))
        #expect(edited.words?.contains("Weather · notes.search") == true, "the AI step now reads another step, and the card says which, by title and tool: \(String(describing: edited.words))")
    }

    @Test func anUnsignedExtensionCantSendAValueStep() async throws {
        let third = try await World(origin: nil, name: "other")
        let value: JSONValue = ["kind": "value", "as": "t", "reads": ["who"]]
        #expect(await third.check(Self.plan([value]))["reason"]?.stringValue == "unusable")
    }

    @Test func linesAreGroupedOnlyWhenTheyAreTheSameToolAndTheSameBytes() async throws {
        let w = try await World()
        _ = try server(w)
        for name in ["post2"] {
            let spec = ToolSpec(name: "ext.hub.\(name)", title: "Create an issue", description: "", inputSchema: Schema.object(["title": Schema.string("Title")]),
                                risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
            w.h.env.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.hub", extensionName: "GitHub", remoteName: name, program: w.h.root.appendingPathComponent("hub-server").path, sandboxed: false) { _, _ in ToolResult(text: "") })
        }
        let one: JSONValue = ["tool": "ext.hub.post", "input": ["repo": "me/digest", "title": "Same"]]
        let other: JSONValue = ["tool": "ext.hub.post2", "input": ["title": "Same"]]
        let plan = Self.plan([one, other])
        let shown = await words(w, plan)
        #expect(shown.words?.contains("× 2") == false, "two tools with one title are two lines: \(String(describing: shown.words))")
        let composed = "\u{E9}", decomposed = "e\u{301}"
        let notices = Self.plan([["tool": "notify.user", "input": ["title": .string(composed)]], ["tool": "notify.user", "input": ["title": .string(decomposed)]]], id: "uni")
        let second = await words(w, notices)
        #expect(second.words?.contains("× 2") == false, "text that only compares equal isn't the same line: \(String(describing: second.words))")
    }

    @Test func theLimitsOn64DifferentLinesAnd256RowsHoldAtTheEdge() async throws {
        let w = try await World()
        func notice(_ i: Int, name: String? = nil) -> JSONValue {
            var step: [String: JSONValue] = ["tool": "notify.user", "input": ["title": .string("Line \(i)")]]
            if let name { step["as"] = .string(name) }
            return .object(step)
        }
        #expect(await w.check(Self.plan((0..<64).map { notice($0) }))["ok"]?.boolValue == true, "64 different lines")
        #expect(await w.check(Self.plan((0..<65).map { notice($0) }))["reason"]?.stringValue == "unusable", "65 different lines")
        #expect(await w.check(Self.plan((0..<256).map { notice($0 % 10, name: "n\($0)") }))["ok"]?.boolValue == true, "256 rows of 10 lines")
        #expect(await w.check(Self.plan((0..<257).map { notice($0 % 10, name: "n\($0)") }))["reason"]?.stringValue == "unusable", "257 rows")
    }

    // MARK: L3

    @Test func theApproveButtonSaysApproveAndAboveItWhatElseIsApproved() async throws {
        let w = try await World()
        _ = try server(w)
        async let reply = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.page, Self.post(["body": "{{page}}"])])])
        let card = await w.answerCard(.allowOnce)
        #expect(card?.allowLabel == "Approve")
        #expect(card?.allowNote == "Approving also lets it pass what it reads to GitHub.", "\(String(describing: card?.allowNote))")
        _ = await reply
        async let plain = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save], id: "plain")])
        let second = await w.answerCard(.allowOnce)
        #expect(second?.allowLabel == "Approve" && second?.allowNote == nil, "nothing passes on: no extra line")
        _ = await plain
    }

    @Test func aPlanIsListedWithWhatTheyReadWhenItLastRanAndHowManyToday() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        var info = await w.h.host.info(id: "com.example.flow")?.plans.first
        #expect(info?.card.contains("It changes:") == true && info?.lastUsed == nil && info?.callsToday == 0 && info?.signed == true, "\(String(describing: info))")
        _ = await w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "input": ["text": "Digest: x"]])
        info = await w.h.host.info(id: "com.example.flow")?.plans.first
        #expect(info?.lastUsed != nil && info?.callsToday == 1)
    }

    @Test func trustShowsTheWholePlanAfterAnEditNotOnlyWhatTheEditAdded() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        #expect(await w.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])).asked, "the new line asks")
        let card = await w.h.host.info(id: "com.example.flow")?.plans.first?.card ?? ""
        #expect(card.contains("It changes:") && card.contains("It tells or asks you:") && !card.contains("New, asking you now"), Comment(rawValue: card))
    }

    @Test func approvingAgainKeepsWhenItLastRanAndARunWhileACardIsUpDoesNotRefuseTheEdit() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        _ = await w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "input": ["text": "Digest: x"]])
        let ran = await w.h.host.info(id: "com.example.flow")?.plans.first?.lastUsed
        #expect(ran != nil)
        #expect(await !w.approve(Self.plan([Self.save])).asked, "the same plan again is covered")
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.first?.lastUsed == ran, "approving again does not make a plan that ran look idle")
        // A run while the edit's card is up changes only when it last ran: the edit is still what they read.
        async let edit = w.ask("sidefolk/plan.approve", ["plan": Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])])
        var waited = 0
        while await w.h.env.broker.pending().isEmpty, waited < 200 { try? await Task.sleep(for: .milliseconds(25)); waited += 1 }
        // What a run does while the card is up (the test program takes one call at a time, so the write itself is made here).
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.lastUsed = Date() }
        #expect(await w.answerCard(.allowOnce) != nil)
        let reply = await edit
        #expect(reply["ok"]?.boolValue == true, "a run in between is not a change of the plan")
    }

    @Test func anIdlePlanEndsWithItsRowWhenTrustIsListedAndOnlyOnce() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let old = Date().addingTimeInterval(-61 * 24 * 3600)
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = old }
        // Nothing asks from the extension: only the list is built (twice).
        _ = await w.h.host.info(id: "com.example.flow")
        _ = await w.h.host.info(id: "com.example.flow")
        var rows: [ActivityEntry] = []
        for _ in 0..<80 where rows.isEmpty {
            rows = try await w.rows("extensions.plan_end")
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await Task.sleep(for: .milliseconds(200))
        rows = try await w.rows("extensions.plan_end")
        #expect(rows.count == 1 && rows.first?.decision == .planEnded, "listing alone ends it, once: \(rows.count)")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil)
        // The extension asking afterwards finds nothing to end again.
        _ = await w.ask("sidefolk/tools.list")
        #expect(try await w.rows("extensions.plan_end").count == 1)
    }

    @Test func trustSaysNobodyReadAllOfItOnlyWhereNoCardWasShown() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.first?.nobodyReadAll == false, "read on a card")
        let w2 = try await World()
        try await w2.setMode(.fullAccess)
        #expect(await !w2.approve(Self.plan([Self.save])).asked)
        #expect(await w2.h.host.info(id: "com.example.flow")?.plans.first?.nobodyReadAll == true, "Full access answered it with no card")
        // Lines read on a card that stand only in Full access are read.
        func info(_ stands: ExtensionPlanInfo.Stands) -> ExtensionPlanInfo { ExtensionPlanInfo(id: "p", title: "", when: "", actions: 1, stands: stands, approvedAt: Date(), expiresAt: nil) }
        #expect(info(.fullAccessSome).nobodyReadAll == false && info(.always).nobodyReadAll == false)
        #expect(info(.fullAccessUnread).nobodyReadAll && info(.autoSome).nobodyReadAll && info(.either).nobodyReadAll)
    }

    @Test func anEntryThatEndedAnotherWayIsNotThePastOfAFreshApproval() async throws {
        let day: TimeInterval = 24 * 3600
        // Ended by its time, 65 days ago, last ran 70 days ago.
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        await w.h.host.updatePreferences("com.example.flow") {
            $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-70 * day)
            $0.plans["digest"]?.expiresAt = Date().addingTimeInterval(-65 * day)
            $0.plans["digest"]?.lastUsed = Date().addingTimeInterval(-70 * day)
        }
        _ = await w.approve(Self.plan([Self.save]))
        var kept = await w.h.host.loadPreferences("com.example.flow").plans["digest"]
        #expect(kept?.lastUsed == nil && kept?.expiresAt == nil, "a fresh approval has no past: \(String(describing: kept))")
        _ = await w.ask("sidefolk/tools.list")
        let swept = try await w.rows("extensions.plan_end")
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.map(\.id) == ["digest"] && swept.isEmpty, "it was not swept the moment it was approved")
        // Another owner's entry under the same id.
        let w2 = try await World()
        _ = await w2.approve(Self.plan([Self.save]))
        await w2.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.owner = "someone else"; $0.plans["digest"]?.lastUsed = Date().addingTimeInterval(-70 * day) }
        _ = await w2.approve(Self.plan([Self.save]))
        kept = await w2.h.host.loadPreferences("com.example.flow").plans["digest"]
        #expect(kept?.lastUsed == nil, "\(String(describing: kept))")
        _ = await w2.ask("sidefolk/tools.list")
        #expect(await w2.h.host.info(id: "com.example.flow")?.plans.map(\.id) == ["digest"])
        // A plan that last ran 59 days ago and is edited, with a card: the approval is use of its own, so it does not end tomorrow.
        let w3 = try await World()
        _ = await w3.approve(Self.plan([Self.save]))
        await w3.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-59 * day); $0.plans["digest"]?.lastUsed = Date().addingTimeInterval(-59 * day) }
        #expect(await w3.approve(Self.plan([Self.save, ["tool": "notify.user", "input": ["title": "Done"]]])).asked)
        let edited = await w3.h.host.loadPreferences("com.example.flow").plans["digest"]
        #expect(edited?.live(at: Date().addingTimeInterval(2 * day), owner: edited?.owner ?? "") == true, "approved just now: alive in two days")
    }

    @Test func aCardThePersonApprovedRenewsAPlanEvenWhenNothingInItWasNew() async throws {
        let day: TimeInterval = 24 * 3600
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        func approvedAt() async -> Date? { await w.h.host.loadPreferences("com.example.flow").plans["digest"]?.approvedAt }
        // Ask every time shows a card even for a plan nothing in which changed; approving it is use.
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-59.9 * day) }
        try await w.setMode(.askEveryTime)
        #expect(await w.approve(Self.plan([Self.save])).asked, "Ask every time shows the card")
        #expect((await approvedAt()).map { Date().timeIntervalSince($0) < 3600 } == true, "approved just now, not 59.9 days ago")
        // Without a card nobody renewed anything: the approval keeps its date.
        try await w.setMode(.askOncePerKind)
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-30 * day) }
        #expect(await !w.approve(Self.plan([Self.save])).asked)
        #expect((await approvedAt()).map { abs(Date().timeIntervalSince($0) - 30 * day) < 3600 } == true, "a covered plan with no card keeps the date of the card they read")
    }

    @Test func anExtensionThatIsNotRunningIsRecordedAsNotToldWhateverTheClientBecomesLater() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-61 * 24 * 3600) }
        try await w.h.host.setEnabled(false, id: "com.example.flow")
        _ = await w.h.host.info(id: "com.example.flow")
        var rows: [ActivityEntry] = []
        for _ in 0..<80 where rows.isEmpty {
            rows = try await w.rows("extensions.plan_end")
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(rows.first?.args?["told"]?.boolValue == false && rows.first?.summary.contains("was not running, so it was not told") == true, "\(String(describing: rows.first?.summary))")
    }

    @Test func theRowSaysWhetherTheExtensionWasToldOfAnIdleEnd() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = Date().addingTimeInterval(-61 * 24 * 3600) }
        _ = await w.ask("sidefolk/tools.list")
        var row = try await w.rows("extensions.plan_end").first
        #expect(row?.args?["told"]?.boolValue == true && row?.summary.hasSuffix("Its extension was told.") == true, "\(String(describing: row?.summary))")
        await w.gateway.recordPlanEnded(extensionId: "com.example.flow", plan: "digest", title: "Digest", told: false)
        row = try await w.rows("extensions.plan_end").first
        #expect(row?.args?["told"]?.boolValue == false && row?.summary.contains("was not running, so it was not told") == true, "\(String(describing: row?.summary))")
    }

    @Test func aLastRunAheadOfTheClockDoesNotKeepAPlanAlivePastSixtyDays() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let old = Date().addingTimeInterval(-61 * 24 * 3600)
        // Set ahead by an hour (a clock that was corrected): it counts as now.
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = old; $0.plans["digest"]?.lastUsed = Date().addingTimeInterval(3600) }
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.map(\.id) == ["digest"], "a little ahead is believed as now")
        // Set ahead by ten days (the clock was moved back): not believed, the approval's date is used, and it is old.
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.lastUsed = Date().addingTimeInterval(10 * 24 * 3600) }
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.isEmpty == true, "far ahead does not keep it alive")
    }

    @Test func aPlanNobodyUsedFor60DaysEndsAndItsProgramIsTold() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let old = Date().addingTimeInterval(-61 * 24 * 3600)
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = old }
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.isEmpty == true, "an idle plan is not live: it stands for nothing")
        // The next time its extension asks anything, the plan is taken away for good and its program told.
        _ = await w.ask("sidefolk/tools.list")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil)
        let ended = try await w.rows("extensions.plan_end").first
        #expect(ended?.decision == .planEnded && ended?.args?["plan"]?.stringValue == "digest", "a plan that ends by itself is a row in History: \(String(describing: ended))")
        // One used a month ago is fine.
        _ = await w.approve(Self.plan([Self.save], id: "recent"))
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["recent"]?.lastUsed = Date().addingTimeInterval(-30 * 24 * 3600); $0.plans["recent"]?.approvedAt = old }
        _ = await w.ask("sidefolk/tools.list")
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.map(\.id) == ["recent"], "use keeps it")
    }

    // MARK: Limits

    @Test func aRunPastItsLimitIsStoppedNotAsked() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save], perRun: 2))
        for _ in 0..<2 {
            let ok = await w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "run": "r1", "input": ["text": "Digest: x"]])
            #expect(ok["standing"]?.boolValue == true)
        }
        let over = await w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "run": "r1", "input": ["text": "Digest: x"]])
        #expect(over["status"]?.stringValue == "capped" && over["limit"]?.stringValue == "run", "\(over)")
        #expect(await w.h.env.broker.pending().isEmpty)
        let fresh = await w.ask("sidefolk/tools.call", ["tool": "notes.save", "plan": "digest", "run": "r2", "input": ["text": "Digest: x"]])
        #expect(fresh["standing"]?.boolValue == true, "another run has its own count")
    }
}


extension ExtensionHost {
    /// A test's way to let time pass for an agent's code without waiting for it.
    func ageAgentCode(_ id: String, by seconds: TimeInterval) {
        guard var code = runtimes[id]?.agentCode else { return }
        code = AgentCode(digits: code.digits, client: code.client, body: code.body, plan: code.plan, expires: code.expires.addingTimeInterval(-seconds), wrong: code.wrong, locked: code.locked)
        runtimes[id]?.agentCode = code
    }

    /// A test's way to let time pass for the agent's window without waiting for it.
    func ageAgentCall(_ id: String, by seconds: TimeInterval) {
        guard let ask = runtimes[id]?.agentAsk else { return }
        runtimes[id]?.agentAsk = (ask.client, ask.at.addingTimeInterval(-seconds))
    }
}
