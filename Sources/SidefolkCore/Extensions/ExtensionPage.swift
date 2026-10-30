import Foundation

/// What an extension's page shows (D62), read from its answer to `sidefolk/page.render`. Only these parts exist, and
/// Sidefolk draws each one itself: an extension says what is true, never how it looks. Every text is the author's,
/// so it is cleaned and clipped here and never reaches a model. Parts this version doesn't know are skipped, so an
/// extension written for a newer Sidefolk still shows what it can.
public struct ExtensionPage: Sendable, Hashable {
    public var summary: Summary?
    public var sections: [Section]

    public init(summary: Summary? = nil, sections: [Section] = []) {
        self.summary = summary
        self.sections = sections
    }

    public enum Tone: String, Sendable, Hashable, CaseIterable {
        case good, warn, bad, info, neutral
    }

    /// The page in one line: the verdict on top of the page, and the Today tile when the manifest asks for one.
    public struct Summary: Sendable, Hashable {
        public var title: String
        public var detail: String
        public var tone: Tone
        public var symbol: String?

        public init(title: String, detail: String = "", tone: Tone = .neutral, symbol: String? = nil) {
            self.title = title
            self.detail = detail
            self.tone = tone
            self.symbol = symbol
        }
    }

    public struct Section: Sendable, Hashable {
        public var title: String?
        public var blocks: [Block]

        public init(title: String? = nil, blocks: [Block]) {
            self.title = title
            self.blocks = blocks
        }
    }

    public enum Block: Sendable, Hashable {
        /// A ring filled to `fraction` (0–1) with the value written inside: "CPU 23%".
        case gauge(Gauge)
        /// A number with its name: "Uptime 3 days".
        case stat(Stat)
        /// Lines over time. The page only says the value now; Sidefolk keeps the past (ExtensionPageHistory).
        case chart(Chart)
        /// Labelled bars, largest first as given: "what's using the memory".
        case bars(Bars)
        /// Label and value pairs: "Chip  Apple M3 Pro".
        case facts(Facts)
        /// A sentence that explains, in plain words.
        case note(Note)
        /// A button that asks Sidefolk a question, as if typed in Ask: the answer goes through commands or the AI,
        /// and through Guard like anything typed there.
        case ask(Ask)
        /// A switch or a button that runs one of the extension's own tools as the person, through Guard (D63).
        case control(Control)
    }

    /// `switch`: on or off, and the tool gets `on` with the new state merged into `input`. `button`: the tool with `input`.
    public struct Control: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case toggle(on: Bool)
            case button(Style)
        }

        public enum Style: String, Sendable, Hashable { case primary, secondary, destructive }

        public var kind: Kind
        public var label: String
        public var detail: String?
        /// The tool's name in the extension (`keep_awake`), never another extension's.
        public var tool: String
        public var input: JSONValue
        public var symbol: String?

        /// What runs when it is clicked, or switched to `on`.
        public func input(switchedTo on: Bool? = nil) -> JSONValue {
            guard let on else { return input }
            return input.setting("on", .bool(on))
        }
    }

    public struct Gauge: Sendable, Hashable {
        public var label: String
        public var value: String
        public var fraction: Double
        public var tone: Tone
        public var caption: String?
    }

    public struct Stat: Sendable, Hashable {
        public var label: String
        public var value: String
        public var tone: Tone
        public var caption: String?
    }

    public struct Chart: Sendable, Hashable {
        /// Names the chart's history, so it survives the page changing around it.
        public var id: String
        public var title: String
        public var unit: String?
        /// The axis's top; nil scales to the data.
        public var max: Double?
        public var caption: String?
        public var series: [Series]
    }

    public struct Series: Sendable, Hashable {
        public var key: String
        public var label: String
        public var value: Double
        /// What the value reads as now: "23%", "1.2 MB/s".
        public var display: String?
    }

    public struct Bars: Sendable, Hashable {
        public var title: String
        public var caption: String?
        public var items: [Bar]
    }

    public struct Bar: Sendable, Hashable {
        public var label: String
        public var value: String
        public var fraction: Double
        public var tone: Tone
    }

    public struct Facts: Sendable, Hashable {
        public var title: String?
        public var items: [Fact]
    }

    public struct Fact: Sendable, Hashable {
        public var label: String
        public var value: String
    }

    public struct Note: Sendable, Hashable {
        public var text: String
        public var tone: Tone
    }

    public struct Ask: Sendable, Hashable {
        public var label: String
        public var ask: String
    }

    // MARK: Reading

    public static let maxBytes = 128 * 1024
    static let maxSections = 16
    static let maxBlocks = 24
    static let maxItems = 24
    static let maxSeries = 4

    /// Reads `{summary, sections}`. Throws only when it isn't a page at all; a bad part is left out.
    public static func parse(_ json: JSONValue) throws -> ExtensionPage {
        guard json.jsonString.utf8.count <= maxBytes else { throw UserFacingError("The page is larger than 128 KB.") }
        guard let object = json.objectValue, object["sections"]?.arrayValue != nil || object["summary"] != nil else {
            throw UserFacingError("That isn't a page.")
        }
        let sections = (object["sections"]?.arrayValue ?? []).prefix(maxSections).compactMap { s -> Section? in
            let blocks = (s["blocks"]?.arrayValue ?? []).prefix(maxBlocks).compactMap(block)
            return blocks.isEmpty ? nil : Section(title: text(s["title"], 60), blocks: blocks)
        }
        return ExtensionPage(summary: object["summary"].flatMap(summary), sections: sections)
    }

    static func summary(_ j: JSONValue) -> Summary? {
        guard let title = text(j["title"], 80) else { return nil }
        return Summary(title: title, detail: text(j["detail"], 160) ?? "", tone: tone(j["tone"]), symbol: symbol(j["symbol"]))
    }

    static func block(_ j: JSONValue) -> Block? {
        switch j["type"]?.stringValue {
        case "gauge":
            guard let label = text(j["label"], 30), let value = text(j["value"], 20) else { return nil }
            return .gauge(Gauge(label: label, value: value, fraction: fraction(j["fraction"]), tone: tone(j["tone"]), caption: text(j["caption"], 60)))
        case "stat":
            guard let label = text(j["label"], 40), let value = text(j["value"], 40) else { return nil }
            return .stat(Stat(label: label, value: value, tone: tone(j["tone"]), caption: text(j["caption"], 80)))
        case "chart":
            guard let id = j["id"]?.stringValue, id.range(of: #"^[a-z0-9_]{1,40}$"#, options: .regularExpression) != nil,
                  let title = text(j["title"], 60) else { return nil }
            let series = (j["series"]?.arrayValue ?? []).prefix(maxSeries).compactMap { s -> Series? in
                guard let key = s["key"]?.stringValue, key.range(of: #"^[a-z0-9_]{1,40}$"#, options: .regularExpression) != nil,
                      let value = s["value"]?.doubleValue, value.isFinite else { return nil }
                return Series(key: key, label: text(s["label"], 30) ?? key, value: value, display: text(s["display"], 20))
            }
            guard !series.isEmpty else { return nil }
            let max = j["max"]?.doubleValue.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return .chart(Chart(id: id, title: title, unit: text(j["unit"], 12), max: max, caption: text(j["caption"], 120), series: series))
        case "bars":
            guard let title = text(j["title"], 60) else { return nil }
            let items = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap { i -> Bar? in
                guard let label = text(i["label"], 60), let value = text(i["value"], 24) else { return nil }
                return Bar(label: label, value: value, fraction: fraction(i["fraction"]), tone: tone(i["tone"]))
            }
            return .bars(Bars(title: title, caption: text(j["caption"], 120), items: items))
        case "facts":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap { i -> Fact? in
                guard let label = text(i["label"], 40), let value = text(i["value"], 120) else { return nil }
                return Fact(label: label, value: value)
            }
            return items.isEmpty ? nil : .facts(Facts(title: text(j["title"], 60), items: items))
        case "note":
            return text(j["text"], 400).map { .note(Note(text: $0, tone: tone(j["tone"]))) }
        case "ask":
            guard let label = text(j["label"], 40), let ask = text(j["ask"], 200) else { return nil }
            return .ask(Ask(label: label, ask: ask))
        case "switch", "button":
            guard let label = text(j["label"], 60), let tool = j["tool"]?.stringValue,
                  tool.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil else { return nil }
            let input = j["input"]?.objectValue.map(JSONValue.object) ?? .object([:])
            guard input.jsonString.utf8.count <= 4096 else { return nil }
            let kind: Control.Kind = j["type"]?.stringValue == "switch" ? .toggle(on: j["on"]?.boolValue ?? false)
                : .button(j["style"]?.stringValue.flatMap(Control.Style.init(rawValue:)) ?? .secondary)
            return .control(Control(kind: kind, label: label, detail: text(j["detail"], 160), tool: tool, input: input, symbol: symbol(j["symbol"])))
        default:
            return nil
        }
    }

    static func text(_ j: JSONValue?, _ characters: Int) -> String? {
        guard let raw = j?.stringValue else { return nil }
        let line = ExtensionText.line(raw, characters: characters).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    static func tone(_ j: JSONValue?) -> Tone { j?.stringValue.flatMap(Tone.init(rawValue:)) ?? .neutral }

    static func fraction(_ j: JSONValue?) -> Double {
        guard let v = j?.doubleValue, v.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }

    static func symbol(_ j: JSONValue?) -> String? {
        guard let s = j?.stringValue, s.count <= 64, s.range(of: ManifestValidator.symbolPattern, options: .regularExpression) != nil else { return nil }
        return s
    }

    /// Every chart's series as `chart/key` and its value now, for the history.
    public var samples: [String: Double] {
        var out: [String: Double] = [:]
        for section in sections {
            for case .chart(let chart) in section.blocks {
                for s in chart.series { out["\(chart.id)/\(s.key)"] = s.value }
            }
        }
        return out
    }
}
