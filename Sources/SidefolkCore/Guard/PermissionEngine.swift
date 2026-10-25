import Foundation

/// How cautious Guard is for the agent's medium-risk actions.
public enum GuardMode: String, Codable, Sendable, CaseIterable {
    /// Ask once per kind of action; "always allow" grants are honoured.
    case standard
    /// Ask for every medium and high action, ignore grants for agents.
    case cautious
}

public struct GuardPolicy: Codable, Sendable, Equatable {
    public var mode: GuardMode = .standard
    /// Capabilities the user switched off entirely.
    public var disabled: Set<Capability> = []
    public init(mode: GuardMode = .standard, disabled: Set<Capability> = []) {
        self.mode = mode
        self.disabled = disabled
    }
}

public enum GuardDecision: Sendable, Equatable {
    case allow(ActivityEntry.Decision)
    case ask(ApprovalRequest)
    case deny(String)
}

/// Deterministic permission decisions. The model never decides what it may do; this does.
public struct PermissionEngine: Sendable {
    public init() {}

    public func evaluate(
        spec: ToolSpec, input: JSONValue, summary: String, scope: ToolScope, caller: Caller, tainted: Bool,
        policy: GuardPolicy, grants: [Grant], folders: [GrantedFolder]
    ) -> GuardDecision {
        if let off = spec.capabilities.first(where: { policy.disabled.contains($0) }) {
            return .deny("\(Self.capabilityName(off)) is turned off in Sidefolk's Permissions settings.")
        }

        // Folder boundary: file tools act only inside folders the user granted.
        let unreadable = scope.readPaths.filter { !FolderAccess.allows($0, write: false, folders: folders) }
        let unwritable = scope.writePaths.filter { !FolderAccess.allows($0, write: true, folders: folders) }
        if let blocked = FolderAccess.forbiddenReason(scope.readPaths + scope.writePaths) {
            return .deny(blocked)
        }
        if !unreadable.isEmpty || !unwritable.isEmpty {
            guard caller.kind != "external", caller.kind != "extension" else {
                return .deny("That folder hasn't been shared with Sidefolk.")
            }
            guard let folder = FolderAccess.suggestedFolder(for: (unwritable + unreadable)[0]) else {
                return .deny("That location is too broad to share. Add a specific folder in Settings › Privacy & Permissions.")
            }
            return .ask(ApprovalRequest(
                tool: spec.name, title: "Let Sidefolk work in \(FolderAccess.displayPath(folder))?",
                summary: summary, risk: max(spec.risk, .medium), caller: caller,
                details: .folderAccess(folder: folder, write: !unwritable.isEmpty),
                canAlways: true
            ))
        }

        // A direct user action is the user's own decision.
        if caller == .user { return .allow(.auto) }

        let networkFromTaint = tainted && spec.capabilities.contains(.network)
        switch spec.risk {
        case .low where !networkFromTaint:
            return .allow(.auto)
        case .low, .medium:
            let grantable = !(tainted && caller.kind != "user")
            if grantable, policy.mode == .standard, Self.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) != nil {
                return .allow(.always)
            }
            return .ask(ApprovalRequest(
                tool: spec.name, title: spec.title, summary: summary, risk: spec.risk, caller: caller,
                details: Self.details(spec: spec, scope: scope), canAlways: grantable, tainted: tainted
            ))
        case .high:
            // Only an exact command may be granted "always"; everything else is asked every time.
            let exactCommand = scope.command != nil
            if exactCommand, !tainted, policy.mode == .standard,
               Self.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) != nil {
                return .allow(.always)
            }
            return .ask(ApprovalRequest(
                tool: spec.name, title: spec.title, summary: summary, risk: .high, caller: caller,
                details: Self.details(spec: spec, scope: scope), canAlways: exactCommand && !tainted, tainted: tainted
            ))
        }
    }

    /// The grant that covers this call, if any. Grants are per tool, narrowed by scope.
    public static func matchingGrant(spec: ToolSpec, scope: ToolScope, caller: Caller, grants: [Grant]) -> Grant? {
        grants.first { g in
            guard g.tool == spec.name, g.callerKind == "any" || g.callerKind == caller.kind else { return false }
            if let command = g.scope.string("command") { return command == scope.command }
            if let folder = g.scope.string("folder") {
                let paths = scope.readPaths + scope.writePaths
                return !paths.isEmpty && paths.allSatisfy { FolderAccess.isInside($0, folder: folder) }
            }
            if let ext = g.scope.string("extension") { return ext == scope.extensionId }
            if let host = g.scope.string("host") { return URL(string: scope.url ?? "")?.host?.lowercased() == host }
            return scope.command == nil
        }
    }

    /// The narrowest sensible scope for an "always allow" grant created from this request.
    public static func grantScope(for scope: ToolScope) -> JSONValue {
        if let command = scope.command { return ["command": .string(command)] }
        if let ext = scope.extensionId { return ["extension": .string(ext)] }
        if let first = (scope.writePaths + scope.readPaths).first, let folder = FolderAccess.suggestedFolder(for: first) {
            return ["folder": .string(folder)]
        }
        if let host = URL(string: scope.url ?? "")?.host?.lowercased() { return ["host": .string(host)] }
        return .object([:])
    }

    static func details(spec: ToolSpec, scope: ToolScope) -> ApprovalRequest.Details {
        if let command = scope.command { return .command(command) }
        if let url = scope.url { return .url(url) }
        let paths = scope.writePaths + scope.readPaths
        if !paths.isEmpty { return .paths(paths) }
        return .none
    }

    public static func capabilityName(_ c: Capability) -> String {
        switch c {
        case .notebook: "The notebook"
        case .memory: "Memory"
        case .time: "Reminders"
        case .watch: "Watching"
        case .clipboard: "Clipboard access"
        case .apps: "Opening apps and links"
        case .network: "Internet access"
        case .shell: "Running commands"
        case .agents: "Agent workers"
        case .extensions: "Extensions"
        case .system: "System information"
        case .filesRead: "Reading files"
        case .filesWrite: "Changing files"
        }
    }
}
