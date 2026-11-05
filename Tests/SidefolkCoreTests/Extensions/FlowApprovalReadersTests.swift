import Foundation
@testable import SidefolkCore
import Testing

/// What the second independent readers found in flow approval (D186–D189, T53): a click answers a plan only while its own call runs, outside content
/// from a file or the clipboard counts for the warning, what Auto let through stands only in Auto, and the rest of the readers' lows, each of which fails
/// without the protection it tests.
@Suite struct FlowApprovalReadersTests {
    typealias World = FlowApprovalTests.World
    static let id = "com.example.flow"

    // MARK: A click answers one plan, while its call runs

    @Test func aClickOnAnUnrelatedControlLeavesNothingToAnswerAnotherPlanWith() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        // The person pressed something else of the extension's (a button that returns at once).
        _ = await w.ask("sidefolk/tools.list")
        let later = await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save, FlowApprovalTests.fetch]), caller: .agent(runId: "r1"))
        #expect(later.asked, "that click is over: a plan that comes after it is read in full")
        let timer = await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save], id: "again"), caller: .agent(runId: "r2"))
        #expect(timer.asked)
    }

    @Test func aClickAnswersAPlanOnlyWhileItsOwnCallIsRunning() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        let click = await w.h.host.notePersonCall(Self.id, caller: .user, tainted: false)
        #expect(click != nil)
        // While the call that click made is running, the plan it asks for is answered, once.
        #expect(await !w.approve(FlowApprovalTests.plan([FlowApprovalTests.save]), caller: .agent(runId: "r1")).asked)
        #expect(await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save], id: "second"), caller: .agent(runId: "r2")).asked, "and only once")
        let other = await w.h.host.notePersonCall(Self.id, caller: .user, tainted: false)
        await w.h.host.endPersonClick(Self.id, try #require(other))
        #expect(await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save], id: "third"), caller: .agent(runId: "r3")).asked, "a call that has returned answers nothing")
        await w.h.host.endPersonClick(Self.id, try #require(click))
    }

    @Test func aCleanTurnOfTheAgentIsNotAClickAndATaintedOneIsNotEvenAsked() async throws {
        let w = try await World()
        try await w.setMode(.fullAccess)
        #expect(await w.h.host.notePersonCall(Self.id, caller: .agent(runId: "r1"), tainted: false) == nil)
        #expect(await w.h.host.notePersonCall(Self.id, caller: .command(extensionId: "com.example.other"), tainted: false) == nil)
        let tainted = await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save]), caller: .agent(runId: "r2"))
        #expect(tainted.asked)
    }

    // MARK: Outside content from files, the clipboard and other apps

    @Test func filesTheClipboardAndOtherAppsAreOutsideContentForTheWarning() async throws {
        let w = try await World()
        _ = try w.registerHub()
        let notes: JSONValue = ["tool": "notes.search", "as": "mine", "input": ["query": "plans"]]
        for (tool, name) in [("files.read", "file"), ("clipboard.read", "clip"), ("applenotes.read", "apple"), ("calendar.today", "day")] {
            let read: JSONValue = ["tool": .string(tool), "as": .string(name), "input": [:]]
            let plan = FlowApprovalTests.plan([notes, read, FlowApprovalTests.post(["body": .string("{{\(name)}}")])])
            let checked = await w.check(plan)
            #expect(checked["steps"]?.arrayValue?.last?["warning"]?.stringValue == "crossing", "\(tool): \(checked)")
        }
        // Only the person's own things, written by nobody else, leave nothing to warn of.
        let own = await w.check(FlowApprovalTests.plan([notes, FlowApprovalTests.post(["body": "{{mine}}"])]))
        #expect(own["steps"]?.arrayValue?.last?["warning"] == nil, "\(own)")
    }

    // MARK: What Auto let through stands only while Auto is on

    @Test func whatAutoLetThroughWithNoCardStandsOnlyWhileAutoIsOn() async throws {
        let w = try await World()
        try await w.setMode(.auto)
        #expect(await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save])).asked, "the first time, the card")
        let second: JSONValue = ["tool": "watch.create", "input": ["interval_minutes": 5]]
        let edit = FlowApprovalTests.plan([FlowApprovalTests.save, second])
        #expect(await !w.approve(edit).asked, "Auto: a note stays inside Sidefolk")
        let call: JSONValue = ["tool": "watch.create", "plan": "digest", "input": ["interval_minutes": 5]]
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true, "it runs while Auto is on")
        try await w.setMode(.askOncePerKind)
        async let after = w.ask("sidefolk/tools.call", call)
        #expect(await w.answerCard(.deny) != nil, "nobody read it, and the mode that let it through is gone")
        #expect(await after["standing"]?.boolValue == false)
        // The next edit shows it as new, and once read it stands in every mode.
        async let reread = w.ask("sidefolk/plan.approve", ["plan": edit])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains("interval_minutes"), "the line nobody read is shown again: \(words)")
        #expect(await reread["ok"]?.boolValue == true)
        #expect(await w.ask("sidefolk/tools.call", call)["standing"]?.boolValue == true)
    }

    @Test func autoStillAsksForWhatLeavesTheMacOrCantBeUndone() async throws {
        let w = try await World()
        try await w.setMode(.auto)
        _ = await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save]))
        let delete: JSONValue = ["tool": "files.trash", "input": ["path": "/tmp/x"]]
        #expect(await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save, delete])).asked, "a high-risk step is never skipped")
        #expect(await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save, FlowApprovalTests.fetch], id: "web")).asked, "an address leaves the Mac")
    }

    // MARK: A claim is the extension's word

    @Test func aFieldNewlySaidToBeTheirsIsNewAndNeverCoveredByTheWordsItWasBefore() async throws {
        let w = try await World()
        _ = try w.registerHub()
        let outside = FlowApprovalTests.plan([FlowApprovalTests.page, FlowApprovalTests.post(["body": "{{page}}"])])
        _ = await w.approve(outside)
        var fields = FlowApprovalTests.post(["body": "{{page}}"]).objectValue ?? [:]
        fields["from"] = ["body": "person"]
        let claimed = JSONValue.object(fields)
        async let reply = w.ask("sidefolk/plan.approve", ["plan": FlowApprovalTests.plan([FlowApprovalTests.page, claimed])])
        let card = await w.answerCard(.deny)
        #expect(card != nil, "page words relabelled as the person's own are something new")
        #expect(await reply["ok"]?.boolValue == false)
    }

    // MARK: Words rebound in a field the table opens

    @Test func anOpenFieldWhoseWordsNowComeFromOutsideIsNew() async throws {
        let w = try await World()
        let ask: JSONValue = ["tool": "ask.user", "as": "answer", "input": ["question": "What?"]]
        func plan(_ title: String) -> JSONValue { FlowApprovalTests.plan([ask, FlowApprovalTests.page, ["tool": "notify.user", "input": ["title": .string(title)]]]) }
        _ = await w.approve(plan("{{answer}}"))
        #expect(await !w.approve(plan("{{answer}} again")).asked, "other words of their own are fine")
        async let rebound = w.ask("sidefolk/plan.approve", ["plan": plan("{{page}}")])
        let card = await w.answerCard(.deny)
        #expect(card != nil, "the notice now says what a page says")
        #expect(await rebound["ok"]?.boolValue == false)
    }

    // MARK: Terms

    @Test func everyWayTheTermsGrowAsksAndSavingTheShorterOnesDoesNot() async throws {
        let w = try await World()
        func plan(perRun: Int? = nil, ttl: Int? = nil, round: Bool = false, when: String = "Every Monday") -> JSONValue {
            var fields = FlowApprovalTests.plan([FlowApprovalTests.save], when: when, perRun: perRun).objectValue ?? [:]
            if let ttl { fields["ttl"] = .number(Double(ttl)) }
            if round { fields["goes_round"] = true }
            return .object(fields)
        }
        _ = await w.approve(plan(perRun: 10, ttl: 600))
        #expect(await !w.approve(plan(perRun: 5, ttl: 300)).asked, "fewer and shorter is narrower")
        for (label, wider) in [("more in a run", plan(perRun: 20, ttl: 600)), ("longer", plan(perRun: 10, ttl: 3000)), ("no end", plan(perRun: 10)),
                               ("goes round", plan(perRun: 10, ttl: 600, round: true)), ("another way of starting", plan(perRun: 10, ttl: 600, when: "Every minute"))] {
            async let reply = w.ask("sidefolk/plan.approve", ["plan": wider])
            #expect(await w.answerCard(.deny) != nil, "\(label)")
            _ = await reply
        }
    }

    // MARK: The card

    @Test func aLongListOfSourcesIsCutWithTheCountOfWhatWasLeftOut() async throws {
        let w = try await World()
        _ = try w.registerHub()
        var steps: [JSONValue] = []
        for i in 0..<30 {
            steps.append(["tool": "web.fetch", "as": .string("s\(i)"), "title": .string("Source number \(i) with a long and descriptive title"),
                          "input": ["url": .string("https://news.example.com/\(i)")]])
        }
        let body = (0..<30).map { "{{s\($0)}}" }.joined()
        steps.append(FlowApprovalTests.post(["body": .string(body)]))
        async let reply = w.ask("sidefolk/plan.approve", ["plan": FlowApprovalTests.plan(steps)])
        let card = await w.answerCard(.allowOnce)
        guard case .text(let words)? = card?.details else { Issue.record("a card"); return }
        #expect(words.contains(" more)"), "the cut says how many it left out: \(words)")
        _ = await reply
    }

    @Test func aProgramThatEndedThePlanMeanwhileIsNotBroughtBackByAnEditNobodyAskedFor() async throws {
        let w = try await World()
        _ = await w.approve(FlowApprovalTests.plan([FlowApprovalTests.save, FlowApprovalTests.fetch]))
        async let reply = w.ask("sidefolk/plan.approve", ["plan": FlowApprovalTests.plan([FlowApprovalTests.save, FlowApprovalTests.fetch, ["tool": "notify.user", "input": ["title": "New"]]])])
        var card: ApprovalRequest?
        for _ in 0..<200 where card == nil {
            card = await w.h.env.broker.pending().first
            if card == nil { try? await Task.sleep(for: .milliseconds(25)) }
        }
        let shown = try #require(card)
        await w.h.host.endPlan(extensionId: Self.id, plan: "digest")
        await w.h.env.broker.resolve(id: shown.id, decision: .allowOnce)
        let answered = await reply
        #expect(answered["ok"]?.boolValue == false && answered["reason"]?.stringValue == "changed", "\(answered)")
        #expect(await w.h.host.planInfos(Self.id).isEmpty, "what they ended stays ended")
    }

    // MARK: Words the card shows are the bytes

    @Test func plainWritingThatLooksLikeSomethingElseIsNotShownAsPlain() {
        for ok in ["Hello", "Привет мир", "Ελλάδα", "👨\u{200D}👩\u{200D}👧", "می\u{200C}خواهم", "Ok ✔\u{FE0F}", "1\u{FE0F}\u{20E3}"] {
            #expect(ExtensionPlanRules.plain(ok), "\(ok.unicodeScalars.map(\.value))")
        }
        for bad in ["A\u{FE0F}", "a\u{200D}b", "→\u{200D}→", "x\u{2800}y", "\u{2800}", "a\u{E000}b", "pаypal", "a\u{200C}\u{200D}b", "\u{FE0F}", "ab\u{0378}c"] {
            #expect(!ExtensionPlanRules.plain(bad), "should be refused: \(bad.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }

    @Test func aKeySpelledAnotherWayIsAnotherKey() {
        let composed = "caf\u{E9}", decomposed = "cafe\u{301}"
        #expect(composed == decomposed, "Swift calls them equal")
        let template: JSONValue = .object([composed: .string("{{x}}")])
        #expect(ExtensionPlanRules.matches(.object([composed: "words"]), template: template, fillable: [composed]))
        #expect(!ExtensionPlanRules.matches(.object([decomposed: "words"]), template: template, fillable: [composed]), "a server reads the other spelling as another field")
    }

    @Test func aNameThatRunsSomethingIsCodeWhateverItIsCalled() {
        for code in ["arguments", "executable", "binary", "cmdline", "flags", "options", "env", "prompt", "task", "run", "sh", "statement", "extraArgs", "runTask"] {
            #expect(ExtensionPlanRules.fieldClass(code, schema: ["type": "string"]) == .code, "\(code)")
        }
        for plain in ["body", "title", "message", "summary"] {
            #expect(ExtensionPlanRules.fieldClass(plain, schema: ["type": "string"]) == .freeText, "\(plain)")
        }
    }

    @Test func aSlotNamingAStepThatComesLaterIsOutside() {
        let later: [(name: String?, tool: String, kind: String?, reads: [String]?)] = [("a", "web.fetch", nil, nil)]
        #expect(ExtensionPlanRules.sources(of: ["title": "{{answer}}"], steps: later, inside: [])["title"] == "outside", "a name no earlier step makes is outside")
        let ask: [(name: String?, tool: String, kind: String?, reads: [String]?)] = [("answer", "ask.user", nil, nil)]
        #expect(ExtensionPlanRules.sources(of: ["title": "{{answer}}"], steps: ask, inside: [])["title"] == "inside")
    }

    @Test func aPolicyThatCantBeReadIsNotAPermission() {
        let unreadable = ExtensionHost.FlowPolicy(policy: nil)
        #expect(unreadable.mode == .askEveryTime && !unreadable.mayPassToServers)
        let normal = ExtensionHost.FlowPolicy(policy: GuardPolicy())
        #expect(normal.mode == .askOncePerKind && normal.mayPassToServers)
    }

    // MARK: Work

    @Test func aPlanAtTheEdgeOfEverythingIsWorkedOutQuickly() async throws {
        let w = try await World()
        _ = try w.registerHub()
        var steps: [JSONValue] = [["tool": "notes.search", "as": "mine", "input": ["query": "plans"]], ["tool": "web.fetch", "as": "p0", "input": ["url": "https://news.example.com/0"]]]
        var names = ["p0"]
        for i in 1..<60 {
            steps.append(["tool": "web.fetch", "as": .string("p\(i)"), "input": ["url": .string("https://news.example.com/\(i)")]])
            names.append("p\(i)")
        }
        for i in 0..<60 {
            steps.append(["kind": "ai", "as": .string("w\(i)"), "reads": .array(names.map { .string($0) })])
        }
        for i in 0..<60 {
            steps.append(["kind": "value", "as": .string("v\(i)"), "reads": .array((0..<60).map { .string("w\($0)") })])
            steps.append(FlowApprovalTests.post(["body": .string("{{v\(i)}}"), "title": .string("Line \(i)")]))
        }
        let started = ContinuousClock.now
        let checked = await w.check(FlowApprovalTests.plan(steps))
        #expect(ContinuousClock.now - started < .seconds(5), "the work is the size of the plan")
        #expect(checked["ok"]?.boolValue != nil)
    }
}

extension FlowApprovalTests.World {
    /// The server the flow tests send to, with a program that can be checked.
    func registerHub() throws -> String {
        let path = h.root.appendingPathComponent("hub-server").path
        try? FileManager.default.copyItem(atPath: "/bin/ls", toPath: path)
        let spec = ToolSpec(name: "ext.hub.post", title: "Create an issue", description: "", inputSchema: Schema.object([
            "repo": Schema.string("Repository"), "title": Schema.string("Title"), "body": Schema.string("Body")]),
                            risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        h.env.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.hub", extensionName: "GitHub", remoteName: "post", program: path, sandboxed: false) { _, _ in
            ToolResult(text: "posted")
        })
        return path
    }
}
