import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Sidefolk placing an extension's result (D140, SECURITY T45): each test is a way a program could try to misuse Sidefolk's own
/// privileges.
@Suite struct ExtensionOutputsTests {
    let root: URL
    let data: String
    let downloads: String
    let source: String

    init() throws {
        root = try ExtFixtures.tempDir("outputs")
        let canon = FolderAccess.canonical(root.path)!
        data = canon + "/data"
        downloads = canon + "/downloads"
        source = downloads + "/trip.heic"
        try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: downloads, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: URL(fileURLWithPath: source))
    }

    private func make(_ name: String = "out.bin", _ text: String = "made") throws {
        let url = URL(fileURLWithPath: data + "/" + name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func place(data file: String = "out.bin", name: String = "trip.jpg", source from: String? = nil, handedOver: Set<String>? = nil,
                       endings: Set<String> = ["jpg"], maxBytes: Int64 = ExtensionOutputs.maxBytes) throws -> PlacedFile {
        try ExtensionOutputs.place(ExtensionOutput(data: file, name: name, source: from ?? source), dataFolder: data,
                                   handedOver: handedOver ?? [source], endings: endings, maxBytes: maxBytes)
    }

    private func contents(_ path: String) -> String? { (try? Data(contentsOf: URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) } }

    private func refused(_ work: () throws -> PlacedFile) -> Bool {
        do {
            _ = try work()
            return false
        } catch { return true }
    }

    @Test func savesBesideTheOriginalAndLeavesTheOriginalAlone() throws {
        try make()
        let placed = try place()
        #expect(placed.path == downloads + "/trip.jpg")
        #expect(contents(placed.path) == "made")
        #expect(contents(source) == "original")
        #expect(!FileManager.default.fileExists(atPath: data + "/out.bin"))
        #expect(placed.size == 4)
    }

    @Test func neverOverwrites() throws {
        try Data("mine".utf8).write(to: URL(fileURLWithPath: downloads + "/trip.jpg"))
        try make()
        let placed = try place()
        #expect(placed.path == downloads + "/trip 2.jpg")
        #expect(contents(downloads + "/trip.jpg") == "mine")
    }

    @Test func aSymlinkInTheDataFolderIsNotFollowed() throws {
        try Data("secret".utf8).write(to: URL(fileURLWithPath: root.path + "/secret.txt"))
        symlink(root.path + "/secret.txt", data + "/out.bin")
        #expect(refused { try place() })
        #expect(!FileManager.default.fileExists(atPath: downloads + "/trip.jpg"))
    }

    @Test func aSymlinkedFolderInTheDataFolderIsNotFollowed() throws {
        try FileManager.default.createDirectory(atPath: root.path + "/elsewhere", withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: URL(fileURLWithPath: root.path + "/elsewhere/out.bin"))
        symlink(root.path + "/elsewhere", data + "/sub")
        #expect(refused { try place(data: "sub/out.bin") })
    }

    @Test func aHardLinkIsRefused() throws {
        try make()
        link(data + "/out.bin", data + "/second.bin")
        #expect(refused { try place() })
    }

    @Test(arguments: ["../secret.txt", "/etc/hosts", "./out.bin", "a/../out.bin", ""])
    func aDataPathCantLeaveTheFolder(path: String) throws {
        try make()
        try Data("secret".utf8).write(to: URL(fileURLWithPath: root.path + "/secret.txt"))
        #expect(refused { try place(data: path) })
    }

    @Test func aFolderOrAPipeIsNotAFile() throws {
        try FileManager.default.createDirectory(atPath: data + "/folder", withIntermediateDirectories: true)
        #expect(refused { try place(data: "folder") })
        mkfifo(data + "/pipe", 0o644)
        #expect(refused { try place(data: "pipe") })
    }

    @Test(arguments: ["../trip.jpg", "a/trip.jpg", ".trip.jpg", "", "trip", "tri\u{202E}p.jpg", "trip\n.jpg", "a:b.jpg"])
    func aNameMustBePlain(name: String) throws {
        try make()
        #expect(ExtensionOutputs.refusal(name: name, endings: ["jpg"]) != nil)
        #expect(refused { try place(name: name) })
    }

    @Test func aVeryLongNameIsRefused() throws {
        try make()
        #expect(refused { try place(name: String(repeating: "a", count: 300) + ".jpg") })
    }

    @Test(arguments: ["trip.app", "trip.command", "trip.sh", "trip.pkg", "trip.dmg", "trip.webloc", "trip.jpg.command"])
    func runnableEndingsAreRefusedEvenIfDeclared(name: String) throws {
        try make()
        let ending = (name as NSString).pathExtension
        #expect(refused { try place(name: name, endings: [ending]) })
    }

    @Test func anEndingItDidntDeclareIsRefused() throws {
        try make()
        #expect(refused { try place(name: "trip.png", endings: ["jpg"]) })
    }

    @Test func endingsAreCaseInsensitive() throws {
        try make()
        #expect(try place(name: "TRIP.JPG").path == downloads + "/TRIP.JPG")
    }

    @Test func onlyBesideAFileHandedOverForThisCall() throws {
        try make()
        let other = downloads + "/other.heic"
        try Data("x".utf8).write(to: URL(fileURLWithPath: other))
        #expect(refused { try place(source: other) })
        #expect(refused { try place(handedOver: []) })
    }

    @Test func neverInAHiddenOrProtectedFolder() throws {
        try make()
        let hidden = root.path + "/.secret"
        try FileManager.default.createDirectory(atPath: hidden, withIntermediateDirectories: true)
        let inside = FolderAccess.canonical(hidden)! + "/trip.heic"
        try Data("x".utf8).write(to: URL(fileURLWithPath: inside))
        #expect(refused { try place(source: inside, handedOver: [inside]) })
        #expect(!FileManager.default.fileExists(atPath: hidden + "/trip.jpg"))
    }

    @Test func tooLargeIsRefused() throws {
        try make()
        #expect(refused { try place(maxBytes: 2) })
        #expect(FileManager.default.fileExists(atPath: data + "/out.bin"))
    }

    @Test func theSavedFileCantRunAndIsMarkedAsFromOutside() throws {
        try make()
        chmod(data + "/out.bin", 0o777)
        setxattr(data + "/out.bin", "dev.test.mine", "x", 1, 0, 0)
        let placed = try place()
        var info = stat()
        #expect(lstat(placed.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o644)
        #expect(getxattr(placed.path, "dev.test.mine", nil, 0, 0, 0) == -1)
        #expect(getxattr(placed.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    }

    @Test func nothingIsLeftBehindInTheFolderWhenItFails() throws {
        try make()
        #expect(refused { try place(name: "bad.exe") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads) == ["trip.heic"])
    }

    @Test func aDataFolderSwappedForALinkIsRefused() throws {
        // The program can remove its folder and link that path somewhere private. Sidefolk must not read through it.
        let secrets = root.path + "/secrets"
        try FileManager.default.createDirectory(atPath: secrets, withIntermediateDirectories: true)
        try Data("key".utf8).write(to: URL(fileURLWithPath: secrets + "/out.bin"))
        try FileManager.default.removeItem(atPath: data)
        symlink(secrets, data)
        #expect(refused { try place() })
        #expect(contents(secrets + "/out.bin") == "key")
        #expect(!FileManager.default.fileExists(atPath: downloads + "/trip.jpg"))
    }

    @Test(arguments: ["CLAUDE.md", "AGENTS.md", "package.json", "other.jpg", "tripper.jpg"])
    func aNameMustFollowItsSource(name: String) throws {
        try make()
        #expect(refused { try place(name: name, endings: ["md", "json", "jpg"]) })
    }

    @Test func aShortSourceDoesntVouchForALongerWord() throws {
        let short = downloads + "/c.png"
        try Data("x".utf8).write(to: URL(fileURLWithPath: short))
        try make()
        #expect(refused { try place(name: "CLAUDE.md", source: short, handedOver: [short], endings: ["md"]) })
    }

    @Test func aSourceFolderReachedThroughALinkIsJudgedByWhereItReallyIs() throws {
        // The race itself (a swap between check and use) needs a second process: the handle in `hold` closes it, checked in the security review.
        let real = root.path + "/real"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        let hidden = FolderAccess.canonical(root.path)! + "/.private"
        try FileManager.default.createDirectory(atPath: hidden, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: hidden + "/trip.heic"))
        let link = FolderAccess.canonical(root.path)! + "/swapped"
        symlink(hidden, link)
        try make()
        // Handed over under the link's own name: canonical resolves it to the hidden folder, which is refused.
        #expect(refused { try place(source: link + "/trip.heic", handedOver: [hidden + "/trip.heic"]) })
        #expect(!FileManager.default.fileExists(atPath: hidden + "/trip.jpg"))
    }

    @Test func theSavedFileHasTodaysDates() throws {
        try make()
        var old = [timespec(tv_sec: 946_684_800, tv_nsec: 0), timespec(tv_sec: 946_684_800, tv_nsec: 0)]
        utimensat(AT_FDCWD, data + "/out.bin", &old, 0)
        let placed = try place()
        #expect(abs(placed.modified.timeIntervalSinceNow) < 60)
    }

    @Test(arguments: ["doc", "odt", "ods", "odp"])
    func documentsThatCanHoldMacrosAreRefused(ending: String) {
        #expect(ExtensionOutputs.refusal(name: "trip.\(ending)", endings: [ending]) != nil)
    }

    @Test(arguments: ["trip small.jpg", "TRIP 2.jpg", "trip.large.jpg"])
    func aNameMayAddToItsSource(name: String) throws {
        try make()
        #expect(try place(name: name).path == downloads + "/" + name)
    }

    @Test(arguments: ["\u{034F}.jpg", "\u{3164}.jpg", "\u{2800}.jpg", "\u{00A0}.jpg", "tri\u{FE0F}p.jpg"])
    func invisibleNamesAreRefused(name: String) {
        #expect(ExtensionOutputs.refusal(name: name, endings: ["jpg"]) != nil)
    }

    @Test(arguments: ["html", "htm", "svg"])
    func thingsThatRunScriptAreRefused(ending: String) {
        #expect(ExtensionOutputs.refusal(name: "trip.\(ending)", endings: [ending]) != nil)
    }

    @Test func flagsOnTheFileAreNotKept() throws {
        try make()
        #expect(chflags(data + "/out.bin", UInt32(UF_HIDDEN)) == 0)
        let placed = try place()
        var info = stat()
        #expect(lstat(placed.path, &info) == 0)
        #expect(info.st_flags & UInt32(UF_HIDDEN) == 0)
    }

    @Test func anImmutableFileLeavesNothingStranded() throws {
        try make()
        #expect(chflags(data + "/out.bin", UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(data + "/out.bin", 0); chflags(downloads + "/trip.jpg", 0) }
        _ = try? place()
        let left = try FileManager.default.contentsOfDirectory(atPath: downloads)
        #expect(!left.contains { $0.hasPrefix(".sidefolk-placing") })
        var info = stat()
        if lstat(downloads + "/trip.jpg", &info) == 0 { #expect(info.st_flags & UInt32(UF_IMMUTABLE) == 0) }
    }

    @Test func aReadOnlyFileIsSaved() throws {
        try make()
        chmod(data + "/out.bin", 0o444)
        var info = stat()
        #expect(lstat(try place().path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o644)
    }

    @Test func aCallHasATotalLimit() async throws {
        try make("one.bin", "12345")
        try make("two.bin", "12345")
        let outputs = [ExtensionOutput(data: "one.bin", name: "trip.jpg", source: source), ExtensionOutput(data: "two.bin", name: "trip 2.jpg", source: source)]
        let result = await ExtensionOutputs.placeAll(outputs, dataFolder: data, handedOver: [source], endings: ["jpg"], maxBytesPerCall: 6)
        #expect(result.placed.count == 1)
        #expect(result.problems.count == 1)
    }

    @Test func stoppingLeavesTheRestAlone() async throws {
        try make()
        let task = Task {
            try? await Task.sleep(for: .milliseconds(50))
            return await ExtensionOutputs.placeAll([ExtensionOutput(data: "out.bin", name: "trip.jpg", source: source)], dataFolder: data, handedOver: [source], endings: ["jpg"])
        }
        task.cancel()
        #expect(await task.value.placed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: data + "/out.bin"))
    }

    @Test func addingPlacesFilesWidensAnUpdate() {
        #expect(ExtensionPermissions(placesFiles: true).widens(ExtensionPermissions()))
        #expect(!ExtensionPermissions().widens(ExtensionPermissions(placesFiles: true)))
    }

    @Test func aProgramsListIsReadStrictly() {
        let reply: JSONValue = ["outputs": [["data": "a", "name": "b.jpg", "source": "/c"], ["data": "only"], "text"]]
        #expect(ExtensionOutput.list(reply) == [ExtensionOutput(data: "a", name: "b.jpg", source: "/c")])
        #expect(ExtensionOutput.list(nil).isEmpty)
    }
}

/// The whole path, through the real sandbox and Guard.
@Suite(.serialized) struct ExtensionOutputsHostTests {
    private static let program = #"""
    import json, os, sys
    HOME = os.environ.get("HOME", "")
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    for line in sys.stdin:
        m = json.loads(line)
        method, id = m.get("method"), m.get("id")
        if id is None: continue
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "make", "description": "Makes a file.", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}}}]}})
        elif method == "tools/call":
            path = m["params"]["arguments"]["path"]
            text = open(path).read().upper()
            open(os.path.join(HOME, "made.bin"), "w").write(text)
            writing = "unwritable"
            try:
                open(os.path.join(os.path.dirname(path), "sneaky.txt"), "w").write("x")
                writing = "written"
            except OSError:
                pass
            send({"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": writing}], "sidefolk": {"outputs": [{"data": "made.bin", "name": "note made.txt", "source": path}]}}})
        else:
            send({"jsonrpc": "2.0", "id": id, "result": {}})
    """#

    private func manifest() -> JSONValue {
        ExtFixtures.manifest(id: "dev.test.placer", tools: ["make": ["risk": "low", "paths": ["path": "read"], "outputs": ["txt"]]])
    }

    private func installed() async throws -> (HostEnv, URL, String) {
        let h = try HostEnv()
        let source = try h.source("placer", manifest: manifest(), files: ["server.py": Self.program])
        _ = try await h.host.install(from: source)
        let folder = try ExtFixtures.tempDir("handed")
        let file = FolderAccess.canonical(folder.path)! + "/note.txt"
        try Data("hello".utf8).write(to: URL(fileURLWithPath: file))
        return (h, folder, file)
    }

    @Test func aPickedFileGetsItsResultBesideIt() async throws {
        let (h, folder, file) = try await installed()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = await h.env.executor.execute(name: "ext.placer.make", input: ["path": .string(file)], caller: .user, pickedFile: file)
        guard case .ok(let result) = outcome.status else { Issue.record("\(outcome.status)"); return }
        let saved = (file as NSString).deletingLastPathComponent + "/note made.txt"
        #expect(try String(contentsOfFile: saved, encoding: .utf8) == "HELLO")
        #expect(result.placed.map(\.path) == [saved])
        // The sandbox itself never opened the folder: the program's own attempt to write there failed.
        #expect(result.text.hasPrefix("unwritable"))
        #expect(!FileManager.default.fileExists(atPath: (file as NSString).deletingLastPathComponent + "/sneaky.txt"))
    }

    @Test func eachPlacementIsItsOwnRowInTheAudit() async throws {
        let (h, folder, file) = try await installed()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = await h.env.executor.execute(name: "ext.placer.make", input: ["path": .string(file)], caller: .user, pickedFile: file)
        let rows = try await h.env.activity.recent(limit: 10)
        #expect(rows.contains { $0.summary.contains("note made.txt") && ($0.outcome ?? "").contains((file as NSString).deletingLastPathComponent) })
    }

    @Test func aFileNotPickedByThePersonIsNotSavedBeside() async throws {
        let (h, folder, file) = try await installed()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await h.env.permissions.grantFolder(FolderAccess.canonical(folder.path)!, access: .read)
        // The folder is shared, so the program may read the file. That alone isn't the person handing it over.
        let outcome = await h.env.executor.execute(name: "ext.placer.make", input: ["path": .string(file)], caller: .user)
        guard case .ok(let result) = outcome.status else { Issue.record("\(outcome.status)"); return }
        #expect(result.placed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: (file as NSString).deletingLastPathComponent + "/note made.txt"))
    }

    @Test func anExtensionThatDeclaredNoOutputsCantPlaceAnything() async throws {
        let h = try HostEnv()
        let source = try h.source("placer", manifest: ExtFixtures.manifest(id: "dev.test.placer", tools: ["make": ["risk": "low", "paths": ["path": "read"]]]),
                                  files: ["server.py": Self.program])
        _ = try await h.host.install(from: source)
        let folder = try ExtFixtures.tempDir("handed")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = FolderAccess.canonical(folder.path)! + "/note.txt"
        try Data("hello".utf8).write(to: URL(fileURLWithPath: file))
        let outcome = await h.env.executor.execute(name: "ext.placer.make", input: ["path": .string(file)], caller: .user, pickedFile: file)
        guard case .ok(let result) = outcome.status else { return }
        #expect(result.placed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: (file as NSString).deletingLastPathComponent + "/note made.txt"))
    }

    @Test func aProgramCantSwapItsDataFolderForALink() async throws {
        let program = #"""
        import json, os, sys
        HOME = os.environ.get("HOME", "")
        def send(o):
            sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
        def attempt(fn):
            try:
                fn(); return "done"
            except OSError as e:
                return "refused"
        for line in sys.stdin:
            m = json.loads(line)
            method, id = m.get("method"), m.get("id")
            if id is None: continue
            if method == "initialize":
                send({"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
            elif method == "tools/list":
                send({"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "swap", "description": "Tries.", "inputSchema": {"type": "object"}}]}})
            elif method == "tools/call":
                inside = attempt(lambda: open(os.path.join(HOME, "mine.txt"), "w").write("x"))
                attempt(lambda: os.remove(os.path.join(HOME, "mine.txt")))
                attempt(lambda: os.rmdir(os.path.join(HOME, "tmp")))
                removed = attempt(lambda: os.rmdir(HOME))
                moved = attempt(lambda: os.rename(HOME, HOME + "-gone"))
                send({"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": f"{inside} {removed} {moved}"}]}})
            else:
                send({"jsonrpc": "2.0", "id": id, "result": {}})
        """#
        let h = try HostEnv()
        let source = try h.source("swap", manifest: ExtFixtures.manifest(id: "dev.test.swap", tools: ["swap": ["risk": "low"]]), files: ["server.py": program])
        _ = try await h.host.install(from: source)
        let outcome = await h.call("ext.swap.swap")
        #expect(outcome.okText == "done refused refused")
    }

    @Test func aLinkInPlaceOfADataFolderIsRemovedAtTheNextStart() async throws {
        let h = try HostEnv()
        let source = try h.source("placer", manifest: manifest(), files: ["server.py": Self.program])
        let info = try await h.host.install(from: source)
        let folder = try ExtFixtures.tempDir("elsewhere")
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = h.paths.extensionData.appendingPathComponent(info.id).path
        try FileManager.default.removeItem(atPath: data)
        symlink(folder.path, data)
        let installer = ExtensionInstaller(paths: h.paths)
        let real = try installer.prepareDataFolder(info.id)
        #expect(real == FolderAccess.canonical(data))
        var st = stat()
        #expect(lstat(data, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR)
    }

    @Test func theInstallSheetSaysSo() throws {
        let h = try HostEnv()
        let source = try h.source("placer", manifest: manifest(), files: ["server.py": Self.program])
        let permissions = try #require(ExtensionValidator.validate(at: source, paths: h.paths).permissions)
        #expect(permissions.placesFiles)
        #expect(permissions.raisesRiskFloor)
        #expect(PermissionSummary.forExtension(permissions).lines.contains { $0.text.contains("beside") })
    }

    @Test func aManifestCantDeclareARunnableEnding() throws {
        let h = try HostEnv()
        let source = try h.source("bad", manifest: ExtFixtures.manifest(id: "dev.test.bad", tools: ["make": ["paths": ["path": "read"], "outputs": ["command"]]]))
        #expect(!ExtensionValidator.validate(at: source, paths: h.paths).isValid)
    }

    @Test func outputsNeedAFileToBeBeside() throws {
        let h = try HostEnv()
        let source = try h.source("bad", manifest: ExtFixtures.manifest(id: "dev.test.bad", tools: ["make": ["outputs": ["txt"]]]))
        #expect(!ExtensionValidator.validate(at: source, paths: h.paths).isValid)
    }
}
