import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Sidefolk's AI building an extension for the person (D39): drafts are text it writes into its own
/// folder, checked and started once with nothing granted, then handed to the install preview. Installing
/// stays the person's click.
@Suite(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
struct ExtensionBuilderTests {
    /// The smallest draft program: one tool, `greet`. With a secret path given, it refuses to start if it can read it.
    static let program = #"""
    import json, sys
    SECRET = %SECRET%
    if SECRET:
        try:
            open(SECRET).read()
            sys.exit(3)  # it could read a folder its trial shouldn't have
        except OSError:
            pass
    TOOLS = [{"name": "greet", "title": "Greet someone", "description": "Says hello.",
              "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}, "additionalProperties": False}}]
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m:
            continue
        if m["method"] == "initialize":
            r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "greeter", "version": "0.1.0"}}
        elif m["method"] == "tools/list":
            r = {"tools": TOOLS}
        elif m["method"] == "tools/call":
            r = {"content": [{"type": "text", "text": "Hello, %s!" % m["params"]["arguments"].get("name", "you")}]}
        else:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "no"}}) + "\n")
            sys.stdout.flush()
            continue
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n")
        sys.stdout.flush()
    """#

    static func manifest(permissions: JSONValue = .object([:]), tools: JSONValue = ["greet": ["title": "Greet someone", "risk": "low"]]) -> JSONValue {
        ["name": "Greeter", "version": "0.1.0", "sidefolk": ">=0.1", "description": "Greets people.",
         "run": ["command": "python3", "args": ["main.py"]], "permissions": permissions, "tools": tools]
    }

    static func files(secret: String? = nil) -> JSONValue {
        ["main.py": .string(program.replacingOccurrences(of: "%SECRET%", with: secret.map { "\"\($0)\"" } ?? "None"))]
    }

    /// A host plus the builder tools, as the runtime registers them; deleted drafts are removed, not trashed.
    static func environment() throws -> (HostEnv, ExtensionDrafts) {
        let h = try HostEnv()
        let drafts = ExtensionDrafts(directory: h.paths.extensionDrafts) { url in ExtensionFiles.removeTree(url.path) }
        h.env.registry.register(ExtensionBuilderTools.all(drafts: drafts, host: h.host, events: h.env.events))
        return (h, drafts)
    }

    @Test func aDraftIsTextSidefolkOwns() throws {
        let (h, drafts) = try Self.environment()
        let folder = try drafts.write(name: "greeter", manifest: Self.manifest(), files: ["main.py": "print()", "lib/notes.md": "# notes"])
        #expect(folder.lastPathComponent == "local.greeter")
        let manifest = try JSONValue.parse(String(decoding: Data(contentsOf: folder.appendingPathComponent(ExtensionManifest.fileName)), as: UTF8.self))
        #expect(manifest["id"] == "local.greeter")
        #expect(manifest["author"] == .string(ExtensionDrafts.author))
        for file in ["main.py", "lib/notes.md", ExtensionManifest.fileName] {
            let mode = ExtensionFS.lstat(folder.appendingPathComponent(file).path).map { $0.st_mode & 0o777 }
            #expect(mode == 0o600, "\(file): never executable, only Sidefolk reads it")
        }
        // Writing again replaces the whole draft.
        try drafts.write(name: "greeter", manifest: Self.manifest(), files: ["main.py": "print(1)"])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("lib").path))
        #expect(drafts.list().map(\.name) == ["greeter"])
        #expect(try drafts.read(name: "greeter").map(\.path) == [ExtensionManifest.fileName, "main.py"])
        try drafts.delete(name: "greeter")
        #expect(drafts.list().isEmpty)
        _ = h
    }

    @Test func draftsRefuseWhatIsntPlainText() throws {
        let (_, drafts) = try Self.environment()
        let bad: [(String, JSONValue, [String: String], String)] = [
            ("Greeter", Self.manifest(), ["main.py": "x"], "lowercase letters"),
            ("g", Self.manifest().setting("icon", "icon.png"), ["main.py": "x"], "Leave “icon” out"),
            ("g", Self.manifest(), [:], "at least its program"),
            ("g", Self.manifest(), ["../escape.py": "x"], "plain relative file name"),
            ("g", Self.manifest(), [".env": "x"], "plain relative file name"),
            ("g", Self.manifest(), ["tool.bin": "x"], "must be one of"),
            ("g", Self.manifest(), [ExtensionManifest.fileName: "{}"], "Pass the manifest"),
            ("g", Self.manifest(), ["main.py": String(repeating: "x", count: 210 * 1024)], "larger than 200 KB"),
            ("g", "not an object", ["main.py": "x"], "JSON object"),
        ]
        for (name, manifest, files, message) in bad {
            #expect(throws: UserFacingError.self, "\(message)") { try drafts.write(name: name, manifest: manifest, files: files) }
            do { try drafts.write(name: name, manifest: manifest, files: files) } catch let e as UserFacingError {
                #expect(e.message.contains(message), "\(e.message)")
            } catch {}
        }
        #expect(drafts.list().isEmpty)
    }

    @Test func draftingChecksItAndStartsItWithNothingGranted() async throws {
        let (h, _) = try Self.environment()
        // It asks to read a folder holding a secret; its trial must not get that folder.
        let secretDir = h.root.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: secretDir, withIntermediateDirectories: true)
        let secret = secretDir.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)
        let outcome = await h.env.executor.execute(
            name: "extensions.draft",
            input: ["name": "greeter", "manifest": Self.manifest(permissions: ["files": ["read": [.string(secretDir.path)]]]),
                    "files": Self.files(secret: secret.path)],
            caller: .agent(runId: "r"))
        let text = try #require(outcome.okText, "\(outcome.status)")
        #expect(text.contains("Valid."), "\(text)")
        #expect(text.contains("Can read"), "the install checks name what it asks for")
        #expect(text.contains("It started in its sandbox and offers 1 tool: ext.greeter.greet"), "\(text)")
        #expect(text.contains("extensions.review"))
        #expect(!outcome.untrusted, "its own words, and the program it wrote")
        // Nothing is installed by drafting.
        #expect(await h.host.extensions().isEmpty)
        #expect(h.env.registry.tool(named: "ext.greeter.greet") == nil)
    }

    @Test func aDraftWithProblemsSaysWhatToFix() async throws {
        let (h, _) = try Self.environment()
        let outcome = await h.env.executor.execute(
            name: "extensions.draft",
            input: ["name": "greeter", "manifest": Self.manifest(tools: ["Greet": ["risk": "low"]]), "files": Self.files()],
            caller: .agent(runId: "r"))
        let text = try #require(outcome.okText)
        #expect(text.contains("tools.Greet") && text.contains("Not valid"), "\(text)")
        #expect(text.contains("call extensions.draft again"))
        #expect(!text.contains("Started once"), "no trial for a draft that fails the checks")
    }

    @Test func onlyACleanRequestFromThePersonCanBuild() async throws {
        let (h, _) = try Self.environment()
        let input: JSONValue = ["name": "greeter", "manifest": Self.manifest(), "files": Self.files()]
        let tainted = await h.env.executor.execute(name: "extensions.draft", input: input, caller: .agent(runId: "r"), tainted: true)
        guard case .denied(let why) = tainted.status else { Issue.record("\(tainted.status)"); return }
        #expect(why.contains("outside content"))
        for caller in [Caller.external(client: "codex"), .extension(id: "dev.x.y"), .routine(id: "r1")] {
            let outcome = await h.env.executor.execute(name: "extensions.draft", input: input, caller: caller)
            guard case .denied = outcome.status else { Issue.record("\(caller): \(outcome.status)"); continue }
        }
        #expect(!ExtensionBuilderTools.all(drafts: ExtensionDrafts(directory: h.root), host: h.host, events: h.env.events)
            .contains { $0.spec.external }, "never offered to other agents")
    }

    @Test func reviewHandsTheDraftToTheInstallPreview() async throws {
        let (h, drafts) = try Self.environment()
        let events = h.env.events.stream()
        let missing = await h.env.executor.execute(name: "extensions.review", input: ["name": "greeter"], caller: .agent(runId: "r"))
        #expect(!missing.isOK)
        try drafts.write(name: "greeter", manifest: Self.manifest(), files: ["main.py": Self.program.replacingOccurrences(of: "%SECRET%", with: "None")])
        let outcome = await h.env.executor.execute(name: "extensions.review", input: ["name": "greeter"], caller: .agent(runId: "r"))
        #expect(outcome.okText?.contains("nothing is installed until they click Install") == true)
        var shown: URL?
        for await event in events { if case .reviewExtension(let folder) = event { shown = folder; break } }
        #expect(shown == drafts.folder(name: "greeter"))

        // The person's click on Install: it is marked as written for them, and its tools are theirs from now on.
        let info = try await h.host.install(from: drafts.folder(name: "greeter"))
        #expect(info.origin == .draft)
        #expect(info.author == ExtensionDrafts.author)
        // Like any extension from outside the app, the model sees a neutral line, not its description (D24).
        let spec = try #require(h.env.registry.tool(named: "ext.greeter.greet")?.spec)
        #expect(!spec.description.contains("Says hello"))
        #expect(await h.call("ext.greeter.greet", ["name": "Ada"]).okText == "Hello, Ada!")
        await h.host.shutdown()
    }

    @Test func readingDraftsListsAndReturnsFiles() async throws {
        let (h, drafts) = try Self.environment()
        let empty = await h.env.executor.execute(name: "extensions.read_draft", input: [:], caller: .agent(runId: "r"))
        #expect(empty.okText == "No extension drafts.")
        try drafts.write(name: "greeter", manifest: Self.manifest(), files: ["main.py": "print('hi')"])
        let list = await h.env.executor.execute(name: "extensions.read_draft", input: [:], caller: .agent(runId: "r"))
        #expect(list.okText?.contains("greeter: “Greeter” 0.1.0") == true, "\(String(describing: list.okText))")
        let files = try #require(await h.env.executor.execute(name: "extensions.read_draft", input: ["name": "greeter"],
                                                              caller: .agent(runId: "r")).okText)
        #expect(files.hasPrefix("=== sidefolk-extension.json ==="))
        #expect(files.contains("=== main.py ===\nprint('hi')"))
    }

    /// The program in the build-extension skill is what the AI starts from: it must pass the checks, and
    /// (with SIDEFOLK_LIVE_NETWORK=1) reach its public API from inside the sandbox.
    @Test func theSkillsTemplateIsAWorkingExtension() async throws {
        let skill = try String(contentsOf: ExtFixtures.repoRoot.appendingPathComponent("Resources/Skills/build-extension/SKILL.md"), encoding: .utf8)
        let start = try #require(skill.range(of: "```python\n"))
        let end = try #require(skill.range(of: "\n```", range: start.upperBound..<skill.endIndex))
        let program = String(skill[start.upperBound..<end.lowerBound])
        let (h, drafts) = try Self.environment()
        let manifest: JSONValue = ["name": "Hacker News", "version": "0.1.0", "sidefolk": ">=0.1",
                                   "run": ["command": "python3", "args": ["main.py"]], "permissions": ["network": true],
                                   "tools": ["top_stories": ["title": "Top Hacker News stories", "risk": "low", "mutates": false]]]
        let drafted = await h.env.executor.execute(name: "extensions.draft",
                                                   input: ["name": "hacker-news", "manifest": manifest, "files": ["main.py": .string(program)]],
                                                   caller: .agent(runId: "r"))
        #expect(drafted.okText?.contains("offers 1 tool: ext.hacker-news.top_stories") == true, "\(String(describing: drafted.okText))")
        guard ExtFixtures.liveNetwork else { return }
        try await h.host.install(from: drafts.folder(name: "hacker-news"))
        let stories = await h.call("ext.hacker-news.top_stories", ["count": 1])
        #expect(stories.okText?.contains("(http") == true, "\(stories.status)")
        await h.host.shutdown()
    }

    /// The developer skill's templates (skills/sidefolk-extension/templates) pass the checks and start in
    /// their sandbox, as `sidefolk ext validate` would show (Node only where Node is installed).
    @Test func theDeveloperTemplatesStartInTheirSandbox() async throws {
        let templates = ExtFixtures.repoRoot.appendingPathComponent("skills/sidefolk-extension/templates")
        let expected = ["python": ["ext.word-count.count_words", "ext.word-count.greet"], "node": ["ext.status-page.service_status"],
                        "sh": ["ext.today.today"]]
        for (name, tools) in expected.sorted(by: { $0.key < $1.key }) {
            if name == "node", InterpreterResolver.system.resolve("node") == nil { continue }
            let folder = templates.appendingPathComponent(name)
            let report = ExtensionValidator.validate(at: folder)
            #expect(report.isValid, "\(name): \(report.errors)")
            let trial = await ExtensionValidator.trial(at: folder)
            #expect(trial.problem == nil, "\(name): \(String(describing: trial.problem))")
            #expect(trial.tools == tools, "\(name)")
            #expect(trial.warnings.isEmpty, "\(name): \(trial.warnings)")
        }
    }

    @Test func thePromptOffersToBuildOnlyWhenTheToolIsThere() {
        let draft = ToolSpec(name: "extensions.draft", title: "", description: "", inputSchema: Schema.object([:]), risk: .low,
                             capabilities: [], category: .extensions, mutates: true)
        #expect(ContextBuilder.reach([draft]).contains("load the build-extension skill first"))
        #expect(!ContextBuilder.reach([]).contains("build-extension"))
        #expect(ContextBuilder.reach([]).contains("an extension or MCP server (Settings › Extensions) could add it"))
    }
}
