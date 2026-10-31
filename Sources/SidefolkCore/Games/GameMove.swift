import Foundation

/// What the person did on a board, as Sidefolk sends it with `sidefolk/game.move` (D75). Small and typed: Sidefolk
/// makes it from a click or a key on a part it drew, so a game only ever hears moves its own board offered.
public enum GameMove: Sendable, Hashable {
    case answer(Int)
    case cell(row: Int, column: Int)
    case button(String)
    case choice(name: String, value: String)
    /// A `timer` part ran out.
    case timeout
    case letter(Character)
    case word(String)
    case number(Int)
    case pad(Int)
    /// A reflex press, timed by Sidefolk (stdin can't time a screen).
    case press(milliseconds: Int)
    case early
    /// The board's `after` time passed: the game's next board (the companion's move after it thought).
    case next
    /// What was typed in an `entry` of kind `text` (an animal's name, a question).
    case text(name: String, value: String)

    public var json: JSONValue {
        switch self {
        case .answer(let i): ["answer": .number(Double(i))]
        case .cell(let r, let c): ["cell": [.number(Double(r)), .number(Double(c))]]
        case .button(let move): ["button": .string(move)]
        case .choice(let name, let value): ["choice": ["name": .string(name), "value": .string(value)]]
        case .timeout: ["timeout": true]
        case .letter(let l): ["letter": .string(String(l))]
        case .word(let w): ["word": .string(w)]
        case .number(let n): ["number": .number(Double(n))]
        case .pad(let p): ["pad": .number(Double(p))]
        case .press(let ms): ["press": ["ms": .number(Double(ms))]]
        case .early: ["early": true]
        case .next: ["next": true]
        case .text(let name, let value): ["text": ["name": .string(name), "value": .string(value)]]
        }
    }

    /// Reads one move, for the dev commands (`move:{"answer":2}`) and tests; nil for anything else.
    public static func parse(_ j: JSONValue) -> GameMove? {
        guard let object = j.objectValue, object.count == 1, let (key, value) = object.first else { return nil }
        switch key {
        case "answer": return value.intValue.flatMap { (0..<4).contains($0) ? .answer($0) : nil }
        case "cell":
            guard let a = value.arrayValue, a.count == 2, let r = a[0].intValue, let c = a[1].intValue, (0..<8).contains(r), (0..<8).contains(c)
            else { return nil }
            return .cell(row: r, column: c)
        case "button": return GameBoard.token(value).map(GameMove.button)
        case "choice":
            guard let name = GameBoard.token(value["name"]), let v = GameBoard.token(value["value"]) else { return nil }
            return .choice(name: name, value: v)
        case "timeout": return value.boolValue == true ? .timeout : nil
        case "letter":
            guard let s = value.stringValue, s.count == 1, let l = s.first, l.isLetter else { return nil }
            return .letter(Character(l.lowercased()))
        case "word":
            guard let s = value.stringValue, (1...24).contains(s.count), s.allSatisfy(\.isLetter) else { return nil }
            return .word(s.lowercased())
        case "number": return value.intValue.flatMap { abs($0) <= 1_000_000 ? .number($0) : nil }
        case "pad": return value.intValue.flatMap { (0..<8).contains($0) ? .pad($0) : nil }
        case "press": return value["ms"]?.intValue.flatMap { (0...60_000).contains($0) ? .press(milliseconds: $0) : nil }
        case "early": return value.boolValue == true ? .early : nil
        case "next": return value.boolValue == true ? .next : nil
        case "text":
            guard let name = GameBoard.token(value["name"]), let raw = value["value"]?.stringValue else { return nil }
            let text = ExtensionText.clean(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return (1...120).contains(text.count) && !text.contains(where: \.isNewline) ? .text(name: name, value: text) : nil
        default: return nil
        }
    }

    /// Whether the board on screen offered this move: a game hears only what its own board asked for.
    public func offered(by board: GameBoard) -> Bool {
        switch self {
        case .answer(let i):
            guard let a = board.answers, !a.locked else { return false }
            return a.tiles.indices.contains(i) && a.tiles[i].state != .faded
        case .cell(let r, let c):
            if let cups = board.cups { return r == 0 && c < cups.count && !cups.locked && !cups.revealed }
            guard let g = board.grid, !g.locked, r < g.rows, c < g.columns else { return false }
            let cell = g.cells[r * g.columns + c]
            return cell.state != .disabled
        case .button(let move): return board.buttons.contains { $0.move == move && !$0.disabled }
        case .choice(let name, let value):
            return board.parts.contains { part in
                if case .choice(let ch) = part { return ch.name == name && ch.options.contains { $0.value == value } }
                return false
            }
        case .timeout: return board.timer != nil || board.reflex?.armed == true
        case .letter: return board.keys.map { $0.mode == .letter && !$0.locked } ?? false
        case .word(let w):
            if let keys = board.keys, keys.mode == .spell, !keys.locked { return true }
            if let entry = board.entry, entry.kind == .word, !entry.locked { return w.count <= entry.max }
            return false
        case .number(let n):
            if let field = board.numberField, !field.locked { return (field.min...field.max).contains(n) }
            if let sticks = board.sticks, !sticks.locked { return (1...min(sticks.take, sticks.left)).contains(n) }
            return false
        case .pad(let i): return board.pads.map { !$0.locked && $0.pads.indices.contains(i) } ?? false
        case .press, .early: return board.reflex?.armed == true
        case .next: return board.after != nil
        case .text(let name, let value):
            guard let entry = board.entry, entry.kind == .text, !entry.locked else { return false }
            return entry.name == name && value.count <= entry.max
        }
    }
}

/// Why a game ended, as `sidefolk/game.end` says it.
public enum GameEndReason: String, Sendable {
    /// The person closed the panel (✕, Esc, or opening Ask).
    case closed
    /// Left open and untouched past the time a game is kept.
    case timeout
    /// The board said it was over.
    case finished
}
