import Darwin
import Foundation

// File tools that change things. They never overwrite and never hard-delete: moves refuse to replace
// anything (a taken name gets " 2", " 3" …), and deleting means the Trash. Each call can be undone.

/// Puts things in the Trash. A seam so tests don't fill the real Trash.
protocol FileTrashing: Sendable {
    /// Trashes `path` and returns where it ended up in the Trash ("" if the system didn't say).
    func trash(path: String) throws -> String
}

struct SystemTrash: FileTrashing {
    func trash(path: String) throws -> String {
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        return (result as URL?)?.path ?? ""
    }
}

private enum WriteChecks {
    static let maxItems = 100

    /// Canonical paths of items that may be moved, renamed or trashed. Everything is checked before
    /// anything is touched, so a bad entry fails the whole call.
    /// - Parameter moving: the items will end up somewhere else (move, rename), as opposed to the Trash.
    static func sources(_ raw: [String]?, moving: Bool) throws -> [String] {
        guard let raw, !raw.isEmpty else { throw ToolError.invalidInput("“paths” needs at least one path.") }
        guard raw.count <= maxItems else { throw UserFacingError("That's too many items at once (the limit is \(maxItems)).") }
        var seen = Set<String>()
        var out: [String] = []
        for entry in raw {
            let path = try source(entry, moving: moving)
            if seen.insert(path).inserted { out.append(path) }
        }
        return out
    }

    static func source(_ raw: String, moving: Bool) throws -> String {
        let path = try FilePaths.resolve(raw)
        guard FilePaths.exists(path) else { throw ToolError.notFound(FilePaths.display(path)) }
        guard !FilePaths.isLink(raw) else {
            throw UserFacingError("\(FilePaths.display(path)) is a link (alias), and I only change real files and folders.")
        }
        guard !FilePaths.isHomeTopLevel(path) else {
            throw UserFacingError("I won't move, rename or delete \(FilePaths.display(path)). It's one of the main folders in your home folder.")
        }
        if moving {
            var st = stat()
            if lstat(path, &st) == 0 { try FilePaths.refuseHardLink(st, path: path) }
        }
        return path
    }

    static func message(for code: Int32, path: String) -> UserFacingError { FileFailure.make(code, path: path, action: "change that") }
}

struct FilesMoveTool: Tool {
    let spec = ToolSpec(
        name: "files.move", title: "Move files",
        description: """
            Move files or folders into another existing folder. Nothing is ever overwritten: if the name is taken \
            the moved item gets " 2" added. Both the source and destination folders must be shared with Sidefolk.
            """,
        inputSchema: Schema.object([
            "paths": Schema.array("Full paths of what to move", items: Schema.string("A full path")),
            "to_folder": Schema.string("The existing folder to move them into"),
        ], required: ["paths", "to_folder"]),
        risk: .medium, capabilities: [.filesWrite], category: .files, mutates: true)

    func summary(for input: JSONValue) -> String {
        let n = input.textList("paths")?.count ?? 0
        let to = FilePaths.scopePath(input.string("to_folder")).map(FilePaths.display) ?? input.string("to_folder") ?? "a folder"
        return "Move \(ToolFormat.count(n, "item")) to \(to)"
    }

    func scope(for input: JSONValue) -> ToolScope {
        let sources = (input.textList("paths") ?? []).compactMap(FilePaths.scopePath)
        return ToolScope(writePaths: sources + [FilePaths.scopePath(input.string("to_folder"))].compactMap { $0 })
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let destination = try FilePaths.resolve(try input.requiredText("to_folder", limit: 1_024))
        guard FilePaths.isDirectory(destination) else {
            throw UserFacingError("The folder \(FilePaths.display(destination)) doesn't exist.", recovery: "Create it first with files.mkdir.")
        }
        let sources = try WriteChecks.sources(input.textList("paths"), moving: true)
        for source in sources where destination == source || destination.hasPrefix(source + "/") {
            throw UserFacingError("I can't move \(FilePaths.display(source)) into itself.")
        }
        // Items that run code when opened (an app, a .command) stay where they are: put on the
        // Desktop or into a synced folder, one click runs them (SECURITY T10.5).
        for source in sources where FilePaths.isRisky(name: FilePaths.name(source)) {
            throw UserFacingError("I won't move \(FilePaths.display(source)), because that kind of item can run programs.",
                                  recovery: "Move it yourself in Finder if you meant to.")
        }

        var moved: [(from: String, to: String)] = []
        var notes: [String] = []
        for source in sources {
            let name = FilePaths.name(source)
            if FilePaths.parent(source) == destination { notes.append("\(name) is already there"); continue }
            do {
                let target = try FileMover.moveToFreeName(from: source, folder: destination, name: name)
                moved.append((source, target))
                if FilePaths.name(target) != name { notes.append("“\(name)” became “\(FilePaths.name(target))” because that name was taken") }
            } catch FileMover.MoveError.errno(let code) {
                notes.append("couldn't move \(name): \(WriteChecks.message(for: code, path: source).message)")
            }
        }
        guard !moved.isEmpty else { throw UserFacingError(notes.isEmpty ? "Nothing was moved." : notes.joined(separator: "; ") + ".") }

        let names = moved.map { FilePaths.name($0.to) }
        var text = "Moved \(ToolFormat.count(moved.count, "item")) to \(FilePaths.display(destination)): \(ToolFormat.names(names, max: 5))."
        if !notes.isEmpty { text += " Note: " + notes.joined(separator: "; ") + "." }
        let records = moved
        return ToolResult(
            text: text,
            card: ResultCard(kind: .file, title: "Moved \(ToolFormat.count(moved.count, "item"))", subtitle: "to " + FilePaths.display(destination),
                             detail: notes.isEmpty ? nil : notes.joined(separator: "; ")),
            undo: UndoAction(label: "Moved \(ToolFormat.count(records.count, "item")) back") {
                var stuck: [String] = []
                for r in records.reversed() {
                    do { try FileMover.moveExclusive(from: r.to, to: r.from) } catch { stuck.append(FilePaths.name(r.to)) }
                }
                if !stuck.isEmpty {
                    throw UserFacingError("I couldn't move back: \(ToolFormat.names(stuck)). Something may have changed since.")
                }
            })
    }
}

struct FilesRenameTool: Tool {
    let spec = ToolSpec(
        name: "files.rename", title: "Rename a file",
        description: "Rename one file or folder (keeping it in the same folder). Fails rather than replacing an existing item.",
        inputSchema: Schema.object([
            "path": Schema.string("Full path of the item"),
            "new_name": Schema.string("The new name only, with no folders, e.g. “Report 2025.pdf”"),
        ], required: ["path", "new_name"]),
        risk: .medium, capabilities: [.filesWrite], category: .files, mutates: true)

    func summary(for input: JSONValue) -> String {
        let old = input.string("path").map { FilePaths.name($0) } ?? "an item"
        return "Rename \(old) to “\((input.string("new_name") ?? "").clipped(80))”"
    }

    func scope(for input: JSONValue) -> ToolScope {
        guard let source = FilePaths.scopePath(input.string("path")), let name = input.string("new_name"), !name.contains("/") else {
            return ToolScope(writePaths: [FilePaths.scopePath(input.string("path"))].compactMap { $0 })
        }
        return ToolScope(writePaths: [source, FilePaths.join(FilePaths.parent(source), name)].compactMap(FilePaths.scopePath))
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let raw = try input.requiredText("path", limit: 1_024)
        let source = try WriteChecks.source(raw, moving: true)
        let newName = try FilePaths.validateName(try input.requiredText("new_name", limit: 255))
        let oldName = FilePaths.name(source)
        guard newName != oldName else { throw UserFacingError("It's already called “\(oldName)”.") }
        let oldExt = (oldName as NSString).pathExtension.lowercased(), newExt = (newName as NSString).pathExtension.lowercased()
        if FilePaths.isRisky(name: newName), oldExt != newExt {
            throw UserFacingError("I won't rename something into a “.\(newExt)” item, because those can run programs.")
        }
        // Check the destination, but rename to the spelling that was asked for: on a case-insensitive disk the
        // canonical form of an existing "readme.txt" would swallow a request for "README.txt".
        let target = FilePaths.join(FilePaths.parent(source), newName)
        _ = try FilePaths.resolve(target)
        try Self.rename(from: source, to: target, oldName: oldName, newName: newName)

        return ToolResult(
            text: "Renamed “\(oldName)” to “\(newName)”.",
            card: ResultCard(kind: .file, title: "Renamed", subtitle: "\(oldName) → \(newName)"),
            undo: UndoAction(label: "Renamed “\(newName.clipped(40))” back") {
                try Self.rename(from: target, to: source, oldName: newName, newName: oldName)
            })
    }

    /// Never replaces. A change of letter case only (`a.txt` → `A.txt`) names the same file, so it is allowed.
    static func rename(from: String, to: String, oldName: String, newName: String) throws {
        var a = stat(), b = stat()
        if lstat(from, &a) == 0, lstat(to, &b) == 0, a.st_dev == b.st_dev, a.st_ino == b.st_ino, oldName.lowercased() == newName.lowercased() {
            guard Darwin.rename(from, to) == 0 else { throw FileFailure.make(errno, path: from, action: "rename that") }
            return
        }
        do { try FileMover.moveExclusive(from: from, to: to) } catch FileMover.MoveError.errno(let code) {
            if code == EEXIST { throw UserFacingError("There's already something called “\(newName.clipped(60))” in that folder, so I didn't rename it.") }
            throw FileFailure.make(code, path: from, action: "rename that")
        }
    }
}

struct FilesMkdirTool: Tool {
    let spec = ToolSpec(
        name: "files.mkdir", title: "Create a folder",
        description: "Create a new folder (and any missing folders above it) inside a folder the user has shared.",
        inputSchema: Schema.object(["path": Schema.string("Full path of the folder to create")], required: ["path"]),
        risk: .medium, capabilities: [.filesWrite], category: .files, mutates: true)

    func summary(for input: JSONValue) -> String {
        "Create the folder \(FilePaths.scopePath(input.string("path")).map(FilePaths.display) ?? input.string("path") ?? "")"
    }

    func scope(for input: JSONValue) -> ToolScope {
        ToolScope(writePaths: [FilePaths.scopePath(input.string("path"))].compactMap { $0 })
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let path = try FilePaths.resolve(try input.requiredText("path", limit: 1_024))
        if FilePaths.exists(path) {
            guard FilePaths.isDirectory(path) else {
                throw UserFacingError("There's already a file called \(FilePaths.name(path)) there, so I can't make a folder with that name.")
            }
            return ToolResult(text: "\(FilePaths.display(path)) already exists.",
                              card: ResultCard(kind: .file, title: "Folder already exists", subtitle: FilePaths.display(path)))
        }
        var missing: [String] = []
        var cursor = path
        while cursor != "/", !FilePaths.exists(cursor) {
            missing.insert(cursor, at: 0)
            cursor = FilePaths.parent(cursor)
        }
        for dir in missing {
            let name = try FilePaths.validateName(FilePaths.name(dir))
            if FilePaths.isRisky(name: name) { throw UserFacingError("I won't create “\(name.clipped(60))”, because that kind of item can run programs.") }
        }
        var created: [String] = []
        for dir in missing {
            guard mkdir(dir, 0o755) == 0 else {
                let code = errno
                Self.remove(created)   // leave nothing half made
                throw FileFailure.make(code, path: dir, action: "create that folder")
            }
            // Sidefolk runs with umask 077; a folder in the user's own files is an ordinary 0755 one.
            _ = chmod(dir, 0o755)
            created.append(dir)
        }
        let made = created
        return ToolResult(
            text: "Created the folder \(FilePaths.display(path)).",
            card: ResultCard(kind: .file, title: "Created a folder", subtitle: FilePaths.display(path)),
            undo: UndoAction(label: "Removed the folder \(FilePaths.name(path))") {
                if Self.remove(made) < made.count {
                    throw UserFacingError("There are files in \(FilePaths.display(path)) now, so I left the folder.")
                }
            })
    }

    /// Removes the folders we made, deepest first, and only while they are empty (`rmdir` refuses otherwise).
    @discardableResult
    static func remove(_ folders: [String]) -> Int {
        var removed = 0
        for dir in folders.reversed() {
            guard rmdir(dir) == 0 else { break }
            removed += 1
        }
        return removed
    }
}

struct FilesTrashTool: Tool {
    let trasher: any FileTrashing
    init(trasher: any FileTrashing = SystemTrash()) { self.trasher = trasher }

    let spec = ToolSpec(
        name: "files.trash", title: "Move files to the Trash",
        description: "Move files or folders to the Trash. Nothing is deleted for good; the user can put them back from the Trash.",
        inputSchema: Schema.object([
            "paths": Schema.array("Full paths of what to trash", items: Schema.string("A full path")),
        ], required: ["paths"]),
        risk: .high, capabilities: [.filesWrite], category: .files, mutates: true)

    func summary(for input: JSONValue) -> String {
        let names = (input.textList("paths") ?? []).map { FilePaths.name($0) }
        return "Move \(ToolFormat.count(names.count, "item")) to the Trash: \(ToolFormat.names(names))"
    }

    func scope(for input: JSONValue) -> ToolScope {
        ToolScope(writePaths: (input.textList("paths") ?? []).compactMap(FilePaths.scopePath))
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let sources = try WriteChecks.sources(input.textList("paths"), moving: false)
        var trashed: [(original: String, inTrash: String)] = []
        var failures: [String] = []
        for source in sources {
            do { trashed.append((source, try trasher.trash(path: source))) }
            catch { failures.append(FilePaths.name(source)) }
        }
        guard !trashed.isEmpty else {
            throw UserFacingError("I couldn't move \(ToolFormat.names(failures)) to the Trash.", recovery: "Check that Sidefolk is allowed to change that folder.")
        }
        var text = "Moved \(ToolFormat.count(trashed.count, "item")) to the Trash: \(ToolFormat.names(trashed.map { FilePaths.name($0.original) }, max: 5))."
        if !failures.isEmpty { text += " Couldn't move: \(ToolFormat.names(failures))." }
        let records = trashed.filter { !$0.inTrash.isEmpty }
        return ToolResult(
            text: text,
            card: ResultCard(kind: .file, title: "Moved \(ToolFormat.count(trashed.count, "item")) to the Trash",
                             subtitle: ToolFormat.names(trashed.map { FilePaths.name($0.original) }),
                             detail: failures.isEmpty ? nil : "Couldn't move: \(ToolFormat.names(failures))"),
            undo: records.isEmpty ? nil : UndoAction(label: "Put \(ToolFormat.count(records.count, "item")) back") {
                var stuck: [String] = []
                for r in records.reversed() {
                    do { try FileMover.moveExclusive(from: r.inTrash, to: r.original) } catch { stuck.append(FilePaths.name(r.original)) }
                }
                if !stuck.isEmpty {
                    throw UserFacingError("I couldn't put back \(ToolFormat.names(stuck)). You can restore it from the Trash.")
                }
            })
    }
}
