import Foundation
import Synchronization
@testable import SidefolkCore

/// A platform that records what was asked of it, with a clipboard that really holds text.
final class RecordingPlatform: PlatformBridge, Sendable {
    private struct State {
        var clipboard: String?
        var openedURLs: [URL] = []
        var openedApps: [String] = []
        var revealed: [String] = []
        var opensSucceed = true
    }
    private let state = Mutex(State())

    init(clipboard: String? = nil) { state.withLock { $0.clipboard = clipboard } }

    var clipboard: String? {
        get { state.withLock { $0.clipboard } }
        set { state.withLock { $0.clipboard = newValue } }
    }
    var openedURLs: [URL] { state.withLock { $0.openedURLs } }
    var openedApps: [String] { state.withLock { $0.openedApps } }
    var revealed: [String] { state.withLock { $0.revealed } }
    func failOpens() { state.withLock { $0.opensSucceed = false } }

    func clipboardText() async -> String? { clipboard }
    func setClipboard(_ text: String) async { clipboard = text }
    func open(url: URL) async -> Bool { state.withLock { $0.openedURLs.append(url); return $0.opensSucceed } }
    func openApplication(_ nameOrBundleId: String) async -> Bool { state.withLock { $0.openedApps.append(nameOrBundleId); return $0.opensSucceed } }
    func reveal(path: String) async { state.withLock { $0.revealed.append(path) } }
    func frontmostApplication() async -> FrontmostApp? { nil }
}

/// Serves canned pages and remembers what was asked for.
final class ScriptedFetcher: WebFetching, Sendable {
    private struct State {
        var responses: [String: Result<WebResponse, WebFetchError>] = [:]
        var fallback: Result<WebResponse, WebFetchError>?
        var requested: [URL] = []
    }
    private let state = Mutex(State())

    var requested: [URL] { state.withLock { $0.requested } }

    func serve(_ url: String, html: String, status: Int = 200, type: String = "text/html; charset=utf-8", finalURL: String? = nil) {
        let u = URL(string: url)!
        let response = WebResponse(requestedURL: u, url: URL(string: finalURL ?? url)!, statusCode: status, contentType: type, body: Data(html.utf8))
        state.withLock { $0.responses[url] = .success(response) }
    }

    func serve(_ url: String, data: Data, type: String?, status: Int = 200) {
        let u = URL(string: url)!
        state.withLock { $0.responses[url] = .success(WebResponse(requestedURL: u, url: u, statusCode: status, contentType: type, body: data)) }
    }

    func fail(_ url: String, with error: WebFetchError) { state.withLock { $0.responses[url] = .failure(error) } }

    func get(_ url: URL, options: WebFetchOptions) async throws -> WebResponse {
        let result = state.withLock { s -> Result<WebResponse, WebFetchError>? in
            s.requested.append(url)
            return s.responses[url.absoluteString] ?? s.fallback
        }
        guard let result else { throw WebFetchError.network("no stub for \(url)") }
        return try result.get()
    }
}

struct ScriptedSearch: FileSearching {
    var results: [String]
    func search(query: String, inFolder folder: String, limit: Int) async throws -> [String] { Array(results.prefix(limit)) }
}

/// A "Trash" inside a temp folder, so tests never touch the real one.
struct TempTrash: FileTrashing {
    let folder: String
    func trash(path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let target = folder + "/" + UUID().uuidString + "-" + (path as NSString).lastPathComponent
        try FileManager.default.moveItem(atPath: path, toPath: target)
        return target
    }
}

/// Everything the built-in tool tests need: an isolated core, the tools registered, and temp folders.
struct BuiltinEnv {
    let env: TestEnv
    let notebook: NotebookStore
    let platform: RecordingPlatform
    let fetcher = ScriptedFetcher()
    let trash: TempTrash
    /// Canonical path of an empty temp folder owned by this test.
    let root: String

    init(clipboard: String? = nil, searchResults: [String] = []) throws {
        env = try TestEnv()
        notebook = NotebookStore(env.db)
        platform = RecordingPlatform(clipboard: clipboard)
        root = FolderAccess.canonical(env.home.path)!
        trash = TempTrash(folder: root + "/.fake-trash")
        env.registry.register(BuiltinTools.make(notebook: notebook, platform: platform, events: env.events, fetcher: fetcher))
        // Swap in the seams so no test touches Spotlight or the real Trash.
        env.registry.register(FilesSearchTool(searcher: ScriptedSearch(results: searchResults)))
        env.registry.register(FilesTrashTool(trasher: trash))
    }

    func cleanup() { try? FileManager.default.removeItem(at: env.home) }

    /// - Parameter said: what the user typed in the request; by default the call's own `url`, as in
    ///   "open https://…". Links the user didn't type make web and open calls ask (SECURITY T2).
    @discardableResult
    func run(_ tool: String, _ input: JSONValue = [:], as caller: Caller = .agent(runId: "t"), tainted: Bool = false,
             said: String? = nil) async -> ToolOutcome {
        await env.executor.execute(name: tool, input: input, caller: caller, tainted: tainted,
                                   mentions: UserMentions(text: said ?? input["url"]?.stringValue ?? ""))
    }

    /// Shares a folder (read and write) the way the user's "always allow" would.
    func grant(_ path: String? = nil) async throws {
        try await env.permissions.grantFolder(path ?? root, access: .readwrite)
    }

    /// A subfolder of the test's temp root, created.
    @discardableResult
    func folder(_ name: String) throws -> String {
        let path = root + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @discardableResult
    func file(_ relative: String, _ content: String = "hello") throws -> String {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
}

extension ToolOutcome {
    var result: ToolResult? { if case .ok(let r) = status { return r } else { return nil } }
    /// The text the model would read, whether it worked or not.
    var text: String {
        switch status {
        case .ok(let r): r.text
        case .denied(let why): why
        case .failed(let e): e.message + (e.recovery.map { " " + $0 } ?? "")
        }
    }
    var failure: UserFacingError? { if case .failed(let e) = status { return e } else { return nil } }
    var wasDenied: Bool { if case .denied = status { return true } else { return false } }
}
