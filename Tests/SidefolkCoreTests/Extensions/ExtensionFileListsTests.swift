import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Several dropped files, each granted by itself (D141), and a drop as the person's own act (SECURITY T43).
@Suite(.serialized) struct ExtensionFileListsTests {
    private static let program = #"""
    import json, os, sys
    HOME = os.environ.get("HOME", "")
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    def attempt(fn):
        try:
            return fn()
        except OSError:
            return "refused"
    for line in sys.stdin:
        m = json.loads(line)
        method, id = m.get("method"), m.get("id")
        if id is None: continue
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "make", "description": "Makes files.", "inputSchema": {"type": "object"}}]}})
        elif method == "tools/call":
            a = m["params"]["arguments"]
            files, outputs, read = a.get("files", []), [], []
            for i, path in enumerate(files):
                read.append(attempt(lambda: open(path).read()))
                name = f"made{i}.bin"
                open(os.path.join(HOME, name), "w").write(str(i))
                stem = os.path.splitext(os.path.basename(path))[0]
                outputs.append({"data": name, "name": stem + " made.txt", "source": path})
            sibling = attempt(lambda: open(a["sibling"]).read()) if "sibling" in a else ""
            send({"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": json.dumps({"read": read, "sibling": sibling, "keys": sorted(a.keys())})}], "sidefolk": {"outputs": outputs}}})
        else:
            send({"jsonrpc": "2.0", "id": id, "result": {}})
    """#

    private func installed() async throws -> (HostEnv, String) {
        let h = try HostEnv()
        let tools: JSONValue = ["make": ["risk": "low", "file_lists": ["files": "read"], "paths": ["extra": "read"], "outputs": ["txt"]]]
        let source = try h.source("lister", manifest: ExtFixtures.manifest(id: "dev.test.lister", tools: tools), files: ["server.py": Self.program])
        _ = try await h.host.install(from: source)
        let folder = FolderAccess.canonical(try ExtFixtures.tempDir("dropped").path)!
        for name in ["a", "b", "c", "other"] { try Data(name.utf8).write(to: URL(fileURLWithPath: "\(folder)/\(name).txt")) }
        return (h, folder)
    }

    private func answer(_ outcome: ToolOutcome) -> JSONValue? {
        guard case .ok(let r) = outcome.status, let line = r.text.split(separator: "\n").first else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    /// What the drop card may promise comes from the permissions, not from the extension.
    @Test func theCardKnowsHowAFileCouldLeave() async throws {
        try await card([:], canSendAway: false, withoutInternet: false)
        try await card(["media": true], canSendAway: true, withoutInternet: true)
        try await card(["clipboard": true], canSendAway: true, withoutInternet: true)
        try await card(["network": true], canSendAway: true, withoutInternet: false)
        try await card(["media": true, "network": true], canSendAway: true, withoutInternet: false)
    }

    private func card(_ permissions: JSONValue, canSendAway: Bool, withoutInternet: Bool) async throws {
        let h = try HostEnv()
        let tools: JSONValue = ["make": ["risk": "low", "file_lists": ["files": "read"]]]
        let drops: JSONValue = [["id": "make", "title": "Make", "kinds": ["file"], "tool": "make", "input": ["files": "{values}"]]]
        let source = try h.source("lister", manifest: ExtFixtures.manifest(id: "dev.test.lister", tools: tools, permissions: permissions, extra: ["drops": drops]),
                                  files: ["server.py": Self.program])
        _ = try await h.host.install(from: source)
        let offer = try #require(h.host.shelf.drops.first)
        #expect(offer.canSendAway == canSendAway)
        #expect(offer.canSendAwayWithoutInternet == withoutInternet)
        await h.host.shutdown()
    }

    @Test func eachDroppedFileIsReadAndGetsItsResultBesideIt() async throws {
        let (h, folder) = try await installed()
        let files = ["a", "b", "c"].map { "\(folder)/\($0).txt" }
        let input: JSONValue = ["files": .array(files.map { .string($0) })]
        let outcome = await h.env.executor.execute(name: "ext.lister.make", input: input, caller: .user, pickedFiles: files)
        #expect(answer(outcome)?["read"] == ["a", "b", "c"])
        guard case .ok(let result) = outcome.status else { Issue.record("not ok"); return }
        #expect(Set(result.placed.map(\.path)) == Set(["a", "b", "c"].map { "\(folder)/\($0) made.txt" }))
    }

    @Test func aFileBesideThemStaysClosed() async throws {
        let (h, folder) = try await installed()
        let files = ["\(folder)/a.txt"]
        let input: JSONValue = ["files": .array(files.map { .string($0) }), "sibling": .string("\(folder)/other.txt")]
        let outcome = await h.env.executor.execute(name: "ext.lister.make", input: input, caller: .user, pickedFiles: files)
        #expect(answer(outcome)?["sibling"]?.stringValue == "refused")
    }

    @Test func aPathNamedInTheInputGetsNoGrant() async throws {
        let (h, folder) = try await installed()
        // A page or a model naming paths isn't handing anything over.
        let input: JSONValue = ["files": [.string("\(folder)/a.txt")]]
        let asUser = await h.env.executor.execute(name: "ext.lister.make", input: input, caller: .user, approvalTimeout: 0.2)
        if case .ok(let r) = asUser.status { #expect(r.placed.isEmpty) }
        #expect(!FileManager.default.fileExists(atPath: "\(folder)/a made.txt"))
    }

    @Test(arguments: [Caller.command(extensionId: "dev.test.lister"), Caller.extension(id: "dev.test.lister")])
    func onlyThePersonCanHandFilesOver(caller: Caller) async throws {
        let (h, folder) = try await installed()
        let files = ["\(folder)/a.txt"]
        _ = await h.env.executor.execute(name: "ext.lister.make", input: ["files": .array(files.map { .string($0) })], caller: caller, approvalTimeout: 0.2, pickedFiles: files)
        #expect(!FileManager.default.fileExists(atPath: "\(folder)/a made.txt"))
    }

    @Test func aLinkToSomethingPrivateIsJudgedAsThat() async throws {
        let (h, folder) = try await installed()
        let hidden = "\(folder)/.secret"
        try FileManager.default.createDirectory(atPath: hidden, withIntermediateDirectories: true)
        try Data("key".utf8).write(to: URL(fileURLWithPath: "\(hidden)/key.txt"))
        symlink("\(hidden)/key.txt", "\(folder)/photo.txt")
        let files = ["\(folder)/photo.txt"]
        let outcome = await h.env.executor.execute(name: "ext.lister.make", input: ["files": .array(files.map { .string($0) })], caller: .user, pickedFiles: files)
        if case .ok(let r) = outcome.status { #expect(!r.text.contains("key")) }
    }

    @Test func aFolderInTheListIsRefused() async throws {
        let (h, folder) = try await installed()
        let inside = "\(folder)/sub"
        try FileManager.default.createDirectory(atPath: inside, withIntermediateDirectories: true)
        let outcome = await h.env.executor.execute(name: "ext.lister.make", input: ["files": [.string(inside)]], caller: .user, pickedFiles: [inside])
        #expect(outcome.okText == nil)
    }

    @Test func tooManyFilesAreRefusedBeforeAnythingRuns() async throws {
        let (h, folder) = try await installed()
        let files = (0...ExtensionOutputs.maxFiles).map { "\(folder)/\($0).txt" }
        let outcome = await h.env.executor.execute(name: "ext.lister.make", input: ["files": .array(files.map { .string($0) })], caller: .user, pickedFiles: files)
        #expect(outcome.okText == nil)
    }

    @Test func aRetryHasNoGrant() async throws {
        // `runSkipped` passes no picked files, so what a skipped step runs was never handed over (D141).
        let context = ToolContext(caller: .user, now: Date())
        #expect(context.handedOver.isEmpty)
    }

    @Test func historyKeepsEveryFile() {
        let files = (0..<ExtensionOutputs.maxFiles).map { JSONValue.string("/f/\($0).txt") }
        #expect(Redactor.arguments(.array(files)).arrayValue?.count == ExtensionOutputs.maxFiles)
    }

    @Test func aHandedOverFolderIsRefusedThroughPathsToo() async throws {
        let h = try HostEnv()
        let tools: JSONValue = ["make": ["risk": "low", "paths": ["path": "read"]]]
        let source = try h.source("single", manifest: ExtFixtures.manifest(id: "dev.test.single", tools: tools), files: ["server.py": Self.program])
        _ = try await h.host.install(from: source)
        let folder = FolderAccess.canonical(try ExtFixtures.tempDir("dropped").path)!
        let outcome = await h.env.executor.execute(name: "ext.single.make", input: ["path": .string(folder)], caller: .user, pickedFile: folder)
        #expect(outcome.okText == nil)
    }


    @Test func aNameCantHoldALineBreak() throws {
        let h = try HostEnv()
        var manifest = ExtFixtures.manifest(id: "dev.test.named")
        if case .object(var fields) = manifest {
            fields["name"] = "Checked: stays on this Mac.\nCourier"
            manifest = .object(fields)
        }
        let source = try h.source("named", manifest: manifest)
        #expect(!ExtensionValidator.validate(at: source, paths: h.paths).isValid)
    }

    @Test func removingKeysLeavesTheRest() {
        let input: JSONValue = ["path": "/secret", "quality": "high"]
        #expect(input.removing(["path"]) == ["quality": "high"])
        #expect(input.removing([]) == input)
    }

    // MARK: The offers

    private func action(input: [String: JSONValue], kinds: [ExtensionManifest.DropMeta.Kind] = [.file], patterns: [String] = [], paths: Set<String> = [],
                        menu: [ExtensionManifest.DropMeta.MenuItem] = []) -> ExtensionDropAction {
        ExtensionDropAction(extensionId: "dev.t", extensionName: "T", key: "k", title: "Do", kinds: kinds, patterns: patterns, tool: "ext.t.do", input: input, menu: menu, pathParameters: paths)
    }

    @Test func aTemplateCantPlantAPath() {
        let drop = action(input: ["path": "{value}", "other": "/Users/me/.ssh/id_rsa", "quality": "high"], paths: ["path", "other"])
        #expect(drop.input(forFiles: ["/d/a.jpg"]) == ["path": "/d/a.jpg", "quality": "high"])
    }

    @Test func aMenuChoiceCantPlantAPathEither() {
        let item = ExtensionManifest.DropMeta.MenuItem(title: "Sneaky", input: ["other": "/secret", "format": "png"])
        let drop = action(input: ["files": "{values}"], paths: ["files", "other"], menu: [item])
        #expect(drop.input(forFiles: ["/d/a.jpg"], choosing: item) == ["files": ["/d/a.jpg"], "format": "png"])
    }

    @Test func severalFilesNeedAnActionThatTakesAList() {
        let one = action(input: ["path": "{value}"])
        let many = action(input: ["files": "{values}"])
        #expect(DropChoices.offers(forFiles: ["/a.jpg", "/b.jpg"], among: [one]).isEmpty)
        #expect(DropChoices.offers(forFiles: ["/a.jpg", "/b.jpg"], among: [many]).count == 1)
        #expect(DropChoices.offers(forFiles: ["/a.jpg"], among: [one, many]).count == 2)
    }

    @Test func everyFileMustFitThePattern() {
        let drop = action(input: ["files": "{values}"], patterns: ["*.jpg"])
        #expect(DropChoices.offers(forFiles: ["/a.jpg", "/b.png"], among: [drop]).isEmpty)
    }

    @Test func aLinkGetsNoOffersWhateverItsCalled() throws {
        let folder = FolderAccess.canonical(try ExtFixtures.tempDir("links").path)!
        defer { ExtensionFiles.removeTree(folder) }
        let target = folder + "/passport.pdf", link = folder + "/holiday.jpg"
        try Data("x".utf8).write(to: URL(fileURLWithPath: target))
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        let drop = action(input: ["files": "{values}"])
        #expect(DropChoices.offers(forFiles: [link], among: [drop]).isEmpty)
    }

    @Test func aNameOnTheCardIsOneLine() {
        #expect(DropChoices.shownName("/x/trip\nSidefolk checked this.jpg") == "trip Sidefolk checked this.jpg")
    }

    @Test func tooManyFilesGetNoOffers() {
        let drop = action(input: ["files": "{values}"])
        #expect(DropChoices.offers(forFiles: (0...ExtensionOutputs.maxFiles).map { "/\($0).jpg" }, among: [drop]).isEmpty)
    }

    // MARK: The manifest

    private func valid(tools: JSONValue, drops: JSONValue) throws -> Bool {
        let h = try HostEnv()
        let source = try h.source("x", manifest: ExtFixtures.manifest(id: "dev.test.x", tools: tools, extra: ["drops": drops]))
        return ExtensionValidator.validate(at: source, paths: h.paths).isValid
    }

    @Test func aListOfValuesNeedsAFileList() throws {
        #expect(try valid(tools: ["echo": ["file_lists": ["files": "read"]]], drops: [["id": "d", "title": "Do", "kinds": ["file"], "tool": "echo", "input": ["files": "{values}"]]]))
        #expect(try !valid(tools: ["echo": ["paths": ["files": "read"]]], drops: [["id": "d", "title": "Do", "kinds": ["file"], "tool": "echo", "input": ["files": "{values}"]]]))
        #expect(try !valid(tools: ["echo": ["file_lists": ["files": "read"]]], drops: [["id": "d", "title": "Do", "kinds": ["link"], "tool": "echo", "input": ["files": "{values}"]]]))
    }

    @Test func aFileListIsReadOnly() throws {
        #expect(try !valid(tools: ["echo": ["file_lists": ["files": "write"]]], drops: []))
    }

    @Test func theMenuIsBounded() throws {
        let tools: JSONValue = ["echo": ["file_lists": ["files": "read"]]]
        func drops(_ count: Int, title: String = "PNG") -> JSONValue {
            [["id": "d", "title": "Do", "kinds": ["file"], "tool": "echo", "input": ["files": "{values}"], "menu": .array((0..<count).map { _ in ["title": .string(title), "input": ["f": "png"]] })]]
        }
        #expect(try valid(tools: tools, drops: drops(12)))
        #expect(try !valid(tools: tools, drops: drops(13)))
        #expect(try !valid(tools: tools, drops: drops(1, title: String(repeating: "x", count: 31))))
    }
}
