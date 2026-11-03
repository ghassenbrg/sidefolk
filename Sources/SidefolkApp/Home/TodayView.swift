import SidefolkCore
import SwiftUI

/// Home › Today (D130): a brief (a greeting and one sentence made of what the app knows) over the theme's scene, then one
/// decision in view with the rest under Next up, beside the day as a list and what's on duty, and what was captured today.
/// One layout in every theme (D84 narrows D64); the columns stack in a narrow window.
struct TodayView: View {
    var model: HomeModel
    /// The queue card the keyboard is on (D58).
    @FocusState private var focused: String?
    @State private var editing: Reminder?
    /// While Quiet is on the queue is held in one card; the person may open it anyway.
    @State private var showHeld = false

    private var now: NowModel { model.now }

    var body: some View {
        HomePage {
            if now.mode == .fullAccess {
                FullAccessBanner(settings: { model.services.openSettings(tab: .privacy) }) { Task { await now.turnOffFullAccess() } }
            }
            brief
            AddonUpdatesTodayRow(updates: model.services.updates)
            ColumnsLayout(widths: [1.75, 1], spacing: Theme.Size.columnGap, minimums: [380, 260]) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if firstDay {
                        Starters { words in model.find.query = words }
                    } else {
                        needsYou
                        if !now.kept.isEmpty { keptForToday }
                    }
                    if !now.captured.isEmpty { captured }
                }
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    DayAgenda(model: now, edit: { editing = $0 }) { model.selection = .calendar }
                    if !firstDay {
                        OnDutyGlance(model: model)
                        if !now.widgets.isEmpty { ExtensionWidgetsSection(model: now) }
                    }
                }
            }
        }
        .environment(\.pageHasScene, true)
        .environment(\.plainSlipStrip, true)
        .sheet(item: $editing) { EditReminderSheet(reminder: $0, model: now) }
    }

    /// Nothing yet on this Mac: no reminders, watches, notes or questions. Today keeps the day and offers three starts.
    private var firstDay: Bool {
        now.reminders.isEmpty && now.doneToday.isEmpty && now.watchers.isEmpty && now.reports.isEmpty && now.recentNotes.isEmpty
            && now.needsYouCount == 0 && now.kept.isEmpty && now.workingSessions.isEmpty && now.widgets.isEmpty
    }

    // MARK: The brief

    private var brief: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(verbatim: DayBrief.greeting(at: Date(), name: NowModel.firstName))
                .font(Theme.Font.greeting).foregroundStyle(Theme.sceneInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .homePageTitle()
                // A share of the page, never all of it: the container includes the page's side padding, so its full width
                // pushed Today wider than the window, and the sidebar with it.
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * (hasScene ? 0.62 : 0.8) }
            (Text(verbatim: DayBrief.lead(needsYou: now.needsYouCount)).fontWeight(.semibold).foregroundStyle(Theme.sceneInk)
                + Text(verbatim: " " + DayBrief.detail(next: now.nextUp, changed: now.changedWatches)).foregroundStyle(Theme.sceneInkMuted))
                .font(.system(size: 15 * ThemeStore.shared.style.tokens.type.scale))
                .fixedSize(horizontal: false, vertical: true)
                // Words stay over the scene's empty side, however long they run in any language (D130).
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(560, width * (hasScene ? 0.46 : 0.8)) }
        }
    }

    private var hasScene: Bool { ThemeStore.shared.style.tokens.material.scene }

    // MARK: Needs you

    @ViewBuilder private var needsYou: some View {
        let queue = now.todayQueue
        if queue.isEmpty {
            AllClear(model: now)
        } else if now.quiet && !showHeld {
            HeldCard(queue: queue, until: now.quietUntil) { showHeld = true }
        } else {
            QueueRow(decision: queue[0], model: now, focused: $focused, style: "card") { work in act(on: queue[0], work) }
                .id(queue[0].id)
            if queue.count > 1 {
                HStack(spacing: Theme.Space.s) {
                    Text("Next up", comment: "Today: what waits after the decision in view").font(Theme.Font.headline).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: (queue.count - 1).formatted()).font(Theme.Font.callout).monospacedDigit().foregroundStyle(Theme.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    KeyHint("↑ ↓")
                    Text("to move").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                    KeyHint("↩")
                    Text("to answer").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                .padding(.top, Theme.Space.s)
                .help(Text("Up and down move between them. Return answers yes or does the main action, Delete says not now, S snoozes a reminder."))
                RowsCard {
                    ForEach(queue.dropFirst()) { decision in
                        NextUpRow(decision: decision, model: now, focused: $focused) {
                            now.forwardDecision = decision.id
                            focused = decision.id
                        }
                    }
                }
            }
            if let result = now.skippedRun { RowsCard { SkippedRunResult(result: result) } }
        }
    }

    /// Runs an answer, then keeps the keyboard where it was in the queue: on the next one, or the last.
    private func act(on decision: NowModel.Decision, _ work: @escaping () async -> Void) {
        let index = now.todayQueue.firstIndex { $0.id == decision.id } ?? 0
        let hadFocus = focused != nil
        Task {
            await work()
            let queue = now.todayQueue
            if hadFocus { focused = queue.isEmpty ? nil : queue[min(index, queue.count - 1)].id }
        }
    }

    // MARK: Kept for Today

    /// News from sources set to Only in Today (Settings › Attention, D88): never on the desktop, here until dismissed.
    private var keptForToday: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: Text("Kept for Today", comment: "Today: notices Settings › Attention keeps off the desktop"),
                          count: now.kept.count,
                          detail: Text("Settings › Attention keeps these off the desktop.", comment: "Under Today's Kept for Today")) {
                Button { model.services.openSettings(tab: .attention) } label: { Text("Change", comment: "Opens Settings › Attention from Today") }
                    .buttonStyle(.sf(.quiet))
            }
            RowsCard {
                ForEach(now.kept) { item in
                    AttentionRow(item: item) { action in Task { await now.respond(item, action: action) } }
                }
            }
        }
    }

    // MARK: Captured today

    private var captured: some View {
        WrapRow(minimum: 160, spacing: Theme.Space.m) {
            Text("Captured today").font(Theme.Font.headline).foregroundStyle(Theme.inkMuted).fixedSize()
            ButtonRow(spacing: Theme.Space.s) {
                ForEach(now.captured) { item in
                    Button { now.open(item) } label: {
                        HStack(spacing: Theme.Space.s) {
                            if let c = now.noteCollections[item.collectionId] { CollectionTile(collection: c, size: 18) }
                            Text(verbatim: item.title.isEmpty ? String(localized: "Untitled") : item.title).font(Theme.Font.body)
                                .foregroundStyle(Theme.ink).lineLimit(1)
                            Text(verbatim: Describe.source(item.source) ?? String(localized: "you", comment: "Who saved a note: the person"))
                                .font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .frame(height: 30)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line))
                        .frame(maxWidth: 320)
                    }
                    .buttonStyle(.sfBare)
                }
            }
        }
    }
}

/// A place's scrolling page in Home (D84): content at most 1080 wide, centred, 32 at the sides (24 in a narrow
/// window), on the canvas.
struct HomePage<Content: View>: View {
    var maxWidth: CGFloat = Theme.Size.contentMaxWidth
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 1000

    var body: some View {
        PageScroll(maxWidth: maxWidth, padding: width < 900 ? Theme.Size.contentPaddingNarrow : Theme.Size.contentPadding) {
            content
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}



/// A card of what needs the person (D84): a bar of amber along the leading edge, who asks with their avatar and when,
/// then the card's own words and buttons; the keyboard's ring while it has the keyboard.
struct NeedsYouCard<Content: View>: View {
    var source: String
    /// The helper who brings it; nil when the companion says it itself (what waited, its own notices).
    var folk: String?
    var settings: AppSettings?
    var at: Date
    var tint: Color
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            if let folk { FolkAvatar(name: folk, size: Theme.Size.avatar) } else if let settings { CompanionAvatar(settings: settings) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(verbatim: "\(source) · \(TimeFormat.clock(at, calendar: .current))")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.l)
        .padding(.leading, 3)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contrastEdge(radius: Theme.Radius.card)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(focused ? Theme.accent : .clear, lineWidth: 2)
        }
        .elevation(.e1, radius: Theme.Radius.card)
    }
}


/// Quiet on (A1's Focus state): the queue held in one card, saying what waits and until when, with the way in.
private struct HeldCard: View {
    var queue: [NowModel.Decision]
    var until: Date?
    var show: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: Theme.Symbol.quiet).font(.system(size: 18)).foregroundStyle(Theme.melody)
                .frame(width: Theme.Size.avatar, height: Theme.Size.avatar)
                .background(Theme.melody.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                if let until {
                    Text("\(queue.count) things wait until \(TimeFormat.clock(until, calendar: .current))",
                         comment: "Today while Quiet is on: the queue is held").font(Theme.Font.headline).foregroundStyle(Theme.ink)
                }
                Text("Quiet is on: only urgent things reach you. They're all here when you're ready.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show them", action: show).buttonStyle(.sf(.secondary))
        }
        .padding(Theme.Space.l)
        .cardSurface()
    }
}

/// Nothing needs the person (A1's all clear): one calm line, and what comes next.
private struct AllClear: View {
    var model: NowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                HStack(spacing: -8) { ForEach(["tempo", "scout", "byte"], id: \.self) { FolkAvatar(name: $0, size: 28) } }
                Text("All clear. Nothing waits on you.").font(Theme.Font.headline).foregroundStyle(Theme.ink)
            }
            if let next = model.nextUp {
                Divider()
                HStack {
                    Text("Coming up").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                    Text(verbatim: next.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(verbatim: TimeFormat.clock(next.at, calendar: .current)).font(Theme.Font.callout.monospacedDigit()).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .padding(Theme.Space.l)
        .cardSurface()
    }
}

/// A first day (A1): three things to try, each put in the Say bar for a look before anything happens.
private struct Starters: View {
    var put: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("Start here"), detail: Text("Each one shows what will happen before it does."))
            RowsCard {
                row("bell", Text("Set a reminder"), "remind me at 5 to stretch", primary: true)
                row("note.text", Text("Keep a note"), "add oat milk to groceries", primary: false)
                row("binoculars", Text("Watch a page"), "tell me when example.com changes", primary: false)
            }
        }
    }

    private func row(_ symbol: String, _ title: Text, _ words: String, primary: Bool) -> some View {
        ListRow(title: title, meta: Text(verbatim: "“\(words)”")) {
            SidebarSquircle(symbol: symbol, color: Theme.link, size: Theme.Size.rowIcon)
        } trailing: {
            Button("Try it") { put(words) }.buttonStyle(.sf(primary ? .primary : .secondary)).fixedSize()
        }
    }
}
