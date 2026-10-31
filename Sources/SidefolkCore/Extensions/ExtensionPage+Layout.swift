import Foundation

// What goes where on an extension's page (D62, D67, D74), decided from what it holds; the app's layouts place it. A
// page that shows a lot (numbers, charts, pictures, a column beside) grows to a wide centred column, its big sections
// across it and its small ones side by side; a page of switches stays a readable column.

/// Where a part of the page goes (D74): across the top, in the column beside the main one, or in the main one.
public enum PageRegion: Equatable, Sendable { case top, side, main }

extension ExtensionPage {
    /// Numbers or several cards, a hero, pictures or a column beside the main one: worth a wide window. A page of
    /// switches and buttons reads better narrow.
    public var isRich: Bool {
        hasSide || sections.contains { $0.isWide && $0.blocks.contains { $0.isCard || $0.isMetric || $0.kind == "hero" || $0.kind == "tiles" } }
    }

    /// Some sections go in a column beside the others (D74).
    public var hasSide: Bool { sections.contains { $0.place == .side } }

    /// What the page draws, in reading order, each with where it goes (D74): a hero leading the page across it, side
    /// sections one by one, and the main sections in runs (the wide ones alone, small ones between them together).
    public var regions: [(region: PageRegion, sections: [Section])] {
        var out: [(region: PageRegion, sections: [Section])] = []
        for (i, section) in sections.enumerated() {
            if i == 0, hero != nil {
                out.append((.top, [section]))
            } else if section.place == .side, hasSide {
                out.append((.side, [section]))
            } else if !section.isWide, let last = out.last, last.region == .main, let first = last.sections.first, !first.isWide {
                out[out.count - 1].sections.append(section)
            } else {
                out.append((.main, [section]))
            }
        }
        return out
    }
}

extension ExtensionPage.Section {
    /// Across the page: numbers, two or more cards, a row of buttons or questions, or notes alone (heads-ups that
    /// read as one line). Anything else (one card with its note, a few switches) takes a column beside its neighbours.
    public var isWide: Bool {
        if blocks.contains(where: { $0.isMetric || ["hero", "transport", "tiles", "cards"].contains($0.kind) }) { return true }
        if blocks.filter(\.isCard).count >= 2 { return true }
        let kinds = Set(blocks.map(\.kind))
        return kinds == ["note"] || kinds.isSubset(of: ["ask", "button"])
    }
}

extension ExtensionPage.Block {
    public var isMetric: Bool { kind == "gauge" || kind == "stat" }
    public var isCard: Bool { kind == "chart" || kind == "bars" || kind == "facts" || kind == "list" }

    public var kind: String {
        switch self {
        case .gauge: "gauge"
        case .stat: "stat"
        case .chart: "chart"
        case .bars: "bars"
        case .facts: "facts"
        case .note: "note"
        case .ask: "ask"
        case .control(let c): if case .toggle = c.kind { "switch" } else { "button" }
        case .choice(let c): c.style == .tiles ? "tiles" : c.style == .cards ? "cards" : "choice"
        case .field: "field"
        case .list: "list"
        case .hero: "hero"
        case .transport: "transport"
        }
    }
}

