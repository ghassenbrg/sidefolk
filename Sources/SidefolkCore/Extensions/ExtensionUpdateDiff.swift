import Foundation

/// What updating an installed extension would change, for the install sheet ("New permission: …") and for the
/// add-on rule (D70): an update that lets it do more than the person agreed to is never installed by itself.
public struct ExtensionUpdateDiff: Sendable, Hashable {
    public var fromVersion: String
    public var toVersion: String
    /// Permission lines, as the install sheet words them.
    public var addedPermissions: [String]
    public var removedPermissions: [String]
    public var addedTools: [String]
    public var removedTools: [String]
    /// Tools that would run at a higher risk than before: a new one above the highest it had, or one it had,
    /// raised.
    public var riskierTools: [String]
    /// Something it may touch or use grew (a folder, a program, the network, the clipboard …), whether or not the
    /// sheet's lines show it.
    public var widensPermissions: Bool
    /// It starts to keep running in the background (D63).
    public var startsInBackground: Bool

    /// One side of an update: the installed copy as it was pinned, or the folder about to replace it.
    public struct Side: Sendable {
        public var version: String
        public var permissions: ExtensionPermissions
        /// The install sheet's permission lines for `permissions`.
        public var lines: [String]
        /// Each tool the manifest describes, at the risk it runs at.
        public var tools: [String: Risk]
        public var background: Bool

        public init(version: String, permissions: ExtensionPermissions, lines: [String], tools: [String: Risk], background: Bool) {
            self.version = version
            self.permissions = permissions
            self.lines = lines
            self.tools = tools
            self.background = background
        }
    }

    public init(from old: Side, to new: Side) {
        fromVersion = old.version
        toVersion = new.version
        let before = Set(old.lines), after = Set(new.lines)
        addedPermissions = after.subtracting(before).sorted()
        removedPermissions = before.subtracting(after).sorted()
        addedTools = Set(new.tools.keys).subtracting(old.tools.keys).sorted()
        removedTools = Set(old.tools.keys).subtracting(new.tools.keys).sorted()
        // A new tool may be as risky as the riskiest it had: it can already do that kind of thing.
        let ceiling = old.tools.values.max()
        riskierTools = new.tools.compactMap { name, risk in
            if let was = old.tools[name] { return risk > was ? name : nil }
            guard let ceiling else { return name }
            return risk > ceiling ? name : nil
        }.sorted()
        widensPermissions = new.permissions.widens(old.permissions)
        startsInBackground = new.background && !old.background
    }

    public var changesPermissions: Bool { !addedPermissions.isEmpty || !removedPermissions.isEmpty }

    /// It could do more after the update than before, so the person looks at it first (D70). Judged on the permissions
    /// themselves, which every sheet line comes from: a line can be new without anything more allowed ("No access to
    /// your files or the internet" once it gives up the network, or the author's reason for using it).
    public var widens: Bool { widensPermissions || !riskierTools.isEmpty || startsInBackground }
}

extension ExtensionPermissions {
    /// Whether these allow anything `old` didn't. Lists count by entry: a path or program not named before widens,
    /// even inside a folder it had, which only errs towards asking.
    public func widens(_ old: ExtensionPermissions) -> Bool {
        let flags: [(Bool, Bool)] = [(network, old.network), (media, old.media), (clipboard, old.clipboard), (power, old.power),
                                     (screen, old.screen), (udp, old.udp)]
        if flags.contains(where: { $0.0 && !$0.1 }) { return true }
        if !Set(read).isSubset(of: old.read) || !Set(write).isSubset(of: old.write) || !Set(exec).isSubset(of: old.exec) { return true }
        if !Set(programs.map(\.name)).isSubset(of: old.programs.map(\.name)) { return true }
        return Self.rank(folders) > Self.rank(old.folders)
    }

    private static func rank(_ use: ExtensionManifest.FolderUse?) -> Int {
        switch use {
        case nil: 0
        case .read: 1
        case .write: 2
        }
    }
}
