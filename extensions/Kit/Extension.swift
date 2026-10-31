import Foundation

/// The program side of Sidefolk's extension protocol (docs/EXTENSIONS.md › The protocol): MCP over stdin and
/// stdout, one JSON-RPC 2.0 message per line each way. The extensions that ship with Sidefolk are small programs
/// built on it and signed inside the app, so they need nothing installed on the Mac: no Python, no Node.
///
/// ```swift
/// let ext = Extension(name: "hello")
/// ext.tool("hello", "Say hello", "Says hello to someone.", input: Schema.object(["name": Schema.string("Who.")])) { args in
///     "Hello, \(args.string("name") ?? "friend")!"
/// }
/// await ext.serve()
/// ```
@MainActor
public final class Extension {
    private struct Tool {
        let name: String
        let title: String
        let description: String
        let input: [String: Any]
        let run: @MainActor (Arguments) async throws -> String
    }

    private let name: String
    private let version: String
    private var tools: [Tool] = []
    private var watchers: [String: @MainActor (Arguments, [String: Any]) async throws -> Check] = [:]
    private var pages: [String: @MainActor (Arguments) async throws -> Page] = [:]
    private var palettes: [String: (query: @MainActor (String) async throws -> PaletteList,
                                    choose: @MainActor (_ item: String, _ action: String) async throws -> PaletteChoice,
                                    preview: (@MainActor (_ item: String) async throws -> PalettePreview?)?)] = [:]
    private var backgroundWork: (@MainActor () async -> Void)?
    private var notices: [String: @MainActor (Arguments) -> Void] = [:]
    private var pairedCheck: (@MainActor (_ tool: String, _ arguments: Arguments) async -> Paired)?

    public init(name: String, version: String = "1.0.0") {
        self.name = name
        self.version = version
    }

    /// A tool: what it does in one sentence the model reads, its JSON Schema, and the work. Throw `Problem` for
    /// something the person or the model can fix ("That folder isn't a Git repository."): it becomes an error result.
    public func tool(_ name: String, _ title: String, _ description: String, input: [String: Any] = Schema.none,
                     run: @escaping @MainActor (Arguments) async throws -> String) {
        tools.append(Tool(name: name, title: title, description: description, input: input, run: run))
    }

    /// A watcher kind the manifest declares: given its settings and the state it returned last time, whether to
    /// tell the person now.
    public func watcher(_ name: String, check: @escaping @MainActor (_ settings: Arguments, _ state: [String: Any]) async throws -> Check) {
        watchers[name] = check
    }

    /// A page the manifest declares (`pages.<name>`): what it shows now, in the person's language (`L`, `Format`; the
    /// arguments carry `language` too).
    public func page(_ name: String, render: @escaping @MainActor (Arguments) async throws -> Page) {
        pages[name] = render
    }

    /// A palette the manifest declares (`palettes.<name>`): what it lists for what the person typed, and what
    /// choosing an item does. `action` is `choose` (Return), `plain` (Shift-Return), `alternate` (Option-Return), `pin`
    /// or `delete`; or, with an empty item, one of the list's own `actions` (`clear`). `preview`, when given, shows the
    /// picked item in full beside the list (say so with `PaletteList(preview: true)`).
    public func palette(_ name: String, query: @escaping @MainActor (String) async throws -> PaletteList,
                        choose: @escaping @MainActor (_ item: String, _ action: String) async throws -> PaletteChoice,
                        preview: (@MainActor (_ item: String) async throws -> PalettePreview?)? = nil) {
        palettes[name] = (query, choose, preview)
    }

    /// Which device a call would reach, for tools whose manifest says `"reach": "paired"`: Sidefolk asks before it
    /// decides whether to ask the person (`sidefolk/paired.check`, D72), with only the argument the manifest's `device`
    /// names (none for a tool that acts on the device in use). Find the device exactly as the tool will, and
    /// answer `.device` only for one the person paired (its key pinned); Sidefolk then puts that id in the parameter the
    /// manifest's `device` names, so the tool must take it there. Honoured for Sidefolk's own extensions only.
    public func paired(_ check: @escaping @MainActor (_ tool: String, _ arguments: Arguments) async -> Paired) {
        pairedCheck = check
    }

    /// What to do when Sidefolk tells the program something without asking (`sidefolk/clipboard.source`).
    public func on(_ method: String, _ handle: @escaping @MainActor (Arguments) -> Void) {
        notices[method] = handle
    }

    /// Work that runs alongside requests for as long as the program runs: with `"background": true` in the manifest,
    /// that is as long as the extension is on (watching the clipboard, holding the Mac awake). It shares the main
    /// actor with requests, so it must await (sleep, I/O) rather than spin.
    public func background(_ work: @escaping @MainActor () async -> Void) {
        backgroundWork = work
    }

    /// Answers every message that has an id until Sidefolk closes stdin. Nothing else may reach stdout.
    public func serve() async {
        if let work = backgroundWork, !Self.isOneCall { Task { await work() } }
        // Read without blocking the main actor, so background work runs between requests.
        for await line in Self.lines() {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let method = message["method"] as? String else { continue }
            guard let id = message["id"] else {
                notices[method]?(Arguments(message["params"] as? [String: Any] ?? [:]))
                continue
            }
            var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
            do {
                reply["result"] = try await answer(method, message["params"] as? [String: Any] ?? [:])
            } catch let unknown as Unknown {
                reply["error"] = ["code": -32601, "message": unknown.what]
            } catch {
                // Reported, not fatal: one bad call shouldn't stop the extension.
                reply["error"] = ["code": -32603, "message": "\(error)"]
            }
            Self.write(reply)
        }
    }

    /// Started for one call that works in a file or folder the person named (`tools.<name>.paths`): it answers that
    /// call and ends, so it runs no background work; the extension's main process does that.
    public static var isOneCall: Bool { ProcessInfo.processInfo.environment["SIDEFOLK_ONE_CALL"] == "1" }

    /// stdin's lines until Sidefolk closes it.
    private static func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            Thread.detachNewThread {
                while let line = readLine(strippingNewline: true) { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    private struct Unknown: Error {
        let what: String
    }

    private func answer(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        // Sidefolk says the person's language with each request (D76); what this request answers is in it.
        Language.use(params["language"] as? String)
        switch method {
        case "initialize":
            return ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18", "capabilities": ["tools": [:]],
                    "serverInfo": ["name": name, "version": version]]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": tools.map { ["name": $0.name, "title": $0.title, "description": $0.description, "inputSchema": $0.input] }]
        case "tools/call":
            let called = params["name"] as? String ?? ""
            guard let tool = tools.first(where: { $0.name == called }) else { return Self.text("Unknown tool: \(called)", error: true) }
            do {
                return Self.text(try await tool.run(Arguments(params["arguments"] as? [String: Any] ?? [:])), error: false)
            } catch let problem as Problem {
                return Self.text(problem.message, error: true)
            }
        case "sidefolk/watch.check":
            let watcher = params["watcher"] as? String ?? ""
            guard let check = watchers[watcher] else { throw Unknown(what: "Unknown watcher: \(watcher)") }
            let result = try await check(Arguments(params["config"] as? [String: Any] ?? [:]), params["state"] as? [String: Any] ?? [:])
            return ["triggered": result.triggered, "state": result.state, "summary": result.summary]
        case "sidefolk/page.render":
            let page = params["page"] as? String ?? ""
            guard let render = pages[page] else { throw Unknown(what: "Unknown page: \(page)") }
            return ["page": try await render(Arguments(params)).json]
        case "sidefolk/palette.query":
            let name = params["palette"] as? String ?? ""
            guard let palette = palettes[name] else { throw Unknown(what: "Unknown palette: \(name)") }
            return try await palette.query(params["query"] as? String ?? "").json
        case "sidefolk/palette.choose":
            let name = params["palette"] as? String ?? ""
            guard let palette = palettes[name] else { throw Unknown(what: "Unknown palette: \(name)") }
            return try await palette.choose(params["item"] as? String ?? "", params["action"] as? String ?? "choose").json
        case "sidefolk/palette.preview":
            let name = params["palette"] as? String ?? ""
            guard let palette = palettes[name], let preview = palette.preview else { throw Unknown(what: "No preview in palette: \(name)") }
            return try await preview(params["item"] as? String ?? "")?.json ?? [:]
        case "sidefolk/paired.check":
            guard let check = pairedCheck else { return ["paired": false] }
            switch await check(params["tool"] as? String ?? "", Arguments(params["arguments"] as? [String: Any] ?? [:])) {
            case .device(let id): return ["paired": true, "device": id]
            case .nothing: return ["paired": true]
            case .unpaired: return ["paired": false]
            }
        default:
            throw Unknown(what: "Method not found: \(method)")
        }
    }

    /// A message to Sidefolk that needs no answer. It acts on two: `sidefolk/nudge` (with the power permission) moves
    /// the pointer by nothing, so apps that watch for activity see some (D63); `sidefolk/clipboard.source` (with the
    /// clipboard permission), sent when the clipboard just changed, is answered with the same notice naming the app
    /// in front (`app`, its bundle id, and `name`), once per copy.
    public func send(_ method: String, _ params: [String: Any] = [:]) {
        Self.write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private static func text(_ text: String, error: Bool) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if error { result["isError"] = true }
        return result
    }

    private static func write(_ reply: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

/// Where a call would go, as `paired` answers it: a device the person paired (by its id), no device at all (stopping
/// what isn't running), or anything else: a device not paired, or one the program can't tell.
public enum Paired: Equatable {
    case device(String)
    case nothing
    case unpaired
}

/// Something the model should read and can act on, returned as an error result instead of an answer.
public struct Problem: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// What a watcher check found: whether to tell the person now, what to remember for the next check, and one line.
public struct Check {
    public var triggered: Bool
    public var state: [String: Any]
    public var summary: String

    public init(triggered: Bool, state: [String: Any] = [:], summary: String) {
        self.triggered = triggered
        self.state = state
        self.summary = summary
    }
}

/// A call's arguments as JSON gave them, read by type.
public struct Arguments {
    public let values: [String: Any]

    public init(_ values: [String: Any]) { self.values = values }

    public func string(_ key: String) -> String? {
        (values[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func int(_ key: String) -> Int? {
        guard let number = values[key] as? NSNumber, !Self.isBool(number) else { return nil }
        return number.intValue
    }

    public func double(_ key: String) -> Double? {
        guard let number = values[key] as? NSNumber, !Self.isBool(number) else { return nil }
        return number.doubleValue
    }

    public func bool(_ key: String) -> Bool? {
        guard let number = values[key] as? NSNumber, Self.isBool(number) else { return nil }
        return number.boolValue
    }

    public func strings(_ key: String) -> [String] {
        (values[key] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// A string that must be there: a clear problem when it isn't.
    public func required(_ key: String) throws -> String {
        guard let value = string(key) else { throw Problem(L("“{key}” is missing.", ["key": key])) }
        return value
    }

    private static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}
