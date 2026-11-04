import Foundation
@testable import SidefolkCore
import Testing

/// One approval for a flow (D186–D189, T53): the plan the person read covers what an edit leaves alone, asks only about what is new, and Full access
/// answers a signed extension's plan for the person's own click. Server calls stand when named and checked. Words from outside never choose where a
/// call goes or what it runs.
@Suite struct FlowApprovalTests {
    final class World: @unchecked Sendable {
        let h: HostEnv
        let gateway: ExtensionActionGateway
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
                    return ExtensionHost.FlowPolicy(mode: policy?.mode ?? .askOncePerKind, mayPassToServers: policy?.flowsMayPassToServers ?? true)
                }
            }
            for (name, risk, caps, mutates) in [("notes.save", Risk.low, Set<Capability>([.notebook]), true), ("notes.search", .low, [.notebook], false),
                                                ("notify.user", .low, [], false), ("web.fetch", .low, [.network], false), ("watch.create", .low, [.watch], true)] {
                h.env.registry.register(ExtensionActionsTests.Probe(name: name, risk: risk, capabilities: caps, mutates: mutates, urlParameter: name == "web.fetch" ? "url" : nil))
            }
            h.env.registry.register(ExtensionPlanEndTool(host: h.host))
            let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name.capitalized), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                       "permissions": ["act": ["purpose": "to run what you set up"]], "tools": ["ask_host": ["title": "Ask the host", "risk": "low", "mutates": false]]]
            try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": ExtensionActionsTests.bridge]), origin: origin)
            tool = "ext.\(name).ask_host"
        }

        func setMode(_ mode: GuardMode) async throws { try await h.env.permissions.updatePolicy { $0.mode = mode } }

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
            async let reply = ask("sidefolk/plan.approve", ["plan": plan], caller: caller)
            let card = await answerCard(.allowOnce, wait: 40)
            return (await reply, card != nil)
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
        #expect(words.contains("Already allowed, unchanged: 2 things"), "\(words)")
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
        #expect(setWords.contains("Morning brief, which has its own approval"), "\(setWords)")
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
        #expect(checked["steps"]?.arrayValue?[2]["why"]?.stringValue == "filled_value")
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
        #expect(try await w.rows("extensions.plan").first?.decision == .fullAccess, "History says Full access answered")
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
        #expect(try await w.rows("extensions.plan").first?.decision == .plan)
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
        #expect(words.contains("body: “[from “Read the page”]”"), "\(words)")
        #expect(words.contains("Outside content: Words from “Read the page” go into body of “Create an issue”"), "\(words)")
        #expect(await reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true, true])
        let run = await w.ask("sidefolk/tools.call", ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "page words"]])
        #expect(run["standing"]?.boolValue == true && run["text"]?.stringValue == "posted", "\(run)")
        #expect(await w.h.env.broker.pending().isEmpty)
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

    @Test func aServerThatCantBeCheckedAsksEveryTime() async throws {
        let w = try await World()
        _ = try server(w, program: "/usr/bin/env")
        let checked = await w.check(Self.plan([Self.post([:])]))
        #expect(checked["steps"]?.arrayValue?.first?["state"]?.stringValue == "asks")
        #expect(checked["steps"]?.arrayValue?.first?["why"]?.stringValue == "server_unpinned")
        let npx = try server(w, program: "/usr/local/bin/npx")
        #expect(ProgramPin.hash(of: npx) == nil && ProgramPin.hash(of: "node") == nil && ProgramPin.hash(of: "/bin/ls") != nil)
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
        #expect(inside == ["repo": "inside", "body": "outside", "title": "inside"])
        #expect(ExtensionPlanRules.sources(of: ["repo": "{{form.x}}"], earlier: ask, inside: [])["repo"] == "outside", "a name the host can't place is outside")
        #expect(ExtensionPlanRules.sources(of: ["repo": "{{x}}"], earlier: ask, inside: [], fromPerson: ["repo"])["repo"] == "inside")
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

    @Test func readingYourOwnThingsAndOutsideWordsThenSendingThemOnStandsOnlyInFullAccess() async throws {
        let w = try await World()
        _ = try server(w)
        let notes: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
        let plan = Self.plan([notes, Self.page, Self.post(["body": "{{page}}"])])
        let asked = await w.check(plan)
        let last = asked["steps"]?.arrayValue?.last
        #expect(last?["state"]?.stringValue == "stands_in_full_access" && last?["why"]?.stringValue == "crossing", "\(asked)")
        // Drop one leg and it stands.
        #expect(await w.check(Self.plan([Self.page, Self.post(["body": "{{page}}"])]))["steps"]?.arrayValue?.last?["state"]?.stringValue == "stands")
        try await w.setMode(.fullAccess)
        #expect(await w.check(plan)["steps"]?.arrayValue?.last?["state"]?.stringValue == "stands")
        // An AI step is a conduit: it counts as reading what it names, and everything before it when it names nothing.
        try await w.setMode(.askOncePerKind)
        let named: JSONValue = ["kind": "ai", "as": "write", "reads": ["page"]]
        #expect(await w.check(Self.plan([Self.page, named, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["state"]?.stringValue == "stands")
        let everything: JSONValue = ["kind": "ai", "as": "write"]
        #expect(await w.check(Self.plan([notes, Self.page, everything, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["why"]?.stringValue == "crossing")
        #expect(await w.check(Self.plan([Self.page, everything, Self.post(["body": "{{write}}"])]))["steps"]?.arrayValue?.last?["why"]?.stringValue == "crossing",
                "no names: it may have read your own things too")
    }

    @Test func anotherExtensionsPlanNeverHoldsAServerLine() async throws {
        let w = try await World(origin: nil, name: "stranger")
        _ = try server(w)
        let checked = await w.check(Self.plan([Self.post([:])]))
        #expect(checked["steps"]?.arrayValue?.first?["state"]?.stringValue == "asks", "\(checked)")
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
