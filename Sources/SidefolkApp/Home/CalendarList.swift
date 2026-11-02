import SidefolkCore
import SwiftUI

/// The Calendar's Agenda (D66, D84): the next two weeks as a list, each day with what's on it in time order (events
/// with their end and place, in their calendar's colour, reminders, routines and what was done), a line at now, and a
/// way to add something that day. Days with nothing are left out, but today always shows. A click opens a thing's
/// details (D97).
struct CalendarList: View {
    var model: CalendarModel

    var body: some View {
        let days = model.days.filter { Calendar.current.isDateInToday($0) || !model.entries(on: $0).isEmpty }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                if model.entries.isEmpty {
                    EmptyState(title: Text("Nothing in the next two weeks"),
                               message: Text("Reminders, routines and your Mac calendar's events show here, by day."),
                               systemImage: "calendar", folk: "tempo", actionTitle: Text("New reminder")) {
                        model.startNew(at: model.newTime(on: Date()))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.xl)
                } else {
                    ForEach(days, id: \.self) { day in dayView(day) }
                }
            }
            .padding(.bottom, Theme.Space.l)
        }
    }

    /// A reminder that comes back several times a day (every 30 minutes) shows once, at its next time that day, with
    /// how many more times follow, so it doesn't fill the day.
    private func folded(_ entries: [CalendarEntry]) -> (entries: [CalendarEntry], more: [String: Int]) {
        var seen: [String: Int] = [:]
        var kept: [CalendarEntry] = []
        for entry in entries {
            if case .reminder(let o) = entry {
                if seen[o.reminder.id] != nil {
                    seen[o.reminder.id, default: 0] += 1
                    continue
                }
                seen[o.reminder.id] = 0
            }
            kept.append(entry)
        }
        return (kept, seen.filter { $0.value > 0 })
    }

    private func dayView(_ day: Date) -> some View {
        let (entries, more) = folded(model.entries(on: day))
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                if isToday { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
                Text(verbatim: TimeFormat.day(day, now: Date(), calendar: .autoupdatingCurrent))
                    .font(Theme.Font.title2).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text(verbatim: ([day.formatted(.dateTime.weekday(.wide).day().month(.wide))] + counts(entries)).joined(separator: " · "))
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Button { model.startNew(at: model.newTime(on: day)) } label: { Label("New reminder", systemImage: "plus").labelStyle(.iconOnly) }
                    .buttonStyle(.sf(.quiet))
                    .help(Text("Add a reminder this day"))
                    .popover(item: draftBinding(day), arrowEdge: .bottom) { CalendarEditor(model: model, draft: $0) }
            }
            RowsCard {
                if entries.isEmpty {
                    Text("Nothing planned.").font(Theme.Font.body).foregroundStyle(Theme.inkFaint)
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    row(entry, more: entry.reminder.flatMap { more[$0.id] } ?? 0, nowLineAbove: isToday && showsNowLine(before: i, in: entries))
                }
            }
        }
    }

    /// "4 events, 4 reminders".
    private func counts(_ entries: [CalendarEntry]) -> [String] {
        let events = entries.filter { if case .event = $0 { true } else { false } }.count
        let reminders = entries.count - events
        var parts: [String] = []
        if events > 0 { parts.append(String(localized: "\(events) events", comment: "The Agenda: a day's count of calendar events")) }
        if reminders > 0 { parts.append(String(localized: "\(reminders) reminders", comment: "The Agenda: a day's count of reminders")) }
        return parts
    }

    /// The now line goes above the first thing still to come today.
    private func showsNowLine(before index: Int, in entries: [CalendarEntry]) -> Bool {
        let now = Date()
        guard let first = entries.firstIndex(where: { !$0.allDay && $0.start >= now && !$0.struck }) else { return false }
        return first == index && index > 0
    }

    private func row(_ entry: CalendarEntry, more: Int, nowLineAbove: Bool) -> some View {
        let item = entry.reminder.flatMap(model.item)
        return VStack(spacing: 0) {
            if nowLineAbove {
                HStack(spacing: 0) {
                    Text(verbatim: TimeFormat.clock(Date(), calendar: .current)).font(Theme.Font.caption.monospacedDigit()).fontWeight(.semibold)
                        .foregroundStyle(Theme.onAccent).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.xs)
                .accessibilityLabel(Text("Now"))
            }
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 0) {
                    if entry.allDay {
                        Text("All day")
                    } else {
                        Text(verbatim: TimeFormat.clock(entry.start, calendar: .current)).foregroundStyle(Theme.ink)
                        if case .event(let e) = entry, e.end > e.start {
                            Text(verbatim: TimeFormat.clock(e.end, calendar: .current)).foregroundStyle(Theme.inkFaint).font(Theme.Font.callout)
                        }
                    }
                }
                .font(Theme.Font.body.monospacedDigit())
                .frame(width: 56, alignment: .leading)
                RoundedRectangle(cornerRadius: 1.5).fill(model.tint(entry).edge.opacity(entry.struck ? 0.4 : 1)).frame(width: 3).frame(minHeight: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if entry.reminder?.recurrence != nil { Image(systemName: "repeat").font(.system(size: 11)).foregroundStyle(Theme.link) }
                        Text(verbatim: entry.title).font(Theme.Font.headline).strikethrough(entry.struck)
                            .foregroundStyle(entry.struck ? Theme.inkFaint : Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail = detail(entry, item: item, more: more) {
                        Text(verbatim: detail).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                trailing(entry)
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s + 2)
            .background(model.selection == entry.id ? Theme.accentSoft : isNext(entry) ? Theme.accentSoft.opacity(0.4) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = entry.id
                model.inspecting = entry.id
            }
            .contextMenu { CalendarMenu(entry: entry, model: model) }
            .calendarInspector(entry, model: model)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    /// The next event still to come today stands out, with how long until it.
    private func isNext(_ entry: CalendarEntry) -> Bool {
        guard case .event(let e) = entry, Calendar.current.isDateInToday(e.start), e.start > Date() else { return false }
        return model.entries.first { if case .event(let x) = $0 { x.start > Date() && !x.allDay } else { false } }?.id == entry.id
    }

    @ViewBuilder private func trailing(_ entry: CalendarEntry) -> some View {
        switch entry {
        case .finished(let r, _) where r.state == .done:
            Chip(verbatim: String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished"), tone: .success, systemImage: "checkmark")
        case .finished:
            Chip("Reminded you", tone: .neutral)
        case .reminder(let o):
            HStack(spacing: Theme.Space.s) {
                Chip(text: o.reminder.action?.kind == .prompt ? Text("Routine", comment: "The Agenda: a reminder that runs a prompt")
                     : Text("Reminder", comment: "The Agenda: what a row is"), tone: .neutral)
                if o.isNext {
                    CheckCircle(checked: false, label: Text("Mark “\(o.reminder.title)” done")) { Task { await model.now.complete(o.reminder) } }
                }
            }
        case .due(let item):
            HStack(spacing: Theme.Space.s) {
                Chip(text: Text("Due", comment: "The Agenda: a task that's due"), tone: .neutral)
                CheckCircle(checked: false, label: Text("Mark “\(item.title)” done")) { Task { await model.finish(item, undo: nil) } }
            }
        case .event(let e) where isNext(entry):
            Chip(text: Text("in \(TimeText.span(e.start.timeIntervalSinceNow))", comment: "The Agenda: how long until the next event"), tone: .accent)
        case .event:
            EmptyView()
        }
    }

    /// What it is beyond its title: the note or task it belongs to, its repeat, who set it; the calendar an event is
    /// on; how a past one ended.
    private func detail(_ entry: CalendarEntry, item: NotebookItem?, more: Int) -> String? {
        var parts: [String] = []
        if more > 0 { parts.append(String(localized: "\(more) more times this day", comment: "The Agenda: a reminder that repeats within the day")) }
        switch entry {
        case .reminder(let o):
            if o.at < Date() { parts.append(String(localized: "Overdue since \(TimeText.short(o.at))")) }
            if let item, item.title.lowercased() != o.reminder.title.lowercased() {
                parts.append(String(localized: "On a task in \(item.title)", comment: "The Agenda: the note or task a reminder belongs to"))
            }
            if let rule = o.reminder.recurrence { parts.append(Describe.recurrence(rule)) }
            if let who = Describe.source(o.reminder.source) {
                parts.append(String(localized: "from \(who)"))
            } else if o.reminder.source == "user", o.reminder.recurrence == nil {
                parts.append(String(localized: "You asked \(TimeText.short(o.reminder.createdAt))", comment: "The Agenda: when the person set a reminder, “You asked today 15:58”"))
            }
        case .due(let item):
            if let due = item.dueAt { parts.append(DueBadge.words(due, allDay: item.dueAllDay)) }
            if let who = Describe.source(item.source) { parts.append(String(localized: "from \(who)")) }
        case .finished(let r, let at):
            parts.append(r.state == .done
                         ? String(localized: "Done at \(TimeFormat.clock(at, calendar: .current))", comment: "The Agenda: when a reminder was done")
                         : String(localized: "Reminded you"))
        case .event(let e):
            if let place = e.location { parts.append(place) }
            if !e.calendar.isEmpty { parts.append(e.calendar) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The editor of a new thing added from a day's +.
    private func draftBinding(_ day: Date) -> Binding<CalendarNewDraft?> {
        Binding(get: { model.draft.flatMap { Calendar.current.isDate($0.start, inSameDayAs: day) && !$0.fromButton ? $0 : nil } }, set: { model.draft = $0 })
    }
}
