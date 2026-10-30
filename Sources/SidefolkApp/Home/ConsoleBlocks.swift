import SidefolkCore
import SwiftUI

// Today's pieces in the Console's styles (D62): dense, keyboard first, every step visible, exact words in mono.

/// A Console section's title: small capitals, a count, and a quiet note at the right.
struct ConsoleTitle: View {
    var title: Text
    var count: Int?
    var note: Text?

    init(title: LocalizedStringKey, count: Int?, note: Text?) {
        self.init(text: Text(title), count: count, note: note)
    }

    init(text: Text, count: Int?, note: Text?) {
        self.title = text
        self.count = count
        self.note = note
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            title.textCase(.uppercase).font(.system(size: 11, weight: .bold, design: .monospaced)).kerning(0.6)
                .foregroundStyle(Theme.inkMuted).accessibilityAddTraits(.isHeader)
            if let count {
                Text(count.formatted()).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.ink).padding(.horizontal, 5).background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: Theme.Space.s)
            note?.font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint).lineLimit(1)
        }
    }
}

// MARK: header:console

/// "Today · Fri 30 Oct, 17:58", and what to show: everything, agents, your own, or watches.
struct ConsoleHeader: View {
    @Bindable var model: NowModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text("Today").font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            TimelineView(.everyMinute) { context in
                Text(verbatim: "· " + context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Theme.Space.m)
            HStack(spacing: Theme.Space.xxs) {
                ForEach(NowModel.Focus.allCases) { focus in
                    Button { model.focus = focus } label: { Text(title(focus)) }
                        .buttonStyle(.plain)
                        .font(Theme.Font.captionStrong)
                        .foregroundStyle(model.focus == focus ? Theme.ink : Theme.inkMuted)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
                        .background(model.focus == focus ? Theme.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(model.focus == focus ? Theme.line : .clear))
                        .accessibilityAddTraits(model.focus == focus ? .isSelected : [])
                }
            }
        }
    }

    private func title(_ focus: NowModel.Focus) -> LocalizedStringKey {
        switch focus {
        case .all: "All"
        case .agents: "Agents"
        case .mine: "Mine"
        case .watches: "Watches"
        }
    }
}

// MARK: agents:steps

/// Every agent's steps, as they happen (D62): each session with where it is, then its last calls to Sidefolk with
/// their risk; then your companion's own.
struct AgentSteps: View {
    var model: NowModel

    var body: some View {
        let sessions = model.sessionsNeedingYou + model.workingSessions
        let companion = model.services.runtime.settings.current.companionName
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ConsoleTitle(title: "Agents", count: sessions.count + model.jobs.count, note: Text("sessions reach Sidefolk over MCP"))
            if sessions.isEmpty && model.jobs.isEmpty {
                Text("Nothing running. Connect Claude Code or Codex to see their sessions here, or start a command with “sidefolk run -- npm test”.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            ForEach(sessions) { s in
                StepsCard(title: Describe.agentName(s.agent),
                          detail: [s.projectName.map { "~/\($0)" }, s.detail.map { "“\($0.clipped(40))”" }, TimeText.duration(Date().timeIntervalSince(s.startedAt))]
                              .compactMap { $0 }.joined(separator: " · "),
                          state: s.state == .needsYou ? String(localized: "Waiting on you") : String(localized: "Running"),
                          urgent: s.state == .needsYou, steps: model.steps[s.agent] ?? []) { model.openSession(s) }
            }
            ForEach(model.jobs) { j in
                StepsCard(title: j.title, detail: j.command, state: String(localized: "Running"), urgent: false, steps: [], open: nil)
            }
            if let own = model.steps[""], !own.isEmpty {
                ConsoleTitle(text: Text(verbatim: companion), count: nil, note: Text("your own companion's work")).padding(.top, Theme.Space.s)
                StepsCard(title: nil, detail: nil, state: nil, urgent: false, steps: own, open: nil)
            }
        }
    }
}

private struct StepsCard: View {
    var title: String?
    var detail: String?
    var state: String?
    var urgent: Bool
    var steps: [ActivityEntry]
    var open: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        if let detail { Text(verbatim: detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                    }
                    Spacer(minLength: Theme.Space.xs)
                    if let state {
                        Text(verbatim: state).textCase(.uppercase).font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(urgent ? Theme.danger : Theme.success)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(urgent ? Theme.dangerSoft : Theme.successSoft, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(Theme.Space.m)
                .contentShape(Rectangle())
                .onTapGesture { open?() }
                if !steps.isEmpty { Divider() }
            }
            ForEach(steps, id: \.id) { step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(verbatim: TimeFormat.clock(step.at, calendar: .current)).foregroundStyle(Theme.inkFaint)
                    Image(systemName: mark(step).symbol).foregroundStyle(mark(step).color).imageScale(.small)
                    Text(verbatim: "\(step.tool.replacingOccurrences(of: ".", with: "_")) \(step.summary)")
                        .foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Theme.Space.xs)
                    RiskTag(risk: step.risk)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, Theme.Space.m).padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            if !steps.isEmpty { Spacer(minLength: Theme.Space.xs).frame(height: Theme.Space.xs) }
        }
        .cardSurface()
    }

    private func mark(_ step: ActivityEntry) -> (symbol: String, color: Color) {
        switch step.decision {
        case .denied, .blocked: ("xmark", Theme.danger)
        case .failed: ("exclamationmark.triangle", Theme.danger)
        case .skipped: ("forward", Theme.inkMuted)
        default: ("checkmark", Theme.success)
        }
    }
}

/// A risk in one short word, coloured: low, med, high.
struct RiskTag: View {
    var risk: String

    var body: some View {
        let tone: (Color, Color) = switch risk {
        case "high": (Theme.danger, Theme.dangerSoft)
        case "medium": (Theme.ink, Theme.surfaceSunken)
        default: (Theme.success, Theme.successSoft)
        }
        Text(verbatim: risk == "medium" ? String(localized: "risk.med", defaultValue: "med", comment: "Short for medium risk, in a narrow column") : risk == "high"
             ? String(localized: "risk.high", defaultValue: "high", comment: "High risk, in a narrow column") : String(localized: "risk.low", defaultValue: "low", comment: "Low risk, in a narrow column"))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tone.0)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tone.1, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: watching:signals

/// Watches and live values as signals (D62): how often each looks and what it saw, values with a line of the last few.
struct WatchSignals: View {
    var model: NowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ConsoleTitle(title: "Signals", count: model.watchers.count + model.reports.count, note: nil)
            VStack(alignment: .leading, spacing: 0) {
                if model.watchers.isEmpty && model.reports.isEmpty {
                    Button("Watch something…") { model.services.openAsk(prefill: "tell me when ") }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link).padding(Theme.Space.m)
                }
                ForEach(model.watchers) { w in
                    let waiting = model.changeWaiting(for: w) != nil
                    signal(title: Describe.watcherTarget(w) ?? w.title,
                           detail: [Describe.interval(w.intervalS), w.lastPageChange.map { String(localized: "changed \(TimeFormat.clock($0.at, calendar: .current))", comment: "When a watch last saw a change: “changed 17:37”") }]
                               .compactMap { $0 }.joined(separator: " · ")) {
                        if waiting {
                            Text(verbatim: "Δ 1").foregroundStyle(Theme.danger)
                        } else if w.state == .error {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                        } else if w.state == .paused {
                            Image(systemName: "pause").foregroundStyle(Theme.inkFaint)
                        } else {
                            Image(systemName: "checkmark").foregroundStyle(Theme.success)
                        }
                    } below: { EmptyView() }
                    Divider()
                }
                ForEach(model.reports) { r in
                    let values = model.values[r.id] ?? []
                    signal(title: model.readings[r.id]?.label ?? r.title, detail: Describe.watcherKind(r.kind).label) {
                        Text(verbatim: model.readings[r.id]?.value ?? "…").foregroundStyle(Theme.ink)
                    } below: {
                        if values.count > 1 { Sparkline(values: values).frame(height: 22).padding(.top, 2) }
                    }
                    Divider()
                }
            }
            .cardSurface()
        }
    }

    private func signal<T: View, B: View>(title: String, detail: String, @ViewBuilder trailing: () -> T, @ViewBuilder below: () -> B) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.xs)
                trailing().font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            below()
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}

// MARK: day:compact

/// What comes next, one line each (D62): the time, what, and a word when it's late, a calendar's, or someone else's.
struct DayCompact: View {
    var model: NowModel
    var edit: (Reminder) -> Void

    var body: some View {
        let rows = DayRow.merge(events: model.events(on: .today).filter { !$0.allDay },
                                reminders: model.groups().first { $0.day == .today }?.reminders ?? [])
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ConsoleTitle(title: "Next", count: rows.count, note: nil)
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing else today.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).padding(Theme.Space.m)
                }
                ForEach(rows) { row in
                    switch row {
                    case .event(let e):
                        line(e.start, e.title) { Image(systemName: "calendar").foregroundStyle(Theme.inkMuted) }
                    case .reminder(let r):
                        let due = r.nextDue ?? r.fireAt
                        line(due, r.title, late: due < Date()) {
                            if due < Date() {
                                Text("late").foregroundStyle(Theme.danger)
                            } else if let who = Describe.source(r.source) {
                                Text(verbatim: who).foregroundStyle(Theme.inkFaint)
                            }
                        }
                        .contextMenu { ReminderMenu(reminder: r, model: model, edit: edit) }
                    }
                    Divider()
                }
            }
            .cardSurface()
        }
    }

    private func line<T: View>(_ at: Date, _ title: String, late: Bool = false, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(verbatim: TimeFormat.clock(at, calendar: .current)).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(late ? Theme.danger : Theme.inkMuted)
            Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.xs)
            trailing().font(Theme.Font.caption)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
