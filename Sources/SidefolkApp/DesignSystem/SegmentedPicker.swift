import SwiftUI

/// Lantern's segmented choice (D84): a well with the chosen segment raised on it, words in ink, the others muted. Two
/// to five short choices that switch a view or a setting at once ("Releases | Snapshots", "Light | Dark | Same as
/// Mac"); longer lists are a pop-up. Each segment is a button, so the keyboard and VoiceOver reach it, and it says
/// when it is the one chosen.
struct SegmentedPicker<Value: Hashable>: View {
    struct Segment {
        var value: Value
        var title: Text
        var symbol: String?

        init(_ value: Value, _ title: Text, symbol: String? = nil) {
            self.value = value
            self.title = title
            self.symbol = symbol
        }

        init(_ value: Value, _ title: LocalizedStringKey, symbol: String? = nil) {
            self.init(value, Text(title), symbol: symbol)
        }

        init(_ value: Value, verbatim title: String, symbol: String? = nil) {
            self.init(value, Text(verbatim: title), symbol: symbol)
        }
    }

    var label: Text
    @Binding var selection: Value
    var segments: [Segment]
    /// Small sits in a row of filters (24 tall); regular is 28.
    var small = false
    /// Every segment as wide as the widest, as a control filling its row does.
    var equalWidths = false
    /// The chosen segment in this colour, its words white: a page's own (D108).
    var chosenFill: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    init(_ label: Text, selection: Binding<Value>, segments: [Segment], small: Bool = false, equalWidths: Bool = false, chosenFill: Color? = nil) {
        self.label = label
        _selection = selection
        self.segments = segments
        self.small = small
        self.equalWidths = equalWidths
        self.chosenFill = chosenFill
    }

    init(_ label: LocalizedStringKey, selection: Binding<Value>, segments: [Segment], small: Bool = false, equalWidths: Bool = false) {
        self.init(Text(label), selection: selection, segments: segments, small: small, equalWidths: equalWidths)
    }

    var body: some View {
        let inner = RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
        SegmentRow(equal: equalWidths) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                let chosen = segment.value == selection
                Button {
                    selection = segment.value
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = segment.symbol { Image(systemName: symbol).font(.system(size: small ? 10 : 11, weight: .medium)) }
                        segment.title.lineLimit(1)
                    }
                    .font(.system(size: small ? 12 : 13, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(chosen ? (chosenFill == nil ? Theme.ink : Color.white) : Theme.inkMuted)
                    // Sharing a narrow row, the words get the room: "Notes" before "No…". Never under the 11 pt floor.
                    .padding(.horizontal, equalWidths ? Theme.Space.xxs : small ? Theme.Space.s + 2 : Theme.Space.m)
                    .minimumScaleFactor(small ? 0.92 : 0.85)
                    .frame(maxWidth: equalWidths ? .infinity : nil, minHeight: (small ? Theme.Size.buttonSmall : Theme.Size.button) - 4)
                    .background {
                        if chosen {
                            inner.fill(chosenFill ?? (scheme == .dark ? Color.white.opacity(0.12) : Theme.surfaceRaised))
                                // The fill alone is about 1.2:1 from its track: an edge says which one is chosen (D130). A dressed page
                                // chooses its own fill, and its contrast.
                                .overlay { if chosenFill == nil { inner.strokeBorder(Theme.accent) } }
                                .shadow(color: Color(hex: 0x0F1E36).opacity(scheme == .dark ? 0 : 0.10), radius: 1, y: 1)
                        }
                    }
                    .contentShape(inner)
                }
                .buttonStyle(.sfBare)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contrastEdge(radius: Theme.Radius.control)
        .fixedSize(horizontal: !equalWidths, vertical: true)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Theme.Motion.micro, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The segments side by side, 2 apart. With `equal`, each as wide as the widest while they all fit; in a row too narrow for that,
/// each gets its own word's width and a share of what's left, so "Aufgaben" takes room from "Alle" before it's cut.
private struct SegmentRow: Layout {
    var equal: Bool
    private static let spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        let natural = sizes.map(\.width).reduce(0, +) + Self.gaps(subviews.count)
        guard equal, let width = proposal.width, width.isFinite else { return CGSize(width: natural, height: height) }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(subviews, in: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + Self.spacing
        }
    }

    private func widths(_ subviews: Subviews, in width: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard equal, !natural.isEmpty else { return natural }
        let room = width - Self.gaps(subviews.count)
        let share = room / CGFloat(natural.count)
        if (natural.max() ?? 0) <= share { return natural.map { _ in share } }
        let left = (room - natural.reduce(0, +)) / CGFloat(natural.count)
        return natural.map { max(0, $0 + left) }
    }

    private static func gaps(_ count: Int) -> CGFloat { spacing * CGFloat(max(0, count - 1)) }
}
