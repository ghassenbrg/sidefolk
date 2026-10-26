import AppKit

/// What the idle scheduler decided at one tick.
enum Decision: Equatable {
    /// Nothing this time (the person is typing, or nothing fits).
    case still
    case posture(CharacterPosture)
    /// A moment, aimed at a screen point when it looks somewhere (a peek, a glance).
    case moment(CharacterAntic, toward: CGPoint?)
}

/// The choosing, without timers or views (so it can be tested): variety over repetition, rare
/// funny moments kept rare, stillness while the person types, and sleepier at night.
struct Mind {
    var profile: LifeProfile
    private(set) var recent: [CharacterAntic] = []
    private var lastRare = Date.distantPast
    private var lastTypingGlance = Date.distantPast

    /// Funny moments surprise only when they are rare.
    static let rare: Set<CharacterAntic> = [.sneeze, .doubleTake]
    static let rareGap: TimeInterval = 600
    /// What still fits sitting, and lying down.
    static let sitting: Set<CharacterAntic> = [.earTwitch, .yawn, .scratch, .glance, .peek]
    static let lying: Set<CharacterAntic> = [.earTwitch, .yawn, .glance]

    init(profile: LifeProfile) { self.profile = profile }

    static func isNight(_ hour: Int) -> Bool { hour >= 22 || hour < 6 }

    /// `quiet` is how long nothing has happened to the companion; `roll` returns 0..<1.
    mutating func decide(posture: CharacterPosture, quiet: TimeInterval, sinceKey: TimeInterval, now: Date, hour: Int,
                         window: CGRect?, pointer: CGPoint, roll: () -> Double) -> Decision {
        let night = Self.isNight(hour)
        if sinceKey < 2 {
            // Typing: hold still; now and then a look at the window the words go into.
            guard let window, now.timeIntervalSince(lastTypingGlance) > 45 else { return .still }
            lastTypingGlance = now
            return .moment(.glance, toward: CGPoint(x: window.midX, y: window.midY))
        }
        let sleepy = night ? 0.5 : 1
        if posture == .stand, let sit = profile.sitAfter, quiet > sit * sleepy { return .posture(.sit) }
        if posture == .sit, let lie = profile.lieAfter, quiet > lie * sleepy { return .posture(.lie) }

        var weights = profile.antics
        switch posture {
        case .stand: break
        case .sit: weights = weights.filter { Self.sitting.contains($0.key) }
        case .lie: weights = weights.filter { Self.lying.contains($0.key) }
        }
        if night {
            weights[.yawn] = weights[.yawn].map { $0 * 3 }
            weights[.hop] = nil
            weights[.wiggle] = nil
        }
        if window == nil { weights[.peek] = nil }
        recent.suffix(2).forEach { weights[$0] = nil }
        if now.timeIntervalSince(lastRare) < Self.rareGap { Self.rare.forEach { weights[$0] = nil } }

        let total = weights.values.reduce(0, +)
        guard total > 0 else { return .still }
        var pick = roll() * total
        // A stable order, so the same roll picks the same moment.
        var chosen = CharacterAntic.idle.first { weights[$0] != nil }!
        for antic in CharacterAntic.idle {
            guard let weight = weights[antic] else { continue }
            chosen = antic
            pick -= weight
            if pick < 0 { break }
        }
        recent = Array((recent + [chosen]).suffix(4))
        if Self.rare.contains(chosen) { lastRare = now }
        let target: CGPoint? = switch chosen {
        case .peek: window.map { CGPoint(x: $0.midX, y: $0.midY) }
        case .glance: window.map { CGPoint(x: $0.midX, y: $0.midY) } ?? pointer
        default: nil
        }
        return .moment(chosen, toward: target)
    }

    /// Seconds until the next tick.
    func nextTick(hour: Int, roll: Double) -> TimeInterval? {
        guard let every = profile.every else { return nil }
        let span = every.lowerBound + (every.upperBound - every.lowerBound) * roll
        return span * (Self.isNight(hour) ? 1.3 : 1)
    }
}

/// The idle scheduler of a live companion: one non-repeating timer, re-armed after each tick, only
/// while it is idle and on screen. Minimal liveliness and reduced motion don't run it at all.
@MainActor
final class Life {
    private(set) var mind: Mind
    private unowned let view: CharacterView
    private let senses: any Surroundings
    private var timer: Timer?
    /// When something last happened to the companion (a state change, the pointer, a click).
    private(set) var quietSince: Date
    /// Runs the clock this many times faster (demos and the render tool only).
    var pace: Double = 1

    init(profile: LifeProfile, view: CharacterView, senses: any Surroundings) {
        mind = Mind(profile: profile)
        self.view = view
        self.senses = senses
        quietSince = senses.now
    }

    var profile: LifeProfile {
        get { mind.profile }
        set { mind.profile = newValue }
    }

    func noteInteraction() { quietSince = senses.now }

    /// Starts or stops ticking to match the view: idle, in a window, motion allowed.
    func refresh() {
        let wanted = profile.every != nil && view.window != nil && !view.reducedMotion && view.state == .idle
        if !wanted {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            arm()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func arm() {
        let hour = Calendar.current.component(.hour, from: senses.now)
        guard let delay = mind.nextTick(hour: hour, roll: .random(in: 0..<1)).map({ $0 / pace }) else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = delay * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        timer = nil
        defer { refresh() }
        guard view.isOnScreen, view.performing == nil else { return }
        let now = senses.now
        let decision = mind.decide(posture: view.posture, quiet: now.timeIntervalSince(quietSince) * pace, sinceKey: senses.secondsSinceKey,
                                   now: now, hour: Calendar.current.component(.hour, from: now), window: senses.activeWindow,
                                   pointer: senses.pointer, roll: { .random(in: 0..<1) })
        switch decision {
        case .still: break
        case .posture(let posture): view.setPosture(posture, animated: true)
        case .moment(let antic, let target): view.perform(antic, toward: target, byItself: true)
        }
    }
}
