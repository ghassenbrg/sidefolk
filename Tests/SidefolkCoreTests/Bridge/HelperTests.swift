import Darwin
import Foundation
import Testing
@testable import SidefolkCore

@Suite struct RunCommandTests {
    @Test func parsesTitleAndCommand() throws {
        #expect(try RunRequest.parse(["--title", "Tests", "--", "npm", "test"]).get() == RunRequest(title: "Tests", command: ["npm", "test"]))
        #expect(try RunRequest.parse(["--", "make", "-j8"]).get() == RunRequest(title: nil, command: ["make", "-j8"]))
        #expect(try RunRequest.parse(["--title=Build", "--", "make"]).get().title == "Build")
        #expect(try RunRequest.parse(["cargo", "build"]).get().command == ["cargo", "build"])
        #expect(throws: RunUsageError.self) { try RunRequest.parse(["--"]).get() }
        #expect(throws: RunUsageError.self) { try RunRequest.parse(["--title"]).get() }
        #expect(throws: RunUsageError.self) { try RunRequest.parse(["--verbose", "--", "x"]).get() }
    }

    @Test func displayQuotesLikeAShell() {
        #expect(CommandRunner.display(["npm", "test"]) == "npm test")
        #expect(CommandRunner.display(["git", "commit", "-m", "it's done"]) == #"git commit -m 'it'\''s done'"#)
        #expect(RunRequest(title: nil, command: ["swift", "test", "--filter", "Bridge"]).displayTitle == "swift test --filter Bridge")
    }

    @Test func terminalSignalsAreNotSentTwice() {
        #expect(!CommandRunner.shouldForward(SIGINT, foreground: true))
        #expect(CommandRunner.shouldForward(SIGINT, foreground: false))
        #expect(CommandRunner.shouldForward(SIGTERM, foreground: true))
        #expect(CommandRunner.shouldForward(SIGHUP, foreground: true))
    }

    @Test func exitStatusesAreKept() async throws {
        let exited = try PosixSpawn.run("sh", arguments: ["-c", "exit 3"], environment: nil, searchPath: true, options: .init())
        #expect(await PosixSpawn.waitAsync(exited) == .exited(3))
        let killed = try PosixSpawn.run("sh", arguments: ["-c", "kill -TERM $$"], environment: nil, searchPath: true, options: .init())
        let t = await PosixSpawn.waitAsync(killed)
        #expect(t == .signaled(SIGTERM))
        #expect(t.shellStatus == 143)
        #expect(throws: PosixSpawnError.self) {
            _ = try PosixSpawn.run("definitely-not-a-command-sidefolk", arguments: [], environment: nil, searchPath: true, options: .init())
        }
    }
}

@Suite struct HookTests {
    let payload = #"""
        {"session_id":"7f0c-11","transcript_path":"/Users/me/.claude/projects/x.jsonl","cwd":"/Users/me/git/app",
         "hook_event_name":"Notification","message":"Claude needs your permission to use Bash\nmore","notification_type":"permission_prompt"}
        """#

    @Test func payloadBecomesASessionEvent() throws {
        let e = try #require(HookForwarder.sessionEvent(name: "Notification", payload: Array(payload.utf8),
                                                        host: HostApp(bundleId: "com.googlecode.iterm2", pid: 77), tty: "/dev/ttys003"))
        #expect(e.sessionId == "7f0c-11")
        #expect(e.cwd == "/Users/me/git/app")
        #expect(e.message == "Claude needs your permission to use Bash")
        #expect(e.notificationType == "permission_prompt")
        #expect(e.hostBundleId == "com.googlecode.iterm2")
        #expect(e.hostPid == 77)
        #expect(SessionEvent(json: e.json) == e)
    }

    @Test func promptIsTrimmedToItsFirstLine() throws {
        let prompt = String(repeating: "x", count: 300) + "\nsecret second line"
        let json: JSONValue = ["session_id": "s", "prompt": .string(prompt)]
        let e = try #require(HookForwarder.sessionEvent(name: "UserPromptSubmit", payload: Array(json.jsonString.utf8), host: nil, tty: nil))
        #expect(e.prompt?.count == 120)
        #expect(e.prompt?.contains("secret") == false)
    }

    @Test func truncatedPayloadStillYieldsTheSession() throws {
        let big = #"{"session_id":"abc","cwd":"/tmp/x","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":""#
            + String(repeating: "a", count: 1000)
        let e = try #require(HookForwarder.sessionEvent(name: "PreToolUse", payload: Array(big.utf8), host: nil, tty: nil))
        #expect(e.sessionId == "abc")
        #expect(e.toolName == "Write")
        #expect(HookForwarder.sessionEvent(name: "Stop", payload: Array("garbage".utf8), host: nil, tty: nil) == nil)
    }

    @Test func readsAtMostTheCap() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data(repeating: 0x61, count: 5000))
        let bytes = HookForwarder.readInput(pipe.fileHandleForReading.fileDescriptor, limit: 1000, deadline: Date().addingTimeInterval(1))
        #expect(bytes.count == 1000)
        // An open but silent stdin doesn't hold the hook past its deadline.
        let silent = Pipe()
        let start = Date()
        #expect(HookForwarder.readInput(silent.fileHandleForReading.fileDescriptor, limit: 1000, deadline: start.addingTimeInterval(0.2)).isEmpty)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func eventNames() {
        #expect(HookForwarder.isEventName("UserPromptSubmit"))
        #expect(!HookForwarder.isEventName("Stop;rm"))
        #expect(!HookForwarder.isEventName(""))
    }

    @Test func hostAppFromTheProcessChain() {
        #expect(ProcessAncestry.topLevelBundle("/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)")
                == "/Applications/Visual Studio Code.app")
        #expect(ProcessAncestry.topLevelBundle("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
                == "/System/Applications/Utilities/Terminal.app")
        #expect(ProcessAncestry.topLevelBundle("/usr/bin/login") == nil)
        // No app above this process: the inherited bundle id is used, without a pid.
        let host = ProcessAncestry.host(startingAt: 1, environment: ["__CFBundleIdentifier": "com.mitchellh.ghostty"])
        #expect(host == HostApp(bundleId: "com.mitchellh.ghostty", pid: nil))
        #expect(ProcessAncestry.host(startingAt: 1, environment: ["__CFBundleIdentifier": "bad id; rm"]) == nil)
        #expect(ProcessAncestry.parent(of: getpid()) == getppid())
    }

    @Test func windowlessAppsAreClimbedPast() throws {
        // Claude's desktop app runs Claude Code from a background-only claude.app; "Open" must
        // bring the desktop app forward, not the binary it can't activate.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hosts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func app(_ name: String, _ id: String, background: Bool = false) throws -> String {
            let contents = root.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
            if background { info["LSBackgroundOnly"] = true }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return root.appendingPathComponent("\(name).app").path
        }
        let cli = try app("claude", "com.example.cli", background: true), desk = try app("Desk", "com.example.desk")
        let paths: [pid_t: String] = [30: cli + "/Contents/MacOS/claude", 20: desk + "/Contents/Helpers/disclaimer", 10: desk + "/Contents/MacOS/Desk"]
        let parents: [pid_t: pid_t] = [30: 20, 20: 10, 10: 1]
        let host = ProcessAncestry.host(startingAt: 30, environment: [:], path: { paths[$0] }, parent: { parents[$0] })
        #expect(host == HostApp(bundleId: "com.example.desk", pid: 10))
        #expect(!ProcessAncestry.showsWindows(cli))
        #expect(ProcessAncestry.showsWindows(desk))
    }

    @Test func hookForwardsToTheApp() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data(#"{"session_id":"s-9","cwd":"/Users/me/git/app","prompt":"Ship it"}"#.utf8))
        try pipe.fileHandleForWriting.close()
        await HookForwarder.run(event: "UserPromptSubmit", socketPath: h.dir.socket, input: pipe.fileHandleForReading.fileDescriptor)
        let session = try await SessionStore(h.env.db).session(id: "s-9")
        #expect(session?.state == .working)
        #expect(session?.title == "Ship it")
    }

    @Test func hookIsQuietWhenTheAppIsAway() async throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data(#"{"session_id":"s"}"#.utf8))
        try pipe.fileHandleForWriting.close()
        let start = Date()
        await HookForwarder.run(event: "Stop", socketPath: dir.socket, input: pipe.fileHandleForReading.fileDescriptor)
        #expect(Date().timeIntervalSince(start) < HookForwarder.budget)
    }

    @Test func statusCommand() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let paths = SidefolkPaths(home: URL(fileURLWithPath: h.dir.path))
        let (text, running) = await HelperCommands.status(paths: paths)
        #expect(running)
        #expect(text.hasPrefix("Sidefolk \(SidefolkVersion.current) is running"))
        h.server.stop()
        let (away, stillRunning) = await HelperCommands.status(paths: paths)
        #expect(!stillRunning)
        #expect(away == "Sidefolk isn't running.")
    }
}
