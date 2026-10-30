import SidefolkCore
import SwiftUI

/// Today at a glance, in the Ask panel while nothing is typed (D58): a click on the companion opens it. What needs you
/// (answered here as on Today, a watch's notice among them), the next two things in your day, who's working, and the
/// way to Today.
struct Glance: Equatable {
    struct Next: Equatable {
        var title: String
        var at: Date
        var event: Bool
    }

    var decisions: [AttentionItem] = []
    var sessions: [AgentSession] = []
    var next: [Next] = []
    var working: [String] = []

    var isEmpty: Bool { decisions.isEmpty && sessions.isEmpty && next.isEmpty && working.isEmpty }

    /// How many each part shows, so the panel stays small.
    static let decisionsShown = 3
    static let nextShown = 2
}

struct GlanceView: View {
    var glance: Glance
    var answer: (AttentionItem, String?) -> Void
    var openSession: (AgentSession) -> Void
    var openToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(glance.sessions.prefix(Glance.decisionsShown)) { session in
                row("hand.raised", Text(Describe.session(session))) {
                    Button("Open session") { openSession(session) }.buttonStyle(.sf(.secondary, compact: true)).fixedSize()
                }
            }
            ForEach(glance.decisions.prefix(max(0, Glance.decisionsShown - glance.sessions.count))) { item in
                row("bell", Text(verbatim: item.title)) {
                    if let primary = item.actions.first(where: \.isPrimary) {
                        Button { answer(item, primary.id) } label: { Text(verbatim: primary.title) }
                            .buttonStyle(.sf(.primary, compact: true)).fixedSize()
                    }
                    Button { answer(item, nil) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
                        .accessibilityLabel("Dismiss")
                }
            }
            ForEach(Array(glance.next.prefix(Glance.nextShown).enumerated()), id: \.offset) { _, next in
                row(next.event ? "calendar" : "alarm",
                    Text(verbatim: "\(TimeFormat.clock(next.at, calendar: .current))  \(next.title)")) { EmptyView() }
            }
            ForEach(glance.working, id: \.self) { title in
                row("sparkles", Text(verbatim: title)) { EmptyView() }
            }
            Button(action: openToday) { Label("Open Today", systemImage: "sun.max") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(Theme.Font.caption)
        }
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }

    private func row(_ symbol: String, _ title: Text, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 16).accessibilityHidden(true)
            title.font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.xs)
            trailing()
        }
    }
}
