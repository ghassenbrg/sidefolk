import SidefolkCore
import SwiftUI

/// Home › Now: what needs you, what's coming up, what Sidefolk is watching and running.
/// Each domain wears its folk's color: Tempo for time, Scout for watching, Byte for agents and jobs.
struct NowView: View {
    @Bindable var model: NowModel

    var body: some View {
        PageScroll {
            NowHero(greeting: greeting, status: status, settings: model.services.runtime.settings.current) {
                model.services.openAsk(prefill: "")
            }
            if model.needsYouCount > 0 { needsYou }
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
        switch model.needsYouCount {
        case 0: Text("Nothing needs you right now.")
        case 1: Text("One thing needs you.")
        case let n: Text("\(n) things need you.")
        }
    }

    // MARK: Needs you

    private var needsYou: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Needs you", folk: nil, count: model.needsYouCount)
            RowsCard {
                ForEach(model.sessionsNeedingYou) { session in
                    SessionNeedsYouRow(session: session) { model.openSession(session) }
                }
                ForEach(model.attention) { item in
                    AttentionRow(item: item) { action in Task { await model.respond(item, action: action) } }
                }
            }
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

    // MARK: Coming up

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Coming up", folk: "tempo", count: model.reminders.count)
            ForEach(model.groups()) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(Text(verbatim: group.title)).padding(.leading, Theme.Space.xs)
                    RowsCard {
                        ForEach(group.reminders) { r in
                            ReminderRow(reminder: r, later: group.day == .later, model: model)
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

    private var watching: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Watching", folk: "scout", count: model.watchers.count)
            RowsCard {
                if model.watchers.isEmpty {
                    InlineEmpty(text: "Not watching anything. I can tell you when a page changes, a site goes down or a file arrives.",
                                systemImage: "binoculars", actionTitle: "Watch something…") {
                        model.services.openAsk(prefill: "tell me when ")
                    }
                }
                ForEach(model.watchers) { w in WatcherRow(watcher: w, model: model) }
            }
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Running", folk: "byte", count: model.jobs.count + model.workingSessions.count)
            RowsCard {
                if model.jobs.isEmpty && model.workingSessions.isEmpty {
                    InlineEmpty(text: "Nothing running. Connect Claude Code or Codex to see their sessions here, or start a command with “sidefolk run -- npm test”.",
                                systemImage: "terminal", actionTitle: "Connect your agents…") {
                        model.services.openSettings(tab: .agents)
                    }
                }
                ForEach(model.workingSessions) { s in
                    RunningRow(symbol: "sparkles", title: Describe.session(s), started: s.startedAt, detail: s.detail,
                               actionTitle: "Open session") { model.openSession(s) }
                }
                ForEach(model.jobs) { j in
                    RunningRow(symbol: "terminal", title: j.title, started: j.startedAt,
                               detail: j.cwd.map { String(localized: "in \(FolderAccess.displayPath($0))") }, command: j.command)
                }
            }
        }
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
    }
}

private struct WatcherRow: View {
    var watcher: Watcher
    var model: NowModel

    var body: some View {
        let kind = Describe.watcherKind(watcher.kind)
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: kind.symbol, folk: "scout")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Space.s) {
                    Text(watcher.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    state
                }
                Text(meta(kind)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                if let target = Describe.watcherTarget(watcher), !watcher.title.contains(target) {
                    Text(target).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                        .lineLimit(1).truncationMode(.middle)
                }
                if watcher.state == .error || watcher.errorCount > 0, let error = watcher.lastError {
                    Text(error).font(Theme.Font.caption).foregroundStyle(Theme.danger).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 6) {
                Button("Check now") { Task { await model.checkNow(watcher) } }
                    .buttonStyle(.sf(.secondary))
                    .disabled(watcher.state == .paused)
                if watcher.state == .paused {
                    Button("Resume") { Task { await model.resume(watcher) } }.buttonStyle(.sf(.secondary))
                } else {
                    Button("Pause") { Task { await model.pause(watcher) } }.buttonStyle(.sf(.secondary))
                }
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
        .nowRow()
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
        case .active: Chip("Watching", tone: .accent)
        case .paused: Chip("Paused", tone: .neutral)
        case .error: Chip("Having trouble", tone: .danger)
        case .triggered: Chip("Spotted", tone: .success)
        case .expired: Chip("Expired", tone: .neutral)
        }
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
                    .contentTransition(.numericText())
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
        guard report.state != .paused else { return String(localized: "Paused · \(schedule)", comment: "“Paused · Every 10 s · stops 11:00”") }
        guard let at = reading?.at else { return schedule }
        return [schedule, String(localized: "read \(TimeText.relative(at))", comment: "“read 5 s ago”")].joined(separator: " · ")
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
