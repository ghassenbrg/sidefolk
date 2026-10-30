import SidefolkCore
import SwiftUI

// Today's pieces in the Board's styles (D64): cards with their title inside, side by side.

/// A card with its title, count and one small link inside, as the Board's columns are.
struct TitledCard<Trailing: View, Content: View>: View {
    var title: LocalizedStringKey
    var count: Int?
    /// A small picture before the title, as the Stage's cards have.
    var emoji: String? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                if let emoji { Text(verbatim: emoji).accessibilityHidden(true) }
                Text(title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                if let count, count > 0 {
                    Text(count.formatted()).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: Theme.Space.s)
                trailing.font(Theme.Font.caption)
            }
            content
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}

// MARK: day:list

/// The day as a list (D64): what's done struck through, what's late in red with Done beside it, the calendar's events,
/// a line at the present, and tomorrow's first two at the foot.
struct DayList: View {
    var model: NowModel
    var edit: (Reminder) -> Void

    private enum Line: Identifiable {
        case done(Reminder), reminder(Reminder), event(CalendarEvent), now, tomorrow(Reminder)
        var id: String {
            switch self {
            case .done(let r): "d" + r.id
            case .reminder(let r): "r" + r.id
            case .event(let e): "e" + e.id
            case .now: "now"
            case .tomorrow(let r): "t" + r.id
            }
        }
    }

    var body: some View {
        let lines = self.lines
        TitledCard(title: "Your day", count: lines.filter { if case .now = $0 { false } else { true } }.count) {
            if model.calendarOn {
                Text("Calendar on").foregroundStyle(Theme.link)
            } else {
                Button("Show my calendar") { Task { await model.showCalendar() } }.buttonStyle(.plain).foregroundStyle(Theme.link)
            }
        } content: {
            if lines.count <= 1 {
                Text("Nothing scheduled. Try “remind me at 5 to stretch”.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    row(line)
                    if case .now = line {} else { Divider().opacity(0.6) }
                }
            }
        }
    }

    private var lines: [Line] {
        let now = Date()
        let today = model.groups().first { $0.day == .today }?.reminders ?? []
        let timed: [(Date, Line)] = model.doneToday.map { ($0.lastFiredAt ?? $0.fireAt, .done($0)) }
            + today.map { ($0.nextDue ?? $0.fireAt, .reminder($0)) }
            + model.events(on: .today).filter { !$0.allDay }.map { ($0.start, .event($0)) }
        let sorted = timed.sorted { $0.0 < $1.0 }
        let past = sorted.filter { $0.0 <= now }.map(\.1), future = sorted.filter { $0.0 > now }.map(\.1)
        let tomorrow = (model.groups().first { $0.day == .tomorrow }?.reminders ?? []).prefix(2).map(Line.tomorrow)
        return past + [.now] + future + tomorrow
    }

    @ViewBuilder private func row(_ line: Line) -> some View {
        switch line {
        case .now:
            HStack(spacing: 4) {
                Rectangle().fill(Theme.danger).frame(height: 1.5)
                Text(verbatim: TimeFormat.clock(Date(), calendar: .current)).font(Theme.Font.captionStrong).monospacedDigit()
                    .foregroundStyle(Theme.onDanger).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.danger, in: Capsule())
            }
            .padding(.vertical, 2)
            .accessibilityLabel(Text("Now"))
        case .done(let r):
            item(time: r.lastFiredAt ?? r.fireAt, title: r.title, detail: nil, struck: true) {
                Image(systemName: "checkmark").foregroundStyle(Theme.success)
            }
        case .reminder(let r):
            let due = r.nextDue ?? r.fireAt
            let late = due < Date()
            item(time: due, title: r.title, detail: late ? String(localized: "late · \(TimeText.relative(due))", comment: "A reminder whose time passed: “late · 28 min ago”") : nil,
                 late: late) {
                if late { Button("Done") { Task { await model.complete(r) } }.buttonStyle(.sf(.secondary)) }
            }
            .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
        case .event(let e):
            item(time: e.start, title: e.title, detail: String(localized: "Calendar")) { EmptyView() }
        case .tomorrow(let r):
            item(time: nil, title: r.title, detail: TimeFormat.clock(r.nextDue ?? r.fireAt, calendar: .current)) { EmptyView() }
                .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
        }
    }

    private func item<T: View>(time: Date?, title: String, detail: String?, struck: Bool = false, late: Bool = false,
                               @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Group {
                if let time { Text(verbatim: TimeFormat.clock(time, calendar: .current)) } else { Text("Tmrw", comment: "Short for tomorrow, in a narrow time column") }
            }
            .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(late ? Theme.danger : Theme.inkMuted)
            .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(Theme.Font.bodyStrong).strikethrough(struck)
                    .foregroundStyle(struck ? Theme.inkFaint : Theme.ink).lineLimit(1)
                if let detail { Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(late ? Theme.danger : Theme.inkMuted).lineLimit(1) }
            }
            Spacer(minLength: Theme.Space.xs)
            trailing()
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}

// MARK: watching:list

/// Watches as a list (D64): each with how often it looks, and a word or a value at the right.
struct WatchingList: View {
    var model: NowModel

    var body: some View {
        TitledCard(title: "Watching", count: model.watchers.count + model.reports.count) {
            Button("All") { model.services.openAsk(prefill: "what are you watching") }.buttonStyle(.plain).foregroundStyle(Theme.link)
        } content: {
            if model.watchers.isEmpty && model.reports.isEmpty {
                Button("Watch something…") { model.services.openAsk(prefill: "tell me when ") }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.watchers) { w in WatchListRow(watcher: w, model: model); Divider().opacity(0.6) }
                ForEach(model.reports) { r in ReportListRow(report: r, reading: model.readings[r.id], model: model); Divider().opacity(0.6) }
            }
        }
    }
}

private struct WatchListRow: View {
    var watcher: Watcher
    var model: NowModel
    @State private var open = false

    var body: some View {
        let waiting = model.changeWaiting(for: watcher) != nil
        Button { open = true } label: {
            ListRowLabel(symbol: Describe.watcherKind(watcher.kind).symbol, title: Describe.watcherTarget(watcher) ?? watcher.title,
                         detail: Describe.interval(watcher.intervalS)) {
                if waiting {
                    Chip(verbatim: String(localized: "changed", comment: "A small chip on a watch whose page changed"), tone: .danger)
                } else if watcher.state == .error {
                    Chip("Having trouble", tone: .danger)
                } else if watcher.state == .paused {
                    Chip("Paused", tone: .neutral)
                } else if watcher.state == .triggered {
                    Chip("Spotted", tone: .success)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .trailing) { WatchTile(watcher: watcher, model: model).frame(width: 340).padding(Theme.Space.s) }
        .onChange(of: open) { _, isOpen in if isOpen { Task { await model.seen(watcher) } } }
    }
}

private struct ReportListRow: View {
    var report: Watcher
    var reading: WatchReading?
    var model: NowModel
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            ListRowLabel(symbol: Describe.watcherKind(report.kind).symbol, title: reading?.label ?? report.title,
                         detail: Describe.watcherKind(report.kind).label) {
                Text(verbatim: reading?.value ?? "…").font(Theme.Font.bodyStrong).monospacedDigit().foregroundStyle(Theme.ink)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .trailing) { ReportRow(report: report, reading: reading, model: model).frame(width: 380) }
    }
}

/// A row of a Board list: a round icon, a title and a detail, something small at the right.
struct ListRowLabel<Trailing: View>: View {
    var symbol: String
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                .frame(width: 26, height: 26).background(Theme.surfaceSunken, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.xs)
            trailing
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: agents:card

/// Who's working, then what just finished (D64): sessions with a word for where they are, commands, and the two newest
/// things done.
struct AgentsCard: View {
    var model: NowModel

    var body: some View {
        let sessions = model.sessionsNeedingYou + model.workingSessions
        TitledCard(title: "Agents at work", count: sessions.count + model.jobs.count) {
            EmptyView()
        } content: {
            if sessions.isEmpty && model.jobs.isEmpty {
                Button("Connect your agents…") { model.services.openSettings(tab: .agents) }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            ForEach(sessions) { s in
                Button { model.openSession(s) } label: {
                    ListRowLabel(symbol: "sparkles", title: Describe.agentName(s.agent),
                                 detail: [s.projectName, s.detail].compactMap { $0 }.joined(separator: " · ")) {
                        if s.state == .needsYou {
                            Chip(verbatim: String(localized: "needs you", comment: "A chip on an agent waiting for an answer"), tone: .danger)
                        } else {
                            Chip(verbatim: String(localized: "working", comment: "A chip on an agent at work"), tone: .accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(model.jobs) { j in
                ListRowLabel(symbol: "terminal", title: j.title, detail: String(localized: "Running for \(TimeText.duration(Date().timeIntervalSince(j.startedAt)))")) {
                    Chip(verbatim: String(localized: "working", comment: "A chip on an agent at work"), tone: .accent)
                }
            }
            if !model.recent.isEmpty {
                Text("Recently").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).padding(.top, Theme.Space.s)
                ForEach(model.recent.prefix(2)) { e in
                    Text(verbatim: "✓ \(e.title) · \(TimeFormat.clock(e.date, calendar: .current))")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
        }
    }
}

// MARK: notes:cards and art:tile

/// The newest notes as cards (D64): their collection, title, and its reminder or who saved it when. A click opens it.
struct NotesCards: View {
    var model: NowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            HStack {
                Text("From your notebook").font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("⌘N new note").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            if model.recentNotes.isEmpty {
                Text("Nothing saved yet. Notes, tasks and links you keep show up here.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Space.s, alignment: .top)], spacing: Theme.Space.s) {
                ForEach(model.recentNotes) { item in
                    Button { model.open(item) } label: { card(item) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ item: NotebookItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if item.pinnedAt != nil { Text(verbatim: "📌") }
                if let c = model.noteCollections[item.collectionId] {
                    CollectionIcon(collection: c, size: 10)
                    Text(verbatim: NotebookCollections.shownName(c)).lineLimit(1)
                }
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            Text(verbatim: item.title).font(Theme.Font.bodyStrong).foregroundStyle(item.status == .done ? Theme.inkFaint : Theme.ink)
                .strikethrough(item.status == .done).lineLimit(2).multilineTextAlignment(.leading)
            Text(verbatim: detail(item)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
        .contentShape(Rectangle())
    }

    private func detail(_ item: NotebookItem) -> String {
        if let due = item.dueAt { return "⏰ \(TimeText.short(due))" }
        let who = Describe.source(item.source) ?? String(localized: "you", comment: "Who saved a note: the person")
        return String(localized: "\(who) · \(TimeText.relative(item.createdAt))", comment: "Who saved a note and when: “Claude Code · 12 min ago”")
    }
}

/// The theme's own picture among the cards (D64), never behind words.
struct ArtTile: View {
    var body: some View {
        if let art = Theme.Art.tile {
            Image(decorative: art, scale: 2).resizable().scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
                .padding(.top, 28)
                .accessibilityHidden(true)
        }
    }
}
