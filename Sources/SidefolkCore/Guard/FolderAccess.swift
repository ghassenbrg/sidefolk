import Darwin
import Foundation

/// File-system boundaries: canonical paths, granted folders, and places tools never touch.
/// See docs/SECURITY.md T10.
public enum FolderAccess {
    /// The kernel's view of a path: `~` expanded, symlinks resolved with `realpath(3)` on the deepest
    /// existing ancestor (lstat semantics), the rest appended. Returns nil for relative paths, NUL,
    /// `.`/`..` components (never collapsed lexically: `link/../x` is not `x`), and dangling links.
    public static func canonical(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\0") else { return nil }
        let parts = expanded.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.contains(where: { $0 == "." || $0 == ".." }) { return nil }

        var existing = parts
        var tail: [String] = []
        var st = stat()
        while !existing.isEmpty, lstat("/" + existing.joined(separator: "/"), &st) != 0 {
            tail.insert(existing.removeLast(), at: 0)
        }
        let base = "/" + existing.joined(separator: "/")
        guard let resolved = realpath(base, nil) else { return nil } // dangling link or vanished
        defer { free(resolved) }
        var result = String(cString: resolved)
        for part in tail { result += (result.hasSuffix("/") ? "" : "/") + part }
        return result
    }

    public static func isInside(_ path: String, folder: String) -> Bool {
        guard let p = canonical(path), let f = canonical(folder) else { return false }
        return p == f || p.hasPrefix(f.hasSuffix("/") ? f : f + "/")
    }

    public static func allows(_ path: String, write: Bool, folders: [GrantedFolder]) -> Bool {
        folders.contains { f in (!write || f.access == .readwrite) && isInside(path, folder: f.path) }
    }

    private static var home: String { canonical(NSHomeDirectory()) ?? NSHomeDirectory() }

    /// Whole subtrees tools never touch, even inside a granted folder (SECURITY T10.2): the system,
    /// apps (bundles run code), every folder on the default PATH and the interpreters' libraries (a
    /// file planted there runs as the user, Sidefolk's own brain included), other users' homes and
    /// the system's private folders.
    static func protectedRoots(home: String) -> [String] {
        ["/System", "/Library", "/usr", "/bin", "/sbin", "/opt", "/Applications", "/cores", "/dev", "/private",
         home + "/Library", home + "/Applications", home + "/bin"]
    }

    /// Parts of `/private` that are ordinary scratch space (`/tmp` and per-user temporary folders).
    static let privateScratch = ["/private/tmp", "/private/var/folders"]

    /// Locations tools never touch, even inside a granted folder. The reason is worded for people.
    public static func forbiddenReason(_ paths: [String]) -> String? {
        let home = self.home
        let sidefolk = [SidefolkPaths.standard().home.path, ProcessInfo.processInfo.environment["SIDEFOLK_HOME"]]
            .compactMap { $0 }.compactMap { canonical($0) }
        for raw in paths {
            guard let p = canonical(raw) else {
                return String(localized: "That path isn't allowed (relative, “..”, or a broken link).")
            }
            if p == "/" { return String(localized: "Sidefolk doesn't work on the whole disk.") }
            let scratch = privateScratch.contains { p == $0 || p.hasPrefix($0 + "/") }
            for prefix in protectedRoots(home: home) + sidefolk where p == prefix || p.hasPrefix(prefix + "/") {
                if scratch, prefix == "/private" { continue }
                return String(localized: "Sidefolk doesn't touch \(displayPath(prefix)) — it's protected.")
            }
            // Other people's home folders (and /Users/Shared, which anyone on this Mac can write).
            if p.hasPrefix("/Users/"), p != home, !p.hasPrefix(home + "/") {
                return String(localized: "Sidefolk only works inside your own home folder.")
            }
            // Hidden files and folders (.ssh, .git, .env, .claude …) are off limits.
            if p.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                return String(localized: "Sidefolk doesn't touch hidden files or folders.")
            }
        }
        return nil
    }

    /// Folders that can never be granted as a whole (too broad): the disk, home itself, a whole
    /// volume, and the shared scratch roots.
    public static func isGrantable(_ folder: String) -> Bool {
        guard let f = canonical(folder) else { return false }
        let tooBroad = ["/", "/Users", "/Volumes", home] + privateScratch
        let parts = f.split(separator: "/")
        let volumeRoot = parts.count == 2 && parts[0] == "Volumes"
        return !tooBroad.contains(f) && !volumeRoot && forbiddenReason([f]) == nil
    }

    /// The folder to offer when a path is outside every grant: the path itself if it is a folder,
    /// otherwise its parent. Nil when that would be too broad to grant.
    public static func suggestedFolder(for path: String) -> String? {
        guard let p = canonical(path) else { return nil }
        var isDir: ObjCBool = false
        let base = FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
            ? p : (p as NSString).deletingLastPathComponent
        return isGrantable(base) ? base : nil
    }

    public static func displayPath(_ path: String) -> String {
        let home = self.home
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
