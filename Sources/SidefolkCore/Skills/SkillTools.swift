import Foundation

/// `skills.list`, `skills.load`, `skills.create` and `skills.delete`. None is offered to external agents;
/// `skills.create` also refuses them (and extensions) itself, whatever path a call takes (SECURITY T3, T4).
public enum SkillTools {
    public static func all(_ library: SkillLibrary) -> [any Tool] {
        [ListSkillsTool(library: library), LoadSkillTool(library: library),
         CreateSkillTool(library: library), DeleteSkillTool(library: library)]
    }

    static func source(for caller: Caller) -> String {
        switch caller {
        case .user: "user"
        case .agent: "agent"
        case .routine(let id): "routine:\(id)"
        case .external(let client): "external:\(client)"
        case .extension(let id): "extension:\(id)"
        }
    }
}

struct ListSkillsTool: Tool {
    let library: SkillLibrary
    let spec = ToolSpec(name: "skills.list", title: String(localized: "List skills"),
                        description: "Lists the skills Sidefolk knows: step-by-step instructions for recurring jobs. Load one with skills.load before following it.",
                        inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .agents, mutates: false)

    func summary(for input: JSONValue) -> String { String(localized: "List skills") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let skills = library.index()
        guard !skills.isEmpty else { return ToolResult(text: "No skills yet.") }
        let text = skills.map { "\($0.name): \($0.description)" }.joined(separator: "\n")
        return ToolResult(text: text, card: ResultCard(kind: .list, title: "\(skills.count) skills"),
                          untrusted: skills.contains { !$0.trusted })
    }
}

struct LoadSkillTool: Tool {
    let library: SkillLibrary
    let spec = ToolSpec(name: "skills.load", title: String(localized: "Load a skill"),
                        description: "Returns a skill's instructions so you can follow them.",
                        inputSchema: Schema.object(["name": Schema.string("The skill's name, from skills.list.")], required: ["name"]),
                        risk: .low, capabilities: [], category: .agents, mutates: false)

    func summary(for input: JSONValue) -> String { String(localized: "Load the skill “\(input.string("name") ?? "")”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let name = input.string("name"), let skill = library.skill(named: name) else {
            throw ToolError.notFound(String(localized: "a skill called “\(input.string("name") ?? "")”"))
        }
        var header = "Skill: \(skill.name)\n\(skill.description)"
        if !skill.tools.isEmpty { header += "\nTools it uses: \(skill.tools.joined(separator: ", "))" }
        if skill.model == "smart" { header += "\nThis skill asks for careful, step-by-step thinking." }
        let body = ExtensionText.cap(skill.trusted ? skill.instructions : ExtensionText.clean(skill.instructions), bytes: 20_000)
        return ToolResult(text: header + "\n\n" + body, card: ResultCard(kind: .info, title: skill.name, subtitle: skill.description),
                          untrusted: !skill.trusted)
    }
}

struct CreateSkillTool: Tool {
    let library: SkillLibrary
    let spec = ToolSpec(
        name: "skills.create", title: String(localized: "Create a skill"),
        description: "Saves new step-by-step instructions as a skill for a job the user will ask for again. The user sees the full text before it is saved.",
        inputSchema: Schema.object([
            "name": Schema.string("Short name: lowercase letters, digits and dashes, like weekly-plan."),
            "description": Schema.string("One sentence: what the skill does and when to use it."),
            "instructions": Schema.string("The steps, in Markdown, naming the tools to use."),
        ], required: ["name", "description", "instructions"]),
        risk: .medium, capabilities: [], category: .agents, mutates: true)

    func summary(for input: JSONValue) -> String {
        String(localized: "Create the skill “\(input.string("name") ?? "")”: \(input.string("description") ?? "")")
    }

    /// The approval card shows this verbatim, and an "always" grant can only ever match this exact text.
    func scope(for input: JSONValue) -> ToolScope { ToolScope(text: Self.fullText(input)) }

    static func fullText(_ input: JSONValue) -> String {
        "Skill “\(input["name"]?.stringValue ?? "")”\n\(input["description"]?.stringValue ?? "")\n\n\(input["instructions"]?.stringValue ?? "")"
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        switch context.caller {
        case .external, .extension:
            throw UserFacingError("Only you or Sidefolk itself can create skills.")
        case .user, .agent, .routine:
            break
        }
        let name = input.string("name") ?? ""
        let skill = try library.create(name: name, description: input.string("description") ?? "",
                                       instructions: input["instructions"]?.stringValue ?? "",
                                       source: SkillTools.source(for: context.caller))
        let library = self.library
        let undo = UndoAction(label: String(localized: "Remove the skill “\(name)”")) { try library.delete(name: name) }
        return ToolResult(text: "Saved the skill “\(skill.name)”.", card: ResultCard(kind: .info, title: skill.name, subtitle: String(localized: "New skill")),
                          undo: undo)
    }
}

struct DeleteSkillTool: Tool {
    let library: SkillLibrary
    let spec = ToolSpec(name: "skills.delete", title: String(localized: "Delete a skill"),
                        description: "Moves a skill the user or Sidefolk created to the Trash. Built-in skills can't be deleted.",
                        inputSchema: Schema.object(["name": Schema.string("The skill's name.")], required: ["name"]),
                        risk: .medium, capabilities: [], category: .agents, mutates: true)

    func summary(for input: JSONValue) -> String { String(localized: "Move the skill “\(input.string("name") ?? "")” to the Trash") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        switch context.caller {
        case .external, .extension:
            throw UserFacingError("Only you or Sidefolk itself can delete skills.")
        case .user, .agent, .routine:
            break
        }
        let name = input.string("name") ?? ""
        let trashed = try library.delete(name: name)
        let library = self.library
        let undo = trashed.map { url in UndoAction(label: String(localized: "Put back the skill “\(name)”")) { try library.restore(url, name: name) } }
        return ToolResult(text: "Moved the skill “\(name)” to the Trash.", card: ResultCard(kind: .info, title: name, subtitle: String(localized: "Deleted")),
                          undo: undo)
    }
}
