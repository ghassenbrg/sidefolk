#if DEBUG
import SidefolkCore
import SwiftUI

/// WhenField in each state it can be in, for UI snapshots: empty, a typed time, a repeat, a time that passed, words it
/// can't read, and a picked time.
struct WhenFieldSamples: View {
    var parser: WhenParser
    @State private var texts = ["", "tomorrow 9", "every day at 8", WhenText.phrase(for: Date().addingTimeInterval(-3600)), "after the meeting",
                                WhenText.phrase(for: WhenPicker.nextHour(.autoupdatingCurrent).addingTimeInterval(2 * 86400))]
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(texts.indices, id: \.self) { i in
                WhenField(text: $texts[i], prompt: Text("When, like “tomorrow 9:00”"), parser: parser, focus: $focus, focusValue: i,
                          emptyHint: i == 0 ? Text("Leave empty to keep \(TimeFormat.when(Date(), now: Date(), calendar: .current))") : nil)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface)
    }
}
#endif
