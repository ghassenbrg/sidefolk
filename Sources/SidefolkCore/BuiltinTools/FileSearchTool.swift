import Foundation

/// Finds files inside one folder. The real implementation asks Spotlight; tests use a fake.
protocol FileSearching: Sendable {
    /// Paths Spotlight reports under `folder` for `query`, in its order, at most `limit` of them.
    func search(query: String, inFolder folder: String, limit: Int) async throws -> [String]
}

/// `/usr/bin/mdfind -onlyin <folder> <query>` with a timeout and an output cap.
struct SpotlightSearch: FileSearching {
    var timeout: TimeInterval = 10
    var maxOutputBytes = 512 * 1024

    func search(query: String, inFolder folder: String, limit: Int) async throws -> [String] {
        let timeout = self.timeout, cap = maxOutputBytes
        let output: Data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try Self.runMdfind(["-onlyin", folder, query], timeout: timeout, cap: cap)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        return String(decoding: output, as: UTF8.self).split(separator: "\n").prefix(limit).map(String.init)
    }

    /// A process we may need to stop from another thread.
    private final class Running: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var stopped = false
        private var timedOutFlag = false
        var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOutFlag }
        func stop(timedOut: Bool = false) {
            lock.lock(); defer { lock.unlock() }
            if timedOut { timedOutFlag = true }
            if !stopped, process.isRunning { stopped = true; process.terminate() }
        }
    }

    private static func runMdfind(_ arguments: [String], timeout: TimeInterval, cap: Int) throws -> Data {
        let running = Running()
        let pipe = Pipe()
        running.process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        running.process.arguments = arguments
        running.process.standardOutput = pipe
        running.process.standardError = FileHandle.nullDevice
        running.process.standardInput = FileHandle.nullDevice
        running.process.environment = [:]
        do { try SpawnLock.withLock { try running.process.run() } } catch {
            throw UserFacingError("Spotlight search isn't available on this Mac.", detail: String(describing: error))
        }
        let timer = DispatchWorkItem { running.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }

        var data = Data()
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData   // blocks until output or EOF
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > cap { running.stop(); break }
        }
        running.process.waitUntilExit()
        if running.timedOut {
            throw UserFacingError("The search took too long, so I stopped it.", recovery: "Try a more specific search or a smaller folder.")
        }
        return data
    }
}

struct FilesSearchTool: Tool {
    let searcher: any FileSearching
    init(searcher: any FileSearching = SpotlightSearch()) { self.searcher = searcher }

    let spec = ToolSpec(
        name: "files.search", title: String(localized: "Find files"),
        description: """
            Search inside one folder the user has shared, using Spotlight (names and contents). Returns matching \
            paths with size and date. Hidden files and anything outside the folder are left out.
            """,
        inputSchema: Schema.object([
            "query": Schema.string("What to look for, e.g. “invoice 2025”"),
            "folder": Schema.string("The folder to search in, e.g. ~/Documents"),
            "limit": Schema.integer("Maximum results (default 25)", minimum: 1, maximum: 50),
        ], required: ["query", "folder"]),
        risk: .low, capabilities: [.filesRead], category: .files, mutates: false)

    func summary(for input: JSONValue) -> String {
        let folder = FilePaths.display(FilePaths.scopePath(input.string("folder")) ?? input.string("folder") ?? String(localized: "a folder"))
        return String(localized: "Search \(folder) for “\((input.string("query") ?? "").clipped(60))”")
    }

    func scope(for input: JSONValue) -> ToolScope {
        ToolScope(readPaths: [FilePaths.scopePath(input.string("folder"))].compactMap { $0 })
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let query = try input.requiredText("query", limit: 200)
        // mdfind would read a leading dash as one of its own options.
        guard !query.hasPrefix("-") else { throw UserFacingError("A search can't start with a dash.") }
        let folder = try FilePaths.resolve(try input.requiredText("folder", limit: 1_024))
        guard FilePaths.isDirectory(folder) else { throw UserFacingError("\(FilePaths.display(folder)) isn't a folder I can search.") }
        let limit = input.clampedInt("limit", default: 25, in: 1...50)

        // Ask for more than we need: some results are dropped below.
        let raw = try await searcher.search(query: query, inFolder: folder, limit: 500)
        var kept: [String] = []
        for candidate in raw {
            guard let path = FolderAccess.canonical(candidate), FolderAccess.isInside(path, folder: folder),
                  FolderAccess.forbiddenReason([path]) == nil else { continue }
            kept.append(path)
            if kept.count == limit { break }
        }
        let where_ = FilePaths.display(folder)
        guard !kept.isEmpty else {
            return ToolResult(text: "Nothing in \(where_) matched “\(query.clipped(60))”.",
                              card: ResultCard(kind: .list, title: String(localized: "No files found"), subtitle: query.clipped(60)))
        }
        let lines = kept.map { path -> String in
            var st = stat()
            var detail = ""
            if lstat(path, &st) == 0 {
                let isDir = st.st_mode & S_IFMT == S_IFDIR
                detail = " — " + (isDir ? "folder" : ToolFormat.bytes(Int64(st.st_size)))
                    + ", modified \(ToolFormat.day(Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))))"
            }
            return ToolFormat.oneLine(ExternalText.clean(FilePaths.display(path)), 240) + detail
        }
        return ToolResult(
            text: "\(ToolFormat.count(kept.count, "file")) in \(where_) matched “\(query.clipped(60))”:\n" + lines.joined(separator: "\n"),
            card: ResultCard(kind: .file, title: String(localized: "\(kept.count) matches for “\(query.clipped(40))”"), subtitle: where_),
            untrusted: true)
    }
}
