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
                $0.askEachTimeOnline = { (try? await permissions.policy(now: clock.now))?.internet == .askEachTime }
            }
            for (name, risk, caps, mutates) in [("notes.save", Risk.low, Set<Capability>([.notebook]), true), ("notes.search", .low, [.notebook], false),
                                                ("notify.user", .low, [], false), ("ask.user", .low, [], false), ("web.fetch", .low, [.network], false), ("watch.create", .low, [.watch], true)] {
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
        #expect(words.contains("body: “[from “Read the page · web.fetch”; it may also be left out]”"), "\(words)")
        #expect(words.contains("Outside content: Words from “Read the page · web.fetch” go into body of “Create an issue”"), "\(words)")
        #expect(await reply["standing"]?.arrayValue?.compactMap(\.boolValue) == [true, true])
        let run = await w.ask("sidefolk/tools.call", ["tool": "ext.hub.post", "plan": "digest", "input": ["repo": "me/digest", "title": "Weekly digest", "body": "page words"]])
        #expect(run["standing"]?.boolValue == true && run["text"]?.stringValue == "posted", "\(run)")
        #expect(await w.h.env.broker.pending().isEmpty)
        let row = try await w.rows("ext.hub.post").first
        #expect(row?.args?["_filled_from"]?.stringValue == "body from page (outside content)", "History says where the words came from: \(String(describing: row?.args))")
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
        #expect(ExtensionPlanRules.fieldClass("body", schema: ["type": "object"], whole: true) == .other, "a whole value of any other kind may carry a place inside")
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
        #expect(busy >= 5, "a loop of plan.check can't starve the host: \(busy)")
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
        #expect(decide(name: ExtensionPlanTool.name, answer: .fullAccess, mode: .fullAccess) == .allow(.fullAccess))
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
        #expect(text.contains("it may also be a list, a record, a number, or left out") == false, "a whole value is only said where it is whole")
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

    @Test func aServersToolCountsAsReadingYourThingsForTheWarningOnlyBeforeALineItFeeds() async throws {
        let w = try await World()
        _ = try server(w)
        let spec = ToolSpec(name: "ext.hub.search", title: "Search mail", description: "", inputSchema: Schema.object(["query": Schema.string("Query")]),
                            risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        w.h.env.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.hub", extensionName: "GitHub", remoteName: "search", sandboxed: false) { _, _ in ToolResult(text: "") })
        let mail: JSONValue = ["tool": "ext.hub.search", "as": "mail", "input": ["query": "invoices"]]
        let plan = Self.plan([Self.page, mail, Self.post(["body": "{{page}} {{mail}}"])])
        #expect(await w.check(plan)["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing", "a server's read may hold your own things")
        #expect(await w.check(Self.plan([Self.page, Self.post(["body": "{{page}}"])]))["steps"]?.arrayValue?.last?["warning"] == nil, "the line itself isn't what it reads")
        #expect(await w.check(Self.plan([Self.post(["body": "{{page}}"]), mail, Self.page]))["steps"]?.arrayValue?.first?["warning"] == nil, "what comes after can't feed it")
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

    @Test func aPlanNobodyUsedFor60DaysEndsAndItsProgramIsTold() async throws {
        let w = try await World()
        _ = await w.approve(Self.plan([Self.save]))
        let old = Date().addingTimeInterval(-61 * 24 * 3600)
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["digest"]?.approvedAt = old }
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.isEmpty == true, "an idle plan is not live: it stands for nothing")
        // The next time its extension asks anything, the plan is taken away for good and its program told.
        _ = await w.ask("sidefolk/tools.list")
        #expect(await w.h.host.loadPreferences("com.example.flow").plans["digest"] == nil)
        // One used a month ago is fine.
        _ = await w.approve(Self.plan([Self.save], id: "recent"))
        await w.h.host.updatePreferences("com.example.flow") { $0.plans["recent"]?.lastUsed = Date().addingTimeInterval(-30 * 24 * 3600); $0.plans["recent"]?.approvedAt = old }
        _ = await w.ask("sidefolk/tools.list")
        #expect(await w.h.host.info(id: "com.example.flow")?.plans.map(\.id) == ["recent"], "use keeps it")
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
        #expect(mine?["state"]?.stringValue == "stands", "\(String(describing: mine))")
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
        #expect(checked["steps"]?.arrayValue?.last?["state"]?.stringValue == "stands", "the person's answer, passed down 90 steps, is still theirs")
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
        func state(_ steps: [JSONValue], _ field: String) async -> String? {
            await w.check(Self.plan(steps + [Self.post([field: "{{a}}"])]))["steps"]?.arrayValue?.last?["state"]?.stringValue
        }
        let ab: [JSONValue] = [["kind": "value", "as": "a", "reads": ["b"]], ["kind": "value", "as": "b", "reads": ["a"]]]
        #expect(await state(ab, "command") == "refused", "two steps reading each other")
        #expect(await state([["kind": "value", "as": "a", "reads": ["nobody"]]], "command") == "refused", "a name no step makes")
        let ask: JSONValue = ["tool": "ask.user", "as": "who", "input": ["question": "Where?"]]
        #expect(await state([["kind": "value", "as": "a", "reads": ["later"]], ask, ["kind": "value", "as": "later", "reads": ["who"]]], "command") == "stands",
                "a name a LATER step makes is that step's, read the same way as an earlier one")
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
