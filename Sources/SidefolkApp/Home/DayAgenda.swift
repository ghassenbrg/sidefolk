import SidefolkCore
import SwiftUI

/// What undo registrations hang on: SwiftUI views aren't objects.
private final class UndoBox: NSObject {
    @MainActor static let shared = UndoBox()
}

/// Today's day as a list down the side (D130): what's next reads first, with a marker where now is. The calendar's events,
/// each in its calendar's colour, and the reminders, which move: drag one up or down, or press ← → on it, a quarter hour at
/// a time (⌘Z puts it back); double-click the card's empty space, or +, to add one. What's done today stays, struck through;
/// a reminder's menu (Control-click) ticks, snoozes and edits it.
struct DayAgenda: View {
    /// An event in a calendar with no colour.
    static let noCalendarColor: UInt32 = 0x8E8E93
    private static let step: TimeInterval = 15 * 60
    /// How much of the day shows at once: a day of repeats shouldn't push On duty out of sight.
    private static let pastShown = 2, nextShown = 6
    /// The + was pressed on a day that already has things in it, so the row for a new reminder shows.
    @State private var adding = false

    var model: NowModel
    var edit: (Reminder) -> Void
    var openCalendar: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var problem: UserFacingError?

    private enum Item: Identifiable {
        case reminder(Reminder, due: Date)
        case done(Reminder, at: Date)
        case event(CalendarEvent)
        case now(Date)

        var id: String {
            switch self {
            case .reminder(let r, _): "r" + r.id
            case .done(let r, _): "d" + r.id
            case .event(let e): "e" + e.id
            case .now: "now"
            }
        }
        var at: Date {
            switch self {
            case .reminder(_, let due): due
            case .done(_, let at): at
            case .event(let e): e.start
            case .now(let at): at
            }
        }
    }

    var body: some View {
        // Each minute, so where now is keeps up with a page nothing else changes on.
        TimelineView(.everyMinute) { _ in day }
    }

    @ViewBuilder private var day: some View {
        let now = Date()
        let today = model.groups().first { $0.day == .today }?.reminders ?? []
        let events = model.events(on: .today)
        let items = (events.filter { !$0.allDay }.map(Item.event)
            + today.map { Item.reminder($0, due: $0.nextDue ?? $0.fireAt) }
            + model.doneToday.map { Item.done($0, at: $0.lastFiredAt ?? $0.fireAt) })
            .sorted { $0.at < $1.at }
        let past = items.filter { $0.at <= now }, next = items.filter { $0.at > now }
        // What's still waiting stays in view however many came after it: a late reminder, a meeting under way.
        let recent = Set(past.suffix(Self.pastShown).map(\.id))
        let shownPast = past.filter { item in
            switch item {
            case .reminder: true
            case .event(let e): e.end > now || recent.contains(item.id)
            case .done: recent.contains(item.id)
            case .now: true
            }
        }
        let hidden = past.count - shownPast.count + max(0, next.count - Self.nextShown)
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(events.filter(\.allDay)) { allDay($0) }
            // One list, the now line among the rows: a late reminder moved past it stays the same row, keyboard and all.
            ForEach(shownPast + [.now(now)] + next.prefix(Self.nextShown)) { row($0, now: now) }
            if hidden > 0 {
                Button(action: openCalendar) { Text("\(hidden) more today", comment: "Today's list of the day: what it doesn't show, opening the Calendar") }
                    .buttonStyle(.sf(.quiet))
                    .padding(.horizontal, Theme.Space.s)
            }
            if let problem {
                InlineError(error: problem).padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.xs)
            }
            if !model.calendarOn {
                InlineEmpty(text: "Show your Mac calendar here too, beside your reminders.", systemImage: "calendar",
                            actionTitle: "Allow") { Task { await model.showCalendar() } }
            }
            if adding || (items.isEmpty && events.isEmpty) { NewReminderRow(model: model, focusAtOnce: adding) }
            Spacer().frame(height: Theme.Space.s)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { addReminder() }
        .cardSurface()
        // The new reminder is on the list now, so its row goes.
        .onChange(of: items.count) { adding = false }
        .onExitCommand { adding = false }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Your day").font(Theme.Font.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.xs)
            Button(action: addReminder) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.sfIcon(side: 22))
                .foregroundStyle(Theme.inkMuted)
                .help("New reminder")
                .accessibilityLabel("New reminder")
            Button("Open Calendar", action: openCalendar).buttonStyle(.sf(.quiet))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
    }

    /// A reminder at the next quarter hour, as double-clicking an empty time always made.
    private func addReminder() {
        adding = true
        model.newReminder(at: Self.snap(Date().addingTimeInterval(Self.step / 2)))
    }

    private static func snap(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    private func nowLine(_ now: Date) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(verbatim: TimeFormat.clock(now, calendar: .current)).font(Theme.Font.captionStrong).monospacedDigit().foregroundStyle(Theme.link)
                .frame(width: Self.timeWidth, alignment: .trailing)
            Circle().fill(Theme.link).frame(width: 7, height: 7)
            Rectangle().fill(Theme.link.opacity(0.5)).frame(height: 1)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now, \(TimeFormat.clock(now, calendar: .current))", comment: "VoiceOver: where now is in the day's list"))
    }

    fileprivate static let timeWidth: CGFloat = 44

    private func allDay(_ event: CalendarEvent) -> some View {
        // Its words at the row's end: the time column is too narrow for them in German and Arabic.
        AgendaLine(time: Text(verbatim: ""), mark: AnyView(Circle().fill(CalendarTint.of(event.color?.hex ?? Self.noCalendarColor).edge)),
                   title: event.title, faded: false, note: Text("All day", comment: "An event with no time, in the day's list"))
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func row(_ item: Item, now: Date) -> some View {
        switch item {
        case .now(let at):
            nowLine(at)
        case .event(let event):
            AgendaLine(time: Text(verbatim: TimeFormat.clock(event.start, calendar: .current)),
                       mark: AnyView(Circle().fill(CalendarTint.of(event.color?.hex ?? Self.noCalendarColor).edge)),
                       title: event.title, faded: event.end <= now)
                .help(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current))–\(TimeFormat.clock(event.end, calendar: .current)) \(event.title)"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current)) \(event.title)"))
        case .reminder(let reminder, let due):
            AgendaReminder(reminder: reminder, due: due, late: due < now) { shift(reminder, from: due, to: due.addingTimeInterval($0 * 60)) } drop: { steps in
                shift(reminder, from: due, to: Self.snap(due.addingTimeInterval(Double(steps) * Self.step)))
            }
            .contextMenu { ReminderMenu(reminder: reminder, model: model, edit: edit) }
        case .done(let reminder, let at):
            AgendaLine(time: Text(verbatim: TimeFormat.clock(at, calendar: .current)),
                       mark: AnyView(Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.success)),
                       title: reminder.title, faded: true, struck: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Done: \(reminder.title)"))
        }
    }

    /// Moves it, never into the past, and lets ⌘Z put it back while that time is still to come.
    private func shift(_ reminder: Reminder, from due: Date, to target: Date) {
        let target = max(target, Self.snap(Date().addingTimeInterval(Self.step / 2)))
        guard abs(target.timeIntervalSince(due)) >= 60 else { return }
        Task { @MainActor in
            problem = await model.move(reminder, to: target)
            guard problem == nil, let undoManager else { return }
            let model = model
            undoManager.registerUndo(withTarget: UndoBox.shared) { _ in
                guard due > Date() else { return }
                Task { @MainActor in _ = await model.move(reminder, to: due) }
            }
            undoManager.setActionName(String(localized: "Move Reminder"))
        }
    }
}

/// One line of the day: its time, a mark, its title.
private struct AgendaLine: View {
    var time: Text
    var mark: AnyView
    var title: String
    var faded: Bool
    var struck = false
    var note: Text?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            time.font(Theme.Font.callout).monospacedDigit().foregroundStyle(Theme.inkFaint)
                .lineLimit(1).frame(width: DayAgenda.timeWidth, alignment: .trailing)
            mark.frame(width: 7, height: 7)
            Text(verbatim: title).font(Theme.Font.body).strikethrough(struck)
                .foregroundStyle(faded ? Theme.inkMuted : Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            note?.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, 7)
    }

}

/// A reminder in the day's list: drag it up or down, or ← → on it, a quarter hour at a time; VoiceOver adjusts it the same
/// way. While it's dragged its time says where it will land.
private struct AgendaReminder: View {
    /// Points of drag for a quarter hour.
    private static let stepHeight: CGFloat = 8
    @MainActor private static var blue: Color { CalendarTint.of(CalendarEntry.Kind.reminder.hex).edge }

    var reminder: Reminder
    var due: Date
    var late: Bool
    var nudge: (Double) -> Void
    var drop: (Int) -> Void
    @GestureState private var drag: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        let steps = Int((drag / Self.stepHeight).rounded())
        let shown = due.addingTimeInterval(Double(steps) * 15 * 60)
        HStack(spacing: Theme.Space.s) {
            Text(verbatim: TimeFormat.clock(shown, calendar: .current)).font(Theme.Font.callout).monospacedDigit()
                .foregroundStyle(late ? Theme.warning : drag == 0 ? Theme.inkFaint : Theme.link)
                .frame(width: DayAgenda.timeWidth, alignment: .trailing)
            // Late still waits to be done: amber, with "late" in words.
            Circle().strokeBorder(late ? Theme.warning : Self.blue, lineWidth: 1.5).frame(width: 7, height: 7)
            Text(verbatim: reminder.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            if late {
                Text("late", comment: "A reminder in the day's list whose time passed").font(Theme.Font.callout.weight(.medium)).foregroundStyle(Theme.warning)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, 7)
        .background(focused ? Theme.accentSoft.opacity(0.6) : .clear)
        .overlay(alignment: .leading) { if focused { Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 5) } }
        .offset(y: drag)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in drop(Int((value.translation.height / Self.stepHeight).rounded())) })
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { nudge(-15); return .handled }
        .onKeyPress(.rightArrow) { nudge(15); return .handled }
        .help(Text("Drag to move it, or use ← and → a quarter hour at a time"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(TimeFormat.clock(due, calendar: .current)) \(reminder.title)"))
        .accessibilityHint(Text("Adjust to move it a quarter hour"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(15)
            case .decrement: nudge(-15)
            @unknown default: break
            }
        }
    }
}
