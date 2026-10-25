import Darwin
import Foundation

// MARK: Shared file plumbing

struct FileFacts: Equatable, Sendable {
    var size: Double
    var mtime: Double
    var isDirectory: Bool

    /// Metadata only; follows links like `ls` would. Nil when nothing is there (or a link dangles).
    static func read(_ path: String) -> FileFacts? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        return FileFacts(size: Double(st.st_size), mtime: mtime, isDirectory: (st.st_mode & S_IFMT) == S_IFDIR)
    }

    func sameContent(as other: FileFacts) -> Bool { size == other.size && abs(mtime - other.mtime) < 0.001 }
}

enum WatchedPath {
    /// A path typed by a person, made absolute and canonical. The canonical form is what gets watched,
    /// so later changes to links in between cannot redirect the watcher (docs/SECURITY.md T10).
    static func prepare(_ config: JSONValue) throws -> JSONValue {
        guard let raw = config.string("path") else { throw WatchError.invalid("Tell me which file or folder to watch.") }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw WatchError.invalid("I need the full path, like ~/Downloads/report.pdf.") }
        guard let canonical = FolderAccess.canonical(expanded) else {
            throw WatchError.invalid("That path isn't allowed (it has “..” in it, or a link that goes nowhere).")
        }
        if let why = FolderAccess.forbiddenReason([canonical]) { throw WatchError.invalid(why) }
        return config.setting("path", .string(expanded)).setting("resolved", .string(canonical))
    }

    /// The canonical path to look at, after checking that no link has appeared on the way since the watcher was made.
    static func resolved(_ config: JSONValue) throws -> String {
        guard let resolved = config.string("resolved") ?? config.string("path").flatMap({ FolderAccess.canonical($0) }) else {
            throw ProbeError.failed("This watcher has no path.")
        }
        guard FolderAccess.canonical(resolved) == resolved else {
            throw ProbeError.failed("A link now points somewhere else on the way to \(FolderAccess.displayPath(resolved)), so I stopped looking there.")
        }
        return resolved
    }

    /// The closest folder that exists, so a watcher for a file that is not there yet still hears about its folder.
    static func nearestExistingDirectory(of path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if let facts = FileFacts.read(url.path), facts.isDirectory { return url.path }
        }
        return nil
    }

    static func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent.displaySafe.clipped(80) }

    static func size(_ bytes: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    /// Types that are safe to hand to the Mac to open: they are shown, never run. Everything else (programs,
    /// scripts, installers, `.inetloc`/`.webloc`/`.fileloc` shortcuts, files with no extension) is shown in its
    /// folder instead. An allow list, because a deny list always misses the next launchable type (docs/SECURITY.md T10).
    static let openableExtensions: Set<String> = [
        "pdf", "txt", "text", "md", "markdown", "rtf", "csv", "tsv", "log", "json", "xml", "yaml", "yml",
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "odt", "ods", "odp",
        "html", "htm", "xhtml",
        "mp3", "m4a", "wav", "aif", "aiff", "aac", "flac", "mp4", "m4v", "mov",
    ]

    /// What "Open" on a notice should open: the file itself when it is plainly a document, otherwise the folder it
    /// is in. Decided on the real file, so a link called `report.pdf` that leads to a script does not count.
    static func openable(_ path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var st = stat()
        guard stat(real, &st) == 0 else { return folder }
        let names = [path, real].map { URL(fileURLWithPath: $0).pathExtension.lowercased() }

        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            // A plain folder opens in Finder; one with a suffix may be a program (`Tool.app`, `Thing.bundle`).
            return names.allSatisfy(\.isEmpty) ? path : folder
        case S_IFREG:
            guard names.allSatisfy(openableExtensions.contains), st.st_mode & 0o111 == 0, !looksLaunchable(real) else { return folder }
            return path
        default:
            return folder
        }
    }

    /// A script (`#!`) or a program (Mach-O, universal or Java class) whatever its name says.
    private static func looksLaunchable(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return true }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 4)) ?? Data())
        if head.starts(with: [0x23, 0x21]) { return true }
        let magic: [[UInt8]] = [[0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF], [0xCE, 0xFA, 0xED, 0xFE], [0xCF, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE]]
        return magic.contains(head)
    }
}

// MARK: file_appears

public struct FileAppearsProbe: WatcherProbe {
    public let kind = WatchKind.fileAppears
    public var defaultInterval: TimeInterval { 30 }
    public var minimumInterval: TimeInterval { 15 }

    /// A file written a moment ago may still be growing; wait this long after its last write.
    let settle: TimeInterval

    public init(settle: TimeInterval = 3) { self.settle = settle }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        w.config = try WatchedPath.prepare(w.config)
        w.condition = w.condition["gone"]?.boolValue == true ? ["gone": true] : .object([:])
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        let path = try WatchedPath.resolved(w.config)
        let gone = w.condition["gone"]?.boolValue == true
        let facts = FileFacts.read(path)
        let previous = w.lastState
        let firstLook = previous == nil
        let name = WatchedPath.name(path)

        var settled = false
        if let facts {
            let before = previous?["exists"]?.boolValue == true ? previous.flatMap(Self.facts) : nil
            settled = now.timeIntervalSince1970 - facts.mtime >= settle || before?.sameContent(as: facts) == true
        }
        let matches = gone ? facts == nil : (facts != nil && settled)
        let wasMatched = previous?["matched"]?.boolValue ?? false

        var state: [String: JSONValue] = ["exists": .bool(facts != nil), "matched": .bool(matches)]
        if let facts { state["size"] = .number(facts.size); state["mtime"] = .number(facts.mtime) }
        let recheck: TimeInterval? = (!gone && facts != nil && !settled) ? settle + 0.5 : nil
        guard matches, !wasMatched else { return ProbeResult(state: .object(state), recheckIn: recheck) }

        if gone {
            return ProbeResult(state: .object(state), triggered: true,
                               summary: firstLook ? "\(name) isn't there" : "\(name) is gone",
                               openTarget: (path as NSString).deletingLastPathComponent)
        }
        let detail = facts.map { "\(WatchedPath.size($0.size))" + ($0.isDirectory ? " (folder)" : "") }
        return ProbeResult(state: .object(state), triggered: true, summary: firstLook ? "\(name) is already there" : "\(name) appeared",
                           detail: detail, openTarget: WatchedPath.openable(path))
    }

    public func eventTargets(for watcher: Watcher) -> [WatchEventTarget] {
        guard let path = try? WatchedPath.resolved(watcher.config), let dir = WatchedPath.nearestExistingDirectory(of: path) else { return [] }
        return [.directory(dir)]
    }

    static func facts(_ state: JSONValue) -> FileFacts? {
        guard let size = state["size"]?.doubleValue, let mtime = state["mtime"]?.doubleValue else { return nil }
        return FileFacts(size: size, mtime: mtime, isDirectory: false)
    }
}

// MARK: file_changes

public struct FileChangesProbe: WatcherProbe {
    public let kind = WatchKind.fileChanges
    public var defaultInterval: TimeInterval { 30 }
    public var minimumInterval: TimeInterval { 15 }

    public init() {}

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        w.config = try WatchedPath.prepare(w.config)
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        let path = try WatchedPath.resolved(w.config)
        let facts = FileFacts.read(path)
        var state: [String: JSONValue] = ["exists": .bool(facts != nil)]
        if let facts { state["size"] = .number(facts.size); state["mtime"] = .number(facts.mtime) }

        guard let previous = w.lastState else { return ProbeResult(state: .object(state)) } // the first look is the baseline
        let existed = previous["exists"]?.boolValue == true
        let before = FileAppearsProbe.facts(previous)
        let name = WatchedPath.name(path)
        let open = WatchedPath.openable(path)

        switch (existed, facts) {
        case (false, nil): return ProbeResult(state: .object(state))
        case (false, let now?):
            return ProbeResult(state: .object(state), triggered: true, summary: "\(name) was created",
                               detail: WatchedPath.size(now.size), openTarget: open)
        case (true, nil):
            return ProbeResult(state: .object(state), triggered: true, summary: "\(name) was deleted",
                               openTarget: (path as NSString).deletingLastPathComponent)
        case (true, let now?):
            guard let before, !now.sameContent(as: before) else { return ProbeResult(state: .object(state)) }
            let sizes = before.size == now.size ? "Size unchanged" : "\(WatchedPath.size(before.size)) → \(WatchedPath.size(now.size))"
            return ProbeResult(state: .object(state), triggered: true, summary: "\(name) changed", detail: sizes, openTarget: open)
        }
    }

    public func eventTargets(for watcher: Watcher) -> [WatchEventTarget] {
        guard let path = try? WatchedPath.resolved(watcher.config) else { return [] }
        if FileFacts.read(path) != nil { return [.file(path)] }
        return WatchedPath.nearestExistingDirectory(of: path).map { [.directory($0)] } ?? []
    }
}

// MARK: folder_new_file

public struct FolderNewFileProbe: WatcherProbe {
    public let kind = WatchKind.folderNewFile
    public var defaultInterval: TimeInterval { 30 }
    public var minimumInterval: TimeInterval { 15 }

    /// How soon to look again at a file that might still be growing.
    let settleRecheck: TimeInterval
    static let maxEntries = 5000
    static let partialSuffixes = [".crdownload", ".download", ".part", ".tmp"]

    public init(settleRecheck: TimeInterval = 3) { self.settleRecheck = settleRecheck }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        w.config = try WatchedPath.prepare(w.config)
        if let pattern = w.config.string("pattern") {
            guard pattern.count <= 100, !pattern.contains("/") else { throw WatchError.invalid("The file pattern should be a short name pattern like *.pdf.") }
        }
        return w
    }

    static func isPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return partialSuffixes.contains { lower.hasSuffix($0) }
    }

    /// Hidden files and partial downloads are never reported.
    static func isIgnored(_ name: String) -> Bool { name.hasPrefix(".") || isPartial(name) }

    static func matches(_ name: String, pattern: String?) -> Bool {
        guard let pattern else { return true }
        return fnmatch(pattern, name, FNM_CASEFOLD) == 0
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        let dir = try WatchedPath.resolved(w.config)
        guard FileFacts.read(dir)?.isDirectory == true else { throw ProbeError.failed("I can't find the folder \(FolderAccess.displayPath(dir)).") }
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: dir) } catch {
            throw ProbeError.failed("I can't read the folder \(FolderAccess.displayPath(dir)).")
        }
        guard names.count <= Self.maxEntries else { throw ProbeError.failed("That folder has too many items for me to watch.") }

        let visible = names.filter { !Self.isIgnored($0) }
        let partials = Array(names.filter { !$0.hasPrefix(".") && Self.isPartial($0) }.sorted().prefix(50))
        guard let previous = w.lastState, let seenList = previous["seen"]?.arrayValue else {
            return ProbeResult(state: ["seen": .array(visible.sorted().map { .string($0) }), "partials": .array(partials.map { .string($0) })])
        }

        let seen = Set(seenList.compactMap(\.stringValue))
        let pattern = w.config.string("pattern")
        let pendingBefore = previous["pending"]?.objectValue?.mapValues { $0.doubleValue ?? -1 } ?? [:]
        let partialsBefore = Set(previous["partials"]?.arrayValue?.compactMap(\.stringValue) ?? [])

        var settled: [String] = []
        var pending: [String: Double] = [:]
        var downloaded: Set<String> = []
        for name in visible.sorted() where !seen.contains(name) && Self.matches(name, pattern: pattern) {
            guard let facts = FileFacts.read(dir + "/" + name) else { continue } // vanished again
            if facts.isDirectory || pendingBefore[name] == facts.size {
                settled.append(name)
            } else {
                pending[name] = facts.size
            }
        }
        // A name that was a partial download a moment ago (report.pdf.crdownload → report.pdf), or that was seen
        // growing between two looks, was being downloaded or written.
        for name in settled + Array(pending.keys) where Self.partialSuffixes.contains(where: { partialsBefore.contains(name + $0) }) {
            downloaded.insert(name)
        }
        for name in pendingBefore.keys where pending[name] != nil && pending[name] != pendingBefore[name] { downloaded.insert(name) }

        let growingBefore = Set(previous["growing"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        let stillGrowing = downloaded.union(growingBefore).filter { pending[$0] != nil }
        var state: [String: JSONValue] = [
            "seen": .array(visible.filter { pending[$0] == nil }.sorted().map { .string($0) }),
            "partials": .array(partials.map { .string($0) }),
        ]
        if !pending.isEmpty { state["pending"] = .object(pending.mapValues { .number($0) }) }
        if !stillGrowing.isEmpty { state["growing"] = .array(stillGrowing.sorted().map { .string($0) }) }
        let recheck: TimeInterval? = pending.isEmpty ? nil : settleRecheck
        guard !settled.isEmpty else { return ProbeResult(state: .object(state), recheckIn: recheck) }

        let folder = WatchedPath.name(dir)
        if settled.count == 1, let only = settled.first {
            let label = only.displaySafe.clipped(80)
            let isDownload = downloaded.contains(only) || growingBefore.contains(only) || folder == "Downloads"
            let facts = FileFacts.read(dir + "/" + only)
            return ProbeResult(state: .object(state), triggered: true,
                               summary: isDownload ? "\(label) finished downloading" : "New in \(folder): \(label)",
                               detail: facts.map { $0.isDirectory ? "A folder" : WatchedPath.size($0.size) },
                               openTarget: WatchedPath.openable(dir + "/" + only), recheckIn: recheck)
        }
        let shown = settled.prefix(4).map { $0.displaySafe.clipped(40) }.joined(separator: ", ")
        let more = settled.count > 4 ? " and \(settled.count - 4) more" : ""
        return ProbeResult(state: .object(state), triggered: true, summary: "\(settled.count) new files in \(folder)",
                           detail: shown + more, openTarget: dir, recheckIn: recheck)
    }

    public func eventTargets(for watcher: Watcher) -> [WatchEventTarget] {
        guard let path = try? WatchedPath.resolved(watcher.config) else { return [] }
        return [.directory(path)]
    }
}
