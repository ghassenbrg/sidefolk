import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The companion in the game's scene, saying the board's prompt in a speech bubble. Over a table (cups, pads, sticks,
/// the Boop button) it stands on the table's back edge beside its bubble, its feet over the table (the board raises the
/// stage above the table drawn after it); over a bigger board it stands small at the side of its bubble. While Sidefolk
/// plays its own part (the cups shuffling, the pads' sequence) the bubble says so.
struct GameStage: View {
    var model: PlayModel
    var board: GameBoard
    var prompt: GameBoard.Prompt?
    var style: GameStyle
    /// Standing on a table that follows, rather than small at the side.
    var peeking: Bool
    /// How far the companion's feet reach onto the table below the stage.
    static let sink: CGFloat = 12

    /// Beside its bubble the companion is a presence, not a stamp; over a board that needs every point (a puzzle, a
    /// keyboard, a field of letters) it stays small.
    private var side: CGFloat {
        board.puzzle != nil || board.keys != nil || board.letters != nil || board.answers != nil ? 56 : 70
    }

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
        VStack(spacing: 6) {
            if let eyebrow = prompt?.eyebrow, !(board.over && board.result != nil) {
                RoundChip(text: eyebrow, style: style)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        // A puzzle's clock and Sudoku's notes switch share the eyebrow's row, so a 9 × 9 board keeps its room.
                        if let puzzle = board.puzzle, let seconds = puzzle.seconds {
                            HStack {
                                PuzzleClock(seconds: seconds, running: puzzle.running, since: model.parts.puzzleShown)
                                Spacer(minLength: 0)
                                if puzzle.input == .digits, !puzzle.locked { NotesSwitch(model: model) }
                            }
                        }
                    }
            }
            HStack(alignment: peeking ? .top : .bottom, spacing: 6) {
                let figure = CompanionFigure(picture: pose, size: peeking ? CGSize(width: 104, height: 100) : CGSize(width: side, height: side),
                                             beat: model.turn)
                Group {
                    if let catching = board.companionButton { CatchableFigure(figure: figure, button: catching, model: model) } else { figure }
                }
                // On a table: the feet sink a little past the stage's edge, onto the table's top.
                .padding(.bottom, peeking ? -Self.sink : 0)
                if let words { SpeechBubble(text: words, chip: prompt?.chip, clock: model.clock, tail: .leading) }
                else { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity)
        // The prompt reads as one header; a companion that can be clicked stays its own button for VoiceOver.
        .accessibilityElement(children: board.companionButton == nil ? .combine : .contain)
        .accessibilityAddTraits(board.companionButton == nil ? .isHeader : [])
    }
}

/// The companion as a button (a board's `companion` button: Which Cup?'s "Check its paw"): clicking it, during the
/// shuffle or before the cups lift, makes the button's move. A small badge with the button's symbol on its shoulder
/// and the pointing hand say it can be clicked; the button's key still works and its words are the tooltip.
struct CatchableFigure: View {
    var figure: CompanionFigure
    var button: GameBoard.Button
    var model: PlayModel
    @State private var hovered = false

    var body: some View {
        Button { model.send(.button(button.move)) } label: {
            figure
                .overlay(alignment: .topTrailing) {
                    Image(systemName: button.symbol ?? "hand.tap.fill").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(hovered ? Theme.onAccent : Theme.accent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(hovered ? Theme.accent : Theme.surface).shadow(color: .black.opacity(0.15), radius: 2, y: 1))
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle())
        .focusable(false)
        .onHover { inside in
            hovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hovered { NSCursor.pop() } }
        .help(button.label)
        #if DEBUG
        .background(GeometryReader { g in Color.clear.onAppear { model.catchFrame = g.frame(in: .global) } })
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.send(.button(button.move)) }
    }
}

/// "Round 2 of 5 · Fair": the board's eyebrow as a pill, its first part bold, the level on a chip in the game's
/// colour (never red, `GameStyle.levelChip`).
struct RoundChip: View {
    var text: String
    var style: GameStyle

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        HStack(spacing: 6) {
            Text(verbatim: parts[0]).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            if parts.count > 1 {
                Text(verbatim: parts.dropFirst().joined(separator: " · ")).font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(style.onColor)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(style.levelChip))
            }
        }
        .lineLimit(1)
        .padding(.leading, 12).padding(.trailing, parts.count > 1 ? 4 : 12).padding(.vertical, 4)
        .background(Capsule().fill(GamePaint.card.opacity(0.96)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
        .overlay(Capsule().strokeBorder(GamePaint.edge, lineWidth: 1))
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
                .font(.system(size: tail == .bottom ? 18 : 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(tail == .bottom ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(5)
            if let clock { TimerBar(clock: clock, id: clock.id) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: tail == .bottom ? 320 : .infinity, alignment: tail == .bottom ? .center : .leading)
        .background {
            SpeechBubbleShape(tail: tail).fill(GamePaint.card).shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                .overlay(SpeechBubbleShape(tail: tail).stroke(GamePaint.edge, lineWidth: 1))
                .flipsForRightToLeftLayoutDirection(true)
        }
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
