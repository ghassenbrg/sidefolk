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

    /// A page the manifest declares (`pages.<name>`): what it shows now. The arguments carry `language`, the
    /// person's (`en`, `fr`, `ar`), for an extension that speaks it.
    public func page(_ name: String, render: @escaping @MainActor (Arguments) async throws -> Page) {
        pages[name] = render
    }

    /// Answers every message that has an id until Sidefolk closes stdin. Nothing else may reach stdout.
    public func serve() async {
        while let line = readLine(strippingNewline: true) {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = message["id"], let method = message["method"] as? String else { continue }
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

    private struct Unknown: Error {
        let what: String
    }

    private func answer(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
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
        default:
            throw Unknown(what: "Method not found: \(method)")
        }
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
        guard let value = string(key) else { throw Problem("“\(key)” is missing.") }
        return value
    }

    private static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}
