import CryptoKit
import Darwin
import Foundation

/// Text that comes from an extension is untrusted: invisible and bidi characters are stripped and
/// lengths are capped before anything shows it to the model or the user (SECURITY T2, T17).
enum ExtensionText {
    /// Removes zero-width, bidi-control, tag and control characters (newline and tab survive).
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars where !isHidden(s) { scalars.append(s) }
        return String(scalars)
    }

    static func isHidden(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09, 0x0A: false
        case 0x00...0x1F, 0x7F...0x9F: true
        case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: true
        default: false
        }
    }

    /// At most `bytes` UTF-8 bytes, cut on a character boundary and marked with an ellipsis.
    static func cap(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var out = ""
        var used = 0
        let budget = bytes - 3 // room for "…"
        for ch in text {
            let n = ch.utf8.count
            if used + n > budget { break }
            out.append(ch)
            used += n
        }
        return out + "…"
    }

    /// Cleaned, capped text for descriptions and errors.
    static func untrusted(_ text: String, bytes: Int) -> String {
        cap(clean(text).trimmingCharacters(in: .whitespacesAndNewlines), bytes: bytes)
    }

    /// One cleaned line (titles, summaries) of at most `characters` characters.
    static func line(_ text: String, characters: Int) -> String {
        let flat = clean(text).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        return flat.clipped(characters)
    }

    /// True when the string holds characters that make a path or name ambiguous to read.
    static func hasControlOrQuote(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            s.value < 0x20 || s.value == 0x7F || s == "\"" || s == "'" || s == "\\" || isHidden(s)
        }
    }
}

enum ExtensionHash {
    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    static func sha256(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    static func sha256(_ value: JSONValue) -> String { sha256(Data(value.jsonString.utf8)) }

    /// Streams a regular file without following a symlink at the last component.
    static func sha256(file path: String) throws -> String {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ExtensionError.io("Couldn't read \(path): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
            } else if n == 0 {
                break
            } else if errno != EINTR {
                throw ExtensionError.io("Couldn't read \(path): \(String(cString: strerror(errno)))")
            }
        }
        return hex(hasher.finalize())
    }
}

enum ExtensionFS {
    /// `realpath(3)` of an existing path, or nil.
    static func realpath(_ path: String) -> String? {
        guard let p = Darwin.realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    static func lstat(_ path: String) -> stat? {
        var st = stat()
        return Darwin.lstat(path, &st) == 0 ? st : nil
    }

    static func isRegular(_ st: stat) -> Bool { (st.st_mode & S_IFMT) == S_IFREG }
    static func isDirectory(_ st: stat) -> Bool { (st.st_mode & S_IFMT) == S_IFDIR }

    /// `child` is `folder` or inside it (both canonical).
    static func isInside(_ child: String, _ folder: String) -> Bool {
        child == folder || child.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Creates a folder (and parents) with owner-only permissions.
    static func makePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

/// Failures inside the extension system. `UserFacingError` is used for anything a person sees.
enum ExtensionError: Error, Sendable, CustomStringConvertible {
    case io(String)
    case spawn(String)

    var description: String {
        switch self {
        case .io(let m), .spawn(let m): m
        }
    }
}
