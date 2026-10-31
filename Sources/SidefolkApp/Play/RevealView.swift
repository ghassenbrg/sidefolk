import SidefolkCore
import SwiftUI

/// A result drawn as it happens (D75), fixed before it plays: two hands that meet in the middle, a coin that turns, dice
/// that tumble. With Reduce Motion the result shows at once.
struct RevealView: View {
    var reveal: GameBoard.Reveal
    var companionName: String
    /// When it began: the model's, so the build-up and the verdict boards share one reveal that never plays twice.
    var start: Date
    /// A fixed moment of it, for the UI snapshots.
    @Environment(\.revealProgress) private var fixed

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || fixed != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: still)) { t in
            let p = fixed ?? (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : min(1, t.date.timeIntervalSince(start) / GameSuspense.revealSeconds))
            switch reveal {
            case .hands(let you, let companion): HandsClash(you: you, companion: companion, p: p, companionName: companionName)
            case .coin(let heads): CoinFace(heads: p < 1 ? Int(p * 14).isMultiple(of: 2) : heads).frame(width: 64, height: 64)
                .scaleEffect(x: 1, y: p < 1 ? max(0.1, abs(cos(p * 14 * .pi / 2))) : 1)
            case .dice(let sides, let values):
                HStack(spacing: 10) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let face = p < 1 ? (Int(p * 18) * 7 + i * 3) % sides + 1 : v
                        DieView(sides: sides, value: face).frame(width: 44, height: 44).rotationEffect(.degrees((1 - p) * 400 * (i.isMultiple(of: 2) ? 1 : -1)))
                    }
                }
            }
        }
        .frame(height: 118)
        // VoiceOver hears the result with the verdict, not while it plays.
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    @Entry var revealProgress: Double? = nil
}

/// Rock, paper, scissors as a collision: both hands pump sealed three times ("Rock… paper… scissors…"), fly to the
/// middle and open on "shoot!", each on its own throw (`HandsReveal`), then the winner acts on the loser: rock cracks
/// scissors (the blades drop), paper covers rock (the rock sinks under it), scissors snip paper in two, and a draw bonks
/// both back. The winner's glow and crown take the verdict's colour (`GameColors`).
struct HandsClash: View {
    var you: Hand
    var companion: Hand
    var p: Double
    var companionName: String

    var body: some View {
        let state = HandsReveal(you: you, companion: companion, at: p)
        let pump = min(p / HandsReveal.opens, 1)
        let fly = min(max((p - HandsReveal.opens) / (HandsReveal.acts - HandsReveal.opens), 0), 1)
        let act = min(max((p - HandsReveal.acts) / (1 - HandsReveal.acts), 0), 1)
        let verdict = state.verdict
        let bounce = state.phase == .pumping ? abs(sin(pump * 3 * .pi)) * 14 : 0
        GeometryReader { geo in
            let w = geo.size.width, mid = w / 2, home = min(w * 0.3, 92)
            // They meet in the middle, then spring back a little: further for a draw, which bonks both.
            let gap = home - fly * (home - 30) + sin(act * .pi / 2) * (verdict == .draw ? 26 : 12)
            ZStack {
                if state.phase == .pumping {
                    Text(verbatim: Self.count(pump)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkMuted)
                        .position(x: mid, y: 12)
                } else if act < 0.9 {
                    Text(String(localized: "Shoot!", comment: "Rock, paper, scissors: the moment both hands show")).font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink).opacity(1 - act).position(x: mid, y: 12)
                }
                side(state.you, won: verdict == .win, lost: verdict == .loss, act: act, ended: p >= 1, mirrored: false).position(x: mid - gap, y: 56 - bounce)
                side(state.companion, won: verdict == .loss, lost: verdict == .win, act: act, ended: p >= 1, mirrored: true).position(x: mid + gap, y: 56 - bounce)
                if act > 0.02, act < 0.7 {
                    Image(systemName: verdict == .draw ? "equal" : "burst.fill").font(.system(size: verdict == .draw ? 18 : 24, weight: .bold))
                        .foregroundStyle(Theme.inkMuted.opacity(0.8)).position(x: mid, y: 52)
                        .scaleEffect(0.6 + act).opacity(1 - act / 0.7)
                }
                // The crown and the glow are the verdict: they come when the reveal has ended, never during it.
                label(String(localized: "You", comment: "Under the person's hand in rock, paper, scissors"),
                      crown: verdict == .win && p >= 1 ? GameColors.color(.win) : nil).position(x: mid - home, y: 106)
                label(companionName, crown: verdict == .loss && p >= 1 ? GameColors.color(.loss) : nil).position(x: mid + home, y: 106)
            }
        }
    }

    /// One side: sealed while the fists pump, then its own throw; the winner grows in its verdict's colour, the loser
    /// takes the winner's effect and stays itself.
    @ViewBuilder private func side(_ hand: Hand?, won: Bool, lost: Bool, act: Double, ended: Bool, mirrored: Bool) -> some View {
        if let hand {
            HandShape(hand: hand)
                .frame(width: 58, height: 58)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .modifier(Defeat(hand: hand, act: lost ? act : 0))
                .scaleEffect(won ? 1 + 0.18 * act : 1)
                .background {
                    if won, ended {
                        // The person's win in success green; the companion's win is the person's loss, in the calm tone.
                        Circle().fill((mirrored ? GameColors.color(.loss) : GameColors.color(.win)).opacity(0.2 * act)).frame(width: 84, height: 84)
                    }
                }
        } else {
            SealedHand().frame(width: 52, height: 52)
        }
    }

    private func label(_ text: String, crown: Color?) -> some View {
        HStack(spacing: 3) {
            if let crown { Image(systemName: "crown.fill").foregroundStyle(crown) }
            Text(verbatim: text).lineLimit(1)
        }
        .font(Theme.Font.captionStrong).foregroundStyle(crown == nil ? Theme.inkMuted : Theme.ink)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(Theme.surface.opacity(0.9)))
        .frame(width: 110)
    }

    static func count(_ pump: Double) -> String {
        switch Int(pump * 3) {
        case 0: String(localized: "Rock…", comment: "Rock, paper, scissors: the first beat of the count")
        case 1: String(localized: "Paper…", comment: "Rock, paper, scissors: the second beat of the count")
        default: String(localized: "Scissors…", comment: "Rock, paper, scissors: the third beat of the count")
        }
    }
}

/// A hand not shown yet: a closed token with a "?", neither rock, paper nor scissors.
struct SealedHand: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceSunken)
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1)
            Image(systemName: "questionmark").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.inkMuted)
        }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

/// What happens to the hand that lost, which always stays its own shape: scissors bend and drop, paper is cut in two,
/// rock sinks and fades under the paper that covered it.
struct Defeat: ViewModifier {
    var hand: Hand
    var act: Double

    func body(content: Content) -> some View {
        switch hand {
        case .scissors:
            content.rotationEffect(.degrees(act * 70)).offset(y: act * 24).opacity(1 - act * 0.5)
        case .paper:
            ZStack {
                content.mask(alignment: .leading) { Rectangle().frame(width: 29) }.rotationEffect(.degrees(-act * 14)).offset(x: -act * 9, y: act * 6)
                content.mask(alignment: .trailing) { Rectangle().frame(width: 29) }.rotationEffect(.degrees(act * 14)).offset(x: act * 9, y: act * 6)
            }
            .opacity(1 - act * 0.4)
        case .rock:
            content.scaleEffect(1 - act * 0.2).offset(y: act * 10).opacity(1 - act * 0.5)
        }
    }
}

/// A die by its sides: a d6 shows pips, the others their shape with the number on top.
struct DieView: View {
    var sides: Int
    var value: Int

    var body: some View {
        if sides == 6 { DieFace(value: value) } else { Polyhedron(sides: sides, value: value) }
    }
}
