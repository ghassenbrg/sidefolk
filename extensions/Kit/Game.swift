import Foundation

/// A game played in Sidefolk's Play panel beside the companion (docs/EXTENSIONS.md › Games, D75). The game keeps its
/// own state and answers with a `Board`; Sidefolk draws every part, sends the person's moves back, keeps the time, and
/// plays the companion's `Cue` from its own fixed lists. Moves are not tool calls: they can only change the game.
///
/// ```swift
/// ext.game("coin", start: { request in
///     GameReply(session: UUID().uuidString, board: Board([.prompt("Heads or tails?"), .answers([Tile("Heads"), Tile("Tails")])]))
/// }, move: { request in
///     Board([.reveal(.coin(heads: Bool.random()))], companion: Cue(move: "cheer"), over: true)
/// })
/// ```
public struct GameRequest {
    /// What the game said its session was when it started; empty in `start`.
    public var session: String
    public var level: String?
    /// The person's language, as Sidefolk speaks it (`en`, `fr`, `pt-BR`, `zh-Hans`, `ar`): see `Localized`.
    public var language: String
    /// Sidefolk's options for every game: `tone` (gentle, cheeky, competitive), `sneaky`, `companion` (its name).
    public var options: Arguments
    /// The person's move, in `move`.
    public var move: Move?
    /// Why it ended, in `end`: `closed`, `timeout` or `finished`.
    public var reason: String?

    init(_ params: [String: Any]) {
        session = params["session"] as? String ?? ""
        level = params["level"] as? String
        language = params["language"] as? String ?? "en"
        options = Arguments(params["options"] as? [String: Any] ?? [:])
        move = (params["move"] as? [String: Any]).map(Move.init)
        reason = params["reason"] as? String
    }
}

/// What starting a game returns: the session Sidefolk sends back with every move (up to 64 letters, digits, `_`, `-`).
public struct GameReply {
    public var session: String
    public var board: Board

    public init(session: String, board: Board) {
        self.session = session
        self.board = board
    }
}

/// The person's move, as Sidefolk sends it: only ever one the board offered.
public enum Move: Equatable {
    case answer(Int)
    case cell(row: Int, column: Int)
    case button(String)
    case choice(name: String, value: String)
    /// A `timer` ran out.
    case timeout
    case letter(String)
    case word(String)
    case number(Int)
    case pad(Int)
    case press(milliseconds: Int)
    case early
    /// The board's `afterMs` passed: answer with the next board (the companion's move once it has thought).
    case next
    /// What was typed in a text `entry`.
    case text(name: String, value: String)
    /// A rectangle dragged on a `puzzle` from one corner cell to the other, in the order dragged.
    case area(row: Int, column: Int, toRow: Int, toColumn: Int)
    /// A number put in a `puzzle` cell (0 clears it), or as a pencil note.
    case place(row: Int, column: Int, value: Int, note: Bool)
    case unknown

    public init(_ json: [String: Any]) {
        if let i = json["answer"] as? Int { self = .answer(i) }
        else if let c = json["cell"] as? [Int], c.count == 2 { self = .cell(row: c[0], column: c[1]) }
        else if let b = json["button"] as? String { self = .button(b) }
        else if let c = json["choice"] as? [String: Any], let n = c["name"] as? String, let v = c["value"] as? String { self = .choice(name: n, value: v) }
        else if json["timeout"] as? Bool == true { self = .timeout }
        else if let l = json["letter"] as? String { self = .letter(l) }
        else if let w = json["word"] as? String { self = .word(w) }
        else if let n = json["number"] as? Int { self = .number(n) }
        else if let p = json["pad"] as? Int { self = .pad(p) }
        else if let p = json["press"] as? [String: Any], let ms = p["ms"] as? Int { self = .press(milliseconds: ms) }
        else if json["early"] as? Bool == true { self = .early }
        else if json["next"] as? Bool == true { self = .next }
        else if let t = json["text"] as? [String: Any], let n = t["name"] as? String, let v = t["value"] as? String { self = .text(name: n, value: v) }
        else if let a = json["area"] as? [Int], a.count == 4 { self = .area(row: a[0], column: a[1], toRow: a[2], toColumn: a[3]) }
        else if let p = json["place"] as? [String: Any], let c = p["cell"] as? [Int], c.count == 2, let v = p["value"] as? Int {
            self = .place(row: c[0], column: c[1], value: v, note: p["note"] as? Bool ?? false)
        }
        else { self = .unknown }
    }
}

/// What the game shows now, top to bottom, and one reaction of the companion's.
public struct Board {
    public var parts: [BoardPart]
    public var companion: Cue?
    /// The game has ended: Sidefolk stops its clock and writes one Activity row.
    public var over: Bool
    /// Sidefolk shows this board so long (100–6000 ms), then asks for the next with `.next`: the companion thinking
    /// before its move, two cards left face up a moment. The game keeps no clock.
    public var afterMs: Int?

    public init(_ parts: [BoardPart], companion: Cue? = nil, over: Bool = false, afterMs: Int? = nil) {
        self.parts = parts
        self.companion = companion
        self.over = over
        self.afterMs = afterMs
    }

    public var json: [String: Any] {
        var out: [String: Any] = ["parts": parts.map(\.json), "over": over]
        if let companion { out["companion"] = companion.json }
        if let afterMs { out["after_ms"] = afterMs }
        return out
    }
}

public enum BoardPart {
    /// The question, large: an eyebrow ("3 of 10") and a chip ("Space").
    case prompt(_ text: String, eyebrow: String? = nil, chip: String? = nil)
    /// 2–4 big tiles; a pick is `.answer(index)`.
    case answers(_ tiles: [Tile], layout: TileLayout = .grid, locked: Bool = false)
    /// Cells up to 8 × 8, row by row; a click is `.cell(row:column:)`. `numpad`: a 3 × 3 board's cells take the digits
    /// as on a number pad (7 8 9 on top).
    case board(rows: Int, columns: Int, cells: [Cell], locked: Bool = false, numpad: Bool = false)
    /// The header's pills: you against the companion, a streak, round pips (`rounds` to win), its sealed pick.
    case score(you: Int, companion: Int, streak: Int? = nil, best: Int? = nil, rounds: Int? = nil, companionPicked: Bool = false)
    /// The end card: a big figure, a line, a ribbon, up to four facts and three buttons.
    case result(figure: String, line: String? = nil, ribbon: String? = nil, tone: Tone = .neutral, facts: [(String, String)] = [],
                actions: [GameButton] = [])
    /// Sidefolk runs it; when it ends the game gets `.timeout`. Keep the same `id` to keep the same clock.
    case timer(id: String, seconds: Double)
    /// A result drawn as it happens.
    case reveal(Reveal)
    case note(_ text: String, title: String? = nil, tone: Tone = .info)
    case facts([(String, String)])
    /// A button that sends `.button(move)`. One primary a board; Return presses it.
    case button(GameButton)
    /// One of a few options, as cards (topics) or segments (lengths); a pick is `.choice(name:value:)`.
    case choice(name: String, label: String? = nil, style: ChoiceStyle = .cards, options: [ChoiceOption], selected: String? = nil)
    /// The parts of the later games (GameParts.swift): pads, cups, a reflex button, a meter, a number field, letter
    /// tiles, a keyboard, a text field, sticks and lives.
    case play(PlayPart)

    var json: [String: Any] {
        switch self {
        case .prompt(let text, let eyebrow, let chip):
            return drop(["type": "prompt", "text": text, "eyebrow": eyebrow, "chip": chip])
        case .answers(let tiles, let layout, let locked):
            return ["type": "answers", "items": tiles.map(\.json), "layout": layout.rawValue, "locked": locked]
        case .board(let rows, let columns, let cells, let locked, let numpad):
            return drop(["type": "board", "rows": rows, "columns": columns, "cells": cells.map(\.json), "locked": locked,
                         "keys": numpad ? "numpad" : nil])
        case .score(let you, let companion, let streak, let best, let rounds, let picked):
            return drop(["type": "score", "you": you, "companion": companion, "streak": streak, "best": best, "rounds": rounds,
                         "companion_picked": picked ? true : nil])
        case .result(let figure, let line, let ribbon, let tone, let facts, let actions):
            return drop(["type": "result", "figure": figure, "line": line, "ribbon": ribbon, "tone": tone.rawValue,
                         "facts": facts.map { ["label": $0.0, "value": $0.1] }, "actions": actions.map(\.json)])
        case .timer(let id, let seconds):
            return ["type": "timer", "id": id, "seconds": seconds]
        case .reveal(let reveal):
            return reveal.json
        case .note(let text, let title, let tone):
            return drop(["type": "note", "text": text, "title": title, "tone": tone.rawValue])
        case .facts(let items):
            return ["type": "facts", "items": items.map { ["label": $0.0, "value": $0.1] }]
        case .button(let button):
            return button.json
        case .choice(let name, let label, let style, let options, let selected):
            return drop(["type": "choice", "name": name, "label": label, "style": style.rawValue, "options": options.map(\.json), "selected": selected])
        case .play(let part):
            return part.json
        }
    }
}

public enum TileLayout: String { case grid, column, row }
public enum TileState: String { case none, picked, right, wrong, faded }
public enum ChoiceStyle: String { case cards, segmented }

public struct Tile {
    public var label: String
    public var state: TileState
    /// The companion's pick, drawn with its face.
    public var companion: Bool
    /// One of Sidefolk's pictures instead of words: `rock`, `paper`, `scissors`.
    public var art: String?
    /// Its key cap when it isn't A–D: a letter, a digit or `?`.
    public var key: String?

    public init(_ label: String, state: TileState = .none, companion: Bool = false, art: String? = nil, key: String? = nil) {
        self.label = label
        self.state = state
        self.companion = companion
        self.art = art
        self.key = key
    }

    var json: [String: Any] { drop(["label": label, "state": state.rawValue, "companion": companion ? true : nil, "art": art, "key": key]) }
}

public struct Cell {
    /// `empty`, `x`, `o`, `disc`, `symbol`, `letter`, `card_back`, `stick`, `cup`.
    public var mark: String
    /// The letter, the SF Symbol, or a disc's `#RRGGBB`.
    public var value: String?
    public var companion: Bool
    /// `win`, `hint`, `disabled`, `new`.
    public var state: String?
    /// What VoiceOver reads.
    public var label: String?
    /// `stamp`, `drop`, `flip`, `lift`, `pop`, `swap`.
    public var animate: String?

    public init(_ mark: String = "empty", value: String? = nil, companion: Bool = false, state: String? = nil, label: String? = nil,
                animate: String? = nil) {
        self.mark = mark
        self.value = value
        self.companion = companion
        self.state = state
        self.label = label
        self.animate = animate
    }

    var json: [String: Any] {
        drop(["mark": mark, "value": value, "companion": companion ? true : nil, "state": state, "label": label, "animate": animate])
    }
}

public enum Reveal {
    case coin(heads: Bool)
    case dice(sides: Int, values: [Int])
    /// `rock`, `paper` or `scissors` each.
    case hands(you: String, companion: String)

    var json: [String: Any] {
        switch self {
        case .coin(let heads): ["type": "reveal", "kind": "coin", "heads": heads]
        case .dice(let sides, let values): ["type": "reveal", "kind": "dice", "sides": sides, "values": values]
        case .hands(let you, let companion): ["type": "reveal", "kind": "hands", "you": you, "companion": companion]
        }
    }
}

public struct GameButton {
    public var label: String
    /// What `.button(move)` says: lowercase letters, digits, `_` and `-`.
    public var move: String
    public var style: ButtonStyle
    public var symbol: String?
    /// A letter key that presses it too ("h" for a hint).
    public var key: String?
    public var disabled: Bool

    public init(_ label: String, move: String, style: ButtonStyle = .secondary, symbol: String? = nil, key: String? = nil, disabled: Bool = false) {
        self.label = label
        self.move = move
        self.style = style
        self.symbol = symbol
        self.key = key
        self.disabled = disabled
    }

    var json: [String: Any] {
        drop(["type": "button", "label": label, "move": move, "style": style == .destructive ? "secondary" : style.rawValue, "symbol": symbol,
              "key": key, "disabled": disabled ? true : nil])
    }
}

public struct ChoiceOption {
    public var value: String
    public var label: String
    public var detail: String?
    public var symbol: String?

    public init(_ value: String, _ label: String, detail: String? = nil, symbol: String? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
        self.symbol = symbol
    }

    var json: [String: Any] { drop(["value": value, "label": label, "detail": detail, "symbol": symbol]) }
}

/// How the companion reacts, every value from Sidefolk's fixed lists (anything else is dropped):
/// - `move`: think, cheer, celebrate, sulk, bow, nod, shrug, giggle, wince, gasp, tease, sweat, dizzy, ready, shuffle, hop,
///   spin, wave, dance, accent:wave, accent:hop, accent:spin, accent:bow
/// - `effect`: confetti, sparkles, hearts, question, exclaim, sweat, stars, frost, flame
/// - `prop`: balloons(1)…balloons(9), hat, crown, magnifier, cards, sealed_card, gem, none
/// - `line`: a key, never text (Sidefolk says its own words, in the person's language and tone): hello, your_turn,
///   my_turn, thinking, close_one, you_win, i_win, draw, record, streak, encourage, tease, caught_cheating, hint_intro, bye
/// - `sound`: tap, flip, rattle, pop, ding, boop, tick, whoosh, stamp, shuffle, snap, cork, fanfare, trombone
/// - `look`: panel, you, away, or a cell `[row, column]`
public struct Cue {
    public var move: String?
    public var effect: String?
    public var prop: String?
    public var line: String?
    public var sound: String?
    public var look: Any?

    public init(move: String? = nil, effect: String? = nil, prop: String? = nil, line: String? = nil, sound: String? = nil, look: Any? = nil) {
        self.move = move
        self.effect = effect
        self.prop = prop
        self.line = line
        self.sound = sound
        self.look = look
    }

    var json: [String: Any] { drop(["move": move, "effect": effect, "prop": prop, "line": line, "sound": sound, "look": look]) }
}

func drop(_ values: [String: Any?]) -> [String: Any] { values.compactMapValues { $0 } }

extension Extension {
    /// A game the manifest declares (`games.<name>`): `start` makes a session and its first board, `move` answers each
    /// move with the next board, `end` hears that the panel closed, was left too long, or the game finished. Answer
    /// within two seconds and under 64 KB, or Sidefolk ends the game.
    public func game(_ name: String, start: @escaping @MainActor (GameRequest) async throws -> GameReply,
                     move: @escaping @MainActor (GameRequest) async throws -> Board,
                     end: @escaping @MainActor (GameRequest) async -> Void = { _ in }) {
        games[name] = (start, move, end)
    }
}
