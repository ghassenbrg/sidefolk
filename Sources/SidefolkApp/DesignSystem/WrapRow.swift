import SwiftUI

/// Words with something at their end (a button, a time, a chip): side by side while the words keep at least `minimum`
/// points, otherwise the end goes under them. A narrow Today column (D64) gave the words what a button left, and an
/// empty state read "Not / watchi / ng" down a 600-point tile.
///
/// The first subview is the words; the rest sit at the end, in a row. Under the words they start at `indent`.
struct WrapRow: Layout {
    var minimum: CGFloat = 200
    var spacing: CGFloat = 8
    var alignment: VerticalAlignment = .center
    var indent: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let words = subviews.first else { return .zero }
        let ends = Array(subviews.dropFirst()).map { $0.sizeThatFits(.unspecified) }
        let endWidth = Self.width(of: ends, spacing: spacing)
        guard let width = proposal.width, width.isFinite else {
            let ideal = words.sizeThatFits(.unspecified)
            return CGSize(width: ideal.width + (ends.isEmpty ? 0 : spacing + endWidth), height: max(ideal.height, ends.map(\.height).max() ?? 0))
        }
        let endHeight = ends.map(\.height).max() ?? 0
        if sideBySide(width, endWidth, ends.isEmpty) {
            let h = words.sizeThatFits(ProposedViewSize(width: width - endWidth - (ends.isEmpty ? 0 : spacing), height: nil)).height
            return CGSize(width: width, height: max(h, endHeight))
        }
        let h = words.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: h + spacing + endHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let words = subviews.first else { return }
        let rest = Array(subviews.dropFirst())
        let ends = rest.map { $0.sizeThatFits(.unspecified) }
        let endWidth = Self.width(of: ends, spacing: spacing)
        if sideBySide(bounds.width, endWidth, ends.isEmpty) {
            let wordsWidth = bounds.width - endWidth - (ends.isEmpty ? 0 : spacing)
            let wordsSize = words.sizeThatFits(ProposedViewSize(width: wordsWidth, height: nil))
            words.place(at: CGPoint(x: bounds.minX, y: bounds.minY + offset(wordsSize.height, in: bounds.height)),
                        proposal: ProposedViewSize(width: wordsWidth, height: wordsSize.height))
            var x = bounds.maxX - endWidth
            for (view, size) in zip(rest, ends) {
                view.place(at: CGPoint(x: x, y: bounds.minY + offset(size.height, in: bounds.height)), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        } else {
            let wordsSize = words.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            words.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: wordsSize.height))
            var x = bounds.minX + indent
            let y = bounds.minY + wordsSize.height + spacing
            for (view, size) in zip(rest, ends) {
                // An end wider than the line on its own gets the line.
                let w = min(size.width, bounds.width - indent)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: size.height))
                x += w + spacing
            }
        }
    }

    private func sideBySide(_ width: CGFloat, _ endWidth: CGFloat, _ alone: Bool) -> Bool {
        alone || width - endWidth - spacing >= minimum
    }

    private func offset(_ height: CGFloat, in line: CGFloat) -> CGFloat {
        alignment == .top ? 0 : alignment == .bottom ? line - height : (line - height) / 2
    }

    private static func width(of sizes: [CGSize], spacing: CGFloat) -> CGFloat {
        sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
    }
}
