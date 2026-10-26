import SwiftUI

/// Buttons side by side, wrapping onto the next line when a language makes them longer, so a button is
/// never cut off. German cut "Allow for this request" to "Für diese Anfrage erlau…" on an approval card;
/// stacking every button instead made a column of five under an answer. A button wider than the line on
/// its own gets the whole line (and truncates there).
struct ButtonRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        let width = lines.map { $0.items.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            for item in line.items {
                // Centred on the line, so a taller button doesn't lift its neighbours' text.
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: y + (line.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        var x: CGFloat = 0
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width { size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if !line.items.isEmpty, x + size.width > width {
                lines.append(line)
                line = Line()
                x = 0
            }
            line.items.append((index, x, size))
            line.height = max(line.height, size.height)
            x += size.width + spacing
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
