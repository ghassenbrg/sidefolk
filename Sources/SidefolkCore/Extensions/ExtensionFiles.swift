import Darwin
import Foundation
import Synchronization

/// One file of an installed extension as pinned at install (SECURITY T14).
public struct ExtensionFilePin: Codable, Sendable, Hashable {
    /// Relative to the extension folder, `/`-separated.
    public var path: String
    public var mode: UInt16
    public var size: Int64
    public var sha256: String
}

/// Walking, copying, pinning and locking extension folders. Links, setuid/setgid/sticky bits and special
/// files (FIFOs, sockets, devices) are refused outright.
enum ExtensionFiles {
    /// Left out of a copy: version-control metadata, Finder litter and Python bytecode caches.
    static let skippedNames: Set<String> = [".git", ".DS_Store", "__pycache__"]
    static let maxFiles = 10_000
    static let maxBytes: Int64 = 200 * 1024 * 1024

    struct Entry {
        var path: String
        var isDirectory: Bool
        var st: stat
    }

    /// Every entry under `root` (depth first, sorted), with links and special files rejected.
    static func walk(_ root: String, skipping: Set<String> = []) throws -> [Entry] {
        var out: [Entry] = []
        var total: Int64 = 0
        func visit(_ rel: String, depth: Int) throws {
            guard depth <= 32 else { throw UserFacingError("The extension's folders are nested too deeply.") }
            let dir = rel.isEmpty ? root : root + "/" + rel
            let names = try FileManager.default.contentsOfDirectory(atPath: dir).sorted()
            for name in names where !skipping.contains(name) {
                let childRel = rel.isEmpty ? name : rel + "/" + name
                guard let st = ExtensionFS.lstat(root + "/" + childRel) else {
                    throw UserFacingError("Couldn't read \(childRel) in the extension.")
                }
                let type = st.st_mode & S_IFMT
                if type == S_IFLNK {
                    throw UserFacingError("The extension contains a link (\(childRel)). Extensions can't contain links.")
                }
                if st.st_mode & (S_ISUID | S_ISGID | S_ISVTX) != 0 {
                    throw UserFacingError("\(childRel) has special permission bits (setuid, setgid or sticky).")
                }
                if type == S_IFDIR {
                    out.append(Entry(path: childRel, isDirectory: true, st: st))
                    try visit(childRel, depth: depth + 1)
                } else if type == S_IFREG {
                    total += Int64(st.st_size)
                    out.append(Entry(path: childRel, isDirectory: false, st: st))
                } else {
                    throw UserFacingError("\(childRel) isn't a regular file or folder.")
                }
                guard out.count <= maxFiles else { throw UserFacingError("The extension has more than \(maxFiles) files.") }
                guard total <= maxBytes else { throw UserFacingError("The extension is larger than 200 MB.") }
            }
        }
        try visit("", depth: 0)
        return out
    }

    /// Copies `source` into a new folder `dest` (which must not exist), file by file, without following links.
    static func copy(from source: String, to dest: String) throws {
        let entries = try walk(source, skipping: skippedNames)
        guard mkdir(dest, 0o700) == 0 else { throw ExtensionError.io("Couldn't create \(dest): \(String(cString: strerror(errno)))") }
        for e in entries {
            let target = dest + "/" + e.path
            if e.isDirectory {
                guard mkdir(target, 0o700) == 0 else { throw ExtensionError.io("Couldn't create \(target)") }
            } else {
                try copyFile(source + "/" + e.path, to: target, expected: e.st)
            }
        }
    }

    private static func copyFile(_ from: String, to: String, expected: stat) throws {
        let src = open(from, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard src >= 0 else { throw ExtensionError.io("Couldn't read \(from)") }
        defer { close(src) }
        var st = stat()
        // The file must still be the one we checked (no swap between the walk and the copy).
        guard fstat(src, &st) == 0, st.st_ino == expected.st_ino, st.st_dev == expected.st_dev, ExtensionFS.isRegular(st) else {
            throw UserFacingError("The extension changed while it was being copied. Try again.")
        }
        let dst = open(to, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard dst >= 0 else { throw ExtensionError.io("Couldn't write \(to)") }
        defer { close(dst) }
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(src, $0.baseAddress, $0.count) }
            if n == 0 { break }
            if n < 0 { if errno == EINTR { continue }; throw ExtensionError.io("Couldn't read \(from)") }
            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes { write(dst, $0.baseAddress! + written, n - written) }
                if w < 0 { if errno == EINTR { continue }; throw ExtensionError.io("Couldn't write \(to)") }
                written += w
            }
        }
        // Keep only the executable bit from the source; everything else is normalised when locking.
        _ = fchmod(dst, expected.st_mode & 0o111 != 0 ? 0o700 : 0o600)
    }

    /// Files become 0444 (0555 if executable) and folders 0555, deepest first.
    static func lock(_ root: String) throws {
        for e in try walk(root).reversed() {
            let mode: mode_t = e.isDirectory || e.st.st_mode & 0o111 != 0 ? 0o555 : 0o444
            guard chmod(root + "/" + e.path, mode) == 0 else { throw ExtensionError.io("Couldn't lock \(e.path)") }
        }
        guard chmod(root, 0o555) == 0 else { throw ExtensionError.io("Couldn't lock \(root)") }
    }

    /// Undoes `lock` on folders so the tree can be removed. Never follows links.
    static func removeTree(_ root: String) {
        guard let st = ExtensionFS.lstat(root) else { return }
        if ExtensionFS.isDirectory(st) {
            _ = chmod(root, 0o700)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
                removeTree(root + "/" + name)
            }
            _ = rmdir(root)
        } else {
            _ = unlink(root)
        }
    }

    /// SHA-256, mode and size of every file, sorted by path.
    static func pin(_ root: String) throws -> [ExtensionFilePin] {
        try walk(root).filter { !$0.isDirectory }.map { e in
            ExtensionFilePin(path: e.path, mode: UInt16(e.st.st_mode & 0o7777), size: Int64(e.st.st_size),
                             sha256: try ExtensionHash.sha256(file: root + "/" + e.path))
        }
    }

    /// One hash over all pins, stored as the record's `manifestHash`.
    static func aggregateHash(_ pins: [ExtensionFilePin]) -> String {
        let lines = pins.map { "\($0.path)\t\(String($0.mode, radix: 8))\t\($0.size)\t\($0.sha256)" }
        return ExtensionHash.sha256(Data(lines.joined(separator: "\n").utf8))
    }
}

/// Verifies installed files against their pins before every spawn. Files whose inode, mtime, size and
/// mode are unchanged since the last hash are not re-hashed; a full hash runs at least daily.
final class ExtensionIntegrity: Sendable {
    private struct Fingerprint: Hashable {
        var dev: Int32, ino: UInt64, sec: Int, nsec: Int, size: Int64, mode: UInt16
        init(_ st: stat) {
            dev = st.st_dev
            ino = st.st_ino
            sec = st.st_mtimespec.tv_sec
            nsec = st.st_mtimespec.tv_nsec
            size = Int64(st.st_size)
            mode = UInt16(st.st_mode & 0o7777)
        }
    }

    private struct Verified {
        var fingerprints: [String: Fingerprint]
        var fullAt: Date
    }

    private let cache = Mutex<[String: Verified]>([:])
    private let fullInterval: TimeInterval

    init(fullInterval: TimeInterval = 86_400) { self.fullInterval = fullInterval }

    /// Nil when every file matches its pin; otherwise a sentence saying what changed.
    func verify(id: String, folder: String, pins: [ExtensionFilePin], now: Date = Date()) -> String? {
        guard let st = ExtensionFS.lstat(folder), ExtensionFS.isDirectory(st) else { return "Its folder is missing." }
        let entries: [ExtensionFiles.Entry]
        do { entries = try ExtensionFiles.walk(folder) } catch { return "Its folder now contains a link or a special file." }
        let files = entries.filter { !$0.isDirectory }
        let pinned = Dictionary(uniqueKeysWithValues: pins.map { ($0.path, $0) })
        if let extra = files.first(where: { pinned[$0.path] == nil }) { return "A file was added: \(extra.path)." }
        let present = Set(files.map(\.path))
        if let missing = pins.first(where: { !present.contains($0.path) }) { return "A file is missing: \(missing.path)." }

        let previous = cache.withLock { $0[id] }
        let full = previous.map { now.timeIntervalSince($0.fullAt) >= fullInterval } ?? true
        var fingerprints: [String: Fingerprint] = [:]
        for f in files {
            let pin = pinned[f.path]!
            let fp = Fingerprint(f.st)
            fingerprints[f.path] = fp
            if !full, previous?.fingerprints[f.path] == fp { continue }
            guard fp.mode == pin.mode, fp.size == pin.size,
                  (try? ExtensionHash.sha256(file: folder + "/" + f.path)) == pin.sha256 else {
                cache.withLock { $0[id] = nil }
                return "A file changed: \(f.path)."
            }
        }
        cache.withLock { $0[id] = Verified(fingerprints: fingerprints, fullAt: full ? now : previous!.fullAt) }
        return nil
    }

    func forget(_ id: String) { cache.withLock { $0[id] = nil } }
}
