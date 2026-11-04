import Foundation
import Synchronization
@testable import SidefolkCore
import Testing

/// Sideflow, the gallery's own extension, in the real sandbox with a scripted model: what the companion and other agents can do with it, through
/// the same host abilities any extension has (D110-D114). Needs it built in the add-ons checkout (`swift build --product ext-sideflow`).
@Suite(.enabled(if: ExtFixtures.addonFolders.contains("sideflow"), ExtFixtures.noAddons), .serialized) struct SideflowSandboxTests {
    final class World: @unchecked Sendable {
        let h: HostEnv
        final class Saved: Sendable {
            private let list = Mutex<[JSONValue]>([])
            func withLock<T: Sendable>(_ body: (inout [JSONValue]) -> T) -> T { list.withLock { body(&$0) } }
        }

        let saved = Saved()

        init() async throws {
            let env = try TestEnv()
            let gateway = ExtensionActionGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity, events: env.events)
            h = try HostEnv(env: env) { $0.actions = gateway }
            let saved = saved
            h.env.registry.register(NoteProbe(record: { input in saved.withLock { $0.append(input) } }))
            h.env.registry.register(NoticeProbe())
            try await h.host.install(from: ExtFixtures.builtIn("sideflow"))
        }

        func text(_ outcome: ToolOutcome) -> String { outcome.okText ?? outcome.problem?.message ?? "" }

        func until(_ what: String, seconds: Double = 8, _ test: () async -> Bool) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if await test() { return }
                try? await Task.sleep(for: .milliseconds(30))
            }
            Issue.record("timed out waiting for \(what)")
        }

        /// The flow as its tool says.
        func flow(_ name: String) async -> JSONValue? {
            let out = await h.call("ext.sideflow.get_flow", ["flow": .string(name)])
            return out.okText.flatMap { try? JSONValue.parse(Data($0.utf8)) }
        }

        func model(_ steps: [ToolCall], reply: String = "Done.") -> ScriptedModel {
            ScriptedModel(steps.map { .turn(.calling([$0])) } + [.turn(.reply(reply))])
        }
    }

    struct NoteProbe: Tool {
        let record: @Sendable (JSONValue) -> Void

        var spec: ToolSpec {
            ToolSpec(name: "notes.save", title: "Save to notebook", description: "", inputSchema: Schema.object(["text": Schema.string("What to save.")], required: ["text"]),
                     risk: .low, capabilities: [.notebook], category: .notes, mutates: true)
        }

        func summary(for input: JSONValue) -> String { "Save a note" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            record(input)
            return ToolResult(text: "Saved.")
        }
    }

    /// A search that finds a note's words, and says so as a command's answer would.
    struct SearchProbe: Tool {
        var spec: ToolSpec {
            ToolSpec(name: "notes.search", title: "Search notebook", description: "", inputSchema: Schema.object(["query": Schema.string("What to look for.")], required: ["query"]),
                     risk: .low, capabilities: [.notebook], category: .notes, mutates: false)
        }

        func summary(for input: JSONValue) -> String { "Search" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            var result = ToolResult(text: "the note's own words", card: ResultCard(kind: .list, title: "1 match"))
            result.rowOutcome = "the note's own words"
            return result
        }
    }

    struct NoticeProbe: Tool {
        var spec: ToolSpec {
            ToolSpec(name: "notify.user", title: "Notify the user", description: "", inputSchema: Schema.object(["title": Schema.string("t"), "body": Schema.string("b"), "level": Schema.string("l")], required: ["title"]),
                     risk: .low, capabilities: [], category: .agents, mutates: false)
        }

        func summary(for input: JSONValue) -> String { "Notify" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult { ToolResult(text: "Shown.") }
    }

    static let definition: JSONValue = ["trigger": ["type": "manual"], "steps": [
        ["id": "t", "text": "From the companion"],
        ["id": "n", "do": "notes.save", "with": ["text": "Saved: {{t}}"], "name": "Save a note"],
    ]]

    @Test func theManifestIsValidAndSaysWhatItAsks() {
        let paths = SidefolkPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let r = ManifestValidator(paths: paths).validate(folder: ExtFixtures.builtIn("sideflow"))
        #expect(r.isValid, "\(r.errors)")
        #expect(r.permissions?.act != nil)
        #expect(r.permissions?.network == false)
        #expect(r.summary?.lines.contains { $0.kind == .act } == true)
    }

    @Test func theCompanionMakesAFlowAndOnlyTheCardTurnsItOn() async throws {
        let w = try await World()
        let answer = w.h.env.autoAnswer(.allowOnce)
        let create = ToolCall(id: "c", name: "ext_sideflow_create_flow", input: ["name": "Companion's", "definition": Self.definition, "start": true])
        let model = w.model([create])
        _ = try await LoopBackend(model: model, checkModel: "m", clock: w.h.env.clock).run(brainTask(w.h.env, text: "make me a flow"), toolbox: toolbox(w.h.env), emit: { _ in })
        let card = await answer.value
        guard case .text(let words)? = card?.details else { Issue.record("the plan must be on the card"); return }
        #expect(words.contains("Save to notebook"))
        #expect(words.contains("filled in when it runs"))
        #expect(card?.asker?.name == "Sideflow")
        await w.until("it to be on") { await w.flow("Companion's")?["state"]?.stringValue == "on" }

        // Nothing has run; running it now needs no card, and History says why.
        #expect(w.saved.withLock { $0.isEmpty })
        let ran = await w.h.call("ext.sideflow.run_flow", ["flow": "Companion's"])
        #expect(ran.isOK, "\(w.text(ran))")
        await w.until("the note") { w.saved.withLock { !$0.isEmpty } }
        #expect(w.saved.withLock { $0.first?["text"]?.stringValue } == "Saved: From the companion")
        #expect(await w.h.env.broker.pending().isEmpty)
        let row = try await w.h.env.activity.recent(limit: 1, tool: "notes.save").first
        #expect(row?.decision == .plan)
        #expect(row?.caller == "extension:dev.sidefolk.sideflow")
        // As written, with how long it was: what a flow fills in stays out of History (D127).
        #expect(row?.args?["text"]?.stringValue == "Saved: {{t}}")
        let kept = [row?.summary, row?.args?.jsonString, row?.outcome].compactMap { $0 }.joined()
        #expect(!kept.contains("From the companion"), "\(kept)")
        #expect(row?.outcome?.contains("\("Saved: From the companion".count)") == true)
        let story = await w.h.call("ext.sideflow.get_run", ["flow": "Companion's"])
        #expect(story.okText?.contains("Save a note") == true)
    }

    /// A run from a draft has no plan to be held to: its program says what it filled in, and Sidefolk checks that fits.
    @Test func aRunFromADraftKeepsWhatItFilledInOutOfHistoryToo() async throws {
        let w = try await World()
        _ = await w.h.call("ext.sideflow.create_flow", ["name": "Draft", "definition": Self.definition])
        let answer = w.h.env.autoAnswer(.allowOnce)
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Draft"])
        _ = await answer.value
        await w.until("the note") { w.saved.withLock { !$0.isEmpty } }
        #expect(w.saved.withLock { $0.first?["text"]?.stringValue } == "Saved: From the companion")
        await w.until("its row") { (try? await w.h.env.activity.recent(limit: 1, tool: "notes.save").first) != nil }
        let row = try await w.h.env.activity.recent(limit: 1, tool: "notes.save").first
        #expect(row?.args?["text"]?.stringValue == "Saved: {{t}}")
        #expect(row?.decision != .plan)
    }

    /// What a flow found stays out of History, by each way it could get there (D127, D136).
    @Test func whatAFlowFoundStaysOutOfHistory() async throws {
        let w = try await World()
        w.h.env.registry.register(SearchProbe())
        let definition: JSONValue = ["trigger": ["type": "manual"], "steps": [["id": "found", "do": "notes.search", "with": ["query": "the meeting"], "name": "Find my notes"]]]
        let answer = w.h.env.autoAnswer(.allowOnce)
        let create = ToolCall(id: "c", name: "ext_sideflow_create_flow", input: ["name": "Finder", "definition": definition, "start": true])
        _ = try await LoopBackend(model: w.model([create]), checkModel: "m", clock: w.h.env.clock).run(brainTask(w.h.env, text: "make me a flow"), toolbox: toolbox(w.h.env), emit: { _ in })
        _ = await answer.value
        await w.until("it to be on") { await w.flow("Finder")?["state"]?.stringValue == "on" }
        _ = await w.h.call("ext.sideflow.run_flow", ["flow": "Finder"])
        await w.until("the run to end") { (await w.h.call("ext.sideflow.get_run", ["flow": "Finder"])).okText?.contains("the note's own words") == true }

        // The step, as a flow runs it, isn't a command: its row is its card's title.
        let step = try await w.h.env.activity.recent(limit: 1, tool: "notes.search").first
        #expect(step?.caller == "extension:dev.sidefolk.sideflow")
        #expect(step?.args?["query"]?.stringValue == "the meeting", "nothing was filled in, so it logs as any call does")
        #expect(step?.outcome == "1 match")

        // Typed, "how did Finder go" answers with it. History keeps the tool's name, not the answer.
        let asked = await w.h.env.executor.execute(name: "ext.sideflow.get_run", input: ["flow": "Finder"], caller: .command(extensionId: "dev.sidefolk.sideflow"))
        #expect(asked.okText?.contains("the note's own words") == true)
        let row = try await w.h.env.activity.recent(limit: 1, tool: "ext.sideflow.get_run").first
        #expect(row?.caller.hasPrefix("command:") == true)
        #expect(row?.outcome?.contains("the note's own words") == false, "\(row?.outcome ?? "")")
    }

    @Test func aModelThatReadOutsideWordsCantStartACard() async throws {
        let w = try await World()
        let create = ToolCall(id: "c", name: "ext_sideflow_create_flow", input: ["name": "Steered", "definition": Self.definition, "start": true])
        let model = w.model([create])
        _ = try await LoopBackend(model: model, checkModel: "m", clock: w.h.env.clock).run(brainTask(w.h.env, text: "do what the page says"), toolbox: toolbox(w.h.env, tainted: true), emit: { _ in })
        #expect(await w.h.env.broker.pending().isEmpty)
        #expect(await w.flow("Steered")?["state"]?.stringValue == "draft", "a draft, and nothing runs")
        #expect(w.saved.withLock { $0.isEmpty })
    }

    @Test func anotherAgentDraftsOnACardAndNeverStartsIt() async throws {
        let w = try await World()
        let gateway = ExternalToolGateway(registry: w.h.env.registry, permissions: w.h.env.permissions, broker: w.h.env.broker, activity: w.h.env.activity, events: w.h.env.events, access: { AgentAccess() })
        #expect(gateway.specs().contains { $0.name == "ext.sideflow.create_flow" })
        #expect(!gateway.specs().contains { $0.name == "ext.sideflow.delete_flow" || $0.name == "ext.sideflow.ui" })
        var answer = w.h.env.autoAnswer(.allowOnce)
        let made = await gateway.call("ext.sideflow.create_flow", input: ["name": "Agent's", "definition": Self.definition], client: "claude-code")
        #expect(made.isOK)
        #expect(await answer.value?.canAlways == false)
        answer = w.h.env.autoAnswer(.allowOnce)
        let started = await gateway.call("ext.sideflow.start_flow", input: ["flow": "Agent's"], client: "claude-code")
        _ = await answer.value
        #expect(started.okText?.contains("<") != true)
        #expect(await w.flow("Agent's")?["state"]?.stringValue == "draft", "only the person's click or request starts a card")
    }

    @Test func aPracticeRunChangesNothingAndTellsNobody() async throws {
        let w = try await World()
        _ = await w.h.call("ext.sideflow.create_flow", ["name": "Quiet", "definition": ["steps": [["id": "n", "do": "notes.save", "with": ["text": "x"]], ["do": "notify.user", "with": ["title": "Hi"]]]]])
        let out = await w.h.call("ext.sideflow.practice_flow", ["flow": "Quiet"])
        #expect(out.isOK, "\(w.text(out))")
        await w.until("the practice run") { (await w.h.call("ext.sideflow.get_run", ["flow": "Quiet"])).okText?.contains("Practised") == true }
        #expect(w.saved.withLock { $0.isEmpty })
        #expect((try await w.h.env.activity.recent(limit: 5, tool: "notify.user")).isEmpty)
    }

    /// Whether this checkout's pack shows a tree: the app leads, and the gallery's pack follows it after the snapshot that has the ability.
    static var packShowsATree: Bool {
        let tools = ExtFixtures.addonsRepo.appendingPathComponent("extensions/sideflow/Sources/Tools.swift")
        return (try? String(contentsOf: tools, encoding: .utf8))?.contains("showing(tree:") == true
    }

    @Test(.enabled(if: packShowsATree, "this checkout's Sideflow pack doesn't show a tree on its card yet"))
    func makingAFlowLeavesItsTreeOnTheCardInAsk() async throws {
        let w = try await World()
        let out = await w.h.call("ext.sideflow.create_flow", ["name": "Shown", "definition": Self.definition])
        #expect(out.isOK, "\(w.text(out))")
        let tree = out.activity.card?.tree.flatMap(ExtensionPage.tree(from:))
        #expect(tree?.reading.isEmpty == false)
        #expect(tree?.reading.allSatisfy { $0.state == .pending } == true, "dashed: nothing has run")
    }

    static var packAsksToShare: Bool {
        let inspector = ExtFixtures.addonsRepo.appendingPathComponent("extensions/sideflow/Sources/Inspector.swift")
        return (try? String(contentsOf: inspector, encoding: .utf8))?.contains(".share(path:") == true
    }

    /// Sidefolk's own watch tools, for what a flow's trigger makes.
    private static func realWatches(_ env: TestEnv) -> WatcherEngine {
        let watchers = WatcherEngine(store: WatcherStore(env.db), attention: AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock), events: env.events, clock: env.clock,
                                     opener: { _ in }, probes: WatchProbes.standard(fetcher: FakeFetcher(), throttle: HostThrottle()))
        env.registry.register(WatchTools.make(engine: watchers))
        return watchers
    }

    private static func watching(_ path: String) -> JSONValue {
        ["trigger": ["type": "watch", "kind": "file_changes", "target": .string(path)], "steps": [["id": "t", "do": "notify.user", "with": ["title": "Changed"]]]]
    }

    /// The folder isn't shared: the flow says so where the person is and offers to, and once it's shared it goes on by itself.
    @Test(.enabled(if: packAsksToShare, "this checkout's Sideflow pack doesn't ask to share a folder yet"))
    func aFolderThatIsntSharedIsAskedForRightThere() async throws {
        let w = try await World()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("status.txt").path
        FileManager.default.createFile(atPath: file, contents: Data("one".utf8))
        _ = Self.realWatches(w.h.env)

        let check = await w.h.env.executor.check(name: "watch.create", input: ["kind": "file_changes", "target": .string(file), "mode": "repeat", "title": "t"],
                                                 caller: .extension(id: "dev.sidefolk.sideflow"), tainted: false, standing: false)
        #expect(check?.decision == .deny)
        #expect(check?.share?.path == file, "the path as named: what's on disk stays out of its sandbox")

        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Status", "definition": Self.watching(file)])
        #expect(made.isOK, "\(w.text(made))")
        guard let id = await w.flow("Status")?["id"]?.stringValue else { Issue.record("no flow"); return }
        func page() async -> String { (try? await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: ["flow": .string(id)]))?.sections.description ?? "" }
        await w.until("the card to say it", seconds: 12) { await page().contains("Needs a folder") }

        try await w.h.env.permissions.grantFolder(folder.path, access: .read)
        await w.until("the card to stop saying it", seconds: 12) { await !page().contains("Needs a folder") }
    }

    /// One hidden file: the plan they read names it, the watch is made, and no words of it are kept.
    @Test(.enabled(if: packAsksToShare, "this checkout's Sideflow pack doesn't ask to share a folder yet"))
    func aHiddenFileWatchedByAPlanKeepsNoWords() async throws {
        let w = try await World()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)/.tmp")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let file = folder.appendingPathComponent("status.txt").path
        FileManager.default.createFile(atPath: file, contents: Data("private words".utf8))

        let watchers = Self.realWatches(w.h.env)

        let answer = w.h.env.autoAnswer(.allowOnce)
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Hidden", "definition": Self.watching(file), "start": true])
        #expect(made.isOK, "\(w.text(made))")
        _ = await answer.value
        await w.until("it to be on") { await w.flow("Hidden")?["state"]?.stringValue == "on" }
        let row = try await w.h.env.activity.recent(limit: 1, tool: "watch.create").first
        #expect(row?.decision == .plan)
        #expect(row?.summary.contains("size and time only") == true)
        let list = await watchers.list()
        let watcher = try #require(list.first { $0.title == "Hidden · Sideflow" })
        #expect(watcher.state == .active)
        #expect(watcher.lastState?.jsonString.contains("private") != true)
    }

    static var packKnowsThePlanLimit: Bool {
        let catalog = ExtFixtures.addonsRepo.appendingPathComponent("extensions/sideflow/Sources/Catalog.swift")
        return (try? String(contentsOf: catalog, encoding: .utf8))?.contains("Plans.maxSteps") == true
    }

    /// The Kit's word for the limit is Sidefolk's, and a flow right at it, watch and all, is really allowed: the page and the host give one answer.
    @Test(.enabled(if: packKnowsThePlanLimit, "this checkout's Sideflow pack doesn't know the plan limit yet"))
    func aFlowAtTheLimitTurnsOnAndOverItIsMarkedFirst() async throws {
        let kit = try String(contentsOf: ExtFixtures.addonsRepo.appendingPathComponent("Kit/Actions.swift"), encoding: .utf8)
        #expect(kit.contains("maxSteps = \(ExtensionPlanRules.maxSteps)"))
        let w = try await World()
        _ = Self.realWatches(w.h.env)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await w.h.env.permissions.grantFolder(folder.path, access: .read)
        func flow(_ actions: Int) -> JSONValue {
            ["trigger": ["type": "watch", "kind": "file_changes", "target": .string(folder.appendingPathComponent("a.txt").path)],
             "steps": .array((0..<actions).map { ["id": .string("s\($0)"), "do": "notify.user", "with": ["title": .string("Line \($0)")]] })]
        }
        let answer = w.h.env.autoAnswer(.allowOnce)
        let fits = await w.h.call("ext.sideflow.create_flow", ["name": "Fits", "definition": flow(ExtensionPlanRules.maxSteps - 4), "start": true])
        #expect(fits.isOK, "\(w.text(fits))")
        _ = await answer.value
        await w.until("it to be on") { await w.flow("Fits")?["state"]?.stringValue == "on" }

        let over = await w.h.call("ext.sideflow.create_flow", ["name": "Over", "definition": flow(ExtensionPlanRules.maxSteps - 3)])
        let read = await w.flow("Over")?.jsonString ?? ""
        #expect(w.text(over).contains("different things to allow") || read.contains("different things to allow"), "\(w.text(over)) \(read.prefix(200))")
    }

    /// Nothing to allow: Sidefolk has no card for that, and the flow turns on.
    @Test(.enabled(if: packKnowsThePlanLimit, "this checkout's Sideflow pack doesn't know the plan limit yet"))
    func aFlowWithNothingToAllowTurnsOn() async throws {
        let w = try await World()
        let made = await w.h.call("ext.sideflow.create_flow", ["name": "Words", "definition": ["trigger": ["type": "manual"], "steps": [["id": "t", "text": "Only words"]]], "start": true])
        #expect(made.isOK, "\(w.text(made))")
        await w.until("it to be on") { await w.flow("Words")?["state"]?.stringValue == "on" }
        #expect(await w.h.env.broker.pending().isEmpty)
    }

    @Test func thePageRendersAndALargeFlowFits() async throws {
        let w = try await World()
        var steps: [JSONValue] = []
        for i in 0..<40 { steps.append(["id": .string("s\(i)"), "text": .string(String(repeating: "words ", count: 40))]) }
        _ = await w.h.call("ext.sideflow.create_flow", ["name": "Long", "definition": ["steps": .array(steps)]])
        let home = try await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: .object([:]), width: 1000)
        #expect(home.workspace)
        #expect(home.summary != nil)
        let id = await w.flow("Long")?["id"]?.stringValue ?? ""
        let one = try await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows", state: ["flow": .string(id)], width: 1000)
        let tree = one.sections.flatMap(\.blocks).compactMap { block -> ExtensionPage.Tree? in if case .tree(let t) = block { t } else { nil } }.first
        #expect(tree?.reading.count == 41, "what sets it off, and every step")
        #expect(tree?.reorder != nil)
        #expect(tree?.picker?.items.isEmpty == false)
        let background = try await w.h.host.renderPage(extensionId: "dev.sidefolk.sideflow", page: "flows")
        #expect(background.sections.isEmpty, "Today reads only the summary")
    }

    @Test func aSentenceRunsItWithoutTheAI() async throws {
        let w = try await World()
        _ = await w.h.call("ext.sideflow.create_flow", ["name": "Morning", "definition": Self.definition])
        let tools = w.h.env.registry.all.compactMap { $0 as? ExtensionTool }.filter { $0.commands != nil }
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", commandTools: tools)
        guard case .extensionCommand(let call)? = parser.parse("what flows do i have", now: w.h.env.clock.now)?.intent else {
            Issue.record("no command")
            return
        }
        #expect(call.tool == "ext.sideflow.list_flows")
    }
}
