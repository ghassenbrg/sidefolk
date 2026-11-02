import SidefolkCore
import SwiftUI

/// When a task is due (D117), in the Notebook. It isn't a reminder: a due date says when, and a reminder when to nudge,
/// and a task can have either, both or neither. Late says so in amber and in words (D78), and nothing comes of it.

/// "Due tomorrow" with a calendar, under a task with a date.
struct DueBadge: View {
    var due: Date
    var allDay: Bool

    var body: some View {
        let late = Self.isLate(due, allDay: allDay)
        Label { Text(verbatim: Self.words(due, allDay: allDay)) } icon: { Image(systemName: "calendar") }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(late ? Theme.warning : Theme.inkMuted)
    }

    static func isLate(_ due: Date, allDay: Bool, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        allDay ? due < calendar.startOfDay(for: now) : due < now
    }

    static func words(_ due: Date, allDay: Bool, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        let when = allDay ? TimeFormat.day(due, now: now, calendar: calendar) : TimeFormat.when(due, now: now, calendar: calendar)
        return isLate(due, allDay: allDay, now: now, calendar: calendar)
            ? String(localized: "Was due \(when)", comment: "A task: when it was due, already past")
            : String(localized: "Due \(when)", comment: "A task: when it's due")
    }
}

/// The editor's calendar button: quick days, any other, and taking it away.
struct DueButton: View {
    var item: NotebookItem
    var model: NotebookModel

    var body: some View {
        Menu {
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: Date())
            ForEach([(Text("Today"), 0), (Text("Tomorrow"), 1), (Text("Next week", comment: "A task's due date: a week from today"), 7)], id: \.1) { choice in
                Button {
                    let day = calendar.date(byAdding: .day, value: choice.1, to: today) ?? today
                    Task { await model.setDue(item, at: NoteDue.dayInstant(day, calendar: calendar), allDay: true) }
                } label: { choice.0 }
            }
            Button("Pick a date…") { model.pickingDue = item }
            if item.dueAt != nil {
                Divider()
                Button("Remove due date", role: .destructive) { Task { await model.setDue(item, at: nil, allDay: false) } }
            }
        } label: {
            Label("Due date", systemImage: item.dueAt == nil ? "calendar" : "calendar.badge.clock").labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.sf(.secondary))
        .fixedSize()
        .disabled(item.status == .done)
        .help(item.dueAt.map { Text(verbatim: DueBadge.words($0, allDay: item.dueAllDay)) } ?? Text("When it's due. It shows on the Calendar and nudges nobody; for a nudge, set a reminder too."))
    }
}

/// Any date, with a time if it has one.
struct PickDueDateSheet: View {
    var item: NotebookItem
    var model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var withTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("When is it due?", comment: "A task's due date").font(Theme.Font.headline).foregroundStyle(Theme.ink)
            Text(verbatim: item.title).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2)
            DatePicker(selection: $date, displayedComponents: withTime ? [.date, .hourAndMinute] : [.date]) { Text("Date") }
                .datePickerStyle(.field).labelsHidden()
            Toggle(isOn: $withTime) { Text("At a time", comment: "A task's due date: with a time, not just a day") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button("Set") {
                    let calendar = Calendar.autoupdatingCurrent
                    let chosen = withTime ? date : NoteDue.dayInstant(date, calendar: calendar)
                    Task { await model.setDue(item, at: chosen, allDay: !withTime) }
                    dismiss()
                }
                .buttonStyle(.sfPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 320)
        .onAppear {
            date = item.dueAt ?? Date()
            withTime = item.dueAt != nil && !item.dueAllDay
        }
    }
}
