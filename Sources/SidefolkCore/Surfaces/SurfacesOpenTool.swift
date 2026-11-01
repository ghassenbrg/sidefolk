import Foundation

/// `surfaces.open`: opens a surface an extension declares (D99), a panel or an overlay beside the companion. It only
/// shows what the extension's own pack and data draw, framed with its name, so it needs no approval; it is a tool so the
/// person's words, the menus and the AI all reach it the same way, audited.
struct SurfacesOpenTool: Tool {
    let events: EventBus
    let shelf: SurfaceShelf

    var spec: ToolSpec {
        let offered = shelf.all.filter(\.ai).map { "\($0.id) (\($0.title))" }
        return ToolSpec(
            name: "surfaces.open", title: String(localized: "Open an extension's panel", comment: "A tool: an extension's panel or overlay beside the companion"),
            description: """
                Opens a panel or an overlay an extension draws beside the companion, framed with its name. Use it when the user \
                asks for what it does; the extension runs it by itself once open. Surfaces: \(offered.joined(separator: "; ")).
                """,
            inputSchema: Schema.object(["surface": Schema.string("extension-id/surface-name, from the list.")], required: ["surface"]),
            risk: .low, capabilities: [.system], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String {
        find(input).map { String(localized: "Open \($0.title)", comment: "Opening an extension's panel: “Open Cups”") }
            ?? String(localized: "Open an extension's panel", comment: "A tool: an extension's panel or overlay beside the companion")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    private func find(_ input: JSONValue) -> SurfaceInfo? { input.string("surface").flatMap { id in shelf.all.first { $0.id == id } } }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        // The AI opening one waits for a click, and only one the extension offers it (D75's rule); the person's words open any.
        let person = context.caller == .user
        guard let info = find(input), person || info.ai else {
            throw ToolError.invalidInput(String(localized: "There's no such panel. They are listed in this tool's description.", comment: "surfaces.open with an unknown name"))
        }
        events.publish(.surface(SurfaceRequest(info: info, focus: person)))
        return ToolResult(text: "Opened \(info.title) from \(info.extensionName) beside the companion. Say it in a few words.",
                          card: ResultCard(kind: .info, title: String(localized: "Open \(info.title)", comment: "Opening an extension's panel: “Open Cups”")))
    }
}

extension IntentParser {
    /// A sentence a surface says opens it, as for games (D75): right away and without AI; two extensions claiming one go to the AI.
    func surface(_ command: String) -> ParsedIntent? {
        let found = surfaces.filter { $0.say.contains(where: { (try? CommandSentence($0))?.match(command) != nil }) }
        guard let info = found.first, Set(found.map(\.extensionId)).count == 1 else { return nil }
        return ParsedIntent(intent: .surface(id: info.id),
                            hint: ParsedIntent.hint(String(localized: "Open \(info.title)", comment: "Opening an extension's panel: “Open Cups”")))
    }
}
