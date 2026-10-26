import SwiftUI

/// Buttons side by side while they fit, stacked when a language makes them longer, so a button is
/// never cut off. German cut "Allow for this request" to "Für diese Anfrage erlau…" on an approval card.
struct ButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}
