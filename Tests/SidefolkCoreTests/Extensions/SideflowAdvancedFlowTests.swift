import Foundation
import Synchronization
@testable import SidefolkCore
import Testing

/// One long, realistic flow, month-end invoices, run for real: Sideflow's own program in its sandbox, another extension's tools through Guard, plans through the host.
/// A throwaway home and folders, a scripted world, no windows. What it does is read back from what the tools logged and what the run wrote down.
@Suite(.enabled(if: ExtFixtures.addonFolders.contains("sideflow"), ExtFixtures.noAddons), .serialized) struct SideflowAdvancedFlowTests {
    /// A ledger the flow works on: it keeps a log of everything asked of it, and does as `set_mode` says.
    static let ledger = #"""
    import json, os, sys
    DATA = os.environ["SIDEFOLK_DATA_DIR"]
    LOG, MODE, STATUS = DATA + "/log.jsonl", DATA + "/mode.json", DATA + "/status"
    def send(m): sys.stdout.write(json.dumps(m) + "\n"); sys.stdout.flush()
    def mode(): return json.load(open(MODE)) if os.path.exists(MODE) else {}
    def log(tool, args):
        with open(LOG, "a") as f: f.write(json.dumps({"tool": tool, "args": args}) + "\n")
    words = {"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"], "additionalProperties": False}
    none = {"type": "object", "additionalProperties": False}
    tools = [
        {"name": "invoices", "title": "List invoices", "inputSchema": none, "outputSchema": {"type": "object", "properties": {"items": {"type": "array"}, "total": {"type": "integer"}, "owner": {}}}},
        {"name": "pay", "title": "Pay an invoice", "inputSchema": words},
        {"name": "refund", "title": "Refund", "inputSchema": words},
        {"name": "flag", "title": "Flag for a person", "inputSchema": words},
        {"name": "send_to", "title": "Send to someone", "inputSchema": {"type": "object", "properties": {"to": {"type": "string"}, "reason": {"type": "string"}}, "required": ["to"], "additionalProperties": False}},
        {"name": "status", "title": "Check it settled", "inputSchema": none, "outputSchema": {"type": "object", "properties": {"state": {"type": "string"}}}},
        {"name": "set_mode", "title": "Set mode", "inputSchema": {"type": "object", "additionalProperties": True}},
        {"name": "release", "title": "Let go", "inputSchema": none},
        {"name": "read_log", "title": "Read log", "inputSchema": none},
    ]
    held = []
    def answer(i, text, data=None, error=False):
        r = {"content": [{"type": "text", "text": text}]}
        if data is not None: r["structuredContent"] = data
        if error: r["isError"] = True
        send({"jsonrpc": "2.0", "id": i, "result": r})
    for line in sys.stdin:
        m = json.loads(line)
        if m.get("method") == "initialize":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "ledger", "version": "1"}}})
        elif m.get("method") == "tools/list":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"tools": tools}})
        elif m.get("method") == "notifications/cancelled":
            log("cancelled", {})
        elif m.get("method") == "tools/call":
            i, name, a = m["id"], m["params"]["name"], m["params"].get("arguments", {})
            md = mode()
            if name == "read_log":
                answer(i, open(LOG).read() if os.path.exists(LOG) else "")
            elif name == "set_mode":
                json.dump(a, open(MODE, "w")); answer(i, "ok")
            elif name == "release":
                for h in held: answer(h, "Paid late")
                del held[:]
                answer(i, "ok")
            elif name == "invoices":
                log(name, a)
                items = [{"id": "INV-1", "amount": 120, "kind": "invoice"}, {"id": "INV-2", "amount": 900, "kind": "invoice"}, {"id": "R-1", "amount": 30, "kind": "refund"}, {"id": "N-1", "amount": 5, "kind": "note"}]
                if md.get("empty"): items = []
                answer(i, "%d open" % len(items), {"items": items, "total": len(items), "owner": None})
            elif name == "status":
                log(name, a)
                n = int(open(STATUS).read()) + 1 if os.path.exists(STATUS) else 1
                open(STATUS, "w").write(str(n))
                state = "settled" if n >= 2 and not md.get("never") else "pending"
                answer(i, "It is " + state, {"state": state})
            elif name == "pay":
                log(name, a)
                token = m["params"].get("_meta", {}).get("progressToken")
                if md.get("hold"):
                    if token: send({"jsonrpc": "2.0", "method": "notifications/progress", "params": {"progressToken": token, "progress": 1, "total": 3, "message": "At the bank"}})
                    held.append(i)
                elif md.get("fail") and md["fail"] in a.get("reason", ""):
                    answer(i, "Card declined", error=True)
                else:
                    answer(i, "Paid " + a.get("reason", ""))
            elif name == "refund":
                log(name, a)
                if md.get("no_refund"): answer(i, "Bank closed", error=True)
                else: answer(i, "Refunded " + a.get("reason", ""))
            elif name == "flag":
                log(name, a); answer(i, "Nobody home", error=True)
            elif name == "send_to":
                log(name, a); answer(i, "Sent")
            else:
                answer(i, "?", error=True)
        elif "id" in m:
            send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
    """#

    static let manifest: JSONValue = ["id": "com.example.ledger", "name": "Ledger", "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]], "tools": [
        "invoices": ["title": "List invoices", "risk": "low", "mutates": false],
        "pay": ["title": "Pay an invoice", "risk": "low", "mutates": true, "timeout": 60],
        "refund": ["title": "Refund", "risk": "low", "mutates": true],
        "flag": ["title": "Flag for a person", "risk": "low", "mutates": true],
        "send_to": ["title": "Send to someone", "risk": "low", "mutates": true],
        "status": ["title": "Check it settled", "risk": "low", "mutates": false],
        "set_mode": ["title": "Set mode", "risk": "low", "mutates": true],
        "release": ["title": "Let go", "risk": "low", "mutates": true],
        "read_log": ["title": "Read log", "risk": "low", "mutates": false],
    ]]

    /// Month end: ask who's closing and up to how much pays by itself. List what's open, biggest first. Stop early if there's nothing. For each: an invoice is another flow's job, which
    /// holds one over the limit, pays one under it and notes a payment that fails; a refund is another flow's too, and if that fails the rest still go on; anything else is flagged, and
    /// if flagging fails that's noted. Then wait until the ledger says it settled, at most five looks. Flag a courtesy note, going on if that fails. Do two things side by side: count
    /// them, and tell the person. Who owns it, or "nobody" if no one. Save the lot in a note.
    static let monthEnd: JSONValue = ["trigger": ["type": "manual"], "steps": [
        ["id": "who", "form": ["title": "Month end", "fields": [["name": "owner", "label": "Who's closing", "kind": "text"], ["name": "limit", "label": "Pays by itself up to", "kind": "number"]]]],
        ["id": "list", "do": "ext.ledger.invoices"],
        ["id": "ahead", "text": "Month end for {{who.owner}}: {{list}}"],
        ["id": "gate", "if": ["value": "{{list.total}}", "test": "less_than", "than": "1"], "then": [["id": "none", "finish": "Nothing to do"]], "else": []],
        ["id": "sorted", "data": ["op": "sort", "from": "{{list.items}}", "field": "amount", "descending": true]],
        ["id": "each", "for_each": "{{sorted}}", "limit": 10, "item_failure": "collect", "steps": [
            ["id": "way", "choose": "{{item.kind}}", "paths": [
                ["when": "invoice", "steps": [["id": "one", "call_flow": "Pay one", "inputs": ["id": "{{item.id}}", "amount": "{{item.amount}}", "limit": "{{who.limit}}"]]]],
                ["when": "refund", "steps": [["id": "back", "call_flow": "Refund", "inputs": ["ref": "{{item.id}}"]]]],
            ], "else": [["id": "flagging", "try": [["id": "odd", "do": "ext.ledger.flag", "with": ["reason": "Odd {{item.id}}"]]], "recover": [["id": "cant", "text": "could not flag {{item.id}}: {{error}}"]]]]],
        ]],
        ["id": "lines", "data": ["op": "join", "from": "{{each}}", "separator": " / "]],
        ["id": "poll", "repeat": [["id": "look", "do": "ext.ledger.status"]], "until": ["value": "{{look.state}}", "test": "is", "than": "settled"], "times": 5],
        ["id": "courtesy", "do": "ext.ledger.flag", "with": ["reason": "Courtesy"], "on_failure": "carry_on"],
        ["id": "both", "parallel": [
            ["name": "count", "steps": [["id": "counted", "data": ["op": "count", "from": "{{sorted}}"]]]],
            ["name": "tell", "steps": [["id": "told", "do": "notify.user", "with": ["title": "Month end", "body": "{{ahead}}"]]]],
        ]],
        ["id": "owner", "data": ["op": "fallback", "from": "{{list.owner}}", "than": "nobody"]],
        ["id": "save", "do": "notes.save", "with": ["text": "{{ahead}} | {{lines}} | {{poll}} | count {{both.count}} | owner {{owner}}"]],
    ]]

    /// What paying one invoice takes, on its own: over the limit it's held; otherwise it's paid, and a payment that fails is noted.
    static let payOne: JSONValue = ["trigger": ["type": "manual"], "steps": [
        ["id": "over", "if": ["value": "{{input.amount}}", "test": "more_than", "than": "{{input.limit}}"], "then": [["id": "held", "text": "held {{input.id}}"]], "else": [
            ["id": "attempt", "try": [["id": "paid", "do": "ext.ledger.pay", "with": ["reason": "Invoice {{input.id}}"]]], "recover": [["id": "missed", "text": "missed {{input.id}}: {{error}}"]]],
        ]],
    ]]

    static let refund: JSONValue = ["trigger": ["type": "manual"], "steps": [["id": "back", "do": "ext.ledger.refund", "with": ["reason": "Back {{input.ref}}"]]]]

    /// The question a stopped run asks, and the person's answer to it.
    final class Asked: Sendable {
        let questions = Mutex<[JSONValue]>([])
        let answer = Mutex<String>("Stop here")
    }

    struct AskProbe: Tool {
        let asked: Asked
        var spec: ToolSpec {
            ToolSpec(name: "ask.user", title: "Ask you", description: "", inputSchema: ["type": "object", "properties": ["question": ["type": "string"], "options": ["type": "array", "items": ["type": "string"]], "timeout_seconds": ["type": "integer"]], "required": ["question"]],
                     risk: .low, capabilities: [], category: .agents, mutates: false)
        }
        func summary(for input: JSONValue) -> String { "Ask" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            asked.questions.withLock { $0.append(input) }
            return ToolResult(text: asked.answer.withLock { $0 })
        }
    }

    struct TellProbe: Tool {
        let told: SideflowSandboxTests.World.Saved
        var spec: ToolSpec {
            ToolSpec(name: "notify.user", title: "Notify the user", description: "", inputSchema: Schema.object(["title": Schema.string("t"), "body": Schema.string("b")], required: ["title"]),
                     risk: .low, capabilities: [], category: .agents, mutates: false)
        }
        func summary(for input: JSONValue) -> String { "Notify" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            told.withLock { $0.append(input) }
            return ToolResult(text: "Shown.")
        }
    }

    final class World: @unchecked Sendable {
        let h: HostEnv
        let saved = SideflowSandboxTests.World.Saved()
        let told = SideflowSandboxTests.World.Saved()
        let asked = Asked()
        let cards = Mutex<[ApprovalRequest]>([])
        let answering = Mutex<Bool>(true)
        var watching: Task<Void, Never>?

        init() async throws {
            let env = try TestEnv()
            let gateway = ExtensionActionGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events)
            let permissions = env.permissions, clock = env.clock
            h = try HostEnv(env: env) {
                $0.actions = gateway
                $0.flowPolicy = {
                    let policy = try? await permissions.policy(now: clock.now)
                    return ExtensionHost.FlowPolicy(mode: policy?.mode ?? .askOncePerKind, mayPassToServers: policy?.flowsMayPassToServers ?? true)
                }
            }
            let saved = saved
            h.env.registry.register(SideflowSandboxTests.NoteProbe(record: { input in saved.withLock { $0.append(input) } }))
            h.env.registry.register(TellProbe(told: told))
            h.env.registry.register(AskProbe(asked: asked))
            try await h.host.install(from: h.source("ledger", manifest: SideflowAdvancedFlowTests.manifest, files: ["server.py": SideflowAdvancedFlowTests.ledger]), origin: .official)
            try await h.host.install(from: ExtFixtures.builtIn("sideflow"), origin: .official)
            let stream = h.env.events.stream()
            let broker = h.env.broker
            watching = Task { [weak self] in
                for await e in stream {
                    guard case .approvalRequested(let r) = e else { continue }
                    self?.cards.withLock { $0.append(r) }
                    if self?.answering.withLock({ $0 }) == true { await broker.resolve(id: r.id, decision: .allowOnce) }
                }
            }
        }

        var cardCount: Int { cards.withLock { $0.count } }
        var log: [(tool: String, reason: String)] {
            get async {
                let text = await h.call("ext.ledger.read_log").okText ?? ""
                return text.split(separator: "\n").compactMap { line in
                    guard let o = try? JSONValue.parse(Data(line.utf8)) else { return nil }
                    return (o["tool"]?.stringValue ?? "", o["args"]?["reason"]?.stringValue ?? "")
                }
            }
        }
        func calls(_ tool: String) async -> [String] { await log.filter { $0.tool == tool }.map(\.reason) }

        func mode(_ m: JSONValue) async { _ = await h.call("ext.ledger.set_mode", m) }

        func until(_ what: String, seconds: Double = 25, _ test: () async -> Bool) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if await test() { return }
                try? await Task.sleep(for: .milliseconds(40))
            }
            Issue.record("timed out waiting for \(what)")
        }

        /// What the run wrote down, read from its own file.
        func run(_ flow: String) -> JSONValue? {
            let folder = h.host.dataFolder(extensionId: "dev.sidefolk.sideflow").appendingPathComponent("runs", isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let found = names.compactMap { try? JSONValue.parse(Data(contentsOf: folder.appendingPathComponent($0))) }.filter { $0["flow_name"]?.stringValue == flow }
            // A lane is a run of the same flow: Month end means the run that was started, and a flow it calls has none but those.
            let runs = flow == "Month end" ? found.filter { $0["parent"] == nil } : found
            return runs.max { ($0["started"]?.doubleValue ?? 0) < ($1["started"]?.doubleValue ?? 0) }
        }
        func status(_ flow: String) -> String? { run(flow)?["status"]?.stringValue }
        func record(_ flow: String, _ step: String) -> JSONValue? { run(flow)?["records"]?.arrayValue?.last { $0["step"]?.stringValue == step } }

        /// What the page's own controls send: a form's answers count only from them.
        func ui(_ input: JSONValue) async {
            var input = input
            if case .object(var fields) = input, let op = fields["op"]?.stringValue, op.hasPrefix("form_"),
               let token = try? String(contentsOf: h.host.dataFolder(extensionId: "dev.sidefolk.sideflow").appendingPathComponent("page-key"), encoding: .utf8) {
                fields["page_token"] = .string(token)
                input = .object(fields)
            }
            _ = await h.call("ext.sideflow.ui", input)
        }

        func answerForm(_ flow: String, owner: String = "Sam", limit: String = "500") async {
            await until("the form") { self.run(flow)?["form"] != nil && self.status(flow) == "waiting" }
            guard let id = run(flow)?["id"]?.stringValue else { return }
            await ui(["op": "form_field", "run": .string(id), "name": "owner", "text": .string(owner)])
            await ui(["op": "form_field", "run": .string(id), "name": "limit", "text": .string(limit)])
            await ui(["op": "form_send", "run": .string(id)])
        }

        func setUp() async throws {
            let made = await h.call("ext.sideflow.create_flow", ["name": "Refund", "definition": SideflowAdvancedFlowTests.refund])
            #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
            let on = await h.call("ext.sideflow.start_flow", ["flow": "Refund"])
            #expect(on.isOK, "\(on.okText ?? on.problem?.message ?? "")")
            await until("Refund to be on") { await self.flowState("Refund") == "on" }
            let one = await h.call("ext.sideflow.create_flow", ["name": "Pay one", "definition": SideflowAdvancedFlowTests.payOne])
            #expect(one.isOK, "\(one.okText ?? one.problem?.message ?? "")")
            let onOne = await h.call("ext.sideflow.start_flow", ["flow": "Pay one"])
            #expect(onOne.isOK, "\(onOne.okText ?? onOne.problem?.message ?? "")")
            await until("Pay one to be on") { await self.flowState("Pay one") == "on" }
            let main = await h.call("ext.sideflow.create_flow", ["name": "Month end", "definition": SideflowAdvancedFlowTests.monthEnd])
            #expect(main.isOK, "\(main.okText ?? main.problem?.message ?? "")")
        }

        func flowState(_ name: String) async -> String? {
            let out = await h.call("ext.sideflow.get_flow", ["flow": .string(name)])
            return out.okText.flatMap { try? JSONValue.parse(Data($0.utf8)) }?["state"]?.stringValue
        }

        func restartSideflow() async throws {
            try await h.host.setEnabled(false, id: "dev.sidefolk.sideflow")
            try await h.host.setEnabled(true, id: "dev.sidefolk.sideflow")
            _ = await h.call("ext.sideflow.list_flows")
        }

        deinit { watching?.cancel() }
    }

    private func started(_ w: World) async {
        let ran = await w.h.call("ext.sideflow.run_flow", ["flow": "Month end"])
        #expect(ran.isOK, "\(ran.okText ?? ran.problem?.message ?? "")")
    }

    // MARK: All of it, as it should go

    @Test func theWholeMonthEndDoesWhatItSays() async throws {
        let w = try await World()
        try await w.setUp()
        let beforeRun = w.cardCount
        await started(w)
        #expect(w.cardCount == beforeRun + 1, "one card, for all of it")
        await w.answerForm("Month end")
        await w.until("it to finish") { w.status("Month end") == "done" || w.status("Month end") == "failed" }
        #expect(w.status("Month end") == "done", "\(w.run("Month end")?["problem"]?.stringValue ?? "")")

        // Biggest first: INV-2 is over the limit, so only INV-1 is paid. The refund went through the other flow. Flagging failed, was noted, and the courtesy flag failed and was carried past.
        #expect(await w.calls("pay") == ["Invoice INV-1"])
        #expect(await w.calls("refund") == ["Back R-1"])
        #expect(await w.calls("flag") == ["Odd N-1", "Courtesy"])
        #expect(await w.calls("status").count == 2, "it looked until it settled, and no more")
        #expect(w.record("Month end", "courtesy")?["status"]?.stringValue == "failed", "it says what failed, and went on")

        let note = w.saved.withLock { $0.last?["text"]?.stringValue } ?? ""
        #expect(note == "Month end for Sam: 4 open | held INV-2 / Paid Invoice INV-1 / Refunded Back R-1 / could not flag N-1: Nobody home | It is settled | count 4 | owner nobody", "\(note)")
        #expect(w.told.withLock { $0.last?["body"]?.stringValue } == "Month end for Sam: 4 open", "the lane had what came before it")
        #expect(w.cardCount == beforeRun + 1)
    }

    @Test func oneCardThenNoneThenOnlyWhatsNew() async throws {
        let w = try await World()
        try await w.setUp()
        await started(w)
        let afterFirst = w.cardCount
        guard case .text(let first)? = w.cards.withLock({ $0.last?.details }) else { Issue.record("a card with words"); return }
        #expect(first.contains("List invoices") && first.contains("Save to notebook"), "\(first)")
        await w.answerForm("Month end")
        await w.until("it to finish") { w.status("Month end") == "done" }

        await started(w)
        await w.answerForm("Month end")
        await w.until("the second to finish") { w.saved.withLock { $0.count == 2 } }
        #expect(w.cardCount == afterFirst, "same flow, nothing to read again")

        // Only words it already writes.
        var edited = try JSONValue.parse(Data(Self.monthEnd.jsonString.replacingOccurrences(of: "Month end for", with: "Closing for").utf8))
        var update = await w.h.call("ext.sideflow.update_flow", ["flow": "Month end", "definition": edited])
        #expect(update.isOK, "\(update.okText ?? update.problem?.message ?? "")")
        await started(w)
        await w.answerForm("Month end")
        await w.until("the third to finish") { w.saved.withLock { $0.count == 3 } }
        #expect(w.cardCount == afterFirst, "words only: nothing new")
        #expect(w.saved.withLock { $0.last?["text"]?.stringValue?.hasPrefix("Closing for") } == true)

        // Something it never did.
        guard var fields = edited.objectValue, var steps = fields["steps"]?.arrayValue else { Issue.record("a flow"); return }
        steps.insert(["id": "extra", "do": "ext.ledger.send_to", "with": ["to": "finance@example.com", "reason": "done"]], at: steps.count - 1)
        fields["steps"] = .array(steps)
        edited = .object(fields)
        update = await w.h.call("ext.sideflow.update_flow", ["flow": "Month end", "definition": edited])
        #expect(update.isOK, "\(update.okText ?? update.problem?.message ?? "")")
        await started(w)
        #expect(w.cardCount == afterFirst + 1, "one card")
        guard case .text(let words)? = w.cards.withLock({ $0.last?.details }) else { Issue.record("a card with words"); return }
        #expect(words.contains("Send to someone"), "\(words)")
        #expect(!words.contains("List invoices") && !words.contains("Save to notebook"), "what's already allowed isn't asked again: \(words)")
        await w.answerForm("Month end")
        await w.until("the fourth to finish") { w.saved.withLock { $0.count == 4 } }
        #expect(await w.calls("send_to").count == 1)
    }

    // MARK: What goes wrong

    @Test func aFailedPaymentIsNotedAndTheRestGoOn() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["fail": "INV-1"])
        await started(w)
        await w.answerForm("Month end")
        await w.until("it to finish") { w.status("Month end") == "done" || w.status("Month end") == "failed" }
        #expect(w.status("Month end") == "done", "\(w.run("Month end")?["problem"]?.stringValue ?? "")")
        #expect(await w.calls("pay").count == 1, "never tried twice by itself")
        #expect(await w.calls("refund") == ["Back R-1"], "the rest went on")
        let note = w.saved.withLock { $0.last?["text"]?.stringValue } ?? ""
        #expect(note.contains("missed INV-1: Card declined"), "\(note)")
    }

    @Test func aCalledFlowThatFailsIsCollectedAndTheRestGoOn() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["no_refund": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("it to finish") { w.saved.withLock { !$0.isEmpty } || w.status("Month end") == "failed" }
        #expect(w.status("Pay one") == "done")
        #expect(w.status("Refund") == "failed")
        #expect(await w.calls("flag") == ["Odd N-1", "Courtesy"], "the item after it still went")
        // Numbers in a sentence come wrapped so they read left to right in any language.
        let said = w.record("Month end", "each")?["summary"]?.stringValue?.filter { !"\u{2068}\u{2069}".contains($0) } ?? ""
        #expect(said == "Went through 4 items; 1 failed", "\(said)")
        #expect(w.saved.withLock { $0.count } == 1)
    }

    @Test func aTrysLastStepsRunWhateverHappened() async throws {
        let w = try await World()
        await w.mode(["fail": "First"])
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Tidy", "definition": ["trigger": ["type": "manual"], "steps": [["id": "t", "try": [["id": "first", "do": "ext.ledger.pay", "with": ["reason": "First"]]], "recover": [["id": "r", "text": "recovered"]], "always": [["id": "tidy", "do": "notes.save", "with": ["text": "tidied"]]]]]]])
        #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Tidy"])
        await w.until("it to finish") { w.status("Tidy") == "done" || w.status("Tidy") == "failed" }
        #expect(w.status("Tidy") == "done")
        #expect(w.record("Tidy", "r") != nil)
        #expect(w.saved.withLock { $0.last?["text"]?.stringValue } == "tidied")
    }

    @Test func tryingAgainFromHereIsOfferedOnlyForWhatDidntHappen() async throws {
        let w = try await World()
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Two", "definition": ["trigger": ["type": "manual"], "steps": [["id": "first", "do": "ext.ledger.pay", "with": ["reason": "First"]], ["id": "second", "do": "ext.ledger.refund", "with": ["reason": "Second"]]]]])
        #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
        func page(_ id: String) async throws -> String { String(describing: try await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: ["run": .string(id)])) }

        // It said it failed: nothing happened, so going on from there is offered, and does just the rest.
        await w.mode(["fail": "First"])
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Two"])
        await w.until("it to fail") { w.status("Two") == "failed" }
        let failed = try #require(w.run("Two")?["id"]?.stringValue)
        #expect(try await page(failed).contains("Try again from here"))
        await w.mode([:])
        await w.ui(["op": "run_again", "run": .string(failed), "here": true])
        await w.until("it to finish") { w.status("Two") == "done" }
        #expect(await w.calls("pay").count == 2)
        #expect(await w.calls("refund") == ["Second"])

        // Stopped in the middle, it may have happened: not offered.
        await w.mode(["hold": true])
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Two"])
        await w.until("the payment to be under way") { await w.calls("pay").count == 3 }
        let stopped = try #require(w.run("Two")?["id"]?.stringValue)
        await w.ui(["op": "stop_run", "run": .string(stopped)])
        await w.until("it to stop") { w.status("Two") == "stopped" }
        #expect(w.record("Two", "first")?["status"]?.stringValue == "unknown")
        #expect(try await !page(stopped).contains("Try again from here"))
    }

    @Test func aRepeatThatNeverSettlesStopsAtItsLimitAndSavesNothing() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["never": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("it to stop") { w.status("Month end") == "failed" || w.status("Month end") == "done" }
        #expect(w.status("Month end") == "failed")
        #expect(await w.calls("status").count == 5, "five looks, the limit")
        #expect(w.saved.withLock { $0.isEmpty }, "what comes after didn't happen")
        #expect(w.run("Month end")?["problem"]?.stringValue?.contains("5") == true)
    }

    @Test func nothingOpenEndsEarlyAndSaysSo() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["empty": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("it to finish") { w.status("Month end") == "done" }
        #expect(await w.calls("pay").isEmpty)
        #expect(w.saved.withLock { $0.isEmpty })
        #expect(w.run("Month end")?["output"]?.stringValue == "Nothing to do")
    }

    @Test func aValueWithNothingInItNeverReachesAWrite() async throws {
        let w = try await World()
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Null", "definition": ["trigger": ["type": "manual"], "steps": [["id": "list", "do": "ext.ledger.invoices"], ["id": "s", "do": "ext.ledger.send_to", "with": ["to": "{{list.owner}}"]], ["id": "after", "do": "notes.save", "with": ["text": "after"]]]]])
        #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Null"])
        await w.until("it to stop") { w.status("Null") == "failed" }
        #expect(await w.calls("send_to").isEmpty, "not sent to nobody")
        #expect(w.saved.withLock { $0.isEmpty })
        #expect(w.run("Null")?["problem"]?.stringValue?.contains("list.owner") == true)
    }

    // MARK: Stop, pause, restart

    @Test func stopDuringAPaymentTellsItAndGoesNoFurther() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["hold": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("the payment to be under way") { await w.calls("pay").count == 1 }
        // How far along it is shows on the run's page.
        let id = try #require(w.run("Month end")?["id"]?.stringValue)
        let child = try #require(w.run("Pay one")?["id"]?.stringValue)
        await w.until("its progress on the page") {
            let page = try? await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: ["run": .string(child)])
            return String(describing: page).contains("At the bank")
        }
        await w.ui(["op": "proceed", "run": .string(id), "how": "stop"])
        await w.until("it to stop") { w.status("Month end") == "stopped" }
        await w.until("the tool to be told") { await w.log.contains { $0.tool == "cancelled" } }
        await w.until("the called flow to end") { w.status("Pay one") == "stopped" }
        #expect(w.record("Pay one", "paid")?["status"]?.stringValue == "unknown", "it was told, which isn't proof: it says it may have happened")
        #expect(await w.calls("refund").isEmpty, "nothing after it")
        #expect(w.saved.withLock { $0.isEmpty })
        for shown in [id, child] {
            let page = try await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: ["run": .string(shown)])
            #expect(!String(describing: page).contains("Try again from here"), "not for what may have happened")
        }
    }

    @Test func pauseHoldsBetweenStepsAndGoesOnWhenSaid() async throws {
        let w = try await World()
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Two", "definition": ["trigger": ["type": "manual"], "steps": [["id": "first", "do": "ext.ledger.pay", "with": ["reason": "First"]], ["id": "second", "do": "ext.ledger.refund", "with": ["reason": "Second"]], ["id": "save", "do": "notes.save", "with": ["text": "{{first}} {{second}}"]]]]])
        #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
        await w.mode(["hold": true])
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Two"])
        await w.until("the payment to be under way") { await w.calls("pay").count == 1 }
        let id = try #require(w.run("Two")?["id"]?.stringValue)
        await w.ui(["op": "pause_run", "run": .string(id)])
        await w.mode([:])
        _ = await w.h.call("ext.ledger.release")
        await w.until("it to pause") { w.run("Two")?["paused"]?.boolValue == true }
        #expect(w.status("Two") == "waiting")
        try? await Task.sleep(for: .milliseconds(800))
        #expect(await w.calls("refund").isEmpty, "the step under way finished; nothing more until they say")
        #expect(w.saved.withLock { $0.isEmpty })
        await w.ui(["op": "proceed", "run": .string(id), "how": "try_again"])
        await w.until("it to finish") { w.status("Two") == "done" }
        #expect(await w.calls("pay").count == 1, "going on isn't doing it again")
        #expect(await w.calls("refund") == ["Second"])
        #expect(w.saved.withLock { $0.last?["text"]?.stringValue } == "Paid late Refunded Second")
    }

    @Test func underFullAccessRunningIsTheApproval() async throws {
        let w = try await World()
        try await w.h.env.permissions.updatePolicy { $0.mode = .fullAccess }
        try await w.setUp()
        let before = w.cardCount
        #expect(before == 0, "turning flows on took no card either: their own click is the approval")
        await w.mode([:])
        let ran = await w.h.call("ext.sideflow.run_flow", ["flow": "Month end"])
        #expect(ran.isOK, "\(ran.okText ?? ran.problem?.message ?? "")")
        await w.answerForm("Month end")
        await w.until("it to finish") { w.status("Month end") == "done" }
        #expect(w.cardCount == 0, "\(w.cards.withLock { $0 })")
        #expect(await w.calls("pay") == ["Invoice INV-1"])
        #expect(w.saved.withLock { $0.count } == 1)
    }

    @Test func sayingNoToTheCardStartsNothing() async throws {
        let w = try await World()
        try await w.setUp()
        w.answering.withLock { $0 = false }
        let ran = Task { await w.h.call("ext.sideflow.run_flow", ["flow": "Month end"]) }
        await w.until("the card") { await !w.h.env.broker.pending().isEmpty }
        let card = try #require(await w.h.env.broker.pending().first)
        await w.h.env.broker.resolve(id: card.id, decision: .deny)
        let outcome = await ran.value
        #expect(!outcome.isOK, "it says it didn't run")
        #expect(w.run("Month end") == nil, "nothing started")
        #expect(await w.calls("invoices").isEmpty)
        #expect(await w.flowState("Month end") == "draft")
    }

    @Test func aRestartInAPaymentAsksAndNeverPaysAgainByItself() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["hold": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("the payment to be under way") { await w.calls("pay").count == 1 }
        w.asked.answer.withLock { $0 = "No answer yet" }
        try await w.restartSideflow()
        await w.until("it to come back asking") { w.status("Pay one") == "interrupted" }
        #expect(w.run("Pay one")?["problem"]?.stringValue?.contains("may or may not") == true, "\(w.run("Pay one")?["problem"]?.stringValue ?? "")")
        #expect(w.record("Pay one", "paid")?["status"]?.stringValue == "unknown")
        await w.until("the question") { w.asked.questions.withLock { !$0.isEmpty } }
        let question = w.asked.questions.withLock { $0.last }
        #expect(question?["question"]?.stringValue?.contains("Did it happen?") == true, "\(question?["question"]?.stringValue ?? "")")
        #expect(question?["options"]?.arrayValue?.first?.stringValue == "Stop here", "what happens if they just press on: never doing it twice")
        try? await Task.sleep(for: .seconds(1))
        #expect(await w.calls("pay").count == 1, "never again by itself")
        #expect(await w.calls("refund").isEmpty)

        // They say stop, through an agent: a stop stops what called it too, whoever said it.
        let id = try #require(w.run("Pay one")?["id"]?.stringValue)
        let stop = await w.h.call("ext.sideflow.continue_run", ["run": .string(id), "how": "stop"])
        #expect(stop.isOK, "\(stop.okText ?? stop.problem?.message ?? "")")
        await w.until("it to end") { w.status("Pay one") == "stopped" }
        await w.until("the flow that called it to end") { w.status("Month end") == "stopped" }
        #expect(await w.calls("pay").count == 1)
        #expect(await w.calls("refund").isEmpty, "the rest of the list didn't go on")
        #expect(w.saved.withLock { $0.isEmpty })
    }

    @Test func aRestartThenTheirAnswerTryAgainDoesItOnTheirWord() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["hold": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("the payment to be under way") { await w.calls("pay").count == 1 }
        await w.mode([:])
        w.asked.answer.withLock { $0 = "It didn't: try again" }
        try await w.restartSideflow()
        await w.until("it to finish") { w.status("Month end") == "done" }
        #expect(await w.calls("pay").count == 2, "they chose to, knowing it may have happened")
        #expect(await w.calls("refund") == ["Back R-1"])
        #expect(w.saved.withLock { $0.count } == 1)
    }

    @Test func aRestartThenTheirAnswerItDidGoesOnWithoutIt() async throws {
        let w = try await World()
        try await w.setUp()
        await w.mode(["hold": true])
        await started(w)
        await w.answerForm("Month end")
        await w.until("the payment to be under way") { await w.calls("pay").count == 1 }
        await w.mode([:])
        w.asked.answer.withLock { $0 = "It did: carry on" }
        try await w.restartSideflow()
        await w.until("it to finish") { w.status("Month end") == "done" }
        #expect(await w.calls("pay").count == 1, "they said it happened")
        #expect(await w.calls("refund") == ["Back R-1"])
    }

    @Test func aRestartWhileAFormWaitsKeepsWhatWasTyped() async throws {
        let w = try await World()
        try await w.setUp()
        await started(w)
        await w.until("the form") { w.run("Month end")?["form"] != nil }
        let id = try #require(w.run("Month end")?["id"]?.stringValue)
        await w.ui(["op": "form_field", "run": .string(id), "name": "owner", "text": "Typed before"])
        try await w.restartSideflow()
        await w.until("the form to be back") { w.status("Month end") == "waiting" }
        await w.ui(["op": "form_field", "run": .string(id), "name": "limit", "text": "500"])
        await w.ui(["op": "form_send", "run": .string(id)])
        await w.until("it to finish") { w.status("Month end") == "done" }
        #expect(w.saved.withLock { $0.last?["text"]?.stringValue?.hasPrefix("Month end for Typed before") } == true)
    }

    // MARK: Practice

    @Test func aPracticeReadsForRealAndChangesNothing() async throws {
        let w = try await World()
        try await w.setUp()
        let practiced = await w.h.call("ext.sideflow.practice_flow", ["flow": "Month end"])
        #expect(practiced.isOK, "\(practiced.okText ?? practiced.problem?.message ?? "")")
        await w.until("the practice to finish") { w.status("Month end") == "done" || w.status("Month end") == "failed" }
        #expect(w.status("Month end") == "done", "\(w.run("Month end")?["problem"]?.stringValue ?? "")")
        #expect(await w.calls("pay").isEmpty, "nothing changed")
        #expect(await w.calls("refund").isEmpty)
        #expect(await w.calls("flag").isEmpty)
        #expect(w.saved.withLock { $0.isEmpty })
        #expect(await w.calls("invoices").count == 1, "reads are real")
    }

    @Test func aPracticeSaysWhatItWouldDoAndDoesntDoIt() async throws {
        let w = try await World()
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Two", "definition": ["trigger": ["type": "manual"], "steps": [["id": "list", "do": "ext.ledger.invoices"], ["id": "first", "do": "ext.ledger.pay", "with": ["reason": "{{list}}"]], ["id": "save", "do": "notes.save", "with": ["text": "{{first}}"]]]]])
        #expect(made.isOK, "\(made.okText ?? made.problem?.message ?? "")")
        _ = await w.h.call("ext.sideflow.practice_flow", ["flow": "Two"])
        await w.until("it to finish") { w.status("Two") == "done" || w.status("Two") == "failed" }
        #expect(w.status("Two") == "done", "\(w.run("Two")?["problem"]?.stringValue ?? "")")
        #expect(w.record("Two", "first")?["status"]?.stringValue == "would")
        #expect(w.record("Two", "save")?["status"]?.stringValue == "would")
        #expect(await w.calls("pay").isEmpty)
        #expect(w.saved.withLock { $0.isEmpty })
    }
}
