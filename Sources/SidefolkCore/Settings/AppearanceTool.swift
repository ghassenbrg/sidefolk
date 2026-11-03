import Foundation

/// `appearance.set`: how Sidefolk looks: light or dark, a theme, which companion. Only these (D127, the founder's choice): nothing about trust, connections, the AI or add-ons
/// has a tool, and those stay the person's own, in Settings.
struct AppearanceTool: Tool {
    static let name = "appearance.set"

    let settings: SettingsStore
    let themes: ThemeLibrary
    let installedCompanions: @Sendable () async -> [String]
    let events: EventBus

    var spec: ToolSpec {
        ToolSpec(
            name: Self.name, title: String(localized: "Change how Sidefolk looks", comment: "A tool: light or dark, a theme, which companion"),
            description: "Changes how Sidefolk looks: light or dark, the theme, or which companion is shown. Say only what should change.",
            inputSchema: Schema.object([
                "mode": ["type": "string", "enum": ["system", "light", "dark"], "description": "Light or dark, or follow the Mac."],
                "theme": Schema.string("A theme's id: \(ThemeLibrary.builtInOrder.joined(separator: ", ")), or an installed one's."),
                "companion": Schema.string("A companion's name: mochi, spark, or one the person installed."),
            ]),
            risk: .medium, capabilities: [.system], category: .system, mutates: true)
    }

    func summary(for input: JSONValue) -> String {
        let said = ["mode", "theme", "companion"].compactMap { input.string($0).map { ToolFormat.oneLine(ExtensionText.clean($0), 60) } }
        return String(localized: "Change how Sidefolk looks: \(said.joined(separator: ", "))", comment: "A tool's row; what changes: “dark, harbor”")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let mode = try input.string("mode").map { raw -> AppAppearance in
            guard let mode = AppAppearance(rawValue: raw) else { throw ToolError.invalidInput("“mode” is system, light or dark.") }
            return mode
        }
        // By its name or exact id, as the companion picks one. Only then an id retired since, saved in a plan long ago: a word that was once an id can name another theme now.
        let theme = try input.string("theme").map { raw -> String in
            let wanted = raw.lowercased(), all = themes.all()
            let successor = ThemeSuccession.retired[raw]?.successor
            guard let found = all.first(where: { $0.tokens.name.lowercased() == wanted || $0.id == raw }) ?? all.first(where: { $0.id == successor }) else {
                throw ToolError.invalidInput("There's no theme called “\(raw)” on this Mac.")
            }
            return found.id
        }
        var companion: CompanionChoice?
        if let raw = input.string("companion") {
            guard let choice = CompanionChoice(rawValue: raw.lowercased()), !choice.isRetired else { throw ToolError.invalidInput("There's no companion called “\(raw)”.") }
            if choice != .mochi, choice != .spark, !(await installedCompanions().contains(choice.rawValue)) { throw ToolError.invalidInput("“\(raw)” isn't installed.") }
            companion = choice
        }
        let chosen = companion
        // What the person made or followed themselves isn't an extension's to take off: there's no undo but picking it again.
        if case .extension = context.caller {
            let current = settings.current
            if chosen != nil, current.customCompanion != nil || current.localCompanion != nil { throw ToolError.unavailable("You're wearing a companion of your own, so an extension leaves it alone.") }
            if theme != nil, current.themeFolder != nil { throw ToolError.unavailable("You're following a theme of your own, so an extension leaves it alone.") }
        }
        guard mode != nil || theme != nil || chosen != nil else { throw ToolError.invalidInput("Say what should change: mode, theme or companion.") }
        await settings.update {
            if let mode { $0.appearance = mode }
            if let theme { $0.theme = theme; $0.themeFolder = nil }
            if let chosen { $0.choose(chosen) }
        }
        events.publish(.settingsChangedByTool)
        return ToolResult(text: summary(for: input))
    }
}
