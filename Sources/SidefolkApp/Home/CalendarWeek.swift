import SidefolkCore
import SwiftUI

/// The Calendar's week (D66): a column a day under the hours, each thing at its time and as long as it lasts (a
/// reminder, a moment, gets a short block), things that overlap side by side (CalendarGrid.columns) and, past what a
/// column has room for, counted in a "+N" that opens the day (D84), all-day events in a row above, and a line at the
/// present today. It opens at the morning, or an hour before now. A week with the Mac calendar's events says, under
/// it, that they are read only here.
struct CalendarWeek: View {
    var model: CalendarModel
    var open: (CalendarModel.Entry) -> Void
    var edit: (Reminder) -> Void
    var add: (Date) -> Void
    @Environment(\.undoManager) private var undo

    private static let hour: CGFloat = 44
    private static let gutter: CGFloat = 44
    /// A reminder's block: a moment, drawn half an hour long so its words fit.
    private static let moment: TimeInterval = 30 * 60
    /// The narrowest a block may be (its picture alone, or "+3"): past that, an overlap's rest is counted.
    private static let narrowest: CGFloat = 34

    var body: some View {
        let days = model.days
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter, height: 1)
                ForEach(days, id: \.self) { dayHeader($0) }
            }
            HStack(alignment: .top, spacing: 0) {
                Text("All day").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: Self.gutter, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.entries(on: day).filter(\.allDay)) { CalendarChip(entry: $0, model: model, showsTime: false, open: open, edit: edit) }
                    }
                    .padding(2)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                }
            }
            .padding(.vertical, 2)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hours
                        ForEach(days, id: \.self) { column($0) }
                    }
                    .frame(height: Self.hour * 24)
                }
                .task {
                    // After the first layout: scrolling on appear alone left the week at midnight.
                    try? await Task.sleep(for: .milliseconds(50))
                    let hour = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo(max(0, min(hour - 1, 7)), anchor: .top)
                }
            }
            if days.contains(where: { day in model.entries(on: day).contains { if case .event = $0 { true } else { false } } }) {
                readOnlyNote
            }
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }

    /// The Mac calendar's events can't be moved or changed here (D57): said once, under the week, not on each block.
    private var readOnlyNote: some View {
        VStack(spacing: 0) {
            Divider()
            Label {
                Text("Events from your Mac's calendar are read only here. Change them in Calendar.",
                     comment: "Under the Calendar's week, when it shows the Mac calendar's events")
            } icon: {
                Image(systemName: "lock")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let today = model.calendar.isDateInToday(day)
        return HStack(spacing: 4) {
            Text(verbatim: day.formatted(.dateTime.weekday(.abbreviated))).foregroundStyle(Theme.inkMuted)
            Text(verbatim: day.formatted(.dateTime.day())).monospacedDigit()
                .foregroundStyle(today ? Theme.onAccent : Theme.ink)
                .frame(minWidth: 22, minHeight: 22)
                .background(today ? Theme.accent : .clear, in: Circle())
        }
        .font(Theme.Font.captionStrong)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { model.show(day: day) }
        .help(Text("Show this day"))
    }

    /// The hours down the side, each a scroll target.
    private var hours: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(verbatim: h == 0 ? "" : String(format: "%02d:00", h))
                    .font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.inkFaint)
                    .frame(width: Self.gutter, height: Self.hour, alignment: .topLeading)
                    .offset(y: -7)
                    .id(h)
            }
        }
    }

    private func column(_ day: Date) -> some View {
        let start = model.calendar.startOfDay(for: day)
        let timed = model.entries(on: day).filter { !$0.allDay }
        let spans = timed.map { (start: $0.start, end: max($0.end, $0.start.addingTimeInterval(Self.moment))) }
        return GeometryReader { geo in
            let fitted = CalendarGrid.fit(spans, maxColumns: Int(geo.size.width / Self.narrowest))
            ZStack(alignment: .topLeading) {
                // The hour lines, and a double-click on an empty time adds a reminder there (to the quarter hour).
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 1).frame(maxHeight: Self.hour, alignment: .top)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in add(time(at: location.y, from: start)) }
                .dropDestination(for: String.self) { ids, location in
                    guard let id = ids.first else { return false }
                    Task { await model.drop(id, on: day, at: time(at: location.y, from: start), undo: undo) }
                    return true
                }
                ForEach(Array(timed.enumerated()), id: \.element.id) { i, entry in
                    if let place = fitted.placed[i] {
                        let width = geo.size.width / CGFloat(place.of)
                        block(entry, height: CGFloat(spans[i].end.timeIntervalSince(spans[i].start) / 3600) * Self.hour, wide: width >= 120, words: width >= 64)
                            .frame(width: max(width - 3, 10))
                            .offset(x: CGFloat(place.column) * width + 1, y: y(entry.start, from: start))
                    }
                }
                ForEach(Array(fitted.more.enumerated()), id: \.offset) { _, more in
                    let width = geo.size.width / CGFloat(more.of)
                    moreChip(more.count, on: day)
                        .frame(width: max(width - 3, 10))
                        .offset(x: CGFloat(more.column) * width + 1, y: y(more.start, from: start))
                }
                if model.calendar.isDateInToday(day) {
                    // The present is a time marker, not an alarm.
                    Rectangle().fill(Theme.accent).frame(height: 2)
                        .offset(y: y(Date(), from: start) - 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }

    /// "+2": what didn't fit across the column at that time; a click opens the day, where everything is listed.
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

    /// A thing as a block: its words at the top, its colour down the edge at its start.
    private func block(_ entry: CalendarModel.Entry, height: CGFloat, wide: Bool, words: Bool) -> some View {
        CalendarChip(entry: entry, model: model, showsTime: wide, showsTitle: words, open: open, edit: edit)
            .frame(maxHeight: max(height - 2, 18), alignment: .top)
            .background(entry.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(entry.tint).frame(width: 2) }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// Where a time is down a day's column, by the clock (so a day that changes to summer time still reads 9:00 at 9).
    private func y(_ date: Date, from start: Date) -> CGFloat {
        guard date >= start else { return 0 }
        let clock = model.calendar.dateComponents([.day, .hour, .minute], from: start, to: date)
        if (clock.day ?? 0) > 0 { return Self.hour * 24 }
        let c = model.calendar.dateComponents([.hour, .minute], from: date)
        return CGFloat(Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) * Self.hour
    }

    /// The time at a point of a day's column, to the nearest quarter hour, by the clock.
    private func time(at y: CGFloat, from start: Date) -> Date {
        let quarters = min(max(Int((Double(y / Self.hour) * 4).rounded()), 0), 95)
        return model.calendar.date(bySettingHour: quarters / 4, minute: quarters % 4 * 15, second: 0, of: start) ?? start
    }
}
