import SidefolkCore
import SwiftUI

/// The board's parts, top to bottom, each drawn by Sidefolk. Buttons that follow one another share a row.
struct BoardView: View {
    var model: PlayModel
    var board: GameBoard

    /// The parts with neighbouring buttons gathered into one row.
    private enum Item: Identifiable {
        case part(Int, GameBoard.Part)
        case buttons(Int, [GameBoard.Button])
        var id: Int { switch self { case .part(let i, _), .buttons(let i, _): i } }
    }

    private var items: [Item] {
        var out: [Item] = []
        for (i, part) in board.parts.enumerated() {
            if case .button(let b) = part {
                if case .buttons(let at, let row)? = out.last { out[out.count - 1] = .buttons(at, row + [b]) } else { out.append(.buttons(i, [b])) }
            } else if case .score = part {
                continue // in the header
            } else {
                out.append(.part(i, part))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                switch item {
                case .buttons(_, let row): GameButtonRow(buttons: row, model: model)
                case .part(_, let part): view(part)
                }
            }
        }
        .animation(Theme.Motion.spring(0.35), value: model.turn)
    }

    @ViewBuilder private func view(_ part: GameBoard.Part) -> some View {
        switch part {
        case .prompt(let p): GamePromptView(prompt: p, clock: model.clock)
        case .answers(let a): AnswersView(answers: a, model: model)
        case .board(let g): GameGridView(grid: g, model: model)
        case .result(let r): GameResultView(result: r, model: model)
        case .reveal(let r): RevealView(reveal: r, companionName: model.companionName, start: model.revealStart).frame(maxWidth: .infinity)
        case .note(let n): GameNoteView(note: n)
        case .facts(let f): GameFactsView(facts: f)
        case .choice(let c): GameChoiceView(choice: c, model: model)
        case .timer(let t): if model.board?.parts.contains(where: { if case .prompt = $0 { true } else { false } }) == false {
            TimerBar(clock: model.clock, id: t.id)
        }
        case .score, .button: EmptyView()
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
        return hovered && !locked ? Theme.surfaceRaised : Theme.surfaceSunken
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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(outlined ? Theme.ink.opacity(0.7) : verdict == .loss ? GameColors.lost.opacity(0.6) : Theme.line,
                                  lineWidth: outlined || verdict == .loss ? 2 : 1)
            }
            .scaleEffect(pending ? 0.96 : tile.state == .right ? 1.03 : hovered && !locked ? 1.02 : 1)
            .opacity(tile.state == .faded ? 0.35 : 1)
            .shadow(color: .black.opacity(hovered && !locked ? 0.12 : 0.04), radius: hovered && !locked ? 6 : 2, y: 2)
            .modifier(Shake(amount: shake))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                let style: SFButtonStyle = switch b.style {
                case .primary: .sf(.primary, compact: false, large: true)
                case .secondary: .sf(.secondary, compact: false, large: true)
                case .plain: .sf(.plain)
                }
                Button { model.send(.button(b.move)) } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: b.label)
                        if let symbol = b.symbol { Image(systemName: symbol) }
                    }
                    .frame(maxWidth: b.style == .plain ? nil : .infinity)
                }
                .buttonStyle(style)
                .disabled(b.disabled || model.pending != nil)
            }
        }
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.sun.opacity(0.14)))
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
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surfaceSunken))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The end card: the big figure, a line, a ribbon, facts, and what to do next.
struct GameResultView: View {
    var result: GameBoard.Result
    var model: PlayModel
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

    var body: some View {
        VStack(spacing: 10) {
            if let ribbon = result.ribbon {
                Label { Text(verbatim: ribbon) } icon: { Image(systemName: "star.fill") }
                    .font(Theme.Font.captionStrong).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.sun))
                    .rotationEffect(.degrees(-3))
            }
            Image(systemName: Self.symbol(verdict)).font(.system(size: 26, weight: .bold)).foregroundStyle(GameColors.color(verdict))
                .opacity(shown ? 1 : 0)
            Text(verbatim: result.figure)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(verdict == .draw ? Theme.ink : GameColors.color(verdict))
                // "7 / 10" is a score read left to right in every language; in Arabic it would otherwise turn round.
                .environment(\.layoutDirection, result.figure.contains("/") ? .leftToRight : layoutDirection)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            if let line = result.line {
                Text(verbatim: line).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            }
            if !result.facts.isEmpty { GameFactsView(facts: result.facts) }
            if !result.actions.isEmpty { GameButtonRow(buttons: result.actions, model: model) }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceSunken.opacity(0.6)))
        .onAppear {
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.5, bounce: 0.45)) { shown = true }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Choices

struct GameChoiceView: View {
    var choice: GameBoard.Choice
    var model: PlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = choice.label { Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted) }
            switch choice.style {
            case .cards:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(choice.options.enumerated()), id: \.offset) { _, o in card(o) }
                }
            case .segmented:
                HStack(spacing: 4) {
                    ForEach(Array(choice.options.enumerated()), id: \.offset) { _, o in segment(o) }
                }
                .padding(3)
                .background(Capsule().fill(Theme.surfaceSunken))
            }
        }
    }

    private func pick(_ o: GameBoard.Choice.Option) { model.send(.choice(name: choice.name, value: o.value)) }

    private func card(_ o: GameBoard.Choice.Option) -> some View {
        let selected = choice.selected == o.value
        return Button { pick(o) } label: {
            VStack(spacing: 5) {
                if let symbol = o.symbol {
                    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(selected ? Theme.accent : Theme.accentSoft))
                }
                Text(verbatim: o.label).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.center)
                if let detail = o.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.accentSoft : Theme.surfaceSunken))
            .overlay {
                // A choice is a selection, not a result: the app's accent, as everywhere else.
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1)
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

/// Cells up to 8 × 8: an X, an O, a disc, a letter or a symbol; the winning line highlighted.
struct GameGridView: View {
    var grid: GameBoard.Grid
    var model: PlayModel

    var body: some View {
        let side = min(76, (PlayView.width - 32 - CGFloat(grid.columns - 1) * 8) / CGFloat(grid.columns))
        VStack(spacing: 8) {
            ForEach(0..<grid.rows, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<grid.columns, id: \.self) { c in cell(grid.cells[r * grid.columns + c], r, c, side) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ cell: GameBoard.Grid.Cell, _ r: Int, _ c: Int, _ side: CGFloat) -> some View {
        Button { model.send(.cell(row: r, column: c)) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // A winning line is the person's win or loss by whose marks it holds.
                    .fill(cell.state == .win ? GameColors.fill(cell.companion ? .loss : .win).opacity(cell.companion ? 1 : 0.35)
                          : cell.state == .hint ? Theme.sun.opacity(0.25) : Theme.surfaceSunken)
                mark(cell, side)
            }
            .frame(width: side, height: side)
            .opacity(cell.state == .disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(grid.locked || cell.state == .disabled || cell.mark != .empty && cell.mark != .cardBack)
        .accessibilityLabel(Text(verbatim: cell.label ?? "\(r + 1), \(c + 1)"))
    }

    @ViewBuilder private func mark(_ cell: GameBoard.Grid.Cell, _ side: CGFloat) -> some View {
        let color = cell.companion ? Theme.accent : Theme.ink
        switch cell.mark {
        case .x: Image(systemName: "xmark").font(.system(size: side * 0.45, weight: .heavy)).foregroundStyle(color)
        case .o: Circle().strokeBorder(color, lineWidth: side * 0.09).padding(side * 0.22)
        case .disc: Circle().fill(cell.value.flatMap(Self.hex) ?? color).padding(side * 0.14)
        case .letter: Text(verbatim: cell.value ?? "").font(.system(size: side * 0.45, weight: .bold, design: .rounded)).foregroundStyle(color)
        case .symbol: Image(systemName: cell.value ?? "questionmark").font(.system(size: side * 0.4, weight: .semibold)).foregroundStyle(color)
        case .cardBack: RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.8)).padding(side * 0.1)
        case .stick: Capsule().fill(Theme.coral).frame(width: side * 0.16).padding(.vertical, side * 0.12)
        case .cup: Image(systemName: "cup.and.saucer.fill").font(.system(size: side * 0.42)).foregroundStyle(color)
        case .empty: EmptyView()
        }
    }

    static func hex(_ s: String) -> Color? {
        guard s.count == 7, s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return Color(hex: v)
    }
}
