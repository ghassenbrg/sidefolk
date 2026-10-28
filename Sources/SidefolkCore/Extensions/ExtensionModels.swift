import Foundation

/// Where an installed extension came from. Nil (not stored) means a folder the person chose, or an MCP server.
public enum ExtensionOrigin: String, Codable, Sendable, Hashable {
    /// Shipped inside Sidefolk and installed by it: first-party code, updated with the app (D39).
    case bundled
    /// Written by Sidefolk's AI for the person in the drafts folder, installed once they approved it (D39).
    case draft
}

/// What Sidefolk pinned when the user installed an extension or added an MCP server. Stored as JSON in
/// `ExtensionRecord.granted`; only the host writes it.
public struct ExtensionPin: Codable, Sendable, Hashable {
    public var name: String
    public var description: String?
    /// The manifest's one line for Settings; pins written before it have none.
    public var tagline: String?
    public var folk: String?
    public var author: String?
    public var origin: ExtensionOrigin?
    /// Sidefolk extensions: how it starts, what it may touch, and the hash of every file.
    public var launch: ExtensionLaunch?
    public var permissions: ExtensionPermissions?
    public var files: [ExtensionFilePin]
    /// Plain MCP servers: the command the user added.
    public var server: MCPServerCommand?
    /// Tool definitions the user approved, by the server's own tool name.
    public var tools: [String: MCPToolDefinition]
    /// Changed or new definitions waiting for the user; those tools can't run (quarantine).
    public var pending: [String: MCPToolDefinition]

    public init(name: String, description: String? = nil, tagline: String? = nil, folk: String? = nil, author: String? = nil, origin: ExtensionOrigin? = nil,
                launch: ExtensionLaunch? = nil, permissions: ExtensionPermissions? = nil, files: [ExtensionFilePin] = [],
                server: MCPServerCommand? = nil, tools: [String: MCPToolDefinition] = [:], pending: [String: MCPToolDefinition] = [:]) {
        self.name = name
        self.description = description
        self.tagline = tagline
        self.folk = folk
        self.author = author
        self.origin = origin
        self.launch = launch
        self.permissions = permissions
        self.files = files
        self.server = server
        self.tools = tools
        self.pending = pending
    }
}

/// A user-added MCP server: runs unsandboxed with the user's rights (SECURITY T16).
public struct MCPServerCommand: Codable, Sendable, Hashable {
    /// Absolute path, resolved when the server was added.
    public var command: String
    public var arguments: [String]
    /// Names of environment variables whose values the app supplies from the Keychain.
    public var environmentKeys: [String]

    public var commandLine: String { ([command] + arguments).joined(separator: " ") }
}

/// A watcher kind an extension contributes, for the watcher engine and the "new watcher" UI.
public struct ExtensionWatcherKind: Sendable, Hashable {
    public var extensionId: String
    public var watcher: String
    public var title: String
    public var description: String
    public var config: [String: ExtensionManifest.ConfigField]
}

public struct ExtensionToolInfo: Sendable, Hashable {
    /// Name in the tool registry, e.g. `ext.system-vitals.battery`.
    public var name: String
    public var title: String
    public var risk: Risk
    /// Changed or new since the user approved it; it can't run until approved.
    public var quarantined: Bool
    /// Sentences that call it without the AI, as people see them ("time in …") (D50).
    public var commands: [String] = []
    /// Offered to Sidefolk's AI; false when its author left it to its commands.
    public var forAI = true
}

/// Everything Settings › Extensions shows for one installed extension or MCP server.
public struct ExtensionInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var kind: ExtensionRecord.Kind
    public var enabled: Bool
    public var running: Bool
    public var lastError: String?
    public var description: String?
    /// One line under its name: the manifest's tagline, or the description's first sentence when it has none.
    public var tagline: String? = nil
    public var folk: String?
    public var author: String?
    public var origin: ExtensionOrigin?
    /// The installed copy's icon file, checked at install and on every load; nil means the default tile.
    public var iconPath: String?
    public var summary: PermissionSummary
    /// For MCP servers, the command line as added.
    public var command: String?
    public var tools: [ExtensionToolInfo]
    public var watchers: [ExtensionWatcherKind]
    /// Where the manifest's `tools` and the program's `tools/list` disagree (a typo, a forgotten entry).
    public var toolWarnings: [String] = []

    public var hasPendingToolChanges: Bool { tools.contains(where: \.quarantined) }
}

/// What installing a folder would do, for the install sheet. `update` is set when an older version is
/// installed: the sheet shows what it gains and loses.
public struct InstallPreview: Sendable {
    public var report: ValidationReport
    public var update: ExtensionUpdateDiff?
    /// Why it can't be installed even though the manifest is valid (an id or name already in use).
    public var conflict: String?

    public var canInstall: Bool { report.isValid && conflict == nil }
}

public struct ExtensionUpdateDiff: Sendable, Hashable {
    public var fromVersion: String
    public var toVersion: String
    public var addedPermissions: [String]
    public var removedPermissions: [String]
    public var addedTools: [String]
    public var removedTools: [String]

    public var changesPermissions: Bool { !addedPermissions.isEmpty || !removedPermissions.isEmpty }
}

/// What adding an MCP server would do, for the confirmation sheet.
public struct MCPServerPreview: Sendable, Hashable {
    public var id: String
    public var name: String
    public var resolvedCommand: String?
    public var arguments: [String]
    public var summary: PermissionSummary
    public var errors: [String]

    public var canAdd: Bool { errors.isEmpty && resolvedCommand != nil }
}

/// The one line Settings shows under an extension's name (D39, amended 2026-10-28): its tagline, or the first sentence
/// of its description for one written before taglines, so a long description never runs off the row.
public enum ExtensionTagline {
    public static func line(tagline: String?, description: String?) -> String {
        if let tagline = tagline?.trimmingCharacters(in: .whitespacesAndNewlines), !tagline.isEmpty { return tagline }
        guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
        // The system's sentences, so a number like 3.5 doesn't end one.
        var first: String?
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
            first = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
            stop = true
        }
        return first.flatMap { $0.isEmpty ? nil : $0 } ?? text
    }
}
