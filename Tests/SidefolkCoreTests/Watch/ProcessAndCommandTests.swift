import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// A table the test controls.
final class FakeProcessTable: ProcessTable {
    private let entries = Mutex<[ProcessEntry]>([])
    func set(_ list: [ProcessEntry]) { entries.withLock { $0 = list } }
    func find(name: String) -> [ProcessEntry] { entries.withLock { $0.filter { $0.name.lowercased() == name.lowercased() } } }
    func entry(pid: Int32) -> ProcessEntry? { entries.withLock { $0.first { $0.pid == pid } } }
}

@Suite struct ProcessExitsProbeTests {
    let table = FakeProcessTable()
    var probe: ProcessExitsProbe { ProcessExitsProbe(table: table) }

    func watcher(name: String? = nil, pid: Int? = nil) throws -> Watcher {
        var config: [String: JSONValue] = [:]
        if let name { config["name"] = .string(name) }
        if let pid { config["pid"] = .number(Double(pid)) }
        return try probe.made(.make(WatchKind.processExits, config: .object(config)))
    }

    @Test func triggersWhenTheProcessIsGoneAfterBeingSeen() async throws {
        var w = try watcher(name: "Xcode")
        table.set([ProcessEntry(pid: 10, name: "Xcode", startedAt: 100)])
        #expect(try await !probe.step(&w).triggered)
        #expect(try await !probe.step(&w).triggered)
        #expect(probe.eventTargets(for: w) == [.process(10)])

        table.set([])
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "Xcode exited")
        #expect(r.level == nil)
        #expect(try await !probe.step(&w).triggered)
    }

    @Test func aProcessThatWasNeverSeenIsSaidSoOnceAndGently() async throws {
        var w = try watcher(name: "NoSuchApp")
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "NoSuchApp isn't running")
        #expect(r.level == .gentle)
        #expect(try await !probe.step(&w).triggered, "not again and again")
        // If it does start later, it is watched like any other.
        table.set([ProcessEntry(pid: 5, name: "NoSuchApp", startedAt: 1)])
        #expect(try await !probe.step(&w).triggered)
        table.set([])
        #expect(try await probe.step(&w).summary == "NoSuchApp exited")
    }

    @Test func aPidIsOnlyTheSameProcessWhileItKeepsItsStartTime() async throws {
        var w = try watcher(pid: 77)
        table.set([ProcessEntry(pid: 77, name: "build", startedAt: 1000)])
        #expect(try await !probe.step(&w).triggered)
        // The pid is reused by something else: the one we watched is gone.
        table.set([ProcessEntry(pid: 77, name: "other", startedAt: 5000)])
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "Process 77 exited")
    }

    @Test func aPidWithANameMustAlsoMatchTheName() async throws {
        var w = try watcher(name: "node", pid: 9)
        table.set([ProcessEntry(pid: 9, name: "python", startedAt: 1)])
        #expect(try await probe.step(&w).summary == "node isn't running")
    }

    @Test func validation() throws {
        #expect(throws: WatchError.self) { _ = try watcher() }
        #expect(throws: WatchError.self) { _ = try watcher(pid: 0) }
        #expect(throws: WatchError.self) { _ = try watcher(name: "/usr/bin/sleep") }
        #expect(probe.minimumInterval == 3)
        #expect(probe.defaultInterval == 5)
    }

    // MARK: Against the real process table

    /// A uniquely named copy of the `sleep` command (a link would run as "sleep"), so a name watch cannot match anything else.
    func uniqueSleeper(in box: Sandbox) throws -> (path: String, name: String) {
        let name = "sft" + UUID().uuidString.prefix(8).lowercased().replacingOccurrences(of: "-", with: "")
        let path = box.path(name)
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: path)
        return (path, name)
    }

    @Test func watchesARealProcessByPidAndSeesItExit() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let real = ProcessExitsProbe(table: LibprocTable())

        var w = try real.made(.make(WatchKind.processExits, config: ["pid": .number(Double(child.processIdentifier))]))
        #expect(try await !real.step(&w).triggered)
        #expect(w.lastState?["seen"]?.boolValue == true)
        #expect(real.eventTargets(for: w) == [.process(child.processIdentifier)])

        child.terminate()
        child.waitUntilExit()
        let r = try await real.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "Process \(child.processIdentifier) exited")
    }

    @Test func watchesARealProcessByNameAndSeesItExit() async throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let sleeper = try uniqueSleeper(in: box)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: sleeper.path)
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let real = ProcessExitsProbe(table: LibprocTable())

        var w = try real.made(.make(WatchKind.processExits, config: ["name": .string(sleeper.name)]))
        #expect(try await !real.step(&w).triggered)
        #expect(w.lastState?["seen"]?.boolValue == true, "the table should find “\(sleeper.name)”")

        child.terminate()
        child.waitUntilExit()
        #expect(try await real.step(&w).summary == "\(sleeper.name) exited")
    }

    @Test func aRealSleepThatEndsOnItsOwnIsNoticed() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["1"]
        try child.run()
        let real = ProcessExitsProbe(table: LibprocTable())
        var w = try real.made(.make(WatchKind.processExits, config: ["pid": .number(Double(child.processIdentifier))]))
        #expect(try await !real.step(&w).triggered)
        child.waitUntilExit()
        #expect(try await real.step(&w).triggered)
    }

    @Test func libprocFindsThisTestProcess() {
        let table = LibprocTable()
        let me = table.entry(pid: getpid())
        #expect(me != nil)
        #expect(me.map { table.find(name: $0.name).contains { $0.pid == getpid() } } == true)
        #expect(table.entry(pid: 0x7ffffff0) == nil)
        let started = Date()
        _ = table.find(name: "no-such-process-anywhere")
        #expect(Date().timeIntervalSince(started) < 0.5, "a scan of every process should be cheap")
    }
}

@Suite struct ShellRunnerTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    func run(_ command: String, timeout: TimeInterval = 10, limit: Int = ShellRunner.outputLimit) async throws -> ShellResult {
        try await ShellRunner.run(command, cwd: box.root, timeout: timeout, grace: 0.3, outputLimit: limit)
    }

    /// True once no process is left in the group. Killed children linger as zombies until launchd reaps them, so give it a moment.
    func groupIsGone(_ pid: Int32) -> Bool {
        for _ in 0..<40 {
            if killpg(pid, 0) != 0, errno == ESRCH { return true }
            usleep(50_000)
        }
        return false
    }

    @Test func capturesOutputAndExitCode() async throws {
        defer { box.cleanUp() }
        let r = try await run("echo out; echo err 1>&2; exit 3")
        #expect(r.exitCode == 3)
        #expect(r.output.contains("out") && r.output.contains("err"))
        #expect(!r.timedOut)
    }

    @Test func runsInTheGivenFolderWithNothingOnStdin() async throws {
        defer { box.cleanUp() }
        #expect(try await run("pwd").output.trimmingCharacters(in: .whitespacesAndNewlines) == box.root)
        let r = try await run("cat; echo done") // would hang if stdin were a terminal or a pipe
        #expect(r.output.contains("done"))
    }

    @Test func theEnvironmentIsFixedAndScrubbed() async throws {
        defer { box.cleanUp() }
        setenv("SIDEFOLK_TEST_SECRET", "hunter2", 1)
        setenv("DYLD_INSERT_LIBRARIES", "/tmp/evil.dylib", 1)
        setenv("ANTHROPIC_API_KEY", "sk-ant-secret-secret-secret", 1)
        defer {
            unsetenv("SIDEFOLK_TEST_SECRET")
            unsetenv("DYLD_INSERT_LIBRARIES")
            unsetenv("ANTHROPIC_API_KEY")
        }
        let r = try await run("env")
        #expect(!r.output.contains("hunter2"))
        #expect(!r.output.contains("DYLD_"))
        #expect(!r.output.contains("ANTHROPIC"))
        #expect(r.output.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"))
    }

    @Test func noFileDescriptorsLeakIntoTheCommand() async throws {
        defer { box.cleanUp() }
        // A high descriptor, deliberately without close-on-exec, that `ls` itself cannot be mistaken for.
        let devNull = open("/dev/null", O_RDONLY)
        let leaked = fcntl(devNull, F_DUPFD, 100)
        defer {
            close(devNull)
            close(leaked)
        }
        let r = try await run("ls /dev/fd")
        let fds = Set(r.output.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) })
        #expect(!fds.contains(leaked), "fd \(leaked) leaked: \(fds)")
        #expect(fds.allSatisfy { $0 < 10 }, "fds: \(fds)")
    }

    @Test func outputIsCapped() async throws {
        defer { box.cleanUp() }
        let r = try await run("head -c 300000 /dev/zero | tr '\\0' 'x'", limit: 64 * 1024)
        #expect(r.output.utf8.count == 64 * 1024)
        #expect(r.truncated)
    }

    @Test func aTimeoutStopsTheCommandAndEverythingItStarted() async throws {
        defer { box.cleanUp() }
        let started = Date()
        let r = try await run("sleep 100 & sleep 100", timeout: 0.5)
        #expect(r.timedOut)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(groupIsGone(r.pid), "nothing from the command may be left running")
    }

    @Test func aCommandThatIgnoresTermIsKilledAfterTheGracePeriod() async throws {
        defer { box.cleanUp() }
        let r = try await run("trap '' TERM; while true; do sleep 1; done", timeout: 0.4)
        #expect(r.timedOut)
        #expect(groupIsGone(r.pid))
    }

    @Test func leftoversAreCleanedUpEvenWithoutATimeout() async throws {
        defer { box.cleanUp() }
        let r = try await run("sleep 100 & echo started")
        #expect(r.output.contains("started"))
        #expect(!r.timedOut)
        #expect(groupIsGone(r.pid), "a background job must not outlive the check")
    }

    @Test func cancellingTheCheckStopsTheCommand() async throws {
        defer { box.cleanUp() }
        let pidFile = box.path("pid")
        let task = Task { try await run("echo $$ > \(pidFile); sleep 100") }
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: pidFile) { try await Task.sleep(for: .milliseconds(50)) }
        task.cancel()
        let r = try await task.value
        #expect(groupIsGone(r.pid))
    }

    @Test func aCommandThatCannotStartIsAnError() async {
        await #expect(throws: ShellError.self) { try await ShellRunner.run("true", cwd: "/definitely/not/here") }
    }
}

@Suite struct CommandProbeTests {
    let box: Sandbox
    var probe: CommandProbe { CommandProbe(timeout: 5, grace: 0.3) }

    init() throws { box = try Sandbox() }

    func watcher(_ command: String, _ condition: JSONValue = .object([:]), source: String = "user", cwd: String? = nil) throws -> Watcher {
        var config: JSONValue = ["command": .string(command)]
        if let cwd { config = config.setting("cwd", .string(cwd)) }
        return try probe.made(.make(WatchKind.command, config: config, condition: condition, title: "my job", source: source))
    }

    @Test func exitCodeCondition() async throws {
        defer { box.cleanUp() }
        var ok = try watcher("echo fine", ["exit_code": 0])
        let r = try await probe.step(&ok)
        #expect(r.triggered)
        #expect(r.summary == "my job succeeded")
        #expect(r.detail == "Output: fine")
        #expect(try await !probe.step(&ok).triggered, "still true, already told")

        var bad = try watcher("echo boom; exit 2", ["exit_code": 2])
        #expect(try await probe.step(&bad).summary == "my job exited with code 2")
        var other = try watcher("exit 1", ["exit_code": 0])
        #expect(try await !probe.step(&other).triggered)
    }

    @Test func outputContainsCondition() async throws {
        defer { box.cleanUp() }
        let flag = box.path("flag")
        var w = try watcher("cat \(flag) 2>/dev/null; true", ["output_contains": "READY"])
        #expect(try await !probe.step(&w).triggered)
        try Data("system Ready now".utf8).write(to: URL(fileURLWithPath: flag))
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "my job: found “READY”")
    }

    @Test func changedCondition() async throws {
        defer { box.cleanUp() }
        let file = box.path("value")
        try Data("one".utf8).write(to: URL(fileURLWithPath: file))
        var w = try watcher("cat \(file)")
        #expect(w.condition["changed"]?.boolValue == true, "changed is the default")
        #expect(try await !probe.step(&w).triggered, "baseline")
        #expect(try await !probe.step(&w).triggered)
        try Data("two".utf8).write(to: URL(fileURLWithPath: file))
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "my job: the output changed")
        #expect(r.detail == "“one” → “two”")
    }

    @Test func aSlowCommandIsAFailureNotAHang() async throws {
        defer { box.cleanUp() }
        let quick = CommandProbe(timeout: 0.4, grace: 0.2)
        var w = try quick.made(.make(WatchKind.command, config: ["command": "sleep 100"], source: "user"))
        await #expect(throws: ProbeError.self) { try await quick.step(&w) }
    }

    @Test func runsInTheChosenFolder() async throws {
        defer { box.cleanUp() }
        var w = try watcher("pwd", ["output_contains": .string(WatchedPath.name(box.root))], cwd: box.root)
        #expect(w.config.string("cwd") == box.root)
        #expect(try await probe.step(&w).triggered)
    }

    @Test func onlyTheUserOrTheApprovedAgentCanMakeOne() throws {
        for source in ["external:codex", "extension:dev.x", "routine:abc"] {
            #expect(throws: WatchError.notAllowed("Only you, or Sidefolk after you approve the exact command, can set up a command watcher.")) {
                _ = try watcher("echo hi", source: source)
            }
        }
        _ = try watcher("echo hi", source: "user")
        _ = try watcher("echo hi", source: "agent")
        #expect(probe.minimumInterval == 60)
    }

    @Test func aRowFromAnotherSourceIsNotRunEvenIfItGotIntoTheDatabase() async throws {
        var w = try watcher("touch /tmp/should-never-exist-\(UUID().uuidString)")
        w.source = "external:codex"
        await #expect(throws: ProbeError.self) { try await probe.step(&w) }
    }

    @Test func badFoldersAndCodesAreRefused() throws {
        defer { box.cleanUp() }
        #expect(throws: WatchError.self) { _ = try watcher("true", cwd: "relative") }
        #expect(throws: WatchError.self) { _ = try watcher("true", cwd: "~/.ssh") }
        #expect(throws: WatchError.self) { _ = try watcher("true", cwd: box.path("missing")) }
        #expect(throws: WatchError.self) { _ = try watcher("true", ["exit_code": 300]) }
        #expect(throws: WatchError.self) { _ = try watcher("   ") }
        #expect(throws: WatchError.self) { _ = try watcher(String(repeating: "a", count: 2001)) }
    }
}
