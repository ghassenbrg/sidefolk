import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Tricks and games with the companion (D44). A trick plays at once. Catch-me and the breathing exercise run for a
/// little while with one line of text above the companion, and put it back where the person keeps it.
final class CompanionPlayer {
    private let companion: CompanionWindowController
    private let caption = CompanionCaption()
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
        guard game != nil else { return }
        if game == .catchMe, let home { companion.hop(to: home) }
        game = nil
        catchable = false
    }

    // MARK: Chance (D44, amended)

    /// The companion name under its hand in rock, paper, scissors.
    var companionName = ""

    /// Plays what core drew: the companion flicks the coin, throws the dice or pumps its fist, the objects fly above it
    /// and land on the result, then the result is said and stays a few seconds. `done` runs once it has gone.
    func toss(_ toss: Toss, done: @escaping @MainActor () -> Void = {}) {
        stop()
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // When the objects leave its paws, and how long they fly, from the moments' own beats (Antics).
        let (antic, launch, flight, waiting): (CharacterAntic, TimeInterval, TimeInterval, String) = switch toss {
        case .coins: (.flick, 0.32, 1.04, String(localized: "Heads or tails…", comment: "Said while a coin spins in the air"))
        case .dice: (.roll, 0.96, 0.9, String(localized: "Rolling…", comment: "Said while dice tumble in the air"))
        case .hands: (.pump, 0, 1.12, String(localized: "Rock… paper… scissors…", comment: "Said while the companion pumps its fist"))
        }
        companion.character.perform(antic)
        var show = TossShow(toss: toss, start: Date().addingTimeInterval(launch), flight: flight, still: still)
        caption.show(still ? toss.result : waiting, stage: show, announce: still, companionName: companionName)
        run = Task { [weak self] in
            try? await Task.sleep(for: .seconds(still ? 0.2 : launch + flight))
            guard let self, !Task.isCancelled else { return }
            show.landed = true
            caption.show(toss.result, stage: show, for: 5, companionName: companionName)
            if case .hands(let person, let mine) = toss {
                // A good sport: a bow when the person wins, a cheer when it does, a nod for a draw.
                companion.character.perform(person == mine ? .nod : person.beats == mine ? .bow : .cheer)
            }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            done()
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

/// One line of text above the companion while a game runs, and what it flipped, rolled or played above that line.
/// It never takes a click: catch-me needs them all.
final class CompanionCaption {
    private let model = CaptionModel()
    private lazy var hosted: HostedPanel<CaptionView> = {
        let hosted = HostedPanel(rootView: CaptionView(model: model), allowsKey: false)
        hosted.panel.ignoresMouseEvents = true
        hosted.panel.hasShadow = false
        return hosted
    }()
    private var hiding: Task<Void, Never>?
    var anchorProvider: (() -> (NSRect, NSScreen)?)?

    /// Shows `text` (and `stage` beneath it), for `seconds` when given (then it goes), otherwise until the next line.
    /// `announce: false` keeps a passing line ("Rolling…") from VoiceOver, which hears the result.
    func show(_ text: String, stage: TossShow? = nil, for seconds: TimeInterval? = nil, announce: Bool = true, companionName: String = "") {
        hiding?.cancel()
        model.text = text
        model.stage = stage
        model.companionName = companionName
        if announce {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        reposition()
        if !hosted.panel.isVisible { hosted.panel.orderFrontRegardless() }
        guard let seconds else { return }
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func reposition() {
        guard let (anchor, screen) = anchorProvider?() else { return }
        // Sized to this line first: a visible panel keeps its size when placed, and a longer line would be cut.
        hosted.panel.setContentSize(hosted.fittingSize)
        hosted.place(beside: anchor, on: screen, gap: 2, preferAbove: true)
    }

    func hide() {
        hiding?.cancel()
        hosted.panel.orderOut(nil)
        // Nothing left to animate while it is away.
        model.stage = nil
    }
}

@MainActor @Observable
final class CaptionModel {
    var text = ""
    var stage: TossShow?
    var companionName = ""
}

struct CaptionView: View {
    var model: CaptionModel

    var body: some View {
        // The objects sit nearest the companion, whom they fly up from; the words are on top.
        VStack(spacing: 6) {
            Text(verbatim: model.text)
                .font(Theme.Font.bubbleTitle)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
                        .strokeBorder(Theme.folkColor("play").opacity(0.5), lineWidth: 1)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
            if let stage = model.stage { TossStage(show: stage, companionLabel: model.companionName) }
        }
        .padding(10)
        .fixedSize()
        .accessibilityHidden(true)
    }
}
