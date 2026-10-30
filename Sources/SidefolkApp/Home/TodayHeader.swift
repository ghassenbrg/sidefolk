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

/// The companion in Home's sidebar (D58): its face, its name and one line about what it's keeping track of; asleep
/// while quiet mode is on, as on the desktop.
struct CompanionNook: View {
    var settings: AppSettings
    var line: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            CompanionPortrait(settings: settings, state: settings.isQuiet(at: Date()) ? .sleeping : .idle, side: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: settings.companionName).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(verbatim: line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s)
        .background(Theme.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Today"))
    }
}
