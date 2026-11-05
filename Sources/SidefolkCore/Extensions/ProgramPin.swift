import Foundation
import Synchronization

/// Whether a server's program can be checked, and what it was (D189). Only a compiled program is: its file is the program. A script, or a
/// launcher that fetches or interprets code each time it starts (`npx`, `uvx`, `node`, `python`, a shell, `docker`), is not, and the card says so
/// instead of showing a check it can't keep.
enum ProgramPin {
    private static let launchers: Set<String> = [
        "time", "nice", "caffeinate", "xargs", "ssh", "script", "sandbox-exec", "volta", "mise", "asdf", "jruby", "luajit", "sbcl", "racket", "elixir", "erl", "tsx", "ts-node", "csh", "tcsh", "ksh", "lua", "awk", "gawk", "rscript", "julia", "pwsh", "xcrun", "arch", "sudo", "nohup", "expect", "tclsh", "groovy", "kotlin",
        "make", "gmake", "just", "task", "rake", "bundle", "bundler", "poetry", "nix", "nix-shell", "timeout", "gtimeout", "gradle", "gradlew", "mvn", "mvnw", "pip", "pip3", "cmake", "ninja", "scons", "tox", "nox", "pdm", "hatch", "pipenv", "conda", "mamba", "composer", "gem", "sbt", "lein", "stack", "cabal", "opam", "dune", "mix", "rebar3", "devbox", "direnv", "watchexec", "entr", "tmux", "screen", "find", "exec", "command", "builtin", "busybox",
        "node", "nodejs", "npx", "npm", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "uv", "uvx", "pipx", "python", "python2", "python3", "ruby", "perl",
        "php", "java", "dotnet", "docker", "podman", "sh", "bash", "zsh", "dash", "fish", "env", "osascript", "swift", "go", "cargo", "dart", "npm-exec",
    ]
    private static let systemFolders = ["/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/usr/libexec/", "/System/", "/Library/Developer/", "/Applications/Xcode"]
    private static let magic: Set<UInt32> = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]

    private struct Seen: Equatable {
        var modified: Date
        var changed: Date
        var size: Int
        var inode: Int
        var hash: String?
    }

    private static let cache = Mutex<[String: Seen]>([:])

    /// Why a program can't be checked, in the card's terms.
    enum Unchecked: String {
        /// Not a full path: which program runs is the search path's word.
        case path
        /// A launcher, interpreter, build tool or shell: the code it starts is what runs, and it is not the file.
        case launcher
        /// Started with a file or folder it loads.
        case loads
        /// Not a compiled program.
        case script
    }

    /// The program's hash now, or nil when it can't be checked: not a regular file, a launcher or interpreter (any version of one), a script, a program
    /// started with a file or folder it loads, or a name with no path. It is the main executable only: what that loads or fetches isn't covered, and the
    /// card doesn't say it is. The launcher list is a closed guess: a compiled build tool or runner not on it would be pinned by its own hash.
    static func hash(of command: String, arguments: [String] = []) -> String? {
        if case .pinned(let hash) = check(of: command, arguments: arguments) { return hash }
        return nil
    }

    enum Result: Equatable {
        case pinned(String)
        case unchecked(Unchecked)
    }

    static func check(of command: String, arguments: [String] = []) -> Result {
        guard command.hasPrefix("/"), let real = ExtensionFS.realpath(command) else { return .unchecked(.path) }
        let name = (real as NSString).lastPathComponent.lowercased()
        // Versioned names too: `ruby3.2`, `node20`, `python3.11`.
        let stem = String(name.prefix { $0.isLetter || $0 == "-" || $0 == "_" })
        if launchers.contains(name) || launchers.contains(stem) || stem.hasPrefix("python") || stem.hasPrefix("pypy") { return .unchecked(.launcher) }
        // The Mac's own command-line tools (`make`, `git`, `xargs`) run what they are given, and what they are given is not in the hash.
        if systemFolders.contains(where: { real.hasPrefix($0) }) { return .unchecked(.launcher) }
        // An argument that names something on this Mac is something the program loads (a script, a config, a folder): the hash would say less than it seems.
        // `--config=/path` too, and any argument with a slash in it, since where it points is not Sidefolk's to know.
        for argument in arguments {
            let value = argument.split(separator: "=", maxSplits: 1).last.map(String.init) ?? argument
            if argument.contains("/") || value.contains("/") || argument.hasPrefix("~") || FileManager.default.fileExists(atPath: (value as NSString).expandingTildeInPath) { return .unchecked(.loads) }
            // A bare name that looks like a file (`server.tcl`, `config.json`) is one the server may find in its own folder, which isn't where Sidefolk looks.
            if value.range(of: #"\.[A-Za-z][A-Za-z0-9]{0,5}\z"#, options: .regularExpression) != nil { return .unchecked(.loads) }
        }
        var info = stat()
        guard stat(real, &info) == 0, (info.st_mode & UInt16(S_IFMT)) == UInt16(S_IFREG) else { return .unchecked(.script) }
        let seen = Seen(modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9),
                        changed: Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9),
                        size: Int(info.st_size), inode: Int(info.st_ino), hash: nil)
        // The change time can't be set from outside the kernel, so a swap that keeps the size and the modified time still shows.
        if let known = cache.withLock({ $0[real] }), known.modified == seen.modified, known.changed == seen.changed, known.size == seen.size, known.inode == seen.inode {
            return known.hash.map(Result.pinned) ?? .unchecked(.script)
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
        return hash.map(Result.pinned) ?? .unchecked(.script)
    }
}
