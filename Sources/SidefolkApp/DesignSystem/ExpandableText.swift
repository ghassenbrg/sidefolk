import SwiftUI

/// A notice's words, which may be longer than their place: the first lines, and Show all only when those cut them short.
/// Opened, the whole text scrolls inside a bounded height, so what comes after it (a card's answers) stays in reach. Plain
/// words only, never Markdown, links or detected data, since they may come from outside; they can be selected and copied,
/// and VoiceOver hears them whole either way.
struct ExpandableText: View {
    var text: String
    var lines = 3
    var font: Font = Theme.Font.body
    var color: Color = Theme.inkMuted
    /// The most the opened text takes before it scrolls.
    var maxHeight: CGFloat = 220
    /// Told when it opens or closes, for a window that fits itself to its content (the Sidecard).
    var changed: (() -> Void)?
    @Environment(\.opensLongText) private var startsOpen
    @State private var open: Bool?
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Whether the first lines leave words out: only then is there anything to open.
    private var cutShort: Bool { fullHeight > shownHeight + 1 }
    private var expanded: Bool { cutShort && (open ?? startsOpen) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if expanded {
                ScrollView {
                    words.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(max(fullHeight, 1), maxHeight))
            } else {
                words.lineLimit(lines)
                    .accessibilityLabel(Text(verbatim: text))
            }
            if cutShort {
                Button {
                    withAnimation(Theme.Motion.ease(0.2)) { open = !expanded }
                    changed?()
                } label: {
                    Label(expanded ? "Show less" : "Show all", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.sf(.plain))
            }
        }
        .background(alignment: .topLeading) {
            // The first lines and the whole text, unseen and at the same width, open or not: whether they cut it short and how tall it opens.
            ZStack(alignment: .topLeading) {
                words.lineLimit(lines).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                words.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .accessibilityHidden(true)
        }
        .onChange(of: fullHeight) { changed?() }
        // Other words in the same place start closed.
        .onChange(of: text) { open = nil }
    }

    private var words: some View {
        Text(verbatim: text).font(font).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

extension EnvironmentValues {
    /// Long text opened from the start: for snapshots, which can't click Show all.
    @Entry var opensLongText = false
}
