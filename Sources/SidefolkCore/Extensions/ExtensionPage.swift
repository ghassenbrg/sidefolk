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
        /// The extension's main switch or button (D67), shown wherever the summary is: on top of the page, on its Today
        /// tile and beside its row in Home's sidebar, so an on/off feature is one click from where people are.
        public var control: Control?

        public init(title: String, detail: String = "", tone: Tone = .neutral, symbol: String? = nil, control: Control? = nil) {
            self.title = title
            self.detail = detail
            self.tone = tone
            self.symbol = symbol
            self.control = control
        }
    }

    public struct Section: Sendable, Hashable {
        /// Where a section goes in a wide window (D74): with the page's main sections, or in a column beside them at
        /// the start edge (a list of devices or accounts to pick from). A narrow window keeps the page's order.
        public enum Place: String, Sendable, Hashable { case main, side }

        public var title: String?
        public var blocks: [Block]
        public var place: Place
        /// Folded under its title until the person opens it (advanced settings, connection details); nil is always open.
        /// Needs a title to fold under.
        public var collapsed: Bool?

        public init(title: String? = nil, blocks: [Block], place: Place = .main, collapsed: Bool? = nil) {
            self.title = title
            self.blocks = blocks
            self.place = place
            self.collapsed = collapsed
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
        /// One of a few options; picking one runs the extension's tool with the option's `value`, through Guard.
        case choice(Choice)
        /// A text field and a button; the tool gets what was typed, through Guard.
        case field(Field)
        /// Rows with a picture, a swatch or a symbol, each with an optional button.
        case list(List)
        /// What the page is about right now, large, with its main actions (D74): "Ready to share", a pairing code to
        /// compare, "Sharing to the TV" and its live numbers. It leads the page in place of the summary.
        case hero(Hero)
        /// Where a playing video or song is, and its play, pause and skip buttons (D74).
        case transport(Transport)
    }

    /// A small label beside an option: "Paired", "New", "Off".
    public struct Badge: Sendable, Hashable {
        public var text: String
        public var tone: Tone
    }

    public struct Hero: Sendable, Hashable {
        /// A few words above the title: the state ("Ready", "Verify TV", "Sharing · live").
        public var eyebrow: String?
        public var title: String
        public var detail: String?
        public var tone: Tone
        public var symbol: String?
        /// A short code to compare, drawn very large: a pairing code, a PIN.
        public var code: String?
        /// A picture in the extension's data folder (`ExtensionDataFile`): what is being shared, a cover.
        public var image: String?
        /// Something is under way: a spinner beside the eyebrow.
        public var busy: Bool
        /// Up to four live numbers under the title: "29 fps", "18 ms".
        public var facts: [Fact]
        /// Up to three buttons; Sidefolk draws them large, the primary one filled.
        public var actions: [Control]
    }

    public struct Transport: Sendable, Hashable {
        public enum State: String, Sendable, Hashable { case playing, paused, buffering, stopped }

        public var title: String?
        public var detail: String?
        /// Seconds, as Sidefolk writes the times under the bar.
        public var position: Double?
        public var duration: Double?
        public var state: State
        /// Up to five buttons, each with a symbol; the primary one (play or pause) is drawn larger, in the middle.
        public var buttons: [Control]
    }

    public struct Choice: Sendable, Hashable {
        /// How the options are drawn (D74): `segmented` side by side (a menu above four), `cards` as equal cards with a
        /// line each (presets), `tiles` as pictures in a grid (displays, windows), `rows` as a list with a badge each
        /// (devices, accounts). An older Sidefolk draws them all as `segmented`.
        public enum Style: String, Sendable, Hashable { case segmented, cards, tiles, rows }

        public struct Option: Sendable, Hashable {
            public var value: String
            public var label: String
            public var detail: String?
            /// A picture in the extension's data folder, for `tiles` and `rows`.
            public var image: String?
            public var symbol: String?
            public var badge: Badge?
            /// A small button of its own on a tile or row ("Forget").
            public var action: Control?
        }

        public var label: String
        public var detail: String?
        public var options: [Option]
        public var selected: String
        public var tool: String
        public var input: JSONValue
        public var style: Style = .segmented
        /// The name the picked option's value goes under in `input`.
        public var key: String = "value"
        /// Shown but not changeable now (while sharing, say).
        public var disabled = false

        /// What runs when `value` is picked.
        public func input(picking value: String) -> JSONValue { input.setting(key, .string(value)) }
    }

    public struct Field: Sendable, Hashable {
        public var label: String
        public var detail: String?
        public var placeholder: String?
        public var button: String
        public var tool: String
        public var input: JSONValue
        /// The name the typed text goes under in `input`.
        public var key: String

        /// What runs for `text`, trimmed and at most 500 characters.
        public func input(typing text: String) -> JSONValue {
            input.setting(key, .string(String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))))
        }
    }

    public struct List: Sendable, Hashable {
        public var title: String?
        public var caption: String?
        public var rows: [Row]
    }

    public struct Row: Sendable, Hashable {
        public var title: String
        public var detail: String?
        /// A picture in the extension's data folder (`ExtensionDataFile`).
        public var image: String?
        /// `#RRGGBB`.
        public var color: String?
        public var symbol: String?
        public var button: Control?
    }

    /// `switch`: on or off, and the tool gets `on` with the new state merged into `input`. `button`: the tool with `input`.
    public struct Control: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case toggle(on: Bool)
            case button(Style)
        }

        /// `plain` (D74) is a quiet text button for what's rarely needed ("Look again", "Forget"); an older Sidefolk
        /// draws it as `secondary`.
        public enum Style: String, Sendable, Hashable { case primary, secondary, destructive, plain }

        public var kind: Kind
        public var label: String
        public var detail: String?
        /// The tool's name in the extension (`keep_awake`), never another extension's.
        public var tool: String
        public var input: JSONValue
        public var symbol: String?
        /// Shown dimmed, `detail` saying why: a step that can't be taken yet ("Choose a TV first").
        public var disabled = false

        public var style: Style? { if case .button(let s) = kind { s } else { nil } }

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

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
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
            let title = text(s["title"], 60)
            return blocks.isEmpty ? nil : Section(title: title, blocks: blocks, place: s["place"]?.stringValue.flatMap(Section.Place.init) ?? .main,
                                                  collapsed: title == nil ? nil : s["collapsed"]?.boolValue)
        }
        var page = ExtensionPage(summary: object["summary"].flatMap(summary), sections: sections)
        page.keepOnePrimary()
        return page
    }

    /// The hero leading the page, when its first section starts with one: drawn instead of the summary banner.
    public var hero: Hero? {
        if case .hero(let h)? = sections.first?.blocks.first { return h }
        return nil
    }

    /// One primary action a page (D74): the first in reading order stays filled, any later one is drawn as secondary,
    /// so "what do I do here" has one answer. The summary's control counts first when the banner shows it.
    mutating func keepOnePrimary() {
        var seen = false
        func keep(_ c: inout Control) {
            guard c.style == .primary else { return }
            if seen { c.kind = .button(.secondary) }
            seen = true
        }
        if hero == nil, var control = summary?.control {
            keep(&control)
            summary?.control = control
        }
        for s in sections.indices {
            for b in sections[s].blocks.indices {
                switch sections[s].blocks[b] {
                case .control(var c): keep(&c); sections[s].blocks[b] = .control(c)
                case .hero(var h): for i in h.actions.indices { keep(&h.actions[i]) }; sections[s].blocks[b] = .hero(h)
                case .transport(var t): for i in t.buttons.indices { keep(&t.buttons[i]) }; sections[s].blocks[b] = .transport(t)
                default: break
                }
            }
        }
    }

    static func summary(_ j: JSONValue) -> Summary? {
        guard let title = text(j["title"], 80) else { return nil }
        var control: Control?
        if let c = j["control"], case .control(let parsed)? = block(c) { control = parsed }
        return Summary(title: title, detail: text(j["detail"], 160) ?? "", tone: tone(j["tone"]), symbol: symbol(j["symbol"]), control: control)
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
        case "switch":
            guard let label = text(j["label"], 60), let tool = toolName(j["tool"]), let input = smallInput(j["input"]) else { return nil }
            return .control(Control(kind: .toggle(on: j["on"]?.boolValue ?? false), label: label, detail: text(j["detail"], 160), tool: tool,
                                    input: input, symbol: symbol(j["symbol"])))
        case "button":
            return button(j, characters: 60).map { .control($0) }
        case "choice":
            guard let label = text(j["label"], 60), let tool = toolName(j["tool"]), let input = smallInput(j["input"]) else { return nil }
            let style = j["style"]?.stringValue.flatMap(Choice.Style.init(rawValue:)) ?? .segmented
            // Pictures and rows hold a list of things (windows, devices); side by side, a few options read best.
            let many = style == .tiles || style == .rows
            let options = (j["options"]?.arrayValue ?? []).prefix(many ? maxItems : (style == .cards ? 6 : 8)).compactMap { o -> Choice.Option? in
                guard let value = o["value"]?.stringValue, (1...40).contains(value.count), let label = text(o["label"], many ? 60 : 30) else { return nil }
                var badge: Badge?
                if let b = o["badge"], let t = text(b["text"], 20) { badge = Badge(text: t, tone: tone(b["tone"])) }
                return Choice.Option(value: value, label: label, detail: text(o["detail"], 60), image: many ? dataFile(o["image"]) : nil,
                                     symbol: symbol(o["symbol"]), badge: badge, action: many ? o["action"].flatMap { button($0, characters: 24) } : nil)
            }
            guard options.count >= (many ? 1 : 2) else { return nil }
            let key = j["key"]?.stringValue ?? "value"
            guard key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, key != "on" else { return nil }
            let selected = j["selected"]?.stringValue ?? ""
            return .choice(Choice(label: label, detail: text(j["detail"], 160), options: options,
                                  selected: options.contains { $0.value == selected } ? selected : "", tool: tool, input: input,
                                  style: style, key: key, disabled: j["disabled"]?.boolValue ?? false))
        case "hero":
            guard let title = text(j["title"], 80) else { return nil }
            let facts = (j["facts"]?.arrayValue ?? []).prefix(4).compactMap { f -> Fact? in
                guard let label = text(f["label"], 24), let value = text(f["value"], 30) else { return nil }
                return Fact(label: label, value: value)
            }
            let code = j["code"]?.stringValue.flatMap { $0.range(of: #"^[0-9A-Z][0-9A-Z \-]{0,11}$"#, options: .regularExpression) != nil ? $0 : nil }
            return .hero(Hero(eyebrow: text(j["eyebrow"], 30), title: title, detail: text(j["detail"], 300), tone: tone(j["tone"]),
                              symbol: symbol(j["symbol"]), code: code, image: dataFile(j["image"]), busy: j["busy"]?.boolValue ?? false,
                              facts: facts, actions: (j["actions"]?.arrayValue ?? []).prefix(3).compactMap { button($0, characters: 30) }))
        case "transport":
            // Every button is drawn as its symbol, its label read aloud and shown on hover.
            let buttons = (j["buttons"]?.arrayValue ?? []).prefix(5).compactMap { button($0, characters: 30) }.filter { $0.symbol != nil }
            guard !buttons.isEmpty else { return nil }
            func seconds(_ v: JSONValue?) -> Double? { v?.doubleValue.flatMap { $0.isFinite && $0 >= 0 && $0 < 1_000_000 ? $0 : nil } }
            return .transport(Transport(title: text(j["title"], 80), detail: text(j["detail"], 120), position: seconds(j["position"]),
                                        duration: seconds(j["duration"]).flatMap { $0 > 0 ? $0 : nil },
                                        state: j["state"]?.stringValue.flatMap(Transport.State.init) ?? .stopped, buttons: buttons))
        case "field":
            guard let label = text(j["label"], 60), let button = text(j["button"], 24), let tool = toolName(j["tool"]),
                  let input = smallInput(j["input"]) else { return nil }
            let key = j["key"]?.stringValue ?? "text"
            guard key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, key != "on" else { return nil }
            return .field(Field(label: label, detail: text(j["detail"], 160), placeholder: text(j["placeholder"], 60), button: button, tool: tool,
                                input: input, key: key))
        case "list":
            let rows = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap { r -> Row? in
                guard let title = text(r["title"], 120) else { return nil }
                var button: Control?
                if let b = r["button"], let label = text(b["label"], 24), let tool = toolName(b["tool"]), let input = smallInput(b["input"]) {
                    button = Control(kind: .button(.secondary), label: label, tool: tool, input: input, symbol: symbol(b["symbol"]))
                }
                return Row(title: title, detail: text(r["detail"], 160), image: dataFile(r["image"]), color: color(r["color"]),
                           symbol: symbol(r["symbol"]), button: button)
            }
            guard !rows.isEmpty || j["title"] != nil else { return nil }
            return .list(List(title: text(j["title"], 60), caption: text(j["caption"], 120), rows: rows))
        default:
            return nil
        }
    }

    /// A button: its label (at most `characters`), the extension's own tool and a small input, a style, a symbol, and
    /// whether it can be clicked now.
    static func button(_ j: JSONValue, characters: Int) -> Control? {
        guard let label = text(j["label"], characters), let tool = toolName(j["tool"]), let input = smallInput(j["input"]) else { return nil }
        return Control(kind: .button(j["style"]?.stringValue.flatMap(Control.Style.init(rawValue:)) ?? .secondary), label: label,
                       detail: text(j["detail"], 160), tool: tool, input: input, symbol: symbol(j["symbol"]), disabled: j["disabled"]?.boolValue ?? false)
    }

    /// The extension's own tool's name, never another's (`ext.other.tool`).
    static func toolName(_ j: JSONValue?) -> String? {
        guard let tool = j?.stringValue, tool.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil else { return nil }
        return tool
    }

    static func smallInput(_ j: JSONValue?) -> JSONValue? {
        let input = j?.objectValue.map(JSONValue.object) ?? .object([:])
        return input.jsonString.utf8.count <= 4096 ? input : nil
    }

    static func color(_ j: JSONValue?) -> String? {
        guard let c = j?.stringValue, c.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else { return nil }
        return c
    }

    static func dataFile(_ j: JSONValue?) -> String? {
        guard let name = j?.stringValue, ExtensionDataFile.isValidName(name) else { return nil }
        return name
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
