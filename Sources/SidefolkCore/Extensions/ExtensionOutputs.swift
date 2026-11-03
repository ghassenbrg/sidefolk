import Darwin
import Foundation

/// What a program asks Sidefolk to save (D140): a file in its own data folder, the name it should have, and the file the
/// person handed over that it belongs beside.
public struct ExtensionOutput: Sendable, Hashable {
    public var data: String
    public var name: String
    public var source: String

    public init(data: String, name: String, source: String) {
        self.data = data
        self.name = name
        self.source = source
    }

    /// `outputs` in a reply's `sidefolk`, read strictly: an entry that isn't three strings is left out.
    static func list(_ asked: JSONValue?) -> [ExtensionOutput] {
        (asked?["outputs"]?.arrayValue ?? []).compactMap { one in
            guard let data = one["data"]?.stringValue, let name = one["name"]?.stringValue, let source = one["source"]?.stringValue else { return nil }
            return ExtensionOutput(data: data, name: name, source: source)
        }
    }
}

/// A file Sidefolk placed for an extension. Identity, size and time let a later step tell this is still that file.
public struct PlacedFile: Sendable, Hashable {
    public var path: String
    public var source: String
    public var device: Int32
    public var inode: UInt64
    public var size: Int64
    public var modified: Date

    public init(path: String, source: String, device: Int32, inode: UInt64, size: Int64, modified: Date) {
        self.path = path
        self.source = source
        self.device = device
        self.inode = inode
        self.size = size
        self.modified = modified
    }
}

/// What came of a call's outputs.
public struct ExtensionPlacement: Sendable {
    public var placed: [PlacedFile] = []
    public var problems: [String] = []
}

extension ToolResult {
    mutating func take(_ placement: ExtensionPlacement) {
        placing = nil
        placed = placement.placed
        if !placement.problems.isEmpty {
            let words = String(localized: "Not saved:") + " " + placement.problems.joined(separator: "; ")
            text += "\n" + words
            card?.detail = words.clipped(200)
            isError = placement.placed.isEmpty
        }
        if let first = placement.placed.first {
            rowOutcome = placement.placed.count == 1 ? first.path
                : String(localized: "\(placement.placed.count) files beside \((first.source as NSString).lastPathComponent)")
        }
    }
}

/// How an extension's result reaches the person's folder without the sandbox ever opening it (D140, SECURITY T45). The program
/// writes in its data folder; Sidefolk, with its own privileges, copies it beside a file the person handed over in the same
/// call. So everything here treats the data folder as hostile: the main risk is being tricked into reading something else.
public enum ExtensionOutputs {
    public static let maxFiles = 64
    public static let maxBytes: Int64 = 32 * 1024 * 1024 * 1024
    /// All of a call's files together: a program can make huge empty files for nothing.
    public static let maxBytesPerCall: Int64 = 64 * 1024 * 1024 * 1024
    static let maxNameBytes = 200

    /// The only endings an output may have, whatever a manifest declares: files that hold content, none that run.
    public static let allowedEndings: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "avif", "tif", "tiff", "gif", "bmp", "ico", "icns", "webp", "jp2", "psd", "tga",
        "pdf", "txt", "md", "rtf", "csv", "tsv", "json", "jsonl", "yaml", "yml", "toml", "xml", "plist",
        "srt", "vtt", "ass", "docx", "xlsx", "pptx", "epub",
        "mp3", "m4a", "aac", "flac", "opus", "ogg", "wav", "aif", "aiff", "caf", "mp4", "m4v", "mov", "webm", "mkv",
        "zip", "7z", "tar", "gz", "tgz", "bz2", "xz",
    ]

    /// Why this name can't be used, or nil. Only a bare name: no folder in it, nothing hidden, nothing that reverses or hides
    /// its letters, and an ending the extension declared.
    public static func refusal(name: String, endings: Set<String>) -> String? {
        let plain = String(localized: "Its name isn't a plain file name.")
        guard !name.isEmpty, name.utf8.count <= maxNameBytes, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return plain }
        let hidden = name.unicodeScalars.contains {
            [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) || $0.properties.isDefaultIgnorableCodePoint
        }
        let readable = (name as NSString).deletingPathExtension.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
        guard !hidden, readable else { return plain }
        let ending = (name as NSString).pathExtension.lowercased()
        guard !ending.isEmpty, allowedEndings.contains(ending), endings.contains(ending) else {
            return String(localized: "This extension can't save files of that kind.")
        }
        return nil
    }

    /// Whether a name shows it comes from its source: "trip.jpg" or "trip small.jpg" beside "trip.heic". Without this, a program
    /// could plant a file the folder's other programs read by name, like `CLAUDE.md` or `package.json` in a project.
    static func follows(name: String, source: String) -> Bool {
        func plain(_ text: String) -> String { (text as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping.lowercased() }
        let made = plain(name), from = plain((source as NSString).lastPathComponent)
        guard made.hasPrefix(from) else { return false }
        // A whole word: "c.png" doesn't vouch for "CLAUDE.md".
        return made.count == from.count || [" ", "."].contains(made.dropFirst(from.count).first)
    }

    /// Everything a call asked for, stopping between files if the person stopped it.
    public static func placeAll(_ outputs: [ExtensionOutput], dataFolder: String, handedOver: Set<String>, endings: Set<String>,
                                maxBytesPerCall: Int64 = maxBytesPerCall) async -> ExtensionPlacement {
        var result = ExtensionPlacement(), left = maxBytesPerCall
        for output in outputs.prefix(maxFiles) {
            if Task.isCancelled {
                result.problems.append(String(localized: "Stopped before saving the rest."))
                break
            }
            do {
                let placed = try place(output, dataFolder: dataFolder, handedOver: handedOver, endings: endings, maxBytes: min(maxBytes, left))
                left -= placed.size
                result.placed.append(placed)
            } catch {
                let why = (error as? UserFacingError)?.message ?? String(localized: "It couldn't be saved.")
                result.problems.append(ExtensionText.untrusted(output.name, bytes: 200) + ": " + why)
            }
        }
        if outputs.count > maxFiles { result.problems.append(String(localized: "Only the first \(maxFiles) files were saved.")) }
        return result
    }

    /// Copies one output beside its source and removes it from the data folder. Never overwrites: a name in use gets a number.
    /// - Parameters:
    ///   - dataFolder: the extension's data folder, already canonical.
    ///   - handedOver: what the person dropped or picked for this very call, canonical. Nothing else may be a source.
    public static func place(_ output: ExtensionOutput, dataFolder: String, handedOver: Set<String>, endings: Set<String>,
                             maxBytes: Int64 = maxBytes, now: Date = Date()) throws -> PlacedFile {
        if let why = refusal(name: output.name, endings: endings) { throw UserFacingError(verbatim: why, changedNothing: true) }
        guard let source = FolderAccess.canonical(output.source), handedOver.contains(source) else {
            throw UserFacingError("It can only save beside a file you gave it for this request.", changedNothing: true)
        }
        guard follows(name: output.name, source: source) else {
            throw UserFacingError("Its name has to start with the name of the file it came from.", changedNothing: true)
        }
        var info = stat()
        guard lstat(source, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw UserFacingError("The file it belongs beside is gone.", changedNothing: true)
        }
        let opened = try open(relative: output.data, in: dataFolder)
        defer { close(opened.file); close(opened.parent) }
        var file = stat()
        guard fstat(opened.file, &file) == 0, file.st_mode & S_IFMT == S_IFREG, file.st_nlink == 1 else {
            throw UserFacingError("It didn't make a plain file.", changedNothing: true)
        }
        guard file.st_size <= maxBytes else { throw UserFacingError("The file it made is too large to save.", changedNothing: true) }

        // The folder is held open from here on and everything is done through that handle, never its path again: a program able
        // to write above it could swap it for a link between a check and a use. Opening follows no link at any level.
        let folder = try hold((source as NSString).deletingLastPathComponent)
        defer { close(folder.handle) }
        var there = stat(), space = statfs()
        if fstat(folder.handle, &there) == 0, there.st_dev != file.st_dev, fstatfs(folder.handle, &space) == 0,
           Int64(space.f_bavail) * Int64(space.f_bsize) < file.st_size {
            throw UserFacingError("There isn't room to save it.", changedNothing: true)
        }

        let holding = ".sidefolk-placing-" + UUID().uuidString
        defer { unlinkat(folder.handle, holding, 0) }
        try copy(opened.file, size: file.st_size, to: holding, in: folder.handle)
        try finish(holding, in: folder.handle, maxBytes: maxBytes, now: now)
        let name = try moveIntoPlace(holding, name: output.name, in: folder.handle)

        var placed = stat()
        guard fstatat(folder.handle, name, &placed, AT_SYMLINK_NOFOLLOW) == 0 else { throw UserFacingError("It couldn't be saved.") }
        // Best effort: the file is saved either way, and a program that kept its copy only keeps its own file.
        unlinkat(opened.parent, opened.last, 0)
        return PlacedFile(path: folder.path + "/" + name, source: source, device: placed.st_dev, inode: placed.st_ino, size: placed.st_size,
                          modified: Date(timeIntervalSince1970: TimeInterval(placed.st_mtimespec.tv_sec) + TimeInterval(placed.st_mtimespec.tv_nsec) / 1e9))
    }

    /// Opens the folder and asks the system where it really is, so the rules are judged on what is actually held.
    private static func hold(_ path: String) throws -> (handle: Int32, path: String) {
        let handle = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard handle >= 0 else { throw UserFacingError("It couldn't be saved in that folder.", changedNothing: true) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(handle, F_GETPATH, &buffer) == 0 else {
            close(handle)
            throw UserFacingError("It couldn't be saved in that folder.", changedNothing: true)
        }
        let real = String(cString: buffer)
        if let why = FolderAccess.forbiddenReason([real]) {
            close(handle)
            throw UserFacingError(verbatim: why, changedNothing: true)
        }
        return (handle, real)
    }

    /// Walks down from the data folder one name at a time, following no link anywhere, so nothing a program did to the folder
    /// can lead outside it, even while this runs.
    private static func open(relative: String, in dataFolder: String) throws -> (file: Int32, parent: Int32, last: String) {
        let refused = UserFacingError("It didn't make a plain file.", changedNothing: true)
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relative.hasPrefix("/"), !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\0") }), let last = parts.last else { throw refused }
        var parent = Darwin.open(dataFolder, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw refused }
        for part in parts.dropLast() {
            let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(parent)
            guard next >= 0 else { throw refused }
            parent = next
        }
        let file = openat(parent, last, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else {
            close(parent)
            throw refused
        }
        return (file, parent, last)
    }

    /// A clone where the disk allows it (no extra space, instant), otherwise a copy.
    private static func copy(_ file: Int32, size: Int64, to name: String, in folder: Int32) throws {
        if fclonefileat(file, folder, name, UInt32(CLONE_NOFOLLOW) | UInt32(CLONE_NOOWNERCOPY)) == 0 { return }
        let out = openat(folder, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard out >= 0 else { throw UserFacingError("It couldn't be saved in that folder.", changedNothing: true) }
        defer { close(out) }
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024), left = size
        while left > 0 {
            let count = read(file, &buffer, min(buffer.count, Int(clamping: left)))
            if count == 0 { return }
            guard count > 0 else { throw UserFacingError("It couldn't be saved.") }
            var written = 0
            while written < count {
                let step = buffer[written..<count].withUnsafeBytes { write(out, $0.baseAddress, $0.count) }
                guard step > 0 else { throw UserFacingError("There isn't room to save it.") }
                written += step
            }
            left -= Int64(count)
        }
    }

    /// What a saved file carries: plain permissions and today's dates, none of the program's flags or attributes, and macOS's mark
    /// of a downloaded file, so opening it gets the same care as anything else from outside. A clone takes the file as it is now,
    /// which a second copy of the program may have grown since it was measured, so it is measured again.
    private static func finish(_ name: String, in folder: Int32, maxBytes: Int64, now: Date) throws {
        let failed = UserFacingError("It couldn't be saved.")
        let fd = openat(folder, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failed }
        defer { close(fd) }
        var made = stat()
        guard fstat(fd, &made) == 0 else { throw failed }
        guard made.st_size <= maxBytes else { throw UserFacingError("The file it made is too large to save.", changedNothing: true) }
        // Only a disk's own compression stays: an immutable flag would strand it, a hidden one hide it.
        guard fchflags(fd, made.st_flags & UInt32(UF_COMPRESSED)) == 0, fchmod(fd, 0o644) == 0 else { throw failed }
        let size = flistxattr(fd, nil, 0, 0)
        if size > 0 {
            var names = [CChar](repeating: 0, count: size)
            flistxattr(fd, &names, size, 0)
            for attribute in names.split(separator: 0).map({ Array($0) + [0] }) { fremovexattr(fd, attribute, 0) }
        }
        let mark = String(format: "0081;%08x;Sidefolk;", Int(now.timeIntervalSince1970))
        guard fsetxattr(fd, "com.apple.quarantine", mark, mark.utf8.count, 0, 0) == 0 else { throw failed }
        var today = timespec(tv_sec: Int(now.timeIntervalSince1970), tv_nsec: 0)
        var created = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: attrgroup_t(ATTR_CMN_CRTIME), volattr: 0, dirattr: 0, fileattr: 0, forkattr: 0)
        fsetattrlist(fd, &created, &today, MemoryLayout<timespec>.size, 0)
        var times = [today, today]
        futimens(fd, &times)
        fsync(fd)
    }

    /// Atomic and exclusive: the name appears complete or not at all, and a file already there is never replaced.
    private static func moveIntoPlace(_ holding: String, name: String, in folder: Int32) throws -> String {
        let base = (name as NSString).deletingPathExtension, ending = (name as NSString).pathExtension
        for number in 1...999 {
            let candidate = number == 1 ? name : "\(base) \(number).\(ending)"
            if renameatx_np(folder, holding, folder, candidate, UInt32(RENAME_EXCL)) == 0 { return candidate }
            if errno == ENOTSUP {
                // Some disks (exFAT) have no exclusive rename. Claiming the name first is just as exclusive: it fails if anything is
                // there, and the rename then only replaces the empty file this made.
                let claim = openat(folder, candidate, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
                if claim >= 0 {
                    close(claim)
                    if renameat(folder, holding, folder, candidate) == 0 { return candidate }
                    unlinkat(folder, candidate, 0)
                    throw UserFacingError("It couldn't be saved in that folder.", changedNothing: true)
                }
            }
            guard errno == EEXIST else { throw UserFacingError("It couldn't be saved in that folder.", changedNothing: true) }
        }
        throw UserFacingError("Too many files already have that name.", changedNothing: true)
    }
}
