import Darwin
import Foundation
import Testing
@testable import SidefolkCore

@Suite struct StderrTeeTests {
    /// Runs `script` with its stderr through a tee whose own output goes to a pipe we read back.
    func run(_ script: String, terminal: Bool) async throws -> (passedOn: String, kept: String, exit: ChildExit) {
        let sink = try #require(SpawnLock.pipe())
        let tee = try #require(StderrTee.make(output: sink.write, terminal: terminal))
        let running = try CommandRunner.start(["/bin/sh", "-c", script], stderr: tee.childEnd)
        tee.childStarted()
        let exit = await running.wait()
        let kept = tee.finish(within: 2)
        close(sink.write)
        let passedOn = String(decoding: FileHandle(fileDescriptor: sink.read, closeOnDealloc: true).readDataToEndOfFile(), as: UTF8.self)
        return (passedOn, kept, exit)
    }

    @Test(arguments: [false, true]) func errorsArePassedOnAndKept(terminal: Bool) async throws {
        let r = try await run("echo first >&2; echo boom >&2; exit 2", terminal: terminal)
        #expect(r.exit == .exited(2))
        #expect(StderrTee.lastLines(r.kept) == ["first", "boom"])
        #expect(StderrTee.lastLines(r.passedOn) == ["first", "boom"], "the person at the terminal still sees everything")
    }

    @Test func theCommandStillSeesATerminalOnStderr() async throws {
        let r = try await run("if [ -t 2 ]; then echo tty >&2; else echo notty >&2; fi", terminal: true)
        #expect(StderrTee.lastLines(r.kept) == ["tty"])
        let piped = try await run("if [ -t 2 ]; then echo tty >&2; else echo notty >&2; fi", terminal: false)
        #expect(StderrTee.lastLines(piped.kept) == ["notty"])
    }

    @Test func onlyTheLastFewKilobytesAreKept() async throws {
        let r = try await run("i=0; while [ $i -lt 2000 ]; do echo line $i >&2; i=$((i+1)); done; exit 1", terminal: false)
        #expect(r.kept.utf8.count <= StderrTee.keep)
        #expect(StderrTee.lastLines(r.kept).last == "line 1999")
    }

    @Test func lastLinesAreWhatAPersonSaw() {
        let text = "\u{1B}[31merror:\u{1B}[0m it broke\r\n 10%\r 50%\r100%\r\n\r\n\u{1B}]0;title\u{07}npm ERR! code 1\n"
        #expect(StderrTee.lastLines(text) == ["error: it broke", "100%", "npm ERR! code 1"])
        #expect(StderrTee.lastLines("a\nb\nc\nd", count: 2) == ["c", "d"])
        #expect(StderrTee.lastLines(String(repeating: "y", count: 400)).first?.count ?? 0 <= 160)
        #expect(StderrTee.lastLines("\n \n").isEmpty)
    }
}
