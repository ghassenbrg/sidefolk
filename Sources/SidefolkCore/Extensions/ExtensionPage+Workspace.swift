import Foundation

/// The small parts a page needs when it takes the window (D126): a head, a column of places, what a person will receive and a row of recent results. Any page may use them.
extension ExtensionPage {
    public struct PageHead: Sendable, Hashable {
        public var title: String
        public var pill: Badge?
        public var detail: String?
        public var actions: [Control]
        /// Under ⋯.
        public var menu: [Control]
    }

    public struct Nav: Sendable, Hashable {
        public struct Item: Sendable, Hashable, Identifiable {
            public var id: String
            public var title: String
            /// One word under the title, beside a dot in `tone`.
            public var status: String?
            public var tone: Tone
            public var symbol: String?
            public var color: String?
            public var selected: Bool
            public var press: Control
        }

        /// Heads the column with the extension's own icon and name, as Sidefolk knows them.
        public var brand: Bool
        public var title: String?
        /// Beside the title.
        public var add: Control?
        public var filters: [Item]
        public var items: [Item]
        /// Where the list is empty.
        public var empty: String?
    }

    public struct Notice: Sendable, Hashable {
        public var title: String?
        public var body: String?
        public var time: String?
        public var footer: String?
        /// Still being written: what's there so far.
        public var forming: Bool
        /// Nothing to show yet: an outline, and these words in it.
        public var placeholder: String?
    }

    public struct Ticks: Sendable, Hashable {
        public struct Item: Sendable, Hashable {
            public var tone: Tone
            /// Read aloud and on hover: "Monday, done".
            public var label: String
            /// Drawn hollow: it didn't run.
            public var hollow: Bool
        }

        public var title: String?
        public var caption: String?
        public var items: [Item]
    }

    static func workspacePart(_ j: JSONValue) -> Block? {
        func badge(_ b: JSONValue?) -> Badge? { text(b?["text"], 24).map { Badge(text: $0, tone: tone(b?["tone"])) } }
        func item(_ i: JSONValue) -> Nav.Item? {
            guard let id = i["id"]?.stringValue, let title = text(i["title"], 60), let press = i["press"].flatMap({ button($0, characters: 60) }) else { return nil }
            return Nav.Item(id: id, title: title, status: text(i["status"], 24), tone: tone(i["tone"]), symbol: symbol(i["symbol"]), color: color(i["color"]),
                            selected: i["selected"]?.boolValue ?? false, press: press)
        }
        switch j["type"]?.stringValue {
        case "bar":
            guard let title = text(j["title"], 80) else { return nil }
            return .bar(PageHead(title: title, pill: badge(j["pill"]), detail: text(j["detail"], 240),
                            actions: (j["actions"]?.arrayValue ?? []).prefix(3).compactMap { button($0, characters: 30) },
                            menu: (j["menu"]?.arrayValue ?? []).prefix(8).compactMap { button($0, characters: 30) }))
        case "nav":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxItems).compactMap(item)
            let brand = j["brand"]?.boolValue ?? false, title = text(j["title"], 40)
            guard !items.isEmpty || brand || title != nil else { return nil }
            return .nav(Nav(brand: brand, title: title, add: j["add"].flatMap { button($0, characters: 30) },
                            filters: (j["filters"]?.arrayValue ?? []).prefix(6).compactMap(item), items: items, empty: text(j["empty"], 120)))
        case "notice":
            let notice = Notice(title: text(j["title"], 80), body: j["body"]?.stringValue.map { ExtensionText.untrusted($0, bytes: 1_000) }, time: text(j["time"], 24), footer: text(j["footer"], 80),
                                forming: j["forming"]?.boolValue ?? false, placeholder: text(j["placeholder"], 120))
            return notice.title == nil && notice.body == nil && notice.placeholder == nil ? nil : .notice(notice)
        case "ticks":
            let items = (j["items"]?.arrayValue ?? []).prefix(31).compactMap { i -> Ticks.Item? in
                text(i["label"], 60).map { Ticks.Item(tone: tone(i["tone"]), label: $0, hollow: i["hollow"]?.boolValue ?? false) }
            }
            return items.isEmpty ? nil : .ticks(Ticks(title: text(j["title"], 60), caption: text(j["caption"], 120), items: items))
        default:
            return nil
        }
    }
}
