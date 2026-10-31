import Foundation

/// Where an extension about to be installed comes from, and so what Sidefolk could check about its code (D71).
public enum InstallSource: String, Sendable, Hashable {
    /// Downloaded from the add-on gallery: signed with Sidefolk's Developer ID and checked before install (D55, T33).
    case gallery
    /// Written by Sidefolk's AI at the person's request (D39): checked, but nobody else read its code.
    case draft
    /// A folder on this Mac: Sidefolk can't tell who made it.
    case folder
}

/// What the install sheet says, built from the manifest alone (D71). The facts are the same whatever the source;
/// the source sets only how loudly the risky combinations are said, never whether they are.
public struct InstallReview: Sendable, Hashable {
    public enum Tone: String, Sendable, Hashable {
        /// Sidefolk's own extension from the gallery: the same sentences, as something good to know.
        case goodToKnow
        /// Anything else: a strong warning, read before installing.
        case careful
    }

    /// What an update changes in what it may do. One that asks for more is shown prominently for every source:
    /// a signature says who made it, not that the person agreed to more.
    public struct Update: Sendable, Hashable {
        /// "Updates 1.0 to 1.1." or "Installs 1.0 again."
        public var line: String
        public var added: [String]
        public var removed: [String]
        public var widens: Bool { !added.isEmpty }

        public init(line: String, added: [String], removed: [String]) {
            self.line = line
            self.added = added
            self.removed = removed
        }

        public init(_ diff: ExtensionUpdateDiff) {
            // The same version again (a folder being worked on, or a pack fetched again) isn't an update.
            // What asks for more is what the auto-updater holds back for review (D70): a riskier tool or running in
            // the background asks for more too, though no permission line changes.
            self.init(line: diff.fromVersion == diff.toVersion
                          ? String(localized: "Installs \(diff.toVersion) again.", comment: "A version number")
                          : String(localized: "Updates \(diff.fromVersion) to \(diff.toVersion).", comment: "Two version numbers"),
                      added: diff.addedPermissions
                          + diff.riskierTools.map { String(localized: "Riskier now: \($0)", comment: "A tool's name") }
                          + (diff.startsInBackground ? [String(localized: "Keeps running in the background now")] : []),
                      removed: diff.removedPermissions)
        }
    }

    public var source: InstallSource
    public var tone: Tone
    public var lines: [PermissionSummary.Line]
    /// Risky combinations, then what the checks noticed: worded the same for every source.
    public var cautions: [String]
    public var update: Update?
    /// What happens once it's installed, in order: what it does by itself, what still asks, macOS, how to undo it.
    public var next: [String]

    public init(source: InstallSource, tone: Tone, lines: [PermissionSummary.Line], cautions: [String], update: Update?, next: [String]) {
        self.source = source
        self.tone = tone
        self.lines = lines
        self.cautions = cautions
        self.update = update
        self.next = next
    }

    /// Everything from the manifest's permissions, as `ManifestValidator` resolved them.
    public init(id: String, permissions: ExtensionPermissions, background: Bool, toolRisks: [Risk], checks: [String] = [],
                update: ExtensionUpdateDiff?, source: InstallSource) {
        let summary = PermissionSummary.forExtension(permissions)
        self.init(source: source, tone: Self.tone(source: source, id: id), lines: summary.lines, cautions: summary.warnings + checks,
                  update: update.map(Update.init), next: Self.next(permissions, background: background, toolRisks: toolRisks))
    }

    /// The calm tone is earned only by code Sidefolk signed as its own: from the gallery, and with Sidefolk's id
    /// (the gallery's seal, `AddonEntry.official`). A draft is unread code; a folder, anyone's.
    public static func tone(source: InstallSource, id: String) -> Tone {
        source == .gallery && AddonEntry.isOfficial(id: id) ? .goodToKnow : .careful
    }

    /// What installing grants and what is still asked later. Each line is a guard the code enforces: the sandbox
    /// (SandboxProfile), Guard's floor for tools (`ExtensionRisk`, `PermissionEngine`), macOS's own switches.
    static func next(_ p: ExtensionPermissions, background: Bool, toolRisks: [Risk]) -> [String] {
        var out = [String(localized: "It runs in a sandbox that allows only what's listed here.")]
        if background {
            // A program that keeps running acts within its permissions without a tool call, so no card comes (D63).
            out.append(String(localized: "It keeps running while it's on, and can use all of this by itself, without asking each time."))
        }
        let asking = toolRisks.filter { $0 >= .medium }.count
        if asking == toolRisks.count, asking > 0 {
            out.append(String(localized: "Guard asks you before Sidefolk's AI or another agent uses its tools, as often as you chose in Settings › Privacy & Permissions."))
        } else if asking > 0 {
            out.append(String(localized: "Guard asks before some of its tools are used, as often as you chose in Settings › Privacy & Permissions; the rest can't reach the internet or change your files."))
        } else if !toolRisks.isEmpty {
            // Low risk is possible only below the floor: no network, no writing, nothing that runs anything (ExtensionRisk).
            out.append(String(localized: "Its tools can't reach the internet or change your files, so Sidefolk's AI may use them without asking."))
        }
        if p.network, p.udp {
            // Live traffic with devices nearby: macOS asks about the local network for Sidefolk, the responsible app.
            out.append(String(localized: "macOS may ask you to allow Sidefolk in Local Network the first time it looks for devices nearby."))
        }
        out.append(String(localized: "You can turn it off or remove it any time in Settings › Extensions."))
        return out
    }
}

extension InstallReview {
    /// The sheet for an extension folder `ExtensionHost.preview` checked.
    public init?(_ preview: InstallPreview, source: InstallSource) {
        guard let manifest = preview.report.manifest, let permissions = preview.report.shownPermissions() else { return nil }
        self.init(id: manifest.id, permissions: permissions, background: manifest.background, toolRisks: preview.report.toolRisks.map(\.risk),
                  checks: preview.report.warnings, update: preview.update, source: source)
    }
}
