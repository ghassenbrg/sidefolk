import SidefolkCore
import SwiftUI

/// The Calendar's list (D66): two weeks of days from the one in view, each with everything on it in time order, its
/// note or task, its repeat and who set it, and a way to add a reminder that day.
struct CalendarList: View {
    var model: CalendarModel
    var open: (CalendarModel.Entry) -> Void
    var edit: (Reminder) -> Void
    var add: (Date) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(model.days, id: \.self) { day in
                    let entries = model.entries(on: day)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(verbatim: TimeFormat.day(day, now: Date(), calendar: .autoupdatingCurrent))
                                .font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                            Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            Button { add(model.newTime(on: day)) } label: { Label("New reminder", systemImage: "plus").labelStyle(.iconOnly) }
                                .buttonStyle(.sf(.plain))
                                .help(Text("Add a reminder this day"))
                        }
                        RowsCard {
                            if entries.isEmpty {
                                Text("Nothing planned.").font(Theme.Font.body).foregroundStyle(Theme.inkFaint)
                                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                            }
                            ForEach(entries) { row($0) }
                        }
                    }
                }
            }
            .padding(.bottom, Theme.Space.l)
        }
    }

    private func row(_ entry: CalendarModel.Entry) -> some View {
        let item = entry.reminder.flatMap(model.item)
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            Group {
                if entry.allDay { Text("All day") } else { Text(verbatim: TimeFormat.clock(entry.start, calendar: .current)) }
            }
            .font(Theme.Font.captionStrong).monospacedDigit().foregroundStyle(entry.start < Date() && !entry.allDay ? Theme.inkMuted : Theme.ink)
            .frame(width: 56, alignment: .leading)
            Image(systemName: entry.symbol(item: item)).foregroundStyle(entry.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title).font(Theme.Font.body).strikethrough(entry.struck)
                    .foregroundStyle(entry.struck ? Theme.inkFaint : Theme.ink).fixedSize(horizontal: false, vertical: true)
                if let detail = detail(entry, item: item) {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if case .reminder(let o) = entry, o.isNext {
                CheckCircle(checked: false, label: Text("Mark “\(o.reminder.title)” done")) { Task { await model.now.complete(o.reminder) } }
            }
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s + 2)
        .contentShape(Rectangle())
        .onTapGesture { open(entry) }
        .contextMenu { CalendarMenu(entry: entry, model: model, edit: edit) }
        .accessibilityElement(children: .combine)
    }

    /// What it is beyond its title: the note or task it belongs to, its repeat, who set it; the calendar an event is
    /// on and until when; how a past one ended.
    private func detail(_ entry: CalendarModel.Entry, item: NotebookItem?) -> String? {
        var parts: [String] = []
        switch entry {
        case .reminder(let o):
            if o.at < Date() { parts.append(String(localized: "Overdue since \(TimeText.short(o.at))")) }
            if let item, item.title.lowercased() != o.reminder.title.lowercased() { parts.append(item.title) }
            if let rule = o.reminder.recurrence { parts.append(Describe.recurrence(rule)) }
            if let who = Describe.source(o.reminder.source) { parts.append(String(localized: "from \(who)")) }
        case .finished(let r, _):
            parts.append(r.state == .done
                         ? String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished")
                         : String(localized: "Reminded you"))
        case .event(let e):
            if !e.allDay { parts.append("\(TimeFormat.clock(e.start, calendar: .current))–\(TimeFormat.clock(e.end, calendar: .current))") }
            if !e.calendar.isEmpty { parts.append(e.calendar) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
