import Darwin
import Foundation

// Low-level file operations for the file tools (docs/SECURITY.md T10). Paths arrive already canonical from
// `FolderAccess`; here they are opened without following links, checked after opening, and moved without
// ever replacing anything.

/// One path as the file tools see it.
enum FilePaths {
    /// The path Guard should check for `scope(for:)`: canonical, or nil when it can't be used. A nil
    /// scope entry is safe because `resolve` refuses the same input when the tool runs.
    static func scopePath(_ raw: String?) -> String? {
        guard let raw = raw?.trimmedText, !raw.isEmpty else { return nil }
        return FolderAccess.canonical(raw)
    }

    /// The canonical path for a tool that is about to touch it. Throws a message people can act on.
    static func resolve(_ raw: String) throws -> String {
        let raw = raw.trimmedText
        guard !raw.isEmpty else { throw ToolError.invalidInput("a path is required.") }
        guard let path = FolderAccess.canonical(raw) else {
            throw UserFacingError("I need a full path that starts with / or ~, without “..” parts or broken links.")
        }
        if let reason = FolderAccess.forbiddenReason([path]) { throw UserFacingError(reason) }
        return path
    }

    static func lstatMode(_ path: String) -> mode_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mode & S_IFMT : nil
    }

    /// A regular file with more than one name may be the same file as one outside every shared folder
    /// (`ln ~/.ssh/id_rsa granted/notes.txt`): reading or moving it would reach that file, so the file
    /// tools leave it alone (SECURITY T10).
    static func refuseHardLink(_ st: stat, path: String) throws {
        guard st.st_mode & S_IFMT == S_IFREG, st.st_nlink > 1 else { return }
        throw UserFacingError("\(display(path)) is a hard link: the same file also has another name, possibly in a folder you haven't shared, so I won't open or move it.",
                              recovery: "If it's yours, copy it to a normal file first (for example with Finder's Duplicate).")
    }

    static func exists(_ path: String) -> Bool { lstatMode(path) != nil }
    static func isDirectory(_ path: String) -> Bool { lstatMode(path) == S_IFDIR }

    /// Whether the last component of what the user typed is itself a symbolic link. `canonical` follows
    /// links, so this looks at the unresolved path.
    static func isLink(_ raw: String) -> Bool {
        lstatMode((raw.trimmedText as NSString).expandingTildeInPath) == S_IFLNK
    }

    static func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func join(_ folder: String, _ name: String) -> String { folder == "/" ? "/" + name : folder + "/" + name }
    static func display(_ path: String) -> String { FolderAccess.displayPath(path) }

    /// Home itself and its direct children (Documents, Desktop …) are never moved, renamed or trashed.
    static func isHomeTopLevel(_ path: String) -> Bool {
        guard let home = FolderAccess.canonical(NSHomeDirectory()) else { return false }
        return path == home || parent(path) == home
    }

    /// File types that can run code when opened. Tools never create or rename into these.
    static let riskyExtensions: Set<String> = ["app", "command", "tool", "terminal", "webloc", "fileloc", "scpt", "workflow", "pkg", "mobileconfig"]

    static func isRisky(name: String) -> Bool { riskyExtensions.contains((name as NSString).pathExtension.lowercased()) }

    /// A single file or folder name: no separators, not hidden, not "." or "..", within the filesystem limit.
    static func validateName(_ name: String) throws -> String {
        let name = name.trimmedText
        guard !name.isEmpty else { throw ToolError.invalidInput("a name is required.") }
        guard !name.contains("/"), !name.contains("\0"), name != ".", name != "..",
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw UserFacingError("“\(name.clipped(60))” can't be used as a file name. It must be just a name, with no “/”.")
        }
        guard !name.hasPrefix(".") else { throw UserFacingError("Sidefolk doesn't create hidden files or folders (names starting with a dot).") }
        guard name.utf8.count <= 255 else { throw UserFacingError("That name is too long.") }
        return name
    }
}

struct DirectoryEntry: Sendable {
    var name: String
    var isDirectory: Bool
    var isLink: Bool
    var size: Int64
    var modified: Date
}

enum DirectoryReader {
    /// Lists a directory through an fd opened without following links; metadata comes from `fstatat`
    /// with no-follow, so a link in the folder is reported as a link, never as its target.
    static func entries(atPath path: String) throws -> [DirectoryEntry] {
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw FileFailure.make(errno, path: path, action: "open that folder") }
        guard let dir = fdopendir(fd) else {
            let code = errno
            close(fd)
            throw FileFailure.make(code, path: path, action: "open that folder")
        }
        defer { closedir(dir) }
        var found: [DirectoryEntry] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let type = st.st_mode & S_IFMT
            found.append(DirectoryEntry(
                name: name, isDirectory: type == S_IFDIR, isLink: type == S_IFLNK, size: Int64(st.st_size),
                modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))))
        }
        return found
    }
}

enum SafeFile {
    struct Contents {
        var data: Data
        var size: Int64
        /// More bytes exist than were read.
        var truncated: Bool
        var modified: Date
    }

    /// Reads up to `maxBytes` of a regular file. The file is opened without following any link, must be a
    /// regular file (no folders, pipes, devices or sockets) and must still be at the checked path.
    static func read(path: String, maxBytes: Int) throws -> Contents {
        let fd = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw FileFailure.make(errno, path: path, action: "open that file") }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else { throw FileFailure.make(errno, path: path, action: "read that file") }
        switch st.st_mode & S_IFMT {
        case S_IFREG: break
        case S_IFDIR: throw UserFacingError("That's a folder, not a file.", recovery: "Use files.list to see what's inside.")
        default: throw UserFacingError("That isn't an ordinary file, so I won't open it.")
        }
        try FilePaths.refuseHardLink(st, path: path)
        // The path must still lead to this very file (it could have been swapped after the check).
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if fcntl(fd, F_GETPATH, &buffer) == 0 {
            let actual = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            guard actual.lowercased() == path.lowercased() else {
                throw UserFacingError("That file changed while I was opening it, so I stopped.")
            }
        }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < maxBytes {
            let want = min(chunk.count, maxBytes - data.count)
            let n = Darwin.read(fd, &chunk, want)
            if n < 0 { throw FileFailure.make(errno, path: path, action: "read that file") }
            if n == 0 { break }
            data.append(contentsOf: chunk[0..<n])
        }
        let size = Int64(st.st_size)
        return Contents(data: data, size: size, truncated: Int64(data.count) < size,
                        modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)))
    }
}

enum FileFailure {
    static func make(_ code: Int32, path: String, action: String) -> UserFacingError {
        let shown = FilePaths.display(path)
        switch code {
        case ENOENT: return UserFacingError("I couldn't find \(shown).")
        case EACCES, EPERM:
            return UserFacingError("macOS didn't let me \(action) at \(shown).",
                                   recovery: "Check that Sidefolk has access to that folder in System Settings › Privacy & Security › Files and Folders.")
        case ELOOP: return UserFacingError("\(shown) goes through a link, so I won't follow it.")
        case ENOTDIR: return UserFacingError("\(shown) isn't a folder.")
        case ENOSPC: return UserFacingError("There's no space left to do that.")
        case EROFS: return UserFacingError("\(shown) is on a read-only disk.")
        default: return UserFacingError("I couldn't \(action) at \(shown).", detail: String(cString: strerror(code)))
        }
    }
}

enum FileMover {
    /// Moves `from` to `to` without replacing anything: fails with `EEXIST` when `to` exists, and with
    /// `ELOOP` when any folder on either path was swapped for a link after Guard checked it.
    static func moveExclusive(from: String, to: String) throws {
        if renamex_np(from, to, UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)) == 0 { return }
        let code = errno
        guard code == EXDEV else { throw MoveError.errno(code) }
        // Different volume: rename can't cross it, so copy and remove through FileManager, which refuses to overwrite.
        guard !FilePaths.exists(to) else { throw MoveError.errno(EEXIST) }
        do { try FileManager.default.moveItem(atPath: from, toPath: to) } catch { throw MoveError.errno(EIO) }
    }

    /// Moves `from` into `folder` under `name`, or `name 2`, `name 3` … when that is taken. Returns the final path.
    static func moveToFreeName(from: String, folder: String, name: String) throws -> String {
        for candidate in FileNames.candidates(for: name, limit: 99) {
            let target = FilePaths.join(folder, candidate)
            do {
                try moveExclusive(from: from, to: target)
                return target
            } catch MoveError.errno(let code) where code == EEXIST {
                continue
            }
        }
        throw UserFacingError("There are too many files called “\(name.clipped(60))” in that folder already.")
    }

    enum MoveError: Error { case errno(Int32) }
}

enum FileNames {
    /// "report.pdf", "report 2.pdf", "report 3.pdf" … ("archive.tar.gz" keeps its double extension).
    static func candidates(for name: String, limit: Int) -> [String] {
        var base = name
        var ext = ""
        let ns = name as NSString
        if !ns.pathExtension.isEmpty, ns.deletingPathExtension != "" {
            ext = "." + ns.pathExtension
            base = ns.deletingPathExtension
            if (base as NSString).pathExtension.lowercased() == "tar" {
                ext = "." + (base as NSString).pathExtension + ext
                base = (base as NSString).deletingPathExtension
            }
        }
        return [name] + (2...max(2, limit)).map { "\(base) \($0)\(ext)" }
    }
}
