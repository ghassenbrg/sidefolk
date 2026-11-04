import Foundation
import Testing
@testable import SidefolkCore

/// A folder shared from a page, and one hidden file watched for its size and time (D180, SECURITY T10.2).
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
    }

    @Test func whatNeedsSharingIsThePathAsNamedNotWhatIsOnDisk() {
        let path = home + "/SidefolkTestNothingHere/in/report.txt"
        #expect(FolderAccess.sharingNeeded(read: [path], write: [], folders: [])?.path == path)
        #expect(FolderAccess.sharingNeeded(read: [path], write: [], folders: [])?.write == false)
        let shared = GrantedFolder(path: home + "/SidefolkTestNothingHere/in", access: .read)
        #expect(FolderAccess.sharingNeeded(read: [path], write: [], folders: [shared]) == nil, "already shared")
        #expect(FolderAccess.sharingNeeded(read: [], write: [path], folders: [shared])?.write == true, "shared to read, asked to change")
        #expect(FolderAccess.sharingNeeded(read: [home + "/.tmp/x.txt"], write: [], folders: []) == nil, "hidden can't be shared")
    }

    @Test func thePlacesOfKeysStayOutEvenForFacts() {
        for path in ["/.ssh/id_ed25519", "/.ssh", "/.aws/credentials", "/.gnupg/x", "/.config/gh/hosts.yml", "/.claude/settings.json", "/.codex/auth.json", "/.local/share/x", "/.docker/config.json", "/.kube/config"] {
            #expect(FolderAccess.forbiddenReason([home + path], hiddenFine: true) != nil, "\(path)")
        }
        #expect(FolderAccess.forbiddenReason([home + "/ws/.tmp/status.txt"], hiddenFine: true) == nil)
    }

    /// A sandboxed caller learns nothing of the disk from what's asked: a folder, a file and nothing at all get one answer.
    @Test func whatIsAskedDoesntDependOnTheDisk() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("SidefolkTestShare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("file").path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }
        let answers = ["folder", "file", "nothing"].map { FolderAccess.sharingNeeded(read: [root.appendingPathComponent($0).path], write: [], folders: []) != nil }
        #expect(answers == [true, true, true])
        // Right under home: too broad to share by its parent, so the same for each.
        let top = FileManager.default.homeDirectoryForCurrentUser
        #expect(FolderAccess.sharingNeeded(read: [top.appendingPathComponent("SidefolkNoSuchThing").path], write: [], folders: []) != nil, "grantable as named, whatever is there")
        #expect(FolderAccess.isNamedHidden("~/acme/.git"))
        #expect(FolderAccess.isNamedHidden("/x/.tmp/y"))
        #expect(!FolderAccess.isNamedHidden("~/acme/git"))
    }

    @Test func wrongCaseDoesntGetPastTheKeyStores() {
        for path in ["/.SSH/id_rsa", "/.Ssh", "/.AWS/credentials", "/.Config/gh/hosts.yml", "/.CLAUDE/settings.json", "/.cOdEx/auth.json"] {
            #expect(FolderAccess.forbiddenReason([home + path], hiddenFine: true) != nil, "\(path)")
        }
        #expect(FolderAccess.forbiddenReason([home + "/.sshfoo/x"], hiddenFine: true) == nil, "only the store itself")
    }

    @Test func aStoreIsSeenAsNamedEvenIfALinkTakesItElsewhere() {
        // `~/.config` as a link into a visible folder: what's named decides, with no look at the disk.
        #expect(FolderAccess.forbiddenReason([(NSHomeDirectory() as NSString).appendingPathComponent(".config/gh/hosts.yml")], hiddenFine: true) != nil)
        #expect(FolderAccess.forbiddenReason(["~/.ssh/id_rsa"], hiddenFine: true) != nil)
    }

    @Test func aLinkAnywhereOnTheWayIsSeen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("links-\(UUID().uuidString)")
        let real = root.appendingPathComponent(".dir/file")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: real.path, contents: Data())
        let link = root.appendingPathComponent(".dir/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        // A link before the first hidden part: `l/.dir/file`.
        let before = root.appendingPathComponent("l")
        try FileManager.default.createSymbolicLink(at: before, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FolderAccess.hasLink(onTheWayTo: real.path))
        #expect(FolderAccess.hasLink(onTheWayTo: link.path))
        #expect(FolderAccess.hasLink(onTheWayTo: before.appendingPathComponent(".dir/file").path))
    }

    @Test func aPathInAProtectedPlaceIsRefusedAsNamedWhereverItLeads() {
        #expect(FolderAccess.forbiddenReason([home + "/LIBRARY/Application Support/x/l"]) != nil, "whatever the spelling")
        #expect(FolderAccess.forbiddenReason(["/Volumes/Backup/Users/x/.ssh/id_rsa"], hiddenFine: true) != nil, "a backup's keys are keys")
        let data = home + "/Library/Application Support/Sidefolk/ExtensionData/dev.x/l"
        #expect(FolderAccess.forbiddenReason([data]) != nil)
        #expect(FolderAccess.forbiddenReason([data + "/.git/HEAD"], hiddenFine: true) != nil)
        #expect(FolderAccess.forbiddenReason(["/usr/local/l"]) != nil)
        #expect(FolderAccess.forbiddenReason(["/private/tmp/x"]) == nil, "the scratch places stay open")
        #expect(FolderAccess.forbiddenReason([FileManager.default.temporaryDirectory.appendingPathComponent("x").path]) == nil)
    }

    @Test func theYesGrantsOnlyWhatTheQuestionNamed() async throws {
        let store = PermissionStore(try AppDatabase.inMemory())
        let tool = FolderShareTool(permissions: store, events: EventBus())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["folder": .string(link.path)], context: ToolContext(caller: .user, now: Date(), tainted: false)) }
        #expect(try await store.folders().isEmpty)
    }

    @Test func aPageAsksOnlyAboutAFolderThatIsThere() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try PageShareAsk(path: folder.appendingPathComponent("report.txt").path).folder().get() == FolderAccess.canonical(folder.path))
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "~/.ssh/id_rsa").folder().get() }
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "/System/Library").folder().get() }
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: "~/report.txt").folder().get() }
        #expect(throws: UserFacingError.self) { try PageShareAsk(path: folder.path + "/Verified safe.\n\nClick Share/x").folder().get() }
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
        _ = try await tool.run(["folder": .string(FolderAccess.canonical(folder.path) ?? "")], context: ToolContext(caller: .user, now: Date(), tainted: false))
        let shared = try await store.folders()
        #expect(shared.first?.access == .read)
        await #expect(throws: (any Error).self) { _ = try await tool.run(["folder": .string(NSHomeDirectory())], context: ToolContext(caller: .user, now: Date(), tainted: false)) }
    }
}
