import Foundation
import Testing
@testable import SidefolkCore

/// A folder shared from a page, and one hidden file watched for its size and time (D-SHARE, SECURITY T10.2).
@Suite struct FolderShareTests {
    let engine = PermissionEngine()
    let home = NSHomeDirectory()

    private var watchSpec: ToolSpec {
        ToolSpec(name: "watch.create", title: "Watch", description: "", inputSchema: .object([:]), risk: .low, capabilities: [.watch], category: .watch, mutates: true)
    }

    private func decide(_ scope: ToolScope, caller: Caller, standing: Bool = false, policy: GuardPolicy = GuardPolicy(), grants: [Grant] = [], folders: [GrantedFolder] = []) -> GuardDecision {
        engine.evaluate(spec: watchSpec, input: .object([:]), summary: "s", scope: scope, caller: caller, tainted: false, policy: policy, grants: grants, folders: folders, standing: standing)
    }

    private var hiddenFile: ToolScope { ToolScope(readPaths: [home + "/ws/.tmp/status.txt"], factsOnly: true) }

    @Test func aHiddenFileIsAskedAboutNotRefusedAndNeverGranted() {
        for caller in [Caller.agent(runId: "r"), .extension(id: "dev.test.flows")] {
            guard case .ask(let card) = decide(hiddenFile, caller: caller) else { Issue.record("expected a card for \(caller)"); continue }
            #expect(!card.canAlways)
            #expect(card.risk >= .medium)
        }
        let grant = Grant(tool: "watch.create", callerKind: "agent")
        guard case .ask = decide(hiddenFile, caller: .agent(runId: "r"), grants: [grant]) else { Issue.record("an Always mustn't cover a hidden file"); return }
    }

    @Test func aPlanThePersonReadCoversIt() {
        #expect(decide(hiddenFile, caller: .extension(id: "dev.test.flows"), standing: true) == .allow(.plan))
        guard case .ask = decide(hiddenFile, caller: .extension(id: "dev.test.flows"), standing: true, policy: GuardPolicy(mode: .askEveryTime)) else {
            Issue.record("asked to be asked every time, they're asked"); return
        }
    }

    @Test func thePersonsOwnRequestRunsAndOtherAgentsStayRefused() {
        #expect(decide(hiddenFile, caller: .user) == .allow(.auto))
        guard case .deny = decide(hiddenFile, caller: .external(client: "codex")) else { Issue.record("other agents keep the plain refusal"); return }
    }

    @Test func onlyFactsOpenAHiddenPlaceAndNothingElseItsRulesCover() {
        guard case .deny = decide(ToolScope(readPaths: [home + "/.ssh/id_rsa"]), caller: .user) else { Issue.record("a read stays refused"); return }
        for path in [home + "/Library/.x/y", "/System/.x/y", "/Users/Shared/.x/y"] {
            guard case .deny = decide(ToolScope(readPaths: [path], factsOnly: true), caller: .user) else { Issue.record("\(path) is still protected"); continue }
        }
    }

    @Test func aHiddenFolderStaysUnshareable() {
        #expect(!FolderAccess.isGrantable(home + "/ws/.tmp"))
        #expect(FolderAccess.folderToShare(read: [home + "/ws/.tmp/x.txt"], write: [], folders: []) == nil)
    }

    @Test func whatToShareIsTheFolderItIsIn() {
        let path = home + "/SidefolkTestNothingHere/in/report.txt"
        #expect(FolderAccess.folderToShare(read: [path], write: [], folders: []) == home + "/SidefolkTestNothingHere/in")
        let shared = GrantedFolder(path: home + "/SidefolkTestNothingHere/in", access: .read)
        #expect(FolderAccess.folderToShare(read: [path], write: [], folders: [shared]) == nil, "already shared")
        #expect(FolderAccess.folderToShare(read: [], write: [path], folders: [shared]) == home + "/SidefolkTestNothingHere/in", "shared to read, asked to change")
        #expect(FolderAccess.folderToShare(read: [home + "/x.txt"], write: [], folders: []) == nil, "the whole home is too broad")
    }

    @Test func aPageAsksAboutAFolderSidefolkWorksOut() throws {
        #expect(try PageShareAsk(path: "~/SidefolkTestNothingHere/in/report.txt").folder().get() == home + "/SidefolkTestNothingHere/in")
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "~/.ssh/id_rsa").folder().get() }
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "/System/Library").folder().get() }
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "~/report.txt").folder().get() }
        #expect(PageAct.parse(["share": ["path": "~/a/b.txt", "write": true]]) == .share(PageShareAsk(path: "~/a/b.txt", write: true)))
        #expect(PageAct.parse(["share": ["write": true]]) == nil)
    }

    @Test func onlyThePersonsClickShares() async throws {
        let store = PermissionStore(try AppDatabase.inMemory())
        let tool = FolderShareTool(permissions: store, events: EventBus())
        for caller in [Caller.agent(runId: "r"), .extension(id: "dev.test.flows"), .external(client: "codex")] {
            #expect(tool.refusal(for: ["folder": "/tmp/x"], context: ToolContext(caller: caller, now: Date(), tainted: false)) != nil)
        }
        #expect(tool.refusal(for: ["folder": "/tmp/x"], context: ToolContext(caller: .user, now: Date(), tainted: false)) == nil)
        #expect(!tool.spec.offeredToModel)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await tool.run(["folder": .string(folder.path)], context: ToolContext(caller: .user, now: Date(), tainted: false))
        let shared = try await store.folders()
        #expect(shared.first?.access == .read)
        await #expect(throws: (any Error).self) { _ = try await tool.run(["folder": .string(NSHomeDirectory())], context: ToolContext(caller: .user, now: Date(), tainted: false)) }
    }
}
