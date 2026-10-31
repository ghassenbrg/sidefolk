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

    public init(summary: Summary? = nil, sections: [Section] = []) {
        self.summary = summary
        self.sections = sections
    }

    var json: [String: Any] {
        var out: [String: Any] = ["sections": sections.filter { !$0.blocks.isEmpty }.map(\.json)]
        if let summary { out["summary"] = summary.json }
        return out
    }
}

public enum Tone: String {
    case good, warn, bad, info, neutral
}

/// The page in one line: on top of the page, and the Today tile when the manifest asks for one.
public struct Summary {
    public var title: String
    public var detail: String
    public var tone: Tone
    public var symbol: String?

    public init(_ title: String, detail: String = "", tone: Tone = .neutral, symbol: String? = nil) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "detail": detail, "tone": tone.rawValue]
        if let symbol { out["symbol"] = symbol }
        return out
    }
}

public struct Section {
    public var title: String?
    public var blocks: [Block]

    public init(_ title: String? = nil, _ blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }

    var json: [String: Any] {
        var out: [String: Any] = ["blocks": blocks.map(\.json)]
        if let title { out["title"] = title }
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
        }
    }

    private static func dropNil(_ values: [String: Any?]) -> [String: Any] { values.compactMapValues { $0 } }
}

public enum ButtonStyle: String {
    case primary, secondary, destructive
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
