import SidefolkCore
import SwiftUI

/// The Calendar's own sidebar (D97): a month to jump with (today circled, the chosen day filled, a dot where something
/// is), then the calendars, Sidefolk's own first, each with its colour and a box that shows or hides it, remembered.
struct CalendarSidebar: View {
    var model: CalendarModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                CalendarMiniMonth(model: model)
                list
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.surface)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            group(Text(verbatim: "Sidefolk")) {
                ForEach([CalendarEntry.Kind.reminder, .task, .routine], id: \.self) { kind in
                    if let id = kind.listId { row(id: id, title: kind.name, hex: kind.hex) }
                }
            }
            if model.calendarOn {
                let accounts = Dictionary(grouping: model.calendars, by: \.account)
                ForEach(accounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { account in
                    group(Text(verbatim: account.isEmpty ? String(localized: "Other", comment: "The Calendar's list: calendars with no account") : account)) {
                        ForEach((accounts[account] ?? []).sorted { $0.title < $1.title }) { info in
                            row(id: info.id, title: info.title, hex: info.color.hex, readOnly: !info.writable)
                        }
                    }
                }
                if model.calendars.isEmpty {
                    Text("macOS hasn't let Sidefolk read your calendars.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button("Show my calendar") { Task { await model.showCalendar() } }
                    .buttonStyle(.sf(.secondary))
            }
        }
    }

    private func group(_ title: Text, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(Theme.Font.eyebrow).foregroundStyle(Theme.inkMuted).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    /// One calendar: its box in its colour (filled while shown), its name, a lock where it can't be changed.
    private func row(id: String, title: String, hex: UInt32, readOnly: Bool = false) -> some View {
        let shown = !model.hidden.contains(id)
        let tint = CalendarTint.of(hex)
        return Button { model.setHidden(id, shown) } label: {
            HStack(spacing: Theme.Space.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(tint.edge, lineWidth: 1.5)
                    if shown {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.edge)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(tint.onSelected)
                    }
                }
                .frame(width: 15, height: 15)
                Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if readOnly {
                    Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                        .help(Text("Read only: change it in Calendar", comment: "The Calendar's list: a calendar Sidefolk can't change"))
                }
            }
            .frame(minHeight: Theme.Size.sidebarRow - 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(shown ? Text("Shown", comment: "A calendar in the list is shown") : Text("Hidden", comment: "A calendar in the list is hidden"))
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}

/// A small month to jump with: its own ‹ ›, today circled, the day in view filled, a dot under days with something.
struct CalendarMiniMonth: View {
    var model: CalendarModel
    @State private var month: Date?

    var body: some View {
        let cal = model.calendar
        let shown = month ?? model.shownMonth
        let days = CalendarGrid.monthDays(of: shown, calendar: cal)
        VStack(spacing: 4) {
            HStack {
                Text(verbatim: shown.formatted(.dateTime.month(.wide).year())).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button { month = cal.date(byAdding: .month, value: -1, to: shown) } label: { Image(systemName: "chevron.backward").frame(width: 20, height: 20) }
                        .accessibilityLabel(Text("Show the previous month"))
                    Button { month = cal.date(byAdding: .month, value: 1, to: shown) } label: { Image(systemName: "chevron.forward").frame(width: 20, height: 20) }
                        .accessibilityLabel(Text("Show the next month"))
                }
                .buttonStyle(.sf(.plain))
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    ForEach(days.prefix(7), id: \.self) { day in
                        Text(verbatim: day.formatted(.dateTime.weekday(.narrow))).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<(days.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { cell($0, month: shown) }
                    }
                }
            }
        }
        .onChange(of: model.shownMonth) { month = nil }
    }

    private func cell(_ day: Date, month: Date) -> some View {
        let cal = model.calendar
        let today = cal.isDateInToday(day)
        let chosen = model.mode != .month && model.mode != .year && cal.isDate(day, inSameDayAs: model.chosenDay)
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let busy = !model.entries(on: day).isEmpty
        return Button { model.jump(to: day) } label: {
            VStack(spacing: 1) {
                Text(verbatim: day.formatted(.dateTime.day())).font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(today ? Theme.onAccent : chosen ? Theme.ink : inMonth ? Theme.ink : Theme.inkFaint)
                    .frame(width: 22, height: 20)
                    .background {
                        if today { Circle().fill(Theme.accent) } else if chosen { Circle().fill(Theme.accentSoft) }
                    }
                Circle().fill(busy ? Theme.inkFaint : .clear).frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .accessibilityLabel(Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }
}
