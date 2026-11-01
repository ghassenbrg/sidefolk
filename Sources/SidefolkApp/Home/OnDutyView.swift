import SidefolkCore
import SwiftUI

/// Home › On duty (D84): everything working for the person now, by the folk who does it: Scout's watches, Byte's agent
/// sessions, commands and extensions working in the background, Tempo's repeating reminders and routines, and live
/// values. Each with its state and Pause, Resume or Stop, through the same paths as everywhere (`NowModel`'s
/// `pause`, `resume`, `stop`, `cancel`; an extension's own switch). Paused things are listed, not counted.
struct OnDutyView: View {
    var model: HomeModel
    @State private var pausing = false

    private var now: NowModel { model.now }

    var body: some View {
        let duty = now.onDuty
        let background = model.pages.background
        let running = model.onDutyRunning
        HomePage {
            hero(duty, running: running, empty: duty.isEmpty && background.isEmpty)
            if duty.isEmpty && background.isEmpty {
                EmptyState(title: Text("Nothing is on duty"),
                           message: Text("When \(model.companionName) watches a page, repeats a reminder or follows an agent, it shows here with a way to pause or stop it."),
                           systemImage: Theme.Symbol.say, folk: "scout",
                           actionTitle: Text("Watch something…")) { model.services.openAsk(prefill: "tell me when ") }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.xxl)
            } else {
                ColumnsLayout(widths: [1, 1], spacing: Theme.Size.columnGap, minimums: [320, 320]) {
                    VStack(alignment: .leading, spacing: Theme.Size.columnGap) {
                        if !duty.watches.isEmpty { scout(duty) }
                        if !duty.repeating.isEmpty { tempo(duty) }
                    }
                    VStack(alignment: .leading, spacing: Theme.Size.columnGap) {
                        if !duty.sessions.isEmpty || !duty.jobs.isEmpty || !background.isEmpty { byte(duty, background: background) }
                        if !duty.reports.isEmpty { liveValues(duty) }
                    }
                }
                Label("Click a folk beside \(model.companionName) on your desktop to come here.", systemImage: "info.circle")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    // MARK: The hero

    private func hero(_ duty: OnDuty, running: Int, empty: Bool) -> some View {
        WrapRow(minimum: 380, spacing: Theme.Space.l, alignment: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Group {
                    switch running {
                    case 0: Text("Nothing is working right now", comment: "On duty's title")
                    case 1: Text("One thing is working for you", comment: "On duty's title")
                    default: Text("\(running) things are working for you", comment: "On duty's title")
                    }
                }
                .font(Theme.Font.title1).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text(verbatim: summary(duty)).font(.system(size: 15 * ThemeStore.shared.style.tokens.type.scale)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Space.s) {
                if !duty.pausable.isEmpty {
                    Button { pauseAll(duty) } label: { Label("Pause all", systemImage: "pause") }
                        .buttonStyle(.sf(.secondary, size: .large, working: pausing))
                        .help(Text("Pauses every watch and live value; reminders, agents and extensions go on."))
                }
                // Empty, the page's one primary is the empty state's own.
                if !empty {
                    Button { model.services.openAsk(prefill: "tell me when ") } label: { Label("Watch something", systemImage: "plus") }
                        .buttonStyle(.sf(.primary, size: .large))
                }
            }
            .fixedSize()
        }
    }

    /// "Scout watches 3, Byte follows 2 agents, Tempo repeats a reminder, and 2 live values are pinned."
    private func summary(_ duty: OnDuty) -> String {
        var parts: [String] = []
        // The same counts as the title (`OnDuty.running`): what's paused is listed below, not counted.
        if duty.runningWatches > 0 { parts.append(String(localized: "Scout watches \(duty.runningWatches)", comment: "On duty's line: how many watches")) }
        let agents = duty.sessions.count + duty.jobs.count + model.pages.backgroundCount
        if agents > 0 { parts.append(String(localized: "Byte follows \(agents)", comment: "On duty's line: agent sessions, commands and extensions working")) }
        if !duty.repeating.isEmpty { parts.append(String(localized: "Tempo repeats \(duty.repeating.count)", comment: "On duty's line: repeating reminders and routines")) }
        if duty.runningReports > 0 { parts.append(String(localized: "\(duty.runningReports) live values", comment: "On duty's line: values told every few seconds or minutes")) }
        guard !parts.isEmpty else {
            return String(localized: "Ask \(model.companionName) to watch a page, a site or a file, repeat a reminder, or follow an agent.")
        }
        return parts.formatted(.list(type: .and)) + "."
    }

    private func pauseAll(_ duty: OnDuty) {
        pausing = true
        Task {
            for w in duty.pausable { await model.services.pauseWatcher(w.id) }
            await now.reload()
            pausing = false
        }
    }

    // MARK: The folks' cards

    private func scout(_ duty: OnDuty) -> some View {
        FolkCard(folk: "scout", title: Text(verbatim: "Scout"), role: Text("Watching pages, sites and files"), count: duty.runningWatches) {
            ForEach(duty.watches) { w in WatchDutyRow(watcher: w, model: now) }
        }
    }

    private func tempo(_ duty: OnDuty) -> some View {
        FolkCard(folk: "tempo", title: Text(verbatim: "Tempo"), role: Text("Repeating reminders and routines"), count: duty.repeating.count) {
            ForEach(duty.repeating) { r in
                ListRow(title: Text(verbatim: r.title), meta: Text(verbatim: meta(r))) {
                    rowIcon(r.action?.kind == .prompt ? "sparkles" : "repeat")
                } trailing: {
                    Chip(text: Text("Next at \(TimeFormat.clock(r.nextDue ?? r.fireAt, calendar: .current))", comment: "A repeating reminder's next time"),
                         tone: .neutral)
                } actions: {
                    Button("Stop") { Task { await now.cancel(r) } }
                }
                .contextMenu { Button("Stop repeating", role: .destructive) { Task { await now.cancel(r) } } }
            }
        }
    }

    private func meta(_ r: Reminder) -> String {
        var parts: [String] = []
        if let recurrence = r.recurrence { parts.append(Describe.recurrence(recurrence)) }
        if r.action?.kind == .prompt { parts.append(String(localized: "a routine: \(model.companionName) runs it", comment: "On duty: a reminder that runs a prompt")) }
        return parts.joined(separator: " · ")
    }

    private func byte(_ duty: OnDuty, background: [ExtensionPageInfo]) -> some View {
        FolkCard(folk: "byte", title: Text(verbatim: "Byte"), role: Text("Agents and add-ons at work"),
                 count: duty.sessions.count + duty.jobs.count + background.count) {
            ForEach(duty.sessions) { s in
                ListRow(title: Text(verbatim: Describe.session(s)), meta: Text(verbatim: sessionMeta(s))) {
                    rowIcon("terminal")
                } trailing: {
                    if s.state == .needsYou {
                        StatusBadge(Text("needs you", comment: "An agent session waits on the person"), state: .tone(.warning))
                    } else {
                        StatusBadge(Text("working", comment: "An agent session is running"), state: .live)
                    }
                } actions: {
                    Button("Open session") { now.openSession(s) }
                }
            }
            ForEach(duty.jobs) { j in
                ListRow(title: Text(verbatim: j.title), meta: Text(verbatim: j.command ?? "")) {
                    rowIcon("terminal")
                } trailing: {
                    StatusBadge(Text("running for \(TimeText.span(Date().timeIntervalSince(j.startedAt)))", comment: "A command Sidefolk follows"), state: .live)
                }
            }
            ForEach(background) { p in
                ListRow(title: Text(verbatim: p.title), meta: model.pages.summaries[p.id].map { Text(verbatim: $0.detail.isEmpty ? $0.title : $0.detail) }) {
                    PageSquircle(info: p, size: Theme.Size.rowIcon)
                } trailing: {
                    if let control = model.pages.summaries[p.id]?.control { QuickControl(info: p, control: control, pages: model.pages, small: true) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selection = .page(p.id) }
            }
        }
    }

    private func sessionMeta(_ s: AgentSession) -> String {
        var parts = [TimeText.span(Date().timeIntervalSince(s.startedAt))]
        if let call = now.lastCalls[s.agent] { parts.append(String(localized: "last: \(call.summary)", comment: "An agent's last call to Sidefolk")) }
        if s.state == .needsYou, let detail = s.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private func liveValues(_ duty: OnDuty) -> some View {
        FolkCard(folk: nil, title: Text("Live values"), role: Text("Read every few seconds or minutes, beside \(model.companionName)"),
                 count: duty.runningReports) {
            ForEach(duty.reports) { r in
                let reading = now.readings[r.id]
                ListRow(title: Text(verbatim: reading?.label ?? r.title), meta: Text(verbatim: Describe.reportSchedule(r))) {
                    rowIcon(Describe.watcherKind(r.kind).symbol)
                } trailing: {
                    HStack(spacing: Theme.Space.m) {
                        if let values = now.values[r.id], values.count > 1 {
                            Sparkline(values: values, color: Theme.glow).frame(width: 72, height: 20)
                        }
                        Text(verbatim: reading?.value ?? "…").font(Theme.Font.title2.monospacedDigit())
                            .foregroundStyle(r.state == .paused ? Theme.inkFaint : Theme.ink)
                    }
                } actions: {
                    if r.state == .paused {
                        Button("Resume") { Task { await now.resume(r) } }
                    } else {
                        Button("Pause") { Task { await now.pause(r) } }
                    }
                    Button("Stop") { Task { await now.stop(r) } }
                }
            }
        }
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkMuted)
            .frame(width: Theme.Size.rowIcon + 4, height: Theme.Size.rowIcon + 4)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.xs + 1, style: .continuous))
    }
}

/// A folk's card on On duty: its avatar (on duty, with its ring of light), name, what it does and how many, then its rows.
struct FolkCard<Rows: View>: View {
    var folk: String?
    var title: Text
    var role: Text
    var count: Int
    @ViewBuilder var rows: Rows

    var body: some View {
        RowsCard {
            HStack(spacing: Theme.Space.m) {
                if let folk {
                    FolkAvatar(name: folk, size: Theme.Size.avatarLarge - 6, live: true)
                } else {
                    Image(systemName: "pin").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.link)
                        .frame(width: Theme.Size.avatarLarge - 6, height: Theme.Size.avatarLarge - 6)
                        .background(Theme.accentSoft, in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    title.font(Theme.Font.title2).foregroundStyle(Theme.ink)
                    role.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                CountBadge(count: count, waiting: false)
            }
            .padding(Theme.Space.l)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            rows
        }
    }
}

/// A watch on On duty: what it watches, how often, a bar of its last checks (D87), its state as a chip when it says more
/// than "watching", and Pause, Resume or Stop; a click opens the watch's own page.
private struct WatchDutyRow: View {
    var watcher: Watcher
    var model: NowModel

    var body: some View {
        let kind = Describe.watcherKind(watcher.kind)
        Button { model.openWatch?(watcher.id) } label: {
            ListRow(title: Text(verbatim: Describe.watcherTarget(watcher) ?? watcher.title), meta: Text(verbatim: meta)) {
                Image(systemName: kind.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkMuted)
                    .frame(width: Theme.Size.rowIcon + 4, height: Theme.Size.rowIcon + 4)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.xs + 1, style: .continuous))
            } trailing: {
                HStack(spacing: Theme.Space.s) {
                    CheckTicks(ticks: model.ticks[watcher.id] ?? [], slots: NowModel.ticks, tick: CGSize(width: 2, height: 14))
                    // The state is said whole; the title wraps first.
                    chip.fixedSize()
                    RowChevron()
                }
            } actions: {
                if watcher.state == .paused {
                    Button("Resume") { Task { await model.resume(watcher) } }
                } else {
                    Button("Pause") { Task { await model.pause(watcher) } }
                }
                Button("Stop") { Task { await model.stop(watcher) } }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows the watch"))
    }

    private var meta: String {
        var parts = [Describe.interval(watcher.intervalS).capitalizedFirst]
        if watcher.state == .error, watcher.errorCount > 0 {
            parts.append(String(localized: "\(watcher.errorCount) checks failed", comment: "A watch having trouble"))
        } else if watcher.state == .paused {
            parts.append(String(localized: "paused", comment: "A watch the person paused"))
        } else if let checked = watcher.lastCheckedAt {
            parts.append(String(localized: "checked \(TimeText.relative(checked))", comment: "“checked 5 min ago”"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var chip: some View {
        let waiting = model.changeWaiting(for: watcher)
        switch watcher.state {
        case .error: Chip("Having trouble", tone: .danger)
        case .paused: Chip("Paused", tone: .neutral)
        case _ where waiting != nil:
            Chip(text: Text("Changed \(TimeFormat.clock(waiting?.createdAt ?? Date(), calendar: .current))", comment: "A watch noticed a change at a time"),
                 // The same tone as Today's tile and every watch: a change is news (D78), not something waiting on you.
                 tone: ChipTone(StatusTone.watch(watcher.state, changeWaiting: true)))
        // Watching is what the bar beside it already says.
        default: EmptyView()
        }
    }
}

/// On duty at a glance on Today (A1): watches and live values as tiles, then the agents at work, with the way in.
struct OnDutyGlance: View {
    var model: HomeModel

    private var now: NowModel { model.now }

    var body: some View {
        let duty = now.onDuty
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("On duty"), count: model.onDutyRunning) {
                Button { model.selection = .onDuty } label: { Label("Open", systemImage: "chevron.forward").labelStyle(.titleAndIcon) }
                    .buttonStyle(.sf(.quiet))
            }
            let tiles = duty.watches.count + duty.reports.count
            if tiles == 0 && duty.sessions.isEmpty && duty.jobs.isEmpty {
                RowsCard {
                    InlineEmpty(text: "Not watching anything. I can tell you when a page changes, a site goes down or a file arrives.",
                                systemImage: "binoculars", actionTitle: "Watch something…") {
                        model.services.openAsk(prefill: "tell me when ")
                    }
                }
            }
            if tiles > 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                          spacing: Theme.Space.m) {
                    ForEach(duty.watches.prefix(4)) { w in WatchCard(watcher: w, model: now) }
                    ForEach(duty.reports.prefix(max(0, 4 - duty.watches.count))) { r in
                        ReportCard(report: r, reading: now.readings[r.id], values: now.values[r.id] ?? [], model: now)
                    }
                }
                if tiles > 4 {
                    Button { model.selection = .onDuty } label: { Text("\(tiles - 4) more on duty", comment: "Today: more watches than its tiles show") }
                        .buttonStyle(.sf(.quiet))
                }
            }
            if !duty.sessions.isEmpty || !duty.jobs.isEmpty {
                Text("Agents at work").font(Theme.Font.headline).foregroundStyle(Theme.ink).padding(.top, Theme.Space.xs)
                RowsCard {
                    ForEach(duty.sessions) { s in
                        ListRow(title: Text(verbatim: Describe.session(s)),
                                meta: Text(verbatim: [TimeText.span(Date().timeIntervalSince(s.startedAt)),
                                                      now.lastCalls[s.agent].map { String(localized: "last: \($0.summary)", comment: "An agent's last call to Sidefolk") }]
                                    .compactMap { $0 }.joined(separator: " · "))) {
                            FolkAvatar(name: "byte", size: Theme.Size.avatar, live: s.state == .working)
                        } trailing: {
                            if s.state == .needsYou {
                                StatusBadge(Text("needs you", comment: "An agent session waits on the person"), state: .tone(.warning))
                            } else {
                                StatusBadge(Text("working", comment: "An agent session is running"), state: .live)
                            }
                        } actions: {
                            Button("Open session") { now.openSession(s) }
                        }
                    }
                    ForEach(duty.jobs) { j in
                        ListRow(title: Text(verbatim: j.title), meta: j.command.map { Text(verbatim: $0) }) {
                            FolkAvatar(name: "byte", size: Theme.Size.avatar, live: true)
                        } trailing: {
                            StatusBadge(Text("working", comment: "An agent session is running"), state: .live)
                        }
                    }
                }
            }
        }
    }
}

extension String {
    /// The first letter as a capital, for a phrase that starts a line ("every 5 min" → "Every 5 min").
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
