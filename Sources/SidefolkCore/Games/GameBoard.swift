import Foundation

/// What a game shows right now in the Play panel (D75), read from a game's answer to `sidefolk/game.start` or
/// `sidefolk/game.move`. As for pages (D62), a game says what is true and Sidefolk draws every part itself, so a board
/// follows the theme, dark mode and right to left, and can't pass for Sidefolk's own cards. Every text is the game's,
/// cleaned and clipped here; it is shown only inside the panel, under the game's badge, and never reaches a model. A
/// part this version doesn't know is skipped, so a newer game still opens.
public struct GameBoard: Sendable, Hashable {
    public var parts: [Part]
    /// One reaction of the companion's, from Sidefolk's fixed lists (`GameCue`).
    public var cue: GameCue?
    /// The game has ended: the panel stops its timers and the Activity row is written.
    public var over: Bool
    /// Words the companion says for one of Sidefolk's own games (its bluff in rock, paper, scissors). Never read from
    /// an extension's board, which can only name a line key.
    public var said: String?
    /// Show this board for so many seconds, then ask the game for its next one (`{next: true}`): the companion thinking
    /// before its move, two cards left face up a moment. The game never keeps time itself.
    public var after: Double?

    public init(parts: [Part] = [], cue: GameCue? = nil, over: Bool = false, after: Double? = nil) {
        self.parts = parts
        self.cue = cue
        self.over = over
        self.after = after
    }

    public static let maxBytes = 64 * 1024
    static let maxParts = 16

    public enum Part: Sendable, Hashable {
        case prompt(Prompt)
        case answers(Answers)
        case board(Grid)
        case score(Score)
        case result(Result)
        case timer(Timer)
        case reveal(Reveal)
        case note(Note)
        case facts([Fact])
        case button(Button)
        case choice(Choice)
        // Phase 2 and 3 (GameBoardParts.swift).
        case pads(Pads)
        case cups(Cups)
        case reflex(Reflex)
        case meter(Meter)
        case number(NumberField)
        case letters(Letters)
        case keys(Keys)
        case entry(Entry)
        case sticks(Sticks)
        case lives(Lives)
    }

    public enum Tone: String, Sendable, Hashable { case good, warn, bad, info, neutral }

    /// The question: large text, an eyebrow ("3 of 10") and a chip ("Space").
    public struct Prompt: Sendable, Hashable {
        public var text: String
        public var eyebrow: String?
        public var chip: String?
    }

    /// 2–4 big tiles; a pick sends `{answer: index}`.
    public struct Answers: Sendable, Hashable {
        public enum Layout: String, Sendable, Hashable { case grid, column, row }
        public enum State: String, Sendable, Hashable { case none, picked, right, wrong, faded }
        public struct Tile: Sendable, Hashable {
            public var label: String
            public var state: State
            /// The companion's pick, shown with its face.
            public var companion: Bool
            /// One of Sidefolk's own pictures (`GameArt`) instead of words: rock, paper and scissors.
            public var art: GameArt?
            /// Its key cap when it isn't A–D: a letter, a digit or `?` (Y, N, ? for yes, no and not sure).
            public var key: String? = nil
        }

        public var tiles: [Tile]
        public var layout: Layout
        /// Answered: the tiles show their states and take no more picks.
        public var locked: Bool
    }

    /// A grid of cells up to 8 × 8; a click sends `{cell: [row, column]}`.
    public struct Grid: Sendable, Hashable {
        public enum Mark: String, Sendable, Hashable { case empty, x, o, disc, symbol, letter, cardBack = "card_back", stick, cup }
        public enum State: String, Sendable, Hashable { case none, win, hint, disabled, new }
        public enum Animate: String, Sendable, Hashable { case stamp, drop, flip, lift, pop, swap }
        public struct Cell: Sendable, Hashable {
            public var mark: Mark
            /// The letter or SF Symbol of a `letter` or `symbol` mark, or a disc's colour as `#RRGGBB`.
            public var value: String?
            /// Drawn in the companion's colour rather than the person's.
            public var companion: Bool
            public var state: State
            /// What VoiceOver reads ("top left, empty").
            public var label: String?
            public var animate: Animate?
        }

        public var rows: Int
        public var columns: Int
        public var cells: [Cell]
        public var locked: Bool
        /// `numpad`: the digits 1–9 pick the cells of a 3 × 3 board laid out as on a number pad (7 8 9 on top).
        public var numpad: Bool = false
    }

    /// The header's pills: you against the companion, a streak, round pips.
    public struct Score: Sendable, Hashable {
        public var you: Int
        public var companion: Int
        public var streak: Int?
        public var best: Int?
        /// Rounds needed to win a match (best of three: 2), with each side's wins so far.
        public var rounds: Int?
        /// The companion has made its pick and keeps it hidden: a sealed card with its face in the header.
        public var companionPicked: Bool
    }

    /// The end card: a big figure, a line, a ribbon, facts and what to do next.
    public struct Result: Sendable, Hashable {
        public var figure: String
        public var line: String?
        public var ribbon: String?
        public var tone: Tone
        public var facts: [Fact]
        public var actions: [Button]
    }

    /// A ring or a bar Sidefolk runs; when it ends Sidefolk sends `{timeout: true}`, so a game never keeps time itself.
    /// The same `id` on the next board keeps the same clock running.
    public struct Timer: Sendable, Hashable {
        public var id: String
        public var seconds: Double
    }

    /// A result drawn as it happens, fixed before it plays: a coin, dice or two hands.
    public enum Reveal: Sendable, Hashable {
        case coin(heads: Bool)
        case dice(sides: Int, values: [Int])
        case hands(you: Hand, companion: Hand)
    }

    public struct Note: Sendable, Hashable {
        public var title: String?
        public var text: String
        public var tone: Tone
    }

    public struct Fact: Sendable, Hashable {
        public var label: String
        public var value: String
    }

    /// A button that sends `{button: move}`. One primary a board (D74); Return presses it.
    public struct Button: Sendable, Hashable {
        public enum Style: String, Sendable, Hashable { case primary, secondary, plain }
        public var label: String
        public var move: String
        public var style: Style
        public var symbol: String?
        /// A letter key that presses it as well ("h" for a hint).
        public var key: String?
        public var disabled: Bool
    }

    /// One of a few options (topics, lengths); picking sends `{choice: {name, value}}`.
    public struct Choice: Sendable, Hashable {
        public enum Style: String, Sendable, Hashable { case cards, segmented }
        public struct Option: Sendable, Hashable {
            public var value: String
            public var label: String
            public var detail: String?
            public var symbol: String?
        }

        public var name: String
        public var label: String?
        public var style: Style
        public var options: [Option]
        public var selected: String?
    }
}

/// Pictures Sidefolk draws for a game, named rather than sent.
public enum GameArt: String, Sendable, Hashable, CaseIterable {
    case rock, paper, scissors
}

// MARK: Reading a board

extension GameBoard {
    /// Reads `{parts, companion, over}`. Throws only when it isn't a board at all or is too large; a bad part is left out.
    public static func parse(_ json: JSONValue) throws -> GameBoard {
        guard json.jsonString.utf8.count <= maxBytes else { throw UserFacingError("The game's board is larger than 64 KB.") }
        guard let object = json.objectValue, let raw = object["parts"]?.arrayValue else { throw UserFacingError("That isn't a game board.") }
        var board = GameBoard(parts: raw.prefix(maxParts).compactMap(part), cue: object["companion"].flatMap(GameCue.parse),
                              over: object["over"]?.boolValue ?? false,
                              after: object["after_ms"]?.doubleValue.flatMap { (100...6000).contains($0) ? $0 / 1000 : nil })
        board.keepOnePrimary()
        return board
    }

    /// The first primary button in reading order stays primary (D74); later ones become secondary.
    mutating func keepOnePrimary() {
        var seen = false
        func keep(_ b: inout Button) {
            guard b.style == .primary else { return }
            if seen { b.style = .secondary }
            seen = true
        }
        for i in parts.indices {
            switch parts[i] {
            case .button(var b):
                keep(&b)
                parts[i] = .button(b)
            case .result(var r):
                for j in r.actions.indices { keep(&r.actions[j]) }
                parts[i] = .result(r)
            default: break
            }
        }
    }

    /// The primary button, which Return presses.
    public var primary: Button? {
        for part in parts {
            if case .button(let b) = part, b.style == .primary, !b.disabled { return b }
            if case .result(let r) = part, let b = r.actions.first(where: { $0.style == .primary && !$0.disabled }) { return b }
        }
        return nil
    }

    public var answers: Answers? { parts.lazy.compactMap { if case .answers(let a) = $0 { a } else { nil } }.first }
    public var grid: Grid? { parts.lazy.compactMap { if case .board(let g) = $0 { g } else { nil } }.first }
    public var score: Score? { parts.lazy.compactMap { if case .score(let s) = $0 { s } else { nil } }.first }
    public var timer: Timer? { parts.lazy.compactMap { if case .timer(let t) = $0 { t } else { nil } }.first }
    public var result: Result? { parts.lazy.compactMap { if case .result(let r) = $0 { r } else { nil } }.first }
    public var reveal: Reveal? { parts.lazy.compactMap { if case .reveal(let r) = $0 { r } else { nil } }.first }
    public var pads: Pads? { parts.lazy.compactMap { if case .pads(let p) = $0 { p } else { nil } }.first }
    public var cups: Cups? { parts.lazy.compactMap { if case .cups(let c) = $0 { c } else { nil } }.first }
    public var reflex: Reflex? { parts.lazy.compactMap { if case .reflex(let r) = $0 { r } else { nil } }.first }
    public var numberField: NumberField? { parts.lazy.compactMap { if case .number(let n) = $0 { n } else { nil } }.first }
    public var letters: Letters? { parts.lazy.compactMap { if case .letters(let l) = $0 { l } else { nil } }.first }
    public var keys: Keys? { parts.lazy.compactMap { if case .keys(let k) = $0 { k } else { nil } }.first }
    public var entry: Entry? { parts.lazy.compactMap { if case .entry(let e) = $0 { e } else { nil } }.first }
    public var sticks: Sticks? { parts.lazy.compactMap { if case .sticks(let s) = $0 { s } else { nil } }.first }
    public var lives: Lives? { parts.lazy.compactMap { if case .lives(let l) = $0 { l } else { nil } }.first }

    /// Every button, the end card's included, for the keys that press them.
    public var buttons: [Button] {
        parts.flatMap { part -> [Button] in
            switch part {
            case .button(let b): [b]
            case .result(let r): r.actions
            default: []
            }
        }
    }

    static func part(_ j: JSONValue) -> Part? {
        switch j["type"]?.stringValue {
        case "prompt":
            guard let text = longText(j["text"], 240) else { return nil }
            return .prompt(Prompt(text: text, eyebrow: line(j["eyebrow"], 40), chip: line(j["chip"], 30)))
        case "answers":
            let tiles = (j["items"]?.arrayValue ?? []).prefix(4).compactMap { t -> Answers.Tile? in
                let art = t["art"]?.stringValue.flatMap(GameArt.init(rawValue:))
                guard let label = line(t["label"], 80) ?? art.map({ _ in "" }) else { return nil }
                let key = t["key"]?.stringValue.flatMap { $0.count == 1 && ($0.first!.isLetter || $0.first!.isNumber || $0 == "?") ? $0.uppercased() : nil }
                return Answers.Tile(label: label, state: t["state"]?.stringValue.flatMap(Answers.State.init) ?? .none,
                                    companion: t["companion"]?.boolValue ?? false, art: art, key: key)
            }
            guard tiles.count >= 2 else { return nil }
            return .answers(Answers(tiles: tiles, layout: j["layout"]?.stringValue.flatMap(Answers.Layout.init) ?? .grid,
                                    locked: j["locked"]?.boolValue ?? false))
        case "board":
            guard let rows = j["rows"]?.intValue, let columns = j["columns"]?.intValue, (1...8).contains(rows), (1...8).contains(columns),
                  let raw = j["cells"]?.arrayValue, raw.count == rows * columns else { return nil }
            let cells = raw.map { c in
                Grid.Cell(mark: c["mark"]?.stringValue.flatMap(Grid.Mark.init) ?? .empty, value: line(c["value"], 64),
                          companion: c["companion"]?.boolValue ?? false, state: c["state"]?.stringValue.flatMap(Grid.State.init) ?? .none,
                          label: line(c["label"], 60), animate: c["animate"]?.stringValue.flatMap(Grid.Animate.init))
            }
            return .board(Grid(rows: rows, columns: columns, cells: cells, locked: j["locked"]?.boolValue ?? false,
                               numpad: rows == 3 && columns == 3 && j["keys"]?.stringValue == "numpad"))
        case "score":
            return .score(Score(you: count(j["you"]) ?? 0, companion: count(j["companion"]) ?? 0, streak: count(j["streak"]),
                                best: count(j["best"]), rounds: count(j["rounds"]).flatMap { (1...9).contains($0) ? $0 : nil },
                                companionPicked: j["companion_picked"]?.boolValue ?? false))
        case "result":
            guard let figure = line(j["figure"], 24) else { return nil }
            return .result(Result(figure: figure, line: line(j["line"], 120), ribbon: line(j["ribbon"], 30), tone: tone(j["tone"]),
                                  facts: facts(j["facts"]), actions: (j["actions"]?.arrayValue ?? []).prefix(3).compactMap(button)))
        case "timer":
            guard let seconds = j["seconds"]?.doubleValue, (1...600).contains(seconds), let id = token(j["id"]) else { return nil }
            return .timer(Timer(id: id, seconds: seconds))
        case "reveal":
            return reveal(j).map(Part.reveal)
        case "note":
            guard let text = longText(j["text"], 400) else { return nil }
            return .note(Note(title: line(j["title"], 40), text: text, tone: tone(j["tone"])))
        case "facts":
            let items = facts(j["items"])
            return items.isEmpty ? nil : .facts(items)
        case "button":
            return button(j).map(Part.button)
        case "choice":
            guard let name = token(j["name"]) else { return nil }
            let options = (j["options"]?.arrayValue ?? []).prefix(12).compactMap { o -> Choice.Option? in
                guard let value = token(o["value"]), let label = line(o["label"], 40) else { return nil }
                return Choice.Option(value: value, label: label, detail: line(o["detail"], 60), symbol: ExtensionPage.symbol(o["symbol"]))
            }
            guard options.count >= 2 else { return nil }
            return .choice(Choice(name: name, label: line(j["label"], 40), style: j["style"]?.stringValue.flatMap(Choice.Style.init) ?? .cards,
                                  options: options, selected: token(j["selected"])))
        default:
            return phaseTwo(j)
        }
    }

    static func reveal(_ j: JSONValue) -> Reveal? {
        switch j["kind"]?.stringValue {
        case "coin":
            return j["heads"]?.boolValue.map { .coin(heads: $0) }
        case "dice":
            guard let sides = j["sides"]?.intValue, Toss.sidesRange.contains(sides) else { return nil }
            let values = (j["values"]?.arrayValue ?? []).prefix(Toss.maxDice).compactMap(\.intValue).filter { (1...sides).contains($0) }
            return values.isEmpty ? nil : .dice(sides: sides, values: values)
        case "hands":
            guard let you = j["you"]?.stringValue.flatMap(Hand.init), let companion = j["companion"]?.stringValue.flatMap(Hand.init) else { return nil }
            return .hands(you: you, companion: companion)
        default:
            return nil
        }
    }

    static func button(_ j: JSONValue) -> Button? {
        guard let label = line(j["label"], 30), let move = token(j["move"]) else { return nil }
        let key = j["key"]?.stringValue.flatMap { $0.count == 1 && $0.first!.isLetter ? $0.lowercased() : nil }
        return Button(label: label, move: move, style: j["style"]?.stringValue.flatMap(Button.Style.init) ?? .secondary,
                      symbol: ExtensionPage.symbol(j["symbol"]), key: key, disabled: j["disabled"]?.boolValue ?? false)
    }

    static func facts(_ j: JSONValue?) -> [Fact] {
        (j?.arrayValue ?? []).prefix(4).compactMap { f in
            guard let label = line(f["label"], 30), let value = line(f["value"], 30) else { return nil }
            return Fact(label: label, value: value)
        }
    }

    static func line(_ j: JSONValue?, _ characters: Int) -> String? { ExtensionPage.text(j, characters) }

    /// Text that may hold a line break or two (a question, a fact), cleaned and capped.
    static func longText(_ j: JSONValue?, _ characters: Int) -> String? {
        guard let raw = j?.stringValue else { return nil }
        let text = ExtensionText.clean(raw).replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).clipped(characters)
        return text.isEmpty ? nil : text
    }

    /// A small name a game chose (a move, a timer, an option): lowercase letters, digits, `_` and `-`.
    static func token(_ j: JSONValue?) -> String? {
        guard let s = j?.stringValue, s.range(of: #"^[a-z0-9][a-z0-9_-]{0,39}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    static func count(_ j: JSONValue?) -> Int? { j?.intValue.map { min(max($0, 0), 99_999) } }

    static func tone(_ j: JSONValue?) -> Tone { j?.stringValue.flatMap(Tone.init(rawValue:)) ?? .neutral }
}
