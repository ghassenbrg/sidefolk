import SidefolkCore
import SwiftUI

/// The board's parts, top to bottom, each drawn by Sidefolk. The prompt is the companion's, said in its bubble in the
/// scene (`GameStage`); a table prop (cups, pads, sticks, the Boop button) stands on the scene's table, the companion
/// peeking over it. Buttons that follow one another share a row.
struct BoardView: View {
    var model: PlayModel
    var board: GameBoard
    var style: GameStyle = .of(nil)

    /// The parts with neighbouring buttons gathered into one row, and the prompt as the companion's stage.
    private enum Item: Identifiable {
        case stage(Int, GameBoard.Prompt?)
        case part(Int, GameBoard.Part)
        case buttons(Int, [GameBoard.Button])
        var id: Int { switch self { case .stage(let i, _), .part(let i, _), .buttons(let i, _): i } }
    }

    /// The end card stands in for the play area: the last move was seen in its build-up, and the board under the card
    /// would push the panel past a small screen. What isn't play (notes, facts, a level to pick, buttons) stays.
    private var ended: Bool { board.over && board.result != nil }

    private static func isPlay(_ part: GameBoard.Part) -> Bool {
        switch part {
        case .answers, .board, .cups, .pads, .reflex, .meter, .number, .letters, .keys, .entry, .sticks, .lives, .timer, .puzzle: true
        default: false
        }
    }

    private var items: [Item] {
        var out: [Item] = []
        for (i, part) in board.parts.enumerated() {
            if ended, Self.isPlay(part) { continue }
            // The end card holds the level picker itself, so they don't stack.
            if ended, case .choice(let c) = part, c.style == .segmented { continue }
            if case .button(let b) = part {
                // A button the companion stands for is clicked on the companion in the scene (GameStage).
                if b.companion { continue }
                if case .buttons(let at, let row)? = out.last { out[out.count - 1] = .buttons(at, row + [b]) } else { out.append(.buttons(i, [b])) }
            } else if case .score = part {
                continue // on the score bar
            } else if case .prompt(let p) = part {
                out.append(.stage(i, p))
            } else {
                out.append(.part(i, part))
            }
        }
        // A board without words still has the companion in its scene, unless it is the end card alone.
        if !out.contains(where: { if case .stage = $0 { true } else { false } }), board.result == nil {
            out.insert(.stage(-1, nil), at: 0)
        }
        return out
    }

    /// The small choices an end card offers (the level for the next game), drawn inside it.
    private var endChoices: [GameBoard.Choice] {
        guard ended else { return [] }
        return board.parts.compactMap { if case .choice(let c) = $0, c.style == .segmented { c } else { nil } }
    }

    private var prompt: GameBoard.Prompt? { board.parts.lazy.compactMap { if case .prompt(let p) = $0 { p } else { nil } }.first }

    /// The companion peeks over a table prop in the middle of the scene; over anything bigger it sits at the side.
    private var peeking: Bool {
        board.result == nil && (board.cups != nil || board.pads != nil || board.sticks != nil || board.reflex != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                switch item {
                // Above the table drawn after it, so the companion stands on it.
                case .stage(_, let prompt): GameStage(model: model, board: board, prompt: prompt, style: style, peeking: peeking).zIndex(1)
                case .buttons(_, let row): GameButtonRow(buttons: row, model: model)
                case .part(_, let part): view(part)
                }
            }
        }
        .animation(Theme.Motion.spring(0.35), value: model.turn)
    }

    @ViewBuilder private func view(_ part: GameBoard.Part) -> some View {
        switch part {
        case .prompt: EmptyView()
        case .answers(let a): AnswersView(answers: a, model: model)
        case .board(let g): GameGridView(grid: g, model: model)
        case .result(let r): GameResultView(result: r, model: model, said: prompt?.text, choices: endChoices)
        case .reveal(let r): RevealView(reveal: r, companionName: model.companionName, start: model.revealStart).frame(maxWidth: .infinity)
            .gameCard(opacity: 0.92)
        case .note(let n): GameNoteView(note: n)
        case .facts(let f): GameFactsView(facts: f)
        case .choice(let c): GameChoiceView(choice: c, model: model)
        case .timer(let t): if board.parts.contains(where: { if case .prompt = $0 { true } else { false } }) == false {
            TimerBar(clock: model.clock, id: t.id)
        }
        case .score, .button: EmptyView()
        case .pads(let p): PadsView(pads: p, model: model).modifier(OnTable(style: style))
        case .cups(let c): CupsView(cups: c, model: model).modifier(OnTable(style: style))
        case .reflex(let r): ReflexView(reflex: r, model: model, style: style).modifier(OnTable(style: style))
        case .meter(let m): MeterView(meter: m).padding(10).gameCard(corner: 16, opacity: 0.94)
        case .number(let n): NumberFieldView(field: n, model: model)
        case .letters(let l): LettersView(letters: l, model: model, largest: (board.keys?.pages.map(\.rows.count).max() ?? 0) > 3 ? 24 : 37)
        case .keys(let k): KeyboardView(keys: k, model: model)
        case .entry(let e): GameEntryView(entry: e, model: model).id(e.name)
        case .sticks(let s): SticksView(sticks: s, model: model).modifier(OnTable(style: style))
        case .lives(let l): LivesView(lives: l)
        case .puzzle(let p): PuzzleView(puzzle: p, model: model)
        }
    }
}

/// A prop standing on the scene's table: the table runs the panel's full width behind it and up over the companion's
/// lower half, so the companion peeks over it.
struct OnTable: ViewModifier {
    var style: GameStyle

    func body(content: Content) -> some View {
        content
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(alignment: .top) {
                GameTableStrip(style: style)
                    .padding(.horizontal, -PlayView.pad)
                    .padding(.top, -6)
                    .padding(.bottom, -8)
            }
    }
}

// MARK: Prompt

struct GamePromptView: View {
    var prompt: GameBoard.Prompt
    var clock: (id: String, start: Date, seconds: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prompt.chip != nil || prompt.eyebrow != nil {
                HStack(spacing: 8) {
                    if let chip = prompt.chip {
                        Text(verbatim: chip).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.accentSoft))
                    }
                    if let eyebrow = prompt.eyebrow {
                        Text(verbatim: eyebrow).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text(verbatim: prompt.text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            if let clock { TimerBar(clock: clock, id: clock.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The time left, as a bar that empties; red in the last five seconds.
struct TimerBar: View {
    var clock: (id: String, start: Date, seconds: Double)?
    var id: String

    var body: some View {
        if let clock {
            TimelineView(.animation(minimumInterval: 1 / 20)) { t in
                let left = max(0, clock.seconds - t.date.timeIntervalSince(clock.start))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceSunken)
                        // Hurry, not danger: the last five seconds turn warm.
                        Capsule().fill(left <= 5 ? Color(hex: 0xFF8A3D) : Theme.accent).frame(width: geo.size.width * left / clock.seconds)
                    }
                }
                .frame(height: 5)
                .accessibilityLabel(String(localized: "\(Int(left.rounded(.up))) seconds left", comment: "A game's timer"))
            }
        }
    }
}

// MARK: Answers

struct AnswersView: View {
    var answers: GameBoard.Answers
    var model: PlayModel

    var body: some View {
        let caps = PlayModel.keyCaps(answers)
        let tiles = answers.tiles.enumerated().map { i, tile in
            AnswerTile(tile: tile, cap: caps[i], pending: model.pending == .answer(i), locked: answers.locked, portrait: model.portrait,
                       companionName: model.companionName) { model.send(.answer(i)) }
        }
        switch answers.layout {
        case .grid:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { $0.element }
            }
        case .row:
            HStack(spacing: 10) { ForEach(Array(tiles.enumerated()), id: \.offset) { $0.element } }
        case .column:
            VStack(spacing: 8) { ForEach(Array(tiles.enumerated()), id: \.offset) { $0.element } }
        }
    }
}

/// A big answer: its key cap, its words or picture, and once answered, ✓ or ✕ and whose pick it was.
struct AnswerTile: View {
    var tile: GameBoard.Answers.Tile
    var cap: String
    var pending: Bool
    var locked: Bool
    var portrait: NSImage?
    var companionName: String
    var action: () -> Void
    @State private var hovered = false
    @State private var shake: CGFloat = 0

    /// What the tile means for the person once answered (`GameVerdict`): drawn in that meaning's colour with its symbol.
    /// None while the pick waits for its verdict (the build-up, D75).
    private var verdict: GameVerdict? { pending ? nil : GameVerdict(tile: tile.state, locked: locked) }

    private var fill: Color {
        if let verdict { return GameColors.fill(verdict) }
        return GamePaint.card
    }

    private var ink: Color { verdict.map(GameColors.ink) ?? Theme.ink }

    /// The person's own pick, pressed and waiting, or unjudged: a neutral ink outline, never a verdict's colour.
    private var outlined: Bool { tile.state == .picked || pending }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(alignment: .top) {
                    Text(verbatim: cap)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(ink.opacity(0.35), lineWidth: 1)
                            .offset(y: hovered && !locked ? -1 : 0))
                    Spacer(minLength: 0)
                    mark
                }
                if let art = tile.art {
                    HandShape(hand: Hand(rawValue: art.rawValue) ?? .rock).frame(width: 52, height: 52)
                }
                Text(verbatim: tile.label)
                    .font(.system(size: tile.art == nil ? 15 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                if tile.art == nil { Spacer(minLength: 0) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: tile.art == nil ? 70 : 112)
            // A raised tile on a darker lip, as the other toys.
            .background {
                if verdict == nil { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GamePaint.lip).offset(y: 4) }
                else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill).brightness(-0.1).offset(y: 4) }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(outlined ? Theme.ink.opacity(0.7) : verdict == .loss ? GameColors.lost.opacity(0.6) : GamePaint.edge,
                                  lineWidth: outlined || verdict == .loss ? 2 : 1)
            }
            .scaleEffect(pending ? 0.96 : tile.state == .right ? 1.03 : hovered && !locked ? 1.02 : 1)
            .opacity(tile.state == .faded ? 0.35 : 1)
            .shadow(color: .black.opacity(hovered && !locked ? 0.12 : 0.04), radius: hovered && !locked ? 6 : 2, y: 2)
            .modifier(Shake(amount: shake))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        // Not `disabled`, which would grey out a right answer's colours.
        .allowsHitTesting(!locked && tile.state != .faded)
        .onHover { hovered = $0 }
        .onChange(of: tile.state) { _, state in
            guard state == .wrong, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
        .accessibilityLabel(Text(verbatim: accessibility))
    }

    @ViewBuilder private var mark: some View {
        HStack(spacing: 4) {
            if tile.companion {
                GameAvatar(portrait: portrait, size: 22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .transition(.scale.combined(with: .opacity))
            }
            if let verdict {
                Image(systemName: verdict.symbol).font(.system(size: 18, weight: .bold))
                    .foregroundStyle(verdict == .win ? .white : GameColors.color(verdict))
            }
        }
    }

    private var accessibility: String {
        var words = "\(cap), \(tile.label)"
        switch tile.state {
        case .right: words += ", " + String(localized: "right", comment: "A game's answer, read by VoiceOver")
        case .wrong: words += ", " + String(localized: "wrong", comment: "A game's answer, read by VoiceOver")
        case .picked: words += ", " + String(localized: "your pick", comment: "A game's answer, read by VoiceOver")
        default: break
        }
        if tile.companion { words += ", " + String(localized: "\(companionName)'s pick", comment: "A game's answer the companion chose, read by VoiceOver") }
        return words
    }
}

/// A wrong answer shakes its head.
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(amount * .pi * 6) * (1 - amount.truncatingRemainder(dividingBy: 1)), y: 0))
    }
}

// MARK: Buttons, notes, facts, results

struct GameButtonRow: View {
    var buttons: [GameBoard.Button]
    var model: PlayModel
    /// Flat, as on the end card, where the result is the one thing that stands up.
    var flat = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                Button { model.send(.button(b.move)) } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: b.label)
                        if let symbol = b.symbol { Image(systemName: symbol) }
                    }
                    .frame(maxWidth: b.style == .plain ? nil : .infinity)
                }
                .buttonStyle(ChunkyButtonStyle(kind: b.style, flat: flat))
                // A plain button's words are measured first; the wide buttons beside it take the room left.
                .layoutPriority(b.style == .plain ? 1 : 0)
                .disabled(b.disabled || model.pending != nil)
            }
        }
    }
}

/// A game's button as a toy: a raised face on a darker lip that sinks when pressed. The primary is the app's accent
/// (a game's colour is decoration, never what a button means), the secondary the games' card on its blue lip, the plain
/// one a soft pill. `flat` drops the lip (the end card's buttons sit under its result, not beside it as equals).
struct ChunkyButtonStyle: ButtonStyle {
    var kind: GameBoard.Button.Style
    var flat = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !GameMotion.reduced && !flat
        let fill: Color = kind == .primary ? Theme.accent : GamePaint.card
        let ink: Color = kind == .primary ? Theme.onAccent : Theme.ink
        let corner: CGFloat = kind == .plain ? 20 : flat ? 14 : 16
        let depth: CGFloat = flat ? 0 : kind == .plain ? 2 : 4
        configuration.label
            .font(.system(size: kind == .plain ? 13 : flat ? 15 : 16, weight: flat ? .bold : .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.65)
            .foregroundStyle(ink)
            .padding(.horizontal, kind == .plain ? 14 : 16)
            .frame(minHeight: kind == .plain ? 34 : flat ? 42 : 46)
            .background {
                ZStack {
                    if depth > 0 {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(kind == .primary ? fill : GamePaint.lip)
                            .brightness(kind == .primary ? -0.14 : 0)
                            .offset(y: depth)
                    }
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(kind == .primary && !flat ? 0.25 : 0.0), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(kind == .primary ? .clear : GamePaint.edge, lineWidth: 1))
                        .offset(y: pressed ? depth - 1 : 0)
                }
            }
            .offset(y: pressed ? depth - 1 : 0)
            .padding(.bottom, depth)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && flat && !GameMotion.reduced ? 0.97 : 1)
            .animation(.spring(duration: 0.15, bounce: 0.5), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct GameNoteView: View {
    var note: GameBoard.Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.tone == .info || note.tone == .neutral ? "lightbulb.fill" : note.tone == .good ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.sun)
            VStack(alignment: .leading, spacing: 2) {
                if let title = note.title { Text(verbatim: title).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink) }
                Text(verbatim: note.text).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GamePaint.card.opacity(0.96))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.sun.opacity(0.14))))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(GamePaint.edge, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct GameFactsView: View {
    var facts: [GameBoard.Fact]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                VStack(spacing: 2) {
                    Text(verbatim: f.value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: f.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GamePaint.inset))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The end card: the result as one unit (an award mark beside the score, who won in words, the game's line), a small
/// new-best chip, facts, what to do next with "Back to games" beside it, and the level for the next game. Calm and
/// flat (the founder's review of the reward card): the mark is the only picture, and it appears once.
struct GameResultView: View {
    var result: GameBoard.Result
    var model: PlayModel
    /// What the companion's bubble already says, not repeated under the score.
    var said: String?
    /// The level for the next game, at the card's foot.
    var choices: [GameBoard.Choice] = []
    @State private var shown = false

    @Environment(\.layoutDirection) private var layoutDirection
    private var verdict: GameVerdict { GameVerdict(tone: result.tone) }

    /// A crown for the person's win, a thumbs-up for a good game lost, an = for a draw: never colour alone.
    static func symbol(_ verdict: GameVerdict) -> String {
        switch verdict {
        case .win: "crown.fill"
        case .loss: "hand.thumbsup.fill"
        case .draw: "equal.circle.fill"
        }
    }

    /// The figure in a fixed order. "7 / 10" reads left to right in every language. "3 – 2" (the person's, then the
    /// companion's) follows the "You vs" bar's sides, which follow the layout: isolated left to right or right to left
    /// with it, so the text's own direction (Arabic's) never puts the companion's number on the person's side.
    static func figure(_ figure: String, _ direction: LayoutDirection) -> String {
        if figure.contains("/") { return "\u{2066}\(figure)\u{2069}" }
        guard figure.contains(" – ") else { return figure }
        return (direction == .rightToLeft ? "\u{2067}" : "\u{2066}") + figure + "\u{2069}"
    }

    /// Who won, in Sidefolk's words: said only for a win or a loss (a draw's card speaks for itself).
    private var title: String? {
        switch verdict {
        // A puzzle is played alone: solved, not won against anyone.
        case .win where model.info.look?.solo == true: String(localized: "Solved!", comment: "A puzzle's end card: the person solved it")
        case .win: String(localized: "You win!", comment: "A game's end card: the person won")
        case .loss: String(localized: "\(model.companionName) wins!", comment: "A game's end card: the companion (named) won")
        case .draw: nil
        }
    }

    /// The award mark: Sidefolk's trophy for the person's win (with the crown that goes with the colour), else the
    /// verdict's symbol, on a soft tile of its colour.
    private var mark: some View {
        let tint = verdict == .win ? Theme.sun : GameColors.color(verdict)
        return ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tint.opacity(0.18))
            if verdict == .win, GameArt.trophy.image != nil {
                GameArt.trophy.view(height: 42)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: Self.symbol(verdict)).font(.system(size: 10, weight: .bold)).foregroundStyle(GameColors.color(verdict))
                            .padding(3).background(Circle().fill(GamePaint.card)).offset(x: 6, y: -3)
                    }
            } else if result.tone == .info {
                // Two people (D96): a winner is named with a trophy in neutral ink, so no colour says whose loss it was.
                Image(systemName: "trophy.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
            } else {
                Image(systemName: Self.symbol(verdict)).font(.system(size: 24, weight: .bold)).foregroundStyle(GameColors.color(verdict))
            }
        }
        .frame(width: 58, height: 58)
        .scaleEffect(shown ? 1 : 0.6)
        .accessibilityHidden(true)
    }

    private var hero: some View {
        HStack(spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.figure(result.figure, layoutDirection))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(verdict == .draw ? Theme.ink : GameColors.color(verdict))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let title {
                    Text(verbatim: title).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                if let line = result.line, line != said {
                    Text(verbatim: line).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(shown ? 1 : 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GamePaint.inset))
    }

    /// Back to the menu, beside what to do next: a square with the menu's grid.
    @ViewBuilder private var backToGames: some View {
        if let back = model.onBack {
            let words = String(localized: "Back to games", comment: "A game's end card: back to the Play panel's menu")
            Button(action: back) { Image(systemName: "square.grid.2x2.fill").frame(width: 22) }
                .buttonStyle(ChunkyButtonStyle(kind: .secondary, flat: true))
                .help(words)
                .accessibilityLabel(words)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let ribbon = result.ribbon {
                // A new best: a small chip in the sun's colour, above the result it crowns.
                Label { Text(verbatim: ribbon) } icon: { Image(systemName: "star.fill").foregroundStyle(Theme.sun) }
                    .font(Theme.Font.captionStrong).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.sun.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Theme.sun.opacity(0.45), lineWidth: 1))
                    .opacity(shown ? 1 : 0)
            }
            hero
            if !result.facts.isEmpty { GameFactsView(facts: result.facts) }
            // What to do next in one row; when its words don't fit there (Higher or Lower's "Switch: Mochi guesses"
            // beside Play again), the first action takes its own row, never cut to "Pla…".
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if !result.actions.isEmpty { GameButtonRow(buttons: result.actions, model: model, flat: true) }
                    backToGames
                }
                VStack(spacing: 6) {
                    GameButtonRow(buttons: Array(result.actions.prefix(1)), model: model, flat: true)
                    HStack(spacing: 8) {
                        GameButtonRow(buttons: Array(result.actions.dropFirst()), model: model, flat: true)
                        backToGames
                    }
                }
            }
            ForEach(Array(choices.enumerated()), id: \.offset) { _, c in GameChoiceView(choice: c, model: model, compact: true) }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .gameCard(corner: 22, opacity: 0.98)
        .onAppear {
            withAnimation(GameMotion.reduced ? nil : .spring(duration: 0.4, bounce: 0.25)) { shown = true }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Choices

struct GameChoiceView: View {
    var choice: GameBoard.Choice
    var model: PlayModel
    /// Inside an end card: the label beside a slimmer row.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = choice.label, !compact {
                Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(GamePaint.card.opacity(0.94)))
            }
            switch choice.style {
            case .cards:
                // Three or fewer share the row (Higher or Lower's two ways to play), rather than sitting in the
                // left half of a grid laid out for four.
                let columns = choice.options.count < 4
                    ? Array(repeating: GridItem(.flexible(), spacing: 8), count: max(choice.options.count, 1))
                    : [GridItem(.adaptive(minimum: 72), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(choice.options.enumerated()), id: \.offset) { i, o in card(o, tint: i) }
                }
            case .segmented:
                HStack(spacing: 6) {
                    if compact, let label = choice.label {
                        Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(choice.options.enumerated()), id: \.offset) { _, o in segment(o) }
                    }
                    .padding(3)
                    .background(Capsule().fill(compact ? GamePaint.inset : GamePaint.card.opacity(0.96)))
                    .overlay(Capsule().strokeBorder(GamePaint.edge, lineWidth: compact ? 0 : 1))
                }
            }
        }
    }

    private func pick(_ o: GameBoard.Choice.Option) { model.send(.choice(name: choice.name, value: o.value)) }

    /// A choice card, each in its own soft pastel (a topic's, the beds' palette) so a grid of them reads at a glance.
    private func card(_ o: GameBoard.Choice.Option, tint: Int) -> some View {
        let selected = choice.selected == o.value
        return Button { pick(o) } label: {
            VStack(spacing: 4) {
                if let art = GameArt.topic(o.symbol), art.image != nil {
                    // Sidefolk's picture of the thing itself (a flask for science, a planet for space).
                    art.view(fitting: 32)
                } else if let symbol = o.symbol {
                    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(selected ? Theme.accent : Theme.accentSoft))
                }
                // A long name wraps (up to three lines, a little smaller) rather than being cut.
                Text(verbatim: o.label).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(3).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if let detail = o.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.accentSoft : GamePaint.card)
                .overlay { if !selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PuzzleColors.region(tint).opacity(0.4)) } }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 2))
            .overlay {
                // A choice is a selection, not a result: the app's accent, as everywhere else.
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.accent : GamePaint.edge, lineWidth: selected ? 2.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: o.label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func segment(_ o: GameBoard.Choice.Option) -> some View {
        let selected = choice.selected == o.value
        return Button { pick(o) } label: {
            Text(verbatim: o.label).font(Theme.Font.captionStrong).foregroundStyle(selected ? Theme.onAccent : Theme.ink).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Grid

/// A memory card face down: the app's accent with a pattern of paws, a white inner frame, raised on its lip.
struct CardBack: View {
    var side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            GameBevel(color: Theme.accent, corner: 9, depth: 3)
            shape.strokeBorder(.white.opacity(0.55), lineWidth: 1.5).padding(4).offset(y: 0)
            VStack(spacing: side * 0.06) {
                ForEach(0..<2, id: \.self) { r in
                    HStack(spacing: side * 0.1) {
                        ForEach(0..<2, id: \.self) { c in
                            Image(systemName: "pawprint.fill").font(.system(size: side * 0.14))
                                .rotationEffect(.degrees((r + c).isMultiple(of: 2) ? -18 : 14))
                        }
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.5))
            .offset(y: -1)
        }
        .padding(side * 0.07)
        .padding(.bottom, 3)
    }
}

/// Cells up to 8 × 8: an X, an O, a disc, a letter or a symbol; the winning line highlighted.
struct GameGridView: View {
    var grid: GameBoard.Grid
    var model: PlayModel

    /// Marks played on a board (Tic-tac-toe's X and O) sit in the cells of one card; cards that are their own pictures
    /// (Memory Pairs) lie straight on the scene.
    private var onBoard: Bool { !grid.cells.contains { $0.mark == .cardBack || $0.mark == .symbol } }

    var body: some View {
        let gap: CGFloat = 8, frame: CGFloat = onBoard ? 10 : 0
        let side = min(76, (PlayView.inner - 2 * frame - CGFloat(grid.columns - 1) * gap) / CGFloat(grid.columns))
        VStack(spacing: gap) {
            ForEach(0..<grid.rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<grid.columns, id: \.self) { c in cell(grid.cells[r * grid.columns + c], r, c, side) }
                }
            }
        }
        .padding(frame)
        .background { if onBoard { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.clear).gameCard(corner: 20) } }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ cell: GameBoard.Grid.Cell, _ r: Int, _ c: Int, _ side: CGFloat) -> some View {
        let index = r * grid.columns + c
        let open = !grid.locked && cell.state != .disabled && (cell.mark == .empty || cell.mark == .cardBack)
        return Button { model.send(.cell(row: r, column: c)) } label: {
            ZStack(alignment: .topLeading) {
                // A white tile raised on its lip; a card face down is its own picture, so it gets no tile.
                if cell.mark != .cardBack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GamePaint.lip).offset(y: 3)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        // A winning line is the person's win or loss by whose marks it holds.
                        .fill(cell.state == .win ? GameColors.fill(cell.companion ? .loss : .win).opacity(cell.companion ? 1 : 0.35)
                              : cell.state == .hint ? Theme.sun.opacity(0.35) : GamePaint.inset)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GamePaint.inset))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(GamePaint.edge, lineWidth: 1))
                }
                mark(cell, side).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(CellArrival(animate: cell.animate, key: "\(index)\(cell.mark.rawValue)\(cell.value ?? "")"))
                if grid.numpad, open {
                    // The digit that plays here, as on a number pad (7 8 9 on top).
                    GameKeyCap(text: "\((2 - r) * 3 + c + 1)").padding(5)
                }
                if model.parts.cursor == index, !grid.locked {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2.5)
                }
            }
            .frame(width: side, height: side)
            .opacity(cell.state == .disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        // Not `disabled`, which would fade every mark while it is the companion's turn.
        .allowsHitTesting(open)
        .accessibilityAddTraits(open ? [] : .isStaticText)
        .accessibilityLabel(Text(verbatim: cell.label ?? "\(r + 1), \(c + 1)"))
    }

    @ViewBuilder private func mark(_ cell: GameBoard.Grid.Cell, _ side: CGFloat) -> some View {
        let color = cell.companion ? Theme.accent : Theme.ink
        switch cell.mark {
        // Chunky marks lit from above, with a small drop shadow: pieces on a board rather than strokes.
        case .x: Image(systemName: "xmark").font(.system(size: side * 0.45, weight: .black))
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
            .shadow(color: color.opacity(0.35), radius: 0, y: 3)
        case .o: Circle().strokeBorder(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .top, endPoint: .bottom), lineWidth: side * 0.11)
            .padding(side * 0.22).shadow(color: color.opacity(0.35), radius: 0, y: 3)
        case .disc: Circle().fill(cell.value.flatMap(Self.hex) ?? color).padding(side * 0.14)
        case .letter: Text(verbatim: cell.value ?? "").font(.system(size: side * 0.45, weight: .bold, design: .rounded)).foregroundStyle(color)
        case .symbol:
            if let face = GameArt.face(cell.value), face.image != nil {
                // The thing itself, in its own colours; a pair the companion found wears its face.
                face.view(fitting: side * 0.66)
                    .overlay(alignment: .bottomTrailing) {
                        if cell.companion {
                            GameAvatar(portrait: model.portrait, size: side * 0.26).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .offset(x: side * 0.14, y: side * 0.12)
                        }
                    }
            } else {
                Image(systemName: cell.value ?? "questionmark").font(.system(size: side * 0.4, weight: .semibold)).foregroundStyle(color)
            }
        case .cardBack:
            if GameArt.cardBack.image != nil {
                GameArt.cardBack.view(height: side * 0.98).shadow(color: .black.opacity(0.18), radius: 2, y: 2)
            } else {
                CardBack(side: side)
            }
        case .stick: CandyStick(color: Theme.coral).frame(width: side * 0.16).padding(.vertical, side * 0.12)
        case .cup:
            if GameArt.cup.image != nil { GameArt.cup.view(height: side * 0.62) }
            else { Image(systemName: "cup.and.saucer.fill").font(.system(size: side * 0.42)).foregroundStyle(color) }
        case .empty: EmptyView()
        }
    }

    static func hex(_ s: String) -> Color? {
        guard s.count == 7, s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return Color(hex: v)
    }
}

/// How a mark arrives: stamped (an X or O squashing in), flipped (a card turning over), dropped or popped in.
struct CellArrival: ViewModifier {
    var animate: GameBoard.Grid.Animate?
    /// What the cell shows, so the animation plays when it changes and not on every board.
    var key: String
    @State private var done = true
    @Environment(\.revealProgress) private var fixed

    func body(content: Content) -> some View {
        content
            .scaleEffect(done ? 1 : animate == .stamp ? 1.5 : animate == .pop ? 0.4 : 1)
            // A card turned drawn flat: a 3D rotation inside the panel drew it at the panel's corner.
            .scaleEffect(x: done || animate != .flip ? 1 : 0.02, y: 1)
            .offset(y: done || animate != .drop ? 0 : -30)
            .opacity(done ? 1 : 0.2)
            .onChange(of: key, initial: true) { _, _ in
                guard animate != nil, fixed == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                done = false
                withAnimation(.spring(duration: 0.32, bounce: 0.4)) { done = true }
            }
    }
}
