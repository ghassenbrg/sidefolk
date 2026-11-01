import Darwin

/// Signals that can never reach Sidefolk itself. `kill(-0, …)` is `kill(0, …)`: the caller's own process group, which
/// under a CI runner or a shell holds the app or the test run and everything that started it. A child that was never
/// started (pid 0), launchd (1), our own group and our own pid are refused.
enum SafeKill {
    /// Signals the process group led by `pid`.
    @discardableResult
    static func group(_ pid: pid_t, _ signal: Int32) -> Int32 {
        guard pid > 1, pid != getpgrp(), pid != getpid() else { return -1 }
        return kill(-pid, signal)
    }

    /// Signals one process.
    @discardableResult
    static func one(_ pid: pid_t, _ signal: Int32) -> Int32 {
        guard pid > 1, pid != getpid(), pid != getppid() else { return -1 }
        return kill(pid, signal)
    }
}
