import Foundation

/// What a status means, before it is a colour (docs/ARCHITECTURE.md › Colour meaning). The app paints each tone with
/// the theme's role for it, so every screen says the same thing the same way: red only when something failed or puts
/// the person's data at risk, never for "off", "no", "late" or "changed".
public enum StatusTone: String, Sendable, Hashable, CaseIterable {
    /// Done, healthy, on, allowed, won: a good outcome or a settled good state, not "busy".
    case success
    /// Needs a look or is waiting: late, waiting for an answer, worth checking. Not an error.
    case warning
    /// An error, a failure, a destructive action, or real risk to the person's data or privacy. Nothing else.
    case danger
    /// Something new to look at, like an unread dot (a page that changed), or an extension's "info". News, not trouble.
    case news
    /// Information, off, paused, nothing happened, a draw.
    case neutral
}

extension StatusTone {
    /// A step in Activity. Saying no and nobody answering are the person's own outcomes, so they read calm; a step
    /// the rules stopped is worth a look; only a step that broke is red.
    public static func decision(_ decision: ActivityEntry.Decision) -> StatusTone {
        switch decision {
        case .allowed, .always: .success
        case .failed: .danger
        case .blocked: .warning
        // Full access answered for the person: no failure, but the riskiest mode, so it stands out (D37).
        case .fullAccess, .fullAccessPaired: .warning
        case .denied, .skipped, .auto, .autoMode, .autoModePaired, .webSetting: .neutral
        }
    }

    /// A tool's risk. Low is the ordinary case, so it carries no colour at all.
    public static func risk(_ risk: Risk?) -> StatusTone {
        switch risk {
        case .high: .danger
        case .medium: .warning
        case .low, nil: .neutral
        }
    }

    /// A watch on its tile, chip or badge. A page that changed is news, never an error; only a watch that keeps
    /// failing to look is red.
    public static func watch(_ state: Watcher.State, changeWaiting: Bool) -> StatusTone {
        if state == .error { return .danger }
        if changeWaiting { return .news }
        switch state {
        case .triggered: return .success
        // Watching is the ordinary, busy state: information, not an outcome to celebrate.
        case .active, .paused, .expired, .error: return .neutral
        }
    }

    /// An agent session: waiting for the person is a question, not a failure.
    public static func session(_ state: AgentSession.State) -> StatusTone {
        switch state {
        case .needsYou: .warning
        // Busy is not done: green is kept for outcomes.
        case .working, .idle, .finished: .neutral
        }
    }

    /// A reminder whose time passed still waits to be done: it needs a look, it didn't fail.
    public static func reminder(late: Bool) -> StatusTone { late ? .warning : .neutral }

    /// The tone an extension asked for on its page (good, warn, bad, info, neutral).
    public static func page(_ tone: ExtensionPage.Tone) -> StatusTone {
        switch tone {
        case .good: .success
        case .warn: .warning
        case .bad: .danger
        case .info: .news
        case .neutral: .neutral
        }
    }
}
