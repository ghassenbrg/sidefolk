import SidefolkCore
import SwiftUI

// How an extension's page uses the window's width (D62, D67): a page that shows a lot (numbers, charts) grows to a
// wide centred column, its big sections across it and its small ones side by side; a page of switches stays a
// readable column. Cards in a row share the row's width and height, so nothing is left hanging at one side.

extension ExtensionPage {
    /// Numbers or several cards: worth a wide window. A page of switches and buttons reads better narrow.
    var isRich: Bool { sections.contains { $0.isWide && $0.blocks.contains { $0.isCard || $0.isMetric } } }

    /// Sections in reading order, the wide ones alone and the runs of small ones between them together.
    var runs: [[Section]] {
        var out: [[Section]] = []
        for section in sections {
            if !section.isWide, let last = out.last, let first = last.first, !first.isWide {
                out[out.count - 1].append(section)
            } else {
                out.append([section])
            }
        }
        return out
    }
}

extension ExtensionPage.Section {
    /// Across the page: numbers, two or more cards, a row of buttons or questions, or notes alone (heads-ups that
    /// read as one line). Anything else (one card with its note, a few switches) takes a column beside its neighbours.
    var isWide: Bool {
        if blocks.contains(where: \.isMetric) { return true }
        if blocks.filter(\.isCard).count >= 2 { return true }
        let kinds = Set(blocks.map(\.kind))
        return kinds == ["note"] || kinds.isSubset(of: ["ask", "button"])
    }
}

extension ExtensionPage.Block {
    var isMetric: Bool { kind == "gauge" || kind == "stat" }
    var isCard: Bool { kind == "chart" || kind == "bars" || kind == "facts" }

    var kind: String {
        switch self {
        case .gauge: "gauge"
        case .stat: "stat"
        case .chart: "chart"
        case .bars: "bars"
        case .facts: "facts"
        case .note: "note"
        case .ask: "ask"
        case .control(let c): if case .toggle = c.kind { "switch" } else { "button" }
        }
    }
}

/// Cards in rows of equal columns: as many as fit at `minWidth`, at most `maxColumns`, then balanced so the last row
/// isn't a lone card (four charts are two by two, not three and one). Each card is as tall as its row.
struct CardGrid: Layout {
    var minWidth: CGFloat
    var maxColumns: Int
    var spacing: CGFloat

    func columns(_ width: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 1 }
        let fit = max(1, min(maxColumns, Int((width + spacing) / (minWidth + spacing)), count))
        let rows = (count + fit - 1) / fit
        return (count + rows - 1) / rows
    }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (columns: Int, column: CGFloat, heights: [CGFloat]) {
        let n = columns(width, count: subviews.count)
        let column = max(0, (width - spacing * CGFloat(n - 1)) / CGFloat(n))
        let heights = stride(from: 0, to: subviews.count, by: n).map { start in
            subviews[start..<min(start + n, subviews.count)].map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        }
        return (n, column, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minWidth * CGFloat(min(maxColumns, subviews.count))
        let r = rows(width, subviews)
        return CGSize(width: width, height: r.heights.reduce(0, +) + spacing * CGFloat(max(0, r.heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(bounds.width, subviews)
        var y = bounds.minY
        for (row, height) in r.heights.enumerated() {
            for i in 0..<r.columns {
                let index = row * r.columns + i
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(i) * (r.column + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: r.column, height: height))
            }
            y += height + spacing
        }
    }
}

/// Small sections side by side, each into the shortest column (as a newspaper fills its columns): as many columns
/// as fit at `minWidth`, never more than there are sections, so one section alone spans the page.
struct SectionColumns: Layout {
    var minWidth: CGFloat
    var maxColumns: Int
    var spacing: CGFloat

    private func place(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let n = max(1, min(maxColumns, Int((width + spacing) / (minWidth + spacing)), subviews.count))
        let column = max(0, (width - spacing * CGFloat(n - 1)) / CGFloat(n))
        var tops = Array(repeating: CGFloat(0), count: n)
        var frames: [CGRect] = []
        for view in subviews {
            let i = tops.indices.min { tops[$0] < tops[$1] } ?? 0
            let height = view.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            frames.append(CGRect(x: CGFloat(i) * (column + spacing), y: tops[i], width: column, height: height))
            tops[i] += height + spacing
        }
        return (frames, max(0, (tops.max() ?? 0) - spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minWidth
        return CGSize(width: width, height: place(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, place(bounds.width, subviews).frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// Buttons in rows that wrap, in reading order.
struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [i], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
    }
}
