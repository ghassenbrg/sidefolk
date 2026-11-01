import SidefolkCore
import SwiftUI

/// A thing's details beside it (D95): its title in its colour, its calendar or kind, when (and its repeat), where with
/// a way to Maps, a web link, the people invited (read only) and the notes. Then what can be done: a reminder is done,
/// edited or taken off the calendar; an event Sidefolk may change is edited or deleted, any event opens in Calendar.
/// Text from an invitation is shown as it is and never acted on.
struct CalendarInspector: View {
    var entry: CalendarEntry
    var model: CalendarModel
    @Environment(\.undoManager) private var undo
    @State private var editing = false

    var body: some View {
        Group {
            if editing {
                switch entry {
                case .event(let e): CalendarEventForm(event: e, model: model) { editing = false }
                default: reminderForm
                }
            } else {
                details
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 340)
    }

    private var details: some View {
        let tint = model.tint(entry)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                RoundedRectangle(cornerRadius: 2).fill(tint.edge).frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.title.isEmpty ? String(localized: "No title", comment: "The Calendar: an event without a title") : entry.title)
                        .font(Theme.Font.title2).foregroundStyle(Theme.ink).strikethrough(entry.struck)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack(spacing: 5) {
                        Circle().fill(tint.edge).frame(width: 8, height: 8)
                        Text(verbatim: source).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            fact("clock", when)
            if let repeats { fact("repeat", repeats) }
            if entry.late { fact("exclamationmark.circle", String(localized: "Overdue since \(TimeText.short(entry.start))"), tone: Theme.warning) }
            if let e = entry.event {
                if let place = e.location {
                    HStack(alignment: .firstTextBaseline) {
                        fact("mappin.and.ellipse", place)
                        Spacer(minLength: Theme.Space.s)
                        Button("Maps") { openMaps(place) }.buttonStyle(.sf(.quiet)).help(Text("Open this place in Maps"))
                    }
                }
                if let link = e.url, let url = URL(string: link) {
                    Link(destination: url) {
                        Label { Text(verbatim: url.host() ?? link).lineLimit(1) } icon: { Image(systemName: "link") }
                    }
                    .font(Theme.Font.body).foregroundStyle(Theme.link)
                }
                if !e.attendees.isEmpty { attendees(e.attendees) }
                if let notes = e.notes {
                    ScrollView {
                        Text(verbatim: notes).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                if !e.changeable { readOnlyNote(e) }
            } else if let reminder = entry.reminder {
                if let item = model.item(of: reminder) {
                    Button { model.now.open(item) } label: {
                        Label { Text(ItemLink.openTitle(item.kind)) } icon: { Image(systemName: ItemKindStyle.symbol(item.kind)) }
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.link).font(Theme.Font.body)
                }
                if let who = Describe.source(reminder.source) { fact("person", String(localized: "from \(who)")) }
                if let notes = reminder.notes, !notes.isEmpty { fact("text.alignleft", notes) }
            }
            actions
        }
    }

    /// "Work · iCloud", or the kind for Sidefolk's own ("Reminders · Sidefolk").
    private var source: String {
        if let e = entry.event {
            let account = model.calendarInfo(e)?.account ?? ""
            return [e.calendar, account].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return model.kind(entry).name + " · Sidefolk"
    }

    /// "Sunday 1 November · 10:00–11:30", "Sunday 1 November · all day", "Sat 31 Oct – Mon 2 Nov".
    private var when: String {
        let cal = model.calendar
        let day = entry.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if entry.allDay {
            let last = entry.end.addingTimeInterval(-1)
            return cal.isDate(entry.start, inSameDayAs: last) ? day + " · " + String(localized: "all day")
                : (entry.start..<last).formatted(.interval.weekday(.abbreviated).day().month(.abbreviated))
        }
        if case .finished(let r, let at) = entry {
            return r.state == .done ? String(localized: "Done at \(TimeFormat.clock(at, calendar: cal))", comment: "The Agenda: when a reminder was done") + " · " + day
                : day + " · " + TimeFormat.clock(at, calendar: cal)
        }
        guard entry.end > entry.start else { return day + " · " + TimeFormat.clock(entry.start, calendar: cal) }
        if cal.isDate(entry.start, inSameDayAs: entry.end) {
            return day + " · " + CalendarEntry.span(entry.start, entry.end, calendar: cal)
        }
        return (entry.start..<entry.end).formatted(.interval.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    private var repeats: String? {
        if let rule = entry.reminder?.recurrence { return Describe.recurrence(rule) }
        if entry.event?.repeats == true { return String(localized: "Repeats", comment: "The Calendar's details: an event that is part of a series") }
        return nil
    }

    private func fact(_ symbol: String, _ text: String, tone: Color = Theme.ink) -> some View {
        Label { Text(verbatim: text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 16)
        }
        .font(Theme.Font.body)
        .foregroundStyle(tone)
    }

    /// The people invited, with their answers: read only, from the invitation.
    private func attendees(_ people: [CalendarAttendee]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(people.count) invited", comment: "The Calendar's details: how many people an event has").font(Theme.Font.captionStrong)
                .foregroundStyle(Theme.inkMuted)
            ForEach(Array(people.prefix(8).enumerated()), id: \.offset) { _, person in
                HStack(spacing: 6) {
                    Image(systemName: answerSymbol(person.answer)).foregroundStyle(answerTone(person.answer)).frame(width: 14)
                        .accessibilityLabel(answerWord(person.answer))
                    Text(verbatim: person.name).font(Theme.Font.callout).foregroundStyle(Theme.ink).lineLimit(1)
                    if person.organizer { Chip("Organizer", tone: .neutral) }
                    if person.isYou { Text("you", comment: "The Calendar's details: the person themselves among those invited").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint) }
                }
            }
            if people.count > 8 {
                Text("and \(people.count - 8) more", comment: "The Calendar's details: people invited beyond those listed").font(Theme.Font.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func answerSymbol(_ answer: CalendarAttendee.Answer) -> String {
        switch answer {
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle"
        case .tentative: "questionmark.circle"
        case .pending, .unknown: "circle.dotted"
        }
    }

    private func answerTone(_ answer: CalendarAttendee.Answer) -> Color {
        switch answer {
        case .accepted: Theme.success
        case .declined, .tentative, .pending, .unknown: Theme.inkMuted
        }
    }

    private func answerWord(_ answer: CalendarAttendee.Answer) -> Text {
        switch answer {
        case .accepted: Text("Going", comment: "The Calendar's details: an invited person said yes")
        case .declined: Text("Not going", comment: "The Calendar's details: an invited person said no")
        case .tentative: Text("Maybe", comment: "The Calendar's details: an invited person said maybe")
        case .pending, .unknown: Text("No answer yet", comment: "The Calendar's details: an invited person hasn't answered")
        }
    }

    /// Why an event can't be changed here, calmly, with where it can be.
    private func readOnlyNote(_ e: CalendarEvent) -> some View {
        Label {
            if !e.attendees.isEmpty {
                Text("Other people are invited, so it changes in Calendar, where you see who is told.")
            } else {
                Text("This calendar can't be changed from here.")
            }
        } icon: { Image(systemName: "lock") }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Theme.Space.s) {
            switch entry {
            case .reminder(let o):
                Button(o.reminder.recurrence == nil ? "Remove" : "Remove series") { model.delete(entry, undo: undo) }.buttonStyle(.sf(.destructive))
                Spacer()
                Button("Edit…") { editing = true }.buttonStyle(.sf(.secondary))
                if o.isNext {
                    Button(String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished")) {
                        model.inspecting = nil
                        Task { await model.complete(o.reminder) }
                    }
                    .buttonStyle(.sf(.primary))
                }
            case .finished:
                Spacer()
            case .event(let e):
                if e.changeable {
                    Button(e.repeats ? "Delete this time" : "Delete") { model.delete(entry, undo: undo) }.buttonStyle(.sf(.destructive))
                    Spacer()
                    Button("Open in Calendar") { model.openInCalendar(e) }.buttonStyle(.sf(.quiet))
                    Button("Edit…") { model.whenWritesAllowed { editing = true } }.buttonStyle(.sf(.primary))
                } else {
                    Spacer()
                    Button("Open in Calendar") { model.openInCalendar(e) }.buttonStyle(.sf(.primary))
                }
            }
        }
    }

    // MARK: Editing a reminder

    @State private var title = ""
    @State private var whenText = ""
    @State private var error: UserFacingError?
    @FocusState private var whenFocused: Bool

    private var reminderForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Edit reminder").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            TextField("What", text: $title).lanternField()
            WhenField(text: $whenText, prompt: Text("When, like “tomorrow 9am” or “every 30 minutes”"), parser: model.now.whenParser,
                      focus: $whenFocused, emptyHint: Text("Leave empty to keep \(TimeFormat.when(entry.start, now: Date(), calendar: model.calendar))"), boxed: true)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { editing = false }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let reminder = entry.reminder else { return }
                    Task {
                        error = await model.now.edit(reminder, title: title, when: whenText)
                        if error == nil {
                            editing = false
                            await model.reload()
                        }
                    }
                }
                .buttonStyle(.sf(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { title = entry.title }
    }

    private func openMaps(_ place: String) {
        var parts = URLComponents(string: "maps://")
        parts?.queryItems = [URLQueryItem(name: "q", value: place)]
        if let url = parts?.url { NSWorkspace.shared.open(url) }
    }
}

/// An event's fields to change (D95): title, all day, start and end, its calendar, where, notes. Saving is
/// `calendar.update`, with ⌘Z.
struct CalendarEventForm: View {
    var event: CalendarEvent
    var model: CalendarModel
    var done: () -> Void
    @Environment(\.undoManager) private var undo
    @State private var draft: CalendarDraft
    @State private var calendarId: String?

    init(event: CalendarEvent, model: CalendarModel, done: @escaping () -> Void) {
        self.event = event
        self.model = model
        self.done = done
        _draft = State(initialValue: event.draft)
        _calendarId = State(initialValue: event.calendarId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            TextField("Title", text: $draft.title).lanternField().font(Theme.Font.headline)
            Toggle("All day", isOn: $draft.allDay).toggleStyle(.switch).controlSize(.small)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
                GridRow {
                    Text("Starts", comment: "The Calendar's editor: when an event starts").foregroundStyle(Theme.inkMuted)
                    DatePicker("Starts", selection: $draft.start, displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute]).labelsHidden()
                }
                GridRow {
                    Text("Ends", comment: "The Calendar's editor: when an event ends").foregroundStyle(Theme.inkMuted)
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute]).labelsHidden()
                }
            }
            .font(Theme.Font.body)
            CalendarPickerMenu(model: model, selection: $calendarId)
            TextField("Location", text: Binding(get: { draft.location ?? "" }, set: { draft.location = $0.isEmpty ? nil : $0 }),
                      prompt: Text("Location", comment: "The Calendar's editor: where an event is")).lanternField()
            TextField("Notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                .lineLimit(3...6).lanternField()
            if event.repeats {
                Text("Only this time of the series changes.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Save") {
                    var next = draft
                    next.calendarId = calendarId
                    if next.allDay, next.end <= next.start { next.end = next.start.addingTimeInterval(86400) }
                    model.change(event, to: next, undo: undo)
                    done()
                    model.inspecting = nil
                }
                .buttonStyle(.sf(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
