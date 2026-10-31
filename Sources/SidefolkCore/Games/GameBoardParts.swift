import Foundation

// The board parts of the games after trivia (the plan's phases 2 and 3, D75 amended): pads, cups, a reflex button, a
// meter, a number field, letter tiles and keyboards, a text field, a row of sticks and lives. As with every part,
// a game says what is true and Sidefolk draws it, times it and takes the person's input on it, each value checked and
// capped here so no game can make a part flood the panel or run for ever.

extension GameBoard {
    /// Coloured pads Sidefolk plays as a sequence (each lit with its note while the companion does its move), then takes
    /// the person's presses: `{pad: i}`.
    public struct Pads: Sendable, Hashable {
        public enum Shape: String, Sendable, Hashable, CaseIterable { case circle, triangle, star, square, diamond }
        public enum Hue: String, Sendable, Hashable, CaseIterable { case blue, green, yellow, red, purple }
        public struct Pad: Sendable, Hashable {
            public var shape: Shape
            public var hue: Hue
            public var label: String
            /// The companion's move as the pad lights (`accent:wave`…).
            public var move: GameCue.Move?
        }

        public var pads: [Pad]
        /// The sequence to show first, as pad indexes; empty when it is the person's turn straight away.
        public var play: [Int]
        /// How long each step shows.
        public var stepSeconds: Double
        public var locked: Bool

        public static let maxSteps = 64
        /// How long Sidefolk plays `play` before taking presses: a pause, then each step.
        public var playSeconds: Double { play.isEmpty ? 0 : 0.6 + Double(play.count) * stepSeconds }
    }

    /// Cups and a gem: the gem shown under `hide`, then the cups swapped (`swaps`, by position) at `swapSeconds` each;
    /// then a pick, `{cell: [0, position]}`. Once picked, `gem` says where it was (`nil` with `revealed`: under none).
    public struct Cups: Sendable, Hashable {
        public var count: Int
        public var hide: Int?
        public var swaps: [[Int]]
        public var swapSeconds: Double
        public var picked: Int?
        /// The cups are lifted: `gem` is where it lay, nil when it was under none (the companion palmed it, for fun).
        public var revealed: Bool
        public var gem: Int?
        public var locked: Bool

        public static let maxSwaps = 40
        /// How long the gem shows, then the shuffle: a pick is taken only after.
        public var shuffleSeconds: Double { swaps.isEmpty || revealed ? 0 : 1.4 + Double(swaps.count) * swapSeconds }
    }

    /// A big button for a reflex duel. Sidefolk waits `after` seconds with the `wait` words, then shows `go` and measures
    /// the press itself (stdin can't time a screen): `{press: {ms}}` from the moment the signal was drawn, `{early: true}`
    /// before it (shown at once with the `early` words), `{timeout: true}` after `window`. `shows` replaces it once
    /// played (the times, "Too soon!").
    public struct Reflex: Sendable, Hashable {
        public var after: Double?
        public var window: Double
        public var wait: String
        public var go: String
        public var early: String
        public var shows: String?
        public var armed: Bool { after != nil && shows == nil }
    }

    /// A thermometer from cold to warm, 0–1, with words: never a colour alone.
    public struct Meter: Sendable, Hashable {
        public var value: Double
        public var label: String?
        public var low: String?
        public var high: String?
    }

    /// A big number field with Sidefolk's digit pad; Return sends `{number: n}` within `min...max`. `history` shows the
    /// guesses so far with whether the answer was higher or lower.
    public struct NumberField: Sendable, Hashable {
        public enum Mark: String, Sendable, Hashable { case higher, lower, right }
        public struct Guess: Sendable, Hashable {
            public var value: Int
            public var mark: Mark
        }
        public var min: Int
        public var max: Int
        public var label: String?
        public var history: [Guess]
        public var locked: Bool
    }

    /// Letter tiles: Daily Word's rows (each marked right, elsewhere or absent, the newest flipping one by one) or
    /// Balloon Words' slots (blanks until guessed). `group` keeps the letters of one Korean syllable or one pinyin
    /// syllable together. With `draft`, what the person types shows in the next row until Return.
    public struct Letters: Sendable, Hashable {
        public enum Mark: String, Sendable, Hashable { case none, right, elsewhere, absent, hidden }
        public enum Style: String, Sendable, Hashable { case rows, slots }
        public struct Tile: Sendable, Hashable {
            public var text: String
            public var mark: Mark
            public var group: Int

            public init(text: String, mark: Mark, group: Int) {
                self.text = text
                self.mark = mark
                self.group = group
            }
        }
        public var style: Style
        public var rows: [[Tile]]
        /// Tiles in a row, for the draft and the empty rows.
        public var length: Int
        /// Rows drawn in all (the tries).
        public var tries: Int
        public var draft: Bool
        /// The row just played: its tiles flip one by one.
        public var flip: Int?
        /// How a typed draft groups (Korean jamo into syllables).
        public var script: Keys.Script

        /// How long the newest row takes to flip, tile after tile.
        public var flipSeconds: Double { flip.flatMap { rows.indices.contains($0) ? 0.35 + Double(rows[$0].count) * 0.22 : nil } ?? 0 }
    }

    /// An on-screen keyboard in the game's script, a page or three of rows (kana in their gojūon order, jamo, Arabic
    /// letters, Latin with its accents). `letter`: each key is a move (`{letter}`); `spell`: keys make a word of
    /// `length` letters that Return sends (`{word}`), with ⌫ and ↵ drawn by Sidefolk.
    public struct Keys: Sendable, Hashable {
        public enum Mode: String, Sendable, Hashable { case letter, spell }
        public enum Script: String, Sendable, Hashable { case latin, kana, hangul, arabic }
        public enum Mark: String, Sendable, Hashable { case none, right, elsewhere, absent, hit, miss }
        public struct Key: Sendable, Hashable {
            public var key: String
            public var mark: Mark
        }
        public struct Page: Sendable, Hashable {
            public var label: String
            public var rows: [[Key]]
        }
        public var pages: [Page]
        public var mode: Mode
        public var length: Int
        public var script: Script
        public var locked: Bool

        public var all: [Key] { pages.flatMap { $0.rows.flatMap { $0 } } }
    }

    /// A text field, typed with the person's input method (Chinese idioms, Japanese and Korean words, an animal's name and
    /// a question to tell it apart): `word` sends `{word}`, `text` sends `{text: {name, value}}`.
    public struct Entry: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable { case word, text }
        public var name: String
        public var kind: Kind
        public var label: String?
        public var placeholder: String?
        public var button: String?
        public var max: Int
        public var locked: Bool
    }

    /// A row of sticks: a click takes that stick and every one after it, up to `take` (`{number: n}`); `groups` and
    /// `hint` light sticks when the companion teaches its trick.
    public struct Sticks: Sendable, Hashable {
        public var total: Int
        public var left: Int
        public var take: Int
        public var groups: [[Int]]
        public var hint: [Int]
        /// The last take, lifted off: how many, and whose.
        public var taken: Int
        public var takenByCompanion: Bool
        public var locked: Bool
    }

    /// Lives left, drawn as balloons or hearts.
    public struct Lives: Sendable, Hashable {
        public enum Symbol: String, Sendable, Hashable { case balloon, heart }
        public var total: Int
        public var left: Int
        public var symbol: Symbol
    }
}

// MARK: Reading the parts

extension GameBoard {
    static func phaseTwo(_ j: JSONValue) -> Part? {
        switch j["type"]?.stringValue {
        case "pads": return pads(j).map(Part.pads)
        case "cups": return cups(j).map(Part.cups)
        case "reflex":
            let words = (line(j["wait"], 24), line(j["go"], 24), line(j["early"], 24))
            guard let wait = words.0, let go = words.1, let early = words.2 else { return nil }
            let after = j["after_ms"]?.doubleValue.flatMap { (300...10_000).contains($0) ? $0 / 1000 : nil }
            let window = min(max(j["window_ms"]?.doubleValue ?? 1500, 300), 5000) / 1000
            return .reflex(Reflex(after: after, window: window, wait: wait, go: go, early: early, shows: line(j["shows"], 40)))
        case "meter":
            guard let v = j["value"]?.doubleValue, v.isFinite else { return nil }
            return .meter(Meter(value: min(max(v, 0), 1), label: line(j["label"], 30), low: line(j["low"], 20), high: line(j["high"], 20)))
        case "number":
            guard let lo = j["min"]?.intValue, let hi = j["max"]?.intValue, abs(lo) <= 1_000_000, abs(hi) <= 1_000_000, lo < hi else { return nil }
            let history = (j["history"]?.arrayValue ?? []).suffix(20).compactMap { g -> NumberField.Guess? in
                guard let v = g["value"]?.intValue, let m = g["mark"]?.stringValue.flatMap(NumberField.Mark.init) else { return nil }
                return NumberField.Guess(value: v, mark: m)
            }
            return .number(NumberField(min: lo, max: hi, label: line(j["label"], 40), history: Array(history), locked: j["locked"]?.boolValue ?? false))
        case "letters": return letters(j).map(Part.letters)
        case "keys": return keys(j).map(Part.keys)
        case "entry":
            guard let name = token(j["name"]) else { return nil }
            let max = min(max(j["max"]?.intValue ?? 40, 1), 120)
            return .entry(Entry(name: name, kind: j["kind"]?.stringValue.flatMap(Entry.Kind.init) ?? .text, label: line(j["label"], 80),
                                placeholder: line(j["placeholder"], 60), button: line(j["button"], 24), max: max,
                                locked: j["locked"]?.boolValue ?? false))
        case "sticks":
            guard let total = j["total"]?.intValue, (1...30).contains(total), let left = j["left"]?.intValue, (0...total).contains(left) else { return nil }
            func indexes(_ v: JSONValue?) -> [Int] { (v?.arrayValue ?? []).prefix(30).compactMap(\.intValue).filter { (0..<total).contains($0) } }
            return .sticks(Sticks(total: total, left: left, take: min(max(j["take"]?.intValue ?? 3, 1), 5),
                                  groups: (j["groups"]?.arrayValue ?? []).prefix(10).map(indexes), hint: indexes(j["hint"]),
                                  taken: min(max(j["taken"]?.intValue ?? 0, 0), total - left),
                                  takenByCompanion: j["taken_by"]?.stringValue == "companion", locked: j["locked"]?.boolValue ?? false))
        case "lives":
            guard let total = j["total"]?.intValue, (1...10).contains(total), let left = j["left"]?.intValue else { return nil }
            return .lives(Lives(total: total, left: min(max(left, 0), total), symbol: j["symbol"]?.stringValue.flatMap(Lives.Symbol.init) ?? .heart))
        default: return nil
        }
    }

    static func pads(_ j: JSONValue) -> Pads? {
        let pads = (j["items"]?.arrayValue ?? []).prefix(5).compactMap { p -> Pads.Pad? in
            guard let shape = p["shape"]?.stringValue.flatMap(Pads.Shape.init), let hue = p["color"]?.stringValue.flatMap(Pads.Hue.init),
                  let label = line(p["label"], 24) else { return nil }
            return Pads.Pad(shape: shape, hue: hue, label: label, move: p["move"]?.stringValue.flatMap(GameCue.Move.init(rawValue:)))
        }
        guard pads.count >= 2 else { return nil }
        let play = (j["play"]?.arrayValue ?? []).prefix(Pads.maxSteps).compactMap(\.intValue)
        guard play.allSatisfy({ pads.indices.contains($0) }) else { return nil }
        let step = min(max(j["step_ms"]?.doubleValue ?? 600, 250), 2000) / 1000
        return Pads(pads: pads, play: Array(play), stepSeconds: step, locked: j["locked"]?.boolValue ?? false)
    }

    static func cups(_ j: JSONValue) -> Cups? {
        guard let count = j["count"]?.intValue, (2...5).contains(count) else { return nil }
        let inRange = { (i: Int) in (0..<count).contains(i) }
        let swaps = (j["swaps"]?.arrayValue ?? []).prefix(Cups.maxSwaps).compactMap { s -> [Int]? in
            guard let a = s.arrayValue?.compactMap(\.intValue), a.count == 2, a.allSatisfy(inRange), a[0] != a[1] else { return nil }
            return a
        }
        let gem = j["gem"]?.intValue
        return Cups(count: count, hide: j["hide"]?.intValue.flatMap { inRange($0) ? $0 : nil }, swaps: swaps,
                    swapSeconds: min(max(j["swap_ms"]?.doubleValue ?? 400, 150), 1500) / 1000,
                    picked: j["picked"]?.intValue.flatMap { inRange($0) ? $0 : nil }, revealed: j["gem"] != nil,
                    gem: gem.flatMap { inRange($0) ? $0 : nil }, locked: j["locked"]?.boolValue ?? false)
    }

    static func letters(_ j: JSONValue) -> Letters? {
        guard let length = j["length"]?.intValue, (1...24).contains(length) else { return nil }
        let rows = (j["rows"]?.arrayValue ?? []).prefix(8).map { row in
            (row.arrayValue ?? []).prefix(24).map { t in
                Letters.Tile(text: line(t["text"], 4) ?? "", mark: t["mark"]?.stringValue.flatMap(Letters.Mark.init) ?? .none,
                             group: min(max(t["group"]?.intValue ?? 0, 0), 24))
            }
        }
        let tries = min(max(j["tries"]?.intValue ?? rows.count, rows.count), 8)
        return Letters(style: j["style"]?.stringValue.flatMap(Letters.Style.init) ?? .rows, rows: Array(rows), length: length,
                       tries: max(tries, 1), draft: j["draft"]?.boolValue ?? false,
                       flip: j["flip"]?.intValue.flatMap { rows.indices.contains($0) ? $0 : nil },
                       script: j["script"]?.stringValue.flatMap(Keys.Script.init) ?? .latin)
    }

    static func keys(_ j: JSONValue) -> Keys? {
        func row(_ r: JSONValue) -> [Keys.Key] {
            (r.arrayValue ?? []).prefix(14).compactMap { k in
                guard let key = k["key"]?.stringValue, key.count == 1, key.first!.isLetter else { return nil }
                return Keys.Key(key: key, mark: k["mark"]?.stringValue.flatMap(Keys.Mark.init) ?? .none)
            }
        }
        let raw = j["pages"]?.arrayValue ?? [["label": "", "rows": j["rows"] ?? []]]
        let pages = raw.prefix(3).compactMap { p -> Keys.Page? in
            let rows = (p["rows"]?.arrayValue ?? []).prefix(6).map(row).filter { !$0.isEmpty }
            return rows.isEmpty ? nil : Keys.Page(label: line(p["label"], 6) ?? "", rows: rows)
        }
        guard !pages.isEmpty else { return nil }
        return Keys(pages: pages, mode: j["mode"]?.stringValue.flatMap(Keys.Mode.init) ?? .letter,
                    length: min(max(j["length"]?.intValue ?? 5, 1), 24), script: j["script"]?.stringValue.flatMap(Keys.Script.init) ?? .latin,
                    locked: j["locked"]?.boolValue ?? false)
    }
}
