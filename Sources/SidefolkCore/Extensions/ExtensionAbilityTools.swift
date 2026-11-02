import Foundation

/// `extensions.setting` (D100): changes a setting an extension declared. The person's click on its row reaches it, and the
/// extension itself for its own settings; never a model, another agent or another extension: its settings' words are its
/// author's, and D24 keeps those out of what a model is offered. An extension that wants the AI to change something offers a
/// tool of its own.
struct ExtensionSettingTool: Tool {
    static let name = "extensions.setting"

    let host: ExtensionHost

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Change an extension's setting", comment: "A tool: a setting an extension declared"),
                 description: "Changes a setting an extension declared.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "key": Schema.string("The setting's key."),
                                             "value": ["description": "Its new value."]], required: ["extension", "key", "value"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        let id = input.string("extension") ?? "", key = input.string("key") ?? ""
        guard var row = host.shelf.settings.first(where: { $0.extensionId == id && $0.key == key }) else {
            return String(localized: "Change an extension's setting", comment: "A tool: a setting an extension declared")
        }
        if let value = input["value"] { row.value = value }
        return "\(ExtensionText.line(row.title, characters: 60)): \(row.valueWords)"
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    /// Only the person, or the extension for itself.
    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        let id = input.string("extension")
        switch context.caller {
        case .user: return nil
        case .extension(let own), .command(let own): return own == id ? nil : "An extension can change only its own settings."
        case .agent, .routine, .external: return "This is for the person's own click."
        }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("extension"), let key = input.string("key"), let value = input["value"] else {
            throw ToolError.invalidInput(String(localized: "There's no such setting."))
        }
        let row = try await host.setSetting(extensionId: id, key: key, value: value)
        let said = "\(ExtensionText.line(row.title, characters: 60)): \(row.valueWords)"
        return ToolResult(text: "Changed.", card: ResultCard(kind: .info, title: said), untrusted: true)
    }
}

/// `extensions.activity` (D100): one row in History from an extension's surface or game, in its words, marked as its own. Only the
/// extension reaches it, for itself; a model never does, and the words are cleaned and clipped like a page's.
struct ExtensionActivityTool: Tool {
    static let name = "extensions.activity"

    let shelfName: @Sendable (String) -> String?

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Note in History", comment: "A tool: an extension adds one row to History"),
                 description: "Adds one row to History for an extension.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "text": Schema.string("What happened."),
                                             "key": Schema.string("Its own name for what this was about."), "result": Schema.string("How it ended.")],
                                            required: ["extension", "text"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: false, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        let text = ExtensionText.line(input.string("text") ?? "", characters: 120)
        guard let name = input.string("extension").flatMap(shelfName) else { return text }
        return "\(ExtensionText.line(name, characters: 40)): \(text)"
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .extension(let own) = context.caller, own == input.string("extension") { return nil }
        return "Only an extension adds its own rows."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        ToolResult(text: "Noted.", card: ResultCard(kind: .info, title: summary(for: input)), untrusted: true)
    }
}
