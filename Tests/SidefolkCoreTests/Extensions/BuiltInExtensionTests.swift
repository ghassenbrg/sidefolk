import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The extensions Sidefolk ships (D39), each a program of its own, run for real under sandbox-exec as the app runs them.
/// Only Git needs anything on the Mac (git itself). Nothing reaches the network unless SIDEFOLK_LIVE_NETWORK=1.
struct BuiltInExtensionTests {
    static let noGit: Comment = "git (developer tools or Homebrew) needed"

    /// git outside any sandbox, with no system or global configuration, to make a repository to look at.
    static func run(_ args: [String], in dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ExtFixtures.git!.path)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = ["HOME": dir.path, "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "git \(args.joined(separator: " "))")
    }

    /// `work/project`: one commit ("First note"), then README changed and new.txt added.
    static func makeRepository(in work: URL) throws -> URL {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try run(["init", "-q", "-b", "main", "project"], in: work)
        let repo = work.appendingPathComponent("project")
        try Data("hello\n".utf8).write(to: repo.appendingPathComponent("README"))
        try run(["add", "README"], in: repo)
        try run(["-c", "user.name=Ada", "-c", "user.email=ada@example.com", "commit", "-q", "-m", "First note"], in: repo)
        try Data("hello again\n".utf8).write(to: repo.appendingPathComponent("README"))
        try Data("new\n".utf8).write(to: repo.appendingPathComponent("new.txt"))
        return repo
    }

    @Test(.enabled(if: ExtFixtures.git != nil, noGit))
    func gitReadsOnlyTheFolderACallNames() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("git"))
        #expect(info.tools.map(\.name) == ["ext.git.clone", "ext.git.log", "ext.git.pull", "ext.git.status"])
        #expect(info.tools.allSatisfy { $0.risk == .medium }, "the internet puts every tool at medium or above")
        #expect(info.iconPath?.hasSuffix("/dev.sidefolk.git/icon.pdf") == true)
        let work = h.root.appendingPathComponent("work")
        let repo = try Self.makeRepository(in: work)
        try await h.env.permissions.grantFolder(work.path, access: .readwrite)
        await h.host.shutdown() // the process install started; folder calls must not need it

        let status = try #require(await h.call("ext.git.status", ["repository": .string(repo.path)]).okText)
        #expect(status.contains("on main"), "\(status)")
        #expect(status.contains("1 changed (0 staged)") && status.contains("1 new and untracked"), "\(status)")
        #expect(status.contains("README") && status.contains("new.txt"), "\(status)")
        let log = try #require(await h.call("ext.git.log", ["repository": .string(repo.path), "count": 5]).okText)
        #expect(log.contains("First note") && log.contains("Ada"), "\(log)")
        // Each call that names a folder ran in a process of its own, gone with the call; none was left running.
        #expect(await h.host.isRunning(info.id) == false)

        // A folder nobody shared: Sidefolk's agent must ask, and a "no" runs nothing.
        let elsewhere = h.root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let answer = h.env.autoAnswer(.deny)
        let denied = await h.env.executor.execute(name: "ext.git.status", input: ["repository": .string(elsewhere.path)],
                                                  caller: .agent(runId: "r"))
        guard case .denied = denied.status else { Issue.record("expected a denial, got \(denied.status)"); return }
        let request = await answer.value
        guard case .folderAccess(_, let write)? = request?.details else { Issue.record("expected a folder card"); return }
        #expect(!write)
        #expect(request?.extensionId == info.id)
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.git != nil, noGit))
    func cloneRefusesWhatItCantDoWithoutTouchingTheNetwork() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("git"))
        let work = h.root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("taken"), withIntermediateDirectories: true)
        try await h.env.permissions.grantFolder(work.path, access: .readwrite)
        let cases: [(String, String, String)] = [
            ("git@github.com:octocat/Hello-World.git", "hello", "Only https addresses"),
            ("ext::sh -c touch% /tmp/pwned", "hello", "Only https addresses"),
            ("https://me:secret@github.com/octocat/Hello-World.git", "hello", "Leave sign-in details out"),
            ("https://github.com/octocat/Hello-World.git", "taken", "already exists"),
            ("https://github.com/octocat/Hello-World.git", "missing/deeper", "doesn't exist yet"),
        ]
        for (url, folder, message) in cases {
            let outcome = await h.call("ext.git.clone", ["url": .string(url), "destination": .string(work.appendingPathComponent(folder).path)])
            #expect(!outcome.isOK, "\(url)")
            #expect(outcome.okText?.contains(message) == true, "\(url): \(String(describing: outcome.okText))")
        }
        // A path the extension would read as its own data folder is refused before any card.
        let relative = await h.call("ext.git.status", ["repository": "project"])
        guard case .denied = relative.status else { Issue.record("expected a refusal, got \(relative.status)"); return }
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.liveNetwork && ExtFixtures.git != nil, "set SIDEFOLK_LIVE_NETWORK=1 to clone from GitHub"))
    func clonesAPublicRepositoryIntoTheNamedFolder() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("git"))
        let work = h.root.appendingPathComponent("git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try await h.env.permissions.grantFolder(work.path, access: .readwrite)
        let destination = work.appendingPathComponent("Hello-World")
        let clone = try #require(await h.call("ext.git.clone", ["url": "https://github.com/octocat/Hello-World.git",
                                                                "destination": .string(destination.path)]).okText)
        #expect(clone.contains("Cloned octocat/Hello-World into"), "\(clone)")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README").path))
        let pull = try #require(await h.call("ext.git.pull", ["repository": .string(destination.path)]).okText)
        #expect(pull.contains("already up to date"), "\(pull)")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func aFolderNamedInACallIsTheOnlyOneTheSandboxOpens() async throws {
        let h = try HostEnv()
        let shared = h.root.appendingPathComponent("shared")
        for (dir, file, text) in [("a", "note.txt", "shared"), ("b", "secret.txt", "secret")] {
            try FileManager.default.createDirectory(at: shared.appendingPathComponent(dir), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: shared.appendingPathComponent("\(dir)/\(file)"))
        }
        let manifest = ExtFixtures.manifest(tools: ["probe": ["risk": "low", "paths": ["granted": "read"]]])
        try await h.host.install(from: h.source("probe", manifest: manifest))
        try await h.env.permissions.grantFolder(shared.path, access: .readwrite)
        let outcome = await h.call("ext.sample.probe", [
            "granted": .string(shared.appendingPathComponent("a/note.txt").path),
            "secret": .string(shared.appendingPathComponent("b/secret.txt").path),
            "outside": .string(shared.appendingPathComponent("a/written.txt").path),
        ])
        let text = try #require(outcome.okText, "\(outcome.status)")
        let r = try JSONValue.parse(text.replacingOccurrences(of: "\u{200B}", with: ""))
        #expect(r["read_granted"] == "ok")
        #expect(r["read_secret"] == "EPERM", "shared with Sidefolk, but not named in this call")
        #expect(r["write_outside"] == "EPERM", "named for reading only")
        await h.host.shutdown()
    }

    /// The founder's request, "please clone this repository under ~/git", through the agent loop with a
    /// scripted model: the folder card, then the action card, then the clone in its own sandbox. Offline,
    /// the destination is taken, so git is never reached; with SIDEFOLK_LIVE_NETWORK=1 it really clones.
    @Test(.enabled(if: ExtFixtures.git != nil, noGit), arguments: [false, true])
    func theFoundersRequestClonesBehindTwoApprovals(live: Bool) async throws {
        guard !live || ExtFixtures.liveNetwork else { return }
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("git"))
        let codeFolder = h.root.appendingPathComponent("git")
        let destination = codeFolder.appendingPathComponent("Hello-World")
        try FileManager.default.createDirectory(at: live ? codeFolder : destination, withIntermediateDirectories: true)

        let cards = Mutex<[ApprovalRequest]>([])
        let stream = h.env.events.stream()
        let broker = h.env.broker
        let answering = Task {
            for await event in stream {
                guard case .approvalRequested(let request) = event else { continue }
                cards.withLock { $0.append(request) }
                await broker.resolve(id: request.id, decision: .allowOnce)
            }
        }
        defer { answering.cancel() }
        let clone = ToolCall(id: "c1", name: "ext_git_clone", input: [
            "url": "https://github.com/octocat/Hello-World.git", "destination": .string(destination.path),
        ])
        let model = ScriptedModel([.turn(.calling([clone])), .turn(.reply("Cloned it into ~/git/Hello-World."))])
        let reply = try await LoopBackend(model: model, checkModel: "m", clock: h.env.clock)
            .run(brainTask(h.env, text: "please clone https://github.com/octocat/Hello-World under ~/git"),
                 toolbox: toolbox(h.env), emit: { _ in })

        let asked = cards.withLock { $0 }
        #expect(asked.count == 2, "\(asked.map(\.title))")
        guard case .folderAccess(let folder, true)? = asked.first?.details else { Issue.record("no folder card first"); return }
        // The card offers the folder it goes in (the existing one, offline), never wider than that.
        #expect(folder == FolderAccess.canonical((live ? codeFolder : destination).path))
        #expect(asked.last?.title == "Clone a repository" && asked.last?.risk == .medium)
        #expect(asked.allSatisfy { $0.extensionId == "dev.sidefolk.git" })
        guard case .toolResults(let results) = model.requests[1].messages.last else { Issue.record("no tool result"); return }
        if live {
            #expect(reply.text == "Cloned it into ~/git/Hello-World.")
            #expect(results.first?.content.contains("Cloned octocat/Hello-World") == true, "\(results)")
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README").path))
        } else {
            #expect(results.first?.content.contains("already exists") == true, "\(results)")
        }
        await h.host.shutdown()
    }

    @Test func worldClockAnswersWithoutAnyPermission() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("world-clock"))
        #expect(info.summary.texts == ["No access to your files or the internet"])
        #expect(info.tools.allSatisfy { $0.risk == .low })
        let now = try #require(await h.call("ext.world-clock.current_time", ["places": ["UTC", "Narnia"]]).okText)
        #expect(now.contains("in UTC (UTC+0)") && now.contains("I don't know where “Narnia” is"), "\(now)")
        let converted = try #require(await h.call("ext.world-clock.convert_time", [
            "time": "2026-01-15 12:00", "from": "UTC", "to": ["Asia/Tokyo", "New York", "São Paulo"],
        ]).okText)
        #expect(converted.contains("21:00 in Asia/Tokyo (JST, UTC+9)"), "\(converted)")
        #expect(converted.contains("07:00 in New York (EST, UTC−5)"), "\(converted)")
        #expect(converted.contains("09:00 in São Paulo"), "\(converted)")
        let gap = await h.call("ext.world-clock.convert_time", ["time": "2026-03-29 02:30", "from": "Paris", "to": ["UTC"]])
        #expect(!gap.isOK && gap.okText?.contains("clocks skip") == true)
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.liveNetwork, "set SIDEFOLK_LIVE_NETWORK=1 to ask Open-Meteo"))
    func weatherReachesOpenMeteoFromItsSandbox() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("weather"))
        let forecast = try #require(await h.call("ext.weather.forecast", ["place": "Lyon", "days": 2]).okText)
        #expect(forecast.hasPrefix("Lyon, Auvergne-Rhône-Alpes, France, now:") && forecast.contains("Tomorrow:"), "\(forecast)")
        let sun = try #require(await h.call("ext.weather.sun_and_moon", ["place": "Lyon"]).okText)
        #expect(sun.contains("sunrise") && sun.contains("The moon is"), "\(sun)")
        let check = try await h.host.checkWatcher(extensionId: "dev.sidefolk.weather", watcher: "rain_soon", config: ["place": "Lyon"], state: .null)
        #expect(check.summary.contains("Lyon"))
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.git != nil, noGit))
    func theShippedCatalogInstallsAsFirstParty() async throws {
        let h = try HostEnv()
        let bundled = BundledExtensions(directory: ExtFixtures.builtIns)
        let ids = ["git", "world-clock", "system-vitals", "weather", "calculator", "currency", "playtime", "images", "pdf", "qr-codes",
                   "archives", "dev-toolbox", "feeds"].map { "dev.sidefolk." + $0 }
        #expect(bundled.entries().map(\.id) == ids)
        let on = Set(["git", "world-clock", "system-vitals", "weather", "calculator", "currency", "playtime", "images"].map { "dev.sidefolk." + $0 })
        #expect(bundled.entries().map(\.on) == ids.map(on.contains))
        #expect(Set(ExtFixtures.builtInFolders) == Set(bundled.entries().map(\.folder.lastPathComponent)), "every program ships, and only those")
        #expect(bundled.samples().isEmpty, "the Python sample stays in the repository")
        await bundled.install(into: h.host)
        #expect(bundled.unavailable.isEmpty, "\(bundled.unavailable)")
        let installed = await h.host.extensions()
        #expect(installed.map(\.id).sorted() == ids.sorted())
        #expect(installed.allSatisfy { $0.origin == .bundled && $0.iconPath != nil })
        #expect(Set(installed.filter(\.enabled).map(\.id)) == on, "the catalog decides what starts on")
        // Their own descriptions and schema reach the model: first-party text from the app (D39), unlike D24's rule.
        let clone = try #require(h.env.registry.tool(named: "ext.git.clone")?.spec)
        #expect(clone.description.contains("Clones a public Git repository"))
        #expect(clone.description.contains("Sidefolk's built-in extension “Git”"))
        #expect(clone.inputSchema["properties"]?["url"]?["description"] != nil)
        #expect(clone.timeout == 305)
        await #expect(throws: UserFacingError.self) { try await h.host.uninstall(id: "dev.sidefolk.git") }
        await h.host.shutdown()
    }
}
