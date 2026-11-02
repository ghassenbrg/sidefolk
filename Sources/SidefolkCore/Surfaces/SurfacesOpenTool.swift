import Foundation

/// `surfaces.open`: opens a surface an extension declares (D99), a panel or an overlay beside the companion. It only
/// shows what the extension's own pack and data draw, framed with its name, so it needs no approval; it is a tool so the
/// person's words, the menus and the AI all reach it the same way, audited.
struct SurfacesOpenTool: Tool {
    static let name = "surfaces.open"

    let events: EventBus
    let shelf: SurfaceShelf

    var spec: ToolSpec {
        let offered = shelf.all.filter(\.ai).map { info -> String in
            let choices = info.arguments.keys.sorted().map { "\($0): \((info.arguments[$0] ?? []).joined(separator: "|"))" }
            return "\(info.id) (\(info.title)\(choices.isEmpty ? "" : "; \(choices.joined(separator: ", "))"))"
        }
        return ToolSpec(
            name: Self.name, title: String(localized: "Open an extension's panel", comment: "A tool: an extension's panel or overlay beside the companion"),
            description: """
                Opens a panel or an overlay an extension draws beside the companion, framed with its name. Use it when the user \
                asks for what it does; the extension runs it by itself once open. Surfaces: \(offered.joined(separator: "; ")).
                """,
            inputSchema: Schema.object([
                "surface": Schema.string("extension-id/surface-name, from the list."),
                "arguments": ["type": "object", "description": "What the surface should start with, if the user said: only the names and values its entry lists."],
                // A tool's reply says who asked, as the extension (D100); nobody else's is read.
                "focus": ["type": "boolean", "description": "Leave this out."],
            ], required: ["surface"]),
            risk: .low, capabilities: [.system], category: .system, mutates: false)
    }

    /// With what goes to the extension, so a card and History show it.
    func summary(for input: JSONValue) -> String {
        guard let info = find(input) else { return String(localized: "Open an extension's panel", comment: "A tool: an extension's panel or overlay beside the companion") }
        let open = String(localized: "Open \(info.title)", comment: "Opening an extension's panel: “Open Cups”")
        let given = Self.arguments(input["arguments"]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.stringValue ?? $0.value.jsonString)" }
        return given.isEmpty ? open : "\(open) · \(given.joined(separator: ", "))"
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    /// What goes to the extension with `surface.open`: at most twelve small plain values under small names; anything else stays out.
    static func arguments(_ j: JSONValue?) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in (j?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }).prefix(12) {
            guard GameBoard.token(.string(key)) != nil else { continue }
            switch value {
            case .string(let text):
                let clean = ExtensionText.clip(ExtensionText.clean(text), 200)
                if !clean.isEmpty { out[key] = .string(clean) }
            case .number(let n) where n.isFinite: out[key] = value
            case .bool: out[key] = value
            default: continue
            }
        }
        return out
    }

    /// What a model's call may pass: only names the manifest lists, with one of the values it lists, or a yes or no it lists as
    /// such. A model's words could be steered by what it read (T2, T40), and the extension may send what it hears anywhere, so no
    /// free text and no numbers go this way; a tool the extension declares can take those, and Guard weighs that call.
    static func offered(_ given: [String: JSONValue], by info: SurfaceInfo) -> [String: JSONValue] {
        given.filter { key, value in
            guard let allowed = info.arguments[key] else { return false }
            switch value {
            case .string(let text): return allowed.contains(text)
            case .bool(let on): return allowed.contains(on ? "true" : "false")
            default: return false
            }
        }
    }

    private func find(_ input: JSONValue) -> SurfaceInfo? { input.string("surface").flatMap { id in shelf.all.first { $0.id == id } } }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        // The AI opening one waits for a click, and only one the extension offers it (D75's rule); the person's words open any,
        // and so does the extension's own command. A tool's reply comes here as the extension, which already judged who asked.
        guard let info = find(input) else { throw Self.noSuchPanel }
        let given = Self.arguments(input["arguments"])
        let request: SurfaceRequest
        switch context.caller {
        case .user:
            request = SurfaceRequest(info: info, focus: true, arguments: given)
        case .command(let id) where id == info.extensionId:
            request = SurfaceRequest(info: info, focus: true, arguments: given)
        case .extension(let id) where id == info.extensionId:
            request = SurfaceRequest(info: info, focus: input["focus"]?.boolValue ?? false, arguments: given)
        default:
            guard info.ai else { throw Self.noSuchPanel }
            request = SurfaceRequest(info: info, focus: false, arguments: Self.offered(given, by: info))
        }
        events.publish(.surface(request))
        return ToolResult(text: "Opened \(info.title) from \(info.extensionName) beside the companion. Say it in a few words.",
                          card: ResultCard(kind: .info, title: String(localized: "Open \(info.title)", comment: "Opening an extension's panel: “Open Cups”")))
    }
}

private extension SurfacesOpenTool {
    static var noSuchPanel: ToolError {
        ToolError.invalidInput(String(localized: "There's no such panel. They are listed in this tool's description.", comment: "surfaces.open with an unknown name"))
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
