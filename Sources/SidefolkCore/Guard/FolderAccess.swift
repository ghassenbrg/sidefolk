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
    /// With `hiddenFine`, a hidden place alone doesn't refuse it: for a call that reads no more than a file's size and time.
    public static func forbiddenReason(_ paths: [String], hiddenFine: Bool = false) -> String? {
        let home = self.home
        let sidefolk = [SidefolkPaths.standard().home.path, ProcessInfo.processInfo.environment["SIDEFOLK_HOME"]]
            .compactMap { $0 }.compactMap { canonical($0) }
        for raw in paths {
            // As named too, before anything looks at where it leads: a link in `~/Library`, in an extension's own data folder say, is still in `~/Library`, and asking
            // about it there would tell a sandbox what's at the other end. The same for a link taking `~/.config` somewhere that doesn't look like one.
            let named = (raw as NSString).expandingTildeInPath
            if hiddenFine, isSecretStore(named) {
                return String(localized: "Sidefolk doesn't touch hidden files or folders.")
            }
            // Case-blind, as the volume is: `~/LIBRARY` is `~/Library`.
            let spelled = named.lowercased()
            for prefix in protectedRoots(home: NSHomeDirectory()) + sidefolk where spelled == prefix.lowercased() || spelled.hasPrefix(prefix.lowercased() + "/") {
                if prefix == "/private", privateScratch.contains(where: { spelled == $0 || spelled.hasPrefix($0 + "/") }) { continue }
                return String(localized: "Sidefolk doesn't touch \(displayPath(prefix)) — it's protected.")
            }
            guard let p = canonical(raw) else {
                return String(localized: "That path isn't allowed (relative, “..”, or a broken link).")
            }
            if p == "/" { return String(localized: "Sidefolk doesn't work on the whole disk.") }
            let scratch = privateScratch.contains { p == $0 || p.hasPrefix($0 + "/") }
            // Compared without case: on a Mac's usual volume `~/BIN` is `~/bin`, and a protected place that doesn't exist yet can be made in
            // another spelling (D185).
            let folded = p.lowercased()
            for prefix in protectedRoots(home: home) + sidefolk where folded == prefix.lowercased() || folded.hasPrefix(prefix.lowercased() + "/") {
                if scratch, prefix == "/private" { continue }
                return String(localized: "Sidefolk doesn't touch \(displayPath(prefix)) — it's protected.")
            }
            // Other people's home folders (and /Users/Shared, which anyone on this Mac can write).
            if p.hasPrefix("/Users/"), p != home, !p.hasPrefix(home + "/") {
                return String(localized: "Sidefolk only works inside your own home folder.")
            }
            // Hidden files and folders (.ssh, .git, .env, .claude …) are off limits.
            if !hiddenFine || isSecretStore(p), isHidden(p) {
                return String(localized: "Sidefolk doesn't touch hidden files or folders.")
            }
        }
        return nil
    }

    /// Whether the path as written has a hidden part: what's asked about before anything looks at the disk. What it really is, is `prepare`'s and `isHidden`'s to find.
    public static func isNamedHidden(_ path: String) -> Bool {
        (path as NSString).expandingTildeInPath.split(separator: "/").contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
    }

    /// Whether anything on the way to this path is a link, from below the home folder or the scratch folder it's in. Looks at each with `lstat`, so a link is seen as one.
    public static func hasLink(onTheWayTo path: String) -> Bool {
        let named = (path as NSString).expandingTildeInPath
        let bases = [NSHomeDirectory(), NSTemporaryDirectory(), "/private/tmp", "/tmp"].map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        let base = bases.first { named.hasPrefix($0 + "/") } ?? ""
        let parts = named.dropFirst(base.count).split(separator: "/").map(String.init)
        var st = stat()
        for end in parts.indices where lstat(base + "/" + parts[...end].joined(separator: "/"), &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK { return true }
        return false
    }

    /// Whether the path has a hidden file or folder in it (.ssh, .git, .env, .claude …).
    public static func isHidden(_ path: String) -> Bool {
        (canonical(path) ?? path).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Where keys and agents' settings live: not even a file's size and time. A second wall, not the first: a card still asks about any other hidden file.
    private static let secretStores = [".ssh", ".gnupg", ".aws", ".kube", ".docker", ".config", ".local", ".claude", ".codex"]

    /// Whatever the spelling, wherever it is: most Mac volumes ignore case, a store that isn't there yet has no spelling to find, and a backup's `.ssh` is still keys.
    private static func isSecretStore(_ path: String) -> Bool {
        path.lowercased().split(separator: "/").contains { secretStores.contains(String($0)) }
    }

    /// The path a refused call would need shared, as the call named it, when that's all that's in its way and sharing could help. Says nothing of what's on disk beyond
    /// what the refusal does: a page asks with this path, and Sidefolk works out the folder only on the person's click.
    public static func sharingNeeded(read: [String], write: [String], folders: [GrantedFolder]) -> (path: String, write: Bool)? {
        guard forbiddenReason(read + write) == nil else { return nil }
        // Whether sharing could help, from the path as named: asking the disk whether it's a folder would tell a sandbox what's there.
        func shareable(_ path: String) -> Bool { isGrantable(path) || isGrantable((path as NSString).deletingLastPathComponent) }
        if let path = write.first(where: { !allows($0, write: true, folders: folders) }) { return shareable(path) ? (path, true) : nil }
        if let path = read.first(where: { !allows($0, write: false, folders: folders) }) { return shareable(path) ? (path, false) : nil }
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

    /// Where Full access works without a folder being shared (D185): strictly inside the person's own home, once symlinks are
    /// resolved, and not in any place `forbiddenReason` names. The home folder itself is not (that is "too broad" for a
    /// share, and for this): what is in it is. Other volumes, other users' homes, `~/Library`, hidden files, Sidefolk's own data
    /// and everything outside the home never qualify, so a link out of the home doesn't either.
    public static func isOpenToFullAccess(_ path: String) -> Bool {
        guard let p = canonical(path), p.hasPrefix(home + "/"), forbiddenReason([p]) == nil else { return false }
        return true
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

    /// A path as people read it: `~` for home, and any character that is hidden or turns the text around written out (`hiddenShown`), so a card or a row can't
    /// show one name for another.
    public static func displayPath(_ path: String) -> String {
        let home = self.home
        if path == home { return "~" }
        return (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path).hiddenShown
    }
}
