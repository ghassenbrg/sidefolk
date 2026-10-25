import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// SECURITY §4.8 spawn hygiene, the line cap, the watchdog and group termination.
@Suite struct ExtensionProcessTests {
    func run(_ script: String, executable: String = "/bin/sh", env: [String: String] = ["PATH": "/usr/bin:/bin"],
             limits: ExtensionProcessLimits = .standard) async throws -> (OutputCollector, ExtensionProcessExit, ExtensionProcess) {
        let args = executable == "/bin/sh" ? ["-c", script] : []
        let p = try ExtensionProcess(spec: ExtensionProcessSpec(executable: executable, arguments: args, environment: env),
                                     limits: limits)
        let out = OutputCollector()
        try p.start(onOutput: { out.add($0) }, onExit: { _ in })
        let exit = await p.waitForExit()
        return (out, exit, p)
    }

    @Test func childSeesOnlyStandardDescriptors() async throws {
        // An inheritable descriptor in Sidefolk (like a database or socket) must not reach the child.
        let fd = open("/dev/null", O_RDONLY)
        let high = dup2(fd, 77)
        close(fd)
        defer { close(high) }
        #expect(fcntl(high, F_GETFD) & FD_CLOEXEC == 0)
        // `[ -e /dev/fd/N ]` opens nothing, so the loop lists exactly the descriptors the shell inherited.
        let (out, exit, _) = try await run("fd=3; while [ $fd -lt 256 ]; do if [ -e /dev/fd/$fd ]; then echo $fd; fi; fd=$((fd+1)); done; echo end")
        #expect(exit.cause == .exited(0))
        #expect(out.lines == ["end"], "open descriptors: \(out.lines)")
    }

    @Test func environmentIsExactlyWhatWasGiven() async throws {
        setenv("SIDEFOLK_TEST_LEAK", "1", 1)
        defer { unsetenv("SIDEFOLK_TEST_LEAK") }
        let (out, _, _) = try await run("", executable: "/usr/bin/env", env: ["PATH": "/usr/bin:/bin", "HOME": "/tmp/x"])
        #expect(Set(out.lines) == ["PATH=/usr/bin:/bin", "HOME=/tmp/x"])
    }

    @Test func linesAreSplitAndOversizedOnesReported() async throws {
        var limits = ExtensionProcessLimits()
        limits.maxLineBytes = 1000
        let (out, _, _) = try await run("echo one; head -c 5000 /dev/zero | tr '\\0' x; echo; echo two; printf 'tail'", limits: limits)
        #expect(out.outputs == [.line(Data("one".utf8)), .oversized, .line(Data("two".utf8)), .line(Data("tail".utf8))])
    }

    @Test func lineSplitterHandlesChunkBoundaries() {
        var s = ExtensionLineSplitter(maxLine: 8)
        var out: [ExtensionProcessOutput] = []
        for chunk in ["ab", "c\r\nde", "fghijklmn", "op\nq", "\n\n"] { out += s.feed(ArraySlice(Array(chunk.utf8))) }
        #expect(out == [.line(Data("abc".utf8)), .oversized, .line(Data("q".utf8))])
        #expect(s.finish() == nil)
    }

    @Test func stderrIsKeptInASmallRing() async throws {
        var limits = ExtensionProcessLimits()
        limits.stderrBytes = 64
        let (_, _, p) = try await run("head -c 1000 /dev/zero | tr '\\0' a >&2; printf END >&2", limits: limits)
        #expect(p.stderrTail.count == 64)
        #expect(p.stderrTail.hasSuffix("END"))
    }

    @Test func terminateKillsTheWholeGroup() async throws {
        let p = try ExtensionProcess(spec: ExtensionProcessSpec(executable: "/bin/sh", arguments: ["-c", "sleep 100 & sleep 100"],
                                                                environment: ["PATH": "/usr/bin:/bin"]))
        try p.start(onOutput: { _ in }, onExit: { _ in })
        try await Task.sleep(for: .milliseconds(200))
        let pgid = p.pid
        let exit = await p.terminate()
        #expect(exit.requested)
        try await Task.sleep(for: .milliseconds(100))
        #expect(kill(-pgid, 0) == -1 && errno == ESRCH, "group \(pgid) still has members")
    }

    @Test func terminateEscalatesToSIGKILL() async throws {
        var limits = ExtensionProcessLimits()
        limits.terminateGrace = 0.3
        let p = try ExtensionProcess(spec: ExtensionProcessSpec(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"],
                                                                environment: ["PATH": "/usr/bin:/bin"]), limits: limits)
        try p.start(onOutput: { _ in }, onExit: { _ in })
        try await Task.sleep(for: .milliseconds(200))
        let exit = await p.terminate()
        #expect(exit.cause == .signaled(SIGKILL))
    }

    @Test func watchdogKillsAGroupOverItsMemoryLimit() async throws {
        var limits = ExtensionProcessLimits()
        limits.maxResidentBytes = 64 * 1024
        limits.sampleInterval = 0.1
        let (_, exit, _) = try await run("sleep 30", limits: limits)
        #expect(exit.watchdog?.contains("memory") == true)
        #expect(exit.cause == .signaled(SIGKILL))
        #expect(!exit.requested)
    }

    @Test func watchdogKillsSustainedCPU() async throws {
        var limits = ExtensionProcessLimits()
        limits.sampleInterval = 0.1
        limits.cpuWindow = 0.5
        let (_, exit, _) = try await run("while :; do :; done", limits: limits)
        #expect(exit.watchdog?.contains("CPU") == true)
    }

    @Test func writingToADeadProcessThrowsInsteadOfSIGPIPE() async throws {
        let (_, _, p) = try await run("exit 0")
        await #expect(throws: (any Error).self) { try await p.write(Data("hello\n".utf8)) }
    }
}
