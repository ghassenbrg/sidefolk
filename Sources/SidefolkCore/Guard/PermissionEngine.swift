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

    /// - Parameter mentions: the links the user typed in the request this call serves (agent runs);
    ///   nil when there is no such request, so every link counts as model-built.
    public func evaluate(
        spec: ToolSpec, input: JSONValue, summary: String, scope: ToolScope, caller: Caller, tainted: Bool,
        policy: GuardPolicy, grants: [Grant], folders: [GrantedFolder], mentions: UserMentions? = nil
    ) -> GuardDecision {
        if let off = spec.capabilities.first(where: { policy.disabled.contains($0) }) {
            return .deny(String(localized: "\(Self.capabilityName(off)) is turned off in Sidefolk's Permissions settings."))
        }

        // Folder boundary: file tools act only inside folders the user granted.
        let unreadable = scope.readPaths.filter { !FolderAccess.allows($0, write: false, folders: folders) }
        let unwritable = scope.writePaths.filter { !FolderAccess.allows($0, write: true, folders: folders) }
        if let blocked = FolderAccess.forbiddenReason(scope.readPaths + scope.writePaths) {
            return .deny(blocked)
        }
        if !unreadable.isEmpty || !unwritable.isEmpty {
            guard caller.kind != "external", caller.kind != "extension" else {
                return .deny(String(localized: "That folder hasn't been shared with Sidefolk."))
            }
            guard let folder = FolderAccess.suggestedFolder(for: (unwritable + unreadable)[0]) else {
                return .deny(String(localized: "That location is too broad to share. Add a specific folder in Settings › Privacy & Permissions."))
            }
            return .ask(ApprovalRequest(
                tool: spec.name, title: String(localized: "Let Sidefolk work in \(FolderAccess.displayPath(folder))?"),
                summary: summary, risk: max(spec.risk, .medium), caller: caller,
                details: .folderAccess(folder: folder, write: !unwritable.isEmpty),
                canAlways: true
            ))
        }

        // A direct user action is the user's own decision.
        if caller == .user { return .allow(.auto) }

        // A link the user didn't type was built by the model: its path or query can carry anything in
        // the context (About you, notes, live state) to someone else's server, so fetching or opening
        // it is at least medium (SECURITY T1, T2). Opening a site the user named is fine in a clean
        // turn; while tainted only the exact address counts. External agents have their own context
        // and their own network, and follow T4 instead.
        let outward = !spec.capabilities.isDisjoint(with: [.network, .apps])
        let typed = scope.url.map { mentions?.contains(url: $0) == true } ?? false
        let namedSite = !tainted && spec.capabilities.contains(.apps) && scope.url.map { mentions?.containsSite(of: $0) == true } == true
        let modelBuilt = outward && scope.url.map(UserMentions.isWebAddress) == true && !typed && !namedSite && caller.kind != "external"
        let risk = modelBuilt ? max(spec.risk, .medium) : spec.risk

        // While untrusted content is in play, anything that could carry it into memory, the
        // clipboard, a browser or the network waits for the user (SECURITY T2, T12). An address
        // the user typed carries nothing the model added.
        let carriesTaint = tainted && ((outward && !typed)
            || (spec.mutates && !spec.capabilities.isDisjoint(with: [.memory, .clipboard])))
        switch risk {
        case .low where !carriesTaint:
            return .allow(.auto)
        case .low, .medium:
            let grantable = !(tainted && caller.kind != "user") && scope.text == nil
            if grantable, policy.mode == .standard, Self.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) != nil {
                return .allow(.always)
            }
            return .ask(ApprovalRequest(
                tool: spec.name, title: spec.title, summary: summary, risk: risk, caller: caller,
                details: Self.details(spec: spec, scope: scope), canAlways: grantable, tainted: tainted,
                // An extension's own word that it changes nothing isn't enough to say so on the card.
                readsOnly: !spec.mutates && spec.capabilities.isDisjoint(with: [.network, .apps, .shell, .extensions])
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
            // A command grant covers that exact command in that exact folder (T9): the same words
            // run somewhere else run a different Makefile. Grants saved without the binding never match.
            if g.scope.string("command") != nil {
                guard let command = scope.command, let binding = g.scope.string("binding") else { return false }
                return binding == commandBinding(command, folder: scope.commandFolder)
            }
            if let folder = g.scope.string("folder") {
                let paths = scope.readPaths + scope.writePaths
                return !paths.isEmpty && paths.allSatisfy { FolderAccess.isInside($0, folder: folder) }
            }
            if let ext = g.scope.string("extension") { return ext == scope.extensionId }
            if let host = g.scope.string("host") {
                // A query or fragment is where a model-built link carries data; a site grant never covers one.
                guard let url = URL(string: scope.url ?? ""), url.query == nil, url.fragment == nil else { return false }
                return url.host?.lowercased() == host
            }
            return scope.command == nil
        }
    }

    /// SHA-256 of the command and the canonical folder it runs in ("" when none), NUL-separated.
    public static func commandBinding(_ command: String, folder: String?) -> String {
        let place = folder.map { FolderAccess.canonical($0) ?? $0 } ?? ""
        return ExtensionHash.sha256(Data((command + "\0" + place).utf8))
    }

    /// The narrowest sensible scope for an "always allow" grant created from this request.
    public static func grantScope(for scope: ToolScope) -> JSONValue {
        if let command = scope.command {
            var bound: JSONValue = ["command": .string(command), "binding": .string(commandBinding(command, folder: scope.commandFolder))]
            if let folder = scope.commandFolder { bound = bound.setting("cwd", .string(FolderAccess.canonical(folder) ?? folder)) }
            return bound
        }
        if let ext = scope.extensionId { return ["extension": .string(ext)] }
        if let first = (scope.writePaths + scope.readPaths).first, let folder = FolderAccess.suggestedFolder(for: first) {
            return ["folder": .string(folder)]
        }
        if let host = URL(string: scope.url ?? "")?.host?.lowercased() { return ["host": .string(host)] }
        return .object([:])
    }

    static func details(spec: ToolSpec, scope: ToolScope) -> ApprovalRequest.Details {
        if let text = scope.text { return .text(text) }
        if let command = scope.command { return .command(command) }
        if let url = scope.url { return .url(url) }
        let paths = scope.writePaths + scope.readPaths
        if !paths.isEmpty { return .paths(paths) }
        return .none
    }

    public static func capabilityName(_ c: Capability) -> String {
        switch c {
        case .notebook: String(localized: "The notebook")
        case .memory: String(localized: "Memory")
        case .time: String(localized: "Reminders")
        case .watch: String(localized: "Watching")
        case .clipboard: String(localized: "Clipboard access")
        case .apps: String(localized: "Opening apps and links")
        case .network: String(localized: "Internet access")
        case .shell: String(localized: "Running commands")
        case .agents: String(localized: "Agent workers")
        case .extensions: String(localized: "Extensions")
        case .system: String(localized: "System information")
        case .filesRead: String(localized: "Reading files")
        case .filesWrite: String(localized: "Changing files")
        case .macApps: String(localized: "Using Apple Notes and Reminders")
        }
    }
}
