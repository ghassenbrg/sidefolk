import SidefolkCore
import SwiftUI

/// A logic puzzle's grid (D79, the puzzles): one calm card of cells with the game's marks (Sidefolk's own heart, star
/// and blossom pictures, numbers, pencil notes, dots), coloured beds with heavier lines between them, Sudoku's boxes,
/// `=` and `×` between cells, plots dragged corner to corner, and where a rule breaks (the calm loss tone with a !,
/// never red) or what a hint points at. The clock counts on above it; Sudoku's digit pad sits under it. A puzzle is
/// the same picture in every language, so it is laid out left to right even in Arabic.
struct PuzzleView: View {
    var puzzle: GameBoard.Puzzle
    var model: PlayModel

    /// Room for the grid, so a 9 × 9 Sudoku with its pad keeps the panel under 720 pt.
    static func side(_ p: GameBoard.Puzzle) -> CGFloat {
        let tall: CGFloat = p.input == .digits ? 300 : 324
        return floor(min(54, (PlayView.inner - 12) / CGFloat(p.columns), tall / CGFloat(p.rows)))
    }

    var body: some View {
        let side = Self.side(puzzle)
        VStack(spacing: 8) {
            PuzzleGrid(puzzle: puzzle, model: model, side: side)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3))
                .environment(\.layoutDirection, .leftToRight)
            if puzzle.input == .digits, let digits = puzzle.digits {
                DigitPad(digits: digits, model: model, puzzle: puzzle)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The cells, and what is drawn over them: lines, clues between cells, plots and the drag in progress.
struct PuzzleGrid: View {
    var puzzle: GameBoard.Puzzle
    var model: PlayModel
    var side: CGFloat

    private var size: CGSize { CGSize(width: side * CGFloat(puzzle.columns), height: side * CGFloat(puzzle.rows)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<puzzle.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<puzzle.columns, id: \.self) { c in cell(r, c) }
                    }
                }
            }
            PuzzleLines(puzzle: puzzle, side: side).allowsHitTesting(false)
            ForEach(Array(puzzle.plots.enumerated()), id: \.offset) { _, plot in PlotShape(plot: plot, side: side).allowsHitTesting(false) }
            if let drag = model.parts.drag {
                let (a, b) = (drag.from, drag.to)
                let plot = GameBoard.Puzzle.Plot(row: min(a / puzzle.columns, b / puzzle.columns), column: min(a % puzzle.columns, b % puzzle.columns),
                                                 height: abs(a / puzzle.columns - b / puzzle.columns) + 1,
                                                 width: abs(a % puzzle.columns - b % puzzle.columns) + 1, state: .none, tint: nil)
                PlotShape(plot: plot, side: side, dragging: true).allowsHitTesting(false)
            }
            ForEach(Array(puzzle.edges.enumerated()), id: \.offset) { _, edge in EdgeClue(edge: edge, columns: puzzle.columns, side: side) }
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(puzzle.input == .drag && !puzzle.locked ? dragging : nil)
    }

    private func index(at point: CGPoint) -> Int {
        let r = min(max(Int(point.y / side), 0), puzzle.rows - 1), c = min(max(Int(point.x / side), 0), puzzle.columns - 1)
        return r * puzzle.columns + c
    }

    /// Corner to corner; a click without moving takes a plot away (or draws one cell). The keyboard draws the same
    /// way (`PlayModel.dragPlot`), into the same preview.
    private var dragging: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                model.parts.dragByKeys = false
                model.parts.drag = (index(at: v.startLocation), index(at: v.location))
            }
            .onEnded { v in
                let (a, b) = (index(at: v.startLocation), index(at: v.location))
                model.parts.drag = nil
                let w = puzzle.columns
                if a == b { model.send(.cell(row: a / w, column: a % w)) } else { model.send(.area(row: a / w, column: a % w, toRow: b / w, toColumn: b % w)) }
            }
    }

    @ViewBuilder private func cell(_ r: Int, _ c: Int) -> some View {
        let i = r * puzzle.columns + c
        let content = PuzzleCellView(cell: puzzle.cells[i], side: side, digits: puzzle.digits ?? 9, model: model,
                                     selected: model.parts.cursor == i && !puzzle.locked)
        switch puzzle.input {
        case .drag:
            content
        case .tap, .digits:
            Button {
                if puzzle.input == .digits { model.parts.cursor = i } else { model.send(.cell(row: r, column: c)) }
            } label: { content }
            .buttonStyle(.plain)
            .allowsHitTesting(!puzzle.locked && !puzzle.cells[i].given)
        }
    }
}

/// One cell: its bed's colour, its mark, notes, and its state.
struct PuzzleCellView: View {
    var cell: GameBoard.Puzzle.Cell
    var side: CGFloat
    var digits: Int
    var model: PlayModel
    var selected: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            if cell.state == .hint || cell.state == .target { Rectangle().fill(Theme.sun.opacity(0.3)) }
            if selected { Rectangle().fill(Theme.accent.opacity(0.14)) }
            mark.opacity(cell.state == .target ? 0.45 : 1)
                .modifier(Settle(fresh: cell.fresh, key: "\(cell.symbol?.rawValue ?? "")\(cell.text ?? "")"))
            if cell.text == nil, cell.symbol == nil, !cell.notes.isEmpty { notes }
            if cell.state == .target || selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2.5).padding(2)
            }
            if cell.state == .conflict { ConflictBadge(size: max(11, side * 0.3)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(2) }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: cell.label ?? ""))
    }

    private var background: Color {
        if cell.state == .conflict { return GameColors.lostSoft }
        if let region = cell.region { return PuzzleColors.region(region) }
        return Theme.surface
    }

    @ViewBuilder private var mark: some View {
        if let symbol = cell.symbol {
            switch symbol {
            case .heart: picture(.faceHeart, fallback: "heart.fill", color: Theme.coral)
            case .star: picture(.faceStar, fallback: "star.fill", color: Theme.sun)
            case .blossom: picture(.faceFlower, fallback: "camera.macro", color: Theme.coral)
            case .dot: Circle().fill(Theme.inkMuted.opacity(0.55)).frame(width: side * 0.16, height: side * 0.16)
            }
        } else if let text = cell.text {
            // A given is printed; a number the person put is in the accent's ink.
            Text(verbatim: text).font(.system(size: side * 0.52, weight: cell.given ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(cell.given ? Theme.ink : Theme.accent)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder private func picture(_ art: GameArt, fallback: String, color: Color) -> some View {
        if art.image != nil { art.view(fitting: side * 0.7) } else {
            Image(systemName: fallback).font(.system(size: side * 0.45, weight: .bold)).foregroundStyle(color)
        }
    }

    /// Pencil notes, each number in its own place, three to a row.
    private var notes: some View {
        let across = 3, down = (digits + across - 1) / across
        return VStack(spacing: 0) {
            ForEach(0..<down, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<across, id: \.self) { c in
                        let n = r * across + c + 1
                        Text(verbatim: cell.notes.contains(n) ? "\(n)" : " ")
                            .font(.system(size: max(7, side * 0.22), weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(side * 0.06)
    }
}

/// The calm loss tone with a "!": a rule broken here, never the danger red (D78).
struct ConflictBadge: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "exclamationmark").font(.system(size: size * 0.6, weight: .heavy)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(GameColors.lost))
            .accessibilityHidden(true)
    }
}

/// How a mark arrives: a small settle, once, as it is played (not on every board).
struct Settle: ViewModifier {
    var fresh: Bool
    var key: String
    @State private var done = true
    @Environment(\.revealProgress) private var fixed

    func body(content: Content) -> some View {
        content
            .scaleEffect(done ? 1 : 0.6)
            .opacity(done ? 1 : 0.3)
            .onChange(of: key, initial: true) { _, _ in
                guard fresh, fixed == nil, !GameMotion.reduced else { return }
                done = false
                withAnimation(.spring(duration: 0.3, bounce: 0.35)) { done = true }
            }
    }
}

/// The grid's lines: thin between cells, heavier between beds and around Sudoku's boxes, a frame around it all.
struct PuzzleLines: View {
    var puzzle: GameBoard.Puzzle
    var side: CGFloat

    var body: some View {
        Canvas { context, size in
            let thin = Theme.line, heavy = Theme.ink.opacity(0.55)
            func region(_ r: Int, _ c: Int) -> Int? { puzzle.cell(row: r, column: c)?.region }
            for r in 0..<puzzle.rows {
                for c in 0..<puzzle.columns {
                    let x = CGFloat(c) * side, y = CGFloat(r) * side
                    // The right and bottom edges of each cell: heavy where two beds or two boxes meet.
                    if c < puzzle.columns - 1 {
                        let boxed = puzzle.box.map { (c + 1) % $0.columns == 0 } ?? false
                        let bed = region(r, c) != nil && region(r, c) != region(r, c + 1)
                        var p = Path()
                        p.move(to: CGPoint(x: x + side, y: y))
                        p.addLine(to: CGPoint(x: x + side, y: y + side))
                        context.stroke(p, with: .color(boxed || bed ? heavy : thin), lineWidth: boxed || bed ? 2.2 : 1)
                    }
                    if r < puzzle.rows - 1 {
                        let boxed = puzzle.box.map { (r + 1) % $0.rows == 0 } ?? false
                        let bed = region(r, c) != nil && region(r, c) != region(r + 1, c)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y + side))
                        p.addLine(to: CGPoint(x: x + side, y: y + side))
                        context.stroke(p, with: .color(boxed || bed ? heavy : thin), lineWidth: boxed || bed ? 2.2 : 1)
                    }
                }
            }
            context.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 9), with: .color(heavy), lineWidth: 2)
        }
    }
}

/// A plot: a soft tinted rectangle with a rounded border, dashed while being dragged; a broken one in the calm loss
/// tone with a !, a hint's in the sun's colour.
struct PlotShape: View {
    var plot: GameBoard.Puzzle.Plot
    var side: CGFloat
    var dragging = false

    var body: some View {
        let rect = CGRect(x: CGFloat(plot.column) * side, y: CGFloat(plot.row) * side, width: CGFloat(plot.width) * side, height: CGFloat(plot.height) * side)
            .insetBy(dx: 3, dy: 3)
        let color: Color = plot.state == .conflict ? GameColors.lost : plot.state == .hint ? Theme.sun : dragging ? Theme.accent
            : PuzzleColors.plot(plot.tint ?? 0)
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(dragging ? 0.12 : 0.24))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2.5, dash: dragging || plot.state == .hint ? [6, 4] : []))
            if plot.state == .conflict { ConflictBadge(size: max(11, side * 0.3)).padding(3) }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// `=` or `×` on the line between two cells, in a small white disc.
struct EdgeClue: View {
    var edge: GameBoard.Puzzle.Edge
    var columns: Int
    var side: CGFloat

    var body: some View {
        let r = CGFloat(edge.cell / columns), c = CGFloat(edge.cell % columns)
        let center = edge.down ? CGPoint(x: (c + 0.5) * side, y: (r + 1) * side) : CGPoint(x: (c + 1) * side, y: (r + 0.5) * side)
        let d = max(17, side * 0.42)
        Text(verbatim: edge.clue == .same ? "=" : "×")
            .font(.system(size: d * 0.78, weight: .black, design: .rounded)).foregroundStyle(Theme.ink)
            .frame(width: d, height: d)
            .background(Circle().fill(Theme.surface).overlay(Circle().strokeBorder(Theme.ink.opacity(0.45), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1))
            .offset(x: center.x - d / 2, y: center.y - d / 2)
            .accessibilityHidden(true)
    }
}

/// The time so far, counting on once a second while the puzzle is being played.
struct PuzzleClock: View {
    var seconds: Double
    var running: Bool
    var since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { t in
            let total = Int(seconds + (running ? max(0, t.date.timeIntervalSince(since)) : 0))
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 11, weight: .bold))
                Text(verbatim: Self.format(total)).font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface.opacity(0.94)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
            .accessibilityElement(children: .combine)
        }
    }

    static func format(_ total: Int) -> String {
        total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Pencil or pen, for Sudoku: N switches.
struct NotesSwitch: View {
    var model: PlayModel

    var body: some View {
        Button { model.parts.notes.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: model.parts.notes ? "pencil" : "pencil.slash").font(.system(size: 11, weight: .bold))
                Text(model.parts.notes ? String(localized: "Notes on", comment: "Sudoku: numbers go in as pencil notes")
                     : String(localized: "Notes off", comment: "Sudoku: numbers go in as answers, not notes"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(model.parts.notes ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(model.parts.notes ? Theme.accent : Theme.surface.opacity(0.94)))
        }
        .buttonStyle(GamePressStyle())
        .focusable(false)
    }
}

/// The numbers under a Sudoku, and a key to clear the cell.
struct DigitPad: View {
    var digits: Int
    var model: PlayModel
    var puzzle: GameBoard.Puzzle

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...digits, id: \.self) { d in key(Text(verbatim: "\(d)"), value: d) }
            key(Text(Image(systemName: "delete.backward")), value: 0)
                .accessibilityLabel(String(localized: "Clear the cell", comment: "Sudoku's digit pad: empties the cell picked"))
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func key(_ label: Text, value: Int) -> some View {
        Button { model.placeDigit(value) } label: {
            label.font(.system(size: 17, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity)
        }
        .buttonStyle(DigitKeyStyle())
        .disabled(puzzle.locked || model.parts.cursor == nil)
        .focusable(false)
    }
}

/// A digit key: a small toy key on its lip, narrow enough for ten in a row.
struct DigitKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !GameMotion.reduced
        configuration.label
            .foregroundStyle(Theme.ink)
            .frame(height: 34)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.line).offset(y: 3)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .offset(y: pressed ? 2 : 0)
                }
            }
            .offset(y: pressed ? 2 : 0)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// The beds' and plots' colours: soft pastels that hold ink in light and dark.
enum PuzzleColors {
    static let light: [UInt32] = [0xFFD8D2, 0xFFE7B8, 0xFFF3B0, 0xDDF2C4, 0xC7EDDC, 0xC9E9F5, 0xD4DEFF, 0xE6D6FA, 0xF8D4EA, 0xEBDCC9, 0xD9E4D0, 0xE0E0E8]
    static let dark: [UInt32] = [0x5A3934, 0x5A4628, 0x55502A, 0x3D5030, 0x2E5244, 0x2C4A57, 0x37406A, 0x4A3A64, 0x5A3550, 0x4D4134, 0x3E4A38, 0x44444F]
    /// Never a red or the loss tone, which would read as a mistake.
    static let plots: [UInt32] = [0x2FA36B, 0x3E7BFA, 0x8B5CF6, 0xE8691C, 0x0E9384, 0x5AC8D8, 0x7342E0, 0x4F9128, 0x1D8AD8, 0xF2B21B, 0x6B7BFF, 0x9C45AC]

    static func region(_ i: Int) -> Color { Color(light: light[i % light.count], dark: dark[i % dark.count]) }
    static func plot(_ i: Int) -> Color { Color(hex: plots[i % plots.count]) }
}
