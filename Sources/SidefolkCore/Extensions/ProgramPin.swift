import Foundation
import Synchronization

/// Whether a server's program can be checked, and what it was (D189). Only a compiled program is: its file is the program. A script, or a
/// launcher that fetches or interprets code each time it starts (`npx`, `uvx`, `node`, `python`, a shell, `docker`), is not, and the card says so
/// instead of showing a check it can't keep.
enum ProgramPin {
    private static let launchers: Set<String> = [
        "csh", "tcsh", "ksh", "lua", "awk", "gawk", "rscript", "julia", "pwsh", "xcrun", "arch", "sudo", "nohup", "expect", "tclsh", "groovy", "kotlin",
        "node", "nodejs", "npx", "npm", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "uv", "uvx", "pipx", "python", "python2", "python3", "ruby", "perl",
        "php", "java", "dotnet", "docker", "podman", "sh", "bash", "zsh", "dash", "fish", "env", "osascript", "swift", "go", "cargo", "dart", "npm-exec",
    ]
    private static let magic: Set<UInt32> = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]

    private struct Seen: Equatable {
        var modified: Date
        var changed: Date
        var size: Int
        var inode: Int
        var hash: String?
    }

    private static let cache = Mutex<[String: Seen]>([:])

    /// The program's hash now, or nil when it can't be checked: not a regular file, a launcher or interpreter (any version of one), a script, a program
    /// started with a file or folder it loads, or a name with no path. It is the main executable only: what that loads or fetches isn't covered, and the
    /// card doesn't say it is.
    static func hash(of command: String, arguments: [String] = []) -> String? {
        guard command.hasPrefix("/"), let real = ExtensionFS.realpath(command) else { return nil }
        // An argument that names something on this Mac is something the program loads (a script, a config, a folder): the hash would say less than it seems.
        for argument in arguments where !argument.hasPrefix("-") && FileManager.default.fileExists(atPath: (argument as NSString).expandingTildeInPath) { return nil }
        let name = (real as NSString).lastPathComponent.lowercased()
        // Versioned names too: `ruby3.2`, `node20`, `python3.11`.
        let stem = String(name.prefix { $0.isLetter || $0 == "-" || $0 == "_" })
        if launchers.contains(name) || launchers.contains(stem) || stem.hasPrefix("python") { return nil }
        var info = stat()
        guard stat(real, &info) == 0, (info.st_mode & UInt16(S_IFMT)) == UInt16(S_IFREG) else { return nil }
        let seen = Seen(modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9),
                        changed: Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9),
                        size: Int(info.st_size), inode: Int(info.st_ino), hash: nil)
        // The change time can't be set from outside the kernel, so a swap that keeps the size and the modified time still shows.
        if let known = cache.withLock({ $0[real] }), known.modified == seen.modified, known.changed == seen.changed, known.size == seen.size, known.inode == seen.inode {
            return known.hash
        }
        var hash: String?
        if let handle = FileHandle(forReadingAtPath: real), let head = try? handle.read(upToCount: 4), head.count == 4 {
            try? handle.close()
            let word = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if magic.contains(word) { hash = try? ExtensionHash.sha256(file: real) }
        }
        var stored = seen
        stored.hash = hash
        cache.withLock { $0[real] = stored }
        return hash
    }
}
