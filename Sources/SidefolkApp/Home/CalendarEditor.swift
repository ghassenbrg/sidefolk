import SidefolkCore
import SwiftUI

/// The editor a new thing opens where it was placed (D97): its title first, then what it is (a reminder, a task in a
/// collection, or an event in one of the person's calendars), and when. Return adds it, Escape lets it go. Reminders
/// and tasks take the when field's words ("every monday 9"); an event takes a start and an end.
struct CalendarEditor: View {
    var model: CalendarModel
    var draft: CalendarNewDraft
    @Environment(\.undoManager) private var undo
    @State private var title = ""
    @State private var kind: CalendarModel.NewKind = .reminder
    @State private var when = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var allDay = false
    @State private var calendarId: String?
    @State private var collection: String?
    @State private var location = ""
    @State private var error: UserFacingError?
    @State private var adding = false
    @FocusState private var titleFocused: Bool
    @FocusState private var whenFocused: Bool

    /// Events only where there is a calendar Sidefolk could add one to.
    private var kinds: [SegmentedPicker<CalendarModel.NewKind>.Segment] {
        var all: [SegmentedPicker<CalendarModel.NewKind>.Segment] = [
            .init(.reminder, Text("Reminder", comment: "The Calendar's editor: what a new thing is"), symbol: "alarm"),
            .init(.task, Text("Task", comment: "The Calendar's editor: what a new thing is"), symbol: "checkmark.circle"),
        ]
        if model.calendarOn, !model.writableCalendars.isEmpty {
            all.append(.init(.event, Text("Event", comment: "The Calendar's editor: what a new thing is"), symbol: "calendar"))
        }
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            TextField("Title", text: $title, prompt: Text(verbatim: "")).fieldHint(Text(placeholder), showing: title.isEmpty).lanternField()
                .accessibilityLabel("Title")
                .font(Theme.Font.headline)
                .focused($titleFocused)
                .onSubmit(add)
            SegmentedPicker("Kind", selection: $kind, segments: kinds, small: true, equalWidths: true)
            switch kind {
            case .reminder, .task:
                WhenField(text: $when, prompt: Text("When, like “tomorrow 9:00”"), parser: model.now.whenParser, focus: $whenFocused,
                          boxed: true, submit: add)
                if kind == .task { collectionPicker }
            case .event:
                Toggle("All day", isOn: $allDay).toggleStyle(.switch).controlSize(.small)
                Grid(alignment: .leading, horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
                    GridRow {
                        Text("Starts", comment: "The Calendar's editor: when an event starts").foregroundStyle(Theme.inkMuted)
                        DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).labelsHidden()
                    }
                    GridRow {
                        Text("Ends", comment: "The Calendar's editor: when an event ends").foregroundStyle(Theme.inkMuted)
                        DatePicker("Ends", selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).labelsHidden()
                    }
                }
                .font(Theme.Font.body)
                CalendarPickerMenu(model: model, selection: $calendarId)
                TextField("Location", text: $location, prompt: Text(verbatim: "")).fieldHint(Text("Location", comment: "The Calendar's editor: where an event is"), showing: location.isEmpty, spoken: false).lanternField()
                    .accessibilityLabel(Text("Location", comment: "The Calendar's editor: where an event is"))
                if !model.writesOn {
                    Label { Text("Sidefolk asks once before it changes your calendars.") } icon: { Image(systemName: "lock") }
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { model.draft = nil }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button(addTitle, action: add)
                    .buttonStyle(.sf(.primary, size: .small, working: adding))
                    .keyboardShortcut(.defaultAction)
                    .disabled(adding || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 320)
        .onAppear {
            start = draft.start
            end = max(draft.end, draft.start.addingTimeInterval(draft.allDay ? 86400 : 900))
            allDay = draft.allDay
            when = WhenText.phrase(for: draft.start)
            calendarId = model.writableCalendars.first?.id
            if draft.allDay, kinds.contains(where: { $0.value == .event }) { kind = .event }
        }
        .task {
            // A popover takes the keyboard once it is on screen; asking sooner leaves the title without it.
            try? await Task.sleep(for: .milliseconds(80))
            titleFocused = true
            await model.loadCollections()
        }
    }

    private var placeholder: String {
        switch kind {
        case .reminder: String(localized: "New reminder")
        case .task: String(localized: "New task", comment: "The Calendar's editor: a new task's title before it's typed")
        case .event: String(localized: "New event", comment: "The Calendar's editor: a new event's title before it's typed")
        }
    }

    private var addTitle: LocalizedStringKey {
        switch kind {
        case .reminder: "Add reminder"
        case .task: "Add task"
        case .event: "Add event"
        }
    }

    /// Which collection a task goes in: the Inbox unless one is chosen.
    private var collectionPicker: some View {
        Picker(selection: $collection) {
            Text("Inbox").tag(String?.none)
            ForEach(model.collections.filter { $0.kind != .inbox }) { c in
                Text(verbatim: NotebookCollections.shownName(c)).tag(Optional(c.name))
            }
        } label: {
            Text("In", comment: "The Calendar's editor: which collection a new task goes in")
        }
        .pickerStyle(.menu)
        .font(Theme.Font.body)
    }

    private func add() {
        guard !adding, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if kind == .event, end <= start { end = start.addingTimeInterval(allDay ? 86400 : 3600) }
        adding = true
        Task {
            error = await model.add(kind, title: title, when: when, start: start, end: allDay ? max(end, start) : end, allDay: allDay,
                                    calendarId: calendarId, collection: collection, location: location, undo: undo)
            adding = false
            if error == nil { model.draft = nil }
        }
    }
}

/// Which of the person's writable calendars an event goes in, each with its colour.
struct CalendarPickerMenu: View {
    var model: CalendarModel
    @Binding var selection: String?

    var body: some View {
        Picker(selection: $selection) {
            ForEach(model.writableCalendars) { info in
                Label {
                    Text(verbatim: info.account.isEmpty ? info.title : "\(info.title) · \(info.account)")
                } icon: {
                    Image(nsImage: CalendarDot.image(info.color.hex))
                }
                .tag(Optional(info.id))
            }
        } label: {
            Text("Calendar", comment: "The Calendar's editor: which of the person's calendars an event goes in")
        }
        .pickerStyle(.menu)
        .font(Theme.Font.body)
    }
}

/// A calendar's colour as a small round picture, for menus (which draw images, not views).
enum CalendarDot {
    @MainActor private static var cache: [UInt32: NSImage] = [:]

    @MainActor static func image(_ hex: UInt32) -> NSImage {
        if let known = cache[hex] { return known }
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor(hex: hex).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        cache[hex] = image
        return image
    }
}

/// The first change to the Mac's calendar asks once (D97): what Sidefolk will and won't do, then Allow or Not now.
struct CalendarWritesSheet: View {
    var model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 28)).foregroundStyle(Theme.accent)
                Text("Let Sidefolk change your calendars?").font(Theme.Font.title2).foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                point("plus.circle", Text("Add, move, resize and delete events in your Mac's calendars from here, as you would in Calendar."))
                point("arrow.uturn.backward", Text("Every change is in History, and ⌘Z or Undo puts it back."))
                point("person.2", Text("Never events other people are invited to (changing them would tell them), calendars you can't edit, or a whole repeating series."))
                point("sparkles", Text("Your AI changes events through Guard, as your Trust settings say, and asks you every time before it deletes one."))
            }
            Text("You can turn this off in Settings › Trust › Your calendar.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            HStack {
                Spacer()
                Button("Not now") { model.answerWrites(false) }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
                Button("Allow changes") { model.answerWrites(true) }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Size.sheet)
    }

    private func point(_ symbol: String, _ text: Text) -> some View {
        Label { text.fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 18) }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
    }
}
