import SidefolkCore
import SwiftUI

/// Today at a glance, Ask's Today tab (D58, D88): what needs you (answered here as on Today, a watch's notice among
/// them), the next two things in your day, and the way to Today. Who's working isn't listed: the agents' faces beside
/// the companion, On duty and the Pocket already show them.
struct Glance: Equatable {
    struct Next: Equatable {
        var title: String
        var at: Date
        var event: Bool
    }

    var decisions: [AttentionItem] = []
    /// Sessions waiting for the person, one line per agent and folder.
    var sessions: [AgentSessionGroup] = []
    var next: [Next] = []

    var isEmpty: Bool { decisions.isEmpty && sessions.isEmpty && next.isEmpty }

    /// How many each part shows, so the panel stays small.
    static let decisionsShown = 3
    static let nextShown = 2
}

struct GlanceView: View {
    var glance: Glance
    /// How many wait in all, for "Needs you · 3".
    var waiting: Int
    var answer: (AttentionItem, String?) -> Void
    var openSession: (AgentSession) -> Void
    var openToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !glance.sessions.isEmpty || !glance.decisions.isEmpty {
                HStack {
                    Eyebrow(Text("Needs you · \(max(waiting, glance.sessions.count + glance.decisions.count))",
                                 comment: "Ask's resting state: how many things wait on the person"))
                    Spacer()
                    Button(action: openToday) { Text("Open Today") }.buttonStyle(.sf(.quiet, size: .small))
                }
                ForEach(glance.sessions.prefix(Glance.decisionsShown)) { group in
                    row(Text(Describe.session(group)), avatar: "byte") {
                        Button("Open session") { openSession(group.session) }.buttonStyle(.sf(.secondary, size: .small)).fixedSize()
                    }
                }
                ForEach(glance.decisions.prefix(max(0, Glance.decisionsShown - glance.sessions.count))) { item in
                    row(Text(verbatim: item.title), avatar: SidecardItemCard.folk(item)) {
                        if let primary = item.actions.first(where: \.isPrimary) {
                            Button { answer(item, primary.id) } label: { Text(verbatim: primary.title) }
                                .buttonStyle(.sf(.primary, size: .small)).fixedSize()
                        }
                        Button { answer(item, nil) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.sf(.plain, size: .small)).foregroundStyle(Theme.inkFaint)
                            .accessibilityLabel("Dismiss")
                    }
                }
            }
            if !glance.next.isEmpty {
                Eyebrow(Text("Next up", comment: "Ask's resting state: what comes next in the day")).padding(.top, Theme.Space.s)
                ForEach(Array(glance.next.prefix(Glance.nextShown).enumerated()), id: \.offset) { _, next in
                    row(Text(verbatim: next.title), symbol: next.event ? "calendar" : "alarm") {
                        Text(verbatim: "\(TimeFormat.clock(next.at, calendar: .current)) · \(TimeText.relative(next.at))")
                            .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).monospacedDigit()
                    }
                }
            }
        }
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }

    private func row(_ title: Text, avatar: String? = nil, symbol: String? = nil, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Theme.Space.s) {
            if let avatar {
                FolkAvatar(name: avatar, size: Theme.Size.avatarSmall)
            } else {
                Image(systemName: symbol ?? "bell").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    .frame(width: Theme.Size.avatarSmall, height: Theme.Size.avatarSmall)
                    .background(Theme.well, in: Circle())
                    .accessibilityHidden(true)
            }
            title.font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.xs)
            trailing()
        }
        .frame(minHeight: Theme.Size.compactRow)
    }
}
