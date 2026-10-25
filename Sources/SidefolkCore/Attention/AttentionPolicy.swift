import Foundation

/// What the user is doing right now, as far as interruptions are concerned. The app keeps it current.
public struct AttentionEnvironment: Sendable, Equatable {
    public var quiet = false
    public var presence: PresenceMode = .always
    /// The frontmost app is fullscreen (video, presentation, game).
    public var fullscreen = false
    /// No input for a while, or the screen is locked.
    public var away = false
    /// Last keystroke anywhere (typing guard).
    public var lastKeyAt: Date?
    /// System notifications are allowed by the user (and macOS).
    public var systemNotificationsAllowed = true
    public var sounds = true
    public init() {}
}

public enum AttentionDecision: Sendable, Equatable {
    case present(AttentionPresentation)
    /// Hold and look again at this time (or when the environment changes).
    case hold(until: Date?)
}

/// Pure interruption rules (docs/PRODUCT.md §11). Kept free of state so it is easy to test.
public enum AttentionPolicy {
    public static let gentleSeconds: TimeInterval = 6
    public static let expandSeconds: TimeInterval = 30
    public static let typingQuiet: TimeInterval = 1.5
    public static let typingMaxDefer: TimeInterval = 20
    public static let attentionSpacing: TimeInterval = 90
    public static let perSourceWindow: TimeInterval = 600
    public static let perSourceLimit = 3
    public static let renudgeAfter: TimeInterval = 600

    /// - Parameters:
    ///   - recent: when earlier attention-level items were presented, with their source.
    public static func decide(
        level: AttentionLevel, source: String, createdAt: Date, now: Date, env: AttentionEnvironment,
        recent: [(source: String, at: Date)]
    ) -> AttentionDecision {
        if level == .ambient { return .present(.ambient) }

        let canSystem = env.systemNotificationsAllowed
        if level == .critical {
            return .present(.system(sound: env.sounds, alsoOnDesktop: !(env.fullscreen || env.presence == .menuBarOnly)))
        }

        // Away: queue, a summary is shown on return.
        if env.away { return .hold(until: nil) }

        if env.quiet || env.fullscreen {
            // Gentle things wait; explicit reminders and watches still reach you quietly.
            if level == .gentle { return .hold(until: nil) }
            return canSystem ? .present(.system(sound: false, alsoOnDesktop: false)) : .hold(until: nil)
        }

        if env.presence == .menuBarOnly {
            if level == .gentle { return .present(.ambient) }
            return canSystem ? .present(.system(sound: env.sounds, alsoOnDesktop: false)) : .present(.attention(expandFor: expandSeconds))
        }

        // Typing guard: wait for a pause, but never longer than the max deferral.
        if let key = env.lastKeyAt, now.timeIntervalSince(key) < typingQuiet, now.timeIntervalSince(createdAt) < typingMaxDefer {
            return .hold(until: key.addingTimeInterval(typingQuiet))
        }

        if level == .gentle { return .present(.gentle(autoDismiss: gentleSeconds)) }

        // Rate limits for attention: spacing overall and a per-source budget.
        if let last = recent.map(\.at).max(), now.timeIntervalSince(last) < attentionSpacing {
            return .hold(until: last.addingTimeInterval(attentionSpacing))
        }
        let sameSource = recent.filter { $0.source == source && now.timeIntervalSince($0.at) < perSourceWindow }
        if sameSource.count >= perSourceLimit {
            let oldest = sameSource.map(\.at).min()!
            return .hold(until: oldest.addingTimeInterval(perSourceWindow))
        }
        return .present(.attention(expandFor: expandSeconds))
    }
}
