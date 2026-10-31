import SidefolkCore
import SwiftUI

// Pieces of Today that more than one layout uses (D58): watches as small tiles, a line of recent values, tomorrow
// beside the day, and what can be done with a reminder.

/// A watch as a small tile: where it looks, its state in one word, and what it last saw. A click shows the whole
/// watch with its buttons; it stands out while what it noticed waits for you.
struct WatchCard: View {
    var watcher: Watcher
    var model: NowModel
    @State private var open = false

    var body: some View {
        let kind = Describe.watcherKind(watcher.kind)
        let waiting = model.changeWaiting(for: watcher) != nil
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label { Text(verbatim: Describe.watcherTarget(watcher) ?? watcher.title).lineLimit(1).truncationMode(.middle) }
                    icon: { Image(systemName: kind.symbol) }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                Text(word(waiting: waiting)).font(Theme.Font.title).foregroundStyle(tone(waiting: waiting))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Theme.Space.m)
            .background(waiting ? Theme.accentSoft.opacity(0.6) : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(waiting ? Theme.accent.opacity(0.6) : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            WatchTile(watcher: watcher, model: model).frame(width: 340).padding(Theme.Space.s)
        }
        .onChange(of: open) { _, isOpen in if isOpen { Task { await model.seen(watcher) } } }
        .contextMenu {
            Button("Check now") { Task { await model.checkNow(watcher) } }.disabled(watcher.state == .paused)
            if watcher.state == .paused {
                Button("Resume") { Task { await model.resume(watcher) } }
            } else {
                Button("Pause") { Task { await model.pause(watcher) } }
            }
            Divider()
            Button("Stop watching", role: .destructive) { Task { await model.stop(watcher) } }
        }
        .accessibilityLabel(Text(verbatim: "\(watcher.title), \(word(waiting: waiting)), \(detail)"))
        .accessibilityHint(Text("Shows the watch"))
    }

    private func word(waiting: Bool) -> String {
        if waiting, watcher.state != .error { return String(localized: "Changed", comment: "A watch tile: what it watches changed") }
        switch watcher.state {
        case .error: return String(localized: "Having trouble")
        case .paused: return String(localized: "Paused")
        case .triggered: return String(localized: "Spotted")
        case .expired: return String(localized: "Expired")
        case .active: return String(localized: "watch.state.active", defaultValue: "Watching", comment: "Status chip on a watch that is running")
        }
    }

    /// A change is news, not trouble (StatusTone.watch); a watch that's simply watching keeps the ink.
    private func tone(waiting: Bool) -> Color {
        switch StatusTone.watch(watcher.state, changeWaiting: waiting) {
        case .neutral: watcher.state == .active ? Theme.ink : Theme.inkFaint
        case let tone: Theme.color(tone)
        }
    }

    /// When it last changed and the first line of that change, else when it last looked.
    private var detail: String {
        if let change = watcher.lastPageChange, let line = change.added.first ?? change.removed.first {
            return "\(TimeFormat.clock(change.at, calendar: .current)) · \(line)"
        }
        if let checked = watcher.lastCheckedAt {
            return String(localized: "checked \(TimeText.relative(checked))", comment: "“checked 5 min ago”")
        }
        return String(localized: "not checked yet")
    }
}

/// A live value as a small tile: its name, the value, and a line of the last few values when they are numbers.
struct ReportCard: View {
    var report: Watcher
    var reading: WatchReading?
    var values: [Double]
    var model: NowModel
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label { Text(verbatim: reading?.label ?? report.title).lineLimit(1) }
                    icon: { Image(systemName: Describe.watcherKind(report.kind).symbol) }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                Text(verbatim: reading?.value ?? "…").font(Theme.Font.title).monospacedDigit()
                    .foregroundStyle(report.state == .paused ? Theme.inkFaint : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if values.count > 1 {
                    Sparkline(values: values).frame(height: 18)
                } else {
                    Text(verbatim: Describe.reportSchedule(report)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Theme.Space.m)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ReportRow(report: report, reading: reading, model: model).frame(width: 380)
        }
        .contextMenu {
            if report.state == .paused {
                Button("Resume") { Task { await model.resume(report) } }
            } else {
                Button("Pause") { Task { await model.pause(report) } }
            }
            Button("Stop") { Task { await model.stop(report) } }
        }
        .accessibilityLabel(Text(verbatim: "\(report.title), \(reading?.value ?? "")"))
        .accessibilityHint(Text("Shows the watch"))
    }
}

/// The last few values as a line, lowest to highest of what's shown, so a change reads at a glance.
struct Sparkline: View {
    var values: [Double]
    var color: Color = Theme.link

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0, high = values.max() ?? 1
            let range = max(high - low, 0.0001)
            Path { path in
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                                        y: geo.size.height * (1 - CGFloat((v - low) / range)) * 0.9 + geo.size.height * 0.05)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Tomorrow beside the day's line: its first few reminders and events, and the rest of the week a click away.
struct TomorrowColumn: View {
    var reminders: [Reminder]
    var events: [CalendarEvent]
    var later: [Reminder]
    var model: NowModel
    var edit: (Reminder) -> Void
    @State private var showingLater = false

    var body: some View {
        let rows = DayRow.merge(events: events, reminders: reminders)
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(Text("Tomorrow"))
            ForEach(rows.prefix(4)) { row in
                switch row {
                case .event(let e): line(e.allDay ? nil : e.start, e.title)
                case .reminder(let r):
                    line(r.nextDue ?? r.fireAt, r.title)
                        .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
                }
            }
            let more = max(0, rows.count - 4) + later.count
            if more > 0 {
                Button("+ \(more) more") { showingLater = true }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
                    .popover(isPresented: $showingLater, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(reminders + later) { r in ReminderRow(reminder: r, later: true, model: model) }
                        }
                        .frame(width: 360)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.m)
    }

    private func line(_ time: Date?, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let time {
                Text(verbatim: TimeFormat.clock(time, calendar: .current)).font(Theme.Font.captionStrong).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Text(verbatim: title).font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What can be done with a reminder, wherever it shows: done, snooze, edit, cancel.
struct ReminderMenu: View {
    var reminder: Reminder
    var model: NowModel
    var edit: (Reminder) -> Void

    var body: some View {
        Button("Mark done") { Task { await model.complete(reminder) } }
        if let item = model.item(of: reminder) { Button(ItemLink.openTitle(item.kind)) { model.open(item) } }
        Button("Edit…") { edit(reminder) }
        Menu("Snooze") {
            ForEach(NowModel.Snooze.allCases, id: \.self) { option in
                Button { Task { await model.snooze(reminder, option) } } label: { Text(verbatim: model.title(for: option)) }
            }
        }
        Divider()
        Button("Cancel reminder", role: .destructive) { Task { await model.cancel(reminder) } }
    }
}

/// A row of columns (D64): side by side, each its share of the width, while every column gets at least `minimum`;
/// otherwise one under the other at full width.
struct ColumnsLayout: Layout {
    var widths: [Double]
    var spacing: CGFloat
    /// Each column's least width; a picture's column can be narrower than one of words.
    var minimums: [CGFloat] = []
    var minimum: CGFloat = 230

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let frames = place(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func place(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let n = subviews.count
        guard n > 0 else { return [] }
        let gaps = spacing * CGFloat(n - 1)
        let shares = (0..<n).map { CGFloat($0 < widths.count ? widths[$0] : 1) }
        let total = shares.reduce(0, +)
        let sideBySide = n > 1 && (0..<n).allSatisfy { (width - gaps) * shares[$0] / total >= ($0 < minimums.count ? minimums[$0] : minimum) }
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            if sideBySide {
                let w = (width - gaps) * shares[i] / total
                let h = subview.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
                frames.append(CGRect(x: x, y: 0, width: w, height: h))
                x += w + spacing
            } else {
                let h = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames.append(CGRect(x: 0, y: y, width: width, height: h))
                y += h + (h > 0 ? spacing : 0)
            }
        }
        return frames
    }
}

/// A decision as a card in a row of them (D64): a coloured dot and who's asking above the question, outlined while
/// the keyboard is on it.
struct QueueCardFrame<Content: View>: View {
    var label: String
    var tint: Color
    var focused: Bool
    /// A card's width in a row; nil fills a column (the Console's stack).
    var width: CGFloat? = 320
    /// When it stops waiting, counted down at the top right.
    var deadline: Date?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                if let deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, deadline.timeIntervalSince(context.date))
                        Label(String(localized: "\(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))) left", comment: "A countdown on a decision: “07:42 left”"),
                              systemImage: "timer")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(left < 120 ? Theme.warning : Theme.link)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            content
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: focused ? 2 : 1))
    }
}
