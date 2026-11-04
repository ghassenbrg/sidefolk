import Foundation

/// What an extension's page shows (D62), read from its answer to `sidefolk/page.render`. Only these parts exist, and
/// Sidefolk draws each one itself: an extension says what is true, never how it looks. Every text is the author's,
/// so it is cleaned and clipped here and never reaches a model. Parts this version doesn't know are skipped, so an
/// extension written for a newer Sidefolk still shows what it can.
public struct ExtensionPage: Sendable, Hashable {
    public var summary: Summary?
    public var sections: [Section]
    /// The label of Back, drawn while the page has somewhere to go back to (D105).
    public var back: String?
    /// The page draws its own head: no title row or summary on it (D105). Its summary still reaches Today and the sidebar.
    public var bare = false
    /// The page lays itself out to the column's very edges, its margins its own (D109). Only a bare page may.
    public var bleed = false
    public var dress: PageDress?
    /// What its Today tile draws instead of its summary (D109). A picture of the summary: no areas, a click opens the page.
    public var tile: SurfaceScene?
    public static let tileSize = SceneSize(width: 720, height: 300)
    /// How wide its column may grow (D108).
    public var maxWidth: Double?
    /// Its own colours, one or two, deep enough to hold white: the first fills its main button and switches, the last marks what's selected. The rest stays the theme's (D126).
    public var accent: [String] = []
    /// The page takes the window (D126): its columns scroll on their own, and Home's sidebar folds while it shows. Only a bare page may.
    public var workspace = false
    /// The person's own companion looks in at the page's corner (D126). Sidefolk places it; the extension never reads it.
    public var companion = false
    /// Keys that work while this page is showing (`ExtensionPage.Shortcut`).
    public var shortcuts: [Shortcut] = []
    /// Its palettes' row (their shortcut and where they open) stays off this page, drawn by a `host_controls` part on another state of it. What it needs from macOS always shows.
    public var quietHost = false

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
        /// `trailing`, on a workspace page (D126): a column on the far side from `side`. On any other page it's with the main ones.
        public enum Place: String, Sendable, Hashable { case main, side, bottom, trailing }

        public var title: String?
        public var detail: String?
        public var blocks: [Block]
        public var place: Place
        /// Folded under its title until the person opens it (advanced settings, connection details); nil is always open.
        /// Needs a title to fold under.
        public var collapsed: Bool?
        /// A small picture beside its title (D100): the person's companion beside "Play against …", say.
        public var picture: PagePicture?
        /// Its title on a band tinted this colour, beside its picture or a symbol (D101).
        public var banner: Banner?
        /// Across the page, however little it holds, rather than beside its neighbours (D101).
        public var wide = false
        /// Its title and all its parts in one card, the parts flat inside it.
        public var card = false
        /// Sections in a row of the same name stand side by side, sharing the width by `weight`, and stack when the column is narrow.
        public var row: String?
        public var weight = 1.0
        /// The row's sections share one card, with a line between them.
        public var joined = false
        /// Its last part stands at the foot of its card.
        public var pinLast = false
        /// Choices or buttons at the end of its title, up to three.
        public var accessories: [Block] = []
        /// A dot in this tone before its title: the section's title says a state.
        public var status: Tone?

        public struct Banner: Sendable, Hashable {
            public var tint: String
            public var symbol: String?
        }

        public init(title: String? = nil, blocks: [Block], place: Place = .main, collapsed: Bool? = nil, detail: String? = nil, picture: PagePicture? = nil) {
            self.picture = picture
            self.title = title
            self.detail = detail
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
        /// Numbers side by side in one strip (D100): "Wins 12", "Best streak 4".
        case stats(StatStrip)
        /// Cards in a grid, each with a picture from the pack, words, a badge and buttons (D100).
        case cards(CardGrid)
        /// Parts of the page one at a time, under tabs Sidefolk switches without asking the program (D100).
        case tabs(Tabs)
        /// Achievements, earned or on their way (D100).
        case badges(BadgeList)
        /// The last things that happened, newest first, with when (D100).
        case recent(RecentList)
        /// The extension's own settings, as the host keeps and draws them (D100).
        case settings(SettingsRows)
        /// A scene drawn inline, so a look no part offers stays entirely the extension's (D100).
        case scene(PageScene)
        /// Rows of controls under named columns (D108): one line per thing that has several settings. Narrow, each row stacks.
        case table(PageTable)
        /// Things in order on a line, with their states (D113).
        case steps(Steps)
        /// A tree of cards that arranges itself (D125).
        case tree(Tree)
        /// A compact head for a page that draws its own: its title, state, one sentence and actions (D126).
        case bar(PageHead)
        /// A column of places to go (D126).
        case nav(Nav)
        /// What a person will receive, drawn as it will arrive (D126).
        case notice(Notice)
        /// A row of recent results, each a mark and its word (D126).
        case ticks(Ticks)
        /// A number on a card, with its symbol and a bar or a line of its past.
        case metric(Metric)
        /// A smaller title inside a card.
        case heading(Heading)
        /// The extension's heads-ups, placed here rather than at the page's foot.
        case headsUps(HeadsUpsPart)
        /// Sidefolk's own controls for this extension (its palettes' shortcuts, what it needs from macOS), placed here rather than on top.
        case hostControls
        /// One thing shown whole.
        case preview(Preview)
    }

    /// A small label beside an option: "Paired", "New", "Off".
    public struct Badge: Sendable, Hashable {
        public var text: String
        public var tone: Tone

        public init(text: String, tone: Tone) {
            self.text = text
            self.tone = tone
        }
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
        /// A picture behind it at its trailing end, from the pack, in place of the plain card (D100).
        public var scene: PagePicture?
        /// A figure standing at its trailing end, with `says` beside it in a bubble inside this page (D100).
        public var figure: PagePicture?
        public var says: String?
        /// `#RRGGBB`, one or two: the symbol's tile as a gradient, its symbol in white (D101).
        public var tile: [String] = []
        /// `#RRGGBB`, one or two: a soft wash over the whole card, top to bottom.
        public var wash: [String] = []
        /// How much is left, around a value, in the symbol's place.
        public var ring: Ring?
        /// Short states under the title.
        public var chips: [Chip] = []
        /// Drawn as a plain card of the page's, its tone in its words and marks only.
        public var plain = false
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
        /// `bar` is segments across the whole width, the pick filled and each with its symbol; `menu` a full-width menu under its label; `pills` small rounded tabs.
        public enum Style: String, Sendable, Hashable { case segmented, cards, tiles, rows, bar, menu, pills }

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
        /// The name the picked option's value goes under in `input`, or in the page's state with `go`.
        public var key: String = "value"
        /// Shown but not changeable now (while sharing, say).
        public var disabled = false
        /// Picking changes the page's state instead of running a tool (D105).
        public var go: PageGo?
        /// Several may be on; the tool gets the set, a list of values, under `key` (D113).
        public var multiple = false
        public var selectedAll: [String] = []
        /// Its label is read aloud but not drawn: the section's title already says it.
        public var hideLabel = false
        /// Tiles to a row, where the pictures should be large: 1–4.
        public var columns: Int?

        /// What a pick does to the page's state, with `go`.
        public func go(picking value: String) -> PageGo? { go.map { var g = $0; g.set[key] = .string(value); return g } }

        /// What runs when `value` is picked.
        public func input(picking value: String) -> JSONValue { input.setting(key, .string(value)) }

        /// What runs for a set of options, in their order.
        public func input(pickingAll values: [String]) -> JSONValue {
            input.setting(key, .array(options.map(\.value).filter(values.contains).map { .string($0) }))
        }
    }

    public struct Field: Sendable, Hashable {
        /// What a live field's state says isn't what it is: the part stays the same part as it follows the typing, so it keeps the keyboard (D105).
        public static func == (a: Field, b: Field) -> Bool {
            a.label == b.label && a.detail == b.detail && a.placeholder == b.placeholder && a.button == b.button && a.tool == b.tool
                && a.input == b.input && a.key == b.key && a.go == b.go && a.live == b.live
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(label)
            hasher.combine(detail)
            hasher.combine(placeholder)
            hasher.combine(button)
            hasher.combine(tool)
            hasher.combine(key)
            hasher.combine(live)
        }

        public var label: String
        public var detail: String?
        public var placeholder: String?
        public var button: String
        public var tool: String
        public var input: JSONValue
        /// The name the typed text goes under in `input`, or in the page's state with `go`.
        public var key: String
        /// Submitting changes the page's state instead of running a tool (D105).
        public var go: PageGo?
        /// With `go`: as they type, a moment after they stop. It starts with `value`, what the state holds.
        public var live = false
        public var value: String?
        /// Set: it shows `value` and is changed in place, with no button (D113). Its own name keeps what's typed apart from the next field's.
        public var id: String?
        public var kind: Kind = .text
        /// A search box: a magnifying glass, no label or button, and a way to clear it.
        public var search = false
        /// Chips that put a value at the caret.
        public var tokens: [Token] = []

        public enum Kind: String, Sendable, Hashable { case text, multiline, time, number }

        public struct Token: Sendable, Hashable {
            public var label: String
            public var value: String
            public var symbol: String?
            /// The heading it's listed under.
            public var group: String?
        }

        /// How long what's typed may be: edited in place, it may be a whole prompt.
        public static let longestEdit = 32_000

        /// What the page's state gets for `text`, with `go`.
        public func go(typing text: String) -> PageGo? {
            go.map { var g = $0; g.set[key] = .string(String(text.prefix(500))); return g }
        }

        /// What runs for `text`, trimmed and at most 500 characters.
        public func input(typing text: String) -> JSONValue {
            input.setting(key, .string(String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(id == nil ? 500 : Self.longestEdit))))
        }
    }

    public struct List: Sendable, Hashable {
        public var title: String?
        public var caption: String?
        public var rows: [Row]
        /// The rows scroll inside this height, rather than the page growing with them.
        public var maxHeight: Double?
        /// Words where there are no rows.
        public var empty: String?
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
        /// What clicking anywhere on the row does. Arrow keys move through a list's rows that have one.
        public var press: Control?
        public var selected = false
        /// A small symbol at its end, in the page's selected colour: "pinned".
        public var mark: String?
        /// What its mark means, read aloud.
        public var markLabel: String?
    }

    /// `switch`: on or off, and the tool gets `on` with the new state merged into `input`. `button`: the tool with `input`.
    public struct Control: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case toggle(on: Bool)
            case button(Style)
        }

        /// `plain` (D74) is a quiet text button for what's rarely needed ("Look again", "Forget"); an older Sidefolk
        /// draws it as `secondary`.
        /// `accent` is filled like the primary, for what stands out where it is (the one card left waiting), without being what the page is for.
        public enum Style: String, Sendable, Hashable { case primary, secondary, destructive, plain, accent }

        public var kind: Kind
        public var label: String
        public var detail: String?
        /// The tool's name in the extension (`set_timer`), never another extension's.
        public var tool: String
        public var input: JSONValue
        public var symbol: String?
        /// Shown dimmed, `detail` saying why: a step that can't be taken yet ("Choose a TV first").
        public var disabled = false
        /// Drawn as its symbol in a filled circle, its label read aloud and on hover (D101).
        public var round = false
        /// What it does instead of running `tool` (D105).
        public var act: PageAct?
        /// A switch with `go`: the name its new state goes under in the page's state.
        public var key: String?
        /// Across the whole width of what holds it.
        public var fill = false
        /// Drawn as its symbol in a framed square, its label read aloud and on hover.
        public var iconOnly = false

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
        /// How tall it is drawn, 100–360 points.
        public var height: Double?
        /// Its lines' colours, in order, where the theme's wouldn't belong.
        public var colors: [PageDress.Pair] = []
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
        /// Beside its label.
        public var picture: PagePicture?
        public var symbol: String?
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
        public var symbol: String?
        public var style = NoteStyle.band
        /// A quiet button at the end of its words.
        public var link: Control?

        public init(text: String, tone: Tone) {
            self.text = text
            self.tone = tone
        }
    }

    public struct Ask: Sendable, Hashable {
        public var label: String
        public var ask: String
        /// A row across the width with a chevron, rather than a small button.
        public var row = false
        public var symbol: String?
    }

    // MARK: Reading

    public static let maxBytes = 128 * 1024
    static let maxSections = 16
    static let maxBlocks = 24
    static let maxItems = 24
    static let maxSeries = 4
    static let maxScrollingRows = 100

    /// Reads `{summary, sections}`. Throws only when it isn't a page at all; a bad part is left out.
    public static func parse(_ json: JSONValue) throws -> ExtensionPage {
        guard json.jsonString.utf8.count <= maxBytes else { throw UserFacingError("The page is larger than 128 KB.") }
        guard let object = json.objectValue, object["sections"]?.arrayValue != nil || object["summary"] != nil else {
            throw UserFacingError("That isn't a page.")
        }
        let sections = (object["sections"]?.arrayValue ?? []).prefix(maxSections).compactMap(section)
        var page = ExtensionPage(summary: object["summary"].flatMap(summary), sections: sections)
        page.back = text(object["back"], 40)
        page.bare = object["bare"]?.boolValue ?? false
        page.bleed = page.bare && (object["bleed"]?.boolValue ?? false)
        page.dress = PageDress.parse(object["dress"])
        page.tile = object["tile"].flatMap { try? SurfaceScene.parse($0, within: tileSize) }
        page.maxWidth = object["max_width"]?.doubleValue.flatMap { $0.isFinite ? min(1320, max(640, $0)) : nil }
        page.workspace = page.bare && (object["workspace"]?.boolValue ?? false)
        page.companion = object["companion"]?.boolValue ?? false
        page.quietHost = object["quiet_host"]?.boolValue ?? false
        page.shortcuts = (object["shortcuts"]?.arrayValue ?? []).prefix(Shortcut.Key.allCases.count).compactMap(Shortcut.parse)
        // As in a dress: white goes on it, so what's too light to hold white words is left out (D108).
        page.accent = Array((object["accent"]?.arrayValue ?? []).compactMap { color($0) }.filter { PageDress.Pair.luminance($0) <= PageDress.Pair.holdsWhite }.prefix(2))
        page.keepOnePrimary()
        return page
    }

    static func section(_ s: JSONValue) -> Section? {
        let blocks = (s["blocks"]?.arrayValue ?? []).prefix(maxBlocks).compactMap(block)
        let title = text(s["title"], 60)
        // A title with controls at its end is a whole section: a toolbar.
        guard !blocks.isEmpty || (title != nil && s["accessories"] != nil) else { return nil }
        var section = Section(title: title, blocks: blocks, place: s["place"]?.stringValue.flatMap(Section.Place.init) ?? .main,
                              collapsed: title == nil ? nil : s["collapsed"]?.boolValue,
                              detail: title == nil ? nil : text(s["detail"], 160), picture: title == nil ? nil : PagePicture.parse(s["picture"]))
        if title != nil, let tint = color(s["banner"]?["tint"]) { section.banner = Section.Banner(tint: tint, symbol: symbol(s["banner"]?["symbol"])) }
        section.wide = s["wide"]?.boolValue ?? false
        section.compose(from: s)
        return section
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
        // A bare page doesn't draw its summary, so its main button doesn't take the page's one.
        if hero == nil, !bare, var control = summary?.control {
            keep(&control)
            summary?.control = control
        }
        func visit(_ list: inout [Section]) {
            for s in list.indices {
                for b in list[s].blocks.indices {
                    switch list[s].blocks[b] {
                    case .control(var c): keep(&c); list[s].blocks[b] = .control(c)
                    case .bar(var bar): for i in bar.actions.indices { keep(&bar.actions[i]) }; list[s].blocks[b] = .bar(bar)
                    case .hero(var h): for i in h.actions.indices { keep(&h.actions[i]) }; list[s].blocks[b] = .hero(h)
                    case .transport(var t): for i in t.buttons.indices { keep(&t.buttons[i]) }; list[s].blocks[b] = .transport(t)
                    case .cards(var grid):
                        for i in grid.items.indices { for a in grid.items[i].actions.indices { keep(&grid.items[i].actions[a]) } }
                        list[s].blocks[b] = .cards(grid)
                    case .tabs(var tabs):
                        for i in tabs.tabs.indices { visit(&tabs.tabs[i].sections) }
                        visit(&tabs.sections)
                        list[s].blocks[b] = .tabs(tabs)
                    default: break
                    }
                }
            }
        }
        visit(&sections)
    }

    static func summary(_ j: JSONValue) -> Summary? {
        guard let title = text(j["title"], 80) else { return nil }
        var control: Control?
        if let c = j["control"], case .control(let parsed)? = block(c) { control = parsed }
        // Details have room for translations, which run longer than English (240 characters, D76).
        return Summary(title: title, detail: text(j["detail"], 240) ?? "", tone: tone(j["tone"]), symbol: symbol(j["symbol"]), control: control)
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
            var chart = Chart(id: id, title: title, unit: text(j["unit"], 12), max: max, caption: text(j["caption"], 120), series: series)
            chart.height = j["height"]?.doubleValue.flatMap { $0.isFinite ? Swift.min(360, Swift.max(100, $0)) : nil }
            chart.colors = (j["colors"]?.arrayValue ?? []).prefix(maxSeries).compactMap(PageDress.Pair.parse)
            return .chart(chart)
        case "bars":
            // Without a title where the section's already says it.
            let title = text(j["title"], 60) ?? ""
            let items = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap { i -> Bar? in
                guard let label = text(i["label"], 60), let value = text(i["value"], 24) else { return nil }
                return Bar(label: label, value: value, fraction: fraction(i["fraction"]), tone: tone(i["tone"]), picture: PagePicture.parse(i["picture"]), symbol: symbol(i["symbol"]))
            }
            return .bars(Bars(title: title, caption: text(j["caption"], 120), items: items))
        case "facts":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap { i -> Fact? in
                guard let label = text(i["label"], 40), let value = text(i["value"], 120) else { return nil }
                return Fact(label: label, value: value)
            }
            return items.isEmpty ? nil : .facts(Facts(title: text(j["title"], 60), items: items))
        case "note":
            return text(j["text"], 400).map {
                var note = Note(text: $0, tone: tone(j["tone"]))
                note.symbol = symbol(j["symbol"])
                note.style = j["style"]?.stringValue.flatMap(NoteStyle.init(rawValue:)) ?? .band
                note.link = j["link"].flatMap { button($0, characters: 30) }
                return .note(note)
            }
        case "ask":
            guard let label = text(j["label"], 40), let ask = text(j["ask"], 200) else { return nil }
            return .ask(Ask(label: label, ask: ask, row: j["row"]?.boolValue ?? false, symbol: symbol(j["symbol"])))
        case "switch":
            let act = PageAct.parse(j)
            // A switch inside a scene shows no words: nothing that opens or reads anything on one.
            if case .palette? = act { return nil }
            if case .refresh? = act { return nil }
            guard let label = text(j["label"], 60), let tool = act == nil ? toolName(j["tool"]) : "", let input = smallInput(j["input"]) else { return nil }
            var control = Control(kind: .toggle(on: j["on"]?.boolValue ?? false), label: label, detail: text(j["detail"], 240), tool: tool,
                                  input: input, symbol: symbol(j["symbol"]))
            control.act = act
            control.key = stateKey(j["key"])
            return .control(control)
        case "button":
            return button(j, characters: 60).map { .control($0) }
        case "choice":
            let go = PageGo.parse(j["go"])
            guard let label = text(j["label"], 60), let tool = go == nil ? toolName(j["tool"]) : "", let input = smallInput(j["input"]) else { return nil }
            let style = j["style"]?.stringValue.flatMap(Choice.Style.init(rawValue:)) ?? .segmented
            // Pictures and rows hold a list of things (windows, devices); side by side, a few options read best.
            let many = style == .tiles || style == .rows || style == .menu
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
            var choice = Choice(label: label, detail: text(j["detail"], 240), options: options,
                                selected: options.contains { $0.value == selected } ? selected : "", tool: tool, input: input,
                                style: style, key: key, disabled: j["disabled"]?.boolValue ?? false, go: go)
            choice.hideLabel = j["hide_label"]?.boolValue ?? false
            choice.columns = j["columns"]?.intValue.map { Swift.min(4, Swift.max(1, $0)) }
            if go == nil, j["multiple"]?.boolValue == true {
                choice.multiple = true
                choice.selectedAll = (j["selected_all"]?.arrayValue ?? []).compactMap(\.stringValue).filter { v in options.contains { $0.value == v } }
            }
            return .choice(choice)
        case "hero":
            guard let title = text(j["title"], 80) else { return nil }
            let facts = (j["facts"]?.arrayValue ?? []).prefix(4).compactMap { f -> Fact? in
                guard let label = text(f["label"], 24), let value = text(f["value"], 30) else { return nil }
                return Fact(label: label, value: value)
            }
            let code = j["code"]?.stringValue.flatMap { $0.range(of: #"^[0-9A-Z][0-9A-Z \-]{0,11}$"#, options: .regularExpression) != nil ? $0 : nil }
            return .hero(Hero(eyebrow: text(j["eyebrow"], 30), title: title, detail: text(j["detail"], 300), tone: tone(j["tone"]),
                              symbol: symbol(j["symbol"]), code: code, image: dataFile(j["image"]), busy: j["busy"]?.boolValue ?? false,
                              facts: facts, actions: (j["actions"]?.arrayValue ?? []).prefix(3).compactMap { button($0, characters: 30) },
                              scene: PagePicture.parse(j["scene"]), figure: PagePicture.parse(j["figure"]), says: text(j["says"], 80),
                              tile: (j["tile"]?.arrayValue ?? []).prefix(2).compactMap(color), wash: (j["wash"]?.arrayValue ?? []).prefix(2).compactMap(color),
                              ring: ring(j["ring"]), chips: chips(j["chips"]), plain: j["plain"]?.boolValue ?? false))
        case "transport":
            // Every button is drawn as its symbol, its label read aloud and shown on hover.
            let buttons = (j["buttons"]?.arrayValue ?? []).prefix(5).compactMap { button($0, characters: 30) }.filter { $0.symbol != nil }
            guard !buttons.isEmpty else { return nil }
            func seconds(_ v: JSONValue?) -> Double? { v?.doubleValue.flatMap { $0.isFinite && $0 >= 0 && $0 < 1_000_000 ? $0 : nil } }
            return .transport(Transport(title: text(j["title"], 80), detail: text(j["detail"], 120), position: seconds(j["position"]),
                                        duration: seconds(j["duration"]).flatMap { $0 > 0 ? $0 : nil },
                                        state: j["state"]?.stringValue.flatMap(Transport.State.init) ?? .stopped, buttons: buttons))
        case "field":
            let go = PageGo.parse(j["go"])
            // With an `id` it is edited in place (D113), so it has no button and may hold a whole prompt, its lines kept.
            let editId = go == nil ? j["id"]?.stringValue.flatMap { $0.range(of: #"^[A-Za-z0-9_.:-]{1,64}$"#, options: .regularExpression) != nil ? $0 : nil } : nil
            guard let label = text(j["label"], 60), let button = editId != nil ? "" : text(j["button"], 24), let tool = go == nil ? toolName(j["tool"]) : "",
                  let input = smallInput(j["input"]) else { return nil }
            let key = j["key"]?.stringValue ?? "text"
            guard key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, key != "on" else { return nil }
            var field = Field(label: label, detail: text(j["detail"], 240), placeholder: text(j["placeholder"], 60), button: button, tool: tool,
                              input: input, key: key, go: go, live: go != nil && (j["live"]?.boolValue ?? false), value: text(j["value"], 500))
            field.search = j["search"]?.boolValue ?? false
            if let editId {
                field.id = editId
                field.value = j["value"]?.stringValue.map { ExtensionText.untrusted($0, bytes: Field.longestEdit * 2) } ?? ""
                field.kind = j["kind"]?.stringValue.flatMap(Field.Kind.init(rawValue:)) ?? .text
                field.tokens = (j["tokens"]?.arrayValue ?? []).prefix(64).compactMap { t in
                    guard let label = text(t["label"], 40), let value = t["value"]?.stringValue, (1...200).contains(value.count) else { return nil }
                    return Field.Token(label: label, value: ExtensionText.line(value, characters: 200), symbol: symbol(t["symbol"]), group: text(t["group"], 40))
                }
            }
            return .field(field)
        case "list":
            // A list that scrolls in its own height may be longer than one drawn whole.
            let rows = (j["items"]?.arrayValue ?? []).prefix(j["max_height"]?.doubleValue == nil ? maxItems : maxScrollingRows).compactMap { r -> Row? in
                guard let title = text(r["title"], 120) else { return nil }
                var button: Control?
                if let b = r["button"] {
                    button = self.button(b, characters: 24)
                    button?.kind = .button(.secondary)
                }
                return Row(title: title, detail: text(r["detail"], 240), image: dataFile(r["image"]), color: color(r["color"]),
                           symbol: symbol(r["symbol"]), button: button, press: rowPress(r["press"]), selected: r["selected"]?.boolValue ?? false,
                           mark: symbol(r["mark"]), markLabel: text(r["mark_label"], 40))
            }
            guard !rows.isEmpty || j["title"] != nil else { return nil }
            return .list(List(title: text(j["title"], 60), caption: text(j["caption"], 120), rows: rows,
                              maxHeight: j["max_height"]?.doubleValue.flatMap { $0.isFinite ? Swift.min(1200, Swift.max(120, $0)) : nil }, empty: text(j["empty"], 160)))
        default:
            return richBlock(j)
        }
    }

    /// A button: its label (at most `characters`), the extension's own tool and a small input, a style, a symbol, and
    /// whether it can be clicked now.
    static func button(_ j: JSONValue, characters: Int) -> Control? {
        let act = PageAct.parse(j)
        guard let label = text(j["label"], characters), let tool = act == nil ? toolName(j["tool"]) : "", let input = smallInput(j["input"]) else { return nil }
        let symbol = symbol(j["symbol"])
        // Only a symbol on it: it may run a tool, which is in History, or move around the page. Anything else hangs on words the person can read (D105).
        let quiet: Bool = switch act {
        case nil, .go?: true
        default: false
        }
        return Control(kind: .button(j["style"]?.stringValue.flatMap(Control.Style.init(rawValue:)) ?? .secondary), label: label,
                       detail: text(j["detail"], 240), tool: tool, input: input, symbol: symbol, disabled: j["disabled"]?.boolValue ?? false,
                       round: j["shape"]?.stringValue == "round", act: act, fill: j["fill"]?.boolValue ?? false, iconOnly: j["shape"]?.stringValue == "icon" && symbol != nil && quiet)
    }

    /// A key in the page's state (D105).
    static func stateKey(_ j: JSONValue?) -> String? {
        guard let key = j?.stringValue, key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil else { return nil }
        return key
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
        let line = ExtensionText.line(raw, characters: characters, isolates: true).trimmingCharacters(in: .whitespaces)
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
        func visit(_ list: [Section]) {
            for section in list {
                for block in section.blocks {
                    if case .chart(let chart) = block { for s in chart.series { out["\(chart.id)/\(s.key)"] = s.value } }
                    if case .tabs(let tabs) = block {
                        for tab in tabs.tabs { visit(tab.sections) }
                        visit(tabs.sections)
                    }
                }
            }
        }
        visit(sections)
        return out
    }
}
