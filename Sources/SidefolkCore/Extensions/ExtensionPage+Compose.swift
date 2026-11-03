import Foundation

/// What lets a page be composed like an app's screen rather than listed: sections as cards, side by side or joined; a number with its symbol and a line
/// of its past; a heading inside a card; a pane showing one thing whole; the host's own parts placed where they belong. None of it knows what a page is about.
extension ExtensionPage {
    /// A number on a card: its symbol, a name, the value large, and under it a bar of how full, or a line of its past.
    public struct Metric: Sendable, Hashable {
        public enum Size: String, Sendable, Hashable { case large, small }

        public var label: String
        public var value: String
        public var symbol: String?
        public var tone: Tone
        /// The symbol's and the bar's colour, where a tone would say something it doesn't mean.
        public var tint: PageDress.Pair?
        public var caption: String?
        /// A bar of how full, 0–1.
        public var fraction: Double?
        /// A line of its past: one of the page's charts' series, whose history Sidefolk keeps.
        public var spark: Spark?
        public var size: Size

        public struct Spark: Sendable, Hashable {
            public var chart: String
            public var series: String
        }
    }

    /// A smaller title inside a card, with a rule above it when it starts a new part.
    public struct Heading: Sendable, Hashable {
        public var title: String
        public var rule: Bool
    }

    /// The extension's heads-ups here rather than at the page's foot. `show` are the watchers shown first; `more` opens the rest, in the extension's words.
    public struct HeadsUpsPart: Sendable, Hashable {
        public var show: [String]
        public var more: String?
        public var less: String?
    }

    /// One thing shown whole, as it would be used: its kind, title, words or picture, what's known about it, and what can be done with it.
    public struct Preview: Sendable, Hashable {
        public var kind: String?
        public var kindSymbol: String?
        public var title: String?
        public var text: String?
        /// Its words in a fixed-width face, kept as they are.
        public var code = false
        /// A picture in the extension's data folder.
        public var image: String?
        /// `#RRGGBB`, shown as a large swatch.
        public var color: String?
        public var facts: [Fact]
        public var footer: String?
        public var actions: [Control]
        /// Nothing to show: these words in the middle of the pane.
        public var empty: String?
    }

    /// A ring around a value, for how much of something is left. Only where the extension knows how much that is.
    public struct Ring: Sendable, Hashable {
        public var fraction: Double
        public var value: String
        public var caption: String?
    }

    /// A short state beside a hero's title: "Screen on".
    public struct Chip: Sendable, Hashable {
        public var label: String
        public var symbol: String?
        public var tone: Tone
    }

    /// How a note stands on the page.
    public enum NoteStyle: String, Sendable, Hashable {
        /// On a soft band in its tone: the first way.
        case band
        /// Words and a symbol with nothing behind them: a footnote.
        case plain
        /// Its symbol on a tile, its words strong: the page's verdict.
        case verdict
    }

    /// Reads what this file adds, or hands on to the parts before it.
    static func composedBlock(_ j: JSONValue) -> Block? {
        switch j["type"]?.stringValue {
        case "metric":
            guard let label = text(j["label"], 40), let value = text(j["value"], 40) else { return nil }
            var spark: Metric.Spark?
            if let chart = j["spark"]?["chart"]?.stringValue, let series = j["spark"]?["series"]?.stringValue { spark = Metric.Spark(chart: chart, series: series) }
            return .metric(Metric(label: label, value: value, symbol: symbol(j["symbol"]), tone: tone(j["tone"]), tint: PageDress.Pair.parse(j["tint"]), caption: text(j["caption"], 80),
                                  fraction: j["fraction"] == nil ? nil : fraction(j["fraction"]), spark: spark, size: j["size"]?.stringValue.flatMap(Metric.Size.init(rawValue:)) ?? .large))
        case "heading":
            return text(j["title"], 60).map { .heading(Heading(title: $0, rule: j["rule"]?.boolValue ?? false)) }
        case "heads_ups":
            return .headsUps(HeadsUpsPart(show: (j["show"]?.arrayValue ?? []).prefix(8).compactMap(\.stringValue), more: text(j["more"], 40), less: text(j["less"], 40)))
        case "host_controls":
            return .hostControls
        case "preview":
            let facts = (j["facts"]?.arrayValue ?? []).prefix(8).compactMap { f -> Fact? in
                guard let label = text(f["label"], 40), let value = text(f["value"], 120) else { return nil }
                return Fact(label: label, value: value)
            }
            return .preview(Preview(kind: text(j["kind"], 30), kindSymbol: symbol(j["kind_symbol"]), title: text(j["title"], 120),
                                    text: j["text"]?.stringValue.map { ExtensionText.untrusted($0, bytes: 32_000) }, code: j["code"]?.boolValue ?? false,
                                    image: dataFile(j["image"]), color: color(j["color"]), facts: facts, footer: text(j["footer"], 120),
                                    actions: (j["actions"]?.arrayValue ?? []).prefix(5).compactMap { button($0, characters: 30) }, empty: text(j["empty"], 160)))
        default:
            return nil
        }
    }

    /// What clicking a whole row does, which the up and down keys also fire, with no words of its own on screen: only a move around the page, never a tool or anything that opens or copies (D105).
    static func rowPress(_ j: JSONValue?) -> Control? {
        guard let j, let press = button(j, characters: 120), case .go? = press.act else { return nil }
        return press
    }

    static func ring(_ j: JSONValue?) -> Ring? {
        guard let j, let value = text(j["value"], 24) else { return nil }
        return Ring(fraction: fraction(j["fraction"]), value: value, caption: text(j["caption"], 24))
    }

    static func chips(_ j: JSONValue?) -> [Chip] {
        (j?.arrayValue ?? []).prefix(4).compactMap { c in text(c["label"], 40).map { Chip(label: $0, symbol: symbol(c["symbol"]), tone: tone(c["tone"])) } }
    }
}

extension ExtensionPage.Block {
    /// Which input this is, whatever it holds now: the same field or list stays the same part as the page changes around it, and another field isn't taken for it.
    public var inputIdentity: String {
        switch self {
        case .field(let f): "field:\(f.label):\(f.key):\(f.id ?? "")"
        case .choice(let c): "choice:\(c.label):\(c.key):\(c.style.rawValue)"
        case .list(let l): "list:\(l.title ?? "")"
        default: kind
        }
    }
}

extension ExtensionPage.Section {
    /// How a section takes part in a row, read from its JSON: its card, the row it shares, its share of that row, and a control at its title's end.
    mutating func compose(from s: JSONValue) {
        card = s["card"]?.boolValue ?? false
        row = s["row"]?.stringValue.flatMap { $0.range(of: #"^[a-z0-9_]{1,24}$"#, options: .regularExpression) != nil ? $0 : nil }
        weight = s["weight"]?.doubleValue.flatMap { $0.isFinite && $0 > 0 ? Swift.min(Swift.max($0, 1), 100) : nil } ?? 1
        joined = s["joined"]?.boolValue ?? false
        pinLast = s["pin_last"]?.boolValue ?? false
        guard title != nil else { return }
        status = s["status"]?.stringValue.flatMap(ExtensionPage.Tone.init(rawValue:))
        accessories = (s["accessories"]?.arrayValue ?? []).prefix(3).compactMap(ExtensionPage.block).filter {
            switch $0 {
            case .choice, .control: true
            default: false
            }
        }
    }

    /// Nothing else on the page may stand beside it.
    var standsAlone: Bool { card || row != nil }
}

extension ExtensionPage {
    /// Runs of sections in the same `row`, in reading order: what's drawn side by side.
    public static func sameRow(_ a: Section, _ b: Section) -> Bool { a.row != nil && a.row == b.row }

    /// The page draws its own head first, so what Sidefolk adds goes under it.
    public var leadsWithBar: Bool {
        guard bare, case .bar? = sections.first?.blocks.first else { return false }
        return true
    }

    /// Made of cards and rows, so its parts stand closer than a list of sections.
    public var isComposed: Bool { sections.contains(where: \.standsAlone) }

    /// The host's heads-ups are placed on this page, so they aren't also drawn at its foot.
    public var placesHeadsUps: Bool { contains { if case .headsUps = $0 { true } else { false } } }

    /// The host's own controls are placed on this page, so they aren't also drawn on top.
    /// One in a fold doesn't count: what the extension needs from macOS always shows.
    public var placesHostControls: Bool {
        sections.contains { section in section.collapsed == nil && section.blocks.contains { if case .hostControls = $0 { true } else { false } } }
    }

    private func contains(_ test: (Block) -> Bool) -> Bool {
        sections.contains { $0.blocks.contains(where: test) }
    }
}
