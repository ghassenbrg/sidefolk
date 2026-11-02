import Foundation

/// A picture a page may show (D100): a file in the pack's `assets` folder, with another for dark mode; one its program made in its data
/// folder; or the person's companion or the person, which Sidefolk places and the extension never reads.
public enum Picture {
    public enum Figure: String { case face, full }

    case pack(_ path: String, dark: String? = nil)
    case data(_ name: String)
    case companion(Figure)
    case person

    var json: [String: Any] {
        switch self {
        case .pack(let path, let dark):
            var out: [String: Any] = ["pack": path]
            if let dark { out["dark"] = dark }
            return out
        case .data(let name): return ["data": name]
        case .companion(let figure): return ["companion": figure.rawValue]
        case .person: return ["person": true]
        }
    }
}

/// One number of a `.stats` strip: "Wins 12".
public struct StatItem {
    public var label: String
    public var value: String
    public var symbol: String?
    public var tone: Tone

    public init(_ label: String, _ value: String, symbol: String? = nil, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.symbol = symbol
        self.tone = tone
    }

    var json: [String: Any] {
        var out: [String: Any] = ["label": label, "value": value, "tone": tone.rawValue]
        if let symbol { out["symbol"] = symbol }
        return out
    }
}

/// `large` has room for a wide picture and several lines; `small` is a tile of a line or two.
public enum CardSize: String { case small, large }

/// One card of a `.cards` grid. Up to three `actions`; the first is also what clicking the picture does. `done` is a tick for what's done
/// today. `menu` is a small menu beside the buttons: "Level ▸ Easy, Fair, Hard". `at` is when it last happened; Sidefolk words it.
public struct Card {
    public var title: String
    public var detail: String?
    public var meta: String?
    public var at: Date?
    public var picture: Picture?
    public var symbol: String?
    public var color: String?
    public var badge: Badge?
    public var done: Bool
    public var actions: [Action]
    public var menu: (label: String, items: [Action])?

    public init(_ title: String, detail: String? = nil, meta: String? = nil, at: Date? = nil, picture: Picture? = nil, symbol: String? = nil, color: String? = nil,
                badge: Badge? = nil, done: Bool = false, actions: [Action] = [], menu: (label: String, items: [Action])? = nil) {
        self.title = title
        self.detail = detail
        self.meta = meta
        self.at = at
        self.picture = picture
        self.symbol = symbol
        self.color = color
        self.badge = badge
        self.done = done
        self.actions = actions
        self.menu = menu
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "done": done, "actions": actions.map(\.json)]
        if let detail { out["detail"] = detail }
        if let meta { out["meta"] = meta }
        if let at { out["at"] = ISO8601DateFormatter().string(from: at) }
        if let picture { out["picture"] = picture.json }
        if let symbol { out["symbol"] = symbol }
        if let color { out["color"] = color }
        if let badge { out["badge"] = ["text": badge.text, "tone": badge.tone.rawValue] }
        if let menu { out["menu"] = ["label": menu.label, "items": menu.items.map(\.json)] as [String: Any] }
        return out
    }
}

/// One tab of `.tabs`: its sections, which can't hold tabs of their own.
public struct PageTab {
    public var id: String
    public var label: String
    public var symbol: String?
    public var badge: String?
    public var sections: [Section]

    public init(_ id: String, _ label: String, symbol: String? = nil, badge: String? = nil, sections: [Section]) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.badge = badge
        self.sections = sections
    }

    var json: [String: Any] {
        var out: [String: Any] = ["id": id, "label": label, "sections": sections.filter { !$0.blocks.isEmpty }.map(\.json)]
        if let symbol { out["symbol"] = symbol }
        if let badge { out["badge"] = badge }
        return out
    }
}

/// One of `.badges`: earned, or how far along (`value` of `goal`).
public struct Achievement {
    public var title: String
    public var detail: String?
    public var symbol: String?
    public var earned: Bool
    public var value: Int?
    public var goal: Int?

    public init(_ title: String, detail: String? = nil, symbol: String? = nil, earned: Bool = false, value: Int? = nil, goal: Int? = nil) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.earned = earned
        self.value = value
        self.goal = goal
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "earned": earned]
        if let detail { out["detail"] = detail }
        if let symbol { out["symbol"] = symbol }
        if let value { out["value"] = value }
        if let goal { out["goal"] = goal }
        return out
    }
}

/// One line of `.recent`: what happened, when, and its tone.
public struct RecentItem {
    public var title: String
    public var detail: String?
    public var at: Date?
    public var tone: Tone
    public var symbol: String?
    public var picture: Picture?

    public init(_ title: String, detail: String? = nil, at: Date? = nil, tone: Tone = .neutral, symbol: String? = nil, picture: Picture? = nil) {
        self.title = title
        self.detail = detail
        self.at = at
        self.tone = tone
        self.symbol = symbol
        self.picture = picture
    }

    var json: [String: Any] {
        var out: [String: Any] = ["title": title, "tone": tone.rawValue]
        if let detail { out["detail"] = detail }
        if let at { out["at"] = ISO8601DateFormatter().string(from: at) }
        if let symbol { out["symbol"] = symbol }
        if let picture { out["picture"] = picture.json }
        return out
    }
}
