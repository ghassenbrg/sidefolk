import Foundation
import Synchronization

/// Whether a server's program can be checked, and what it was (D189). Only a compiled program is: its file is the program. A script, or a
/// launcher that fetches or interprets code each time it starts (`npx`, `uvx`, `node`, `python`, a shell, `docker`), is not, and the card says so
/// instead of showing a check it can't keep.
enum ProgramPin {
    private static let launchers: Set<String> = [
        "node", "nodejs", "npx", "npm", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "uv", "uvx", "pipx", "python", "python2", "python3", "ruby", "perl",
        "php", "java", "dotnet", "docker", "podman", "sh", "bash", "zsh", "dash", "fish", "env", "osascript", "swift", "go", "cargo", "dart", "npm-exec",
    ]
    private static let magic: Set<UInt32> = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]

    private struct Seen: Equatable {
        var modified: Date
        var size: Int
        var hash: String?
    }

    private static let cache = Mutex<[String: Seen]>([:])

    /// The program's hash now, or nil when it can't be checked: not a regular file, a launcher, a script, or a name with no path.
    static func hash(of command: String) -> String? {
        guard command.hasPrefix("/"), let real = ExtensionFS.realpath(command) else { return nil }
        let name = (real as NSString).lastPathComponent.lowercased()
        let stem = name.prefix { $0 != "." }
        if launchers.contains(String(stem)) || launchers.contains(name) || stem.hasPrefix("python") { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: real), attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date, let size = (attributes[.size] as? NSNumber)?.intValue else { return nil }
        if let known = cache.withLock({ $0[real] }), known.modified == modified, known.size == size { return known.hash }
        var hash: String?
        if let handle = FileHandle(forReadingAtPath: real), let head = try? handle.read(upToCount: 4), head.count == 4 {
            try? handle.close()
            let word = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if magic.contains(word) { hash = try? ExtensionHash.sha256(file: real) }
        }
        cache.withLock { $0[real] = Seen(modified: modified, size: size, hash: hash) }
        return hash
    }
}
