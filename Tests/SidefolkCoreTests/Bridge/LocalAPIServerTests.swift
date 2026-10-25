import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

@Suite(.serialized) struct LocalAPIServerTests {
    // MARK: Socket location (T6)

    @Test func socketIsPrivate() throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        var st = stat()
        #expect(lstat(h.dir.socket, &st) == 0)
        #expect(st.st_mode & S_IFMT == S_IFSOCK)
        #expect(st.st_mode & 0o777 == 0o600)
        #expect(lstat(h.dir.run, &st) == 0)
        #expect(st.st_mode & 0o777 == 0o700)
    }

    @Test func refusesLongPaths() throws {
        let long = "/tmp/" + String(repeating: "x", count: 120) + "/sidefolk.sock"
        let env = try TestEnv()
        let server = LocalAPIServer(socket: URL(fileURLWithPath: long), services: BridgeServices(
            tools: ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity,
                                       events: env.events),
            tokens: BrainTokenRegistry()))
        #expect(throws: BridgeError.pathTooLong(long)) { try server.start() }
    }

    @Test func refusesOpenOrSymlinkedRunFolder() throws {
        let h = try BridgeHarness()
        defer { h.stop() }
        mkdir(h.dir.run, 0o755)
        chmod(h.dir.run, 0o755)
        #expect(throws: BridgeError.self) { try h.server.start() }

        rmdir(h.dir.run)
        let elsewhere = h.dir.path + "/elsewhere"
        mkdir(elsewhere, 0o700)
        symlink(elsewhere, h.dir.run)
        #expect(throws: BridgeError.self) { try h.server.start() }
    }

    @Test func liveSocketIsNeverUnlinked() async throws {
        let a = try BridgeHarness().start()
        defer { a.stop() }
        let env = try TestEnv()
        let b = LocalAPIServer(socket: URL(fileURLWithPath: a.dir.socket), services: BridgeServices(
            tools: ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity,
                                       events: env.events),
            tokens: BrainTokenRegistry()))
        #expect(throws: BridgeError.alreadyRunning) { try b.start() }
        let client = try await a.connect()
        defer { client.close() }
        #expect(client.hello.caller == "external")
    }

    @Test func staleSocketIsReplaced() async throws {
        let h = try BridgeHarness()
        defer { h.stop() }
        try PrivateDirectory.ensure(h.dir.run)
        let fd = try UnixSocket.makeSocket()
        try UnixSocket.bind(fd, path: h.dir.socket)
        close(fd) // bound, nobody listening: ECONNREFUSED
        try h.server.start()
        let client = try await h.connect()
        client.close()
    }

    @Test func foreignUserIsRejected() async throws {
        let h = try BridgeHarness(peerUID: { _ in getuid() + 1 }).start()
        defer { h.stop() }
        await #expect(throws: BridgeError.self) { _ = try await h.connect() }
    }

    // MARK: Protocol

    @Test func helloComesFirst() throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let raw = try RawSocket(path: h.dir.socket)
        defer { raw.close() }
        raw.send(#"{"id":1,"method":"tools/list","params":{}}"# + "\n")
        let reply = try JSONValue.parse(#require(raw.readLine()))
        #expect(reply["error"]?.string("code") == "hello_required")
        #expect(raw.isClosed())
    }

    @Test func versionMismatchIsRefused() throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let raw = try RawSocket(path: h.dir.socket)
        defer { raw.close() }
        raw.send(#"{"id":1,"method":"hello","params":{"version":99,"client":"x"}}"# + "\n")
        let reply = try JSONValue.parse(#require(raw.readLine()))
        #expect(reply["error"]?.string("code") == "version")
        #expect(raw.isClosed())
    }

    @Test func oversizedLineClosesTheConnection() throws {
        var limits = LocalAPIServer.Limits()
        limits.maxLineBytes = 1024
        let h = try BridgeHarness(limits: limits).start()
        defer { h.stop() }
        let raw = try RawSocket(path: h.dir.socket)
        defer { raw.close() }
        raw.send(#"{"id":1,"method":"hello","params":{"version":1}}"# + "\n")
        _ = raw.readLine()
        raw.send(#"{"id":2,"method":"status","params":{"pad":""# + String(repeating: "a", count: 4000) + "\"}}\n")
        let reply = try JSONValue.parse(#require(raw.readLine()))
        #expect(reply["error"]?.string("code") == "too_large")
        #expect(raw.isClosed())
    }

    @Test func connectionLimit() async throws {
        var limits = LocalAPIServer.Limits()
        limits.maxConnections = 1
        let h = try BridgeHarness(limits: limits).start()
        defer { h.stop() }
        let first = try await h.connect()
        defer { first.close() }
        let raw = try RawSocket(path: h.dir.socket)
        defer { raw.close() }
        let reply = try JSONValue.parse(#require(raw.readLine()))
        #expect(reply["error"]?.string("code") == "busy")
    }

    @Test func idleConnectionsClose() async throws {
        var limits = LocalAPIServer.Limits()
        limits.idleTimeout = 0.2
        let h = try BridgeHarness(limits: limits).start()
        defer { h.stop() }
        let client = try await h.connect()
        #expect(await pollUntil(3) { !client.isOpen })
        #expect(h.server.connectionCount == 0)
    }

    // MARK: External callers (T4)

    func registerSampleTools(_ env: TestEnv) {
        for name in ["notes.save", "notes.search", "files.read", "clipboard.read", "web.fetch", "watch.create", "status", "skills.load"] {
            env.registry.register(ProbeTool(name: name, risk: .low, mutates: false))
        }
    }

    @Test func externalCallersSeeOnlyTheExposedTools() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let client = try await h.connect()
        defer { client.close() }
        let names = try await client.call("tools/list").toolNames
        #expect(names == ["notes.save", "notes.search", "watch.create", "status"])
    }

    @Test func hiddenToolsAreRefused() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let client = try await h.connect()
        defer { client.close() }
        for name in ["files.read", "files_read", "clipboard.read", "skills.load", "nonexistent"] {
            let reply = try await client.call("tools/call", ["name": .string(name), "arguments": [:]])
            #expect(reply["isError"] == true)
        }
        #expect(try await h.env.activity.count() == 0)
    }

    @Test func readingNotesAlwaysAsksAndNeverOffersAlways() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let client = try await h.connect(client: "Claude Code")
        defer { client.close() }
        let answer = h.env.autoAnswer(.allowOnce)
        let reply = try await client.call("tools/call", ["name": "notes_search", "arguments": ["x": "ideas"]])
        let request = await answer.value
        #expect(reply["isError"] == false)
        #expect(request?.risk == .medium)
        #expect(request?.canAlways == false)
        #expect(request?.caller == .external(client: "Claude Code"))
    }

    @Test func lowRiskExposedToolsRunWithoutAsking() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let client = try await h.connect()
        defer { client.close() }
        let reply = try await client.call("tools/call", ["name": "status", "arguments": [:]])
        #expect(reply["isError"] == false)
        let log = try await h.env.activity.recent()
        #expect(log.first?.caller == "external:test-agent")
    }

    @Test func commandWatchersAreRefusedAndHidden() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let schema = Schema.object(["kind": Schema.string("kind", enum: ["url", "file", "command"])])
        var watch = ProbeTool(name: "watch.create", risk: .low)
        watch.spec.inputSchema = schema
        h.env.registry.register(watch)
        let client = try await h.connect()
        defer { client.close() }
        let tools = try await client.call("tools/list")["tools"]?.arrayValue ?? []
        #expect(tools.first?["inputSchema"]?["properties"]?["kind"]?["enum"] == ["url", "file"])
        let refused = try await client.call("tools/call", ["name": "watch.create", "arguments": ["kind": "command"]])
        #expect(refused["isError"] == true)
        let allowed = try await client.call("tools/call", ["name": "watch.create", "arguments": ["kind": "url"]])
        #expect(allowed["isError"] == false)
    }

    @Test func notesFromAgentsAreTagged() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let seen = Mutex<JSONValue?>(nil)
        var save = ProbeTool(name: "notes.save", risk: .low, result: { input in
            seen.withLock { $0 = input }
            return ToolResult(text: "saved")
        })
        save.spec.inputSchema = Schema.object(["title": Schema.string("t"), "tags": Schema.array("tags", items: Schema.string("tag"))])
        h.env.registry.register(save)
        let client = try await h.connect(client: "Claude Code")
        defer { client.close() }
        _ = try await client.call("tools/call", ["name": "notes.save", "arguments": ["title": "Idea", "tags": ["x"]]])
        #expect(seen.withLock { $0 }?["tags"] == ["x", "from-claude-code"])
    }

    @Test func rateLimitPerMinute() async throws {
        var limits = LocalAPIServer.Limits()
        limits.callsPerMinute = 3
        let h = try BridgeHarness(limits: limits).start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let client = try await h.connect()
        defer { client.close() }
        for _ in 0..<3 { _ = try await client.call("tools/call", ["name": "status", "arguments": [:]]) }
        await #expect(throws: BridgeError.remote(code: "rate_limited", message: "Too many calls to Sidefolk this minute. Try again shortly.")) {
            _ = try await client.call("tools/call", ["name": "status", "arguments": [:]])
        }
    }

    @Test func concurrentCallLimit() async throws {
        var limits = LocalAPIServer.Limits()
        limits.concurrentCalls = 1
        let h = try BridgeHarness(limits: limits).start()
        defer { h.stop() }
        h.env.registry.register(ProbeTool(name: "status", risk: .low, result: { _ in
            try await Task.sleep(for: .milliseconds(500))
            return ToolResult(text: "slow")
        }))
        let client = try await h.connect()
        defer { client.close() }
        async let slow = client.call("tools/call", ["name": "status", "arguments": [:]])
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: BridgeError.self) { _ = try await client.call("tools/call", ["name": "status", "arguments": [:]]) }
        #expect(try await slow["text"] == "slow")
    }

    // MARK: Brain tokens (T6)

    @Test func brainTokenCallsGoThroughTheRunsToolbox() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let toolbox = BrainToolbox(runId: "run-1", specs: h.env.registry.specs, executor: h.env.executor, emit: { _ in })
        let token = BrainTokenRegistry.makeToken()
        h.tokens.register(token: token, toolbox: toolbox)
        let client = try await h.connect(token: token)
        defer { client.close() }
        #expect(client.hello.caller == "agent")
        #expect(try await client.call("tools/list").toolNames.contains("files.read"))
        let reply = try await client.call("tools/call", ["name": "files_read", "arguments": [:]])
        #expect(reply["isError"] == false)
        #expect(toolbox.outcomes.count == 1)
        #expect(try await h.env.activity.recent().first?.runId == "run-1")
    }

    @Test func unknownTokenDisconnects() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        await #expect(throws: BridgeError.remote(code: "unauthorized", message: "Unknown or expired token.")) {
            _ = try await h.connect(token: BrainTokenRegistry.makeToken())
        }
    }

    @Test func tokenBindsToTheFirstConnection() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let toolbox = BrainToolbox(runId: "r", specs: [], executor: h.env.executor, emit: { _ in })
        let token = BrainTokenRegistry.makeToken()
        h.tokens.register(token: token, toolbox: toolbox)
        let first = try await h.connect(token: token)
        defer { first.close() }
        await #expect(throws: BridgeError.self) { _ = try await h.connect(token: token) }
    }

    @Test func tokenExpiresWithTheRun() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let toolbox = BrainToolbox(runId: "r", specs: [], executor: h.env.executor, emit: { _ in })
        let token = BrainTokenRegistry.makeToken()
        h.tokens.register(token: token, toolbox: toolbox)
        let client = try await h.connect(token: token)
        h.tokens.unregister(token: token)
        await #expect(throws: BridgeError.self) { _ = try await client.call("tools/list") }
        #expect(await pollUntil { !client.isOpen })
        await #expect(throws: BridgeError.self) { _ = try await h.connect(token: token) }
    }

    @Test func noMessageCanClaimToBeTheUser() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        registerSampleTools(h.env)
        let raw = try RawSocket(path: h.dir.socket)
        defer { raw.close() }
        raw.send(#"{"id":1,"method":"hello","params":{"version":1,"client":"you","caller":"user"}}"# + "\n")
        let hello = try JSONValue.parse(#require(raw.readLine()))
        #expect(hello["result"]?.string("caller") == "external")
        raw.send(#"{"id":2,"method":"tools/call","params":{"name":"status","arguments":{},"caller":"user"}}"# + "\n")
        _ = raw.readLine()
        #expect(try await h.env.activity.recent().first?.caller == "external:you")
    }

    // MARK: Sessions, jobs, status

    @Test func statusAndJobsOverTheSocket() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let client = try await h.connect(client: "sidefolk-cli")
        defer { client.close() }
        let started = try await client.call("job/start", JobReport(title: "npm test", command: "npm test", cwd: "/tmp", pid: 99999).json)
        let id = try #require(started.string("id"))
        #expect(StatusSnapshot(json: try await client.call("status")).jobsRunning == 1)
        _ = try await client.call("job/finish", JobReport(id: id, title: "npm test", exitCode: 0, durationSeconds: 3).json)
        let job = try await JobStore(h.env.db).job(id: id)
        #expect(job?.state == .succeeded)
        #expect(StatusSnapshot(json: try await client.call("status")).jobsRunning == 0)
    }

    @Test func malformedSessionEventsAreRefused() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let client = try await h.connect()
        defer { client.close() }
        await #expect(throws: BridgeError.self) {
            _ = try await client.call("session/event", ["agent": "claude-code", "event": "Stop", "session_id": "../../etc"])
        }
    }
}
