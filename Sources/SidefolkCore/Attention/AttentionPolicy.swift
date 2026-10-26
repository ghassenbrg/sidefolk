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
    /// All sources of one self-named kind together (every external agent, every session, every
    /// extension): a new name doesn't buy a new budget.
    public static let perFamilyLimit = 6
    /// Gentle bubbles per source and in total per window; past them a gentle item is a badge only.
    public static let gentlePerSourceLimit = 6
    public static let gentleLimit = 12
    public static let renudgeAfter: TimeInterval = 600

    /// Sources that may interrupt with `critical`: reminders and watchers (their creators are checked
    /// when they are made; only the user's own may be critical) and the user's own actions. Callers
    /// never pick these names: agents and extensions always post under a prefixed source.
    public static let criticalSources: Set<String> = ["reminder", "watcher", "user"]

    /// The shared budget a self-named source also counts against, if any.
    public static func family(_ source: String) -> String? {
        ["external:", "session:", "extension:", "routine:"].first { source.hasPrefix($0) }
    }

    /// - Parameters:
    ///   - recent: when earlier attention-level items were presented, with their source.
    ///   - gentle: when earlier gentle items were presented, with their source.
    public static func decide(
        level: AttentionLevel, source: String, createdAt: Date, now: Date, env: AttentionEnvironment,
        recent: [(source: String, at: Date)], gentle: [(source: String, at: Date)] = []
    ) -> AttentionDecision {
        let level = level == .critical && !criticalSources.contains(source) ? .attention : level
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

        if level == .gentle {
            // Bubbles are cheap to send: past the budget they only add to the badge (T24).
            let window = (recent + gentle).filter { now.timeIntervalSince($0.at) < perSourceWindow }
            let mine = window.filter { $0.source == source || (family(source) != nil && family($0.source) == family(source)) }
            let bubbles = gentle.filter { now.timeIntervalSince($0.at) < perSourceWindow }
            if mine.count >= gentlePerSourceLimit || bubbles.count >= gentleLimit { return .present(.ambient) }
            return .present(.gentle(autoDismiss: gentleSeconds))
        }

        // Reminders arrive at the time the user chose; spacing them out would make them late.
        if source == "reminder" { return .present(.attention(expandFor: expandSeconds)) }

        // Rate limits for attention: spacing overall, a per-source budget and a per-family budget.
        if let last = recent.map(\.at).max(), now.timeIntervalSince(last) < attentionSpacing {
            return .hold(until: last.addingTimeInterval(attentionSpacing))
        }
        let window = recent.filter { now.timeIntervalSince($0.at) < perSourceWindow }
        let sameSource = window.filter { $0.source == source }
        if sameSource.count >= perSourceLimit {
            let oldest = sameSource.map(\.at).min()!
            return .hold(until: oldest.addingTimeInterval(perSourceWindow))
        }
        if let family = family(source) {
            let sameFamily = window.filter { $0.source.hasPrefix(family) }
            if sameFamily.count >= perFamilyLimit {
                let oldest = sameFamily.map(\.at).min()!
                return .hold(until: oldest.addingTimeInterval(perSourceWindow))
            }
        }
        return .present(.attention(expandFor: expandSeconds))
    }
}
