import SidefolkCore
import SwiftUI

/// The Calendar's year (D97): twelve small months, today circled, each day with something on it shaded by how busy it
/// is (in the accent, its count in words for VoiceOver). A click opens that day; a month's name opens the month.
struct CalendarYear: View {
    var model: CalendarModel

    var body: some View {
        let months = CalendarGrid.yearMonths(of: model.days.first ?? Date(), calendar: model.calendar)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: Theme.Space.l, alignment: .top)],
                          alignment: .leading, spacing: Theme.Space.l) {
                    ForEach(months, id: \.self) { month(starting: $0).id($0) }
                }
                .padding(Theme.Space.l)
            }
            .task(id: months.first) {
                // This year opens at this month.
                guard let now = months.first(where: { model.calendar.isDate($0, equalTo: Date(), toGranularity: .month) }) else { return }
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(now, anchor: .center)
            }
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }

    private func month(starting first: Date) -> some View {
        let cal = model.calendar
        let days = CalendarGrid.monthDays(of: first, calendar: cal)
        return VStack(alignment: .leading, spacing: 4) {
            Button { model.mode = .month; model.jump(to: first) } label: {
                Text(verbatim: first.formatted(.dateTime.month(.wide))).font(Theme.Font.headline)
                    .foregroundStyle(cal.isDate(first, equalTo: Date(), toGranularity: .month) ? Theme.link : Theme.ink)
            }
            .buttonStyle(.sfBare)
            .accessibilityAddTraits(.isHeader)
            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    ForEach(days.prefix(7), id: \.self) { day in
                        Text(verbatim: day.formatted(.dateTime.weekday(.narrow))).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<(days.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                            if cal.isDate(day, equalTo: first, toGranularity: .month) { cell(day) } else { Color.clear.frame(height: 22) }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let today = model.calendar.isDateInToday(day)
        let count = model.entries(on: day).count
        return Button { model.show(day: day) } label: {
            Text(verbatim: day.formatted(.dateTime.day())).font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(today ? Theme.onAccent : Theme.ink)
                .frame(width: 22, height: 22)
                .background {
                    if today {
                        Circle().fill(Theme.accent)
                    } else if count > 0 {
                        // One thing a light wash, four or more the strongest: how full the day is, at a glance.
                        Circle().fill(Theme.accent.opacity(0.12 + 0.075 * Double(min(count, 4))))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .help(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(count > 0 ? Text("\(count) things", comment: "The Calendar's narrow month: how many things a day has") : Text(verbatim: ""))
    }
}
