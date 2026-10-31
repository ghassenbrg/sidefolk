import SidefolkCore
import SwiftUI

/// Home › Today (D84): the day first. A brief (a greeting and one sentence made of what the app knows), the day as a
/// line, then what needs the person (three at most in view, the rest folded) beside a glance at what's on duty, and
/// what was captured today. One layout in every theme (D84 narrows D64); the columns stack in a narrow window.
struct TodayView: View {
    var model: HomeModel
    /// The queue card the keyboard is on (D58).
    @FocusState private var focused: String?
    @State private var editing: Reminder?
    /// The folded part of the queue is open.
    @State private var showAll = false
    /// While Quiet is on the queue is held in one card; the person may open it anyway.
    @State private var showHeld = false

    private var now: NowModel { model.now }

    var body: some View {
        HomePage {
            if now.mode == .fullAccess {
                FullAccessBanner(settings: { model.services.openSettings(tab: .privacy) }) { Task { await now.turnOffFullAccess() } }
            }
            brief
            DayCard(model: now, edit: { editing = $0 }) { model.selection = .calendar }
            if firstDay {
                Starters { words in model.find.query = words }
            } else {
                ColumnsLayout(widths: [1.75, 1], spacing: Theme.Size.columnGap, minimums: [380, 260]) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) { needsYou }
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        OnDutyGlance(model: model)
                        if !now.widgets.isEmpty { ExtensionWidgetsSection(model: now) }
                    }
                }
            }
            if !now.captured.isEmpty { captured }
        }
        .sheet(item: $editing) { EditReminderSheet(reminder: $0, model: now) }
    }

    /// Nothing yet on this Mac: no reminders, watches, notes or questions. Today keeps the day and offers three starts.
    private var firstDay: Bool {
        now.reminders.isEmpty && now.doneToday.isEmpty && now.watchers.isEmpty && now.reports.isEmpty && now.recentNotes.isEmpty
            && now.needsYouCount == 0 && now.workingSessions.isEmpty && now.widgets.isEmpty
    }

    // MARK: The brief

    private var brief: some View {
        WrapRow(minimum: 420, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(verbatim: DayBrief.greeting(at: Date(), name: NowModel.firstName))
                    .font(Theme.Font.display).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                (Text(verbatim: DayBrief.lead(needsYou: now.needsYouCount)).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    + Text(verbatim: " " + DayBrief.detail(next: now.nextUp, changed: now.changedWatches)).foregroundStyle(Theme.inkMuted))
                    .font(.system(size: 15 * ThemeStore.shared.style.tokens.type.scale))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Space.s) {
                CountTile(count: now.needsYouCount, label: Text("need you", comment: "Today's count: things that wait on the person"), dot: Theme.waitGlow)
                CountTile(count: model.onDutyRunning,
                          label: Text("on duty", comment: "Today's count: things working for the person"), dot: Theme.glow) {
                    model.selection = .onDuty
                }
                CountTile(count: now.doneCount, label: Text("done today", comment: "Today's count: things done today"), dot: Theme.success) {
                    model.selection = .history
                }
            }
            .fixedSize()
        }
    }

    // MARK: Needs you

    @ViewBuilder private var needsYou: some View {
        let queue = now.queue
        SectionHeader(title: Text("Needs you"), count: queue.count) {
            if !queue.isEmpty && !now.quiet {
                HStack(spacing: Theme.Space.s) {
                    KeyHint("↑ ↓")
                    Text("to move").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                    KeyHint("↩")
                    Text("to answer").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                .fixedSize()
                .help(Text("Up and down move between them. Return answers yes or does the main action, Delete says not now, S snoozes a reminder."))
            }
        }
        if queue.isEmpty {
            AllClear(model: now)
        } else if now.quiet && !showHeld {
            HeldCard(queue: queue, until: now.quietUntil) { showHeld = true }
        } else {
            let shown = showAll ? queue : Array(queue.prefix(3))
            ForEach(shown) { decision in
                QueueRow(decision: decision, model: now, focused: $focused, style: "card") { work in act(on: decision, work) }
            }
            if queue.count > 3 {
                FoldedQueue(rest: Array(queue.dropFirst(3)), open: showAll, model: now) { showAll.toggle() }
            }
            if let result = now.skippedRun { RowsCard { SkippedRunResult(result: result) } }
        }
    }

    /// Runs an answer, then keeps the keyboard where it was in the queue: on the next one, or the last.
    private func act(on decision: NowModel.Decision, _ work: @escaping () async -> Void) {
        let index = now.queue.firstIndex { $0.id == decision.id } ?? 0
        let hadFocus = focused != nil
        Task {
            await work()
            let queue = now.queue
            if hadFocus { focused = queue.isEmpty ? nil : queue[min(index, queue.count - 1)].id }
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
                    .buttonStyle(.plain)
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

/// One of the brief's three counts: a dot of light, the number, and what it counts. A click goes where they are.
private struct CountTile: View {
    var count: Int
    var label: Text
    var dot: Color
    var action: (() -> Void)?

    var body: some View {
        let tile = HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(dot).frame(width: 9, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 0) {
                Text(count > 99 ? "99+" : count.formatted()).font(Theme.Font.number).monospacedDigit().foregroundStyle(Theme.ink)
                label.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(minWidth: 108, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        if let action {
            Button(action: action) { tile.contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            tile
        }
    }
}

/// Today's day (D58, D84): the line from morning to evening with the calendar's events and the reminders, the done ones
/// struck through, and the way to the Calendar. Tomorrow is the Calendar's Agenda now.
struct DayCard: View {
    var model: NowModel
    var edit: (Reminder) -> Void
    var openCalendar: () -> Void

    var body: some View {
        let today = model.groups().first { $0.day == .today }?.reminders ?? []
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            WrapRow(minimum: 160, spacing: Theme.Space.s) {
                Text("Your day").font(Theme.Font.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                HStack(spacing: Theme.Space.m) {
                    if model.calendarOn { legend(Text("Calendar"), Theme.folkColor("tempo")) }
                    legend(Text("Reminders"), Theme.folkColor("byte"))
                    Button("Open Calendar", action: openCalendar).buttonStyle(.sf(.quiet))
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            DayRail(reminders: today, done: model.doneToday, events: model.events(on: .today), now: Date(),
                    move: { reminder, date in await model.move(reminder, to: date) }, add: { model.newReminder(at: $0) },
                    menu: { AnyView(ReminderMenu(reminder: $0, model: model, edit: edit)) })
            if !model.calendarOn {
                InlineEmpty(text: "Show your Mac calendar here too, beside your reminders.", systemImage: "calendar",
                            actionTitle: "Allow") { Task { await model.showCalendar() } }
            }
            if today.isEmpty && model.doneToday.isEmpty && model.events(on: .today).isEmpty {
                NewReminderRow(model: model)
            }
        }
        .cardSurface()
    }

    private func legend(_ title: Text, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            title.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// A card of what needs the person (D84): a bar of amber along the leading edge, who asks with their avatar and when,
/// then the card's own words and buttons; the keyboard's ring while it has the keyboard.
struct NeedsYouCard<Content: View>: View {
    var source: String
    var folk: String
    var at: Date
    var tint: Color
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            FolkAvatar(name: folk, size: Theme.Size.avatar)
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
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(focused ? Theme.accent : .clear, lineWidth: 2)
        }
        .elevation(.e1, radius: Theme.Radius.card)
    }
}

/// The queue past its first three (A1): who else waits, in one sentence, and Show all.
private struct FoldedQueue: View {
    var rest: [NowModel.Decision]
    var open: Bool
    var model: NowModel
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: -8) {
                ForEach(Array(Set(rest.map(folk)).sorted().prefix(3)), id: \.self) { FolkAvatar(name: $0, size: 26) }
            }
            (open ? Text("Showing all \(rest.count + 3).", comment: "Today's queue, unfolded")
                 : Text("\(rest.count) more can wait: \(names)", comment: "Today's queue, folded: “4 more can wait: Read the clipboard, Skipped, a reminder”"))
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                open ? Text("Show fewer") : Text("Show all \(rest.count + 3)", comment: "Today's queue, folded: shows every card")
            }
            .buttonStyle(.sf(.quiet))
            .fixedSize()
        }
        .padding(Theme.Space.m)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.controlBorder.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var names: String {
        rest.prefix(4).map { decision -> String in
            switch decision {
            case .approval(let r): r.title
            case .session(let s): Describe.session(s)
            case .attention(let a): a.title
            case .skipped(let s): s.request.title
            }
        }.formatted(.list(type: .and))
    }

    private func folk(_ decision: NowModel.Decision) -> String {
        switch decision {
        case .approval, .skipped: "guard"
        case .session: "byte"
        case .attention(let a): a.refKind == "watcher" ? "scout" : a.refKind == "reminder" ? "tempo" : "pip"
        }
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
