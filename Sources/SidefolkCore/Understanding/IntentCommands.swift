import Foundation

/// A sentence that matched one extension's command (D50), ready to run without the AI.
public struct ExtensionCommandCall: Sendable, Hashable {
    /// The tool's name in the registry (`ext.world-clock.current_time`).
    public var tool: String
    public var input: JSONValue
    public var extensionId: String
    /// The sentence as the person typed or said it: an address in it counts as typed (SECURITY T1).
    public var said: String

    public init(tool: String, input: JSONValue, extensionId: String, said: String) {
        self.tool = tool
        self.input = input
        self.extensionId = extensionId
        self.said = said
    }
}

extension IntentParser {
    /// The extension command the whole sentence is, after every core intent had its turn (D50). Sentences two
    /// extensions both claim go to the AI: guessing would hand someone's words to the wrong program. Within one
    /// extension the first tool in name order wins, so the author decides by how they write them.
    func extensionCommand(_ command: String) -> ParsedIntent? {
        var found: [(tool: ExtensionTool, input: JSONValue)] = []
        for tool in commandTools.sorted(by: { $0.spec.name < $1.spec.name }) {
            if let input = tool.commands?.input(for: command) { found.append((tool, Self.fitting(input, to: tool.spec.inputSchema))) }
        }
        guard let first = found.first, Set(found.map(\.tool.extensionId)).count == 1 else { return nil }
        let tool = first.tool
        let name = (tool.firstParty ? BuiltInExtensionWords.name(tool.extensionId) : nil) ?? tool.extensionName
        // A built-in says what it will do ("The time in Tokyo"); anyone else's tool is named by its title.
        let what = tool.firstParty ? tool.summary(for: first.input) : tool.spec.title
        let call = ExtensionCommandCall(tool: tool.spec.name, input: first.input, extensionId: tool.extensionId, said: command)
        return ParsedIntent(intent: .extensionCommand(call), hint: ParsedIntent.hint(ExtensionText.line(name, characters: 40), what.clipped(60)))
    }

    /// A slot's number where the tool wants text ("timestamp 1730000000"), or its text where it wants a number: the
    /// author wrote the sentence, the program's schema says the type.
    static func fitting(_ input: JSONValue, to schema: JSONValue) -> JSONValue {
        guard case .object(var fields) = input, let properties = schema["properties"]?.objectValue else { return input }
        func fit(_ value: JSONValue, _ type: String?) -> JSONValue {
            switch (value, type) {
            case (.number(let n), "string"?): return .string(n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n))
            case (.string(let s), "number"?), (.string(let s), "integer"?): return Double(s).map { .number($0) } ?? value
            default: return value
            }
        }
        for (key, value) in fields {
            let property = properties[key]
            if case .array(let items) = value {
                let itemType = property?["items"]?["type"]?.stringValue
                fields[key] = .array(items.map { fit($0, itemType) })
            } else {
                fields[key] = fit(value, property?["type"]?.stringValue)
            }
        }
        return .object(fields)
    }
}
