import SidefolkCore
import SwiftUI

/// Home › Calendar (D66, D97), as a Mac calendar works: its own sidebar (a month to jump with, the calendars shown or
/// hidden), the Agenda, a Day, a Week, a Month that scrolls on and a Year. ⌘← ⌘→ (the chevrons, or two fingers
/// sideways) step back and ahead, ⌘T comes back to today; the arrows move the selection, Return opens it, Delete
/// removes it with ⌘Z. A double-click or a drag over empty time adds something there; things are dragged to move
/// and an event's bottom edge to change its length.
struct CalendarView: View {
    @Bindable var model: CalendarModel
    @FocusState private var focused: Bool
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undo
    @State private var width: CGFloat = 1000
    @State private var narrowSidebar = false

    /// Below this, the sidebar is a popover from its button rather than a column.
    private static let sidebarRoom: CGFloat = 820

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarShown, width >= Self.sidebarRoom {
                CalendarSidebar(model: model)
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle().fill(Theme.line).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header
                notices
                content
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
        // No minimum of its own: Home's window takes its least size from its pages, and a page that asked for more
        // than the window had pushed the whole window's content up under the toolbar.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfaceSunken)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The page takes the keyboard, so the arrows, Return and Delete work without stealing them from the one bar.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        // On the page, not as the buttons' shortcuts: those would take ⌘← and ⌘→ from every text field in the window.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let back = press.key == .upArrow || press.key == (direction == .rightToLeft ? .rightArrow : .leftArrow)
            // Arrow keys always carry the function and keypad flags.
            let modifiers = press.modifiers.subtracting([.function, .numericPad])
            if modifiers == .command, press.key == .leftArrow || press.key == .rightArrow {
                step(back ? -1 : 1)
                return .handled
            }
            guard modifiers.isEmpty else { return .ignored }
            model.moveSelection(back ? -1 : 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard model.selection != nil else { return .ignored }
            model.openSelection()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in
            guard let entry = model.entry(id: model.selection) else { return .ignored }
            model.delete(entry, undo: undo)
            return .handled
        }
        .onKeyPress(.escape) {
            guard model.selection != nil || model.inspecting != nil else { return .ignored }
            model.inspecting = nil
            model.selection = nil
            return .handled
        }
        .onKeyPress(characters: ["t", "T"]) { press in
            guard press.modifiers.isEmpty || press.modifiers == .command else { return .ignored }
            step(nil)
            return .handled
        }
        .onAppear { focused = true }
        .task { await model.reload() }
        .sheet(isPresented: $model.asksForWrites) { CalendarWritesSheet(model: model) }
    }

    /// ← is back in time where text runs left to right, ahead where it runs right to left; nil is today.
    private func step(_ by: Int?) {
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
            if let by { model.go(by) } else { model.today() }
        }
    }

    private var header: some View {
        WrapRow(minimum: 260, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                sidebarButton
                Text(verbatim: model.title).font(Theme.Font.title).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .contentTransition(.numericText())
            }
            HStack(spacing: Theme.Space.s) {
                Button { model.startNew(at: model.newTime(on: model.mode == .day ? model.chosenDay : Date()), fromButton: true) } label: {
                    Label("New", systemImage: "plus").labelStyle(.iconOnly).frame(width: 18)
                }
                .buttonStyle(.sf(.quiet))
                .help(Text("Add a reminder, a task or an event", comment: "The Calendar's + button"))
                .popover(item: newFromButton, arrowEdge: .bottom) { CalendarEditor(model: model, draft: $0) }
                Button("Today") { step(nil) }
                    .buttonStyle(.sf(.secondary))
                    .help(Text("Back to today (⌘T)"))
                HStack(spacing: 0) {
                    Button { step(direction == .rightToLeft ? 1 : -1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 22) }
                        .help(Text(direction == .rightToLeft ? nextHelp : previousHelp))
                        .accessibilityLabel(Text(direction == .rightToLeft ? nextHelp : previousHelp))
                    Button { step(direction == .rightToLeft ? -1 : 1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 22) }
                        .help(Text(direction == .rightToLeft ? previousHelp : nextHelp))
                        .accessibilityLabel(Text(direction == .rightToLeft ? previousHelp : nextHelp))
                }
                // The chevrons point where time goes on screen: in Arabic the next week is on the left.
                .environment(\.layoutDirection, .leftToRight)
                .buttonStyle(.sf(.plain))
                SegmentedPicker("View", selection: $model.mode, segments: [
                    .init(CalendarModel.Mode.agenda, Text("Agenda", comment: "The Calendar's list of the next two weeks")),
                    .init(CalendarModel.Mode.day, Text("Day", comment: "The Calendar's view of one day")),
                    .init(CalendarModel.Mode.week, "Week"),
                    .init(CalendarModel.Mode.month, "Month"),
                    .init(CalendarModel.Mode.year, Text("Year", comment: "The Calendar's view of a whole year")),
                ], small: width < 900)
            }
            .fixedSize()
        }
    }

    /// The editor of a new thing from the + button (one placed on the grid opens from where it was placed).
    private var newFromButton: Binding<CalendarNewDraft?> {
        Binding(get: { model.draft?.fromButton == true ? model.draft : nil }, set: { model.draft = $0 })
    }

    @ViewBuilder private var sidebarButton: some View {
        let label = Text("Calendars", comment: "The Calendar's sidebar button: the month and the list of calendars")
        if width >= Self.sidebarRoom {
            Button { withAnimation(reduceMotion ? nil : Theme.Motion.standard) { model.toggleSidebar() } } label: {
                Image(systemName: "sidebar.leading").frame(width: 24, height: 22)
            }
            .buttonStyle(.sf(.plain))
            .help(label)
            .accessibilityLabel(label)
        } else {
            Button { narrowSidebar = true } label: { Image(systemName: "sidebar.leading").frame(width: 24, height: 22) }
                .buttonStyle(.sf(.plain))
                .help(label)
                .accessibilityLabel(label)
                .popover(isPresented: $narrowSidebar, arrowEdge: .bottom) { CalendarSidebar(model: model).frame(width: 240, height: 520) }
        }
    }

    /// One calm line at a time: the calendar not shown yet, what the last change couldn't do.
    @ViewBuilder private var notices: some View {
        if !model.calendarOn {
            RowsCard {
                InlineEmpty(text: "Your calendar can be here too, beside your reminders, in its own colours.", systemImage: "calendar",
                            actionTitle: "Show my calendar") { Task { await model.showCalendar() } }
            }
        }
        if let problem = model.problem {
            InlineError(error: problem)
        }
    }

    @ViewBuilder private var content: some View {
        let slide: Edge = model.lastStep < 0 ? .leading : .trailing
        Group {
            switch model.mode {
            case .agenda: CalendarList(model: model)
            case .day, .week: CalendarTimeGrid(model: model, days: model.days)
            case .month: CalendarMonth(model: model)
            case .year: CalendarYear(model: model)
            }
        }
        .id(periodKey)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: slide).combined(with: .opacity),
                                                           removal: .move(edge: slide == .leading ? .trailing : .leading).combined(with: .opacity)))
        .offset(x: model.swipe)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(CalendarScrollCatcher(model: model, step: step))
    }

    /// Changes when a step shows another period, so it slides in; the month scrolls in place instead.
    private var periodKey: String {
        model.mode == .month ? "month" : "\(model.mode.rawValue)-\(model.days.first?.timeIntervalSince1970 ?? 0)"
    }

    private var previousHelp: LocalizedStringKey {
        switch model.mode {
        case .day: "Show the previous day (⌘←)"
        case .week: "Show the previous week (⌘←)"
        case .month: "Show the previous month (⌘←)"
        case .year: "Show the previous year (⌘←)"
        case .agenda: "Show the previous two weeks (⌘←)"
        }
    }

    private var nextHelp: LocalizedStringKey {
        switch model.mode {
        case .day: "Show the next day (⌘→)"
        case .week: "Show the next week (⌘→)"
        case .month: "Show the next month (⌘→)"
        case .year: "Show the next year (⌘→)"
        case .agenda: "Show the next two weeks (⌘→)"
        }
    }
}
