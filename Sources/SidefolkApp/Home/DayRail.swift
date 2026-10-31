import SidefolkCore
import SwiftUI

/// Today as a line (D58): the hours around now, the calendar's events as blocks and reminders as chips, with a line at
/// the present. Drag a reminder, or press ← → on it, to move it by quarter hours (⌘Z puts it back); double-click an
/// empty time to add a reminder there. What's done today stays on it, struck through; a reminder's menu (Control-click)
/// ticks, snoozes and edits it.
struct DayRail: View {
    var reminders: [Reminder]
    var done: [Reminder] = []
    var events: [CalendarEvent]
    var now: Date
    var move: (Reminder, Date) async -> UserFacingError?
    var add: (Date) -> Void
    var menu: (Reminder) -> AnyView = { _ in AnyView(EmptyView()) }
    @Environment(\.undoManager) private var undoManager
    @State private var problem: UserFacingError?
    /// The rail's width, measured; laying out happens in points, so a short event still shows its title.
    @State private var width: CGFloat = 640
    /// An hour label's width in the theme's caption font, measured, so labels are spaced by what they really take.
    @State private var labelWidth: CGFloat = 32

    private static let step: TimeInterval = 15 * 60
    private static let lane: CGFloat = 44

    var body: some View {
        let span = range
        let shown = items(in: span)
        let placed = DayLine.place(shown.map { DayLine.Item(start: $0.start, end: $0.end, readable: readable($0)) },
                                   in: span, width: Double(width))
        let lanes = max(1, (placed.map(\.lane).max() ?? 0) + 1)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack(alignment: .topLeading) {
                hours(span, width: width, height: CGFloat(lanes) * Self.lane)
                // Under the items, so it never crosses their words.
                nowLine(span, width: width, height: CGFloat(lanes) * Self.lane)
                // Double-click an empty time: a reminder there.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        add(snap(DayLine.time(at: Double(location.x), in: span, width: Double(width))))
                    }
                ForEach(Array(zip(shown, placed)), id: \.0.id) { item, place in
                    view(item, place, span: span)
                        .offset(x: CGFloat(place.x), y: CGFloat(place.lane) * Self.lane)
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(lanes) * Self.lane + 20, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
            .background(alignment: .topLeading) {
                Text(verbatim: "00:00").font(Theme.Font.caption).monospacedDigit().fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            }
            if let problem {
                InlineError(error: problem)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
    }

    // MARK: Time and place

    /// The hours shown (DayLine.range): around now and everything still to come today, done things aside.
    private var range: ClosedRange<Date> {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let all = items(in: dayStart...dayEnd).filter { if case .done = $0 { false } else { true } }
        return DayLine.range(now: now, starts: all.map(\.start), ends: all.map(\.end), calendar: cal)
    }

    /// The points a chip needs for its words, up to a share of the rail, so a narrow rail still shows a few side by side.
    private func readable(_ item: Item) -> Double {
        let most = min(170, max(90, Double(width) * 0.4))
        return min(most, Double(item.title.count) * 6.6 + 34)
    }

    /// To the nearest quarter hour.
    private func snap(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / Self.step).rounded() * Self.step)
    }

    // MARK: What's on it

    enum Item {
        case reminder(Reminder, due: Date)
        case done(Reminder, at: Date)
        case event(CalendarEvent)

        var id: String {
            switch self {
            case .reminder(let r, _): "r" + r.id
            case .done(let r, _): "d" + r.id
            case .event(let e): "e" + e.id
            }
        }
        var start: Date {
            switch self {
            case .reminder(_, let due): due
            case .done(_, let at): at
            case .event(let e): e.start
            }
        }
        var end: Date {
            switch self {
            case .reminder(_, let due): due
            case .done(_, let at): at
            case .event(let e): e.end
            }
        }
        var title: String {
            switch self {
            case .reminder(let r, _), .done(let r, _): r.title
            case .event(let e): e.title
            }
        }
    }

    private func items(in span: ClosedRange<Date>) -> [Item] {
        let timed = events.filter { !$0.allDay && $0.end > span.lowerBound && $0.start < span.upperBound }.map(Item.event)
        let due = reminders.compactMap { r -> Item? in
            let at = r.nextDue ?? r.fireAt
            return span.contains(at) ? .reminder(r, due: at) : nil
        }
        let finished = done.compactMap { r -> Item? in
            let at = r.lastFiredAt ?? r.fireAt
            return span.contains(at) ? .done(r, at: at) : nil
        }
        return (timed + due + finished).sorted { $0.start < $1.start }
    }

    // MARK: Drawing

    /// A line at every hour, and labels where they fit (DayLine.ticks): never two touching, whatever the width.
    private func hours(_ span: ClosedRange<Date>, width: CGFloat, height: CGFloat) -> some View {
        let ticks = DayLine.ticks(in: span, width: Double(width), labelWidth: Double(labelWidth), calendar: .current)
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.date) { tick in
                Rectangle().fill(Theme.line).frame(width: 1, height: height).offset(x: CGFloat(tick.x))
                if let labelX = tick.labelX {
                    Text(verbatim: TimeFormat.clock(tick.date, calendar: .current)).font(Theme.Font.caption).monospacedDigit()
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize()
                        .offset(x: CGFloat(labelX), y: height + 3)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func nowLine(_ span: ClosedRange<Date>, width: CGFloat, height: CGFloat) -> some View {
        Rectangle().fill(Theme.danger).frame(width: 2, height: height + 6)
            .offset(x: CGFloat(DayLine.x(now, in: span, width: Double(width))) - 1, y: -3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A chip at its place. Its edge at its time is marked (the leading one, or the trailing one when it had to end
    /// there), and an event's length is drawn under it, so where it starts and ends reads exactly.
    @ViewBuilder private func view(_ item: Item, _ place: DayLine.Placement, span: ClosedRange<Date>) -> some View {
        let chipWidth = max(CGFloat(place.width) - 3, 20)
        switch item {
        case .event(let event):
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: event.title).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current)) · \(String(localized: "Calendar"))")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
                .padding(.horizontal, 7)
                .frame(width: chipWidth, height: Self.lane - 6, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(Theme.accent).frame(width: min(max(CGFloat(place.length), 2), chipWidth), height: 3)
                }
                .overlay(alignment: place.endsAtTime ? .trailing : .leading) { TimeEdge(color: Theme.accent) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.5)))
                .help(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current))–\(TimeFormat.clock(event.end, calendar: .current)) \(event.title)"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current)) \(event.title)"))
        case .reminder(let reminder, let due):
            ReminderChip(reminder: reminder, due: due, late: due < now, width: chipWidth, endsAtTime: place.endsAtTime,
                         pointsPerSecond: width / span.upperBound.timeIntervalSince(span.lowerBound)) { minutes in
                shift(reminder, from: due, by: minutes)
            } drop: { seconds in
                shift(reminder, from: due, to: snap(due.addingTimeInterval(seconds)))
            }
            .contextMenu { menu(reminder) }
        case .done(let reminder, let at):
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: reminder.title).font(Theme.Font.captionStrong).strikethrough()
                Text(verbatim: TimeFormat.clock(at, calendar: .current)).font(Theme.Font.caption).strikethrough()
            }
            .foregroundStyle(Theme.success).lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: chipWidth, height: Self.lane - 6, alignment: .leading)
            .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: place.endsAtTime ? .trailing : .leading) { TimeEdge(color: Theme.success) }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Done: \(reminder.title)"))
        }
    }

    private func shift(_ reminder: Reminder, from due: Date, by minutes: Double) {
        shift(reminder, from: due, to: due.addingTimeInterval(minutes * 60))
    }

    /// Moves it, never into the past, and lets ⌘Z put it back while that time is still to come.
    private func shift(_ reminder: Reminder, from due: Date, to target: Date) {
        let target = max(target, snap(Date().addingTimeInterval(Self.step / 2)))
        guard abs(target.timeIntervalSince(due)) >= 60 else { return }
        let move = self.move
        Task { @MainActor in
            problem = await move(reminder, target)
            guard problem == nil, let undoManager else { return }
            undoManager.registerUndo(withTarget: UndoBox.shared) { _ in
                guard due > Date() else { return }
                Task { @MainActor in _ = await move(reminder, due) }
            }
            undoManager.setActionName(String(localized: "Move Reminder"))
        }
    }
}

/// The edge of a chip that sits at its time: a bar of the chip's colour, so the chip reads as starting (or, near the
/// end of the line, ending) there.
private struct TimeEdge: View {
    var color: Color

    var body: some View {
        Rectangle().fill(color).frame(width: 3).accessibilityHidden(true)
    }
}

/// What undo registrations hang on: SwiftUI views aren't objects.
private final class UndoBox: NSObject {
    @MainActor static let shared = UndoBox()
}

/// A reminder on the rail: drag it along, or ← → on it a quarter hour at a time; VoiceOver adjusts it the same way.
private struct ReminderChip: View {
    var reminder: Reminder
    var due: Date
    var late: Bool
    var width: CGFloat
    var endsAtTime = false
    var pointsPerSecond: CGFloat
    var nudge: (Double) -> Void
    var drop: (TimeInterval) -> Void
    @GestureState private var drag: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "alarm").imageScale(.small)
                Text(verbatim: reminder.title).lineLimit(1)
            }
            .font(Theme.Font.captionStrong)
            Text(verbatim: late ? String(localized: "\(TimeFormat.clock(due, calendar: .current)) · late", comment: "A reminder on the day's line whose time passed")
                            : TimeFormat.clock(due, calendar: .current))
                .font(Theme.Font.caption).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(late ? Theme.danger : Theme.ink)
        .padding(.horizontal, 8)
        .frame(width: width, height: 38, alignment: .leading)
        .background(late ? Theme.dangerSoft : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: endsAtTime ? .trailing : .leading) { TimeEdge(color: late ? Theme.danger : Theme.accent) }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.accent.opacity(0.45), lineWidth: focused ? 2 : 1))
        .shadow(color: .black.opacity(drag == 0 ? 0 : 0.15), radius: 6, y: 2)
        .offset(x: drag)
        .gesture(DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in state = value.translation.width }
            .onEnded { value in drop(Double(value.translation.width / max(pointsPerSecond, 0.0001))) })
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
