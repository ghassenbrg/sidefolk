import Foundation

public enum FolderShare { public static let toolName = "folders.share" }

/// `folders.share` (D180): where the person's yes to a page's `share` question lands. Their click alone: a model, another agent or the extension
/// never reach it. The folder is one Sidefolk's question named, and the same rules hold as for Settings › Trust.
struct FolderShareTool: Tool {
    static let name = FolderShare.toolName

    let permissions: PermissionStore
    let events: EventBus

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Share a folder with Sidefolk", comment: "A tool: the person's yes to a page asking to share a folder"),
                 description: "Shares a folder with Sidefolk on the person's click.",
                 inputSchema: Schema.object(["folder": Schema.string("The folder."), "write": Schema.boolean("Whether files in it may change too.")], required: ["folder"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        String(localized: "Share \(FolderAccess.displayPath(input.string("folder") ?? "")) with Sidefolk", comment: "A row in History: a folder was shared")
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        context.caller == .user ? nil : "This is for the person's own click."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let folder = input.string("folder") else { throw ToolError.invalidInput(String(localized: "Tell me which folder.")) }
        // What they read is what's shared: a link swapped in since the question gets nothing.
        try await permissions.grantFolder(folder, access: input["write"]?.boolValue == true ? .readwrite : .read, now: context.now, exactly: true)
        events.changed(.permissions)
        return ToolResult(text: "Shared.", card: ResultCard(kind: .info, title: summary(for: input)))
    }
}
