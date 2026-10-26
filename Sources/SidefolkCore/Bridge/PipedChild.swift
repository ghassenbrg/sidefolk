import Darwin
import Foundation
import Synchronization

/// A child in its own process group with only pipes on fds 0–2 (T7, T15): a timeout or cancel
/// stops the whole tree (Claude Code spawns node helpers and the MCP bridge), and the child never
/// inherits Sidefolk's database or socket descriptors.
final class PipedChild: Sendable {
    let pid: pid_t
    let output: Int32
    private let input: Mutex<Int32>
    private let errors: Int32
    private let exit: Task<ChildExit, Never>
    private let stderrTail: Task<String, Never>

    private init(pid: pid_t, input: Int32, output: Int32, errors: Int32) {
        self.pid = pid
        self.input = Mutex(input)
        self.output = output
        self.errors = errors
        exit = Task.detached { await PosixSpawn.waitAsync(pid) }
        // stderr must be drained or a chatty child blocks; reads happen on a thread of their own.
        stderrTail = Task.detached {
            await withCheckedContinuation { c in
                Thread.detachNewThread { c.resume(returning: PipedChild.drainTail(errors, keep: 8 * 1024)) }
            }
        }
    }

    deinit {
        input.withLock { if $0 >= 0 { Darwin.close($0) } }
        Darwin.close(output)
    }

    static func spawn(_ executable: String, arguments: [String], environment: [String: String], cwd: String) throws -> PipedChild {
        guard let i = SpawnLock.pipe() else { throw BridgeError.system("pipe", errno) }
        guard let o = SpawnLock.pipe() else { closeAll([i.read, i.write]); throw BridgeError.system("pipe", errno) }
        guard let e = SpawnLock.pipe() else { closeAll([i.read, i.write, o.read, o.write]); throw BridgeError.system("pipe", errno) }
        let stdinPipe = [i.read, i.write], stdoutPipe = [o.read, o.write], stderrPipe = [e.read, e.write]
        // Writing to a child that already died must fail with EPIPE, not kill Sidefolk.
        _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)
        let pid: pid_t
        do {
            pid = try PosixSpawn.run(executable, arguments: arguments, environment: environment, searchPath: false,
                                options: PosixSpawn.Options(newProcessGroup: true, closeOtherDescriptors: true,
                                                       stdio: (stdinPipe[0], stdoutPipe[1], stderrPipe[1]), cwd: cwd))
        } catch {
            closeAll(stdinPipe + stdoutPipe + stderrPipe)
            throw error
        }
        closeAll([stdinPipe[0], stdoutPipe[1], stderrPipe[1]])
        return PipedChild(pid: pid, input: stdinPipe[1], output: stdoutPipe[0], errors: stderrPipe[0])
    }

    private static func closeAll(_ fds: [Int32]) { for fd in fds where fd >= 0 { Darwin.close(fd) } }

    /// Writes to the child's stdin; false if it is gone.
    @discardableResult
    func write(_ text: String) -> Bool {
        input.withLock { fd in fd >= 0 && UnixSocket.writeAll(fd, Array(text.utf8), timeout: 10) }
    }

    func closeInput() {
        input.withLock { fd in
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }

    func wait() async -> ChildExit { await exit.value }

    /// The last few KB the child wrote to stderr (available once it exited).
    func stderr() async -> String { await stderrTail.value }

    /// Signals every process in the child's group (the group id is the child's pid).
    func signalGroup(_ signal: Int32) {
        _ = kill(-pid, signal)
    }

    /// SIGTERM to the group, SIGKILL after `grace` seconds if it is still there.
    func terminate(grace: TimeInterval = 2) async {
        signalGroup(SIGTERM)
        let exit = self.exit
        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await exit.value; return true }
            group.addTask { try? await Task.sleep(for: .seconds(grace)); return false }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
        if !ended { signalGroup(SIGKILL) }
        _ = await exit.value
        // Stragglers that ignored SIGTERM (the MCP helper, node) go with the group.
        signalGroup(SIGKILL)
    }

    private static func drainTail(_ fd: Int32, keep: Int) -> String {
        var tail: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            tail += chunk[0..<n]
            if tail.count > keep { tail.removeFirst(tail.count - keep) }
        }
        Darwin.close(fd)
        return String(decoding: tail, as: UTF8.self)
    }
}
