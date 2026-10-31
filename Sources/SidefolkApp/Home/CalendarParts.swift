import SidefolkCore
import SwiftUI

// What the Calendar's three views share (D66): how a thing looks, what a click on it does, its menu, and the sheet
// that adds a reminder at a time.

extension CalendarModel.Entry {
    /// Its picture: the note or task it belongs to, an alarm, a tick when done, a bell when it told you, a calendar.
    func symbol(item: NotebookItem?) -> String {
        switch self {
        case .reminder: item.map { ItemKindStyle.symbol($0.kind) } ?? "alarm"
        case .finished(let r, _): r.state == .done ? "checkmark" : "bell"
        case .event: "calendar"
        }
    }

    /// Its colour: Tempo's for what's to come, amber once late (it waits, it didn't fail), green when done, faint when
    /// it already told you, the theme's accent for the calendar's events (as on Today's line).
    var tint: Color {
        switch self {
        case .reminder(let o): o.at < Date() ? Theme.warning : Theme.folkColor("tempo")
        case .finished(let r, _): r.state == .done ? Theme.success : Theme.inkFaint
        case .event: Theme.accent
        }
    }

    var struck: Bool { if case .finished(let r, _) = self { r.state == .done } else { false } }

    /// "15:00 Call mom", for help and VoiceOver.
    var spoken: String {
        let time = allDay ? String(localized: "All day") : TimeFormat.clock(start, calendar: .current)
        switch self {
        case .finished(let r, _) where r.state == .done: return String(localized: "Done: \(title)") + ", " + time
        default: return "\(time) \(title)"
        }
    }
}

/// One thing as a small chip: its picture in its colour, the time, the title. A click opens it; Control-click has
/// what Today's menu has; a reminder's next time can be dragged to another day or time.
struct CalendarChip: View {
    var entry: CalendarModel.Entry
    var model: CalendarModel
    /// Where a chip is narrow, its place says its time and the title gets the room.
    var showsTime = true
    /// Too narrow for words (a busy hour in the week): the picture alone, its words in its help.
    var showsTitle = true
    var open: (CalendarModel.Entry) -> Void
    var edit: (Reminder) -> Void

    var body: some View {
        let chip = HStack(spacing: 4) {
            Image(systemName: entry.symbol(item: entry.reminder.flatMap(model.item))).imageScale(.small).foregroundStyle(entry.tint)
            if showsTime, !entry.allDay {
                Text(verbatim: TimeFormat.clock(entry.start, calendar: .current)).monospacedDigit().foregroundStyle(Theme.inkMuted)
                    .fixedSize()
            }
            if showsTitle {
                Text(verbatim: entry.title).strikethrough(entry.struck)
                    .foregroundStyle(entry.struck ? Theme.inkFaint : Theme.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(Theme.Font.caption)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(entry.tint.opacity(entry.allDay ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { open(entry) }
        .contextMenu { CalendarMenu(entry: entry, model: model, edit: edit) }
        .help(Text(verbatim: entry.spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.spoken))
        .accessibilityAddTraits(.isButton)
        if entry.movable, let reminder = entry.reminder {
            chip.draggable(reminder.id) { chip.frame(width: 160) }
        } else {
            chip
        }
    }
}

/// A thing's menu: a reminder's next time has all of Today's (ReminderMenu); a later time of a series edits the series
/// or opens its note; the calendar's events and what's past have nothing to change.
struct CalendarMenu: View {
    var entry: CalendarModel.Entry
    var model: CalendarModel
    var edit: (Reminder) -> Void

    var body: some View {
        if case .reminder(let o) = entry {
            if o.isNext {
                ReminderMenu(reminder: o.reminder, model: model.now, edit: edit)
            } else {
                if let item = model.item(of: o.reminder) { Button(ItemLink.openTitle(item.kind)) { model.now.open(item) } }
                Button("Edit…") { edit(o.reminder) }
            }
        } else if let reminder = entry.reminder, let item = model.item(of: reminder) {
            Button(ItemLink.openTitle(item.kind)) { model.now.open(item) }
        }
    }
}

/// A new reminder at a time chosen on the calendar: what to be reminded of, then Add. It's added through Guard, as
/// from the one bar.
struct NewReminderSheet: View {
    var at: Date
    var model: CalendarModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var when = ""
    @State private var error: UserFacingError?
    @State private var adding = false
    @FocusState private var whenFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New reminder").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            TextField("What", text: $title, prompt: Text("New reminder")).textFieldStyle(.roundedBorder)
                .onSubmit(add)
            // The time clicked on, written as the field writes a picked time; type over it to change it.
            WhenField(text: $when, prompt: Text("When, like “tomorrow 9:00”"), parser: model.now.whenParser, focus: $whenFocused,
                      submit: add)
                .textFieldStyle(.roundedBorder)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Add reminder", action: add)
                    .buttonStyle(.sf(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(adding || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 400)
        .onAppear { when = WhenText.phrase(for: at) }
    }

    private func add() {
        guard !adding, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        adding = true
        Task {
            error = await model.add(title, when: when)
            adding = false
            if error == nil { dismiss() }
        }
    }
}

/// A time to add a reminder at, as a sheet's item.
struct NewReminderTime: Identifiable {
    var at: Date
    var id: Date { at }
}
