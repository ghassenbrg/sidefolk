import SidefolkCore
import SwiftUI

/// Home › Calendar (D66): a month, a week or a list of days, with Today, ← and → and the mode at the top. ← → (or the
/// chevrons) step back and ahead, T comes back to today. A click opens a thing; a double-click on an empty day or time
/// adds a reminder there; a reminder's next time can be dragged to another day or time, ⌘Z putting it back.
struct CalendarView: View {
    @Bindable var model: CalendarModel
    @State private var editing: Reminder?
    @State private var adding: NewReminderTime?
    @FocusState private var focused: Bool
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            if !model.calendarOn {
                RowsCard {
                    InlineEmpty(text: "Your calendar can be here too, beside your reminders.", systemImage: "calendar",
                                actionTitle: "Show my calendar") { Task { await model.showCalendar() } }
                }
            }
            if let problem = model.problem {
                InlineError(error: problem)
            }
            switch model.mode {
            case .month: CalendarMonth(model: model, open: open, edit: { editing = $0 }) { adding = NewReminderTime(at: $0) }
            case .week: CalendarWeek(model: model, open: open, edit: { editing = $0 }) { adding = NewReminderTime(at: $0) }
            case .day: CalendarList(model: model, open: open, edit: { editing = $0 }) { adding = NewReminderTime(at: $0) }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfaceSunken)
        // The page takes the keyboard, so ← → and T work without stealing them from the one bar's field.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(characters: ["t", "T"]) { _ in
            model.today()
            return .handled
        }
        .onAppear { focused = true }
        .task { await model.reload() }
        .sheet(item: $editing) { EditReminderSheet(reminder: $0, model: model.now) }
        .sheet(item: $adding) { NewReminderSheet(at: $0.at, model: model) }
    }

    /// ← is back in time where text runs left to right, ahead where it runs right to left.
    private func step(_ key: Int) -> KeyPress.Result {
        model.go(direction == .rightToLeft ? -key : key)
        return .handled
    }

    private var header: some View {
        WrapRow(minimum: 220, spacing: Theme.Space.m) {
            Text(verbatim: model.title).font(Theme.Font.title).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.Space.s) {
                Button("Today") { model.today() }.buttonStyle(.sf(.secondary)).help(Text("Back to today (T)"))
                HStack(spacing: 0) {
                    Button { model.go(-1) } label: { Image(systemName: "chevron.backward").frame(width: 24, height: 22) }
                        .help(Text(previousHelp)).accessibilityLabel(Text(previousHelp))
                    Button { model.go(1) } label: { Image(systemName: "chevron.forward").frame(width: 24, height: 22) }
                        .help(Text(nextHelp)).accessibilityLabel(Text(nextHelp))
                }
                .buttonStyle(.sf(.plain))
                Picker("View", selection: $model.mode) {
                    Text("Month").tag(CalendarModel.Mode.month)
                    Text("Week").tag(CalendarModel.Mode.week)
                    Text("Day", comment: "The Calendar's list of days, from one day").tag(CalendarModel.Mode.day)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .fixedSize()
        }
    }

    private var previousHelp: LocalizedStringKey {
        switch model.mode {
        case .month: "Show the previous month"
        case .week: "Show the previous week"
        case .day: "Show the previous day"
        }
    }

    private var nextHelp: LocalizedStringKey {
        switch model.mode {
        case .month: "Show the next month"
        case .week: "Show the next week"
        case .day: "Show the next day"
        }
    }

    /// A click on a thing: a reminder that belongs to a note or task opens it in the Notebook (D49); another reminder
    /// opens its editor; the calendar's events say what they are in their help, and stay in the Calendar app (D57).
    private func open(_ entry: CalendarModel.Entry) {
        guard let reminder = entry.reminder else { return }
        if let item = model.item(of: reminder) {
            model.now.open(item)
        } else if case .reminder = entry {
            editing = reminder
        }
    }
}
