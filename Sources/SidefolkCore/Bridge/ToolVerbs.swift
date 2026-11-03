import Foundation

/// `sidefolk notify`, `ask`, `remind`, `note`, `tools` and `call`: Sidefolk's tools for scripts and shells that don't speak
/// MCP. They are another agent's tools by another door: every one goes to the app as an external client, so through
/// `ExternalToolGateway`, Guard and the audit trail, and `call` reaches exactly what `sidefolk mcp` does (T4). English, like
/// the rest of the command (STATUS, Languages).
public enum ToolVerbs {
    public static let verbs: Set<String> = ["notify", "ask", "remind", "note", "tools", "call"]
    /// What a script sees in `$?`. With `--options`, `ask` exits with the chosen one's place, from 0.
    public static let noAnswer: Int32 = 10
    public static let failed: Int32 = 11
    public static let unavailable: Int32 = 69

    static let client = "sidefolk-cli"

    public enum Request: Equatable, Sendable {
        case call(tool: String, input: JSONValue)
        case ask(input: JSONValue, options: [String])
        case list(json: Bool)
    }

    public struct Output: Equatable, Sendable {
        public var out = ""
        public var error = ""
        public var code: Int32 = 0
    }

    public struct UsageError: Error, Equatable {
        public let message: String
    }

    /// `arguments` starts at the verb.
    public static func parse(_ arguments: [String]) -> Result<Request, UsageError> {
        var words = Words(Array(arguments.dropFirst()))
        do {
            switch arguments.first {
            case "notify":
                let body = try words.value("--body"), attention = words.flag("--attention")
                var input: [String: JSONValue] = ["title": .string(try words.only("sidefolk notify \"title\" [--body text] [--attention]"))]
                if let body { input["body"] = .string(body) }
                if attention { input["level"] = "attention" }
                return .success(.call(tool: "notify.user", input: .object(input)))
            case "ask":
                let options = try words.value("--options")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                let timeout = try words.value("--timeout")
                var input: [String: JSONValue] = ["question": .string(try words.only("sidefolk ask \"question\" [--options a,b] [--timeout seconds]"))]
                if !options.isEmpty { input["options"] = .array(options.map { .string($0) }) }
                if let timeout {
                    guard let seconds = Int(timeout) else { throw UsageError(message: "--timeout takes a number of seconds.") }
                    input["timeout_seconds"] = .number(Double(seconds))
                }
                return .success(.ask(input: .object(input), options: options))
            case "remind":
                let usage = "sidefolk remind \"title\" --at \"in 20 minutes\" [--notes text] [--gentle]"
                guard let when = try words.value("--at") else { throw UsageError(message: "usage: \(usage)") }
                let notes = try words.value("--notes"), gentle = words.flag("--gentle")
                var input: [String: JSONValue] = ["title": .string(try words.only(usage)), "when": .string(when)]
                if let notes { input["notes"] = .string(notes) }
                if gentle { input["level"] = "gentle" }
                return .success(.call(tool: "reminders.create", input: .object(input)))
            case "note":
                let kind = words.flag("--task") ? "task" : words.flag("--idea") ? "idea" : words.flag("--link") ? "link" : nil
                let collection = try words.value("--collection"), due = try words.value("--due"), remind = try words.value("--remind")
                let tags = try words.values("--tag")
                var input: [String: JSONValue] = ["text": .string(try words.only("sidefolk note \"text\" [--task|--idea|--link] [--collection name] [--tag t]… [--due when] [--remind when]"))]
                if let kind { input["kind"] = .string(kind) }
                if let collection { input["collection"] = .string(collection) }
                if let due { input["due"] = .string(due) }
                if let remind { input["remind"] = .string(remind) }
                if !tags.isEmpty { input["tags"] = .array(tags.map { .string($0) }) }
                return .success(.call(tool: "notes.save", input: .object(input)))
            case "tools":
                let json = words.flag("--json")
                guard words.isEmpty else { throw UsageError(message: "usage: sidefolk tools [--json]") }
                return .success(.list(json: json))
            case "call":
                guard (1...2).contains(words.count), let tool = words.first else { throw UsageError(message: "usage: sidefolk call <tool> ['{\"json\": \"arguments\"}']") }
                guard words.count == 2 else { return .success(.call(tool: tool, input: .object([:]))) }
                guard let input = try? JSONValue.parse(words.last ?? ""), input.objectValue != nil else {
                    throw UsageError(message: "The arguments must be one JSON object.")
                }
                return .success(.call(tool: tool, input: input))
            default:
                throw UsageError(message: "unknown command \(arguments.first ?? "").")
            }
        } catch let usage as UsageError {
            return .failure(usage)
        } catch {
            return .failure(UsageError(message: "\(error)"))
        }
    }

    public static func run(_ request: Request, paths: SidefolkPaths) async -> Output {
        do {
            let client = try await BridgeClient.connect(socketPath: paths.socket.path, client: Self.client)
            defer { client.close() }
            switch request {
            case .list(let json):
                let reply = try await client.call(BridgeProtocol.Method.toolsList.rawValue, .object([:]), timeout: 10)
                let tools = reply["tools"]?.arrayValue ?? []
                if json { return Output(out: reply.jsonString) }
                return Output(out: tools.compactMap { tool in
                    tool.string("name").map { "\($0.replacingOccurrences(of: ".", with: "_"))\t\(tool.string("title") ?? "")" }
                }.joined(separator: "\n"))
            case .call(let tool, let input):
                let (text, isError) = try await call(client, tool, input)
                return isError ? Output(error: text, code: failed) : Output(out: text)
            case .ask(let input, let options):
                let (text, isError) = try await call(client, "ask.user", input)
                if isError { return Output(error: text, code: failed) }
                if text == "no answer" { return Output(error: text, code: noAnswer) }
                return Output(out: text, code: Int32(options.firstIndex(of: text) ?? 0))
            }
        } catch BridgeError.notRunning {
            return Output(error: MCPStdioBridge.notRunningMessage, code: unavailable)
        } catch {
            return Output(error: "Sidefolk isn't reachable: \(error)", code: unavailable)
        }
    }

    /// A call may wait for the person, as long as their question or card lasts.
    private static func call(_ client: BridgeClient, _ tool: String, _ input: JSONValue) async throws -> (String, Bool) {
        let reply = try await client.call(BridgeProtocol.Method.toolsCall.rawValue, ["name": .string(tool), "arguments": input], timeout: nil)
        return (reply.string("text") ?? "", reply["isError"]?.boolValue ?? false)
    }

    /// Takes flags out of the arguments, so what's left is the text.
    private struct Words {
        private var rest: [String]
        init(_ words: [String]) { rest = words }

        var isEmpty: Bool { rest.isEmpty }
        var count: Int { rest.count }
        var first: String? { rest.first }
        var last: String? { rest.last }

        mutating func flag(_ name: String) -> Bool {
            guard let at = rest.firstIndex(of: name) else { return false }
            rest.remove(at: at)
            return true
        }

        mutating func value(_ name: String) throws -> String? {
            guard let at = rest.firstIndex(of: name) else { return nil }
            guard at + 1 < rest.count else { throw UsageError(message: "\(name) needs a value.") }
            let value = rest[at + 1]
            rest.removeSubrange(at...(at + 1))
            return value
        }

        mutating func values(_ name: String) throws -> [String] {
            var found: [String] = []
            while let one = try value(name) { found.append(one) }
            return found
        }

        /// The one piece of text left.
        func only(_ usage: String) throws -> String {
            guard rest.count == 1, let text = rest.first, !text.hasPrefix("--") else { throw UsageError(message: "usage: \(usage)") }
            return text
        }
    }
}
