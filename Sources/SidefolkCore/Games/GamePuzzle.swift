import Foundation

// The logic puzzles' grid (D79, the puzzles): Seesaw's hearts and stars with = and × between cells, Blossoms' coloured
// beds, Garden Plots' rectangles dragged over numbers, Sudoku's boxes, numbers and pencil notes. As with every part, the
// game says what is true (marks, where a rule breaks, what a hint points at) and Sidefolk draws it, takes the clicks,
// drags and digits, and counts the clock on; every value is checked and capped here.

extension GameBoard {
    public struct Puzzle: Sendable, Hashable {
        /// What the person does on it: tap a cell (`{cell}`), drag a rectangle (`{area}`, a click alone is `{cell}`), or
        /// put a number in a cell they pick (`{place}`).
        public enum Input: String, Sendable, Hashable { case tap, drag, digits }
        /// Sidefolk's own pieces: a heart and a star (Seesaw), a blossom and a dot ruling a cell out (Blossoms).
        public enum Symbol: String, Sendable, Hashable, CaseIterable { case heart, star, blossom, dot }
        /// A rule broken there (the calm loss tone with a symbol, never red), what a hint rests on, where it says to play.
        public enum State: String, Sendable, Hashable { case none, conflict, hint, target }
        public enum Clue: String, Sendable, Hashable { case same, different }

        public struct Cell: Sendable, Hashable {
            public var symbol: Symbol?
            /// A number, up to two characters.
            public var text: String?
            /// Part of the puzzle as dealt: drawn fixed, never played.
            public var given: Bool
            /// Pencil notes, 1–9.
            public var notes: [Int]
            /// Its region (Blossoms' bed), 0–11, drawn in that region's colour.
            public var region: Int?
            public var state: State
            /// The mark just played: it settles in.
            public var fresh: Bool
            public var label: String?

            public init(symbol: Symbol? = nil, text: String? = nil, given: Bool = false, notes: [Int] = [], region: Int? = nil,
                        state: State = .none, fresh: Bool = false, label: String? = nil) {
                self.symbol = symbol
                self.text = text
                self.given = given
                self.notes = notes
                self.region = region
                self.state = state
                self.fresh = fresh
                self.label = label
            }
        }

        /// A clue between `cell` and the cell right of it, or below it when `down`.
        public struct Edge: Sendable, Hashable {
            public var cell: Int
            public var down: Bool
            public var clue: Clue
        }

        public struct Plot: Sendable, Hashable {
            public var row: Int
            public var column: Int
            public var height: Int
            public var width: Int
            public var state: State
            /// Its colour among the plots' twelve.
            public var tint: Int?

            public init(row: Int, column: Int, height: Int, width: Int, state: State = .none, tint: Int? = nil) {
                self.row = row
                self.column = column
                self.height = height
                self.width = width
                self.state = state
                self.tint = tint
            }

            public func contains(row r: Int, column c: Int) -> Bool { r >= row && r < row + height && c >= column && c < column + width }
        }

        public var rows: Int
        public var columns: Int
        public var cells: [Cell]
        public var input: Input
        /// The numbers the digit pad offers, 1 to this.
        public var digits: Int?
        /// Sudoku's boxes, rows × columns, drawn with thicker lines.
        public var box: (rows: Int, columns: Int)?
        public var edges: [Edge]
        public var plots: [Plot]
        /// The time spent so far, counting on in the panel while `running`.
        public var seconds: Double?
        public var running: Bool
        public var locked: Bool

        public static let sides = 2...10
        public static let maxEdges = 200
        public static let maxPlots = 100
        public static let regions = 12

        public static func == (a: Puzzle, b: Puzzle) -> Bool {
            a.rows == b.rows && a.columns == b.columns && a.cells == b.cells && a.input == b.input && a.digits == b.digits
                && a.box?.rows == b.box?.rows && a.box?.columns == b.box?.columns && a.edges == b.edges && a.plots == b.plots
                && a.seconds == b.seconds && a.running == b.running && a.locked == b.locked
        }

        public func hash(into h: inout Hasher) {
            h.combine(rows)
            h.combine(columns)
            h.combine(cells)
            h.combine(plots)
            h.combine(locked)
        }

        public func cell(row: Int, column: Int) -> Cell? {
            (0..<rows).contains(row) && (0..<columns).contains(column) ? cells[row * columns + column] : nil
        }
    }

    public var puzzle: Puzzle? { parts.lazy.compactMap { if case .puzzle(let p) = $0 { p } else { nil } }.first }

    static func puzzle(_ j: JSONValue) -> Puzzle? {
        guard let rows = j["rows"]?.intValue, let columns = j["columns"]?.intValue, Puzzle.sides.contains(rows), Puzzle.sides.contains(columns),
              let raw = j["cells"]?.arrayValue, raw.count == rows * columns else { return nil }
        let count = rows * columns
        let cells = raw.map { c in
            Puzzle.Cell(symbol: c["symbol"]?.stringValue.flatMap(Puzzle.Symbol.init),
                        text: c["text"]?.stringValue.flatMap { $0.count <= 2 && $0.allSatisfy(\.isNumber) && !$0.isEmpty ? $0 : nil },
                        given: c["given"]?.boolValue ?? false,
                        notes: Array(Set((c["notes"]?.arrayValue ?? []).prefix(9).compactMap(\.intValue).filter { (1...9).contains($0) })).sorted(),
                        region: c["region"]?.intValue.flatMap { (0..<Puzzle.regions).contains($0) ? $0 : nil },
                        state: c["state"]?.stringValue.flatMap(Puzzle.State.init) ?? .none,
                        fresh: c["fresh"]?.boolValue ?? false, label: line(c["label"], 60))
        }
        let edges = (j["edges"]?.arrayValue ?? []).prefix(Puzzle.maxEdges).compactMap { e -> Puzzle.Edge? in
            guard let cell = e["cell"]?.intValue, (0..<count).contains(cell), let clue = e["clue"]?.stringValue.flatMap(Puzzle.Clue.init) else { return nil }
            let down = e["down"]?.boolValue ?? false
            // The other cell must be on the grid, right of it in the same row or below it.
            guard down ? cell / columns < rows - 1 : cell % columns < columns - 1 else { return nil }
            return Puzzle.Edge(cell: cell, down: down, clue: clue)
        }
        let plots = (j["plots"]?.arrayValue ?? []).prefix(Puzzle.maxPlots).compactMap { p -> Puzzle.Plot? in
            guard let r = p["row"]?.intValue, let c = p["column"]?.intValue, let h = p["height"]?.intValue, let w = p["width"]?.intValue,
                  r >= 0, c >= 0, h >= 1, w >= 1, r + h <= rows, c + w <= columns else { return nil }
            return Puzzle.Plot(row: r, column: c, height: h, width: w, state: p["state"]?.stringValue.flatMap(Puzzle.State.init) ?? .none,
                               tint: p["tint"]?.intValue.flatMap { (0..<Puzzle.regions).contains($0) ? $0 : nil })
        }
        let input = j["input"]?.stringValue.flatMap(Puzzle.Input.init) ?? .tap
        let digits = j["digits"]?.intValue.flatMap { (1...9).contains($0) ? $0 : nil }
        guard input != .digits || digits != nil else { return nil }
        var box: (rows: Int, columns: Int)?
        if let b = j["box"]?.arrayValue?.compactMap(\.intValue), b.count == 2, b[0] >= 1, b[1] >= 1, rows % b[0] == 0, columns % b[1] == 0 {
            box = (b[0], b[1])
        }
        let clock = j["clock"]
        let seconds = clock?["seconds"]?.doubleValue.flatMap { $0.isFinite && $0 >= 0 ? min($0, 359_999) : nil }
        return Puzzle(rows: rows, columns: columns, cells: cells, input: input, digits: digits, box: box, edges: Array(edges), plots: Array(plots),
                      seconds: seconds, running: seconds != nil && (clock?["running"]?.boolValue ?? false), locked: j["locked"]?.boolValue ?? false)
    }
}
