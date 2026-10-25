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

    /// Locations tools never touch, even inside a granted folder.
    public static func forbiddenReason(_ paths: [String]) -> String? {
        let home = self.home
        let roots = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db", "/private/var/root", "/private/var/log", "/Library", "/dev",
                     home + "/Library"]
        let sidefolk = [SidefolkPaths.standard().home.path, ProcessInfo.processInfo.environment["SIDEFOLK_HOME"]]
            .compactMap { $0 }.compactMap { canonical($0) }
        for raw in paths {
            guard let p = canonical(raw) else {
                return "That path isn't allowed (relative, “..”, or a broken link)."
            }
            if p == "/" { return "Sidefolk doesn't work on the whole disk." }
            for prefix in roots + sidefolk where p == prefix || p.hasPrefix(prefix + "/") {
                return "Sidefolk doesn't touch \(displayPath(prefix)) — it's protected."
            }
            // Hidden files and folders (.ssh, .git, .env, .claude …) are off limits.
            if p.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                return "Sidefolk doesn't touch hidden files or folders."
            }
        }
        return nil
    }

    /// Folders that can never be granted as a whole (too broad).
    public static func isGrantable(_ folder: String) -> Bool {
        guard let f = canonical(folder) else { return false }
        let tooBroad = ["/", "/Users", "/Applications", "/Volumes", "/private", "/System", "/Library", home]
        return !tooBroad.contains(f) && forbiddenReason([f]) == nil
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
