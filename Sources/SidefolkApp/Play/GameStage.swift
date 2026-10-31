import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The companion in the game's scene, saying the board's prompt in a speech bubble. Over a table (cups, pads, sticks,
/// the Boop button) it peeks over it in the middle, the bubble above; over a bigger board it sits small at the side of
/// its bubble. While Sidefolk plays its own part (the cups shuffling, the pads' sequence) the bubble says so.
struct GameStage: View {
    var model: PlayModel
    var board: GameBoard
    var prompt: GameBoard.Prompt?
    var style: GameStyle
    /// Peeking over a table that follows, rather than at the side.
    var peeking: Bool

    private var words: String? {
        if board.cups != nil, model.parts.shuffling {
            return String(localized: "Shuffling…", comment: "Which Cup?: the companion shuffles the cups") + " 👀"
        }
        if board.pads != nil, model.parts.playing { return String(localized: "Watch…", comment: "Copy Me: the companion shows the sequence to copy") }
        return prompt?.text ?? board.result?.line
    }

    private var pose: NSImage? {
        let verdict = board.result.map { GameVerdict(tone: $0.tone) }
        let state = model.parts.shuffling || model.parts.playing ? CharacterState.thinking
            : GameFigures.state(for: board.cue?.move, over: board.over, verdict: verdict)
        return model.figure?(state) ?? model.portrait
    }

    var body: some View {
        VStack(spacing: 8) {
            if let eyebrow = prompt?.eyebrow { RoundChip(text: eyebrow, style: style) }
            if peeking {
                VStack(spacing: 2) {
                    if let words { SpeechBubble(text: words, chip: prompt?.chip, clock: model.clock, tail: .bottom) }
                    CompanionPeek(picture: pose, width: 96, share: 0.74, beat: model.turn)
                }
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    CompanionPeek(picture: pose, width: 66, share: 0.8, beat: model.turn)
                        .clipped()
                    if let words { SpeechBubble(text: words, chip: prompt?.chip, clock: model.clock, tail: .leading) }
                    else { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "Round 2 of 5 · Fair": the board's eyebrow as a pill, its first part bold.
struct RoundChip: View {
    var text: String
    var style: GameStyle

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        HStack(spacing: 6) {
            Text(verbatim: parts[0]).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            if parts.count > 1 {
                Text(verbatim: parts.dropFirst().joined(separator: " · ")).font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(style.onColor)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(style.color))
            }
        }
        .lineLimit(1)
        .padding(.leading, 11).padding(.trailing, parts.count > 1 ? 4 : 11).padding(.vertical, 3)
        .background(Capsule().fill(Theme.surface.opacity(0.94)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
    }
}

/// A rounded bubble with a tail toward whoever speaks: the companion's prompt, a topic chip, the time left.
struct SpeechBubble: View {
    nonisolated enum Tail: Sendable { case bottom, leading }
    var text: String
    var chip: String?
    var clock: (id: String, start: Date, seconds: Double)?
    var tail: Tail

    var body: some View {
        VStack(alignment: tail == .bottom ? .center : .leading, spacing: 6) {
            if let chip {
                Text(verbatim: chip).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            Text(verbatim: text)
                .font(.system(size: tail == .bottom ? 18 : 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(tail == .bottom ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(5)
            if let clock { TimerBar(clock: clock, id: clock.id) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: tail == .bottom ? 320 : .infinity, alignment: tail == .bottom ? .center : .leading)
        .background(SpeechBubbleShape(tail: tail).fill(Theme.surface).flipsForRightToLeftLayoutDirection(true).shadow(color: .black.opacity(0.12), radius: 6, y: 3))
        .contentTransition(.opacity)
    }
}

/// A rounded rectangle with a small tail at the bottom middle, or on the leading side near the bottom.
nonisolated struct SpeechBubbleShape: Shape {
    var tail: SpeechBubble.Tail

    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 18, style: .continuous)
        switch tail {
        case .bottom:
            p.move(to: CGPoint(x: r.midX - 10, y: r.maxY - 1))
            p.addQuadCurve(to: CGPoint(x: r.midX + 2, y: r.maxY + 11), control: CGPoint(x: r.midX - 2, y: r.maxY + 6))
            p.addQuadCurve(to: CGPoint(x: r.midX + 10, y: r.maxY - 1), control: CGPoint(x: r.midX + 5, y: r.maxY + 4))
        case .leading:
            p.move(to: CGPoint(x: r.minX + 1, y: r.maxY - 26))
            p.addQuadCurve(to: CGPoint(x: r.minX - 10, y: r.maxY - 10), control: CGPoint(x: r.minX - 4, y: r.maxY - 16))
            p.addQuadCurve(to: CGPoint(x: r.minX + 1, y: r.maxY - 12), control: CGPoint(x: r.minX - 3, y: r.maxY - 10))
        }
        return p
    }
}
