import Foundation

/// A part that says itself: what the parts below are, and how a newer one can reach a page without a case of its own.
public protocol PagePart {
    var json: [String: Any] { get }
}

extension Section {
    /// Its title and parts in one card, standing in `row` beside the sections of the same name.
    public func inCard(row: String? = nil, weight: Double = 1, joined: Bool = false, accessories: [Block] = [], status: Tone? = nil) -> Section {
        var out = self
        out.card = !joined
        out.row = row
        out.weight = weight
        out.joined = joined
        out.accessories = accessories
        out.status = status
        return out
    }
}

/// A number on a card: its symbol, a name, the value large, and a bar of how full or a line of its past (`spark`, a chart's series on this page).
public struct Metric: PagePart {
    public enum Size: String { case large, small }

    public var label, value: String
    public var symbol, caption: String?
    public var tone: Tone
    public var tint: PagePair?
    public var fraction: Double?
    public var spark: (chart: String, series: String)?
    public var size: Size

    public init(_ label: String, _ value: String, symbol: String? = nil, tone: Tone = .neutral, tint: PagePair? = nil, caption: String? = nil, fraction: Double? = nil,
                spark: (chart: String, series: String)? = nil, size: Size = .large) {
        self.label = label
        self.value = value
        self.symbol = symbol
        self.tone = tone
        self.tint = tint
        self.caption = caption
        self.fraction = fraction
        self.spark = spark
        self.size = size
    }

    public var json: [String: Any] {
        var out: [String: Any] = ["type": "metric", "label": label, "value": value, "tone": tone.rawValue, "size": size.rawValue]
        if let symbol { out["symbol"] = symbol }
        if let tint { out["tint"] = tint.json }
        if let caption { out["caption"] = caption }
        if let fraction { out["fraction"] = fraction }
        if let spark { out["spark"] = ["chart": spark.chart, "series": spark.series] }
        return out
    }
}

/// One thing shown whole: its kind, title, words or picture, what's known of it, and what can be done with it. `empty`: nothing to show, these words instead.
public struct Preview: PagePart {
    public var kind, kindSymbol, title, text, image, color, footer, empty: String?
    public var code: Bool
    public var facts: [(String, String)]
    public var actions: [Action]

    public init(kind: String? = nil, kindSymbol: String? = nil, title: String? = nil, text: String? = nil, code: Bool = false, image: String? = nil, color: String? = nil,
                facts: [(String, String)] = [], footer: String? = nil, actions: [Action] = [], empty: String? = nil) {
        self.kind = kind
        self.kindSymbol = kindSymbol
        self.title = title
        self.text = text
        self.code = code
        self.image = image
        self.color = color
        self.facts = facts
        self.footer = footer
        self.actions = actions
        self.empty = empty
    }

    public var json: [String: Any] {
        Block.dropNil(["type": "preview", "kind": kind, "kind_symbol": kindSymbol, "title": title, "text": text, "code": code ? true : nil, "image": image, "color": color,
                       "facts": facts.map { ["label": $0.0, "value": $0.1] }, "footer": footer, "actions": actions.map(\.json), "empty": empty])
    }
}

/// Bars with a picture or a symbol beside each, or a chart with its own height and colours: what `.bars` and `.chart` say, and a little more.
public struct PicturedBar {
    public var bar: Bar
    public var picture: Picture?
    public var symbol: String?

    public init(_ bar: Bar, picture: Picture? = nil, symbol: String? = nil) {
        self.bar = bar
        self.picture = picture
        self.symbol = symbol
    }
}

private struct Raw: PagePart {
    var json: [String: Any]
}

extension Block {
    public static func metric(_ metric: Metric) -> Block { .part(metric) }
    public static func preview(_ preview: Preview) -> Block { .part(preview) }

    /// A smaller title inside a card, with a rule above it when it starts a new part.
    public static func heading(_ title: String, rule: Bool = false) -> Block { .part(Raw(json: ["type": "heading", "title": title, "rule": rule])) }

    /// Only the rule: what's above and below it are different things.
    public static var rule: Block { .part(Raw(json: ["type": "heading", "title": " ", "rule": true])) }

    /// Your heads-ups here rather than at the page's foot: `show` first, the rest behind `more`.
    public static func headsUps(show: [String] = [], more: String? = nil, less: String? = nil) -> Block {
        .part(Raw(json: dropNil(["type": "heads_ups", "show": show, "more": more, "less": less])))
    }

    /// Sidefolk's own controls for you (your palettes' shortcuts, what you need from macOS), here rather than on top.
    public static var hostControls: Block { .part(Raw(json: ["type": "host_controls"])) }

    /// A note with a symbol: `.band` on a soft band, `.plain` with nothing behind it, `.verdict` on a tile with strong words. `link`: a quiet button after its words.
    public enum NoteStyle: String { case band, plain, verdict }
    public static func note(_ text: String, tone: Tone = .neutral, symbol: String?, style: NoteStyle = .band, link: Action? = nil) -> Block {
        .part(Raw(json: dropNil(["type": "note", "text": text, "tone": tone.rawValue, "symbol": symbol, "style": style.rawValue, "link": link?.json])))
    }

    /// A question as a row across the width, with a chevron: it sends `ask`, as if typed in Ask.
    public static func askRow(_ label: String, _ ask: String, symbol: String? = nil) -> Block {
        .part(Raw(json: dropNil(["type": "ask", "label": label, "ask": ask, "row": true, "symbol": symbol])))
    }

    /// A choice with its label read aloud but not drawn, and `columns` of tiles to a row.
    public static func choosing(_ label: String, detail: String? = nil, style: PickerStyle, _ options: [Option], selected: String, tool: String, input: [String: Any] = [:],
                                key: String = "value", disabled: Bool = false, hideLabel: Bool = false, columns: Int? = nil) -> Block {
        .part(Raw(json: dropNil(["type": "choice", "style": style.rawValue, "label": label, "detail": detail, "selected": selected, "tool": tool, "input": input, "key": key,
                                 "disabled": disabled ? true : nil, "hide_label": hideLabel ? true : nil, "columns": columns, "options": options.map(\.json)])))
    }

    /// A choice whose pick goes into the page's state under `key` (D105), as `choosing` draws it.
    public static func going(_ label: String, style: PickerStyle, _ options: [Option], selected: String, key: String, also: [String: Any] = [:], hideLabel: Bool = true) -> Block {
        .part(Raw(json: dropNil(["type": "choice", "style": style.rawValue, "label": label, "selected": selected, "go": ["set": also], "key": key, "input": [:],
                                 "hide_label": hideLabel ? true : nil, "options": options.map(\.json)])))
    }

    /// A search box: as they type, its words go into the page's state under `key` (D105). `clear` says what clearing it is, read aloud. `also`: what else changes with them.
    public static func search(_ label: String, placeholder: String, clear: String, key: String, value: String?, also: [String: Any] = [:]) -> Block {
        .part(Raw(json: dropNil(["type": "field", "search": true, "live": true, "label": label, "placeholder": placeholder, "button": clear, "key": key, "value": value,
                                 "go": ["set": also], "input": [:]])))
    }

    /// Rows that scroll in their own height, one of them selected; `empty`: the words where there are none.
    public static func scrollingList(maxHeight: Double, empty: String, _ rows: [Row]) -> Block {
        .part(Raw(json: ["type": "list", "max_height": maxHeight, "empty": empty, "title": "", "items": rows.map(\.json)]))
    }

    public static func bars(_ title: String? = nil, caption: String? = nil, pictured items: [PicturedBar]) -> Block {
        .part(Raw(json: dropNil(["type": "bars", "title": title, "caption": caption, "items": items.map { item in
            dropNil(["label": item.bar.label, "value": item.bar.value, "fraction": item.bar.fraction, "tone": item.bar.tone.rawValue, "picture": item.picture?.json, "symbol": item.symbol])
        }])))
    }

    /// `.chart`, drawn `height` points tall in its own `colors`.
    public static func chart(id: String, _ title: String, unit: String? = nil, max: Double? = nil, caption: String? = nil, height: Double, colors: [PagePair], series: [Series]) -> Block {
        .part(Raw(json: dropNil(["type": "chart", "id": id, "title": title, "unit": unit, "max": max, "caption": caption, "height": height, "colors": colors.map(\.json),
                                 "series": series.map { dropNil(["key": $0.key, "label": $0.label, "value": $0.value, "display": $0.display]) }])))
    }
}
