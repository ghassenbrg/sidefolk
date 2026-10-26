import Darwin
import Foundation

/// Another tool's config file, edited the careful way: a timestamped backup beside it first, then an
/// atomic replace that keeps its permissions, follows a symlinked dotfile to its target, and
/// refuses to overwrite a file that changed since it was read.
struct AgentConfigFile {
    let url: URL

    struct Snapshot {
        /// nil when the file does not exist.
        var text: String?
        var modified: Date?
        var mode: mode_t?
    }

    static let maxBytes = 64 << 20

    func read() throws -> Snapshot {
        let path = target
        var st = stat()
        guard stat(path, &st) == 0 else {
            if errno == ENOENT { return Snapshot() }
            throw IntegrationError.unreadable(url.path, String(cString: strerror(errno)))
        }
        guard st.st_mode & S_IFMT == S_IFREG, st.st_size <= Self.maxBytes else {
            throw IntegrationError.unreadable(url.path, "not a regular file of reasonable size")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else { throw IntegrationError.unreadable(url.path, "not UTF-8 text") }
        return Snapshot(text: text, modified: Self.mtime(st), mode: st.st_mode & 0o7777)
    }

    /// The path writes go to: the symlink's target for a symlinked dotfile.
    var target: String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `<file>.sidefolk-backup-20261026-101500` next to the file, same permissions (0600 at most).
    func backupURL(at date: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = URL(fileURLWithPath: target).path + ".sidefolk-backup-" + f.string(from: date)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return URL(fileURLWithPath: candidate)
    }

    func backup(_ snapshot: Snapshot, to backup: URL) throws {
        guard let text = snapshot.text else { return }
        try write(Data(text.utf8), to: backup.path, mode: min(snapshot.mode ?? 0o600, 0o600), exclusive: true)
    }

    /// Replaces the file atomically. Throws `changedMeanwhile` if someone else wrote it after `snapshot`.
    func replace(with text: String, expecting snapshot: Snapshot) throws {
        let path = target
        var st = stat()
        let exists = stat(path, &st) == 0
        if exists != (snapshot.text != nil) || (exists && Self.mtime(st) != snapshot.modified) {
            throw IntegrationError.changedMeanwhile(url.path)
        }
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temp = dir + "/." + (path as NSString).lastPathComponent + ".sidefolk-" + Identifier.make()
        do {
            try write(Data(text.utf8), to: temp, mode: snapshot.mode ?? 0o600, exclusive: true)
            guard rename(temp, path) == 0 else { throw IntegrationError.unwritable(url.path, String(cString: strerror(errno))) }
        } catch {
            unlink(temp)
            throw error
        }
    }

    private func write(_ data: Data, to path: String, mode: mode_t, exclusive: Bool) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC | (exclusive ? O_EXCL : O_TRUNC), mode)
        guard fd >= 0 else { throw IntegrationError.unwritable(path, String(cString: strerror(errno))) }
        defer { close(fd) }
        _ = fchmod(fd, mode)
        let ok = data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
        guard ok, fsync(fd) == 0 else { throw IntegrationError.unwritable(path, String(cString: strerror(errno))) }
    }

    private static func mtime(_ st: stat) -> Date {
        Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
    }
}

public enum IntegrationError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case unreadable(String, String)
    case unwritable(String, String)
    case malformed(String, String)
    case changedMeanwhile(String)

    public var description: String {
        switch self {
        case .unavailable(let why): why
        case .unreadable(let path, let why): String(localized: "\(FolderAccess.displayPath(path)) can't be read: \(why).")
        case .unwritable(let path, let why): String(localized: "\(FolderAccess.displayPath(path)) can't be written: \(why).")
        case .malformed(let path, let why):
            String(localized: "\(FolderAccess.displayPath(path)) isn't what Sidefolk expected (\(why)), so it wasn't changed.")
        case .changedMeanwhile(let path):
            String(localized: "\(FolderAccess.displayPath(path)) changed while Sidefolk was editing it. Nothing was written; try again.")
        }
    }
}
