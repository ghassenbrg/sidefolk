import Foundation

/// A rail of things in order (`steps`, D113): a line threading through stops, each a sentence with its state, for anything that happens one
/// after another: a recipe, a checklist, a pipeline, a day. Sidefolk draws it, with keyboard and VoiceOver; moving and adding are your tools'.
public struct StepRail {
    public struct Item {
        public enum State: String { case none, pending, running, waiting, done, failed, skipped }

        public var id: String
        public var title: String
        public var detail: String?
        /// A short word at the trailing end: what it came to.
        public var result: String?
        public var symbol: String?
        /// `#RRGGBB`: the tile behind its symbol.
        public var color: String?
        public var tone: Tone
        public var state: State
        public var badge: Badge?
        /// How far in: 0 on the line, 1 or 2 on a branch from it.
        public var depth: Int
        /// A branch's first word: "If yes".
        public var label: String?
        /// Can't be moved or have anything added after it (what starts the rail).
        public var locked: Bool
        /// Up to two small buttons.
        public var actions: [Action]
        /// Longer text it produced, folded under the row.
        public var output: String?

        public init(_ id: String, _ title: String, detail: String? = nil, result: String? = nil, symbol: String? = nil, color: String? = nil, tone: Tone = .neutral,
                    state: State = .none, badge: Badge? = nil, depth: Int = 0, label: String? = nil, locked: Bool = false, actions: [Action] = [], output: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.result = result
            self.symbol = symbol
            self.color = color
            self.tone = tone
            self.state = state
            self.badge = badge
            self.depth = depth
            self.label = label
            self.locked = locked
            self.actions = actions
            self.output = output
        }

        var json: [String: Any] {
            var out: [String: Any] = ["id": id, "title": title, "tone": tone.rawValue, "state": state.rawValue, "depth": depth]
            if let detail { out["detail"] = detail }
            if let result { out["result"] = result }
            if let symbol { out["symbol"] = symbol }
            if let color { out["color"] = color }
            if let badge { out["badge"] = ["text": badge.text, "tone": badge.tone.rawValue] }
            if let label { out["label"] = label }
            if locked { out["locked"] = true }
            if !actions.isEmpty { out["actions"] = actions.map(\.json) }
            if let output { out["output"] = output }
            return out
        }
    }

    /// A tool to run, with what the person pointed at merged into `input` under `key`.
    public struct Hook {
        public var tool: String
        public var input: [String: Any]
        public var key: String
        /// What the "add" button says.
        public var label: String?

        public init(tool: String, input: [String: Any] = [:], key: String, label: String? = nil) {
            self.tool = tool
            self.input = input
            self.key = key
            self.label = label
        }

        var json: [String: Any] {
            var out: [String: Any] = ["tool": tool, "input": input, "key": key]
            if let label { out["label"] = label }
            return out
        }
    }

    public var title: String?
    public var caption: String?
    public var items: [Item]
    public var selected: String?
    /// Clicking a row: `key` holds its id.
    public var select: Hook?
    /// Moving a row: `key` holds `{"id": moved, "before": the id it now stands before, or nothing at the end}`.
    public var reorder: Hook?
    /// The + after a row: `key` holds its id.
    public var insert: Hook?
    /// `#RRGGBB`, one or two: the line, as a gradient from the first stop to the last.
    public var line: [String]

    public init(_ title: String? = nil, caption: String? = nil, _ items: [Item], selected: String? = nil, select: Hook? = nil, reorder: Hook? = nil, insert: Hook? = nil, line: [String] = []) {
        self.title = title
        self.caption = caption
        self.items = items
        self.selected = selected
        self.select = select
        self.reorder = reorder
        self.insert = insert
        self.line = line
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "steps", "items": items.map(\.json)]
        if let title { out["title"] = title }
        if let caption { out["caption"] = caption }
        if let selected { out["selected"] = selected }
        if let select { out["select"] = select.json }
        if let reorder { out["reorder"] = reorder.json }
        if let insert { out["insert"] = insert.json }
        if !line.isEmpty { out["line"] = line }
        return out
    }
}

/// A field that shows what is saved and is changed in place (D113): no button, it runs your tool on Return or on leaving it, with what's typed under `key`.
public struct EditField {
    public enum Kind: String { case text, multiline, time, number }

    /// A chip that puts `value` at the caret.
    public struct Token {
        public var label: String
        public var value: String
        public var symbol: String?

        public init(_ label: String, value: String, symbol: String? = nil) {
            self.label = label
            self.value = value
            self.symbol = symbol
        }

        var json: [String: Any] {
            var out: [String: Any] = ["label": label, "value": value]
            if let symbol { out["symbol"] = symbol }
            return out
        }
    }

    public var id: String
    public var label: String
    public var detail: String?
    public var placeholder: String?
    public var value: String
    public var kind: Kind
    public var tokens: [Token]
    public var tool: String
    public var input: [String: Any]
    public var key: String

    public init(_ id: String, _ label: String, value: String, detail: String? = nil, placeholder: String? = nil, kind: Kind = .text, tokens: [Token] = [],
                tool: String, input: [String: Any] = [:], key: String = "text") {
        self.id = id
        self.label = label
        self.detail = detail
        self.placeholder = placeholder
        self.value = value
        self.kind = kind
        self.tokens = tokens
        self.tool = tool
        self.input = input
        self.key = key
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "field", "id": id, "label": label, "value": value, "kind": kind.rawValue, "tool": tool, "input": input, "key": key]
        if let detail { out["detail"] = detail }
        if let placeholder { out["placeholder"] = placeholder }
        if !tokens.isEmpty { out["tokens"] = tokens.map(\.json) }
        return out
    }
}

/// Several of a few options (D113): weekdays, tags. The tool gets the whole set, a list of values, under `key`.
public struct MultiChoice {
    public var label: String
    public var detail: String?
    public var options: [(String, String)]
    public var selected: [String]
    public var tool: String
    public var input: [String: Any]
    public var key: String

    public init(_ label: String, detail: String? = nil, options: [(String, String)], selected: [String], tool: String, input: [String: Any] = [:], key: String = "values") {
        self.label = label
        self.detail = detail
        self.options = options
        self.selected = selected
        self.tool = tool
        self.input = input
        self.key = key
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "choice", "multiple": true, "label": label, "selected": selected.first ?? "", "selected_all": selected, "tool": tool, "input": input, "key": key,
                                  "options": options.map { ["value": $0.0, "label": $0.1] }]
        if let detail { out["detail"] = detail }
        return out
    }
}
