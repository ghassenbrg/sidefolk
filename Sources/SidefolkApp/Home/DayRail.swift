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

    private static let step: TimeInterval = 15 * 60
    private static let lane: CGFloat = 44

    var body: some View {
        let span = range
        let placed = layout(span)
        let lanes = max(1, (placed.map(\.lane).max() ?? 0) + 1)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack(alignment: .topLeading) {
                hours(span, width: width, height: CGFloat(lanes) * Self.lane)
                // Under the items, so it never crosses their words.
                nowLine(span, width: width, height: CGFloat(lanes) * Self.lane)
                // Double-click an empty time: a reminder there.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in add(snap(time(at: location.x, width: width, span: span))) }
                ForEach(placed, id: \.item.id) { placed in
                    view(placed.item, width: placed.width, span: span)
                        .offset(x: placed.x, y: CGFloat(placed.lane) * Self.lane)
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(lanes) * Self.lane + 20, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
            if let problem {
                InlineError(error: problem)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
    }

    // MARK: Time and place

    /// The hours shown: from an hour before now (or the first thing, if earlier) to a few hours ahead (or the last
    /// thing), whole hours, at least six, within today.
    private var range: ClosedRange<Date> {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let all = items(in: dayStart...dayEnd).filter { if case .done = $0 { false } else { true } }
        var lower = min(now.addingTimeInterval(-3600), all.map(\.start).min() ?? now)
        var upper = max(now.addingTimeInterval(3 * 3600), all.map(\.end).max() ?? now)
        lower = max(dayStart, hourFloor(lower))
        upper = min(dayEnd, hourFloor(upper.addingTimeInterval(3599)))
        if upper.timeIntervalSince(lower) < 6 * 3600 {
            upper = min(dayEnd, lower.addingTimeInterval(6 * 3600))
            lower = max(dayStart, upper.addingTimeInterval(-6 * 3600))
        }
        return lower...upper
    }

    private func hourFloor(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    private func x(_ date: Date, _ span: ClosedRange<Date>, _ width: CGFloat) -> CGFloat {
        let total = span.upperBound.timeIntervalSince(span.lowerBound)
        return CGFloat(date.timeIntervalSince(span.lowerBound) / max(total, 1)) * width
    }

    private func time(at x: CGFloat, width: CGFloat, span: ClosedRange<Date>) -> Date {
        span.lowerBound.addingTimeInterval(Double(x / max(width, 1)) * span.upperBound.timeIntervalSince(span.lowerBound))
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

    /// Where each item sits, in points: at its time, wide enough to read (an event at least its length), kept inside
    /// the rail, on the first lane where it covers nothing.
    private func layout(_ span: ClosedRange<Date>) -> [(item: Item, x: CGFloat, width: CGFloat, lane: Int)] {
        var rights: [CGFloat] = []
        return items(in: span).map { item in
            let readable = min(170, CGFloat(item.title.count) * 6.6 + 34)
            let long = x(item.end, span, width) - x(item.start, span, width)
            let w = min(width, max(readable, long, 64))
            let at = min(max(0, x(item.start, span, width)), width - w)
            let lane: Int
            if let free = rights.firstIndex(where: { $0 + 4 <= at }) {
                lane = free
                rights[free] = at + w
            } else {
                lane = rights.count
                rights.append(at + w)
            }
            return (item, at, w, lane)
        }
    }

    // MARK: Drawing

    private func hours(_ span: ClosedRange<Date>, width: CGFloat, height: CGFloat) -> some View {
        let total = span.upperBound.timeIntervalSince(span.lowerBound)
        let every: TimeInterval = total > 12 * 3600 ? 2 * 3600 : 3600
        let marks = stride(from: 0, through: total, by: every).map { span.lowerBound.addingTimeInterval($0) }
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { mark in
                let at = x(mark, span, width)
                Rectangle().fill(Theme.line).frame(width: 1, height: height).offset(x: at)
                Text(verbatim: TimeFormat.clock(mark, calendar: .current)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    .fixedSize()
                    .offset(x: max(0, min(at - 14, width - 34)), y: height + 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func nowLine(_ span: ClosedRange<Date>, width: CGFloat, height: CGFloat) -> some View {
        Rectangle().fill(Theme.danger).frame(width: 2, height: height + 6)
            .offset(x: x(now, span, width) - 1, y: -3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func view(_ item: Item, width itemWidth: CGFloat, span: ClosedRange<Date>) -> some View {
        switch item {
        case .event(let event):
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: event.title).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current)) · \(String(localized: "Calendar"))")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
                .padding(.horizontal, 7)
                .frame(width: itemWidth - 3, height: Self.lane - 6, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.5)))
                .help(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current))–\(TimeFormat.clock(event.end, calendar: .current)) \(event.title)"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(TimeFormat.clock(event.start, calendar: .current)) \(event.title)"))
        case .reminder(let reminder, let due):
            ReminderChip(reminder: reminder, due: due, late: due < now, width: itemWidth - 3,
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
            .frame(width: itemWidth - 3, height: Self.lane - 6, alignment: .leading)
            .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
