import Foundation

/// How Sidefolk's AI builds an extension for the person (D39, the `build-extension` skill):
/// `extensions.draft` writes and checks a draft, `extensions.review` opens the normal install preview
/// for it, `extensions.read_draft` reads drafts back. They write text into Sidefolk's drafts folder and
/// open a window; installing stays the person's own click on the install sheet. Only Sidefolk's agent
/// (or the person) may use them, never in a turn that read outside content, and none is offered to
/// other agents.
public enum ExtensionBuilderTools {
    public static func all(drafts: ExtensionDrafts, host: ExtensionHost, events: EventBus) -> [any Tool] {
        [DraftExtensionTool(drafts: drafts, host: host), ReviewExtensionTool(drafts: drafts, host: host, events: events),
         ReadDraftTool(drafts: drafts)]
    }

    /// Code that will run on this Mac comes only from a clean request by the person (as command watchers, T9).
    static func refusal(_ context: ToolContext) -> String? {
        switch context.caller {
        case .user, .agent: break
        case .routine, .external, .extension, .command: return "Only Sidefolk itself, answering the person, can build extensions."
        }
        guard !context.tainted else {
            return "This request read outside content (a web page, a file, another app), so I won't write code in it. "
                + "Ask the person to ask again in a new request."
        }
        return nil
    }

    static let nameSchema = Schema.string("Short name for the draft: lowercase letters, digits and dashes, like strava-runs.")
}

struct DraftExtensionTool: Tool {
    let drafts: ExtensionDrafts
    let host: ExtensionHost

    let spec = ToolSpec(
        name: "extensions.draft", title: String(localized: "Write an extension draft"),
        description: "Writes (or replaces) an extension draft in Sidefolk's drafts folder, checks it like an install would, and "
            + "starts it once with every permission removed to see that it answers. Pass the whole draft every time. Follow the "
            + "build-extension skill. Nothing is installed: the person installs it from the install preview (extensions.review).",
        inputSchema: Schema.object([
            "name": ExtensionBuilderTools.nameSchema,
            "manifest": .object(["type": "object",
                                 "description": "sidefolk-extension.json as an object, without id, author or icon (Sidefolk sets them)."]),
            "files": .object(["type": "object",
                              "description": "Every other file, by relative path (main.py, lib/client.py), as text. .py .js .mjs .cjs .sh .json .txt .md .csv only."]),
        ], required: ["name", "manifest", "files"]),
        risk: .low, capabilities: [.extensions], category: .extensions, mutates: true)

    func summary(for input: JSONValue) -> String {
        String(localized: "Write the extension draft “\(input.string("name") ?? "")”")
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? { ExtensionBuilderTools.refusal(context) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let name = input.string("name") ?? ""
        var files: [String: String] = [:]
        for (path, value) in input["files"]?.objectValue ?? [:] {
            guard let text = value.stringValue else { throw UserFacingError(verbatim: "files[“\(path)”] must be the file's text.") }
            files[path] = text
        }
        let folder = try drafts.write(name: name, manifest: input["manifest"] ?? .null, files: files)
        let preview = await host.preview(folder: folder)
        let manifest = preview.report.manifest
        let title = manifest?.name ?? name
        var lines = ["Saved the draft “\(title)” (\(ExtensionDrafts.id(for: name))) with \(files.count + 1) files. The install checks say:",
                     preview.report.text]
        if let conflict = preview.conflict { lines.append("It can't be installed as it is: \(conflict)") }
        var ready = false
        if preview.canInstall {
            let trial = await drafts.trial(name: name)
            lines.append("Started once in a sandbox with every permission removed: \(trial.text)")
            ready = trial.problem == nil
        }
        if ready, let manifest {
            lines.append("Once installed, its tools are ext.\(manifest.shortName).<tool>, offered from the person's next request. "
                + "Next: tell the person in one or two sentences what it does and what it may access, then call extensions.review "
                + "with name “\(name)” to open the install preview.")
        } else {
            lines.append("Next: fix what is above and call extensions.draft again with the whole draft.")
        }
        return ToolResult(text: lines.joined(separator: "\n"),
                          card: ResultCard(kind: .info, title: String(localized: "Drafted “\(title)”"),
                                           subtitle: ready ? String(localized: "Ready for you to review") : String(localized: "Still has problems")))
    }
}

struct ReviewExtensionTool: Tool {
    let drafts: ExtensionDrafts
    let host: ExtensionHost
    let events: EventBus

    let spec = ToolSpec(
        name: "extensions.review", title: String(localized: "Show an extension draft for review"),
        description: "Opens the install preview for a finished draft in a window of its own, where the person reads what it can do "
            + "and installs it, or doesn't. Use it once the draft passes extensions.draft's checks.",
        inputSchema: Schema.object(["name": ExtensionBuilderTools.nameSchema], required: ["name"]),
        risk: .low, capabilities: [.extensions], category: .extensions, mutates: false)

    func summary(for input: JSONValue) -> String {
        String(localized: "Show the extension draft “\(input.string("name") ?? "")” for review")
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? { ExtensionBuilderTools.refusal(context) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let name = input.string("name") ?? ""
        guard drafts.exists(name: name) else { throw ToolError.notFound(String(localized: "a draft called “\(name)”")) }
        let folder = drafts.folder(name: name)
        let preview = await host.preview(folder: folder)
        guard preview.canInstall, let manifest = preview.report.manifest else {
            let why = preview.conflict ?? preview.report.errors.first?.description ?? "it doesn't pass the install checks"
            throw UserFacingError(verbatim: "The draft isn't ready: \(why). Fix it with extensions.draft first.")
        }
        events.publish(.reviewExtension(folder))
        return ToolResult(
            text: "The install preview for “\(manifest.name)” is open in its own window. The person reads what it may do and "
                + "decides there; nothing is installed until they click Install. Say so in one sentence. Once installed, its tools are "
                + "offered from their next request. Don't open it again unless they ask.",
            card: ResultCard(kind: .info, title: String(localized: "Review “\(manifest.name)”"), subtitle: String(localized: "Waiting for you to review it")))
    }
}

struct ReadDraftTool: Tool {
    let drafts: ExtensionDrafts

    let spec = ToolSpec(
        name: "extensions.read_draft", title: String(localized: "Read extension drafts"),
        description: "Without a name, lists the extension drafts Sidefolk wrote. With a name, returns that draft's files, to change "
            + "it with extensions.draft (an installed one updates through the install preview).",
        inputSchema: Schema.object(["name": ExtensionBuilderTools.nameSchema]),
        risk: .low, capabilities: [.extensions], category: .extensions, mutates: false)

    func summary(for input: JSONValue) -> String {
        input.string("name").map { String(localized: "Read the extension draft “\($0)”") } ?? String(localized: "List extension drafts")
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? { ExtensionBuilderTools.refusal(context) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let name = input.string("name"), !name.isEmpty else {
            let all = drafts.list()
            guard !all.isEmpty else { return ToolResult(text: "No extension drafts.") }
            return ToolResult(text: all.map { "\($0.name): “\($0.title)” \($0.version ?? "")" }.joined(separator: "\n"),
                              card: ResultCard(kind: .list, title: String(localized: "Extension drafts")))
        }
        let files = try drafts.read(name: name)
        let text = files.map { "=== \($0.path) ===\n\($0.text)" }.joined(separator: "\n\n")
        return ToolResult(text: ExtensionText.cap(text, bytes: 60_000), card: ResultCard(kind: .info, title: name, subtitle: String(localized: "Extension draft")))
    }
}
