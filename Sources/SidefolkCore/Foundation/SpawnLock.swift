import Darwin
import Foundation

/// macOS has no `pipe2(O_CLOEXEC)`: between `pipe()` and `fcntl(FD_CLOEXEC)` another thread's spawn
/// could inherit the new descriptors, and a reader would then wait forever for end-of-file. Every
/// place that creates pipes or spawns a process takes this one lock, so that window never overlaps
/// a spawn.
public enum SpawnLock {
    private static let lock = NSLock()

    public static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Runs a spawn call, retrying briefly on ETXTBSY: an executable that was just written can be
    /// held open for a moment by a child some other part of the process started.
    public static func spawn(_ attempt: () -> Int32) -> Int32 {
        var rc: Int32 = 0
        for delay in [0, 20_000, 50_000, 100_000, 200_000] as [useconds_t] {
            if delay > 0 { usleep(delay) }
            rc = withLock { attempt() }
            if rc != ETXTBSY { return rc }
        }
        return rc
    }

    /// A pipe whose both ends are close-on-exec. Returns nil (errno set) on failure.
    public static func pipe() -> (read: Int32, write: Int32)? {
        withLock {
            var fds: [Int32] = [-1, -1]
            guard Darwin.pipe(&fds) == 0 else { return nil }
            _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
            _ = fcntl(fds[1], F_SETFD, FD_CLOEXEC)
            return (fds[0], fds[1])
        }
    }
}
