import Foundation

/// `attention.set`: Open, Focus or Quiet, always with an end for the last two, so nothing is left silenced by a job that forgot (D127).
struct AttentionSetTool: Tool {
    static let name = "attention.set"

    let settings: SettingsStore
    let attention: AttentionCenter

    var spec: ToolSpec {
        ToolSpec(
            name: Self.name, title: String(localized: "Set Focus or Quiet", comment: "A tool: how much may reach the person right now"),
            description: "Sets how much may reach the person: open (everything), focus (holds whispers) or quiet (only urgent things), for some minutes.",
            inputSchema: Schema.object([
                "mode": ["type": "string", "enum": ["open", "focus", "quiet"], "description": "How much may reach them."],
                "minutes": Schema.integer("For how long, 1 to 1440. Needed for focus and quiet."),
            ], required: ["mode"]),
            risk: .medium, capabilities: [.system], category: .system, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String {
        let minutes = input["minutes"]?.intValue ?? 0
        switch input.string("mode") {
        case "focus": return String(localized: "Focus for \(minutes) minutes", comment: "A tool's row")
        case "quiet": return String(localized: "Quiet for \(minutes) minutes", comment: "A tool's row")
        default: return String(localized: "Open to everything", comment: "A tool's row: Focus and Quiet end")
        }
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let mode = input.string("mode") ?? ""
        guard ["open", "focus", "quiet"].contains(mode) else { throw ToolError.invalidInput("“mode” is open, focus or quiet.") }
        let minutes = input["minutes"]?.intValue ?? 0
        guard mode == "open" || (1...1440).contains(minutes) else { throw ToolError.invalidInput("“minutes” is 1 to 1440.") }
        let until = mode == "open" ? nil : Date().addingTimeInterval(Double(minutes) * 60)
        await settings.update {
            $0.quietUntil = mode == "quiet" ? until : nil
            $0.focusUntil = mode == "focus" ? until : nil
        }
        await attention.update {
            $0.quiet = mode == "quiet"
            $0.focus = mode == "focus"
        }
        return ToolResult(text: summary(for: input))
    }
}
