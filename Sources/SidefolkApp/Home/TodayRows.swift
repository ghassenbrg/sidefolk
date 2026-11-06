import SidefolkCore
import SwiftUI

// MARK: - Rows

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
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
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

/// One row of the queue, whatever it is, and the keys that act on it while it has the keyboard (D58). No key says yes here
/// (D130): a click puts the keyboard on a row just brought forward, and another agent's question has Yes as its main
/// answer. Keys move, snooze and say no, and no only once the row has been in view for a moment.
struct QueueRow: View {
    /// Delete arrives as U+007F, which `.delete` alone doesn't match.
    static let keys: Set<KeyEquivalent> = [.return, .delete, .deleteForward, KeyEquivalent("\u{7F}"), .upArrow, .downArrow, .leftArrow, .rightArrow,
                                           "s", "j", "k"]

    var decision: NowModel.Decision
    var model: NowModel
    var focused: FocusState<String?>.Binding
    /// "rows" in a list, or "card": Today's card of its own (D84), with who asks above it.
    var style = "rows"
    var act: (@escaping () async -> Void) -> Void
    @State private var armed = false

    var body: some View {
        let isFocused = focused.wrappedValue == decision.id
        Group {
            if case .approval(let request) = decision {
                // Guard's question is a permission slip here too (D84): who asks in the strip, what it touches, Allow.
                PermissionSlip(request: request, look: request.extensionId.flatMap { model.extensionLooks[$0] },
                               companionName: model.services.runtime.settings.current.companionName, keys: false, focused: isFocused) { answer in
                    act { await model.answer(request, answer) }
                } changeMode: {
                    model.services.openSettings(tab: .trust)
                }
                .padding(style == "card" ? 0 : Theme.Space.s)
            } else if style == "card" {
                NeedsYouCard(source: cardLabel, folk: folk, settings: model.services.runtime.settings.current, at: at, tint: cardTint,
                             focused: isFocused) { cardBody }
            } else {
                row.background(isFocused ? Theme.accentSoft.opacity(0.6) : .clear)
            }
        }
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused(focused, equals: decision.id)
.onKeyPress(keys: Self.keys, phases: .down) { press in handle(press) }
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

    private var cardLabel: String { decision.cardLabel(model) }

    private var cardTint: Color {
        switch decision {
        // Waiting on you is amber; only a high-risk step is red (StatusTone).
        case .approval(let request): request.risk == .high ? Theme.danger : Theme.warning
        case .session: Theme.warning
        case .attention: Theme.link
        case .skipped: Theme.inkMuted
        }
    }

    /// The folk whose avatar stands beside a card: Guard asks, Byte keeps agents, Scout watches, Tempo keeps time.
    private var folk: String? { decision.folk }

    private var at: Date {
        switch decision {
        case .approval(let request): request.createdAt
        case .session(let session): session.updatedAt
        case .attention(let item): item.createdAt
        case .skipped(let step): step.skippedAt
        }
    }

    /// What a card on Today says (D84): the question, the parts as chips, and at most three buttons, the main one last.
    @ViewBuilder private var cardBody: some View {
        switch decision {
        case .approval:
            EmptyView()
        case .session(let session):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(verbatim: session.detail.flatMap { $0.isEmpty ? nil : $0 } ?? Describe.session(session))
                    .font(Theme.Font.title2).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                WrapRow(minimum: 220, spacing: Theme.Space.s) {
                    Text("Answer in its own window. Sidefolk only lets you know.").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.openSession(session) } label: { Label("Open session", systemImage: "arrow.up.forward") }
                        .buttonStyle(.sf(.primary, size: .regular)).fixedSize()
                }
            }
        case .attention(let item):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(item.title).font(Theme.Font.title2).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if let body = item.body, !body.isEmpty {
                    ExpandableText(text: body)
                }
                // The watch's own page has the change line by line and its checks (D87): a link, so the card keeps its
                // three buttons.
                if item.refKind == "watcher", let id = item.refId, let open = model.openWatch {
                    Button { open(id) } label: {
                        HStack(spacing: Theme.Space.xxs) {
                            Text("See what changed")
                            Image(systemName: "chevron.forward").font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.sfBare)
                    .font(Theme.Font.bodyStrong).foregroundStyle(Theme.link)
                }
                ButtonRow(spacing: Theme.Space.s) {
                    Button("Dismiss") { act { await model.respond(item, action: nil) } }.buttonStyle(.sf(.quiet, size: .regular))
                    ForEach(Self.cardActions(item), id: \.id) { action in
                        Button { act { await model.respond(item, action: action.id) } } label: { Text(verbatim: action.title) }
                            .buttonStyle(.sf(action.isPrimary ? .primary : .secondary, size: .regular))
                    }
                }
                // At the card's trailing end with the main answer last, as the permission slip and the Sidecard have them.
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .skipped(let step):
            SkippedStepRow(step: step, run: { act { await model.runSkipped(step) } }, dismiss: { act { await model.dismissSkipped(step) } },
                           plain: true)
        }
    }

    /// Beside Dismiss, two answers with the main one last: sorting the main one last and keeping the first two had
    /// left a reminder without Done.
    static func cardActions(_ item: AttentionItem) -> [AttentionAction] {
        // A question's answers are all it has: none can be left off.
        if item.refKind == "ask" {
            let main = item.actions.first(where: \.isPrimary)
            return item.actions.filter { !$0.isPrimary } + (main.map { [$0] } ?? [])
        }
        // The card has its own Dismiss, as the rows do; an item's "dismiss" answer would show it twice (an agent's notice, a job's).
        let actions = item.actions.filter { $0.id != "dismiss" }
        let main = actions.first(where: \.isPrimary)
        let others = actions.filter { !$0.isPrimary }.prefix(main == nil ? 2 : 1)
        return Array(others) + (main.map { [$0] } ?? [])
    }

    @ViewBuilder private var row: some View {
        switch decision {
        case .approval:
            EmptyView()
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
        case .return: open()
        case .delete, .deleteForward, KeyEquivalent("\u{7F}"): no()
        default: snooze()
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let queue = model.focusedQueue
        guard let i = queue.firstIndex(where: { $0.id == decision.id }) else { return .ignored }
        focused.wrappedValue = queue[min(max(i + step, 0), queue.count - 1)].id
        return .handled
    }

    /// Return opens a session that waits on you. Everything else takes a click on its button.
    private func open() -> KeyPress.Result {
        guard case .session(let session) = decision else { return .ignored }
        model.openSession(session)
        return .handled
    }

    private func no() -> KeyPress.Result {
        guard armed, let work = decision.notNow(model) else { return .ignored }
        focused.wrappedValue = decision.id
        act(work)
        return .handled
    }

    private func snooze() -> KeyPress.Result {
        guard let work = decision.snoozed(model) else { return .ignored }
        focused.wrappedValue = decision.id
        act(work)
        return .handled
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
                headline.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if let detail = session.detail, !detail.isEmpty {
                    ExpandableText(text: detail, font: Theme.Font.caption)
                }
                Text("Waiting since \(TimeText.short(session.updatedAt))").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                Button("Open session", action: open).buttonStyle(.sf(.primary)).fixedSize().padding(.top, 4)
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
                    ExpandableText(text: body, font: Theme.Font.caption)
                }
                Text(verbatim: ([Self.who(item)].compactMap { $0 } + [TimeText.short(item.createdAt)]).joined(separator: " · "))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                // Wrapping, so a narrow column never cuts "Done · 10 min · Tomorrow" to "… 1… T…".
                ButtonRow(spacing: 6) {
                    // The row has its own Dismiss; an item's "dismiss" answer would show it twice.
                    ForEach(item.actions.filter { $0.id != "dismiss" }, id: \.id) { action in
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

    private var kind: String {
        // An agent's notice reads as the agent's, whatever it was about.
        if item.refKind == "notify" || item.refKind == nil { return String(item.source.split(separator: ":").first ?? "") }
        return item.refKind ?? ""
    }

    /// Another app's notice says whose it is: "Claude Code · Today 09:11".
    static func who(_ item: AttentionItem) -> String? {
        let parts = item.source.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts[0] == "external" || (parts[0] == "session" && parts.count == 3) else { return nil }
        return Describe.agentName(parts[1])
    }

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
        }
        .buttonStyle(.sfIcon(side: 22))
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
                    Text(when).foregroundStyle(overdue ? Theme.warning : Theme.inkMuted)
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
        .buttonStyle(.sfBare)
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
    /// It appeared because the person asked for it, so typing starts here.
    var focusAtOnce = false
    @FocusState private var focus: Field?
    private enum Field { case title, when }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The day's column is narrow, so each field gets its own line.
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.folkColor("tempo"))
                    .accessibilityHidden(true)
                TextField("New reminder", text: $model.newTitle, prompt: Text(verbatim: "")).fieldHint(Text("New reminder"), showing: model.newTitle.isEmpty, spoken: false)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .when }
                    .accessibilityLabel("New reminder")
            }
            // Typed first; the calendar beside it for picking (WhenField).
            WhenField(text: $model.newWhen, prompt: Text("When, like “tomorrow 9:00”"), parser: model.whenParser,
                      focus: $focus, focusValue: .when) { Task { await model.addReminder() } }
                .textFieldStyle(.plain)
                .padding(.leading, 29)
            Button("Add reminder") { Task { await model.addReminder() } }
                .buttonStyle(.sf(.primary))
                .disabled(!model.canAddReminder)
                .fixedSize()
                .padding(.leading, 29)
                .padding(.top, 2)
            if let error = model.newError {
                InlineError(error: error).padding(.leading, 29)
            }
        }
        .nowRow()
        .onChange(of: model.newWhen) { model.clearError() }
        .onChange(of: model.newReminderFocus) { focus = .title }
        .task { if focusAtOnce { focus = .title } }
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
            // In a narrow column the button goes under the words: "Claude Cod…  Open s…" said nothing.
            WrapRow(minimum: 170, spacing: Theme.Space.s, alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(2)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(verbatim: ([elapsed(at: context.date)] + [detail].compactMap { $0 }).joined(separator: " · "))
                            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    }
                    if let command {
                        Text(command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(.sf(.secondary)).fixedSize()
                }
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
    @FocusState private var whenFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Edit reminder").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            TextField("What", text: $title).lanternField()
            WhenField(text: $when, prompt: Text("When, like “tomorrow 9am” or “every 30 minutes”"), parser: model.whenParser,
                      focus: $whenFocused, emptyHint: Text("Leave empty to keep \(current)"), boxed: true)
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

extension NowModel.Decision {
    /// Delete: not now. Nil for what can only be opened.
    func notNow(_ model: NowModel) -> (() async -> Void)? {
        switch self {
        case .approval(let request): { await model.answer(request, .deny) }
        case .attention(let item): { await model.respond(item, action: nil) }
        case .skipped(let step): { await model.dismissSkipped(step) }
        case .session: nil
        }
    }

    /// S: later, for what offers it.
    func snoozed(_ model: NowModel) -> (() async -> Void)? {
        guard case .attention(let item) = self, let later = item.actions.first(where: { $0.id.hasPrefix("snooze") }) else { return nil }
        return { await model.respond(item, action: later.id) }
    }

    /// Who's asking, above a card: the board's "Mochi asks", "Claude Code is waiting", "Watch changed".
    @MainActor func cardLabel(_ model: NowModel) -> String {
        switch self {
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
            // Another app's notice is signed by the app, as its card was.
            case _ where item.source.hasPrefix("external:"):
                return Describe.caller(item.source, companion: model.services.runtime.settings.current.companionName)
            default: return String(localized: "\(model.services.runtime.settings.current.companionName) noticed")
            }
        case .skipped: return String(localized: "Skipped", comment: "Above a decision card: a step nobody answered in time")
        }
    }

    /// The helper who brings it; nil when the companion says it itself.
    @MainActor var folk: String? {
        switch self {
        case .approval, .skipped: "guard"
        case .session: "byte"
        // The same helper the Sidecard's card showed; the companion's own words come with its face.
        case .attention(let item): SidecardItemCard.folk(item)
        }
    }

    /// Its name in a line.
    var title: String {
        switch self {
        case .approval(let r): r.title
        case .session(let s): Describe.session(s)
        case .attention(let a): a.title
        case .skipped(let s): s.request.title
        }
    }

    /// Another app or an agent waiting on the person, not something of their own: its asker is said in amber.
    var isFirm: Bool {
        switch self {
        case .approval(let r): r.slipTone != .calm
        case .session: true
        case .attention, .skipped: false
        }
    }

    /// What colour its label says it in (D78): waiting on the person amber, a watch's change news, the rest quiet.
    var statusTone: StatusTone {
        if isFirm { return .warning }
        if case .attention(let item) = self, item.refKind == "watcher" { return .news }
        return .neutral
    }

    /// Beside the label, so the colour is never all that says it.
    var statusSymbol: String {
        switch self {
        case .approval: isFirm ? "clock" : "checkmark.shield"
        case .session: "clock"
        case .attention(let item):
            switch item.refKind {
            case "watcher": "arrow.left.arrow.right"
            case "reminder": "bell"
            default: "sparkle"
            }
        case .skipped: "forward.end"
        }
    }
}

/// What waits after the decision in view (D130): who asks and what, in one line. A click or Return brings it forward, where
/// it's answered with everything it needs; ↑ ↓ move as they do on the cards.
struct NextUpRow: View {
    private static let keys = QueueRow.keys
    @State private var armed = false

    var decision: NowModel.Decision
    var model: NowModel
    var focused: FocusState<String?>.Binding
    var act: (@escaping () async -> Void) -> Void
    var bringForward: () -> Void

    var body: some View {
        let isFocused = focused.wrappedValue == decision.id
        Button(action: bringForward) {
            HStack(spacing: Theme.Space.m) {
                if let folk = decision.folk {
                    FolkAvatar(name: folk, size: 26)
                } else {
                    CompanionAvatar(settings: model.services.runtime.settings.current, size: 26)
                }
                Text(verbatim: decision.title).font(Theme.Font.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                // The status keeps its room and its whole words; the title gives way first.
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: decision.statusSymbol).font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
                    Text(verbatim: decision.cardLabel(model)).font(Theme.Font.callout.weight(decision.statusTone == .neutral ? .regular : .medium)).lineLimit(1)
                }
                .foregroundStyle(Theme.color(decision.statusTone))
                .fixedSize()
                RowChevron()
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s + 2)
            .contentShape(Rectangle())
            // Inside the row: the card clips what reaches past it.
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).strokeBorder(Theme.focus, lineWidth: 2).padding(3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.sfBare)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused(focused, equals: decision.id)
        .onKeyPress(keys: Self.keys, phases: .down) { press in
            switch press.key {
            case .return:
                bringForward()
                return .handled
            case .delete, .deleteForward, KeyEquivalent("\u{7F}"):
                guard armed, let work = decision.notNow(model) else { return .ignored }
                focused.wrappedValue = decision.id
                act(work)
                return .handled
            case "s":
                guard let work = decision.snoozed(model) else { return .ignored }
                focused.wrappedValue = decision.id
                act(work)
                return .handled
            case .upArrow, .leftArrow, "k": return move(-1)
            default: return move(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
        .accessibilityHint(Text("Brings it forward to answer"))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let queue = model.focusedQueue
        guard let i = queue.firstIndex(where: { $0.id == decision.id }) else { return .ignored }
        focused.wrappedValue = queue[min(max(i + step, 0), queue.count - 1)].id
        return .handled
    }
}
