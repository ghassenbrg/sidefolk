import SidefolkCore
import SwiftUI

/// The Calendar's month (D66, D95): whole weeks from the person's first weekday that scroll on, a row at a time, with
/// two fingers (the title follows the month most on screen) and step a month with ⌘← ⌘→. Each day shows as many lines
/// as fit and "+ N more" to its Day; a narrow day shows its things as dots. Days outside the month in view are dimmer;
/// today's number is circled; the 1st says its month.
struct CalendarMonth: View {
    var model: CalendarModel
    @Environment(\.undoManager) private var undo

    private static let header: CGFloat = 24
    private static let least: CGFloat = 72
    private static let line: CGFloat = 19

    var body: some View {
        let rows = CalendarModel.monthRows
        GeometryReader { geo in
            let row = max(Self.least, (geo.size.height - Self.header) / CGFloat(rows))
            // A row above and one below the six on screen, so a scroll shows what comes in.
            let days = CalendarGrid.weeks(from: model.calendar.date(byAdding: .weekOfYear, value: -1, to: model.days.first ?? Date()) ?? Date(),
                                          count: rows + 2, calendar: model.calendar)
            let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
            let wide = geo.size.width / 7
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(days.prefix(7), id: \.self) { day in
                        Text(verbatim: day.formatted(.dateTime.weekday(wide >= 110 ? .wide : .abbreviated)))
                            .font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(height: Self.header)
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.first) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { cell($0, height: row, width: wide) }
                        }
                    }
                }
                .offset(y: -row - model.monthScroll)
                .frame(height: row * CGFloat(rows), alignment: .top)
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
            .onAppear { CalendarScrollCatcher.monthRow = row }
            .onChange(of: row) { CalendarScrollCatcher.monthRow = row }
        }
    }

    private func cell(_ day: Date, height: CGFloat, width: CGFloat) -> some View {
        let cal = model.calendar
        let inMonth = cal.isDate(day, equalTo: model.shownMonth, toGranularity: .month)
        let today = cal.isDateInToday(day)
        let entries = model.entries(on: day)
        let first = cal.component(.day, from: day) == 1
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if first, width >= 90 {
                    Text(verbatim: day.formatted(.dateTime.month(.abbreviated))).font(Theme.Font.captionStrong)
                        .foregroundStyle(inMonth ? Theme.ink : Theme.inkFaint)
                }
                Text(verbatim: day.formatted(.dateTime.day()))
                    .font(Theme.Font.captionStrong).monospacedDigit()
                    .foregroundStyle(today ? Theme.onAccent : inMonth ? Theme.ink : Theme.inkFaint)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(today ? Theme.accent : .clear, in: Circle())
            }
            if width < 76 {
                dots(entries)
            } else {
                // Room for the number and as many lines as fit; one goes to "+ N more" when they don't.
                let room = max(1, Int((height - 28) / Self.line))
                let shown = entries.count > room ? room - 1 : entries.count
                ForEach(entries.prefix(shown)) { entry in
                    CalendarChip(entry: entry, model: model, showsTime: width >= 130)
                }
                if entries.count > shown {
                    Button("+ \(entries.count - shown) more") { model.show(day: day) }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
                        .padding(.horizontal, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(inMonth ? Theme.surfaceRaised : Theme.surfaceSunken)
        .overlay(alignment: .topLeading) {
            // Hairlines between days: each draws its top and leading edge.
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.line).frame(height: 1)
                Rectangle().fill(Theme.line).frame(width: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.startNew(at: model.newTime(on: day)) }
        .popover(item: draftBinding(day), arrowEdge: .trailing) { CalendarEditor(model: model, draft: $0) }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            Task { await model.drop(id, on: day, undo: undo) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }

    /// A narrow day's things as their colours' dots, four at most.
    private func dots(_ entries: [CalendarEntry]) -> some View {
        HStack(spacing: 3) {
            ForEach(entries.prefix(4)) { entry in Circle().fill(model.tint(entry).edge).frame(width: 6, height: 6) }
            if entries.count > 4 { Text(verbatim: "+").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
        }
        .padding(.horizontal, 4)
        .accessibilityLabel(Text("\(entries.count) things", comment: "The Calendar's narrow month: how many things a day has"))
    }

    /// The editor of a new thing, from the day it is placed on.
    private func draftBinding(_ day: Date) -> Binding<CalendarNewDraft?> {
        Binding(get: { model.draft.flatMap { model.calendar.isDate($0.start, inSameDayAs: day) && !$0.fromButton ? $0 : nil } }, set: { model.draft = $0 })
    }
}
