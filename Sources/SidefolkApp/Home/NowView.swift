import SidefolkCore
import SwiftUI

/// Home › Today: what needs you, what's coming up, what Sidefolk is watching and running.
/// Each domain wears its folk's color: Tempo for time, Scout for watching, Byte for agents and jobs.
struct NowView: View {
    @Bindable var model: NowModel
    /// The queue row the keyboard is on (D58).
    @FocusState private var focused: String?

    var body: some View {
        PageScroll {
            TodayHeader(greeting: greeting, status: status, settings: model.services.runtime.settings.current) {
                model.services.openAsk(prefill: "")
            }
            if model.mode == .fullAccess {
                FullAccessBanner(settings: { model.services.openSettings(tab: .privacy) }) { Task { await model.turnOffFullAccess() } }
            }
            if model.needsYouCount > 0 || model.skippedRun != nil { needsYou }
            // Values told every few seconds or minutes change as you look: they sit near the top.
            if !model.reports.isEmpty { live }
            // Live agent work comes first while there is some: it is the part nothing else on the Mac shows.
            if busy { running }
            comingUp
            watching
            if !busy { running }
            if !model.recent.isEmpty { recently }
        }
    }

    private var busy: Bool { !model.jobs.isEmpty || !model.workingSessions.isEmpty }

    private var greeting: Text {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: Text("Good morning")
        case 12..<18: Text("Good afternoon")
        default: Text("Good evening")
        }
    }

    private var status: Text {
        let needs = switch model.needsYouCount {
        case 0: Text("Nothing needs you right now.")
        case 1: Text("One thing needs you.")
        case let n: Text("\(n) things need you.")
        }
        let left = model.remindersLeftToday
        return left == 0 ? needs : Text("\(needs) \(Text("\(left) reminders left today."))", comment: "Two sentences in Today's header")
    }

    // MARK: Needs you

    private var needsYou: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Needs you", folk: nil, count: model.needsYouCount)
            RowsCard {
                ForEach(model.queue) { decision in
                    QueueRow(decision: decision, model: model, focused: $focused) { work in act(on: decision, work) }
                }
                if let result = model.skippedRun {
                    SkippedRunResult(result: result)
                }
            }
            // The keys work on the row the keyboard is on; Tab gets there.
            Text(verbatim: "↑↓  ·  ⏎  ·  ⌫  ·  S")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                .padding(.leading, Theme.Space.xs)
                .help(Text("Up and down move between them. Return answers yes or does the main action, Delete says not now, S snoozes a reminder."))
                .accessibilityHidden(true)
        }
    }

    /// Runs an answer, then keeps the keyboard where it was in the queue: on the next one, or the last.
    private func act(on decision: NowModel.Decision, _ work: @escaping () async -> Void) {
        let index = model.queue.firstIndex { $0.id == decision.id } ?? 0
        let hadFocus = focused != nil
        Task {
            await work()
            let queue = model.queue
            if hadFocus { focused = queue.isEmpty ? nil : queue[min(index, queue.count - 1)].id }
        }
    }

    // MARK: Live

    private var live: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Live", folk: "scout", count: model.reports.count)
            RowsCard {
                ForEach(model.reports) { w in ReportRow(report: w, reading: model.readings[w.id], model: model) }
            }
        }
    }

    // MARK: Your day

    private var comingUp: some View {
        let groups = model.groups()
        let reminders = { (day: NowModel.ReminderGroup.Day) in groups.first { $0.day == day }?.reminders ?? [] }
        return VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Your day", folk: "tempo", count: model.reminders.count)
            // Today as a line (D58), with the calendar beside the reminders once it's shown (D57).
            RowsCard {
                DayRail(reminders: reminders(.today), events: model.events(on: .today), now: Date(),
                        move: { reminder, date in await model.move(reminder, to: date) }, add: { model.newReminder(at: $0) })
                if !model.calendarOn {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "calendar").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                        Text("Your calendar can be here too, beside your reminders.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: Theme.Space.s)
                        Button("Show my calendar") { Task { await model.showCalendar() } }.buttonStyle(.sf(.secondary)).fixedSize()
                    }
                    .nowRow()
                }
            }
            ForEach([NowModel.ReminderGroup.Day.today, .tomorrow, .later], id: \.self) { day in
                let events = model.events(on: day)
                let due = reminders(day)
                if !events.isEmpty || !due.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(Text(verbatim: NowModel.ReminderGroup(day: day, reminders: due).title)).padding(.leading, Theme.Space.xs)
                        RowsCard {
                            // The day in time order: all-day events, then events and reminders as they come.
                            ForEach(DayRow.merge(events: events, reminders: due)) { row in
                                switch row {
                                case .event(let event): EventRow(event: event)
                                case .reminder(let r): ReminderRow(reminder: r, later: day == .later, model: model)
                                }
                            }
                        }
                    }
                }
            }
            if model.reminders.isEmpty {
                RowsCard {
                    InlineEmpty(text: "Nothing scheduled. Try “remind me at 5 to stretch”.", systemImage: "alarm")
                    NewReminderRow(model: model)
                }
            } else {
                RowsCard { NewReminderRow(model: model) }
            }
        }
    }

    // MARK: Watching

    /// Watches as tiles (D58): what each keeps an eye on, when it last looked, and what it last saw change.
    private var watching: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Watching", folk: "scout", count: model.watchers.count)
            if model.watchers.isEmpty {
                RowsCard {
                    InlineEmpty(text: "Not watching anything. I can tell you when a page changes, a site goes down or a file arrives.",
                                systemImage: "binoculars", actionTitle: "Watch something…") {
                        model.services.openAsk(prefill: "tell me when ")
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Theme.Space.m, alignment: .top)],
                          alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(model.watchers) { w in WatchTile(watcher: w, model: model) }
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
            SectionHeader(title: "Recently")
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
private struct WatchTile: View {
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
private struct ChangeLines: View {
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
private struct FinishedRow: View {
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
private enum DayRow: Identifiable {
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
private struct EventRow: View {
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
private struct QueueRow: View {
    var decision: NowModel.Decision
    var model: NowModel
    var focused: FocusState<String?>.Binding
    var act: (@escaping () async -> Void) -> Void
    @State private var armed = false

    var body: some View {
        row
            .focusable()
            .focusEffectDisabled()
            .focused(focused, equals: decision.id)
            .background(focused.wrappedValue == decision.id ? Theme.accentSoft.opacity(0.6) : .clear)
            .onKeyPress(keys: [.return, .delete, .upArrow, .downArrow, "s"], phases: .down) { press in handle(press) }
            .task {
                try? await Task.sleep(for: .milliseconds(800))
                armed = true
            }
    }

    @ViewBuilder private var row: some View {
        switch decision {
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
        case .upArrow: move(-1)
        case .downArrow: move(1)
        case .return: yes(command: press.modifiers.contains(.command))
        case .delete: no()
        default: snooze()
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let queue = model.queue
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
private struct ApprovalQueueRow: View {
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

private struct SessionNeedsYouRow: View {
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

private struct AttentionRow: View {
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

private struct ReminderRow: View {
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
private struct ItemLink: View {
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
        .foregroundStyle(Theme.accent)
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

private struct NewReminderRow: View {
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
private struct ReportRow: View {
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

private struct RunningRow: View {
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
private struct EditReminderSheet: View {
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
