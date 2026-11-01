import Foundation

/// A page the extension adds to Home (docs/EXTENSIONS.md › Pages). It says what is true; Sidefolk draws it with its
/// own parts, keeps the past of every chart, and refreshes it as often as the manifest says.
///
/// ```swift
/// ext.page("mac") { args in
///     Page(summary: Summary("All good", detail: "CPU 12%", tone: .good),
///          sections: [Section("Right now", [.gauge("CPU", "12%", fraction: 0.12, tone: .good)])])
/// }
/// ```
public struct Page {
    public var summary: Summary?
    public var sections: [Section]
    /// A game extension's records, for Sidefolk's Game Center (D93): it draws the page itself from these.
    public var games: GameRecords?

    public init(summary: Summary? = nil, sections: [Section] = [], games: GameRecords? = nil) {
        self.summary = summary
        self.sections = sections
        self.games = games
    }

    var json: [String: Any] {
        var out: [String: Any] = ["sections": sections.filter { !$0.blocks.isEmpty }.map(\.json)]
        if let summary { out["summary"] = summary.json }
        if let games { out["games"] = games.json }
        return out
    }
}

/// What a game extension says of its games for the Game Center (D93): each game's tallies, its best in its own words
/// and its board or word of the day, by the game's name in the manifest, and its last games. Numbers and short text:
/// Sidefolk lays the center out and draws every picture from its own art by the game's look.
public struct GameRecords {
    public struct Record {
        public var played, won, lost, drawn, streak, bestStreak: Int
        /// "Best: 9 moves", "Fair 3:12".
        public var best: String?
        /// The day's board or word: what to say of it, whether it is done, the days in a row.
        public var today: (text: String, done: Bool, streak: Int)?

        public init(played: Int = 0, won: Int = 0, lost: Int = 0, drawn: Int = 0, streak: Int = 0, bestStreak: Int = 0, best: String? = nil,
                    today: (text: String, done: Bool, streak: Int)? = nil) {
            (self.played, self.won, self.lost, self.drawn, self.streak, self.bestStreak) = (played, won, lost, drawn, streak, bestStreak)
            self.best = best
            self.today = today
        }

        var json: [String: Any] {
            var out: [String: Any] = ["played": played, "won": won, "lost": lost, "drawn": drawn, "streak": streak, "best_streak": bestStreak]
            if let best { out["best"] = best }
            if let today { out["today"] = ["text": today.text, "done": today.done, "streak": today.streak] as [String: Any] }
            return out
        }
    }

    public enum Outcome: String { case won, lost, draw, solved }

    /// A game played to the end: its name (or a tally of its own under it, `higher_lower_yours`), when, how it went,
    /// and the score or time in its words.
    public struct Recent {
        public var game: String
        public var at: Date
        public var outcome: Outcome
        public var text: String?

        public init(game: String, at: Date, outcome: Outcome, text: String? = nil) {
            self.game = game
            self.at = at
            self.outcome = outcome
            self.text = text
        }
    }

    /// Two people's head-to-head in a game (D96): their names, each one's wins, the draws.
    public struct Duel {
        public var game: String
        public var names: [String]
        public var wins: [Int]
        public var draws: Int

        public init(game: String, names: [String], wins: [Int], draws: Int = 0) {
            self.game = game
            self.names = names
            self.wins = wins
            self.draws = draws
        }
    }

    public var records: [String: Record]
    public var recent: [Recent]
    /// The games two people can play each other on one Mac (D96), by name: Sidefolk offers "2 players" for them.
    public var twoPlayers: [String]
    public var duels: [Duel]

    public init(records: [String: Record] = [:], recent: [Recent] = [], twoPlayers: [String] = [], duels: [Duel] = []) {
        self.records = records
        self.recent = recent
        self.twoPlayers = twoPlayers
        self.duels = duels
    }

    var json: [String: Any] {
        let iso = ISO8601DateFormatter()
        var out: [String: Any] = ["records": records.mapValues(\.json),
                                  "recent": recent.map { r -> [String: Any] in
                                      var out: [String: Any] = ["game": r.game, "at": iso.string(from: r.at), "outcome": r.outcome.rawValue]
                                      if let text = r.text { out["text"] = text }
                                      return out
                                  }]
        if !twoPlayers.isEmpty { out["two_players"] = twoPlayers }
        if !duels.isEmpty {
            out["duels"] = duels.map { ["game": $0.game, "names": $0.names, "wins": $0.wins, "draws": $0.draws] as [String: Any] }
        }
        return out
    }
}

public enum Tone: String {
    case good, warn, bad, info, neutral
}

/// The page in one line: on top of the page, and the Today tile when the manifest asks for one. `control`, a `.toggle`
/// or a `.button`, is the extension's main switch: Sidefolk shows it with the summary, on the Today tile and beside
/// the page in Home's sidebar (anything else there is ignored).
public struct Summary {
    public var title: String
    public var detail: String
    public var tone: Tone
    public var symbol: String?
    public var control: Block?

    public init(_ title: String, detail: String = "", tone: Tone = .neutral, symbol: String? = nil, control: Block? = nil) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
        self.control = control
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "detail": detail, "tone": tone.rawValue]
        if let symbol { out["symbol"] = symbol }
        if let control { out["control"] = control.json }
        return out
    }
}

public struct Section {
    /// `side`: in a wide window, in a column beside the main sections at the start edge (a list of devices to pick
    /// from); narrower, in the page's order.
    public enum Place: String { case main, side, bottom }

    public var title: String?
    public var detail: String?
    public var blocks: [Block]
    public var place: Place
    /// Folded under its title (`true`) or open (`false`) until the person opens or folds it: settings most people never
    /// change. nil: always open.
    public var collapsed: Bool?

    public init(_ title: String? = nil, _ blocks: [Block], place: Place = .main, collapsed: Bool? = nil, detail: String? = nil) {
        self.title = title
        self.detail = detail
        self.blocks = blocks
        self.place = place
        self.collapsed = collapsed
    }

    var json: [String: Any] {
        var out: [String: Any] = ["blocks": blocks.map(\.json)]
        if let title { out["title"] = title }
        if let detail { out["detail"] = detail }
        if place != .main { out["place"] = place.rawValue }
        if let collapsed { out["collapsed"] = collapsed }
        return out
    }
}

/// One line of a chart: its value now. Sidefolk remembers the earlier ones.
public struct Series {
    public var key: String
    public var label: String
    public var value: Double
    public var display: String?

    public init(_ key: String, _ label: String, _ value: Double, display: String? = nil) {
        self.key = key
        self.label = label
        self.value = value
        self.display = display
    }
}

public struct Bar {
    public var label: String
    public var value: String
    public var fraction: Double
    public var tone: Tone

    public init(_ label: String, _ value: String, fraction: Double, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.fraction = fraction
        self.tone = tone
    }
}

public enum Block {
    /// A ring filled to `fraction` (0–1) with the value inside.
    case gauge(_ label: String, _ value: String, fraction: Double, tone: Tone = .neutral, caption: String? = nil)
    case stat(_ label: String, _ value: String, tone: Tone = .neutral, caption: String? = nil)
    /// `id` names the chart's history; `max` is the axis's top (nil scales to the data).
    case chart(id: String, _ title: String, unit: String? = nil, max: Double? = nil, caption: String? = nil, series: [Series])
    case bars(_ title: String, caption: String? = nil, _ items: [Bar])
    case facts(_ title: String? = nil, _ items: [(String, String)])
    case note(_ text: String, tone: Tone = .neutral)
    /// A button that asks Sidefolk this, as if typed in Ask.
    case ask(_ label: String, _ ask: String)
    /// A switch that runs one of this extension's tools with `on` (the new state) merged into `input`.
    case toggle(_ label: String, detail: String? = nil, on: Bool, tool: String, input: [String: Any] = [:])
    /// A button that runs one of this extension's tools with `input`.
    case button(_ label: String, tool: String, input: [String: Any] = [:], style: ButtonStyle = .secondary, symbol: String? = nil)
    /// One of a few options, as `(value, label)`: picking one runs one of this extension's tools with `value` (the
    /// option's) merged into `input`.
    case choice(_ label: String, detail: String? = nil, options: [(String, String)], selected: String, tool: String, input: [String: Any] = [:])
    /// A text field with a button: runs one of this extension's tools with what was typed merged into `input` as `key`.
    case field(_ label: String, detail: String? = nil, placeholder: String? = nil, button: String, tool: String, input: [String: Any] = [:],
               key: String = "text")
    /// Rows with a picture, a colour or a symbol, a line under each, and a button each (Copy, Remove).
    case list(_ title: String? = nil, caption: String? = nil, _ rows: [Row])
    /// One of a list of things, drawn as what it chooses between: `.cards` (presets, a line each), `.tiles` (pictures:
    /// displays, windows), `.rows` (devices or accounts with a badge each). Picking one runs one of this extension's
    /// tools with the option's value merged into `input` as `key`. An older Sidefolk draws it as a plain choice.
    case picker(_ label: String, detail: String? = nil, style: PickerStyle = .rows, _ options: [Option], selected: String, tool: String,
                input: [String: Any] = [:], key: String = "value", disabled: Bool = false)
    /// What the page is about right now, large, with its main actions; leading the page, it replaces the summary.
    case hero(Hero)
    /// Where something playing is, with its buttons (play or pause as the primary one).
    case transport(Transport)
    /// A button with all its options: a line on hover, dimmed when it can't run yet.
    case action(Action)

    var json: [String: Any] {
        switch self {
        case .gauge(let label, let value, let fraction, let tone, let caption):
            return Self.dropNil(["type": "gauge", "label": label, "value": value, "fraction": fraction, "tone": tone.rawValue, "caption": caption])
        case .stat(let label, let value, let tone, let caption):
            return Self.dropNil(["type": "stat", "label": label, "value": value, "tone": tone.rawValue, "caption": caption])
        case .chart(let id, let title, let unit, let max, let caption, let series):
            return Self.dropNil(["type": "chart", "id": id, "title": title, "unit": unit, "max": max, "caption": caption,
                                 "series": series.map { Self.dropNil(["key": $0.key, "label": $0.label, "value": $0.value, "display": $0.display]) }])
        case .bars(let title, let caption, let items):
            return Self.dropNil(["type": "bars", "title": title, "caption": caption,
                                 "items": items.map { ["label": $0.label, "value": $0.value, "fraction": $0.fraction, "tone": $0.tone.rawValue] }])
        case .facts(let title, let items):
            return Self.dropNil(["type": "facts", "title": title, "items": items.map { ["label": $0.0, "value": $0.1] }])
        case .note(let text, let tone):
            return ["type": "note", "text": text, "tone": tone.rawValue]
        case .ask(let label, let ask):
            return ["type": "ask", "label": label, "ask": ask]
        case .toggle(let label, let detail, let on, let tool, let input):
            return Self.dropNil(["type": "switch", "label": label, "detail": detail, "on": on, "tool": tool, "input": input])
        case .button(let label, let tool, let input, let style, let symbol):
            return Self.dropNil(["type": "button", "label": label, "tool": tool, "input": input, "style": style.rawValue, "symbol": symbol])
        case .choice(let label, let detail, let options, let selected, let tool, let input):
            return Self.dropNil(["type": "choice", "label": label, "detail": detail, "selected": selected, "tool": tool, "input": input,
                                 "options": options.map { ["value": $0.0, "label": $0.1] }])
        case .field(let label, let detail, let placeholder, let button, let tool, let input, let key):
            return Self.dropNil(["type": "field", "label": label, "detail": detail, "placeholder": placeholder, "button": button, "tool": tool,
                                 "input": input, "key": key])
        case .list(let title, let caption, let rows):
            return Self.dropNil(["type": "list", "title": title, "caption": caption, "items": rows.map(\.json)])
        case .picker(let label, let detail, let style, let options, let selected, let tool, let input, let key, let disabled):
            return Self.dropNil(["type": "choice", "style": style.rawValue, "label": label, "detail": detail, "selected": selected, "tool": tool,
                                 "input": input, "key": key, "disabled": disabled ? true : nil, "options": options.map(\.json)])
        case .hero(let hero):
            return hero.json
        case .transport(let transport):
            return transport.json
        case .action(let action):
            return action.json
        }
    }

    private static func dropNil(_ values: [String: Any?]) -> [String: Any] { values.compactMapValues { $0 } }
}

/// `primary` is the page's one main action (Sidefolk keeps only the first filled); `plain` is quiet text for what's
/// rarely needed ("Look again", "Forget").
public enum ButtonStyle: String {
    case primary, secondary, destructive, plain
}

public enum PickerStyle: String {
    case segmented, cards, tiles, rows
}

/// A button: runs one of this extension's tools with `input`. `detail` is shown on hover; `disabled` dims it, its
/// detail saying why ("Choose a TV first").
public struct Action {
    public var label: String
    public var tool: String
    public var input: [String: Any]
    public var style: ButtonStyle
    public var symbol: String?
    public var detail: String?
    public var disabled: Bool

    public init(_ label: String, tool: String, input: [String: Any] = [:], style: ButtonStyle = .secondary, symbol: String? = nil,
                detail: String? = nil, disabled: Bool = false) {
        self.label = label
        self.tool = tool
        self.input = input
        self.style = style
        self.symbol = symbol
        self.detail = detail
        self.disabled = disabled
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "button", "label": label, "tool": tool, "input": input, "style": style.rawValue]
        if let symbol { out["symbol"] = symbol }
        if let detail { out["detail"] = detail }
        if disabled { out["disabled"] = true }
        return out
    }
}

/// A small label beside an option: "Paired", "New".
public struct Badge {
    public var text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// One option of a `picker`: a picture (a file in the data folder, as for list rows) or a symbol, a line under its
/// label, a badge, and a small button of its own.
public struct Option {
    public var value: String
    public var label: String
    public var detail: String?
    public var image: String?
    public var symbol: String?
    public var badge: Badge?
    public var action: Action?

    public init(_ value: String, _ label: String, detail: String? = nil, image: String? = nil, symbol: String? = nil, badge: Badge? = nil,
                action: Action? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
        self.image = image
        self.symbol = symbol
        self.badge = badge
        self.action = action
    }

    var json: [String: Any] {
        var out: [String: Any] = ["value": value, "label": label]
        if let detail { out["detail"] = detail }
        if let image { out["image"] = image }
        if let symbol { out["symbol"] = symbol }
        if let badge { out["badge"] = ["text": badge.text, "tone": badge.tone.rawValue] }
        if let action { out["action"] = action.json }
        return out
    }
}

/// What the page is about now: `eyebrow` the state in a few words, a large `title`, `code` a short code to compare
/// (drawn very large), `image` a picture in the data folder, `busy` a spinner, up to four `facts` (live numbers) and
/// three `actions` drawn large.
public struct Hero {
    public var title: String
    public var eyebrow: String?
    public var detail: String?
    public var tone: Tone
    public var symbol: String?
    public var code: String?
    public var image: String?
    public var busy: Bool
    public var facts: [(String, String)]
    public var actions: [Action]

    public init(_ title: String, eyebrow: String? = nil, detail: String? = nil, tone: Tone = .neutral, symbol: String? = nil, code: String? = nil,
                image: String? = nil, busy: Bool = false, facts: [(String, String)] = [], actions: [Action] = []) {
        self.title = title
        self.eyebrow = eyebrow
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
        self.code = code
        self.image = image
        self.busy = busy
        self.facts = facts
        self.actions = actions
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "hero", "title": title, "tone": tone.rawValue, "busy": busy,
                                  "facts": facts.map { ["label": $0.0, "value": $0.1] }, "actions": actions.map(\.json)]
        if let eyebrow { out["eyebrow"] = eyebrow }
        if let detail { out["detail"] = detail }
        if let symbol { out["symbol"] = symbol }
        if let code { out["code"] = code }
        if let image { out["image"] = image }
        return out
    }
}

/// Something playing: `position` and `duration` in seconds, its state, and up to five buttons, each with a symbol.
public struct Transport {
    public enum State: String { case playing, paused, buffering, stopped }

    public var title: String?
    public var detail: String?
    public var position: Double?
    public var duration: Double?
    public var state: State
    public var buttons: [Action]

    public init(title: String? = nil, detail: String? = nil, position: Double? = nil, duration: Double? = nil, state: State, buttons: [Action]) {
        self.title = title
        self.detail = detail
        self.position = position
        self.duration = duration
        self.state = state
        self.buttons = buttons
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "transport", "state": state.rawValue, "buttons": buttons.map(\.json)]
        if let title { out["title"] = title }
        if let detail { out["detail"] = detail }
        if let position { out["position"] = position }
        if let duration { out["duration"] = duration }
        return out
    }
}

/// One row of a `list`: `image` is a picture file in the extension's data folder (`Paths.data`), named relative to it,
/// which Sidefolk reads and draws (a PNG or JPEG up to 4 MB); `color` is `#RRGGBB`; `button` runs one of the
/// extension's tools.
public struct Row {
    public var title: String
    public var detail: String?
    public var image: String?
    public var color: String?
    public var symbol: String?
    public var button: (label: String, tool: String, input: [String: Any], symbol: String?)?

    public init(_ title: String, detail: String? = nil, image: String? = nil, color: String? = nil, symbol: String? = nil,
                button: (label: String, tool: String, input: [String: Any], symbol: String?)? = nil) {
        self.title = title
        self.detail = detail
        self.image = image
        self.color = color
        self.symbol = symbol
        self.button = button
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title]
        if let detail { out["detail"] = detail }
        if let image { out["image"] = image }
        if let color { out["color"] = color }
        if let symbol { out["symbol"] = symbol }
        if let button {
            var b: [String: Any] = ["label": button.label, "tool": button.tool, "input": button.input]
            if let symbol = button.symbol { b["symbol"] = symbol }
            out["button"] = b
        }
        return out
    }
}

/// What a palette lists. `items` in order; `note` is one line under them ("312 copies kept"). `preview`: the palette
/// answers `sidefolk/palette.preview`, so Sidefolk shows the picked item beside the list. `actions`: what the palette
/// as a whole can do, sent to `choose` with an empty item: `clear` (⌥⌘⌫) and `clear_all` (⇧⌥⌘⌫).
public struct PaletteList {
    public var items: [PaletteItem]
    public var note: String?
    public var preview: Bool
    public var actions: [String]

    public init(_ items: [PaletteItem], note: String? = nil, preview: Bool = false, actions: [String] = []) {
        self.items = items
        self.note = note
        self.preview = preview
        self.actions = actions
    }

    var json: [String: Any] {
        var out: [String: Any] = ["items": items.map(\.json)]
        if let note { out["note"] = note }
        if preview { out["preview"] = true }
        if !actions.isEmpty { out["actions"] = actions }
        return out
    }
}

public struct PaletteItem {
    public enum Kind: String { case text, link, image, file, color, code }
    public var id: String
    public var title: String
    public var detail: String?
    public var kind: Kind
    public var pinned: Bool
    /// Besides choosing it: `plain`, `alternate` (⌥: paste when choosing copies, and the other way round), `pin`, `delete`.
    public var actions: [String]
    /// A small picture: a PNG or JPEG in the extension's data folder, named relative to it (`thumbs/abc.png`), at most
    /// 4 MB. Make it small once (a few hundred pixels) rather than pointing at a big original: a list has 200 rows.
    public var image: String?
    /// `#RRGGBB`, drawn as a swatch.
    public var color: String?
    /// A heading drawn above this item when it differs from the one before ("Pinned").
    public var section: String?

    public init(id: String, title: String, detail: String? = nil, kind: Kind = .text, pinned: Bool = false, actions: [String] = [],
                image: String? = nil, color: String? = nil, section: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.pinned = pinned
        self.actions = actions
        self.image = image
        self.color = color
        self.section = section
    }

    var json: [String: Any] {
        var out: [String: Any] = ["id": id, "title": title, "kind": kind.rawValue, "pinned": pinned, "actions": actions]
        if let detail { out["detail"] = detail }
        if let image { out["image"] = image }
        if let color { out["color"] = color }
        if let section { out["section"] = section }
        return out
    }
}

/// The picked item in full, beside the list: its text (up to 20,000 characters), a bigger picture (a file in the data
/// folder, as for items, up to 25 MB), and facts ("Copied", "From").
public struct PalettePreview {
    public var title: String?
    public var text: String?
    /// Shown in a fixed-width font.
    public var code: Bool
    public var image: String?
    public var facts: [(String, String)]

    public init(title: String? = nil, text: String? = nil, code: Bool = false, image: String? = nil, facts: [(String, String)] = []) {
        self.title = title
        self.text = text
        self.code = code
        self.image = image
        self.facts = facts
    }

    var json: [String: Any] {
        var out: [String: Any] = ["code": code, "facts": facts.map { ["label": $0.0, "value": $0.1] }]
        if let title { out["title"] = title }
        if let text { out["text"] = text }
        if let image { out["image"] = image }
        return out
    }
}

/// What choosing an item did: close the palette, paste into the app in front (after putting it on the clipboard).
public struct PaletteChoice {
    public var close: Bool
    public var paste: Bool
    public var message: String?

    public init(close: Bool = false, paste: Bool = false, message: String? = nil) {
        self.close = close
        self.paste = paste
        self.message = message
    }

    var json: [String: Any] {
        var out: [String: Any] = ["close": close, "paste": paste]
        if let message { out["message"] = message }
        return out
    }
}
