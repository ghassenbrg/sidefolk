import SidefolkCore
import SwiftUI

/// The Calendar's month (D66): whole weeks from the person's first weekday, each day with as many chips as fit and
/// "+ N more" to its list. Days outside the month are dimmer; today's number is circled.
struct CalendarMonth: View {
    var model: CalendarModel
    var open: (CalendarModel.Entry) -> Void
    var edit: (Reminder) -> Void
    var add: (Date) -> Void
    @Environment(\.undoManager) private var undo

    private static let header: CGFloat = 24
    private static let least: CGFloat = 92
    private static let chip: CGFloat = 20

    var body: some View {
        let days = model.days
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        GeometryReader { geo in
            // The weeks share the height; below the least a day needs, the month scrolls.
            let row = max(Self.least, (geo.size.height - Self.header) / CGFloat(max(weeks.count, 1)))
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(days.prefix(7), id: \.self) { day in
                            Text(verbatim: day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                    }
                    .frame(height: Self.header)
                    ForEach(weeks, id: \.first) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { cell($0, height: row, wide: geo.size.width / 7 >= 130) }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
            }
            .scrollDisabled(row * CGFloat(weeks.count) + Self.header <= geo.size.height)
        }
    }

    private func cell(_ day: Date, height: CGFloat, wide: Bool) -> some View {
        let cal = model.calendar
        let inMonth = cal.isDate(day, equalTo: model.anchor, toGranularity: .month)
        let today = cal.isDateInToday(day)
        let entries = model.entries(on: day)
        // Room for the number and as many chips as fit; one line goes to "+ N more" when they don't.
        let room = max(1, Int((height - 30) / Self.chip))
        let shown = entries.count > room ? room - 1 : entries.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: day.formatted(.dateTime.day()))
                .font(Theme.Font.captionStrong).monospacedDigit()
                .foregroundStyle(today ? Theme.onAccent : inMonth ? Theme.ink : Theme.inkFaint)
                .frame(minWidth: 22, minHeight: 22)
                .background(today ? Theme.accent : .clear, in: Circle())
            ForEach(entries.prefix(shown)) { entry in
                CalendarChip(entry: entry, model: model, showsTime: wide, open: open, edit: edit)
            }
            if entries.count > shown {
                Button("+ \(entries.count - shown) more") { model.show(day: day) }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
                    .padding(.horizontal, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
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
        .onTapGesture(count: 2) { add(model.newTime(on: day)) }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            Task { await model.drop(id, on: day, undo: undo) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }
}
