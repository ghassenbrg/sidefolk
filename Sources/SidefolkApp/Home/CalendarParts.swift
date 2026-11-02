import SidefolkCore
import SwiftUI

// What the Calendar's views share (D66, D97): a thing as a block (Day and Week), a bar (all day), a line (Month), its
// menu, and its details beside it.

/// A thing in the Day or Week, saying as much as it has room for: its title, then its time, then where, then its
/// notes, each only when the block is tall and wide enough; a reminder is one line with its picture. In its
/// calendar's colour: a tinted fill with a strong edge, solid while selected.
struct CalendarBlock: View {
    var entry: CalendarEntry
    var model: CalendarModel
    var width: CGFloat
    var height: CGFloat
    var selected: Bool

    var body: some View {
        let tint = model.tint(entry)
        let ink = selected ? tint.onSelected : tint.text
        let words = width >= 28
        VStack(alignment: .leading, spacing: 1) {
            if words {
                if height < 34 || entry.reminder != nil {
                    line(ink: ink)
                } else {
                    // As much title as two lines hold before the time (the rest in its help and details).
                    Text(verbatim: entry.title).font(Theme.Font.captionStrong).foregroundStyle(ink)
                        .strikethrough(entry.struck)
                        .lineLimit(height >= 52 ? 2 : 1)
                    Text(verbatim: span).font(Theme.Font.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.85)).lineLimit(1)
                    if let place = entry.event?.location, height >= 62 {
                        Label { Text(verbatim: place).lineLimit(1) } icon: { Image(systemName: "mappin").imageScale(.small) }
                            .labelStyle(.titleAndIcon).font(Theme.Font.caption).foregroundStyle(ink.opacity(0.85))
                    }
                    if let notes = entry.event?.notes, height >= 96, width >= 120 {
                        Text(verbatim: notes).font(Theme.Font.caption).foregroundStyle(ink.opacity(0.75))
                            .lineLimit(max(1, Int((height - 76) / 15)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, words ? 7 : 3)
        .padding(.trailing, 3)
        .padding(.vertical, height < 26 ? 2 : 3)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(selected ? tint.selectedFill : tint.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(tint.edge).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            if entry.late {
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.warning, lineWidth: 1)
            }
        }
        .opacity(entry.struck ? 0.6 : 1)
        .help(Text(verbatim: entry.spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.spoken))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// One line: a reminder's picture and title, or a short event's title and, where wide, its time.
    private func line(ink: Color) -> some View {
        HStack(spacing: 4) {
            if entry.reminder != nil {
                Image(systemName: entry.symbol(item: entry.reminder.flatMap(model.item))).imageScale(.small)
                    .foregroundStyle(selected ? ink : model.tint(entry).edge)
            }
            Text(verbatim: entry.title).font(Theme.Font.captionStrong).foregroundStyle(ink).strikethrough(entry.struck).lineLimit(1)
            if width >= 120 {
                Text(verbatim: TimeFormat.clock(entry.start, calendar: model.calendar)).font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(ink.opacity(0.85)).lineLimit(1).fixedSize()
            }
        }
    }

    /// "10:00–11:30".
    private var span: String {
        let cal = model.calendar
        return entry.end > entry.start ? CalendarEntry.span(entry.start, entry.end, calendar: cal)
            : TimeFormat.clock(entry.start, calendar: cal)
    }
}

/// A reminder in Day and Week (D97): a moment, so a one-line pill at its time rather than a slab of time; its picture
/// in its colour, its title, and, for one that comes back several times that day, how often.
struct CalendarPill: View {
    var entry: CalendarEntry
    var model: CalendarModel
    var every: String?
    var selected: Bool

    var body: some View {
        let tint = model.tint(entry)
        let ink = selected ? tint.onSelected : tint.text
        HStack(spacing: 4) {
            Image(systemName: entry.symbol(item: entry.reminder.flatMap(model.item))).imageScale(.small)
                .foregroundStyle(selected ? ink : tint.edge)
            Text(verbatim: entry.title).font(Theme.Font.captionStrong).foregroundStyle(ink).strikethrough(entry.struck)
                .lineLimit(1).layoutPriority(1)
            if let every {
                Text(verbatim: "· " + every).font(Theme.Font.caption).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? tint.selectedFill : tint.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            if entry.late { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.warning, lineWidth: 1) }
        }
        .opacity(entry.struck ? 0.6 : 1)
        .help(Text(verbatim: entry.spoken + (every.map { " · " + $0 } ?? "")))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.spoken + (every.map { ", " + $0 } ?? "")))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "+3": what didn't fit across a day's column at that time (D97). A click lists them; a click on one shows its
/// details there.
struct MoreChip: View {
    var entries: [CalendarEntry]
    var model: CalendarModel
    @State private var open = false
    @State private var chosen: CalendarEntry?

    var body: some View {
        Button { chosen = nil; open = true } label: {
            Text(verbatim: "\u{2066}+\(entries.count.formatted())\u{2069}")
                .font(Theme.Font.captionStrong).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 18)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .help(Text("\(entries.count) more at this time", comment: "The Calendar's week: things that didn't fit side by side; a click lists them"))
        .accessibilityLabel(Text("\(entries.count) more at this time", comment: "The Calendar's week: things that didn't fit side by side; a click lists them"))
        .popover(isPresented: $open, arrowEdge: .trailing) {
            if let chosen {
                VStack(alignment: .leading, spacing: 0) {
                    Button { self.chosen = nil } label: { Label("Back", systemImage: "chevron.backward") }
                        .buttonStyle(.sf(.plain)).padding([.top, .horizontal], Theme.Space.m)
                    CalendarInspector(entry: chosen, model: model)
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { entry in
                Button {
                    model.selection = entry.id
                    chosen = entry
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Circle().fill(model.tint(entry).edge).frame(width: 8, height: 8)
                        Text(verbatim: TimeFormat.clock(entry.start, calendar: model.calendar)).monospacedDigit().foregroundStyle(Theme.inkMuted)
                        Text(verbatim: entry.title).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(Theme.Font.body)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(minHeight: Theme.Size.compactRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityLabel(Text(verbatim: entry.spoken))
            }
        }
        .padding(Theme.Space.s)
        .frame(width: 280)
    }
}

/// An all-day or multi-day event as a filled bar in its calendar's colour.
struct CalendarBar: View {
    var entry: CalendarEntry
    var model: CalendarModel

    var body: some View {
        let tint = model.tint(entry)
        let selected = model.selection == entry.id
        Text(verbatim: entry.title)
            .font(Theme.Font.captionStrong).lineLimit(1)
            .foregroundStyle(selected ? tint.onSelected : tint.text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(selected ? tint.selectedFill : tint.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(tint.edge).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.inspecting = entry.id }
            .simultaneousGesture(TapGesture().onEnded { model.selection = entry.id })
            .contextMenu { CalendarMenu(entry: entry, model: model) }
            .calendarInspector(entry, model: model)
            .help(Text(verbatim: entry.spoken))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: entry.spoken))
            .accessibilityAddTraits(.isButton)
    }
}

/// One thing as a single line, as a month shows it: an all-day event as a filled bar; a timed one as its colour's
/// dot, its time and title; a reminder with its picture. A click selects, a double-click opens its details; a
/// movable one can be dragged to another day.
struct CalendarChip: View {
    var entry: CalendarEntry
    var model: CalendarModel
    /// Where a chip is narrow, the title gets the room.
    var showsTime = true

    var body: some View {
        let tint = model.tint(entry)
        let selected = model.selection == entry.id
        let ink = selected ? tint.onSelected : (entry.allDay ? tint.text : Theme.ink)
        let chip = HStack(spacing: 4) {
            if entry.reminder != nil {
                Image(systemName: entry.symbol(item: entry.reminder.flatMap(model.item))).imageScale(.small)
                    .foregroundStyle(selected ? ink : tint.edge)
            } else if !entry.allDay {
                Circle().fill(selected ? ink : tint.edge).frame(width: 7, height: 7)
            }
            if showsTime, !entry.allDay {
                Text(verbatim: TimeFormat.clock(entry.start, calendar: .current)).monospacedDigit()
                    .foregroundStyle(selected ? ink : Theme.inkMuted).fixedSize()
            }
            Text(verbatim: entry.title).strikethrough(entry.struck)
                .foregroundStyle(entry.struck && !selected ? Theme.inkFaint : ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(Theme.Font.caption)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.selectedFill)
            } else if entry.allDay {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.fill)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.inspecting = entry.id }
        .simultaneousGesture(TapGesture().onEnded { model.selection = entry.id })
        .contextMenu { CalendarMenu(entry: entry, model: model) }
        .calendarInspector(entry, model: model)
        .help(Text(verbatim: entry.spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.spoken))
        .accessibilityAddTraits(.isButton)
        if entry.movable {
            chip.draggable(entry.id) { chip.frame(width: 160) }
        } else {
            chip
        }
    }
}

/// A thing's menu: Get Info, then a reminder's next time has all of Today's (ReminderMenu); a later time of a series
/// edits the series or opens its note; an event Sidefolk may change can be deleted, and any opens in Calendar.
struct CalendarMenu: View {
    var entry: CalendarEntry
    var model: CalendarModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        Button("Get Info") { model.inspecting = entry.id }
        Divider()
        switch entry {
        case .reminder(let o):
            if o.isNext {
                ReminderMenu(reminder: o.reminder, model: model.now, edit: { _ in model.inspecting = entry.id })
            } else if let item = model.item(of: o.reminder) {
                Button(ItemLink.openTitle(item.kind)) { model.now.open(item) }
            }
            Divider()
            Button("Remove from Calendar") { model.delete(entry, undo: undo) }
        case .finished(let r, _):
            if let item = model.item(of: r) { Button(ItemLink.openTitle(item.kind)) { model.now.open(item) } }
        case .due(let item):
            Button("Mark Done") { Task { await model.finish(item, undo: undo) } }
            Button(ItemLink.openTitle(item.kind)) { model.now.open(item) }
        case .event(let e):
            Button("Open in Calendar") { model.openInCalendar(e) }
            if e.changeable {
                Divider()
                Button("Delete Event") { model.delete(entry, undo: undo) }
            }
        }
    }
}

extension View {
    /// A thing's details beside it while it is the one being inspected (a double-click, Return, Get Info).
    func calendarInspector(_ entry: CalendarEntry, model: CalendarModel) -> some View {
        popover(isPresented: Binding(get: { model.inspecting == entry.id }, set: { if !$0, model.inspecting == entry.id { model.inspecting = nil } }),
                arrowEdge: .trailing) {
            CalendarInspector(entry: entry, model: model)
        }
    }
}
