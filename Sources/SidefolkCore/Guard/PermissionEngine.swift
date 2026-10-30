import Foundation

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
                canAlways: true, extensionId: scope.extensionId
            ))
        }

        // A direct user action is the user's own decision.
        if caller == .user { return .allow(.auto) }

        // A link the user didn't type was built by the model: its path or query can carry anything in
        // the context (About you, notes, live state) to someone else's server, so fetching or opening
        // it is at least medium (SECURITY T1, T2). Opening a site the user named is fine in a clean
        // turn; while tainted only the exact address counts. External agents have their own context
        // and their own network, and follow T4 instead. A call Sidefolk's own code keeps off the network (a CPU
        // report) reaches nothing, whatever its tool could.
        let opensApps = spec.capabilities.contains(.apps)
        let usesNetwork = spec.capabilities.contains(.network) && scope.reach != .nowhere
        let outward = usesNetwork || opensApps
        let typed = scope.url.map { mentions?.contains(url: $0) == true } ?? false
        let namedSite = !tainted && opensApps && scope.url.map { mentions?.containsSite(of: $0) == true } == true
        let modelBuilt = outward && scope.url.map(UserMentions.isWebAddress) == true && !typed && !namedSite && caller.kind != "external"
        let risk = modelBuilt ? max(spec.risk, .medium) : spec.risk

        // How Sidefolk's own agent uses the internet (D47). A built-in service (Open-Meteo for the weather) hears only
        // what the model asks it and passes it to no one else. Reading a page at an address the model wrote is a site
        // read: it changes nothing, and Guard can name the site it reaches.
        let internet = policy.internet(for: caller)
        let internetCall = internet != nil && usesNetwork && !opensApps && !typed
        let service: String? = if internetCall, case .service(let name) = scope.reach,
            spec.capabilities.isSubset(of: [.network, .extensions, .watch]) { name } else { nil }
        let site = internetCall && scope.reach == nil && !spec.mutates && spec.capabilities == [.network] && modelBuilt
            ? scope.url.flatMap(URL.init(string:)).flatMap(UserMentions.host) : nil
        let askEachTime = internetCall && internet == .askEachTime

        // While untrusted content is in play, anything that could carry it into memory, the
        // clipboard, a browser or the network waits for the user (SECURITY T2, T12). An address
        // the user typed carries nothing the model added.
        let outwardUntyped = outward && !typed
        let carriesTaint = tainted && (outwardUntyped
            || (spec.mutates && !spec.capabilities.isDisjoint(with: [.memory, .clipboard])))
        let mode = policy.mode(for: caller)
        let honoursGrants = mode != .askEveryTime && !askEachTime
        let decision: GuardDecision
        switch risk {
        case .low where !carriesTaint && !askEachTime:
            return .allow(.auto)
        case .low, .medium:
            // Grants hold in a clean turn. After outside content was read, a grant the person gave in a clean turn
            // still holds where what the model writes can reach no one new: a built-in service, or reading a site
            // allowed for good (a site grant never covers a query, F1) (D47). "Always" is never offered then.
            let clean = !(tainted && caller.kind != "user")
            let grantable = scope.text == nil && (clean || service != nil || site != nil)
            let holding = clean ? grants : grants.filter { g in
                site != nil ? g.scope.string("host") != nil : g.scope.string("extension") != nil || g.scope.string("service") != nil
            }
            if grantable, honoursGrants, Self.matchingGrant(spec: spec, scope: scope, caller: caller, grants: holding) != nil {
                return .allow(.always)
            }
            if internet == .withoutAsking, internetCall, scope.text == nil, service != nil || (site != nil && !tainted) {
                return .allow(.webSetting)
            }
            // A call that can't carry anything off the Mac may instead be allowed for the rest of Sidefolk's
            // run (D37): a library of Apple Notes copied in batches is one card per kind, not one per batch.
            let forRequest = tainted && caller.runId != nil && honoursGrants && scope.text == nil
                && !Self.couldCarryOut(spec, outwardUntyped: outwardUntyped)
            decision = .ask(ApprovalRequest(
                tool: spec.name, title: spec.title, summary: summary, risk: risk, caller: caller,
                details: Self.details(spec: spec, scope: scope), canAlways: clean && scope.text == nil && !askEachTime, tainted: tainted,
                effect: Self.effect(of: spec, extension: scope.extensionId != nil || spec.name.hasPrefix("ext.")), canAllowForRequest: forRequest,
                extensionId: scope.extensionId, site: Self.siteOfGrant(scope), service: service
            ))
        case .high:
            // Only an exact command may be granted "always"; everything else is asked every time.
            let exactCommand = scope.command != nil
            if exactCommand, !tainted, honoursGrants,
               Self.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) != nil {
                return .allow(.always)
            }
            decision = .ask(ApprovalRequest(
                tool: spec.name, title: spec.title, summary: summary, risk: .high, caller: caller,
                details: Self.details(spec: spec, scope: scope), canAlways: exactCommand && !tainted, tainted: tainted,
                extensionId: scope.extensionId
            ))
        }
        // Auto and Full access answer, themselves, the questions the person chose not to be asked; the internet
        // asks each time when the person said so, whatever the mode (D47).
        if !askEachTime, let tag = Self.answeredByMode(mode, risk: risk, spec: spec, scope: scope, tainted: tainted,
                                                       outwardUntyped: outwardUntyped) {
            return .allow(tag)
        }
        return decision
    }

    /// The question Auto or Full access answers without the person (D37), with the tag Activity shows,
    /// or nil when the person must answer. Text to read in full (a new skill: instructions for later
    /// runs) always waits for them. Auto acts on medium risk in a clean turn. Full access acts on
    /// anything, except, in a turn that read outside content, what could carry data out.
    static func answeredByMode(_ mode: GuardMode, risk: Risk, spec: ToolSpec, scope: ToolScope, tainted: Bool,
                               outwardUntyped: Bool) -> ActivityEntry.Decision? {
        guard scope.text == nil else { return nil }
        switch mode {
        case .askEveryTime, .askOncePerKind:
            return nil
        case .auto:
            return !tainted && risk == .medium ? .autoMode : nil
        case .fullAccess:
            return tainted && couldCarryOut(spec, outwardUntyped: outwardUntyped) ? nil : .fullAccess
        }
    }

    /// What a turn steered by a web page, file or extension still never does without the person, even
    /// in Full access (SECURITY T2, T12, T21): reach a server or another app at an address the person
    /// didn't type, run a program, change files (a shared folder may sync them anywhere), hand input to
    /// an extension or MCP server, or write the clipboard or memory, which carry it into later moments.
    static func couldCarryOut(_ spec: ToolSpec, outwardUntyped: Bool) -> Bool {
        outwardUntyped
            || !spec.capabilities.isDisjoint(with: [.shell, .filesWrite, .extensions])
            || (spec.mutates && !spec.capabilities.isDisjoint(with: [.memory, .clipboard]))
    }

    /// What a call can do, for the card's label, from what Sidefolk lets it do: an extension's capabilities come
    /// from its sandbox (network, folders, programs), so its own word that it changes nothing is never taken; a
    /// built-in tool's `mutates` is Sidefolk's own.
    static func effect(of spec: ToolSpec, extension isExtension: Bool) -> ApprovalRequest.Effect {
        let can = spec.capabilities
        if can.contains(.shell) { return .runsPrograms }
        if can.contains(.filesWrite) { return .changesFiles }
        if spec.mutates, !isExtension { return .changesThings }
        if can.contains(.network) { return .usesInternet }
        if can.contains(.apps) { return .opensApps }
        if can.contains(.filesRead) { return .readsFiles }
        return isExtension ? .usesExtension : .readsPrivateData
    }

    /// The grant that covers this call, if any. Grants are per tool, narrowed by scope.
    public static func matchingGrant(spec: ToolSpec, scope: ToolScope, caller: Caller, grants: [Grant]) -> Grant? {
        grants.first { g in
            guard g.tool == spec.name, g.callerKind == "any" || g.callerKind == caller.grantKind else { return false }
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
            if let service = g.scope.string("service") { return scope.reach == .service(service) }
            if let host = g.scope.string("host") {
                // A query or fragment is where a model-built link carries data; a site grant never covers one (audit
                // F1). "www." and a final dot name the same site.
                guard let url = URL(string: scope.url ?? ""), url.query == nil, url.fragment == nil else { return false }
                return UserMentions.host(url) != nil && UserMentions.host(url) == UserMentions.site(host)
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
        if let host = siteOfGrant(scope) { return ["host": .string(host)] }
        if case .service(let name) = scope.reach { return ["service": .string(name)] }
        return .object([:])
    }

    /// The site an "Always allow" from this call would cover, when it would be a site grant ("example.com").
    static func siteOfGrant(_ scope: ToolScope) -> String? {
        guard scope.command == nil, scope.extensionId == nil, scope.readPaths.isEmpty, scope.writePaths.isEmpty,
              let url = URL(string: scope.url ?? "") else { return nil }
        return UserMentions.host(url)
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
        case .watch: String(localized: "capability.watch", defaultValue: "Watching", comment: "A permission: watching pages, files and programs. Also in “%@ is turned off in Sidefolk's Permissions settings.”")
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
        case .calendar: String(localized: "Reading your calendar")
        }
    }
}
