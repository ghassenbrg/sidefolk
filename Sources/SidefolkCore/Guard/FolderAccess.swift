import Foundation

/// File-system boundaries: canonical paths, granted folders, and places tools never touch.
public enum FolderAccess {
    /// Expands `~`, makes absolute, resolves `..` and symlinks (of the deepest existing ancestor).
    public static func canonical(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var url = URL(fileURLWithPath: expanded).standardizedFileURL
        // Resolve symlinks on the part that exists so a link cannot smuggle a path out of a granted folder.
        var suffix: [String] = []
        let fm = FileManager.default
        while !fm.fileExists(atPath: url.path), url.path != "/" {
            suffix.insert(url.lastPathComponent, at: 0)
            url = url.deletingLastPathComponent()
        }
        var resolved = url.resolvingSymlinksInPath()
        for part in suffix { resolved.appendPathComponent(part) }
        var result = resolved.standardizedFileURL.path
        if result.hasPrefix("/private/var/") || result.hasPrefix("/private/tmp/") {
            // Keep the /private form; both spellings canonicalise the same way below.
            result = String(result)
        }
        return result
    }

    public static func isInside(_ path: String, folder: String) -> Bool {
        let p = canonical(path)
        let f = canonical(folder)
        return p == f || p.hasPrefix(f.hasSuffix("/") ? f : f + "/")
    }

    public static func allows(_ path: String, write: Bool, folders: [GrantedFolder]) -> Bool {
        folders.contains { f in
            (!write || f.access == .readwrite) && isInside(path, folder: f.path)
        }
    }

    /// Locations no tool may touch regardless of grants.
    public static func forbiddenReason(_ paths: [String]) -> String? {
        let home = NSHomeDirectory()
        let forbiddenPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/etc", "/Library",
                                 home + "/Library/Keychains", home + "/.ssh", home + "/.gnupg", home + "/.aws",
                                 home + "/Library/Application Support/Sidefolk"]
        for raw in paths {
            let p = canonical(raw)
            if p == "/" { return "Sidefolk doesn't work on the whole disk." }
            for prefix in forbiddenPrefixes where p == prefix || p.hasPrefix(prefix + "/") {
                return "Sidefolk doesn't touch \(displayPath(prefix)) — it's protected."
            }
        }
        return nil
    }

    /// The folder to offer when a path is outside every grant: the path itself if it is a folder,
    /// otherwise its parent, never broader than a direct child of the home folder.
    public static func suggestedFolder(for path: String) -> String {
        let p = canonical(path)
        var isDir: ObjCBool = false
        let base = FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
            ? p : (p as NSString).deletingLastPathComponent
        return base == NSHomeDirectory() ? p : base
    }

    public static func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
