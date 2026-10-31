import SidefolkCore
import SwiftUI

/// A note or task's reminder in the Notebook (D49): the bell beside it, the times to pick from, and a sheet for any
/// other time. The reminder belongs to the item: done or trashed, it stops; opened or restored, it comes back.

/// "Tomorrow 09:00" with a bell, under an item that has a reminder.
struct ReminderBadge: View {
    var reminder: Reminder

    var body: some View {
        Label {
            Text(verbatim: when)
        } icon: {
            Image(systemName: reminder.recurrence == nil ? "bell" : "bell.and.waves.left.and.right")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Theme.link)
        .accessibilityLabel(Text("Reminder \(when)"))
    }

    private var when: String { ReminderBadge.when(reminder) }

    static func when(_ reminder: Reminder) -> String {
        TimeFormat.when(reminder.nextDue ?? reminder.fireAt, now: Date(), calendar: .autoupdatingCurrent)
    }
}

/// The items of a "Remind me" menu: quick times, any other time, and taking the reminder away.
struct RemindMenuItems: View {
    var item: NotebookItem
    var model: NotebookModel

    var body: some View {
        ForEach(model.remindPresets(), id: \.preset) { choice in
            Button {
                Task { await model.remind(item, at: choice.date) }
            } label: {
                Text(verbatim: "\(choice.preset.title) (\(TimeFormat.clock(choice.date, calendar: .autoupdatingCurrent)))")
            }
        }
        Button("Pick a time…") { model.pickingTime = item }
        if model.reminders[item.id] != nil {
            Divider()
            Button("Remove reminder", role: .destructive) { Task { await model.removeReminder(of: item) } }
        }
    }

    /// A done task, or an item without words yet, has nothing to be reminded about.
    static func offered(for item: NotebookItem) -> Bool {
        !(item.kind == .task && item.status == .done) && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The editor's bell, with the same menu as the list. Just the icon: the bar beside it is full with a task's pickers and
/// Done; the time is under the title.
struct RemindButton: View {
    var item: NotebookItem
    var model: NotebookModel

    var body: some View {
        let reminder = model.reminders[item.id]
        Menu {
            RemindMenuItems(item: item, model: model)
        } label: {
            Label("Remind me", systemImage: reminder == nil ? "bell" : "bell.fill").labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.sf(.secondary))
        .fixedSize()
        .disabled(!RemindMenuItems.offered(for: item))
        .help(reminder.map { Text("Reminder \(ReminderBadge.when($0))") } ?? Text("Remind me"))
    }
}

/// Any other time for a note or task's reminder: typed ("monday at 9", "every friday") or picked, one value.
struct PickReminderTimeSheet: View {
    var item: NotebookItem
    var model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = PickReminderTimeSheet.nextHour()
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        let parser = WhenParser(settings: model.services.runtime.settings.current)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Remind me about “\(item.title.clipped(60))”").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            WhenField(text: $text, prompt: Text("When, like “tomorrow 9:00”"), parser: parser, focus: $typing, showsPicker: false,
                      submit: set)
                .textFieldStyle(.roundedBorder)
            DatePicker("When", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Set reminder", action: set)
                    .buttonStyle(.sf(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(date <= Date())
            }
        }
        // Typing moves the picker; picking writes the field.
        .onChange(of: text) {
            if let reading = WhenReading(text, parser: parser), !reading.past, reading.date != date { date = reading.date }
        }
        .onChange(of: date) {
            if WhenReading(text, parser: parser)?.date != date { text = WhenText.phrase(for: date, timeZone: parser.calendar.timeZone) }
        }
        .onAppear {
            text = WhenText.phrase(for: date, timeZone: parser.calendar.timeZone)
            typing = true
        }
        .padding(Theme.Space.xl)
        .frame(width: 360)
    }

    /// What was typed, when it says more than the picker can (a repeat); else the picked time.
    private func set() {
        guard date > Date() else { return }
        let when = date
        let parser = WhenParser(settings: model.services.runtime.settings.current)
        let phrase = WhenReading(text, parser: parser).map { _ in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        dismiss()
        Task { await model.remind(item, at: when, phrase: phrase) }
    }

    /// The next whole hour: a time most people would pick anyway.
    static func nextHour(after now: Date = Date()) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now.addingTimeInterval(3600)
    }
}
