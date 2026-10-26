import Darwin
import Foundation

/// POSIX unix-domain socket helpers shared by the app's server and the `sidefolk` helper.
/// `NWListener` creates the socket with the process umask and exposes neither the fd nor peer
/// credentials, so both sides use plain sockets (docs/MACOS-NOTES.md §10, SECURITY.md T6).
public enum UnixSocket {
    /// `sun_path` holds 104 bytes including the terminating NUL.
    public static let maxPathBytes = 103

    static func address(for path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard !bytes.contains(0) else { throw BridgeError.unsafeLocation("the path contains NUL") }
        guard bytes.count <= maxPathBytes else { throw BridgeError.pathTooLong(path) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: bytes) }
        return addr
    }

    /// A stream socket that never raises SIGPIPE and is not inherited by spawned children.
    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.system("socket", errno) }
        prepare(fd)
        return fd
    }

    static func prepare(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    static func bind(_ fd: Int32, path: String) throws {
        var addr = try address(for: path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { throw BridgeError.system("bind", errno) }
    }

    /// Blocking connect. ENOENT and ECONNREFUSED mean nobody is listening.
    static func connect(_ fd: Int32, path: String) throws {
        var addr = try address(for: path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else {
            let code = errno
            if code == ENOENT || code == ECONNREFUSED { throw BridgeError.notRunning }
            throw BridgeError.system("connect", code)
        }
    }

    /// The uid of the process on the other end (`LOCAL_PEERCRED`). The uid is the access check; a pid
    /// never is, since pids get reused (see `peerPID`).
    public static func peerUID(_ fd: Int32) -> uid_t? {
        var cred = xucred()
        var len = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &cred, &len) == 0, cred.cr_version == UInt32(XUCRED_VERSION) else {
            return nil
        }
        return cred.cr_uid
    }

    /// The pid that connected (`LOCAL_PEERPID`). Used in logs, and to tell whether a session event's
    /// host app sits above its sender while that sender is still connected (`HostTrust`).
    static func peerPID(_ fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        return getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == 0 ? pid : nil
    }

    /// Writes everything, waiting up to `timeout` whenever a non-blocking socket is full.
    static func writeAll(_ fd: Int32, _ bytes: [UInt8], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { raw in Darwin.write(fd, raw.baseAddress! + offset, bytes.count - offset) }
            if n > 0 { offset += n; continue }
            if n < 0, errno == EINTR { continue }
            guard n < 0, errno == EAGAIN else { return false }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            _ = poll(&pfd, 1, Int32(min(remaining, 60) * 1000))
        }
        return true
    }

    /// Waits until `fd` is readable or the deadline passes.
    static func waitReadable(_ fd: Int32, until deadline: Date) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let rc = poll(&pfd, 1, Int32(max(1, min(remaining, 60) * 1000)))
            if rc > 0 { return true }
            if rc < 0, errno != EINTR { return false }
        }
    }
}

/// Splits a byte stream into lines, refusing any line longer than `limit`.
struct BridgeLineBuffer: Sendable {
    let limit: Int
    private var pending: [UInt8] = []

    init(limit: Int) { self.limit = limit }

    /// The complete lines in `chunk` (without the newline), or `overflow` when a line is too long.
    mutating func append(_ chunk: UnsafeRawBufferPointer) -> (lines: [[UInt8]], overflow: Bool) {
        var lines: [[UInt8]] = []
        var start = 0
        for (i, byte) in chunk.enumerated() where byte == 0x0A {
            pending.append(contentsOf: chunk[start..<i])
            start = i + 1
            if pending.last == 0x0D { pending.removeLast() }
            guard pending.count <= limit else { return (lines, true) }
            if !pending.isEmpty { lines.append(pending) }
            pending.removeAll(keepingCapacity: true)
        }
        pending.append(contentsOf: chunk[start...])
        return (lines, pending.count > limit)
    }

    mutating func append(_ bytes: [UInt8]) -> (lines: [[UInt8]], overflow: Bool) {
        bytes.withUnsafeBytes { append($0) }
    }
}

/// Folders that hold secrets or the socket: mode 0700, owned by this user, not a symlink (T6).
public enum PrivateDirectory {
    /// Creates `path` with mode 0700 if it is missing (parents too), then verifies it with `lstat`.
    public static func ensure(_ path: String) throws {
        let parent = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parent) {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        if mkdir(path, 0o700) != 0, errno != EEXIST { throw BridgeError.system("mkdir", errno) }
        try verify(path)
    }

    /// Refuses anything but a real directory owned by `getuid()` with no group or world bits.
    public static func verify(_ path: String) throws {
        var st = stat()
        guard lstat(path, &st) == 0 else { throw BridgeError.unsafeLocation("\(path) is missing") }
        guard st.st_mode & S_IFMT == S_IFDIR else { throw BridgeError.unsafeLocation("\(path) is not a real folder") }
        guard st.st_uid == getuid() else { throw BridgeError.unsafeLocation("\(path) belongs to another user") }
        guard st.st_mode & 0o077 == 0 else { throw BridgeError.unsafeLocation("\(path) is readable by other users") }
    }

    /// A private file written once: O_EXCL so an existing file or planted symlink is never followed.
    static func writeSecretFile(_ path: String, contents: String) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BridgeError.system("open", errno) }
        defer { close(fd) }
        _ = fchmod(fd, 0o600)
        let bytes = Array(contents.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, bytes.count - offset) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { throw BridgeError.system("write", errno) }
            offset += n
        }
    }

    /// Reads a small file only if it is a regular 0600 file owned by this user (no symlinks).
    static func readSecretFile(_ path: String, maxBytes: Int = 4096) throws -> String {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BridgeError.unsafeLocation("\(path) can't be opened") }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_mode & 0o077 == 0 else {
            throw BridgeError.unsafeLocation("\(path) must be a private file owned by you")
        }
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let n = read(fd, &buffer, maxBytes)
        guard n >= 0 else { throw BridgeError.system("read", errno) }
        return String(decoding: buffer[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
