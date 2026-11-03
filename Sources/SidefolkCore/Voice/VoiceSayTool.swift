import Foundation

/// `voice.say`: says a line aloud in the Mac's own voice (D127). An extension's words go with its name, as its notices do, and nothing is said in Focus or Quiet.
struct VoiceSayTool: Tool {
    static let name = "voice.say"
    static let longest = 300

    let settings: SettingsStore
    let events: EventBus

    var spec: ToolSpec {
        ToolSpec(
            name: Self.name, title: String(localized: "Say something aloud", comment: "A tool: speaks a line"),
            description: "Says a short line aloud. Nothing is said while the person is in Focus or Quiet.",
            inputSchema: Schema.object(["text": Schema.string("What to say, at most 300 characters.")], required: ["text"]),
            risk: .medium, capabilities: [.system], category: .system, mutates: true)
    }

    func summary(for input: JSONValue) -> String {
        String(localized: "Say aloud: \(ToolFormat.oneLine(ExtensionText.clean(input.string("text") ?? ""), Self.longest))", comment: "A tool's row: “Say aloud: time to stretch”")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let text = ToolFormat.oneLine(ExtensionText.clean(input.string("text") ?? ""), Self.longest)
        guard !text.isEmpty else { throw ToolError.invalidInput("Say what to say.") }
        let now = context.now, current = settings.current
        guard !current.isQuiet(at: now), !current.isFocused(at: now) else { return ToolResult(text: "Not said: the person is in Focus or Quiet.") }
        // Their word on how far it may interrupt counts for a voice as for a notice (D88).
        guard case .deliver = current.interruptions.route(AttentionItem(level: .gentle, source: AgentFacingTools.source(for: context.caller), title: "")) else {
            return ToolResult(text: "Not said: the person keeps this off their desktop.")
        }
        // Whose words these are, when they aren't the companion's: a voice can't carry a name any other way.
        var line = text
        let owner = context.caller.runId.flatMap(AgentRuntime.jobOwner(of:))
        let speaker = if case .extension(let id) = context.caller { id } else { owner }
        if let speaker {
            line = String(localized: "\(AgentFacingTools.extensionName(speaker) ?? speaker) says: \(text)", comment: "Spoken aloud: an extension's name, then its words")
        }
        events.publish(.speak(line))
        // Whether it's heard is the voice's to say: replies off, a call, the person speaking.
        return ToolResult(text: "Asked to say it aloud.")
    }
}
