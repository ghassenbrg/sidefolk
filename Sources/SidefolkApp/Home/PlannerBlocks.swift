import SidefolkCore
import SwiftUI

// Today's pieces in the Planner's styles (D64): an open spread you write in, decisions as index cards, watches in the
// margin, and the companion as a sticker on the page.

/// A sheet of the spread (a column with `page`): paper with a soft shadow.
struct PaperPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

// MARK: header:page

/// The date, big, as a planner's page starts: the day of the month, the weekday and month, and the weather when a
/// weather watch reads it.
struct PageHeader: View {
    var model: NowModel

    var body: some View {
        let now = Date()
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(verbatim: now.formatted(.dateTime.day()))
                .font(.system(size: 56 * ThemeStore.shared.style.tokens.type.scale, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(now.formatted(.dateTime.weekday(.wide))), \(now.formatted(.dateTime.month(.wide)))",
                     comment: "Under a planner page's big date: “Friday, October”")
                    .font(.system(size: 20, design: .serif)).italic().foregroundStyle(Theme.ink)
                if let weather {
                    Text(verbatim: weather).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var weather: String? {
        guard let report = model.reports.first(where: { $0.kind == WatchKind.weather }), let reading = model.readings[report.id] else { return nil }
        return String(localized: "\(reading.value) in \(reading.label) · from Weather", comment: "Under the date: “18 °C in Fukuoka · from Weather”")
    }
}

// MARK: day:ruled

/// The day on ruled lines (D64): a box to tick, what's done struck through with when, reminders and the calendar's
/// events marked, a line at the present, and a last line to write on. Tomorrow and what was jotted today below.
struct RuledDay: View {
    var model: NowModel
    var edit: (Reminder) -> Void
    @State private var writing = ""

    private enum Line: Identifiable {
        case done(Reminder), reminder(Reminder), event(CalendarEvent), now
        var id: String {
            switch self {
            case .done(let r): "d" + r.id
            case .reminder(let r): "r" + r.id
            case .event(let e): "e" + e.id
            case .now: "now"
            }
        }
        var at: Date {
            switch self {
            case .done(let r): r.lastFiredAt ?? r.fireAt
            case .reminder(let r): r.nextDue ?? r.fireAt
            case .event(let e): e.start
            case .now: Date()
            }
        }
    }

    var body: some View {
        let today = model.groups().first { $0.day == .today }?.reminders ?? []
        let tomorrow = model.groups().first { $0.day == .tomorrow }?.reminders ?? []
        let lines = (model.doneToday.map(Line.done) + today.map(Line.reminder)
                     + model.events(on: .today).filter { !$0.allDay }.map(Line.event) + [.now]).sorted { $0.at < $1.at }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line($0) }
            HStack(spacing: Theme.Space.m) {
                Color.clear.frame(width: 44)
                TextField("Click a line to write, like “call mom at 6”", text: $writing)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .serif)).italic()
                    .foregroundStyle(Theme.ink)
                    .onSubmit {
                        let text = writing.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        writing = ""
                        model.services.ask(text, how: .auto)
                    }
            }
            .ruled()
            if !tomorrow.isEmpty {
                Text("Tomorrow").font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.inkMuted)
                    .padding(.top, Theme.Space.l).ruled()
                ForEach(tomorrow.prefix(4)) { r in
                    HStack(spacing: Theme.Space.m) {
                        time(r.nextDue ?? r.fireAt)
                        Text(verbatim: r.title).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                    .ruled()
                    .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
                }
            }
            if !jotted.isEmpty {
                Text("Jotted today").font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.inkMuted)
                    .padding(.top, Theme.Space.l).ruled()
                ForEach(jotted) { item in
                    Button { model.open(item) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(verbatim: item.title).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(verbatim: jottedDetail(item)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ruled()
                }
            }
        }
    }

    private var jotted: [NotebookItem] { model.recentNotes.filter { Calendar.current.isDateInToday($0.createdAt) } }

    private func jottedDetail(_ item: NotebookItem) -> String {
        let who = Describe.source(item.source) ?? String(localized: "you", comment: "Who saved a note: the person")
        guard let c = model.noteCollections[item.collectionId] else { return who }
        return "\(who) → \(NotebookCollections.shownName(c))"
    }

    @ViewBuilder private func line(_ line: Line) -> some View {
        switch line {
        case .now:
            HStack(spacing: 4) {
                Rectangle().fill(Theme.danger).frame(height: 1.5)
                Text("now \(TimeFormat.clock(Date(), calendar: .current))", comment: "The present on the day's ruled lines")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onDanger)
                    .padding(.horizontal, 5).background(Theme.danger, in: Capsule())
            }
            .padding(.vertical, 2)
        case .done(let r):
            row(at: line.at, title: r.title, struck: true, ticked: true) {
                Text("done \(TimeFormat.clock(line.at, calendar: .current))", comment: "On a ruled line: when it was done").foregroundStyle(Theme.inkFaint)
            }
        case .reminder(let r):
            let late = line.at < Date()
            row(at: line.at, title: r.title, struck: false, ticked: false, tick: { Task { await model.complete(r) } }) {
                if late {
                    HStack(spacing: 4) {
                        Label(TimeText.relative(line.at), systemImage: "alarm").foregroundStyle(Theme.danger)
                        Menu("snooze") {
                            ForEach(NowModel.Snooze.allCases, id: \.self) { option in
                                Button { Task { await model.snooze(r, option) } } label: { Text(verbatim: model.title(for: option)) }
                            }
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Theme.link)
                    }
                } else {
                    Label("reminder", systemImage: "alarm").foregroundStyle(Theme.inkFaint)
                }
            }
            .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
        case .event(let e):
            row(at: line.at, title: e.title, struck: false, ticked: nil) {
                Label("Calendar", systemImage: "calendar").foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func row<T: View>(at: Date, title: String, struck: Bool, ticked: Bool?, tick: (() -> Void)? = nil,
                              @ViewBuilder mark: () -> T) -> some View {
        HStack(spacing: Theme.Space.m) {
            time(at)
            if let ticked {
                Button { tick?() } label: {
                    Image(systemName: ticked ? "checkmark.square" : "square").foregroundStyle(ticked ? Theme.inkFaint : Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .disabled(tick == nil)
                .accessibilityLabel(Text(ticked ? "Done" : "Mark “\(title)” done"))
            } else {
                Color.clear.frame(width: 14)
            }
            Text(verbatim: title).font(.system(size: 15, design: .serif)).strikethrough(struck)
                .foregroundStyle(struck ? Theme.inkFaint : Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            mark().font(Theme.Font.caption).lineLimit(1)
        }
        .ruled()
    }

    private func time(_ at: Date) -> some View {
        Text(verbatim: TimeFormat.clock(at, calendar: .current)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            .frame(width: 44, alignment: .leading)
    }
}

private extension View {
    /// A line of a ruled page: its height, and the rule under it.
    func ruled() -> some View {
        padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: queue:index

/// A decision as an index card (D64): who asks in small capitals with the risk stamped beside it, a clip at the corner,
/// faint rules behind the words.
struct IndexCardFrame<Content: View>: View {
    var label: String
    var risk: Risk?
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(verbatim: label).textCase(.uppercase).font(.system(size: 10.5, weight: .bold)).kerning(0.8)
                    .foregroundStyle(Theme.link).lineLimit(1)
                if let risk, risk != .low {
                    Text(verbatim: risk == .high ? String(localized: "High risk") : String(localized: "Medium risk"))
                        .textCase(.uppercase).font(.system(size: 9.5, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(risk == .high ? Theme.danger : Theme.link)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(risk == .high ? Theme.danger : Theme.link, lineWidth: 1.2))
                        .rotationEffect(.degrees(-2))
                }
                Spacer(minLength: 0)
                Image(systemName: "paperclip").font(.system(size: 18, weight: .light)).foregroundStyle(Theme.inkFaint)
                    .rotationEffect(.degrees(20)).offset(y: -6).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            // Rules behind the card's words, as an index card has.
            VStack(spacing: 22) { ForEach(0..<14, id: \.self) { _ in Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1) } }
                .padding(.top, 34)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: focused ? 2 : 1))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }
}

// MARK: watching:margin

/// Watches as a quiet list in the margin (D64), a stamp on what changed until you look.
struct MarginWatches: View {
    var model: NowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keeping an eye on").font(.system(size: 17, design: .serif)).italic().foregroundStyle(Theme.ink)
                .padding(.bottom, Theme.Space.xs)
            if model.watchers.isEmpty && model.reports.isEmpty {
                Button("Watch something…") { model.services.openAsk(prefill: "tell me when ") }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            ForEach(model.watchers) { w in
                let waiting = model.changeWaiting(for: w) != nil
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: Describe.watcherKind(w.kind).symbol).foregroundStyle(Theme.inkMuted).frame(width: 18)
                    Text(verbatim: Describe.watcherTarget(w) ?? w.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    if waiting {
                        Text("Changed", comment: "A stamp on a watch whose page changed").textCase(.uppercase)
                            .font(.system(size: 9.5, weight: .heavy)).kerning(0.6).foregroundStyle(Theme.danger)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.danger, lineWidth: 1.2))
                            .rotationEffect(.degrees(-3))
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.seen(w) } }
            }
            ForEach(model.reports) { r in
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: Describe.watcherKind(r.kind).symbol).foregroundStyle(Theme.inkMuted).frame(width: 18)
                    Text(verbatim: model.readings[r.id]?.label ?? r.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(verbatim: model.readings[r.id]?.value ?? "…").font(.system(size: 14, design: .serif)).foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }
}

// MARK: companion:sticker

/// The companion as a sticker on the page (D64), saying one line about what it's on.
struct CompanionSticker: View {
    var model: NowModel

    var body: some View {
        let settings = model.services.runtime.settings.current
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            Spacer(minLength: 0)
            Text(verbatim: model.nookLine).font(.system(size: 14, design: .serif)).italic().foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            CompanionPortrait(settings: settings, state: settings.isQuiet(at: Date()) ? .sleeping : .idle, side: 74)
                .padding(5)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .rotationEffect(.degrees(-4))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
