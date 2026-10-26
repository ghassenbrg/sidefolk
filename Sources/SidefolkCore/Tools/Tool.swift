import Foundation

public enum Risk: String, Codable, Sendable, CaseIterable, Comparable {
    /// Reads Sidefolk data or creates Sidefolk-owned, undoable things.
    case low
    /// Changes things outside Sidefolk or reveals private data; asked once, may be granted "always".
    case medium
    /// Destructive, irreversible, or runs code; asked every time.
    case high

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// What a tool needs. Settings can switch whole capabilities off; extensions declare them.
public enum Capability: String, Codable, Sendable, CaseIterable {
    case notebook, memory, time, watch, clipboard, apps, network, shell, agents, extensions, system
    case filesRead = "files.read"
    case filesWrite = "files.write"
    /// Reading the Mac's own apps (Apple Notes, Reminders) through Apple Events (DECISIONS D38).
    case macApps = "mac.apps"
}

/// Drives which prop the companion holds and which folk may cameo.
public enum ToolCategory: String, Codable, Sendable, CaseIterable {
    case notes, memory, time, watch, files, web, system, agents, extensions
}

public struct ToolSpec: Sendable, Hashable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: JSONValue
    public var risk: Risk
    public var capabilities: Set<Capability>
    public var category: ToolCategory
    public var mutates: Bool
    /// Offered to external agents through the Sidefolk MCP server.
    public var external: Bool
    /// How long one call may run when it needs longer than the caller's usual limit (cloning a repository).
    public var timeout: TimeInterval?

    public init(
        name: String, title: String, description: String, inputSchema: JSONValue, risk: Risk,
        capabilities: Set<Capability>, category: ToolCategory, mutates: Bool, external: Bool = false,
        timeout: TimeInterval? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.risk = risk
        self.capabilities = capabilities
        self.category = category
        self.mutates = mutates
        self.external = external
        self.timeout = timeout
    }

    /// Name safe for model APIs (letters, digits, underscore, dash).
    public var modelName: String { name.replacingOccurrences(of: ".", with: "_") }
}

/// Who is asking. Trust differs: the user's own click outranks an agent, which outranks content.
public enum Caller: Sendable, Hashable, CustomStringConvertible {
    /// A direct user action: a slash command, a button in Sidefolk.
    case user
    /// Sidefolk's own agent answering the user.
    case agent(runId: String)
    /// A scheduled routine running unattended.
    case routine(id: String)
    /// Another AI agent connected through the Sidefolk MCP server.
    case external(client: String)
    /// An extension (e.g. its watcher asking to notify).
    case `extension`(id: String)

    public var kind: String {
        switch self {
        case .user: "user"
        case .agent: "agent"
        case .routine: "routine"
        case .external: "external"
        case .extension: "extension"
        }
    }

    public var description: String {
        switch self {
        case .user: "you"
        case .agent: "Sidefolk"
        case .routine: "a routine"
        case .external(let client): client
        case .extension(let id): id
        }
    }

    public var runId: String? { if case .agent(let id) = self { return id } else { return nil } }
}

/// What a call would touch, so Guard can check boundaries and scope "always allow" grants.
public struct ToolScope: Sendable, Hashable {
    public var readPaths: [String] = []
    public var writePaths: [String] = []
    public var command: String?
    public var url: String?
    public var extensionId: String?
    /// Text the user must read in full before approving (e.g. a new skill); never grantable "always".
    public var text: String?

    public init(readPaths: [String] = [], writePaths: [String] = [], command: String? = nil, url: String? = nil,
                extensionId: String? = nil, text: String? = nil) {
        self.readPaths = readPaths
        self.writePaths = writePaths
        self.command = command
        self.url = url
        self.extensionId = extensionId
        self.text = text
    }

    public static let none = ToolScope()

    /// The folder a command runs in: tools that take a working folder list it first in `readPaths`.
    public var commandFolder: String? { command == nil ? nil : readPaths.first }
}

/// A compact, presentable result shown in the Ask panel and the Activity log.
public struct ResultCard: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case note, reminder, watcher, memory, file, web, list, info, collection, extensionResult }
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var detail: String?
    public var refId: String?
    public var url: String?
    /// For notebook items: note, idea, task or link, so the card can show the right icon.
    public var itemKind: NotebookItem.Kind?

    public init(kind: Kind, title: String, subtitle: String? = nil, detail: String? = nil, refId: String? = nil, url: String? = nil,
                itemKind: NotebookItem.Kind? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.refId = refId
        self.url = url
        self.itemKind = itemKind
    }
}

public struct UndoAction: Sendable {
    public var label: String
    public var perform: @Sendable () async throws -> Void
    public init(label: String, perform: @escaping @Sendable () async throws -> Void) {
        self.label = label
        self.perform = perform
    }
}

public struct ToolResult: Sendable {
    /// What the model reads.
    public var text: String
    public var card: ResultCard?
    public var undo: UndoAction?
    /// The text contains content from outside the user's own words (web, files, clipboard, extensions).
    public var untrusted: Bool
    /// The tool ran and reported a failure in its own words (an extension's `isError`). The text is
    /// still shown to the model, but the call doesn't count as done.
    public var isError: Bool

    public init(text: String, card: ResultCard? = nil, undo: UndoAction? = nil, untrusted: Bool = false, isError: Bool = false) {
        self.text = text
        self.card = card
        self.undo = undo
        self.untrusted = untrusted
        self.isError = isError
    }
}

public struct ToolContext: Sendable {
    public var caller: Caller
    public var now: Date
    /// Untrusted content was in play when this call was made (docs/SECURITY.md T2, T3).
    public var tainted: Bool
    /// The folders Guard let this call use: those the person shared, plus any allowed for this call only.
    public var folders: [GrantedFolder]
    public init(caller: Caller, now: Date, tainted: Bool = false, folders: [GrantedFolder] = []) {
        self.caller = caller
        self.now = now
        self.tainted = tainted
        self.folders = folders
    }

    /// Where something a tool writes came from. Sidefolk's own agent acting in a clean turn acts for
    /// the user ("user:agent"); in a tainted turn its writes stay marked as the agent's, and so does
    /// the user saving an answer such a turn wrote (the words are still the agent's).
    public var provenanceTag: String {
        switch caller {
        case .user: tainted ? "agent" : "user"
        case .agent: tainted ? "agent" : "user:agent"
        case .routine: "routine"
        case .external(let client): "external:\(client)"
        case .extension(let id): "extension:\(id)"
        }
    }
}

public enum ToolError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidInput(String)
    case notFound(String)
    case unavailable(String)

    public var description: String {
        switch self {
        case .invalidInput(let m): "Invalid input: \(m)"
        case .notFound(let m): "Not found: \(m)"
        case .unavailable(let m): m
        }
    }
}

public protocol Tool: Sendable {
    var spec: ToolSpec { get }
    /// One plain-language line for approvals and Activity ("Move 3 files to Downloads/PDFs").
    func summary(for input: JSONValue) -> String
    func scope(for input: JSONValue) -> ToolScope
    /// Why this call can't run at all, decided before Guard asks anything: an approval card for a call
    /// the tool would then refuse is a question with no right answer. Nil lets Guard decide.
    func refusal(for input: JSONValue, context: ToolContext) -> String?
    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult
}

public extension Tool {
    func scope(for input: JSONValue) -> ToolScope { .none }
    func refusal(for input: JSONValue, context: ToolContext) -> String? { nil }
}

/// JSON Schema helpers so tool definitions stay short and consistent.
public enum Schema {
    public static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": false,
        ])
    }

    public static func string(_ description: String, enum values: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": "string", "description": .string(description)]
        if let values { o["enum"] = .array(values.map { .string($0) }) }
        return .object(o)
    }

    public static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": "integer", "description": .string(description)]
        if let minimum { o["minimum"] = .number(Double(minimum)) }
        if let maximum { o["maximum"] = .number(Double(maximum)) }
        return .object(o)
    }

    public static func number(_ description: String) -> JSONValue {
        .object(["type": "number", "description": .string(description)])
    }

    public static func boolean(_ description: String) -> JSONValue {
        .object(["type": "boolean", "description": .string(description)])
    }

    public static func array(_ description: String, items: JSONValue) -> JSONValue {
        .object(["type": "array", "description": .string(description), "items": items])
    }
}
