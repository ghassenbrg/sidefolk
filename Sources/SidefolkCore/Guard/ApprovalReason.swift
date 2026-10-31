import Foundation

/// What a run read that made it untrusted (SECURITY T2), as far as Sidefolk can name it: the first such result (D71).
public enum TaintSource: Sendable, Hashable {
    /// An extension's answer. `official`: Sidefolk's own code wrote it (bundled or from the gallery), though what it
    /// relays (a TV's name on the network) still comes from outside.
    case `extension`(name: String, official: Bool)
    case web
    case file
    case other

    /// What a tool's untrusted result counts as. A wrapped tool (another agent's view of it) is named as itself.
    static func of(_ tool: any Tool) -> TaintSource {
        let base = (tool as? ExternalFacade)?.base ?? tool
        if let ext = base as? ExtensionTool {
            let name = (ext.firstParty ? BuiltInExtensionWords.name(ext.extensionId) : nil) ?? ext.extensionName
            return .extension(name: ToolFormat.oneLine(ExtensionText.clean(name), 40), official: ext.firstParty)
        }
        switch base.spec.category {
        case .web: return .web
        case .files: return .file
        default: return .other
        }
    }
}

/// Why a card asks when it does because of outside content, in words (D71): what was read, why this call matters, and,
/// when the person chose to be asked less, that their mode never answers this. Guard's decision is unchanged (T2, T12,
/// T21); this only explains it.
public struct ApprovalReason: Sendable, Hashable {
    public var text: String
    /// Sidefolk's own extension asking after reading Sidefolk's own extension: said calmly. Anything else stays strong.
    public var calm: Bool

    public init?(_ request: ApprovalRequest) {
        guard request.tainted else { return nil }
        // Other apps' medium calls are evaluated as tainted so they're asked every time (T4): nothing was read.
        if request.caller.kind == "external" {
            text = String(localized: "Another app is asking, so I check with you each time.")
            calm = false
            return
        }
        var sentences = [Self.read(request.taintedBy), Self.matters(request.effect)]
        switch request.mode {
        case .fullAccess?: sentences.append(String(localized: "Full access never decides this for you after outside content."))
        // Auto answers only medium risk in a clean turn; a high-risk card would have asked anyway.
        case .auto? where request.risk == .medium: sentences.append(String(localized: "Auto never decides this for you after outside content."))
        default: break
        }
        text = sentences.joined(separator: " ")
        if case .extension(_, official: true)? = request.taintedBy { calm = request.firstParty } else { calm = false }
    }

    static func read(_ source: TaintSource?) -> String {
        switch source {
        case .extension(let name, _)?: String(localized: "This request read results from \(name) first.", comment: "An extension's name")
        case .web?: String(localized: "This request read a web page first.")
        case .file?: String(localized: "This request read a file first.")
        case .other?, nil: String(localized: "This request read outside content first, like a web page, a file or an extension's answer.")
        }
    }

    /// Why that matters for this call: what it could do with what was read (`PermissionEngine.couldCarryOut`).
    static func matters(_ effect: ApprovalRequest.Effect) -> String {
        switch effect {
        case .usesInternet: String(localized: "This can send what it's given off this Mac, so I check with you first.")
        case .opensApps: String(localized: "This opens a link or app with what it's given, so I check with you first.")
        case .changesFiles: String(localized: "This changes files, so I check with you first.")
        case .runsPrograms: String(localized: "This runs a program, so I check with you first.")
        case .usesExtension: String(localized: "This hands what it's given to an extension, so I check with you first.")
        case .readsPrivateData, .readsFiles, .changesThings: String(localized: "This could act on what was read, so I check with you first.")
        }
    }
}
