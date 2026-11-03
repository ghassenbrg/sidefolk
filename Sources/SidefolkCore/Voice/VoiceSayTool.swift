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
        // Whose words these are, when they aren't the companion's: a voice can't carry a name any other way.
        var line = text
        if case .extension(let id) = context.caller {
            line = String(localized: "\(AgentFacingTools.extensionName(id) ?? id) says: \(text)", comment: "Spoken aloud: an extension's name, then its words")
        } else if context.caller.runId?.hasPrefix(AgentRuntime.jobPrefix) == true {
            line = String(localized: "From a job you set up: \(text)", comment: "Spoken aloud: words from a job an extension handed the companion")
        }
        events.publish(.speak(line))
        // Whether it's heard is the voice's to say: replies off, a call, the person speaking.
        return ToolResult(text: "Asked to say it aloud.")
    }
}
