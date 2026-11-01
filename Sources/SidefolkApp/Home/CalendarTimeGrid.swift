import SidefolkCore
import SwiftUI

/// The Calendar's Day and Week (D66, D95): a column a day under the hours, each thing at its time and as long as it
/// lasts, saying as much as its size has room for (`CalendarBlock`); overlaps side by side and, past what a column has
/// room for, counted in a "+N" that opens the day (D84); all-day and multi-day events as bars in a band above; a line
/// at the present. It opens at the working hours (or an hour before now), pinching changes the hour's height, a drag
/// over empty time or a double-click places something new, a thing is dragged to move it and an event's bottom edge to
/// change its length, all to the quarter hour.
struct CalendarTimeGrid: View {
    var model: CalendarModel
    var days: [Date]
    @Environment(\.undoManager) private var undo
    @State private var drag: GridDrag?
    @State private var pinchFrom: CGFloat?
    /// Each day column's frame in the grid, so a drag knows which day it is over (in either direction of text).
    @State private var columns: [Date: CGRect] = [:]

    private var hour: CGFloat { model.hourHeight }
    private static let gutter: CGFloat = 52
    /// The narrowest a block may be (its colour alone, or "+3"): past that, an overlap's rest is counted.
    private static let narrowest: CGFloat = 34
    /// A reminder is a moment: one line tall, whatever the hour's height.
    private static let momentHeight: CGFloat = 22
    private static let quarter: TimeInterval = 15 * 60

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter, height: 1)
                ForEach(days, id: \.self) { dayHeader($0) }
            }
            allDayBand
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hours
                        ForEach(days, id: \.self) { column($0) }
                    }
                    .frame(height: hour * 24)
                    .coordinateSpace(.named(Self.space))
                    .onPreferenceChange(ColumnFrames.self) { columns = $0 }
                }
                .task(id: days.first) {
                    // After the first layout: scrolling on appear alone left the grid at midnight.
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(openingHour, anchor: .top)
                }
            }
            .simultaneousGesture(pinch)
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }

    private static let space = "calendar-grid"

    /// An hour before now when today is in view, else the morning: where the working day starts.
    private var openingHour: Int {
        let cal = model.calendar
        if days.contains(where: cal.isDateInToday) { return max(0, min(cal.component(.hour, from: Date()) - 1, 20)) }
        return max(0, model.runtime.settings.current.morningHour - 1)
    }

    /// Two fingers apart or together: taller or shorter hours, kept when they lift.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let from = pinchFrom ?? hour
                pinchFrom = from
                model.setHourHeight(from * value.magnification)
            }
            .onEnded { _ in
                pinchFrom = nil
                model.keepHourHeight()
            }
    }

    // MARK: Headers and the all-day band

    private func dayHeader(_ day: Date) -> some View {
        let today = model.calendar.isDateInToday(day)
        return HStack(spacing: 4) {
            Text(verbatim: day.formatted(.dateTime.weekday(days.count == 1 ? .wide : .abbreviated))).foregroundStyle(Theme.inkMuted)
            Text(verbatim: day.formatted(.dateTime.day())).monospacedDigit()
                .foregroundStyle(today ? Theme.onAccent : Theme.ink)
                .frame(minWidth: 22, minHeight: 22)
                .background(today ? Theme.accent : .clear, in: Circle())
        }
        .font(Theme.Font.captionStrong)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: days.count == 1 ? .leading : .center)
        .padding(.horizontal, days.count == 1 ? Theme.Space.s : 0)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if days.count > 1 { model.show(day: day) } }
        .help(days.count > 1 ? Text("Show this day") : Text(verbatim: ""))
    }

    /// All-day and multi-day events as bars across the days they cover, stacked as Calendar stacks them; three rows,
    /// then "+N" on the days with more.
    private var allDayBand: some View {
        let cal = model.calendar
        let firstDay = days.first ?? Date()
        let all = Array(Set(days.flatMap { model.entries(on: $0).filter(\.allDay) })).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let spans = all.map { entry -> (first: Int, last: Int) in
            let first = max(0, cal.dateComponents([.day], from: firstDay, to: cal.startOfDay(for: entry.start)).day ?? 0)
            let lastDay = cal.startOfDay(for: entry.end.addingTimeInterval(-1))
            let last = min(days.count - 1, cal.dateComponents([.day], from: firstDay, to: lastDay).day ?? first)
            return (first, max(first, last))
        }
        let lanes = CalendarGrid.lanes(spans)
        let rows = min(3, (lanes.max() ?? -1) + 1)
        let row: CGFloat = 22
        return HStack(alignment: .top, spacing: 0) {
            Text("All day").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: Self.gutter - 6, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 4)
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(max(days.count, 1))
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            Rectangle().fill(.clear).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.startNew(at: day, end: cal.date(byAdding: .day, value: 1, to: day), allDay: true) }
                        }
                    }
                    ForEach(Array(all.enumerated()), id: \.element.id) { i, entry in
                        if lanes[i] < rows {
                            CalendarBar(entry: entry, model: model)
                                .frame(width: max(CGFloat(spans[i].last - spans[i].first + 1) * width - 4, 10), height: row - 3)
                                .padding(.leading, CGFloat(spans[i].first) * width + 2)
                                .padding(.top, CGFloat(lanes[i]) * row + 2)
                        }
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let more = all.indices.filter { lanes[$0] >= rows && spans[$0].first <= index && spans[$0].last >= index }.count
                        if more > 0 {
                            Button { model.show(day: day) } label: {
                                Text(verbatim: "+\(more.formatted())").font(Theme.Font.captionStrong).foregroundStyle(Theme.link)
                            }
                            .buttonStyle(.plain)
                            .frame(width: width - 4, alignment: .trailing)
                            .padding(.leading, CGFloat(index) * width)
                            .padding(.top, CGFloat(rows) * row)
                        }
                    }
                }
            }
        }
        .frame(height: max(24, CGFloat(rows) * row + (all.count > 0 && lanes.contains { $0 >= rows } ? 18 : 4)))
    }

    // MARK: Hours and columns

    /// The hours down the side in the person's clock (13:00 or 1 PM), each a scroll target, and now in the accent.
    private var hours: some View {
        let cal = model.calendar
        return VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(verbatim: h == 0 ? "" : (cal.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date())
                    .formatted(.dateTime.hour()))
                    .font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.inkFaint)
                    .frame(width: Self.gutter - 8, height: hour, alignment: .topTrailing)
                    .padding(.trailing, 8)
                    .offset(y: -7)
                    .id(h)
            }
        }
        .overlay(alignment: .topTrailing) {
            if days.contains(where: cal.isDateInToday) {
                TimelineView(.everyMinute) { context in
                    Text(verbatim: TimeFormat.clock(context.date, calendar: cal))
                        .font(Theme.Font.caption.monospacedDigit()).fontWeight(.semibold)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                        .padding(.trailing, 3)
                        .padding(.top, max(0, y(context.date, from: cal.startOfDay(for: context.date)) - 8))
                        .accessibilityLabel(Text("Now"))
                }
            }
        }
    }

    private func column(_ day: Date) -> some View {
        let start = model.calendar.startOfDay(for: day)
        let timed = model.entries(on: day).filter { !$0.allDay }
        let spans = timed.map { entry in
            (start: entry.start, end: max(entry.end, entry.start.addingTimeInterval(Double(Self.momentHeight / hour) * 3600)))
        }
        return GeometryReader { geo in
            let fitted = CalendarGrid.fit(spans, maxColumns: Int(geo.size.width / Self.narrowest))
            ZStack(alignment: .topLeading) {
                background(day: start)
                ForEach(Array(timed.enumerated()), id: \.element.id) { i, entry in
                    if let place = fitted.placed[i] {
                        let width = geo.size.width / CGFloat(place.of)
                        let moving = drag?.entry?.id == entry.id
                        block(entry, width: max(width - 3, 10), height: max(height(spans[i]) - 1, entry.reminder == nil ? 18 : Self.momentHeight - 1))
                            .opacity(moving ? 0.35 : 1)
                            .padding(.leading, CGFloat(place.column) * width + 1)
                            .padding(.top, y(entry.start, from: start))
                    }
                }
                ForEach(Array(fitted.more.enumerated()), id: \.offset) { _, more in
                    let width = geo.size.width / CGFloat(more.of)
                    moreChip(more.count, on: day)
                        .frame(width: max(width - 3, 10))
                        .padding(.leading, CGFloat(more.column) * width + 1)
                        .padding(.top, y(more.start, from: start))
                }
                preview(on: start, width: geo.size.width)
                newDraft(on: start, width: geo.size.width)
                if model.calendar.isDateInToday(day) { nowLine(from: start) }
            }
            .preference(key: ColumnFrames.self, value: [start: geo.frame(in: .named(Self.space))])
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }

    /// The hour lines, the working hours a shade lighter than the night, and the empty time's gestures: a
    /// double-click places a new thing at that quarter hour, a drag places one over the time it covers.
    private func background(day: Date) -> some View {
        let settings = model.runtime.settings.current
        let work = settings.morningHour..<max(settings.eveningHour, settings.morningHour + 1)
        return VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Rectangle().fill(work.contains(h) ? Color.clear : Theme.surfaceSunken.opacity(0.55))
                    .frame(height: hour)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 1) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            let at = time(at: location.y, from: day)
            model.startNew(at: at, end: at.addingTimeInterval(3600))
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let a = time(at: value.startLocation.y, from: day), b = time(at: value.location.y, from: day)
                    drag = GridDrag(kind: .create, day: day, start: min(a, b), end: max(max(a, b), min(a, b).addingTimeInterval(Self.quarter)))
                }
                .onEnded { _ in
                    if let drag { model.startNew(at: drag.start, end: drag.end) }
                    drag = nil
                }
        )
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first else { return false }
            Task { await model.drop(id, on: day, at: time(at: location.y, from: day), undo: undo) }
            return true
        }
    }

    /// A thing as a block, with its gestures: a click selects, a double-click (or Return) opens its details, a drag
    /// moves it, an event's bottom edge changes its length.
    private func block(_ entry: CalendarEntry, width: CGFloat, height: CGFloat) -> some View {
        let selected = model.selection == entry.id
        return CalendarBlock(entry: entry, model: model, width: width, height: height, selected: selected)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.inspecting = entry.id }
            .simultaneousGesture(TapGesture().onEnded { model.selection = entry.id })
            .gesture(entry.movable ? moveGesture(entry) : nil)
            .overlay(alignment: .bottom) {
                if case .event(let e) = entry, e.changeable, height >= 30 { resizeHandle(e) }
            }
            .contextMenu { CalendarMenu(entry: entry, model: model) }
            .calendarInspector(entry, model: model)
    }

    private func moveGesture(_ entry: CalendarEntry) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                model.selection = entry.id
                let day = dayAt(value.location) ?? model.calendar.startOfDay(for: entry.start)
                let shift = snap(Double(value.translation.height / hour) * 3600)
                let clock = entry.start.timeIntervalSince(model.calendar.startOfDay(for: entry.start)) + shift
                let start = day.addingTimeInterval(min(max(clock, 0), 24 * 3600 - Self.quarter))
                drag = GridDrag(kind: .move, entry: entry, day: day, start: start, end: start.addingTimeInterval(entry.end.timeIntervalSince(entry.start)))
            }
            .onEnded { _ in
                if let drag, let entry = drag.entry { Task { await model.move(entry, to: drag.start, undo: undo) } }
                drag = nil
            }
    }

    private func resizeHandle(_ event: CalendarEvent) -> some View {
        Rectangle().fill(.clear).frame(height: 6).contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        let end = event.end.addingTimeInterval(snap(Double(value.translation.height / hour) * 3600))
                        drag = GridDrag(kind: .resize, entry: .event(event), day: model.calendar.startOfDay(for: event.start), start: event.start,
                                        end: max(end, event.start.addingTimeInterval(Self.quarter)))
                    }
                    .onEnded { _ in
                        if let drag { model.resize(event, end: drag.end, undo: undo) }
                        drag = nil
                    }
            )
            .accessibilityHidden(true)
    }

    /// Where a drag will put a thing (or the time it covers), with the time it would start.
    @ViewBuilder private func preview(on day: Date, width: CGFloat) -> some View {
        if let drag, model.calendar.isDate(drag.day, inSameDayAs: day) {
            let span = max(drag.end.timeIntervalSince(drag.start), Double(Self.momentHeight / hour) * 3600)
            let tint = drag.entry.map(model.tint) ?? CalendarTint.of(CalendarEntry.Kind.reminder.hex)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.fill.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(tint.edge, style: StrokeStyle(lineWidth: 1.5, dash: drag.kind == .create ? [4, 3] : [])))
                .overlay(alignment: .topLeading) {
                    Text(verbatim: CalendarEntry.span(drag.start, drag.end, calendar: model.calendar))
                        .font(Theme.Font.captionStrong.monospacedDigit()).foregroundStyle(tint.text).padding(4)
                }
                .frame(width: max(width - 3, 10), height: max(CGFloat(span / 3600) * hour, 20))
                .padding(.leading, 1)
                .padding(.top, y(drag.start, from: day))
                .allowsHitTesting(false)
        }
    }

    /// The new thing being placed, which its editor points from.
    @ViewBuilder private func newDraft(on day: Date, width: CGFloat) -> some View {
        if let draft = model.draft, !draft.allDay, !draft.fromButton, model.calendar.isDate(draft.start, inSameDayAs: day), drag == nil {
            let tint = CalendarTint.of(CalendarEntry.Kind.reminder.hex)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.fill)
                .overlay(alignment: .leading) { Rectangle().fill(tint.edge).frame(width: 3) }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("New", comment: "The Calendar: a thing being placed, before it has a title")
                        .font(Theme.Font.captionStrong).foregroundStyle(tint.text).padding(.leading, 7).padding(.top, 3)
                }
                .frame(width: max(width - 3, 10), height: max(CGFloat(draft.end.timeIntervalSince(draft.start) / 3600) * hour, 20))
                .popover(item: Binding(get: { model.draft?.fromButton == false ? model.draft : nil }, set: { model.draft = $0 }), arrowEdge: .trailing) { CalendarEditor(model: model, draft: $0) }
                .padding(.leading, 1)
                .padding(.top, y(draft.start, from: day))
        }
    }

    /// The present: a line across today with a dot at its start. A time marker, not an alarm.
    private func nowLine(from start: Date) -> some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.leading, -4)
                Rectangle().fill(Theme.accent).frame(height: 2)
            }
            .padding(.top, y(context.date, from: start) - 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "+2": what didn't fit across the column at that time; a click opens the day, where there is room.
    private func moreChip(_ count: Int, on day: Date) -> some View {
        Button { model.show(day: day) } label: {
            Text(verbatim: "+\(count.formatted())")
                .font(Theme.Font.captionStrong).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 18)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("\(count) more at this time", comment: "The Calendar's week: things that didn't fit side by side; a click shows the day"))
        .accessibilityLabel(Text("\(count) more at this time", comment: "The Calendar's week: things that didn't fit side by side; a click shows the day"))
        .accessibilityHint(Text("Show this day"))
    }

    // MARK: Time and place

    private func height(_ span: (start: Date, end: Date)) -> CGFloat { CGFloat(span.end.timeIntervalSince(span.start) / 3600) * hour }

    /// Where a time is down a day's column, by the clock (so a day that changes to summer time still reads 9:00 at 9).
    private func y(_ date: Date, from start: Date) -> CGFloat {
        guard date >= start else { return 0 }
        if (model.calendar.dateComponents([.day], from: start, to: date).day ?? 0) > 0 { return hour * 24 }
        let c = model.calendar.dateComponents([.hour, .minute], from: date)
        return CGFloat(Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) * hour
    }

    /// The time at a point of a day's column, to the quarter hour, by the clock.
    private func time(at y: CGFloat, from start: Date) -> Date {
        let quarters = min(max(Int((Double(y / hour) * 4).rounded(.down)), 0), 95)
        return model.calendar.date(bySettingHour: quarters / 4, minute: quarters % 4 * 15, second: 0, of: start) ?? start
    }

    private func snap(_ seconds: TimeInterval) -> TimeInterval { (seconds / Self.quarter).rounded() * Self.quarter }

    private func dayAt(_ point: CGPoint) -> Date? { columns.first { $0.value.minX <= point.x && point.x < $0.value.maxX }?.key }
}

/// A drag on the grid: moving a thing, changing an event's length, or placing a new one.
private struct GridDrag {
    enum Kind { case move, resize, create }
    var kind: Kind
    var entry: CalendarEntry?
    var day: Date
    var start: Date
    var end: Date

    init(kind: Kind, entry: CalendarEntry? = nil, day: Date, start: Date, end: Date) {
        self.kind = kind
        self.entry = entry
        self.day = day
        self.start = start
        self.end = end
    }
}

private struct ColumnFrames: PreferenceKey {
    static let defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) { value.merge(nextValue()) { $1 } }
}
