import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// The data folder belongs to Sidefolk even though what's inside belongs to the program. Run through the real host and sandbox.
@Suite(.serialized) struct ExtensionDataFolderTests {
    /// Answers `try` with what each attempt came to, and `write` with where a file really landed.
    private static let program = #"""
    import ctypes, json, os, sys
    HOME = os.environ.get("HOME", "")
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    def attempt(fn):
        try:
            fn(); return "done"
        except OSError:
            return "refused"
    libc = ctypes.CDLL(None, use_errno=True)
    def swap(a, b):
        libc.renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        if libc.renamex_np(a.encode(), b.encode(), 2) != 0:
            raise OSError(ctypes.get_errno(), "swap")
    def tryall(a):
        inner = os.path.join(HOME, "inner")
        os.makedirs(inner, exist_ok=True)
        results = {}
        results["inside"] = attempt(lambda: open(os.path.join(HOME, "mine.txt"), "w").write("x"))
        attempt(lambda: os.remove(os.path.join(HOME, "mine.txt")))
        results["swap"] = attempt(lambda: swap(HOME, inner))
        os.rmdir(inner)
        attempt(lambda: os.rmdir(os.path.join(HOME, "tmp")))
        results["remove"] = attempt(lambda: os.rmdir(HOME))
        results["rename"] = attempt(lambda: os.rename(HOME, HOME + "-gone"))
        results["link"] = attempt(lambda: os.symlink(a["target"], HOME))
        results["tmp_link"] = attempt(lambda: os.symlink(a["target"], os.path.join(HOME, "tmp")))
        results["through_link"] = attempt(lambda: open(os.path.join(HOME, "tmp", "planted.txt"), "w").write("x"))
        return results
    for line in sys.stdin:
        m = json.loads(line)
        method, id = m.get("method"), m.get("id")
        if id is None: continue
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "attempts", "description": "Tries.", "inputSchema": {"type": "object"}}, {"name": "write", "description": "Writes.", "inputSchema": {"type": "object"}}]}})
        elif method == "tools/call":
            a = m["params"].get("arguments", {})
            if m["params"]["name"] == "attempts":
                text = json.dumps(tryall(a))
            else:
                open(os.path.join(HOME, "mine.txt"), "w").write("x")
                text = os.path.realpath(HOME)
            send({"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": text}]}})
        else:
            send({"jsonrpc": "2.0", "id": id, "result": {}})
    """#

    private func manifest() -> JSONValue {
        ExtFixtures.manifest(id: "dev.test.holder", tools: ["attempts": ["risk": "low"], "write": ["risk": "low"]])
    }

    private func installed() async throws -> (HostEnv, String, String) {
        let h = try HostEnv()
        let source = try h.source("holder", manifest: manifest(), files: ["server.py": Self.program])
        let info = try await h.host.install(from: source)
        let target = FolderAccess.canonical(try ExtFixtures.tempDir("private").path)!
        try Data("secret".utf8).write(to: URL(fileURLWithPath: target + "/secret.txt"))
        chmod(target, 0o755)
        return (h, h.paths.extensionData.appendingPathComponent(info.id).path, target)
    }

    private func mode(_ path: String) -> mode_t {
        var info = stat()
        lstat(path, &info)
        return info.st_mode & 0o777
    }

    private func isRealFolder(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private func restarted(_ h: HostEnv) async throws -> ExtensionHost {
        await h.host.shutdown()
        var config = ExtensionHost.Configuration()
        config.callTimeout = 10
        let host = ExtensionHost(paths: h.paths, store: h.store, registry: h.env.registry, events: h.env.events, configuration: config)
        await host.start()
        return host
    }

    @Test func withoutTheNetworkNoServiceThatFetchesIsOpen() throws {
        #expect(!SandboxProfile.baseRules.contains("com.apple.trustd.agent"))
        #expect(SandboxProfile.networkRules.contains("com.apple.trustd.agent"))
        // HEIC and AVIF can't be written without it (the encoder's signature is checked), so `media` says so to the person.
        #expect(SandboxProfile.mediaRules.contains("com.apple.trustd.agent"))
    }

    @Test func noServiceCarriesWordsBetweenExtensionsOrOntoTheLog() {
        #expect(!SandboxProfile.baseRules.contains("com.apple.system.logger"))
        #expect(!SandboxProfile.baseRules.contains("notification_center"))
    }

    /// Inside the checkout, the one folder under /Users a test may use: nothing here touches the person's own files.
    @Test(.enabled(if: #filePath.hasPrefix("/Users/"), "needs a checkout under /Users"))
    func peoplesFoldersAreClosedButTheWayDownToWhatItWasGiven() throws {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = checkout.appendingPathComponent(".build/sandbox-names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = root.appendingPathComponent("data/me"), other = root.appendingPathComponent("elsewhere")
        for folder in [mine, other] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let theirs = other.appendingPathComponent("file"), own = mine.appendingPathComponent("file")
        for file in [theirs, own] { try Data("x".utf8).write(to: file) }
        func runs(_ program: String, _ arguments: String...) throws -> Bool {
            let profile = try SandboxProfile.make(.init(extensionDir: (program as NSString).deletingLastPathComponent, dataDir: mine.path, executable: program,
                                                        permissions: ExtensionPermissions()))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile.text] + profile.arguments + [program] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        #expect(try runs("/usr/bin/stat", own.path))
        #expect(try runs("/bin/test", "-e", root.appendingPathComponent("data").path), "the way down")
        #expect(try !runs("/usr/bin/stat", theirs.path))
        #expect(try !runs("/bin/test", "-e", theirs.path))
        #expect(try !runs("/bin/test", "-e", checkout.appendingPathComponent("Package.swift").path))
        // The same folders by the data volume's own name: an existing name and a missing one must look alike there too.
        let throughTheVolume = "/System/Volumes/Data" + theirs.path
        #expect(try !runs("/bin/test", "-e", throughTheVolume))
        #expect(try !runs("/bin/test", "-e", throughTheVolume + "-missing"))
        #expect(try runs("/bin/test", "-e", "/System/Volumes/Data" + own.path), "what it was given, by that name too")
    }

    /// A home under /Users, in the checkout, with two extensions' data folders and a folder nobody was given.
    private struct PeoplesFolders {
        let root: URL, all: URL, mine: URL, other: URL, elsewhere: URL
        init() throws {
            let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            root = checkout.appendingPathComponent(".build/sandbox-names-\(UUID().uuidString)")
            all = root.appendingPathComponent("ExtensionData")
            mine = all.appendingPathComponent("me")
            other = all.appendingPathComponent("other")
            elsewhere = root.appendingPathComponent("elsewhere")
            for folder in [mine, other, elsewhere] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        }

        /// Its exit status and what it said on the way out.
        func run(_ program: String, _ arguments: String...) throws -> (ok: Bool, said: String) {
            let profile = try SandboxProfile.make(.init(extensionDir: (program as NSString).deletingLastPathComponent, dataDir: mine.path, executable: program,
                                                        permissions: ExtensionPermissions(), allData: all.path))
            let process = Process(), error = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile.text] + profile.arguments + [program] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = error
            try process.run()
            let said = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return (process.terminationStatus == 0, said)
        }
    }

    @Test(.enabled(if: #filePath.hasPrefix("/Users/"), "needs a checkout under /Users"))
    func noExtensionCanListWhoIsInstalledOrWhatTheyKeep() throws {
        let home = try PeoplesFolders()
        defer { try? FileManager.default.removeItem(at: home.root) }
        for file in [home.mine, home.other] { try Data("x".utf8).write(to: file.appendingPathComponent("file")) }
        #expect(try home.run("/usr/bin/stat", home.mine.appendingPathComponent("file").path).ok)
        #expect(try !home.run("/bin/ls", home.all.path).ok)
        #expect(try !home.run("/bin/ls", home.other.path).ok)
    }

    /// A file's number gives nothing away but that it's used: counted, not named.
    @Test(.enabled(if: #filePath.hasPrefix("/Users/"), "needs a checkout under /Users"))
    func aFilesNumberDoesntNameIt() throws {
        let home = try PeoplesFolders()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let hidden = home.elsewhere.appendingPathComponent("file")
        try Data("x".utf8).write(to: hidden)
        var info = stat()
        #expect(lstat(hidden.path, &info) == 0)
        let used = try home.run("/usr/bin/stat", "/.vol/\(info.st_dev)/\(info.st_ino)")
        #expect(!used.ok && used.said.contains("Operation not permitted"), "\(used.said)")
        let unused = try home.run("/usr/bin/stat", "/.vol/\(info.st_dev)/\(UInt64(1) << 60)")
        #expect(!unused.ok && unused.said.contains("No such file"), "\(unused.said)")
    }

    @Test(.enabled(if: #filePath.hasPrefix("/Users/"), "needs a checkout under /Users"))
    func aLinkOpensNothingUnderPeoplesFolders() throws {
        let home = try PeoplesFolders()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let given = home.mine.appendingPathComponent("file"), hidden = home.elsewhere.appendingPathComponent("file")
        for file in [given, hidden] { try Data("x".utf8).write(to: file) }
        // In a folder nobody gave it, pointing at what it was given.
        let toGiven = home.elsewhere.appendingPathComponent("to-given"), outOf = home.mine.appendingPathComponent("out-of")
        try FileManager.default.createSymbolicLink(at: toGiven, withDestinationURL: given)
        // In what it was given, pointing out of it.
        try FileManager.default.createSymbolicLink(at: outOf, withDestinationURL: hidden)
        #expect(try home.run("/bin/test", "-e", given.path).ok)
        #expect(try !home.run("/bin/test", "-e", toGiven.path).ok)
        #expect(try !home.run("/bin/test", "-e", outOf.path).ok)
    }

    @Test func anotherExtensionsDataCantEvenBeSeen() throws {
        let root = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: FileManager.default.temporaryDirectory, create: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let all = root.appendingPathComponent("ExtensionData"), mine = all.appendingPathComponent("me"), other = all.appendingPathComponent("other")
        for folder in [mine, other] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let theirs = other.appendingPathComponent("file"), own = mine.appendingPathComponent("file")
        for file in [theirs, own] { try Data("x".utf8).write(to: file) }
        func canStat(_ path: String) throws -> Bool { try runs("/usr/bin/stat", path) }
        func exists(_ path: String) throws -> Bool { try runs("/bin/test", "-e", path) }
        func runs(_ program: String, _ arguments: String...) throws -> Bool {
            let profile = try SandboxProfile.make(.init(extensionDir: (program as NSString).deletingLastPathComponent, dataDir: mine.path, executable: program,
                                                        permissions: ExtensionPermissions(), allData: all.path))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile.text] + profile.arguments + [program] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        #expect(try canStat(own.path))
        #expect(try !canStat(theirs.path))
        #expect(try !canStat(other.path))
        #expect(try exists(own.path))
        #expect(try !exists(theirs.path))
        #expect(try !exists(other.path))
    }

    @Test func aRunningProgramCantRemoveReplaceOrSwapItsFolder() async throws {
        let (h, data, target) = try await installed()
        let outcome = await h.env.executor.execute(name: "ext.holder.attempts", input: ["target": .string(target)], caller: .user)
        let answer = try #require(outcome.okText)
        let results = try JSONDecoder().decode([String: String].self, from: Data(answer.utf8))
        #expect(results["inside"] == "done")
        #expect(results["swap"] == "refused")
        #expect(results["remove"] == "refused")
        #expect(results["rename"] == "refused")
        #expect(results["link"] == "refused")
        #expect(isRealFolder(data))
        // A link it may make inside its own folder doesn't reach anywhere: the sandbox judges where it really goes.
        #expect(results["through_link"] == "refused")
        #expect(!FileManager.default.fileExists(atPath: target + "/planted.txt"))
    }

    @Test func aLinkAlreadyThereIsRemovedAtStartAndNeverFollowed() async throws {
        let (h, data, target) = try await installed()
        try FileManager.default.removeItem(atPath: data)
        symlink(target, data)
        let host = try await restarted(h)
        let outcome = await h.env.executor.execute(name: "ext.holder.write", input: .object([:]), caller: .user)
        let answer = try #require(outcome.okText)
        #expect(answer == FolderAccess.canonical(data))
        #expect(isRealFolder(data))
        #expect(FileManager.default.fileExists(atPath: data + "/mine.txt"))
        #expect(!FileManager.default.fileExists(atPath: target + "/mine.txt"))
        #expect(!FileManager.default.fileExists(atPath: target + "/tmp"))
        #expect(mode(target) == 0o755)
        #expect(try String(contentsOfFile: target + "/secret.txt", encoding: .utf8) == "secret")
        await host.shutdown()
    }

    @Test func aBrokenLinkAlreadyThereIsReplaced() async throws {
        let (h, data, target) = try await installed()
        try FileManager.default.removeItem(atPath: data)
        symlink(target + "/nowhere", data)
        let host = try await restarted(h)
        #expect(await h.env.executor.execute(name: "ext.holder.write", input: .object([:]), caller: .user).okText == FolderAccess.canonical(data))
        #expect(isRealFolder(data))
        #expect(!FileManager.default.fileExists(atPath: target + "/nowhere"))
        await host.shutdown()
    }

    @Test func aFileAlreadyThereIsReplaced() async throws {
        let (h, data, _) = try await installed()
        try FileManager.default.removeItem(atPath: data)
        try Data("x".utf8).write(to: URL(fileURLWithPath: data))
        let host = try await restarted(h)
        #expect(await h.env.executor.execute(name: "ext.holder.write", input: .object([:]), caller: .user).okText == FolderAccess.canonical(data))
        #expect(isRealFolder(data))
        await host.shutdown()
    }

    @Test func aLinkForItsTemporaryFolderGivesNothingAndChangesNothing() async throws {
        let (h, data, target) = try await installed()
        try FileManager.default.removeItem(atPath: data + "/tmp")
        symlink(target, data + "/tmp")
        let host = try await restarted(h)
        _ = await h.env.executor.execute(name: "ext.holder.write", input: .object([:]), caller: .user)
        #expect(mode(target) == 0o755)
        #expect(!FileManager.default.fileExists(atPath: target + "/mine.txt"))
        await host.shutdown()
    }

    @Test func removingAnExtensionDoesntReachThroughALink() async throws {
        let (h, data, target) = try await installed()
        try FileManager.default.removeItem(atPath: data)
        symlink(target, data)
        await h.host.shutdown()
        ExtensionFiles.removeTree(data)
        #expect(FileManager.default.fileExists(atPath: target + "/secret.txt"))
        var info = stat()
        #expect(lstat(data, &info) != 0)
    }

    @Test func aDataFolderLinkedThroughItsParentStillWorks() throws {
        // The folder all data folders sit in may itself be reached through a link (a moved home): that's the person's doing, not a program's.
        let root = try ExtFixtures.tempDir("moved")
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let home = root.appendingPathComponent("home")
        symlink(real.path, home.path)
        let paths = SidefolkPaths(home: home)
        try paths.prepare()
        let folder = try ExtensionInstaller(paths: paths).prepareDataFolder("dev.test.moved")
        #expect(folder == FolderAccess.canonical(real.path)! + "/ExtensionData/dev.test.moved")
    }
}
