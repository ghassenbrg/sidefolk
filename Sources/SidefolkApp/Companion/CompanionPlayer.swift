import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Tricks and games with the companion (D44). A trick plays at once. Catch-me and the breathing exercise run for a
/// little while with one line of text above the companion, and put it back where the person keeps it.
final class CompanionPlayer {
    private let companion: CompanionWindowController
    /// The line above the companion, shared with the Play panel's cues (D75).
    let caption = CompanionCaption()
    /// The game being played, if any.
    private(set) var game: CompanionAct?
    private var run: Task<Void, Never>?
    // Catch-me: the score, where the companion lives, and whether a boop now counts (not while it is mid-hop).
    private var caught = 0
    private var home: NSPoint?
    private var catchable = false

    static let catchSeconds: TimeInterval = 20
    static let breaths = 5
    static let bestKey = "companion.catchBest"

    init(companion: CompanionWindowController) {
        self.companion = companion
    }

    var anchorProvider: (() -> (NSRect, NSScreen)?)? {
        get { caption.anchorProvider }
        set { caption.anchorProvider = newValue }
    }

    func play(_ act: CompanionAct) {
        switch act {
        case .catchMe: startCatching()
        case .breathe: startBreathing()
        default: trick(act)
        }
    }

    static let tricks: [CompanionAct: CharacterAntic] = [
        .dance: .dance, .wave: .wave, .bow: .bow, .flip: .spin, .hop: .hop, .cheer: .cheer, .nod: .nod, .giggle: .giggle,
    ]

    private func trick(_ act: CompanionAct) {
        companion.character.perform(Self.tricks[act] ?? [.dance, .wave, .bow, .spin, .giggle, .hop].randomElement()!)
    }

    /// Ends a game, or a toss still in the air, early (the person dragged the companion away, chose Stop Playing, or
    /// asked for something else to play).
    func stop() {
        run?.cancel()
        run = nil
        caption.hide()
        caption.offerAgain(nil)
        guard game != nil else { return }
        if game == .catchMe, let home { companion.hop(to: home) }
        game = nil
        catchable = false
    }

    // MARK: Chance (D44, amended)

    /// The companion name under its hand in rock, paper, scissors.
    var companionName = ""

    /// When the toss being played lands.
    private var landsAt: Date?
    /// The longest a toss is in the air and settling (dice: thrown at 0.96 s, 0.9 s of flight, then 0.6 s to rest).
    static let longestToss: TimeInterval = 2.46

    /// How long a coin's or a die's card should wait, so the Ask panel doesn't say "Heads!" while the coin still spins.
    /// The tool's card can come before its event reaches the player; then it waits for the longest toss.
    func untilLanded(now: Date = Date()) -> TimeInterval {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        guard let landsAt, landsAt > now else { return Self.longestToss }
        return landsAt.timeIntervalSince(now)
    }

    /// The companion's face, embossed on the coin.
    var face: NSImage? {
        get { caption.model.face }
        set { caption.model.face = newValue }
    }
    /// Calls the person got right in a row, for the streak sparkles.
    private var calledRight = 0

    /// Plays what core drew: the companion flicks the coin, throws the dice or pumps its fist, the objects fly above it
    /// and land on the result, then the companion reacts and the result stays a few seconds under an Again pill.
    /// `again` plays the same toss once more; `done` runs once it has gone.
    func toss(_ toss: Toss, again: (() -> Void)? = nil, done: @escaping @MainActor () -> Void = {}) {
        stop()
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // When the objects leave its paws, and how long they fly, from the moments' own beats (Antics).
        let (antic, launch, flight, waiting): (CharacterAntic, TimeInterval, TimeInterval, String) = switch toss {
        case .coins: (.flick, 0.32, 1.2, String(localized: "Heads or tails…", comment: "Said while a coin spins in the air"))
        case .dice: (.roll, 0.96, 0.9, String(localized: "Rolling…", comment: "Said while dice tumble in the air"))
        case .hands: (.pump, 0, 1.12, String(localized: "Rock… paper… scissors…", comment: "Said while the companion pumps its fist"))
        }
        companion.character.perform(antic)
        landsAt = Date().addingTimeInterval(still ? 0 : launch + flight + TossShow.settle)
        var show = TossShow(toss: toss, start: Date().addingTimeInterval(launch), flight: flight, still: still)
        caption.show(still ? "" : waiting, stage: show, announce: false, companionName: companionName)
        run = Task { [weak self] in
            try? await Task.sleep(for: .seconds(still ? 0.2 : launch + flight))
            guard let self, !Task.isCancelled else { return }
            // The wobble or the clash plays out first.
            if !still { try? await Task.sleep(for: .seconds(TossShow.settle)) }
            guard !Task.isCancelled else { return }
            show.landed = true
            let (move, line) = reaction(to: toss)
            caption.show(line ?? "", stage: show, for: 5, announce: false, companionName: companionName)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: [toss.result, line].compactMap { $0 }.joined(separator: " "),
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            if let again, game == nil, !Self.isHands(toss) { caption.offerAgain(again) }
            if let move { companion.character.perform(move) }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            done()
        }
    }

    private static func isHands(_ toss: Toss) -> Bool { if case .hands = toss { true } else { false } }

    /// How the companion takes what came up (D75): a call right or wrong, a natural 20 or a 1, doubles, a hand won or lost.
    private func reaction(to toss: Toss) -> (CharacterAntic?, String?) {
        switch toss {
        case .coins:
            guard let right = toss.called else { return (.nod, nil) }
            calledRight = right ? calledRight + 1 : 0
            if right, calledRight >= 3, calledRight.isMultiple(of: 3) {
                caption.flash(.sparkles)
                return (.cheer, String(localized: "\(calledRight) in a row!", comment: "The companion: the person called the coin right several times"))
            }
            return right ? (.cheer, String(localized: "You called it!", comment: "The companion: the person called the coin right"))
                : (.giggle, String(localized: "Next one's yours.", comment: "The companion: the person called the coin wrong"))
        case .dice(let sides, let rolls, _):
            if sides == 20, rolls.count == 1, rolls[0] == 20 {
                caption.flash(.sparkles)
                return (.cheer, String(localized: "Natural 20!", comment: "The companion: a d20 landed on 20"))
            }
            if sides == 20, rolls.count == 1, rolls[0] == 1 { return (.startle, String(localized: "Oof.", comment: "The companion: a d20 landed on 1")) }
            if sides == 6, rolls == [1, 1] { return (.giggle, String(localized: "Snake eyes!", comment: "The companion: two dice both landed on 1")) }
            if rolls.count == 2, rolls[0] == rolls[1] { return (.cheer, String(localized: "Doubles!", comment: "The companion: two dice landed on the same face")) }
            return (.nod, nil)
        case .hands(let person, let mine):
            // A good sport: a bow when the person wins, a cheer when it does, a nod for a draw.
            return (person == mine ? .nod : person.beats == mine ? .bow : .cheer, nil)
        }
    }

    // MARK: Catch me

    /// A click on the companion: a catch while catch-me runs. True when the game took the click.
    func click() -> Bool {
        guard game == .catchMe else { return false }
        guard catchable else { return true }
        caught += 1
        catchable = false
        caption.show(String(localized: "Caught: \(caught)", comment: "A score in the catch-me game"))
        hopAway()
        return true
    }

    private func startCatching() {
        stop()
        game = .catchMe
        caught = 0
        home = companion.panel.frame.origin
        run = Task { [weak self] in
            for n in [3, 2, 1] {
                self?.caption.show(String(localized: "Catch me in \(n)…", comment: "Counting down to the catch-me game"))
                try? await Task.sleep(for: .seconds(0.8))
            }
            guard let self, !Task.isCancelled else { return }
            caption.show(String(localized: "Go!"))
            let end = Date().addingTimeInterval(Self.catchSeconds)
            var stay = 1.6
            while Date() < end, !Task.isCancelled {
                hopAway()
                try? await Task.sleep(for: .seconds(stay))
                // Faster as the game goes on.
                stay = max(0.8, stay - 0.06)
            }
            guard !Task.isCancelled else { return }
            finishCatching()
        }
    }

    /// Somewhere else near its spot, along its floor and now and then a little above it, always on screen.
    private func hopAway() {
        guard let home else { return }
        let screen = companion.screen.visibleFrame, size = companion.panel.frame.size, now = companion.panel.frame.origin
        var spot = now
        for _ in 0..<12 where hypot(spot.x - now.x, spot.y - now.y) < 90 {
            spot = NSPoint(x: home.x + .random(in: -340...340), y: home.y + (Bool.random() ? 0 : .random(in: 20...140)))
            spot.x = min(max(spot.x, screen.minX), screen.maxX - size.width)
            spot.y = min(max(spot.y, home.y), screen.maxY - size.height)
        }
        companion.hop(to: spot) { [weak self] in
            guard let self, self.game == .catchMe else { return }
            self.catchable = true
            self.caption.reposition()
        }
    }

    private func finishCatching() {
        catchable = false
        let best = UserDefaults.standard.integer(forKey: Self.bestKey)
        let record = caught > best
        if record { UserDefaults.standard.set(caught, forKey: Self.bestKey) }
        if let home { companion.hop(to: home) { [weak self] in self?.caption.reposition() } }
        game = nil
        run = Task { [weak self, caught] in
            try? await Task.sleep(for: .seconds(0.45))
            guard let self, !Task.isCancelled else { return }
            companion.character.perform(caught > 0 ? .cheer : .giggle)
            caption.show(record && best > 0
                ? String(localized: "Time's up! Caught: \(caught), a new best!", comment: "The end of the catch-me game")
                : String(localized: "Time's up! Caught: \(caught). Best: \(max(best, caught)).", comment: "The end of the catch-me game"),
                for: 5)
        }
    }

    // MARK: Breathing

    /// Five slow breaths: in for four seconds, hold one, out for six, with the companion breathing along.
    private func startBreathing() {
        stop()
        game = .breathe
        run = Task { [weak self] in
            for round in 1...Self.breaths {
                guard let self, !Task.isCancelled else { return }
                companion.character.perform(.breathe)
                caption.show(String(localized: "Breathe in… (\(round) of \(Self.breaths))", comment: "A breathing exercise: round 1 of 5"))
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                caption.show(String(localized: "Hold…", comment: "A breathing exercise: hold your breath"))
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                caption.show(String(localized: "Breathe out…", comment: "A breathing exercise"))
                try? await Task.sleep(for: .seconds(6))
            }
            guard let self, !Task.isCancelled else { return }
            game = nil
            companion.character.perform(.nod)
            caption.show(String(localized: "Nicely done. A little calmer?", comment: "The end of the breathing exercise"), for: 5)
        }
    }
}
