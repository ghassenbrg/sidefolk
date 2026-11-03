import Foundation

/// A rail of things in order (`steps`, D113), read like any page part: what is off is dropped, nothing here reaches a model, and each hook
/// runs one of the extension's own tools as the person, through Guard. For anything that happens one after another: a recipe, a checklist, a
/// pipeline, a day. It holds no meaning of its own: rows, a line, and what a click means is the tool's.
extension ExtensionPage {
    public struct Steps: Sendable, Hashable {
        public struct Item: Sendable, Hashable, Identifiable {
            public enum State: String, Sendable, Hashable { case none, pending, running, waiting, done, failed, skipped }

            public var id: String
            public var title: String
            public var detail: String?
            public var result: String?
            public var symbol: String?
            public var color: String?
            public var tone: Tone
            public var state: State
            public var badge: Badge?
            /// 0 on the line, up to 2 on a branch from it.
            public var depth: Int
            public var label: String?
            public var locked: Bool
            public var actions: [Control]
            public var output: String?
        }

        /// One of the extension's tools, with what the person pointed at under `key`.
        public struct Hook: Sendable, Hashable {
            public var tool: String
            public var input: JSONValue
            public var key: String
            public var label: String?

            public func input(_ value: JSONValue) -> JSONValue { input.setting(key, value) }
        }

        public var title: String?
        public var caption: String?
        public var items: [Item]
        public var selected: String?
        public var select: Hook?
        public var reorder: Hook?
        public var insert: Hook?
        public var line: [String]

        /// The rows that move together with `id`: those beside it at its depth, between its parent and the next one out.
        public func siblings(of id: String) -> [Item] {
            guard let at = items.firstIndex(where: { $0.id == id }) else { return [] }
            let depth = items[at].depth
            var start = at, end = at
            while start > 0, items[start - 1].depth >= depth { start -= 1 }
            while end + 1 < items.count, items[end + 1].depth >= depth { end += 1 }
            return items[start...end].filter { $0.depth == depth && !$0.locked }
        }

        /// What moving `id` by one place among its own says: the id it now stands before, or `.null` at the end. Nil when it can't go there.
        public func move(_ id: String, by delta: Int) -> JSONValue? {
            let own = siblings(of: id)
            guard let at = own.firstIndex(where: { $0.id == id }), own.indices.contains(at + delta) else { return nil }
            if delta < 0 { return ["id": .string(id), "before": .string(own[at + delta].id)] }
            let next = at + delta + 1
            return ["id": .string(id), "before": own.indices.contains(next) ? .string(own[next].id) : .null]
        }
    }

    static let maxStepItems = 64

    /// `id` is the row's own name, and comes back in hooks: the shape a key has, a little longer.
    private static let stepId = #"^[A-Za-z0-9_.:-]{1,64}$"#

    static func parseSteps(_ j: JSONValue) -> Steps? {
        var seen = Set<String>()
        let items = (j["items"]?.arrayValue ?? []).prefix(maxStepItems).compactMap { i -> Steps.Item? in
            guard let id = i["id"]?.stringValue, id.range(of: stepId, options: .regularExpression) != nil, seen.insert(id).inserted, let title = text(i["title"], 240) else { return nil }
            var badge: Badge?
            if let b = i["badge"], let t = text(b["text"], 24) { badge = Badge(text: t, tone: tone(b["tone"])) }
            let actions = (i["actions"]?.arrayValue ?? []).prefix(2).compactMap { button($0, characters: 24) }
            return Steps.Item(id: id, title: title, detail: text(i["detail"], 240), result: text(i["result"], 24), symbol: symbol(i["symbol"]), color: color(i["color"]),
                              tone: tone(i["tone"]), state: i["state"]?.stringValue.flatMap(Steps.Item.State.init(rawValue:)) ?? .none, badge: badge,
                              depth: min(max(i["depth"]?.intValue ?? 0, 0), 2), label: text(i["label"], 24), locked: i["locked"]?.boolValue ?? false, actions: actions,
                              output: i["output"]?.stringValue.map { ExtensionText.untrusted($0, bytes: 4_000) })
        }
        guard !items.isEmpty else { return nil }
        return Steps(title: text(j["title"], 60), caption: text(j["caption"], 240), items: items, selected: j["selected"]?.stringValue, select: hook(j["select"]), reorder: hook(j["reorder"]),
                     insert: hook(j["insert"]), line: Array((j["line"]?.arrayValue ?? []).compactMap { color($0) }.prefix(2)))
    }
}
