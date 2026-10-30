import SidefolkCore
import SwiftUI

/// Home › Today, drawn from the theme's layout (D64): rows of columns of blocks, each one of Today's pieces in one of
/// its styles. Harbor's is the Desk: decisions and the day on the left; what's watched, who's working and what just
/// happened on the right. Columns stack when the window is narrow.
/// Each domain wears its folk's color: Tempo for time, Scout for watching, Byte for agents and jobs.
struct NowView: View {
    @Bindable var model: NowModel
    /// The queue row the keyboard is on (D58).
    @FocusState private var focused: String?
    @State private var editing: Reminder?

    private var layout: ThemeLayout { ThemeStore.shared.style.tokens.layout }

    var body: some View {
        PageScroll(maxWidth: 1180) {
            if model.mode == .fullAccess {
                FullAccessBanner(settings: { model.services.openSettings(tab: .privacy) }) { Task { await model.turnOffFullAccess() } }
            }
            ForEach(Array(layout.today.enumerated()), id: \.offset) { _, row in
                ColumnsLayout(widths: row.map(\.width), spacing: Theme.Space.l,
                              minimums: row.map { $0.blocks.allSatisfy { $0.kind == .art } ? 150 : 230 }) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, column in
                        let blocks = VStack(alignment: .leading, spacing: Theme.Space.xl) {
                            ForEach(column.blocks.filter(shows), id: \.self) { block($0) }
                        }
                        if column.page { PaperPage { blocks } } else { blocks }
                    }
                }
            }
        }
        .sheet(item: $editing) { EditReminderSheet(reminder: $0, model: model) }
    }

    /// The Console's filter (D64): agents, your own, or watches, with the header and what needs you always there.
    private func shows(_ block: ThemeLayout.Block) -> Bool {
        switch model.focus {
        case .all: true
        case .agents: [.header, .queue, .agents].contains(block.kind)
        case .mine: [.header, .queue, .day, .notes, .companion].contains(block.kind)
        case .watches: [.header, .queue, .watching].contains(block.kind)
        }
    }

    /// One of Today's pieces in its style. Only styles the theme check lets through reach here.
    @ViewBuilder private func block(_ block: ThemeLayout.Block) -> some View {
        switch block.kind {
        case .header:
            switch block.style {
            case "console": ConsoleHeader(model: model)
            case "page": PageHeader(model: model)
            default: TodayHeader(greeting: TodayHeader.greeting(), line: model.headline, large: block.style == "large")
            }
        case .queue:
            if model.needsYouCount > 0 || model.skippedRun != nil {
                needsYou(block.style)
            } else if block.style == "stack" || block.style == "index" {
                // A column of its own stays, saying so, rather than leaving a gap.
                emptyQueue(block.style)
            }
        case .day:
            switch block.style {
            case "list": DayList(model: model) { editing = $0 }
            case "compact": DayCompact(model: model) { editing = $0 }
            case "stickers": DayStickers(model: model) { editing = $0 }
            case "ruled": RuledDay(model: model) { editing = $0 }
            default: comingUp
            }
        case .watching:
            switch block.style {
            case "list": WatchingList(model: model)
            case "signals": WatchSignals(model: model)
            case "badges": WatchBadges(model: model)
            case "margin": MarginWatches(model: model)
            default: watching
            }
        case .agents:
            switch block.style {
            case "card": AgentsCard(model: model)
            case "steps": AgentSteps(model: model)
            case "helpers": HelpersCard(model: model)
            default: running
            }
        case .recent: if !model.recent.isEmpty { recently }
        case .notes:
            if block.style == "chips" { JottedChips(model: model) } else { NotesCards(model: model) }
        case .art: ArtTile()
        case .companion:
            if block.style == "sticker" {
                CompanionSticker(model: model)
            } else {
                TodayStage(model: model) { decision in
                    QueueRow(decision: decision, model: model, focused: $focused, style: "bubbles") { work in act(on: decision, work) }
                }
            }
        }
    }

    // MARK: Needs you

    @ViewBuilder private func emptyQueue(_ style: String) -> some View {
        if style == "index" {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("To decide").font(.system(size: 17, design: .serif)).italic().foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text("Nothing to decide.").font(.system(size: 14, design: .serif)).italic().foregroundStyle(Theme.inkMuted)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ConsoleTitle(title: "Queue", count: 0, note: nil)
                Text("Nothing waits on you.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    @ViewBuilder private func needsYou(_ style: String) -> some View {
        if style == "index" {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("To decide").font(.system(size: 17, design: .serif)).italic().foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                ForEach(model.focusedQueue) { decision in
                    QueueRow(decision: decision, model: model, focused: $focused, style: "index") { work in act(on: decision, work) }
                }
                if let result = model.skippedRun { RowsCard { SkippedRunResult(result: result) } }
            }
        } else if style == "stack" {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ConsoleTitle(title: "Queue", count: model.focusedQueue.count, note: Text("j/k move · ⏎ allow · ⌫ deny · s snooze"))
                ForEach(model.focusedQueue) { decision in
                    QueueRow(decision: decision, model: model, focused: $focused, style: "stack") { work in act(on: decision, work) }
                }
                if let result = model.skippedRun { RowsCard { SkippedRunResult(result: result) } }
            }
        } else {
            needsYouList(style)
        }
    }

    private func needsYouList(_ style: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Needs you", folk: nil, count: model.needsYouCount) {
                // The keys work on the row the keyboard is on; Tab gets there.
                Group {
                    if style == "cards" { Text("← → move · ⏎ answer · ⌫ not now") } else { Text("↑↓ to move · ⏎ to answer") }
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.link)
                .help(Text("Up and down move between them. Return answers yes or does the main action, Delete says not now, S snoozes a reminder."))
            }
            if style == "cards" {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        ForEach(model.focusedQueue) { decision in
                            QueueRow(decision: decision, model: model, focused: $focused, style: "cards") { work in act(on: decision, work) }
                        }
                    }
                    .padding(2)
                }
                if let result = model.skippedRun { RowsCard { SkippedRunResult(result: result) } }
            } else {
                RowsCard {
                    ForEach(model.focusedQueue) { decision in
                        QueueRow(decision: decision, model: model, focused: $focused) { work in act(on: decision, work) }
                    }
                    if let result = model.skippedRun {
                        SkippedRunResult(result: result)
                    }
                }
            }
        }
    }

    /// Runs an answer, then keeps the keyboard where it was in the queue: on the next one, or the last.
    private func act(on decision: NowModel.Decision, _ work: @escaping () async -> Void) {
        let index = model.focusedQueue.firstIndex { $0.id == decision.id } ?? 0
        let hadFocus = focused != nil
        Task {
            await work()
            let queue = model.focusedQueue
            if hadFocus { focused = queue.isEmpty ? nil : queue[min(index, queue.count - 1)].id }
        }
    }

    // MARK: Your day

    private var comingUp: some View {
        let groups = model.groups()
        let today = groups.first { $0.day == .today }?.reminders ?? []
        let tomorrow = groups.first { $0.day == .tomorrow }?.reminders ?? []
        let later = groups.first { $0.day == .later }?.reminders ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Your day", folk: "tempo", count: model.reminders.count) {
                Text("Drag to move · double-click to add").font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            // Today as a line (D58), with the calendar beside the reminders once it's shown (D57), and tomorrow beside it.
            RowsCard {
                HStack(alignment: .top, spacing: 0) {
                    DayRail(reminders: today, done: model.doneToday, events: model.events(on: .today), now: Date(),
                            move: { reminder, date in await model.move(reminder, to: date) }, add: { model.newReminder(at: $0) },
                            menu: { AnyView(ReminderMenu(reminder: $0, model: model) { editing = $0 }) })
                    if !tomorrow.isEmpty || !later.isEmpty || !model.events(on: .tomorrow).isEmpty {
                        Divider()
                        TomorrowColumn(reminders: tomorrow, events: model.events(on: .tomorrow), later: later, model: model) { editing = $0 }
                            .frame(width: 180, alignment: .topLeading)
                    }
                }
                if !model.calendarOn {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "calendar").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                        Text("Your calendar can be here too, beside your reminders.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: Theme.Space.s)
                        Button("Show my calendar") { Task { await model.showCalendar() } }.buttonStyle(.sf(.secondary)).fixedSize()
                    }
                    .nowRow()
                }
                if model.reminders.isEmpty {
                    InlineEmpty(text: "Nothing scheduled. Try “remind me at 5 to stretch”.", systemImage: "alarm")
                    NewReminderRow(model: model)
                }
            }
        }
    }

    // MARK: Watching

    /// Watches and live values as tiles (D58): what each keeps an eye on, in one big word or number, and what it last
    /// saw. A click shows the whole watch and what can be done with it.
    private var watching: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Watching", folk: "scout", count: model.watchers.count + model.reports.count) {
                if !model.watchers.isEmpty || !model.reports.isEmpty {
                    Button("All") { model.services.openAsk(prefill: "what are you watching") }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
                }
            }
            if model.watchers.isEmpty && model.reports.isEmpty {
                RowsCard {
                    InlineEmpty(text: "Not watching anything. I can tell you when a page changes, a site goes down or a file arrives.",
                                systemImage: "binoculars", actionTitle: "Watch something…") {
                        model.services.openAsk(prefill: "tell me when ")
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.s, alignment: .top)],
                          alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(model.watchers) { w in WatchCard(watcher: w, model: model) }
                    ForEach(model.reports) { r in ReportCard(report: r, reading: model.readings[r.id], values: model.values[r.id] ?? [], model: model) }
                }
            }
        }
    }

    // MARK: Agents at work

    private var agentCount: Int {
        model.workingSessions.count + model.finishedSessions.count + model.jobs.count + (model.ownRun == nil ? 0 : 1)
    }

    /// Who is working right now (D58): your companion, Claude Code and Codex sessions with the last thing each asked
    /// of Sidefolk, commands Sidefolk was asked to keep an eye on, and sessions that finished in the last hour.
    private var running: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Agents at work", folk: "byte", count: agentCount)
            RowsCard {
                if agentCount == 0 {
                    InlineEmpty(text: "Nothing running. Connect Claude Code or Codex to see their sessions here, or start a command with “sidefolk run -- npm test”.",
                                systemImage: "terminal", actionTitle: "Connect your agents…") {
                        model.services.openSettings(tab: .agents)
                    }
                }
                if let own = model.ownRun {
                    RunningRow(symbol: "bubble.left.and.bubble.right", title: own.conversation.map { "\(companion): \($0.title)" } ?? companion,
                               started: own.run.startedAt, detail: own.step?.summary,
                               actionTitle: own.conversation == nil ? nil : "Open conversation") {
                        if let id = own.conversation?.id { model.services.openConversation(id) }
                    }
                }
                ForEach(model.workingSessions) { s in
                    RunningRow(symbol: "sparkles", title: Describe.session(s), started: s.startedAt, detail: lastCall(s) ?? s.detail,
                               actionTitle: "Open session") { model.openSession(s) }
                }
                ForEach(model.jobs) { j in
                    RunningRow(symbol: "terminal", title: j.title, started: j.startedAt,
                               detail: j.cwd.map { String(localized: "in \(FolderAccess.displayPath($0))") }, command: j.command)
                }
                ForEach(model.finishedSessions) { s in
                    FinishedRow(session: s, lastCall: lastCall(s))
                }
            }
        }
    }

    private var companion: String { model.services.runtime.settings.current.companionName }

    /// The last thing a session's agent asked Sidefolk to do, in Activity's words.
    private func lastCall(_ session: AgentSession) -> String? {
        model.lastCalls[session.agent].map { String(localized: "Last: \($0.summary)", comment: "The last thing an agent asked Sidefolk to do") }
    }

    // MARK: Recently

    private var recently: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Recently") {
                Button("Activity") { model.services.openActivity() }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            RowsCard {
                ForEach(model.recent) { e in
                    HStack(spacing: Theme.Space.m) {
                        IconTile(symbol: e.symbol, folk: e.folk, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(e.detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                        Text(TimeText.short(e.date)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s + 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Rows

/// A watch as a tile: what it keeps an eye on, its state, when it last looked, and what it last saw change, with the
/// way to see that change in full. It stands out while what it noticed is still waiting in the queue (D58).
struct WatchTile: View {
    var watcher: Watcher
    var model: NowModel
    @State private var showingChange = false

    var body: some View {
        let kind = Describe.watcherKind(watcher.kind)
        let waiting = model.changeWaiting(for: watcher) != nil
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                IconTile(symbol: kind.symbol, folk: "scout", size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(watcher.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
                    if let target = Describe.watcherTarget(watcher), !watcher.title.contains(target) {
                        Text(target).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: Theme.Space.xs)
                state
            }
            Text(meta(kind)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            if let change = watcher.lastPageChange {
                Button { showingChange = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Changed \(TimeText.short(change.at))").font(Theme.Font.captionStrong)
                            .foregroundStyle(waiting ? Theme.danger : Theme.inkMuted)
                        if let line = change.added.first ?? change.removed.first {
                            Text(verbatim: line).font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("See the change"))
                .popover(isPresented: $showingChange, arrowEdge: .bottom) { ChangeLines(change: change) }
            }
            if watcher.state == .error || watcher.errorCount > 0, let error = watcher.lastError {
                Text(error).font(Theme.Font.caption).foregroundStyle(Theme.danger).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button("Check now") { Task { await model.checkNow(watcher) } }
                    .buttonStyle(.sf(.secondary))
                    .disabled(watcher.state == .paused)
                if watcher.state == .paused {
                    Button("Resume") { Task { await model.resume(watcher) } }.buttonStyle(.sf(.secondary))
                } else {
                    Button("Pause") { Task { await model.pause(watcher) } }.buttonStyle(.sf(.secondary))
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Stop watching", role: .destructive) { Task { await model.stop(watcher) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More for “\(watcher.title)”")
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface()
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(waiting ? Theme.danger.opacity(0.6) : .clear, lineWidth: 1.5))
        .onChange(of: showingChange) { _, open in if open { Task { await model.seen(watcher) } } }
        .accessibilityElement(children: .contain)
    }

    private func meta(_ kind: Describe.WatcherKind) -> String {
        var parts = [kind.label, Describe.interval(watcher.intervalS)]
        if let checked = watcher.lastCheckedAt {
            parts.append(String(localized: "checked \(TimeText.relative(checked))", comment: "“checked 5 min ago”"))
        } else {
            parts.append(String(localized: "not checked yet"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var state: some View {
        switch watcher.state {
        case .active: Chip(verbatim: String(localized: "watch.state.active", defaultValue: "Watching", comment: "Status chip on a watch that is running"), tone: .accent)
        case .paused: Chip("Paused", tone: .neutral)
        case .error: Chip("Having trouble", tone: .danger)
        case .triggered: Chip("Spotted", tone: .success)
        case .expired: Chip("Expired", tone: .neutral)
        }
    }
}

/// A page's last change in full: the lines that went and the lines that came.
struct ChangeLines: View {
    var change: PageChange

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Changed \(TimeText.short(change.at))").font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            ForEach(Array(change.removed.enumerated()), id: \.offset) { _, line in
                Text(verbatim: "− " + line).foregroundStyle(Theme.danger)
            }
            ForEach(Array(change.added.enumerated()), id: \.offset) { _, line in
                Text(verbatim: "+ " + line).foregroundStyle(Theme.success)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(Theme.Space.m)
        .frame(maxWidth: 420, alignment: .leading)
    }
}

/// A session that finished in the last hour: how long it took, and the last thing it asked of Sidefolk.
struct FinishedRow: View {
    var session: AgentSession
    var lastCall: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "checkmark.seal", folk: "byte")
            VStack(alignment: .leading, spacing: 3) {
                Text(Describe.session(session)).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                let end = session.endedAt ?? session.updatedAt
                Text(verbatim: ([String(localized: "Finished \(TimeText.relative(end))", comment: "“Finished 12 min ago”")] + [lastCall].compactMap { $0 })
                    .joined(separator: " · "))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .nowRow()
        .accessibilityElement(children: .combine)
    }
}

/// A line of a day under the rail: an event or a reminder.
enum DayRow: Identifiable {
    case event(CalendarEvent)
    case reminder(Reminder)

    var id: String {
        switch self {
        case .event(let e): "e" + e.id
        case .reminder(let r): "r" + r.id
        }
    }

    static func merge(events: [CalendarEvent], reminders: [Reminder]) -> [DayRow] {
        let timed = events.filter { !$0.allDay }.map { ($0.start, DayRow.event($0)) }
            + reminders.map { ($0.nextDue ?? $0.fireAt, DayRow.reminder($0)) }
        return events.filter(\.allDay).map(DayRow.event) + timed.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

/// An event from the calendar (D57): read-only here; it lives in the Calendar app.
struct EventRow: View {
    var event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "calendar", folk: "tempo")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: [when, event.calendar].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .nowRow()
        .accessibilityElement(children: .combine)
    }

    private var when: String {
        guard !event.allDay else { return String(localized: "All day") }
        return "\(TimeFormat.clock(event.start, calendar: .current))–\(TimeFormat.clock(event.end, calendar: .current))"
    }
}

/// One row of the queue, whatever it is, and the keys that answer it while it has the keyboard (D58). The rules are
/// the approval card's: nothing answers until the row has been in view for a moment; a high-risk "yes" needs ⌘⏎;
/// another app's or an extension's request is never approved from the keyboard, only said no to.
struct QueueRow: View {
    var decision: NowModel.Decision
    var model: NowModel
    var focused: FocusState<String?>.Binding
    /// "rows" in a list, or "cards" side by side (D64), where ← → move as ↑ ↓ do.
    var style = "rows"
    var act: (@escaping () async -> Void) -> Void
    @State private var armed = false

    var body: some View {
        let isFocused = focused.wrappedValue == decision.id
        Group {
            if style == "cards" || style == "stack" {
                QueueCardFrame(label: cardLabel, tint: cardTint, focused: isFocused, width: style == "stack" ? nil : 320,
                               deadline: deadline) { row }
            } else if style == "bubbles" {
                QueueBubbleFrame(label: cardLabel, tint: cardTint, focused: isFocused) { row }
            } else if style == "index" {
                IndexCardFrame(label: cardLabel, risk: risk, focused: isFocused) { row }
            } else {
                row.background(isFocused ? Theme.accentSoft.opacity(0.6) : .clear)
            }
        }
            .focusable()
            .focusEffectDisabled()
            .focused(focused, equals: decision.id)
.onKeyPress(keys: [.return, .delete, .upArrow, .downArrow, .leftArrow, .rightArrow, "s", "j", "k"], phases: .down) { press in handle(press) }
            .task {
                try? await Task.sleep(for: .milliseconds(800))
                armed = true
            }
    }

    private var risk: Risk? {
        if case .approval(let request) = decision { return request.risk }
        if case .skipped(let step) = decision { return step.request.risk }
        return nil
    }

    private var deadline: Date? {
        if case .approval(let request) = decision { return request.expiresAt }
        return nil
    }

    /// Who's asking, above a card: the board's "Mochi asks", "Claude Code is waiting", "Watch changed".
    private var cardLabel: String {
        switch decision {
        case .approval(let request):
            switch request.caller.kind {
            case "agent": return String(localized: "\(model.services.runtime.settings.current.companionName) asks", comment: "Above a decision card: the companion asks")
            case "user", "command": return String(localized: "You asked")
            default: return String(localized: "Another app asks")
            }
        case .session(let session): return String(localized: "\(Describe.agentName(session.agent)) is waiting")
        case .attention(let item):
            switch item.refKind {
            case "watcher": return String(localized: "Watch changed")
            case "reminder": return String(localized: "Reminder")
            default: return String(localized: "\(model.services.runtime.settings.current.companionName) noticed")
            }
        case .skipped: return String(localized: "Skipped", comment: "Above a decision card: a step nobody answered in time")
        }
    }

    private var cardTint: Color {
        switch decision {
        case .approval(let request): request.risk == .high ? Theme.danger : Theme.sun
        case .session: Theme.danger
        case .attention: Theme.link
        case .skipped: Theme.inkMuted
        }
    }

    @ViewBuilder private var row: some View {
        switch decision {
        case .approval(let request) where style != "rows":
            ApprovalCard(request: request, look: request.extensionId.flatMap { model.extensionLooks[$0] }, framed: false, keys: false) { answer in
                act { await model.answer(request, answer) }
            }
            .padding([.horizontal, .bottom], Theme.Space.m)
        case .approval(let request):
            ApprovalQueueRow(request: request, look: request.extensionId.flatMap { model.extensionLooks[$0] }) { answer in
                act { await model.answer(request, answer) }
            }
        case .session(let session):
            SessionNeedsYouRow(session: session) { model.openSession(session) }
        case .attention(let item):
            AttentionRow(item: item) { action in act { await model.respond(item, action: action) } }
        case .skipped(let step):
            SkippedStepRow(step: step, run: { act { await model.runSkipped(step) } }, dismiss: { act { await model.dismissSkipped(step) } })
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow, .leftArrow, "k": move(-1)
        case .downArrow, .rightArrow, "j": move(1)
        case .return: yes(command: press.modifiers.contains(.command))
        case .delete: no()
        default: snooze()
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let queue = model.focusedQueue
        guard let i = queue.firstIndex(where: { $0.id == decision.id }) else { return .ignored }
        focused.wrappedValue = queue[min(max(i + step, 0), queue.count - 1)].id
        return .handled
    }

    private func yes(command: Bool) -> KeyPress.Result {
        switch decision {
        case .approval(let request):
            guard request.mayApproveFromKeys(armed: armed, command: command) else { return .ignored }
            act { await model.answer(request, .allowOnce) }
        case .session(let session):
            model.openSession(session)
        case .attention(let item):
            guard let primary = item.actions.first(where: \.isPrimary) else { return .ignored }
            act { await model.respond(item, action: primary.id) }
        case .skipped(let step):
            guard armed, step.request.risk != .high || command else { return .ignored }
            act { await model.runSkipped(step) }
        }
        return .handled
    }

    private func no() -> KeyPress.Result {
        switch decision {
        case .approval(let request): act { await model.answer(request, .deny) }
        case .attention(let item): act { await model.respond(item, action: nil) }
        case .skipped(let step): act { await model.dismissSkipped(step) }
        case .session: return .ignored
        }
        return .handled
    }

    private func snooze() -> KeyPress.Result {
        guard case .attention(let item) = decision, let later = item.actions.first(where: { $0.id.hasPrefix("snooze") }) else { return .ignored }
        act { await model.respond(item, action: later.id) }
        return .handled
    }
}

/// Guard's question as a row of the queue: the approval card's words and buttons, beside Guard's icon.
struct ApprovalQueueRow: View {
    var request: ApprovalRequest
    var look: ExtensionLook?
    var decide: (ApprovalDecision) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "checkmark.shield", folk: "guard")
            ApprovalCard(request: request, look: look, framed: false, keys: false, decide: decide)
            Spacer(minLength: 0)
        }
        .nowRow()
    }
}

/// Shared row padding so every list in Now lines up.
private extension View {
    func nowRow() -> some View {
        padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
    }
}

struct SessionNeedsYouRow: View {
    var session: AgentSession
    var open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "hand.raised", folk: "byte")
            VStack(alignment: .leading, spacing: 3) {
                headline.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let detail = session.detail, !detail.isEmpty {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(3)
                }
                Text("Waiting since \(TimeText.short(session.updatedAt))").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                Button("Open session", action: open).buttonStyle(.sf(.primary)).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .nowRow()
        .accessibilityElement(children: .contain)
    }

    private var headline: Text {
        let agent = Describe.agentName(session.agent)
        guard let project = session.projectName else { return Text("\(agent) needs you") }
        return Text("\(agent) needs you in \(project)", comment: "“Claude Code needs you in sidefolk”: the agent, then the project")
    }
}

struct AttentionRow: View {
    var item: AttentionItem
    var respond: (String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: symbol, folk: folk)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = item.body, !body.isEmpty {
                    Text(body).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(3)
                }
                Text(TimeText.short(item.createdAt)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                HStack(spacing: 6) {
                    ForEach(item.actions, id: \.id) { action in
                        Button { respond(action.id) } label: { Text(verbatim: action.title) }
                            .buttonStyle(.sf(action.isPrimary ? .primary : .secondary))
                    }
                    Button("Dismiss") { respond(nil) }.buttonStyle(.sf(.plain))
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .nowRow()
        .accessibilityElement(children: .contain)
    }

    private var kind: String { item.refKind ?? String(item.source.split(separator: ":").first ?? "") }

    private var symbol: String {
        switch kind {
        case "reminder": "alarm"
        case "watcher": "binoculars"
        case "job": "terminal"
        case "session", "external": "sparkles"
        case "summary": "tray.full"
        case "brief": "sun.max"
        default: "bell"
        }
    }

    private var folk: String {
        switch kind {
        case "reminder", "brief": "tempo"
        case "watcher": "scout"
        case "job", "session", "external": "byte"
        default: "sidefolk"
        }
    }
}

/// A round checkbox, Things-style. Marks a reminder or task done.
struct CheckCircle: View {
    var checked: Bool
    var label: Text
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(checked ? Theme.success : Theme.inkFaint, lineWidth: 1.5)
                if checked {
                    Circle().fill(Theme.success)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.surface)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

struct ReminderRow: View {
    var reminder: Reminder
    /// In the Later group, times carry their day.
    var later: Bool
    var model: NowModel
    @State private var editing = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            CheckCircle(checked: false, label: Text("Mark “\(reminder.title)” done")) { Task { await model.complete(reminder) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(2)
                if let item = model.item(of: reminder) { ItemLink(item: item, reminder: reminder) { model.open(item) } }
                HStack(spacing: Theme.Space.s) {
                    Text(when).foregroundStyle(overdue ? Theme.danger : Theme.inkMuted)
                    if let rule = reminder.recurrence {
                        Label { Text(verbatim: Describe.recurrence(rule)) } icon: { Image(systemName: "repeat") }
                            .labelStyle(.titleAndIcon)
                    }
                    if let who = Describe.source(reminder.source) { Text("from \(who)") }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            // Snooze is a button only when it is about to matter; a list of future reminders stays quiet.
            if dueSoon { snoozeMenu }
            Menu {
                Button("Edit…") { editing = true }
                if !dueSoon { Menu("Snooze") { snoozeItems(prefixed: false) } }
                Button("Cancel reminder", role: .destructive) { Task { await model.cancel(reminder) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for “\(reminder.title)”")
        }
        .nowRow()
        .onTapGesture(count: 2) { editing = true }
        .contextMenu {
            Button("Mark done") { Task { await model.complete(reminder) } }
            if let item = model.item(of: reminder) { Button(ItemLink.openTitle(item.kind)) { model.open(item) } }
            Button("Edit…") { editing = true }
            snoozeItems(prefixed: true)
            Divider()
            Button("Cancel reminder", role: .destructive) { Task { await model.cancel(reminder) } }
        }
        .sheet(isPresented: $editing) { EditReminderSheet(reminder: reminder, model: model) }
    }

    private var snoozeMenu: some View {
        Menu("Snooze") { snoozeItems(prefixed: false) }
            .menuStyle(.button)
            .buttonStyle(.sf(.secondary))
            .fixedSize()
            .accessibilityLabel("Snooze “\(reminder.title)”")
    }

    /// "10 minutes" inside the Snooze menu; "Snooze 10 minutes" where the menu doesn't say it.
    @ViewBuilder private func snoozeItems(prefixed: Bool) -> some View {
        ForEach(NowModel.Snooze.allCases, id: \.self) { option in
            Button { Task { await model.snooze(reminder, option) } } label: {
                Text(verbatim: prefixed ? model.snoozeTitle(for: option) : model.title(for: option))
            }
        }
    }

    private var due: Date { reminder.nextDue ?? reminder.fireAt }
    private var overdue: Bool { due < Date() }
    private var dueSoon: Bool { due.timeIntervalSinceNow < 3600 }

    private var when: String {
        let time = later ? TimeText.short(due) : TimeFormat.clock(due, calendar: .autoupdatingCurrent)
        if overdue { return String(localized: "Overdue since \(TimeText.short(due))") }
        if reminder.state == .snoozed { return String(localized: "Snoozed until \(time)") }
        return time
    }
}

/// The note or task a reminder belongs to (D49), a click away in the Notebook: its title when the reminder has words of
/// its own, else just what kind of thing it is.
struct ItemLink: View {
    var item: NotebookItem
    var reminder: Reminder
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            Label {
                if item.title.lowercased() == reminder.title.lowercased() {
                    Text(Self.openTitle(item.kind))
                } else {
                    Text(verbatim: item.title)
                }
            } icon: {
                Image(systemName: ItemKindStyle.symbol(item.kind))
            }
            .labelStyle(.titleAndIcon)
            .font(Theme.Font.caption)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.link)
        .help(Text("Open “\(item.title.clipped(60))” in the Notebook"))
        .accessibilityLabel(Text("Open “\(item.title.clipped(60))” in the Notebook"))
    }

    static func openTitle(_ kind: NotebookItem.Kind) -> LocalizedStringResource {
        switch kind {
        case .note: "Open note"
        case .idea: "Open idea"
        case .task: "Open task"
        case .link: "Open link"
        }
    }
}

struct NewReminderRow: View {
    @Bindable var model: NowModel
    @FocusState private var focus: Field?
    private enum Field { case title, when }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.folkColor("tempo"))
                    .accessibilityHidden(true)
                TextField("New reminder", text: $model.newTitle, prompt: Text("New reminder"))
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .when }
                    .accessibilityLabel("New reminder")
                Rectangle().fill(Theme.line).frame(width: 1, height: 18)
                TextField("When", text: $model.newWhen, prompt: Text("When, like “tomorrow 9:00”"))
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .frame(minWidth: 190, maxWidth: 240)
                    .focused($focus, equals: .when)
                    .onSubmit { Task { await model.addReminder() } }
                    .accessibilityLabel("When")
                Button("Add reminder") { Task { await model.addReminder() } }
                    .buttonStyle(.sf(.primary))
                    .disabled(!model.canAddReminder)
            }
            if let error = model.newError {
                InlineError(error: error).padding(.leading, 29)
            }
        }
        .nowRow()
        .onChange(of: model.newWhen) { model.clearError() }
        .onChange(of: model.newReminderFocus) { focus = .title }
    }
}

/// A report: its latest value, large, how often it reads and when it stops, with Pause and Stop at hand.
struct ReportRow: View {
    var report: Watcher
    var reading: WatchReading?
    var model: NowModel

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            IconTile(symbol: Describe.watcherKind(report.kind).symbol, folk: "scout")
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Text(verbatim: reading?.value ?? "…").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(report.state == .paused ? Theme.inkFaint : Theme.ink).lineLimit(1).truncationMode(.tail)
                Text(verbatim: meta).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                if report.errorCount > 0, let error = report.lastError {
                    Text(error).font(Theme.Font.caption).foregroundStyle(Theme.danger).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 6) {
                if report.state == .paused {
                    Button("Resume") { Task { await model.resume(report) } }.buttonStyle(.sf(.secondary))
                } else {
                    Button("Pause") { Task { await model.pause(report) } }.buttonStyle(.sf(.secondary))
                }
                Button("Stop") { Task { await model.stop(report) } }.buttonStyle(.sf(.secondary))
                    .accessibilityLabel(Text("Stop showing \(report.title)"))
            }
        }
        .nowRow()
        .accessibilityElement(children: .contain)
    }

    private var meta: String {
        let schedule = Describe.reportSchedule(report)
        return report.state == .paused ? String(localized: "Paused · \(schedule)", comment: "“Paused · Every 10 s · stops 11:00”") : schedule
    }
}

struct RunningRow: View {
    var symbol: String
    var title: String
    var started: Date
    var detail: String?
    var command: String?
    var actionTitle: LocalizedStringKey?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: symbol, folk: "byte")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(verbatim: ([elapsed(at: context.date)] + [detail].compactMap { $0 }).joined(separator: " · "))
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                if let command {
                    Text(command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.sf(.secondary))
            }
        }
        .nowRow()
        .accessibilityElement(children: .contain)
    }

    private func elapsed(at now: Date) -> String {
        let seconds = now.timeIntervalSince(started)
        return seconds < 60 ? String(localized: "Just started") : String(localized: "Running for \(TimeText.span(seconds))")
    }
}

/// Rename a reminder or give it a new time, in the same words you'd type to the companion.
struct EditReminderSheet: View {
    var reminder: Reminder
    var model: NowModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var when = ""
    @State private var error: UserFacingError?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Edit reminder").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            TextField("What", text: $title).textFieldStyle(.roundedBorder)
            TextField("When — e.g. “tomorrow 9am” or “every 30 minutes”; leave empty to keep \(current)", text: $when)
                .textFieldStyle(.roundedBorder)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        error = await model.edit(reminder, title: title, when: when)
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(.sf(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .onAppear { title = reminder.title }
    }

    /// "Today 10:30, every 30 minutes until 18:00": the next time, and the repeat it belongs to.
    private var current: String {
        let next = TimeFormat.when(reminder.nextDue ?? reminder.fireAt, now: Date(), calendar: .autoupdatingCurrent)
        guard let rule = reminder.recurrence else { return next }
        return String(localized: "\(next), \(TimeFormat.recurrence(rule, now: Date(), calendar: .autoupdatingCurrent))",
                      comment: "The next time, then the repeat: “Today 10:30, every 30 minutes”")
    }
}
