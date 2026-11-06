import CryptoKit
import Darwin
import Foundation

/// Text that comes from an extension is untrusted: invisible and bidi characters are stripped and
/// lengths are capped before anything shows it to the model or the user (SECURITY T2, T17).
enum ExtensionText {
    /// Removes zero-width, bidi-control (the Arabic letter mark too), tag and control characters (newline and tab survive).
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars where !isHidden(s) { scalars.append(s) }
        return String(scalars)
    }

    static func isHidden(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09, 0x0A: false
        case 0x00...0x1F, 0x7F...0x9F: true
        case 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: true
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

    /// One cleaned line (titles, summaries) of at most `characters` characters; with `isolates`, words people read
    /// on a page or a board keep the Kit's isolates (`shown`).
    static func line(_ text: String, characters: Int, isolates: Bool = false) -> String {
        let cleaned = isolates ? shown(text) : clean(text)
        // Every kind of line break, so a title can't start a paragraph on a card.
        let flat = cleaned.unicodeScalars.map { ["\n", "\t", "\u{2028}", "\u{2029}", "\u{85}", "\r"].contains($0) ? " " : String($0) }.joined()
        return clip(flat, characters)
    }

    /// Text shown to people, never passed on: hidden characters removed, except first-strong isolates (FSI … PDI) that
    /// pair up. The Kit's `L` puts one around each value it fills in, so a name or a number keeps its own direction in
    /// a sentence of the other (an Arabic sentence that begins with "Mochi" still reads right to left). An isolate
    /// can't reorder what is inside it, and an unpaired one is dropped, so it can't reach past its value (D76 amended,
    /// T13). Everything else that reorders text (overrides, embeddings, LRI, RLI, marks) is still removed.
    static func shown(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        var keep = scalars.map { !isHidden($0) }
        var open: [Int] = []
        for (i, s) in scalars.enumerated() {
            if s == fsi { open.append(i) }
            if s == pdi, let start = open.popLast() { (keep[start], keep[i]) = (true, true) }
        }
        scalars = scalars.indices.filter { keep[$0] }.map { scalars[$0] }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }

    private static let fsi: Unicode.Scalar = "\u{2068}", pdi: Unicode.Scalar = "\u{2069}"

    /// `clipped`, counting only what shows: a value's isolates don't use up the room. A line too long loses them with
    /// its end, so none is left open.
    static func clip(_ text: String, _ characters: Int) -> String {
        let t = withoutStacks(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let isolate = { (c: Character) in c == Character(fsi) || c == Character(pdi) }
        guard t.count - t.filter(isolate).count > characters else { return t }
        return t.filter { !isolate($0) }.clipped(characters)
    }

    /// The most marks one character keeps. Every language's real text fits, and a cap counted in characters then also
    /// bounds bytes: one letter under 500,000 combining marks is one `Character` and a megabyte.
    static let marksPerCharacter = 8

    /// Takes off what a character carries past `marksPerCharacter`.
    static func withoutStacks(_ text: String) -> String {
        guard text.utf8.count > text.count * 4 else { return text }
        var out = String.UnicodeScalarView()
        var run = 0
        for s in text.unicodeScalars {
            run = s.properties.isGraphemeExtend ? run + 1 : 0
            if run <= marksPerCharacter { out.append(s) }
        }
        return String(out)
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
