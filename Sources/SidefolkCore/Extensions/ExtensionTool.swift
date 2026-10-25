import Foundation

/// A tool an extension or MCP server provides, registered as `ext.<short>.<tool>` with the extension id
/// as owner. Results are always untrusted; Guard scopes "always allow" grants to the extension.
public struct ExtensionTool: Tool {
    public let spec: ToolSpec
    public let extensionId: String
    public let extensionName: String
    /// The tool's name on the extension's side of the protocol.
    public let remoteName: String
    private let invoke: @Sendable (JSONValue) async throws -> ToolResult

    init(spec: ToolSpec, extensionId: String, extensionName: String, remoteName: String,
         invoke: @escaping @Sendable (JSONValue) async throws -> ToolResult) {
        self.spec = spec
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.remoteName = remoteName
        self.invoke = invoke
    }

    public static func registryName(short: String, tool: String) -> String { "ext.\(short).\(tool)" }

    /// MCP servers name tools freely (`getFileContents`, `git-status`); Sidefolk names are `[a-z0-9_]`.
    static func localName(_ remote: String, maxLength: Int) -> String? {
        var out = ""
        for ch in remote.lowercased() {
            out.append(ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "_")
        }
        let trimmed = String(out.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? nil : trimmed
    }

    public func summary(for input: JSONValue) -> String {
        let args = (input.objectValue?.isEmpty ?? true) ? "" : " " + input.jsonString
        return "\(spec.title) (\(extensionName))\(args)"
    }

    public func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: extensionId) }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        try await invoke(input)
    }
}
