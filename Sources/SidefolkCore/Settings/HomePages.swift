import Foundation

/// How the person arranged extensions' pages in Home (D67): their order in the sidebar, the ones kept out of it (still
/// in the Extensions page), the ones whose tile is off Today, and whether the sidebar's Extensions group is folded.
/// Pages are named by `ExtensionPageInfo.id` (`<extension id>/<page>`). A page not mentioned anywhere is new: it
/// shows, after the ones the person placed, with its tile if it has one.
public struct HomePages: Codable, Sendable, Equatable {
    public var order: [String] = []
    public var hidden: [String] = []
    public var noTile: [String] = []
    public var collapsed = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        hidden = (try? c.decode([String].self, forKey: .hidden)) ?? []
        noTile = (try? c.decode([String].self, forKey: .noTile)) ?? []
        collapsed = (try? c.decode(Bool.self, forKey: .collapsed)) ?? false
    }

    /// `ids` in the person's order: the placed ones as placed, then new ones in the order given.
    public func sorted(_ ids: [String]) -> [String] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.enumerated().sorted { a, b in
            switch (rank[a.element], rank[b.element]) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    /// The pages the sidebar lists, in order.
    public func shown(_ ids: [String]) -> [String] { sorted(ids).filter { !hidden.contains($0) } }

    public func inSidebar(_ id: String) -> Bool { !hidden.contains(id) }
    public func tile(_ id: String) -> Bool { !noTile.contains(id) }

    public mutating func setInSidebar(_ id: String, _ on: Bool) {
        hidden.removeAll { $0 == id }
        if !on { hidden.append(id) }
    }

    public mutating func setTile(_ id: String, _ on: Bool) {
        noTile.removeAll { $0 == id }
        if !on { noTile.append(id) }
    }

    /// Moves `id` to sit before `before` (at the end when nil) among `all`, the pages there are now; the whole order
    /// is written down, so a page added later doesn't jump between them.
    public mutating func move(_ id: String, before: String?, among all: [String]) {
        var ids = sorted(all).filter { $0 != id }
        let at = before.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
        ids.insert(id, at: at)
        order = ids
    }

    /// Moves `id` one place up (`-1`) or down (`1`) among the pages the sidebar shows.
    public mutating func step(_ id: String, by delta: Int, among all: [String]) {
        let visible = shown(all)
        guard let i = visible.firstIndex(of: id) else { return }
        let j = i + delta
        guard visible.indices.contains(j) else { return }
        // Down past the next one means before the one after it.
        let before = delta < 0 ? visible[j] : (visible.indices.contains(j + 1) ? visible[j + 1] : nil)
        move(id, before: before, among: all)
    }
}
