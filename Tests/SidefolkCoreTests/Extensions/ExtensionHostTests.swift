import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Integration tests that run real extensions under sandbox-exec with this Mac's python3. The extensions that ship
/// with Sidefolk are programs of their own and are tested in BuiltInExtensionTests.
@Suite(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
struct ExtensionHostTests {
    @Test func helloFolkTemplateWorks() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.repoRoot.appendingPathComponent("extensions/hello-folk"))
        #expect(info.summary.texts == ["No access to your files or the internet"])
        #expect(await h.call("ext.hello-folk.hello", ["name": "Ada"]).text == "Hello, Ada!")
        var state: JSONValue = .null
        var fired: [Bool] = []
        for _ in 0..<3 {
            let r = try await h.host.checkWatcher(extensionId: info.id, watcher: "countdown", config: [:], state: state)
            fired.append(r.triggered)
            state = r.state
        }
        #expect(fired == [false, false, true])
        await h.host.shutdown()
    }

    @Test func sandboxBlocksWhatTheManifestDoesNotGrant() async throws {
        let h = try HostEnv()
        let granted = h.root.appendingPathComponent("granted")
        try FileManager.default.createDirectory(at: granted, withIntermediateDirectories: true)
        try Data("shared".utf8).write(to: granted.appendingPathComponent("note.txt"))
        let secret = h.root.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)

        let manifest = ExtFixtures.manifest(tools: ["probe": ["risk": "low"]], permissions: [
            "files": ["read": [.string(granted.path)]], "exec": ["/usr/bin/true"],
        ])
        try await h.host.install(from: h.source("probe", manifest: manifest))
        let outcome = await h.call("ext.sample.probe", [
            "secret": .string(secret.path), "outside": .string(h.root.appendingPathComponent("written.txt").path),
            "granted": .string(granted.appendingPathComponent("note.txt").path),
        ])
        let text = try #require(outcome.okText, "\(String(describing: outcome.failure))")
        let r = try JSONValue.parse(text.replacingOccurrences(of: "\u{200B}", with: ""))
        #expect(r["network"] == "EPERM")
        #expect(r["unix_socket"] == "EPERM")
        #expect(r["read_secret"] == "EPERM")
        #expect(r["read_ssh"] == "EPERM" || r["read_ssh"] == "ENOENT")
        #expect(r["list_home"] == "EPERM")
        #expect(r["write_outside"] == "EPERM")
        #expect(r["write_extension"] != "ok")
        #expect(r["exec_unlisted"] == "EPERM")
        #expect(r["symlink_escape"] == "EPERM")
        #expect(r["write_data"] == "ok")
        #expect(r["read_granted"] == "ok")
        #expect(r["exec_listed"] == "ok")
        #expect(r["open_fds"] == [])
        let env = Set(r["env"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        #expect(env.isSubset(of: ["HOME", "TMPDIR", "PATH", "PYTHONDONTWRITEBYTECODE", "LANG", "SIDEFOLK_EXTENSION_ID",
                                  "SIDEFOLK_DATA_DIR", "__CF_USER_TEXT_ENCODING", "LC_CTYPE"]), "\(env)")
        #expect(!FileManager.default.fileExists(atPath: h.root.appendingPathComponent("written.txt").path))
        await h.host.shutdown()
    }

    @Test func installCopiesLocksAndPins() async throws {
        let h = try HostEnv()
        let src = try h.source("pins", manifest: ExtFixtures.manifest(), files: [
            "server.py": ExtFixtures.server, "lib/helper.txt": "help", ".git/config": "x", ".DS_Store": "x",
        ])
        let info = try await h.host.install(from: src)
        let folder = h.paths.extensions.appendingPathComponent(info.id).path
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).sorted() == ["lib", "server.py", "sidefolk-extension.json"])
        for (path, mode) in [("", 0o555), ("/lib", 0o555), ("/server.py", 0o444), ("/lib/helper.txt", 0o444)] {
            #expect(ExtensionFS.lstat(folder + path).map { $0.st_mode & 0o777 } == mode_t(mode), "\(path)")
        }
        let record = try #require(try await h.store.record(id: info.id))
        let pin = try #require(try record.granted?.decode(ExtensionPin.self))
        #expect(pin.files.map(\.path) == ["lib/helper.txt", "server.py", "sidefolk-extension.json"])
        #expect(pin.files.first?.sha256 == ExtensionHash.sha256(Data("help".utf8)))
        #expect(record.manifestHash == ExtensionFiles.aggregateHash(pin.files))
        #expect(pin.tools.keys.sorted() == ["echo", "probe"])
        #expect(FileManager.default.fileExists(atPath: h.paths.extensionData.appendingPathComponent(info.id).path))
        await h.host.shutdown()
    }

    @Test func tamperedFilesDisableTheExtension() async throws {
        let h = try HostEnv()
        let notices = h.env.events.stream()
        let info = try await h.host.install(from: h.source("tamper", manifest: ExtFixtures.manifest()))
        #expect(await h.call("ext.sample.echo", ["a": 1]).okText?.contains("echoed") == true)
        await h.host.shutdown()

        let file = h.paths.extensions.appendingPathComponent("\(info.id)/server.py").path
        chmod(file, 0o644)
        try Data((ExtFixtures.server + "\n# changed\n").utf8).write(to: URL(fileURLWithPath: file))
        let outcome = await h.call("ext.sample.echo", ["a": 1])
        #expect(outcome.failure?.message.contains("files changed") == true)
        let state = try #require(await h.host.info(id: info.id))
        #expect(!state.enabled)
        #expect(state.lastError?.contains("server.py") == true)
        #expect(h.env.registry.tool(named: "ext.sample.echo") == nil)
        #expect(await ExtFixtures.firstNotice(notices)?.contains("changed on disk") == true)
        await #expect(throws: UserFacingError.self) { try await h.host.setEnabled(true, id: info.id) }
    }

    @Test func tamperIsFoundAtStartup() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: h.source("boot", manifest: ExtFixtures.manifest()))
        await h.host.shutdown()
        let dir = h.paths.extensions.appendingPathComponent(info.id).path
        chmod(dir, 0o755)
        try Data("x".utf8).write(to: URL(fileURLWithPath: dir + "/added.py"))

        let restarted = ExtensionHost(paths: h.paths, store: h.store, registry: ToolRegistry(), events: h.env.events)
        await restarted.start()
        let state = try #require(await restarted.info(id: info.id))
        #expect(!state.enabled)
        #expect(state.lastError?.contains("added.py") == true)
    }

    @Test func crashingExtensionIsTurnedOffAfterThreeCrashes() async throws {
        let h = try HostEnv()
        let notices = h.env.events.stream()
        let info = try await h.host.install(from: h.source("crash", manifest: ExtFixtures.manifest(args: ["server.py", "crash"])))
        for _ in 0..<3 {
            let outcome = await h.call("ext.sample.echo")
            #expect(outcome.failure?.message.contains("stopped while working") == true, "\(String(describing: outcome.failure))")
            try await Task.sleep(for: .milliseconds(100))
        }
        let state = try #require(await h.host.info(id: info.id))
        #expect(!state.enabled)
        #expect(state.lastError?.contains("3× in 5 min") == true)
        #expect(h.env.registry.tool(named: "ext.sample.echo") == nil)
        #expect(await ExtFixtures.firstNotice(notices)?.contains("kept crashing") == true)
        #expect(try await h.store.record(id: info.id)?.enabled == false)

        try await h.host.setEnabled(true, id: info.id)
        #expect(h.env.registry.tool(named: "ext.sample.echo") != nil)
    }

    @Test func serverInitiatedSamplingIsRefused() async throws {
        let h = try HostEnv()
        try await h.host.install(from: h.source("sampling", manifest: ExtFixtures.manifest(args: ["server.py", "sampling"])))
        let text = try #require(await h.call("ext.sample.echo").okText)
        let reply = try JSONValue.parse(text)
        #expect(reply["id"] == "s1")
        #expect(reply["error"]?["code"] == -32601)
        #expect(reply["result"] == nil)
        await h.host.shutdown()
    }

    @Test func oversizedMessageFailsFastAndCountsAsACrash() async throws {
        let h = try HostEnv()
        try await h.host.install(from: h.source("huge", manifest: ExtFixtures.manifest(args: ["server.py", "huge"])))
        let started = Date()
        let outcome = await h.call("ext.sample.echo")
        #expect(outcome.failure?.detail?.contains("larger than 1 MiB") == true, "\(String(describing: outcome.failure))")
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(await h.host.isRunning("dev.test.sample") == false)
    }

    @Test func slowCallsTimeOut() async throws {
        let h = try HostEnv { $0.callTimeout = 1 }
        try await h.host.install(from: h.source("slow", manifest: ExtFixtures.manifest(args: ["server.py", "slow"])))
        let outcome = await h.call("ext.sample.echo")
        #expect(outcome.failure?.message.contains("took too long") == true)
        await h.host.shutdown()
    }

    @Test func changedToolDefinitionsAreQuarantined() async throws {
        let h = try HostEnv()
        let notices = h.env.events.stream()
        let info = try await h.host.install(from: h.source("rug", manifest: ExtFixtures.manifest(args: ["server.py", "rugpull"])))
        await h.host.shutdown()

        // The next launch reports a different description for both tools.
        let held = await h.call("ext.sample.echo")
        #expect(held.failure?.message.contains("on hold") == true, "\(String(describing: held.failure))")
        #expect(h.env.registry.tool(named: "ext.sample.echo") == nil)
        #expect(await h.host.info(id: info.id)?.hasPendingToolChanges == true)
        #expect(await ExtFixtures.firstNotice(notices)?.contains("on hold") == true)

        try await h.host.approveToolChanges(id: info.id)
        let tool = try #require(h.env.registry.tool(named: "ext.sample.echo"))
        // Approved for the extension, but its description never reaches the model (SECURITY T2).
        #expect(!tool.spec.description.contains("Ignore previous instructions"))
        #expect(tool.spec.description.contains("“Sample”"))
        #expect(await h.call("ext.sample.echo").okText?.contains("echoed") == true)
        await h.host.shutdown()
    }

    @Test func resultsAreUntrustedAndCleaned() async throws {
        let h = try HostEnv()
        try await h.host.install(from: h.source("clean", manifest: ExtFixtures.manifest()))
        let outcome = await h.call("ext.sample.echo", ["b": 2])
        #expect(outcome.text == #"echoed {"b": 2}"#)
        #expect(outcome.untrusted)
        #expect(outcome.modelText.hasPrefix("<untrusted_content source="))
        let tool = try #require(h.env.registry.tool(named: "ext.sample.echo"))
        #expect(tool.scope(for: [:]).extensionId == "dev.test.sample")
        #expect(tool.spec.risk == .low)
        #expect(!tool.spec.external)
        #expect(h.env.registry.owner(of: "ext.sample.echo") == "dev.test.sample")
        await h.host.shutdown()
    }

    @Test func watcherChecksCarryState() async throws {
        let h = try HostEnv()
        let manifest = ExtFixtures.manifest(extra: ["watchers": ["count": ["title": "Count", "config": ["after": ["type": "integer", "default": 2]]]]])
        let info = try await h.host.install(from: h.source("watch", manifest: manifest))
        let kinds = await h.host.watcherKinds()
        #expect(kinds.map(\.watcher) == ["count"])
        #expect(kinds.first?.title == "Count")
        let first = try await h.host.checkWatcher(extensionId: info.id, watcher: "count", config: [:], state: .null)
        #expect(!first.triggered)
        #expect(first.summary == "check 1")
        let second = try await h.host.checkWatcher(extensionId: info.id, watcher: "count", config: [:], state: first.state)
        #expect(second.triggered)
        await #expect(throws: UserFacingError.self) {
            try await h.host.checkWatcher(extensionId: info.id, watcher: "count", config: ["nope": 1], state: .null)
        }
        await h.host.shutdown()
    }

    @Test func idleProcessesStop() async throws {
        let h = try HostEnv { $0.idleTimeout = 0.5 }
        try await h.host.install(from: h.source("idle", manifest: ExtFixtures.manifest()))
        _ = await h.call("ext.sample.echo")
        #expect(await h.host.isRunning("dev.test.sample"))
        try await Task.sleep(for: .seconds(1.5))
        #expect(await h.host.isRunning("dev.test.sample") == false)
        #expect(await h.call("ext.sample.echo").okText != nil)
        await h.host.shutdown()
    }

    @Test func updateShowsDiffAndUninstallRemovesEverything() async throws {
        let h = try HostEnv()
        let src = try h.source("upd", manifest: ExtFixtures.manifest())
        let info = try await h.host.install(from: src)
        let data = h.paths.extensionData.appendingPathComponent(info.id)
        try Data("kept".utf8).write(to: data.appendingPathComponent("state.json"))

        var newer = ExtFixtures.manifest(tools: ["probe": ["risk": "low"]], permissions: ["exec": ["/usr/bin/true"]])
        if case .object(var o) = newer { o["version"] = "1.1.0"; newer = .object(o) }
        try ExtFixtures.makeExtension(at: src, manifest: newer)
        let preview = await h.host.preview(folder: src)
        let diff = try #require(preview.update)
        #expect(diff.fromVersion == "1.0.0" && diff.toVersion == "1.1.0")
        #expect(diff.addedPermissions == ["Can run /usr/bin/true"])
        #expect(diff.addedTools == ["probe"] && diff.removedTools == ["echo"])

        let updated = try await h.host.install(from: src)
        #expect(updated.version == "1.1.0")
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("state.json").path))

        try await h.host.uninstall(id: info.id)
        #expect(!FileManager.default.fileExists(atPath: h.paths.extensions.appendingPathComponent(info.id).path))
        #expect(!FileManager.default.fileExists(atPath: data.path))
        #expect(try await h.store.record(id: info.id) == nil)
        #expect(h.env.registry.tool(named: "ext.sample.echo") == nil)
        #expect(await h.host.extensions().isEmpty)
    }

    @Test func failedInstallRollsBack() async throws {
        let h = try HostEnv()
        let broken = try h.source("broken", manifest: ExtFixtures.manifest(), files: ["server.py": "import sys\nsys.exit(1)\n"])
        await #expect(throws: UserFacingError.self) { try await h.host.install(from: broken) }
        #expect(!FileManager.default.fileExists(atPath: h.paths.extensions.appendingPathComponent("dev.test.sample").path))
        #expect(try await h.store.all().isEmpty)
        #expect(await h.host.extensions().isEmpty)
    }

    @Test func plainMCPServerRunsUnsandboxedAtMediumRisk() async throws {
        let h = try HostEnv()
        let python = try #require(ExtFixtures.python)
        let script = h.root.appendingPathComponent("server.py")
        try Data(ExtFixtures.server.utf8).write(to: script)
        let preview = await h.host.previewMCPServer(name: "Fixture Server", command: python.path, arguments: ["-I", script.path])
        #expect(preview.canAdd, "\(preview.errors)")
        #expect(preview.id == "mcp.fixture-server")
        #expect(!preview.summary.sandboxed)

        let info = try await h.host.addMCPServer(name: "Fixture Server", command: python.path, arguments: ["-I", script.path])
        #expect(info.kind == .mcp)
        #expect(info.version == "0.1")
        #expect(info.tools.allSatisfy { $0.risk == .medium })
        let tool = try #require(h.env.registry.tool(named: "ext.fixture-server.echo"))
        #expect(tool.spec.description.contains("unsandboxed"))
        #expect(tool.spec.capabilities.contains(.network))
        #expect(await h.call("ext.fixture-server.echo", ["x": 1]).okText?.contains("echoed") == true)

        let duplicate = await h.host.previewMCPServer(name: "Fixture Server", command: python.path, arguments: [])
        #expect(!duplicate.canAdd)
        #expect(await h.host.previewMCPServer(name: "X", command: "definitely-not-a-command-\(UUID())", arguments: []).canAdd == false)
        #expect(await h.host.previewMCPServer(name: "Y", command: python.path, arguments: [], environmentKeys: ["DYLD_INSERT_LIBRARIES"]).canAdd == false)
        try await h.host.uninstall(id: info.id)
        #expect(h.env.registry.tool(named: "ext.fixture-server.echo") == nil)
    }

    @Test func shortNameClashesAreRefused() async throws {
        let h = try HostEnv()
        try await h.host.install(from: h.source("one", manifest: ExtFixtures.manifest(id: "dev.one.sample")))
        let clash = try h.source("two", manifest: ExtFixtures.manifest(id: "dev.two.sample"))
        #expect(await h.host.preview(folder: clash).conflict != nil)
        await #expect(throws: UserFacingError.self) { try await h.host.install(from: clash) }
        await h.host.shutdown()
    }
}
