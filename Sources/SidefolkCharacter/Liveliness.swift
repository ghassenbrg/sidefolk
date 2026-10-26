import Foundation

/// How much life a companion shows on its own (docs/research/lively-companions.md).
public enum Liveliness: String, CaseIterable, Sendable {
    /// Today's companion (D20): it moves when something happens and settles after 20 s. It still
    /// answers the person's own hand (a click, a stroke, a drop), which costs nothing at rest.
    case minimal
    /// Small moments now and then while idle (an ear twitch, a stretch, a glance at what you are
    /// doing), sitting down and later lying down when nothing happens, startled by news, glad
    /// when something is done. Every level settles its loops after 20 s (D20); moments are one-shots.
    case balanced
    /// More often and more variety (hops, wiggles, sneezes, double-takes) and eyes that follow the
    /// pointer across the screen. Breathing still settles at 20 s: kept going, it would cost
    /// WindowServer about a tenth of a core all the time (docs/research, Measurements).
    case lively

    /// The numbers behind each level.
    var profile: LifeProfile {
        switch self {
        case .minimal:
            LifeProfile(every: nil, sitAfter: nil, lieAfter: nil, antics: [:], newsReactions: false)
        case .balanced:
            LifeProfile(every: 28...65, sitAfter: 100, lieAfter: 220,
                        antics: [.earTwitch: 3, .stretch: 1, .yawn: 1, .scratch: 1.2, .peek: 1.4, .glance: 2, .hop: 0.4,
                                 .sneeze: 0.25],
                        newsReactions: true)
        case .lively:
            LifeProfile(every: 10...26, sitAfter: 150, lieAfter: 300,
                        antics: [.earTwitch: 3, .stretch: 1, .yawn: 0.8, .scratch: 1.2, .peek: 1.4, .glance: 1.6, .hop: 1.4,
                                 .wiggle: 1.2, .sneeze: 0.5, .doubleTake: 0.7],
                        newsReactions: true)
        }
    }
}

/// One-shot moments of life: on its own while idle, or answering the person.
public enum CharacterAntic: String, CaseIterable, Sendable {
    // On its own, while idle.
    case earTwitch, stretch, yawn, scratch, hop, wiggle, peek, glance, sneeze, doubleTake
    // Answering the person or the news.
    case boop, pet, startle, cheer, land, spin, dizzy

    /// The ones the idle scheduler may pick.
    public static let idle: [CharacterAntic] = [.earTwitch, .stretch, .yawn, .scratch, .hop, .wiggle, .peek, .glance, .sneeze,
                                                .doubleTake]
}

/// How it holds itself while idle: standing, sitting, then lying down when nothing happens for long.
public enum CharacterPosture: String, CaseIterable, Sendable {
    case stand, sit, lie
}

/// What a liveliness level allows.
struct LifeProfile {
    /// Seconds between moments while idle; nil for none at all.
    var every: ClosedRange<TimeInterval>?
    /// Quiet seconds before it sits, then lies down; nil keeps it standing.
    var sitAfter: TimeInterval?
    var lieAfter: TimeInterval?
    /// Idle moments and how often each is picked, relative to the others.
    var antics: [CharacterAntic: Double]
    /// Startled by a notification, glad when a task is done.
    var newsReactions: Bool
}
