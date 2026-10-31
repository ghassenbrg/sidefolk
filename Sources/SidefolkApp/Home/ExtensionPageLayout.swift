import SidefolkCore
import SwiftUI

// How an extension's page uses the window's width (D62, D67, D73): the rules of what goes where are
// ExtensionPage+Layout in SidefolkCore; these are the layouts that place it. Cards in a row share the row's width and
// height, so nothing is left hanging at one side.


nonisolated private struct RegionKey: LayoutValueKey { static let defaultValue = PageRegion.main }

extension View {
    func pageRegion(_ region: PageRegion) -> some View { layoutValue(key: RegionKey.self, value: region) }
}

/// A page with a side column (D73): in a window wide enough, the top parts across, then the side parts in a column at
/// the start edge (as a list of devices sits in an app's sidebar) beside the main ones; narrower, everything in one
/// column in the page's order. Each column stacks its parts; the page is as tall as the longer one.
struct PageRegions: Layout {
    var spacing: CGFloat
    /// Below this, one column.
    var minimumWide: CGFloat = 780

    func sideWidth(_ width: CGFloat) -> CGFloat { min(360, max(280, (width - spacing) * 0.32)) }

    private func frames(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        func height(_ view: LayoutSubview, _ w: CGFloat) -> CGFloat { view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        // One column when narrow, or when nothing goes beside the main parts.
        guard width >= minimumWide, subviews.contains(where: { $0[RegionKey.self] == .side }) else {
            var y: CGFloat = 0
            for (i, view) in subviews.enumerated() {
                let h = height(view, width)
                frames[i] = CGRect(x: 0, y: y, width: width, height: h)
                y += h + spacing
            }
            return (frames, max(0, y - spacing))
        }
        let side = sideWidth(width), main = width - side - spacing
        var top: CGFloat = 0
        for (i, view) in subviews.enumerated() where view[RegionKey.self] == .top {
            let h = height(view, width)
            frames[i] = CGRect(x: 0, y: top, width: width, height: h)
            top += h + spacing
        }
        // Laid out start to end; SwiftUI mirrors it right to left.
        var sideY = top, mainY = top
        for (i, view) in subviews.enumerated() where view[RegionKey.self] != .top {
            if view[RegionKey.self] == .side {
                let h = height(view, side)
                frames[i] = CGRect(x: 0, y: sideY, width: side, height: h)
                sideY += h + spacing
            } else {
                let h = height(view, main)
                frames[i] = CGRect(x: side + spacing, y: mainY, width: main, height: h)
                mainY += h + spacing
            }
        }
        return (frames, max(0, max(sideY, mainY) - spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        return CGSize(width: width, height: frames(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(bounds.width, subviews).frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// Cards in rows of equal columns: as many as fit at `minWidth`, at most `maxColumns`, then balanced so the last row
/// isn't a lone card (four charts are two by two, not three and one). Each card is as tall as its row.
struct CardGrid: Layout {
    var minWidth: CGFloat
    var maxColumns: Int
    var spacing: CGFloat
    /// Off: as many columns as fit even when there are fewer cards, so two pictures stay picture-sized (D73).
    var stretch = true

    func columns(_ width: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 1 }
        let room = max(1, min(maxColumns, Int((width + spacing) / (minWidth + spacing))))
        if !stretch { return room }
        let fit = min(room, count)
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
