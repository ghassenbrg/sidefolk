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
    /// `keys` (two letters, the left player's first): two people share it, each on their own key, and the first key
    /// decides (`.pressKey`, or `.earlyKey` before the signal); clicks don't count then. A Sidefolk from before this
    /// takes Space and clicks only.
    case reflex(afterMs: Int?, windowMs: Int = 1500, wait: String, go: String, early: String, shows: String? = nil, keys: [String]? = nil)
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
    /// A logic puzzle's grid, 2–10 cells a side: cells with a symbol (`heart`, `star`, `blossom`, `dot`) or a number,
    /// givens drawn fixed, pencil `notes`, coloured `region`s (0–11), thick lines around boxes of `box` (Sudoku's 2 × 3 or
    /// 3 × 3), `=` and `×` clues between cells (`edges`) and rectangles (`plots`). `input` is what the person does on it:
    /// `tap` a cell (`.cell`), `drag` a rectangle (`.area`; a click alone is `.cell`), or `digits` from 1 to `digits` into
    /// the cell they pick (`.place`). `seconds` is the time so far, counting on while `running`.
    case puzzle(rows: Int, columns: Int, cells: [PuzzleCell], input: String = "tap", digits: Int? = nil, box: (rows: Int, columns: Int)? = nil,
                edges: [PuzzleEdge] = [], plots: [PuzzlePlot] = [], seconds: Double? = nil, running: Bool = false, locked: Bool = false)

    var json: [String: Any] {
        switch self {
        case .pads(let pads, let play, let step, let locked):
            return ["type": "pads", "items": pads.map(\.json), "play": play, "step_ms": step, "locked": locked]
        case .cups(let count, let hide, let swaps, let ms, let picked, let revealed, let gem, let locked):
            var out = drop(["type": "cups", "count": count, "hide": hide, "swaps": swaps, "swap_ms": ms, "picked": picked, "locked": locked])
            // A lifted set says where the gem was, `null` for under none.
            if revealed { out["gem"] = gem.map { $0 as Any } ?? NSNull() }
            return out
        case .reflex(let after, let window, let wait, let go, let early, let shows, let keys):
            return drop(["type": "reflex", "after_ms": after, "window_ms": window, "wait": wait, "go": go, "early": early, "shows": shows,
                         "keys": keys])
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
        case .puzzle(let rows, let columns, let cells, let input, let digits, let box, let edges, let plots, let seconds, let running, let locked):
            return drop(["type": "puzzle", "rows": rows, "columns": columns, "cells": cells.map(\.json), "input": input, "digits": digits,
                         "box": box.map { [$0.rows, $0.columns] }, "edges": edges.isEmpty ? nil : edges.map(\.json),
                         "plots": plots.isEmpty ? nil : plots.map(\.json),
                         "clock": seconds.map { ["seconds": $0, "running": running] as [String: Any] }, "locked": locked])
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
    /// Sidefolk's picture of the move, drawn instead of the shape: `wave`, `hop`, `spin`, `bow`, `wave_both`. A Sidefolk
    /// that doesn't know it draws the shape.
    public var art: String?

    public init(_ label: String, shape: String, color: String, move: String? = nil, art: String? = nil) {
        self.label = label
        self.shape = shape
        self.color = color
        self.move = move
        self.art = art
    }

    var json: [String: Any] { drop(["shape": shape, "color": color, "label": label, "move": move, "art": art]) }
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

/// A puzzle cell: a `symbol` (`heart`, `star`, `blossom`, `dot`) or `text` (a number, up to two characters), `given`
/// when it can't change, pencil `notes` (1–9), its `region` (0–11, drawn in that region's colour), a `state`
/// (`conflict` where a rule breaks, `hint` for what a hint rests on, `target` where it says to play, its mark shown
/// faintly), and `fresh` for the mark just played.
public struct PuzzleCell {
    public var symbol: String?
    public var text: String?
    public var given: Bool
    public var notes: [Int]
    public var region: Int?
    public var state: String?
    public var fresh: Bool
    /// What VoiceOver reads.
    public var label: String?

    public init(symbol: String? = nil, text: String? = nil, given: Bool = false, notes: [Int] = [], region: Int? = nil, state: String? = nil,
                fresh: Bool = false, label: String? = nil) {
        self.symbol = symbol
        self.text = text
        self.given = given
        self.notes = notes
        self.region = region
        self.state = state
        self.fresh = fresh
        self.label = label
    }

    var json: [String: Any] {
        drop(["symbol": symbol, "text": text, "given": given ? true : nil, "notes": notes.isEmpty ? nil : notes, "region": region, "state": state,
              "fresh": fresh ? true : nil, "label": label])
    }
}

/// A clue between `cell` and the cell right of it (or below it, `down`): `same` (=) or `different` (×).
public struct PuzzleEdge {
    public var cell: Int
    public var down: Bool
    public var clue: String

    public init(cell: Int, down: Bool, clue: String) {
        self.cell = cell
        self.down = down
        self.clue = clue
    }

    var json: [String: Any] { ["cell": cell, "down": down, "clue": clue] }
}

/// A rectangle on the grid (a plot): its top-left cell, size, a `state` (`conflict`, `hint`) and its colour (0–11).
public struct PuzzlePlot {
    public var row: Int
    public var column: Int
    public var height: Int
    public var width: Int
    public var state: String?
    public var tint: Int?

    public init(row: Int, column: Int, height: Int, width: Int, state: String? = nil, tint: Int? = nil) {
        self.row = row
        self.column = column
        self.height = height
        self.width = width
        self.state = state
        self.tint = tint
    }

    var json: [String: Any] { drop(["row": row, "column": column, "height": height, "width": width, "state": state, "tint": tint]) }
}
