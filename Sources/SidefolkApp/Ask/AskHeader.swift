import SidefolkCore
import SwiftUI

/// What Ask shows under its field (D84): the conversation, or a compact Today. An extension's tab opens what it says in Ask's place
/// (one panel at a time), so it is never a state of its own here.
enum AskTab: Hashable {
    case ask, today
    /// A tab an extension declares (D100): it opens what the entry says, in Ask's place.
    case entry(String)
}

/// Ask's header (D84): who you talk to, how much Sidefolk asks, the way home and to Settings; under it the tabs,
/// and for an AI conversation when it happened with the way to it in History.
struct AskHeader: View {
    @Bindable var model: AskModel
    var companionName: String
    var portrait: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                if let portrait {
                    // Already round: a profile picture, or the drawn face on its disc (CompanionArt.avatar).
                    Image(nsImage: portrait).resizable().frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                        .padding(.trailing, Theme.Space.xs)
                }
                Text(companionName).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    .layoutPriority(1)
                ModeChip(mode: model.mode) { model.actions?.openSettings(tab: .privacy) }
                    .padding(.leading, Theme.Space.xs)
                Spacer(minLength: Theme.Space.xs)
                button("house", help: "Open Sidefolk") { model.actions?.openHome() }
                button("gearshape", help: "Settings") { model.actions?.openSettings(tab: nil) }
                button("xmark", help: "Close") { model.onClose?() }
            }
            HStack(spacing: Theme.Space.s) {
                SegmentedPicker(Text("Show", comment: "Ask's tabs, for VoiceOver: the conversation, Today or Play"),
                                selection: Binding(get: { model.tab }, set: choose), segments: tabs, small: true)
                    .fixedSize()
                Spacer(minLength: Theme.Space.xs)
                if model.tab == .ask, let thread = model.thread, let at = model.threadAnsweredAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        historyLink(thread: thread, said: Self.when(at, now: context.date))
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
    }

    private var tabs: [SegmentedPicker<AskTab>.Segment] {
        let waiting = max(model.waiting, model.glance.decisions.count + model.glance.sessions.count)
        let today = waiting > 0 ? Text("Today") + Text(verbatim: " \(waiting.formatted())") : Text("Today")
        return [.init(.ask, Text("Ask", comment: "Ask's tab: the conversation")),
                .init(.today, today)]
            // Anyone but Sidefolk's own says whose it is, as in the menus (T41).
            + entries.map { .init(.entry($0.id), Text(ext: $0.shownTitle), symbol: $0.symbol) }
    }

    /// Two at most: the row stays one row whichever extensions are on.
    private var entries: [ExtensionEntry] { Array(model.entryTabs.prefix(2)) }

    private func choose(_ tab: AskTab) {
        switch tab {
        case .entry(let id): entries.first { $0.id == id }.map { model.actions?.open($0) }
        case .ask, .today: model.tab = tab
        }
    }

    /// "Just now · Open in History": when the AI last answered in this conversation, and the way to all of it.
    private func historyLink(thread: String, said: String) -> some View {
        Button { model.actions?.openConversation(thread) } label: {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: "\(said) · ") + Text("Open in History", comment: "Ask's header: opens this conversation in Home › History")
                Text("Open in History", comment: "Ask's header: opens this conversation in Home › History")
            }
            .font(Theme.Font.callout)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.link)
        .help(Text("Open this conversation in History", comment: "Ask's header: the tooltip of Open in History"))
    }

    /// "Just now" for the last minute, then "5 min ago".
    static func when(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? String(localized: "Just now", comment: "Ask's header: the AI answered less than a minute ago")
            : TimeText.relative(date, now: now)
    }

    private func button(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).imageScale(.small) }
            .buttonStyle(.sf(.plain))
            .help(help)
            .accessibilityLabel(help)
    }
}

/// Ask's Today tab (D84): what needs you and what's next, as Glance has them, with the way to Today.
struct AskTodayTab: View {
    var model: AskModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if model.glance.isEmpty {
                Text("Nothing needs you, and nothing else is coming up today.", comment: "Ask's Today tab when it is empty")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.xs)
            } else {
                GlanceView(glance: model.glance, waiting: model.waiting,
                           answer: { item, action in
                               if let action { model.actions?.answer(question: item, actionId: action) } else { model.actions?.dismissAttention(item) }
                           },
                           openSession: { model.actions?.openSession($0) },
                           openToday: { model.actions?.openNow() })
            }
            // Glance has the way to Today beside "Needs you"; without that line it goes here.
            if model.glance.decisions.isEmpty, model.glance.sessions.isEmpty {
                Button { model.actions?.openNow() } label: { Text("Open Today") }
                    .buttonStyle(.sf(.quiet, size: .small))
            }
        }
    }
}
