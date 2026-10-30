import SidefolkCore
import SwiftUI

// Today's pieces in the Stage's styles (D62): the companion big on its stage, saying what needs you; the day as
// stickers, watches as round badges, helpers at work, and what was jotted today.

// MARK: companion:stage

/// The companion on a stage with the theme's sky, a hello, and what needs you as speech bubbles from it. When nothing
/// does, it says so, cheers once, and naps when you're quiet.
struct TodayStage<Bubble: View>: View {
    var model: NowModel
    @ViewBuilder var bubble: (NowModel.Decision) -> Bubble
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cheering = false

    var body: some View {
        let settings = model.services.runtime.settings.current
        let queue = model.focusedQueue
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    TodayHeader.greeting().font(Theme.Font.hero).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    Text(verbatim: subtitle(settings)).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                }
                if queue.isEmpty {
                    allClear
                } else {
                    ForEach(queue.prefix(3)) { decision in bubble(decision) }
                    if queue.count > 3 {
                        Text("+ \(queue.count - 3) more").font(Theme.Font.captionStrong).foregroundStyle(Theme.link)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.l)
            .padding(.trailing, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: Theme.Space.xs) {
                CompanionPortrait(settings: settings, state: settings.isQuiet(at: Date()) ? .sleeping : .idle, side: 150)
                    .scaleEffect(cheering && !reduceMotion ? 1.08 : 1)
                    .overlay(alignment: .top) {
                        if cheering { Text(verbatim: "✨ 🎉 ✨").font(.system(size: 26)).offset(y: -30).transition(.opacity) }
                    }
                    .accessibilityHidden(true)
                Label("naps when it's quiet", systemImage: "zzz")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
                    .background(Theme.surfaceRaised.opacity(0.9), in: Capsule())
            }
            .padding(Theme.Space.m)
        }
        .frame(maxWidth: .infinity, minHeight: 560)
        // In the background, so the picture's own size never widens the stage.
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line))
        .onChange(of: queue.isEmpty) { wasEmpty, isEmpty in
            // The queue just cleared: one small cheer, then back to rest.
            guard isEmpty, !wasEmpty else { return }
            withAnimation(Theme.Motion.spring(0.4)) { cheering = true }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(Theme.Motion.ease(0.4)) { cheering = false }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var backdrop: some View {
        if let art = Theme.Art.backdrop(dark: scheme == .dark) {
            Image(decorative: art, scale: 2).resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            LinearGradient(colors: [Theme.accentSoft, Theme.surfaceSunken], startPoint: .top, endPoint: .bottom)
        }
    }

    private func subtitle(_ settings: AppSettings) -> String {
        let n = model.needsYouCount
        let watching = model.watchers.count + model.reports.count
        let needs = n == 0 ? String(localized: "Nothing needs you") : String(localized: "\(n) little things need you")
        guard watching > 0 else { return needs }
        let keeps = String(localized: "watching \(watching) things", comment: "On the stage, after what needs you: how many watches the companion keeps")
        return "\(needs) · \(keeps)"
    }

    private var allClear: some View {
        VStack(spacing: Theme.Space.xs) {
            Text("All clear.").font(Theme.Font.title).foregroundStyle(Theme.ink)
            Text(verbatim: nextUp).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: 360)
        .background(Theme.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var nextUp: String {
        let now = Date()
        let reminder = model.reminders.map { ($0.nextDue ?? $0.fireAt, $0.title) }.filter { $0.0 > now }.min { $0.0 < $1.0 }
        let event = model.events(on: .today).filter { !$0.allDay && $0.start > now }.map { ($0.start, $0.title) }.min { $0.0 < $1.0 }
        guard let next = [reminder, event].compactMap({ $0 }).min(by: { $0.0 < $1.0 }) else {
            return String(localized: "Nothing needs you, and nothing else is planned today.")
        }
        return String(localized: "Nothing needs you. Next up: \(next.1) at \(TimeFormat.clock(next.0, calendar: .current)).")
    }
}

/// A decision as a speech bubble from the companion (D62): who's asking, then the question and its buttons.
struct QueueBubbleFrame<Content: View>: View {
    var label: String
    var tint: Color
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            content
        }
        .frame(maxWidth: 440, alignment: .topLeading)
        .background(Theme.surfaceRaised, in: BubbleShape(radius: Theme.Radius.card))
        .overlay(BubbleShape(radius: Theme.Radius.card).stroke(focused ? Theme.accent : Theme.line, lineWidth: focused ? 2.5 : 1))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

/// A rounded box with a small tail on its right, toward the companion.
nonisolated struct BubbleShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: 0, dy: 0).divided(atDistance: rect.width - 8, from: .minXEdge).slice,
                        cornerRadius: radius, style: .continuous)
        let y = min(rect.maxY - radius - 4, rect.minY + 40)
        path.move(to: CGPoint(x: rect.maxX - 8, y: y - 8))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: y + 8))
        return path
    }
}

// MARK: day:stickers

/// The day as stickers (D62): each with its picture, time and title; a late one stands out (and wiggles, unless motion
/// is reduced); done ones fade with a tick. Drag one sideways to move it, a quarter hour per step.
struct DayStickers: View {
    var model: NowModel
    var edit: (Reminder) -> Void

    private enum Sticker: Identifiable {
        case done(Reminder), reminder(Reminder), event(CalendarEvent)
        var id: String {
            switch self {
            case .done(let r): "d" + r.id
            case .reminder(let r): "r" + r.id
            case .event(let e): "e" + e.id
            }
        }
        var at: Date {
            switch self {
            case .done(let r): r.lastFiredAt ?? r.fireAt
            case .reminder(let r): r.nextDue ?? r.fireAt
            case .event(let e): e.start
            }
        }
    }

    var body: some View {
        let today = model.groups().first { $0.day == .today }?.reminders ?? []
        let stickers = (model.doneToday.map(Sticker.done) + today.map(Sticker.reminder)
                        + model.events(on: .today).filter { !$0.allDay }.map(Sticker.event)).sorted { $0.at < $1.at }
        TitledCard(title: "Today", count: nil, emoji: "📅") {
            Text("drag a sticker to change its time").foregroundStyle(Theme.inkFaint)
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(stickers) { sticker($0) }
                Button { model.services.openAsk(prefill: "remind me ") } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus")
                        Text("add")
                    }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func sticker(_ s: Sticker) -> some View {
        switch s {
        case .done(let r):
            StickerCard(emoji: Self.emoji(r.title, fallback: "✅"), time: s.at, title: r.title, done: true, late: false)
        case .reminder(let r):
            StickerCard(emoji: Self.emoji(r.title, fallback: "⏰"), time: s.at, title: r.title, done: false, late: s.at < Date()) { minutes in
                Task { _ = await model.move(r, to: s.at.addingTimeInterval(minutes * 60)) }
            }
            .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
        case .event(let e):
            StickerCard(emoji: Self.emoji(e.title, fallback: "📅"), time: s.at, title: e.title, done: false, late: false)
        }
    }

    /// The first emoji in a title, else a picture for what it is.
    static func emoji(_ title: String, fallback: String) -> String {
        title.first { $0.unicodeScalars.first?.properties.isEmojiPresentation == true }.map(String.init) ?? fallback
    }
}

private struct StickerCard: View {
    var emoji: String
    var time: Date
    var title: String
    var done: Bool
    var late: Bool
    var move: ((Double) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: CGFloat = 0
    @State private var wiggle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: emoji).font(.system(size: 22))
                Spacer()
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }
            }
            Text(verbatim: TimeFormat.clock(time, calendar: .current)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(done ? Theme.inkFaint : Theme.ink)
                .strikethrough(done).lineLimit(2)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(late ? Theme.dangerSoft : Theme.accentSoft.opacity(done ? 0.4 : 0.8),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(late ? Theme.danger : .clear, lineWidth: 2))
        .overlay(alignment: .top) {
            if late {
                Text("late · \(TimeText.relative(time))", comment: "On a sticker whose time passed").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onDanger).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.danger, in: Capsule()).offset(y: -8)
            }
        }
        .opacity(done ? 0.7 : 1)
        .rotationEffect(.degrees(late && wiggle && !reduceMotion ? 2 : 0))
        .offset(x: drag)
        .gesture(DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in if move != nil { state = value.translation.width } }
            .onEnded { value in
                // A quarter hour for every 24 points.
                let steps = (value.translation.width / 24).rounded()
                if steps != 0 { move?(Double(steps) * 15) }
            })
        .onAppear {
            guard late, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.25).repeatCount(5, autoreverses: true).delay(0.6)) { wiggle = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(TimeFormat.clock(time, calendar: .current)) \(title)\(done ? ", " + String(localized: "done") : late ? ", " + String(localized: "late") : "")"))
    }
}

// MARK: watching:badges

/// Watches as round badges (D62): a picture or a value inside, a dot when something changed, a word under it.
struct WatchBadges: View {
    var model: NowModel

    var body: some View {
        TitledCard(title: "Watching", count: model.watchers.count + model.reports.count, emoji: "👀") {
            EmptyView()
        } content: {
            if model.watchers.isEmpty && model.reports.isEmpty {
                Button("Watch something…") { model.services.openAsk(prefill: "tell me when ") }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)], spacing: Theme.Space.m) {
                ForEach(model.watchers) { w in WatchBadge(watcher: w, model: model) }
                ForEach(model.reports) { r in
                    BadgeLabel(inside: { Text(verbatim: model.readings[r.id]?.value ?? "…").font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.5) },
                               title: model.readings[r.id]?.label ?? r.title, detail: Describe.watcherKind(r.kind).label, dot: false)
                }
            }
        }
    }
}

private struct WatchBadge: View {
    var watcher: Watcher
    var model: NowModel
    @State private var open = false

    var body: some View {
        let waiting = model.changeWaiting(for: watcher) != nil
        Button { open = true } label: {
            BadgeLabel(inside: { Image(systemName: Describe.watcherKind(watcher.kind).symbol).font(.system(size: 20)) },
                       title: watcher.title, detail: waiting ? String(localized: "changed \(TimeFormat.clock(watcher.lastPageChange?.at ?? Date(), calendar: .current))", comment: "When a watch last saw a change: “changed 17:37”")
                           : Describe.interval(watcher.intervalS),
                       dot: waiting)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { WatchTile(watcher: watcher, model: model).frame(width: 340).padding(Theme.Space.s) }
        .onChange(of: open) { _, isOpen in if isOpen { Task { await model.seen(watcher) } } }
    }
}

private struct BadgeLabel<Inside: View>: View {
    @ViewBuilder var inside: Inside
    var title: String
    var detail: String
    var dot: Bool

    var body: some View {
        VStack(spacing: 4) {
            inside
                .foregroundStyle(Theme.link)
                .frame(width: 62, height: 62)
                .background(Theme.accentSoft, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if dot { Circle().fill(Theme.danger).frame(width: 12, height: 12).overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 2)) }
                }
            Text(verbatim: title).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(1)
            Text(verbatim: detail).font(.system(size: 10.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: agents:helpers

/// Agents as helpers at work (D62): who, where, and a word for whether they need you.
struct HelpersCard: View {
    var model: NowModel

    var body: some View {
        let sessions = model.sessionsNeedingYou + model.workingSessions
        TitledCard(title: "Helpers at work", count: sessions.count + model.jobs.count, emoji: "🤝") {
            EmptyView()
        } content: {
            if sessions.isEmpty && model.jobs.isEmpty {
                Button("Connect your agents…") { model.services.openSettings(tab: .agents) }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            ForEach(sessions) { s in
                Button { model.openSession(s) } label: {
                    ListRowLabel(symbol: "sparkles", title: Describe.agentName(s.agent),
                                 detail: [s.projectName, s.detail].compactMap { $0 }.joined(separator: " · ")) {
                        Chip(verbatim: s.state == .needsYou ? String(localized: "needs you", comment: "A chip on an agent waiting for an answer")
                                                            : String(localized: "working", comment: "A chip on an agent at work"),
                             tone: s.state == .needsYou ? .danger : .success)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(model.jobs) { j in
                ListRowLabel(symbol: "terminal", title: j.title, detail: String(localized: "Running for \(TimeText.duration(Date().timeIntervalSince(j.startedAt)))")) {
                    Chip(verbatim: String(localized: "working", comment: "A chip on an agent at work"), tone: .success)
                }
            }
        }
    }
}

// MARK: notes:chips

/// What was jotted today, as chips (D62): each note with its collection; a click opens it.
struct JottedChips: View {
    var model: NowModel

    var body: some View {
        let today = model.recentNotes.filter { Calendar.current.isDateInToday($0.createdAt) }
        let notes = today.isEmpty ? model.recentNotes : today
        TitledCard(title: today.isEmpty ? "Jotted lately" : "Jotted today", count: notes.count, emoji: "📝") {
            EmptyView()
        } content: {
            if notes.isEmpty {
                Text("Nothing saved yet. Notes, tasks and links you keep show up here.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            FlowLayout(spacing: Theme.Space.xs) {
                ForEach(notes) { item in
                    Button { model.open(item) } label: {
                        HStack(spacing: 4) {
                            if let c = model.noteCollections[item.collectionId] { CollectionIcon(collection: c, size: 10) }
                            Text(verbatim: item.title.clipped(40)).foregroundStyle(Theme.ink)
                            if let c = model.noteCollections[item.collectionId] {
                                Text(verbatim: "· \(NotebookCollections.shownName(c))").foregroundStyle(Theme.inkMuted)
                            }
                        }
                        .font(Theme.Font.caption)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
                        .background(Theme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Lays chips out in lines, wrapping when a line is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let frames = place(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            frames.append(CGRect(x: x, y: y, width: min(size.width, width), height: size.height))
            x += size.width + spacing
            line = max(line, size.height)
        }
        return frames
    }
}
