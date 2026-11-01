import Darwin
import Testing
@testable import SidefolkCore

/// A child never started has pid 0, and `kill(-0, SIGKILL)` would end our own process group: the app, or a test run
/// and the script that started it (the release machine's silent deaths, 2026-11-01).
struct SafeKillTests {
    @Test func neverSignalsItself() {
        #expect(SafeKill.group(0, 0) == -1)
        #expect(SafeKill.group(1, 0) == -1)
        #expect(SafeKill.group(getpgrp(), 0) == -1)
        #expect(SafeKill.group(getpid(), 0) == -1)
        #expect(SafeKill.one(0, 0) == -1)
        #expect(SafeKill.one(getpid(), 0) == -1)
        #expect(SafeKill.one(getppid(), 0) == -1)
    }
}
