import Foundation

/// The board parts of games beyond questions and grids (docs/EXTENSIONS.md › Games), used as `.play(...)`. Sidefolk
/// draws each, keeps their time and takes the person's input on them; values off their lists are dropped.
public enum PlayPart {
    /// 2–5 pads; `play` is a sequence Sidefolk shows first (each pad lit for `stepMs`, 250–2000, with its note and the
    /// companion's `move`), then the person presses: `.pad(i)`.
    case pads([Pad], play: [Int] = [], stepMs: Int = 600, locked: Bool = false)
    /// 2–5 cups: the gem shown under `hide`, then `swaps` (pairs of positions, up to 40) at `swapMs` each; a pick is
    /// `.cell(row: 0, column: position)`. After it, `revealed` lifts them, the gem under `gem` (nil: under none).
    case cups(count: Int, hide: Int? = nil, swaps: [[Int]] = [], swapMs: Int = 400, picked: Int? = nil, revealed: Bool = false, gem: Int? = nil,
              locked: Bool = false)
    /// A reflex button: `wait` for `afterMs` (300–10000), then `go`; Sidefolk times the press (`.press(milliseconds:)`),
    /// says `early` and sends `.early` before the signal, `.timeout` after `windowMs`. `shows` replaces it once played.
    case reflex(afterMs: Int?, windowMs: Int = 1500, wait: String, go: String, early: String, shows: String? = nil)
    /// A thermometer, 0 cold to 1 warm, with words at either end.
    case meter(Double, label: String? = nil, low: String? = nil, high: String? = nil)
    /// A number field with a digit pad; Return sends `.number(n)`. `history`: earlier guesses, each `higher`, `lower` or `right`.
    case number(min: Int, max: Int, label: String? = nil, history: [(Int, String)] = [], locked: Bool = false)
    /// Letter tiles: `rows` (Daily Word: up to 8 of up to 24, marks `right`, `elsewhere`, `absent`; the row `flip` turns
    /// tile by tile) or `slots` (Balloon Words: `hidden` until guessed). `draft`: what the person types shows in the next row.
    case letters(rows: [[LetterTile]], length: Int, tries: Int? = nil, style: String = "rows", draft: Bool = false, flip: Int? = nil,
                 script: String = "latin")
    /// An on-screen keyboard, up to three pages of up to six rows. `letter`: a key is `.letter(k)`; `spell`: keys make a
    /// word of `length` that Return sends as `.word(w)`. `script` (`latin`, `kana`, `hangul`, `arabic`) says how a typed
    /// word groups (jamo into syllables).
    case keys(pages: [KeyPage], mode: String = "letter", length: Int? = nil, script: String = "latin", locked: Bool = false)
    /// A text field typed with the person's input method: `word` sends `.word(w)`, `text` sends `.text(name:value:)`.
    case entry(name: String, kind: String = "text", label: String? = nil, placeholder: String? = nil, button: String? = nil, max: Int = 40,
               locked: Bool = false)
    /// A row of sticks: a click takes it and the ones after it, up to `take` (`.number(n)`); `groups` and `hint` light some.
    case sticks(total: Int, left: Int, take: Int = 3, groups: [[Int]] = [], hint: [Int] = [], taken: Int = 0, takenBy: String? = nil,
                locked: Bool = false)
    /// Lives left, as `balloon`s or `heart`s.
    case lives(total: Int, left: Int, symbol: String = "heart")

    var json: [String: Any] {
        switch self {
        case .pads(let pads, let play, let step, let locked):
            return ["type": "pads", "items": pads.map(\.json), "play": play, "step_ms": step, "locked": locked]
        case .cups(let count, let hide, let swaps, let ms, let picked, let revealed, let gem, let locked):
            var out = drop(["type": "cups", "count": count, "hide": hide, "swaps": swaps, "swap_ms": ms, "picked": picked, "locked": locked])
            // A lifted set says where the gem was, `null` for under none.
            if revealed { out["gem"] = gem.map { $0 as Any } ?? NSNull() }
            return out
        case .reflex(let after, let window, let wait, let go, let early, let shows):
            return drop(["type": "reflex", "after_ms": after, "window_ms": window, "wait": wait, "go": go, "early": early, "shows": shows])
        case .meter(let value, let label, let low, let high):
            return drop(["type": "meter", "value": value, "label": label, "low": low, "high": high])
        case .number(let min, let max, let label, let history, let locked):
            return drop(["type": "number", "min": min, "max": max, "label": label, "history": history.map { ["value": $0.0, "mark": $0.1] },
                         "locked": locked])
        case .letters(let rows, let length, let tries, let style, let draft, let flip, let script):
            return drop(["type": "letters", "rows": rows.map { $0.map(\.json) }, "length": length, "tries": tries, "style": style, "draft": draft,
                         "flip": flip, "script": script])
        case .keys(let pages, let mode, let length, let script, let locked):
            return drop(["type": "keys", "pages": pages.map(\.json), "mode": mode, "length": length, "script": script, "locked": locked])
        case .entry(let name, let kind, let label, let placeholder, let button, let max, let locked):
            return drop(["type": "entry", "name": name, "kind": kind, "label": label, "placeholder": placeholder, "button": button, "max": max,
                         "locked": locked])
        case .sticks(let total, let left, let take, let groups, let hint, let taken, let by, let locked):
            return drop(["type": "sticks", "total": total, "left": left, "take": take, "groups": groups, "hint": hint, "taken": taken,
                         "taken_by": by, "locked": locked])
        case .lives(let total, let left, let symbol):
            return ["type": "lives", "total": total, "left": left, "symbol": symbol]
        }
    }
}

/// A pad: `shape` circle, triangle, star, square or diamond; `color` blue, green, yellow, red or purple; the companion's
/// `move` as it lights (`accent:wave`, `accent:hop`, `accent:spin`, `accent:bow`).
public struct Pad {
    public var shape: String
    public var color: String
    public var label: String
    public var move: String?

    public init(_ label: String, shape: String, color: String, move: String? = nil) {
        self.label = label
        self.shape = shape
        self.color = color
        self.move = move
    }

    var json: [String: Any] { drop(["shape": shape, "color": color, "label": label, "move": move]) }
}

/// One letter tile: its text, a mark (`none`, `right`, `elsewhere`, `absent`, `hidden`) and the syllable it belongs to.
public struct LetterTile {
    public var text: String
    public var mark: String
    public var group: Int

    public init(_ text: String, mark: String = "none", group: Int = 0) {
        self.text = text
        self.mark = mark
        self.group = group
    }

    var json: [String: Any] { ["text": text, "mark": mark, "group": group] }
}

/// A keyboard page ("あ", "が"): rows of keys, each a single letter with a mark (`right`, `elsewhere`, `absent`, `hit`,
/// `miss`).
public struct KeyPage {
    public var label: String
    public var rows: [[(key: String, mark: String)]]

    public init(_ label: String = "", rows: [[(key: String, mark: String)]]) {
        self.label = label
        self.rows = rows
    }

    var json: [String: Any] { ["label": label, "rows": rows.map { $0.map { ["key": $0.key, "mark": $0.mark] } }] }
}
