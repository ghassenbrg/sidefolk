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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    init(_ label: Text, selection: Binding<Value>, segments: [Segment], small: Bool = false, equalWidths: Bool = false) {
        self.label = label
        _selection = selection
        self.segments = segments
        self.small = small
        self.equalWidths = equalWidths
    }

    init(_ label: LocalizedStringKey, selection: Binding<Value>, segments: [Segment], small: Bool = false, equalWidths: Bool = false) {
        self.init(Text(label), selection: selection, segments: segments, small: small, equalWidths: equalWidths)
    }

    var body: some View {
        let inner = RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
        HStack(spacing: 2) {
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
                    .foregroundStyle(chosen ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, small ? Theme.Space.s + 2 : Theme.Space.m)
                    .frame(maxWidth: equalWidths ? .infinity : nil, minHeight: (small ? Theme.Size.buttonSmall : Theme.Size.button) - 4)
                    .background {
                        if chosen {
                            inner.fill(scheme == .dark ? Color.white.opacity(0.12) : Theme.surfaceRaised)
                                .shadow(color: Color(hex: 0x0F1E36).opacity(scheme == .dark ? 0 : 0.10), radius: 1, y: 1)
                        }
                    }
                    .contentShape(inner)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .fixedSize(horizontal: !equalWidths, vertical: true)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Theme.Motion.micro, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
