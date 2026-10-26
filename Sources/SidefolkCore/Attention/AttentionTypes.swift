import Foundation

/// How the app should present an attention item right now.
public enum AttentionPresentation: Sendable, Hashable {
    /// Pose or badge only.
    case ambient
    /// A small bubble that goes away on its own.
    case gentle(autoDismiss: TimeInterval)
    /// The companion steps forward and the bubble stays until handled (collapsed after `expandFor`).
    case attention(expandFor: TimeInterval)
    /// Attention plus a system notification (used when the companion is hidden, away or critical).
    case system(sound: Bool, alsoOnDesktop: Bool)
}

public enum AttentionDirective: Sendable {
    case present(AttentionItem, AttentionPresentation)
    /// The item was handled (here or in a notification) and should disappear everywhere.
    case withdraw(id: String)
    /// Items waiting for the user (shown as a count on the companion).
    case backlog(count: Int)
}
