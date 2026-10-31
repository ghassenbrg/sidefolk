import Foundation
import Darwin
import Testing
@testable import SidefolkCore

struct OutputMuteLeaseTests {
    private final class Device: OutputMuteDevice {
        var current: UInt32 = 1
        var states: [UInt32: Bool] = [1: false, 2: false]
        var failMute = false
        func defaultOutput() throws -> UInt32 { current }
        func isMuted(_ device: UInt32) throws -> Bool { states[device] ?? false }
        func setMuted(_ muted: Bool, device: UInt32) throws {
            if muted && failMute { throw Failure.unsupported }
            states[device] = muted
        }
        enum Failure: Error { case unsupported }
    }

    @Test func restoresOnlyTheMuteItIntroduced() throws {
        let backend = Device()
        var lease = OutputMuteLease(backend: backend)
        try lease.followDefault()
        #expect(backend.states[1] == true)
        try lease.restore()
        #expect(backend.states[1] == false)
        backend.states[1] = true
        try lease.followDefault()
        try lease.restore()
        #expect(backend.states[1] == true)
    }

    @Test func respectsAnExternalUnmuteAndRestoresOnDeviceChanges() throws {
        let backend = Device()
        var lease = OutputMuteLease(backend: backend)
        try lease.followDefault()
        backend.states[1] = false
        try lease.restore()
        #expect(backend.states[1] == false)
        try lease.followDefault()
        backend.current = 2
        try lease.followDefault()
        #expect(backend.states[1] == false && backend.states[2] == true)
        try lease.restore()
        #expect(backend.states[2] == false)
    }

    @Test func unsupportedNewDeviceDoesNotLeavePreviousDeviceMuted() throws {
        let backend = Device()
        var lease = OutputMuteLease(backend: backend)
        try lease.followDefault()
        backend.current = 2
        backend.failMute = true
        #expect(throws: Device.Failure.self) { try lease.followDefault() }
        #expect(backend.states[1] == false && backend.states[2] == false)
        try lease.restore()
    }

    @Test func onlyOneExtensionCanOwnTheGuardian() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("guardian")
        try Data("#!/bin/sh\nprintf 'ok\\n'\ncat >/dev/null\n".utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        let router = OutputMuteRouter(executable: helper)
        try await router.set(true, owner: "one", sequence: 1, failed: { _ in })
        try await router.set(true, owner: "one", sequence: 2, failed: { _ in })
        await #expect(throws: UserFacingError.self) { try await router.set(true, owner: "two", sequence: 1, failed: { _ in }) }
        await #expect(throws: UserFacingError.self) { try await router.set(true, owner: "two", sequence: 2, failed: { _ in }) }
        try await router.release(owner: "two")
        try await router.set(true, owner: "two", sequence: 3, failed: { _ in })
        await #expect(throws: UserFacingError.self) { try await router.set(true, owner: "three", sequence: 1, failed: { _ in }) }
        try await router.release(owner: "one")
        try await router.set(true, owner: "three", sequence: 2, failed: { _ in })
        try await router.release(owner: "three")
        try await router.set(false, owner: "late", sequence: 2, failed: { _ in })
        try await router.set(true, owner: "late", sequence: 1, failed: { _ in })
        try await router.set(true, owner: "another", sequence: 1, failed: { _ in })
        try await router.releaseAll()
    }

    @Test func slowStartupCannotRaceANewGuardian() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("guardian")
        let marker = directory.appendingPathComponent("started")
        let script = "#!/bin/sh\nif [ ! -f '\(marker.path)' ]; then touch '\(marker.path)'; sleep 3.4; fi\nprintf 'ok\\n'\ncat >/dev/null\n"
        try Data(script.utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        let router = OutputMuteRouter(executable: helper)
        await #expect(throws: UserFacingError.self) { try await router.set(true, owner: "slow", sequence: 1, failed: { _ in }) }
        await #expect(throws: UserFacingError.self) { try await router.set(true, owner: "next", sequence: 1, failed: { _ in }) }
        try await Task.sleep(for: .seconds(1))
        try await router.set(true, owner: "next", sequence: 2, failed: { _ in })
        try await router.releaseAll()
    }

    @Test func unrelatedChildrenCannotKeepTheGuardianPipeOpen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("guardian")
        try Data("#!/bin/sh\nprintf 'ok\\n'\ncat >/dev/null\n".utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        let router = OutputMuteRouter(executable: helper)
        try await router.set(true, owner: "one", sequence: 1, failed: { _ in })
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["10"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }
        try await router.release(owner: "one")
        #expect(unrelated.isRunning, "the lease restored even though another child is still alive")
        try await router.releaseAll()
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func guardianSeesEOFWhenItsHostCrashes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("guardian")
        let restored = directory.appendingPathComponent("restored")
        let script = "#!/bin/sh\nprintf 'ok\\n'\ncat >/dev/null\nprintf restored > '\(restored.path)'\n"
        try Data(script.utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        let parent = Process(), output = Pipe()
        parent.executableURL = URL(fileURLWithPath: try #require(ExtFixtures.python?.path))
        parent.arguments = ["-c", "import subprocess,sys,time; p=subprocess.Popen([sys.argv[1]],stdin=subprocess.PIPE,stdout=subprocess.PIPE); print(p.stdout.readline().decode().strip(),flush=True); time.sleep(30)", helper.path]
        parent.standardOutput = output; parent.standardError = FileHandle.nullDevice
        try parent.run()
        defer { if parent.isRunning { parent.terminate() } }
        #expect(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).contains("ok"))
        #expect(kill(parent.processIdentifier, SIGKILL) == 0)
        parent.waitUntilExit()
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: restored.path) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(FileManager.default.fileExists(atPath: restored.path), "the surviving helper sees EOF and restores")
    }
}
