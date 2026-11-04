import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// D185: Full access works anywhere in the person's home that isn't protected, asking nothing; Auto, after outside content,
/// still runs a file change inside a folder the person shared; the other callers and modes are not moved by either.
@Suite struct FullAccessMeansFullTests {
    static let home = NSHomeDirectory()
    static let agent = Caller.agent(runId: "r")

    // MARK: Where Full access works without a share

    @Test func insideTheHomeWorksAndNothingElseDoes() throws {
        let unique = "sf-full-\(UUID().uuidString)"
        // Inside the home: files and folders that exist or will.
        #expect(FolderAccess.isOpenToFullAccess("\(Self.home)/\(unique)/a.txt"))
        #expect(FolderAccess.isOpenToFullAccess("\(Self.home)/\(unique)"))
        // The home itself is too broad, and so is anything not under it.
        #expect(!FolderAccess.isOpenToFullAccess(Self.home))
        #expect(!FolderAccess.isOpenToFullAccess("/"))
        #expect(!FolderAccess.isOpenToFullAccess("/Users"))
        #expect(!FolderAccess.isOpenToFullAccess("/Users/Shared/x"))
        #expect(!FolderAccess.isOpenToFullAccess("/Users/someone-else/Documents/x"))
        #expect(!FolderAccess.isOpenToFullAccess("/Volumes/Macintosh HD/System/x"))
        #expect(!FolderAccess.isOpenToFullAccess("/Volumes/Backup/Documents/x"))
        #expect(!FolderAccess.isOpenToFullAccess("/etc/hosts"))
        #expect(!FolderAccess.isOpenToFullAccess("/tmp/x"))
        #expect(!FolderAccess.isOpenToFullAccess("/Applications/Safari.app/x"))
    }

    @Test func aProtectedPlaceThatDoesNotExistYetIsProtectedInAnyCase() {
        for path in ["\(Self.home)/BIN/tool", "\(Self.home)/Bin", "\(Self.home)/APPLICATIONS/x.app", "\(Self.home)/lIbRaRy/x"] {
            #expect(!FolderAccess.isOpenToFullAccess(path), "\(path)")
            #expect(FolderAccess.forbiddenReason([path]) != nil, "\(path)")
        }
    }

    @Test func protectedPlacesInsideTheHomeStayOut() {
        let unique = "sf-full-\(UUID().uuidString)"
        for path in ["\(Self.home)/Library/Preferences/x.plist", "\(Self.home)/Library", "\(Self.home)/Applications/Tool.app/x",
                     "\(Self.home)/bin/x", "\(Self.home)/.ssh/id_ed25519", "\(Self.home)/.config/x", "\(Self.home)/\(unique)/.env",
                     "\(Self.home)/\(unique)/.git/config", "\(Self.home)/Documents/.hidden/x",
                     SidefolkPaths.standard().home.path + "/sidefolk.sqlite"] {
            #expect(!FolderAccess.isOpenToFullAccess(path), "\(path)")
        }
        // Relative paths, "..", and a path through "." never qualify (nothing is collapsed lexically).
        for path in ["Documents/x", "\(Self.home)/Documents/../Library/x", "\(Self.home)/./Documents/x", "~/../x"] {
            #expect(!FolderAccess.isOpenToFullAccess(path), "\(path)")
        }
    }

    @Test func aLinkOutOfTheHomeIsNotInsideIt() throws {
        let link = "\(Self.home)/sf-full-link-\(UUID().uuidString)"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/private/tmp")
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(!FolderAccess.isOpenToFullAccess(link + "/x.txt"), "a link in the home that leads out of it")
        #expect(!FolderAccess.isOpenToFullAccess(link))
    }

    @Test func onlySidefolkOwnAgentInFullAccessGetsThem() {
        let scope = ToolScope(writePaths: ["\(Self.home)/sf-full-\(UUID().uuidString)/a.txt"])
        let full = GuardPolicy(mode: .fullAccess)
        #expect(ToolExecutor.fullAccessFolders(scope, caller: Self.agent, policy: full).count == 1)
        // A typed extension command gets the mode but not the home: its folder is the extension's to name, so it keeps its card.
        for caller in [Caller.command(extensionId: "dev.x.y"), .external(client: "claude-code"), .extension(id: "dev.x.y"), .routine(id: "r")] {
            #expect(ToolExecutor.fullAccessFolders(scope, caller: caller, policy: full).isEmpty, "\(caller.kind)")
        }
        for mode in [GuardMode.askEveryTime, .askOncePerKind, .auto] {
            #expect(ToolExecutor.fullAccessFolders(scope, caller: Self.agent, policy: GuardPolicy(mode: mode)).isEmpty, "\(mode)")
        }
        // Full access that has ended is the mode it replaced.
        var ended = GuardPolicy(mode: .fullAccess)
        ended.fullAccessEnds = Date(timeIntervalSince1970: 0)
        #expect(ToolExecutor.fullAccessFolders(scope, caller: Self.agent, policy: ended.current(at: Date())).isEmpty)
    }

    // MARK: End to end: a tainted turn in Full access moves a file in an unshared folder, with no card

    /// A file tool that says what folders Guard let it have.
    final class FolderProbe: Tool {
        init(paths: [String]) { self.paths = paths }
        let spec = ToolSpec(name: "files.move", title: "Move", description: "", inputSchema: .object([:]), risk: .medium,
                            capabilities: [.filesWrite], category: .files, mutates: true)
        let paths: [String]
        let seen = Mutex<[GrantedFolder]?>(nil)
        func summary(for input: JSONValue) -> String { "Move a file" }
        func scope(for input: JSONValue) -> ToolScope { ToolScope(writePaths: paths) }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            seen.withLock { $0 = context.folders }
            return ToolResult(text: "Moved.")
        }
    }

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

    @Test func fullAccessMovesInAnUnsharedHomeFolderAfterOutsideContent() async throws {
        let env = try TestEnv()
        let path = "\(Self.home)/sf-full-\(UUID().uuidString)/a.txt"
        let tool = FolderProbe(paths: [path])
        env.registry.register(tool)
        try await env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let (counter, listener) = cards(env)
        defer { listener.cancel() }

        let out = await env.executor.execute(name: "files.move", input: .object([:]), caller: Self.agent, tainted: true)
        #expect(out.isOK)
        #expect(counter.value == 0)
        #expect(tool.seen.withLock { $0 }?.contains { $0.access == .readwrite && FolderAccess.isInside(path, folder: $0.path) } == true,
                "the tool is handed the path, since it checks the folders Guard let it have")
        // Nothing was added to the person's list, and the log has the row.
        #expect(try await env.permissions.folders().isEmpty)
        #expect(try await env.activity.recent().first?.decision == .fullAccess)
    }

    @Test func fullAccessStillRefusesAProtectedPlaceAndTheSameAskedCallerElsewhere() async throws {
        let env = try TestEnv()
        env.registry.register(FolderProbe(paths: ["\(Self.home)/.ssh/authorized_keys"]))
        try await env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let out = await env.executor.execute(name: "files.move", input: .object([:]), caller: Self.agent, tainted: false)
        guard case .denied = out.status else { Issue.record("a protected place is refused in Full access: \(out.status)"); return }
        #expect(await env.executor.allowedForNow().isEmpty)
    }

    @Test func anotherAgentInFullAccessIsStillRefusedAnUnsharedFolder() async throws {
        let env = try TestEnv()
        env.registry.register(FolderProbe(paths: ["\(Self.home)/sf-full-\(UUID().uuidString)/a.txt"]))
        try await env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let out = await env.executor.execute(name: "files.move", input: .object([:]), caller: .external(client: "codex"), tainted: true)
        guard case .denied = out.status else { Issue.record("other agents never reach an unshared folder: \(out.status)"); return }
    }

    // MARK: Auto: a file change inside a shared folder after outside content

    private func sharedFolder(_ env: TestEnv) async throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sf-auto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await env.permissions.grantFolder(folder.path, access: .readwrite)
        return folder.path
    }

    @Test func autoChangesFilesInASharedFolderAfterOutsideContent() async throws {
        let env = try TestEnv()
        let shared = try await sharedFolder(env)
        defer { try? FileManager.default.removeItem(atPath: shared) }
        env.registry.register(FolderProbe(paths: [shared + "/a.txt", shared + "/Invoices/a.txt"]))
        try await env.permissions.setPolicy(GuardPolicy(mode: .auto))
        let (counter, listener) = cards(env)
        defer { listener.cancel() }
        let out = await env.executor.execute(name: "files.move", input: .object([:]), caller: Self.agent, tainted: true)
        #expect(out.isOK && counter.value == 0)
        #expect(try await env.activity.recent().first?.decision == .autoMode)
    }

    /// The residual risk, written down (T21): a steered turn can move a file from one shared folder into another, one of which may sync.
    /// It stays inside what the person shared, and it is in History.
    @Test func aMoveBetweenTwoSharedFoldersAfterOutsideContentRunsAndIsLogged() async throws {
        let env = try TestEnv()
        let private1 = try await sharedFolder(env), synced = try await sharedFolder(env)
        defer { for p in [private1, synced] { try? FileManager.default.removeItem(atPath: p) } }
        env.registry.register(FolderProbe(paths: [private1 + "/secret.txt", synced + "/secret.txt"]))
        try await env.permissions.setPolicy(GuardPolicy(mode: .auto))
        let out = await env.executor.execute(name: "files.move", input: .object([:]), caller: Self.agent, tainted: true)
        #expect(out.isOK)
        let row = try await env.activity.recent().first
        #expect(row?.decision == .autoMode && row?.tool == "files.move")
    }

    @Test func autoStillAsksForAFolderThatIsNotSharedAndForOneThatIsOnlyRead() async throws {
        let env = try TestEnv()
        let shared = try await sharedFolder(env)
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await env.permissions.updatePolicy { $0.choose(.auto) }
        // One path inside, one outside: the outside one asks, and Auto never answers a folder question.
        let spec = FolderProbe(paths: []).spec
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("sf-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let decision = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s",
                                                   scope: ToolScope(writePaths: [shared + "/a.txt", outside.path + "/a.txt"]), caller: Self.agent,
                                                   tainted: true, policy: GuardPolicy(mode: .auto), grants: [],
                                                   folders: try await env.permissions.folders())
        guard case .ask(let card) = decision, case .folderAccess = card.details else { Issue.record("\(decision)"); return }
        // A folder shared read-only doesn't let Auto change files in it after outside content.
        let readOnly = FileManager.default.temporaryDirectory.appendingPathComponent("sf-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: readOnly) }
        try await env.permissions.grantFolder(readOnly.path, access: .read)
        let ro = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(writePaths: [readOnly.path + "/a.txt"]),
                                             caller: Self.agent, tainted: true, policy: GuardPolicy(mode: .auto), grants: [],
                                             folders: try await env.permissions.folders())
        guard case .ask(let roCard) = ro, case .folderAccess(_, let write) = roCard.details, write else { Issue.record("\(ro)"); return }
    }

    @Test func aLinkOutOfASharedFolderStillAsksAfterOutsideContentInAuto() async throws {
        let env = try TestEnv()
        let shared = try await sharedFolder(env)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("sf-out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { for p in [shared, outside.path] { try? FileManager.default.removeItem(atPath: p) } }
        try FileManager.default.createSymbolicLink(atPath: shared + "/escape", withDestinationPath: outside.path)
        let spec = FolderProbe(paths: []).spec
        let folders = try await env.permissions.folders()
        func decide(_ path: String) -> GuardDecision {
            PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(writePaths: [path]), caller: Self.agent,
                                        tainted: true, policy: GuardPolicy(mode: .auto), grants: [], folders: folders)
        }
        #expect(decide(shared + "/ok.txt") == .allow(.autoMode))
        guard case .ask(let card) = decide(shared + "/escape/x.txt"), case .folderAccess = card.details else { Issue.record("a link out of a shared folder must ask"); return }
        // A look-alike name is another folder, a `..` is refused, a relative path is refused.
        guard case .ask = decide(shared + "-other/x.txt") else { Issue.record("prefix collision"); return }
        guard case .deny = decide(shared + "/../x.txt") else { Issue.record("dot-dot"); return }
        guard case .deny = decide("a/b.txt") else { Issue.record("relative"); return }
    }

    @Test func theFolderCardSaysItCameAfterOutsideContent() {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("sf-card-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let spec = FolderProbe(paths: []).spec
        for tainted in [false, true] {
            let d = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(writePaths: [outside.path + "/a.txt"]),
                                                caller: Self.agent, tainted: tainted, policy: GuardPolicy(mode: .auto), grants: [], folders: [])
            guard case .ask(let card) = d else { Issue.record("\(d)"); continue }
            #expect(card.tainted == tainted, "so the card can say a page may be steering which folder, and offer sharing for good only on purpose")
        }
    }

    /// What Auto now runs after outside content reaches nothing off the Mac; a step that changes how Sidefolk behaves stays a card.
    @Test func autoStillAsksForStepsThatChangeSidefolkItselfAfterOutsideContent() {
        func decide(_ caps: Set<Capability>, mutates: Bool, mode: GuardMode = .auto) -> GuardDecision {
            let spec = ToolSpec(name: "t.x", title: "X", description: "", inputSchema: .object([:]), risk: .medium, capabilities: caps, category: .system, mutates: mutates)
            return PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: .none, caller: Self.agent, tainted: true,
                                               policy: GuardPolicy(mode: mode), grants: [], folders: [])
        }
        for caps: Set<Capability> in [[.system]] {
            guard case .ask = decide(caps, mutates: true) else { Issue.record("a mutating system step asks after outside content: \(caps)"); continue }
            #expect(decide(caps, mutates: true, mode: .fullAccess) == .allow(.fullAccess))
        }
        // Reads and steps that stay in Sidefolk run.
        #expect(decide([.system], mutates: false) == .allow(.autoMode))
        #expect(decide([.macApps], mutates: false) == .allow(.autoMode))
        #expect(decide([.calendar], mutates: false) == .allow(.autoMode))
        #expect(decide([.notebook], mutates: true) == .allow(.autoMode))
    }

    // MARK: Remembering what can be taken back

    private func trash(_ mode: GuardMode, tainted: Bool, caller: Caller = FullAccessMeansFullTests.agent, name: String = "files.trash",
                       caps: Set<Capability> = [.filesWrite]) -> ApprovalRequest? {
        let spec = ToolSpec(name: name, title: "Trash", description: "", inputSchema: .object([:]), risk: .high, capabilities: caps,
                            category: .files, mutates: true)
        let folder = FileManager.default.temporaryDirectory.path
        let d = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(writePaths: [folder + "/a.txt"]),
                                            caller: caller, tainted: tainted, policy: GuardPolicy(mode: mode), grants: [],
                                            folders: [GrantedFolder(path: folder, access: .readwrite)])
        if case .ask(let r) = d { return r }
        return nil
    }

    @Test func autoAsksOncePerRequestForWhatGoesToTheTrash() {
        #expect(trash(.auto, tainted: false)?.canAllowForRequest == true)
        #expect(trash(.auto, tainted: true)?.canAllowForRequest == true)
        // Removing Apple Notes shows its list to read in full, so it stays a card every time.
        #expect(PermissionEngine.recoverable == ["files.trash"])
        // Not for what can't be taken back, not in the other modes, not for other callers.
        #expect(trash(.auto, tainted: false, name: "calendar.delete", caps: [.calendarWrite])?.canAllowForRequest == false)
        #expect(trash(.auto, tainted: false, name: "watch.create", caps: [.watch, .shell])?.canAllowForRequest == false)
        #expect(trash(.askOncePerKind, tainted: false)?.canAllowForRequest == false)
        #expect(trash(.askEveryTime, tainted: false)?.canAllowForRequest == false)
        #expect(trash(.auto, tainted: false, caller: .external(client: "codex"))?.canAllowForRequest == false)
        #expect(trash(.auto, tainted: false, caller: .routine(id: "r"))?.canAllowForRequest == false)
        #expect(trash(.fullAccess, tainted: true) == nil, "Full access runs it")
    }

    @Test func oneCardForTheRestOfTheRunForTheTrashAndNotForTheNextRun() async throws {
        let env = try TestEnv()
        let shared = try await sharedFolder(env)
        defer { try? FileManager.default.removeItem(atPath: shared) }
        env.registry.register(ProbeTool(name: "files.trash", risk: .high, capabilities: [.filesWrite], scope: { _ in ToolScope(writePaths: [shared + "/a.txt"]) },
                                        result: { _ in ToolResult(text: "Moved to the Trash.") }))
        try await env.permissions.setPolicy(GuardPolicy(mode: .auto))
        let counter = CallCounter()
        let stream = env.events.stream()
        let broker = env.broker
        let answering = Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                counter.bump()
                await broker.resolve(id: r.id, decision: .allowForRequest)
            }
        }
        defer { answering.cancel() }
        let one = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        for _ in 1...3 { #expect(await one.call("files.trash", input: ["x": "a"]).isOK) }
        #expect(counter.value == 1)
        await one.close()
        let two = BrainToolbox(runId: "run-2", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await two.call("files.trash", input: ["x": "a"])
        #expect(counter.value == 2)
    }

    @Test func anExtensionsToolGetsForThisRequestAfterOutsideContentUnlessItRunsPrograms() {
        func card(_ caps: Set<Capability>, caller: Caller = FullAccessMeansFullTests.agent, tainted: Bool = true) -> ApprovalRequest? {
            let spec = ToolSpec(name: "ext.poster.post", title: "Post", description: "", inputSchema: .object([:]), risk: .medium, capabilities: caps,
                                category: .extensions, mutates: true)
            let d = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(extensionId: "com.acme.poster"),
                                                caller: caller, tainted: tainted, policy: GuardPolicy(mode: .auto), grants: [], folders: [])
            if case .ask(let r) = d { return r }
            return nil
        }
        #expect(card([.extensions])?.canAllowForRequest == true)
        #expect(card([.extensions, .network])?.canAllowForRequest == false, "a yes given while a page steers must not cover later calls to a network")
        #expect(card([.extensions, .shell])?.canAllowForRequest == false, "an unsandboxed program stays a card every time")
        #expect(card([.extensions], caller: .external(client: "codex"))?.canAllowForRequest == false)
        #expect(card([.extensions], caller: .extension(id: "dev.x.y"))?.canAllowForRequest == false)
        // And "Always" is still a clean turn's: an extension's grant isn't offered after outside content.
        #expect(card([.extensions])?.canAlways == false)
    }
}
