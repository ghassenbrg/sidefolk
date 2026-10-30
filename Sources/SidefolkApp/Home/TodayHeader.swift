import SidefolkCore
import SwiftUI

/// The top of Today (D58): the day, a greeting and what's left in one line, beside your companion and the way to ask
/// it something. One line instead of a large card, so the queue under it is in view when the window opens.
struct TodayHeader: View {
    var greeting: Text
    var status: Text
    var settings: AppSettings
    var ask: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Eyebrow(Text(verbatim: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))))
                greeting.font(Theme.Font.title).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                status.font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button(action: ask) {
                Label("Ask \(settings.companionName)…", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.sf(.secondary))
            .fixedSize()
            CompanionPortrait(settings: settings, side: 64)
                .accessibilityHidden(true)
        }
        .padding(.bottom, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }
}
