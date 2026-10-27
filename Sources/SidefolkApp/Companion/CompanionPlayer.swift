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

    /// Ends a game early (the person dragged the companion away, or chose Stop Playing).
    func stop() {
        guard game != nil else { return }
        run?.cancel()
        run = nil
        if game == .catchMe, let home { companion.hop(to: home) }
        game = nil
        catchable = false
        caption.hide()
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

/// One line of text above the companion while a game runs. It never takes a click: catch-me needs them all.
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

    /// Shows `text`, for `seconds` when given (then it goes), otherwise until the next line.
    func show(_ text: String, for seconds: TimeInterval? = nil) {
        hiding?.cancel()
        model.text = text
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
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
    }
}

@MainActor @Observable
final class CaptionModel {
    var text = ""
}

struct CaptionView: View {
    var model: CaptionModel

    var body: some View {
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
            .padding(10)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
