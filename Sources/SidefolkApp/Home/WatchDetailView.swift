import SidefolkCore
import SwiftUI

/// A watch's own page in Home (D87), opened from On duty, Today's watch tiles and a changed-watch card: what it watches,
/// how often and who does it (Scout), Check now, Pause or Resume and Stop, the latest change line by line, and a
/// timeline of its checks. Everything here is kept on this Mac for 30 days and goes with the watch.
struct WatchDetailView: View {
    var home: HomeModel
    var model: WatchDetailModel
    @State private var confirmingStop = false
    @State private var showingAll = false

    var body: some View {
        HomePage {
            Button { home.selection = .onDuty } label: { Label("On duty", systemImage: "chevron.backward") }
                .buttonStyle(.sf(.quiet))
                .padding(.bottom, -Theme.Space.m)
            if let w = model.watcher {
                hero(w)
                if w.mode == .report { LiveValueLook(watcher: w, value: home.now.readings[w.id]?.value, services: home.services) { Task { await model.reload() } } }
                if hasText(w) { change(w) }
                timeline(w)
            } else if model.loaded {
                EmptyState(title: Text("This watch is gone"),
                           message: Text("It was stopped, and its history went with it."),
                           systemImage: "binoculars", folk: "scout", actionTitle: Text("Back to On duty")) { home.selection = .onDuty }
                    .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(Text("Stop watching “\(model.watcher?.title ?? "")”?"), isPresented: $confirmingStop) {
            Button("Stop watching", role: .destructive) {
                Task {
                    await model.stop()
                    home.selection = .onDuty
                }
            }
        } message: {
            Text("Its checks and the text it kept are deleted with it.")
        }
    }

    // MARK: What it watches

    private func hero(_ w: Watcher) -> some View {
        let kind = Describe.watcherKind(w.kind)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                IconTile(symbol: kind.symbol, folk: "scout", size: 52)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(verbatim: w.title).font(Theme.Font.title1).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .homePageTitle()
                    if let target = Describe.watcherTarget(w), target != w.title {
                        // An address or a path reads left to right in every language.
                        Text(verbatim: "\u{2066}\(target)\u{2069}").font(Theme.Font.mono).foregroundStyle(Theme.inkMuted)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    facts(w, kind: kind).padding(.top, Theme.Space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                state(w)
            }
            if let error = w.lastError, w.state == .error || w.errorCount > 0 { trouble(error, stopped: w.state == .error) }
            ButtonRow(spacing: Theme.Space.s) {
                // One primary: Check now while it watches; Resume when it doesn't (a paused or stuck watch can't look).
                if w.state == .active {
                    Button { Task { await model.checkNow() } } label: { Label(WatchWordsUI.checkNow, systemImage: "arrow.clockwise") }
                        .buttonStyle(.sf(.primary, size: .regular, working: model.working == .check))
                    Button { Task { await model.pause() } } label: { Label("Pause", systemImage: "pause") }
                        .buttonStyle(.sf(.secondary, size: .regular, working: model.working == .pause))
                } else {
                    Button { Task { await model.resume() } } label: { Label("Resume", systemImage: "play") }
                        .buttonStyle(.sf(.primary, size: .regular, working: model.working == .resume))
                }
                Button { confirmingStop = true } label: { Label("Stop watching", systemImage: "xmark") }
                    .buttonStyle(.sf(.destructive, size: .regular, working: model.working == .stop))
            }
        }
    }

    /// "Web page · every 30 min · Scout · since 1 Nov · stops 1 Dec · checked 2 min ago".
    private func facts(_ w: Watcher, kind: Describe.WatcherKind) -> some View {
        ButtonRow(spacing: Theme.Space.m) {
            fact(kind.symbol, Text(verbatim: kind.label))
            fact("clock", Text(verbatim: Describe.interval(w.intervalS).capitalizedFirst))
            HStack(spacing: Theme.Space.xs) {
                FolkAvatar(name: "scout", size: 18)
                Text("Scout watches it", comment: "A watch's page: the folk who does the watching")
            }
            fact("calendar", Text("Since \(TimeFormat.day(w.createdAt, now: Date(), calendar: .autoupdatingCurrent))", comment: "A watch's page: when it started"))
            if let end = w.expiresAt, w.state == .active {
                fact("hourglass", Text("Stops \(TimeFormat.moment(end, now: Date(), calendar: .autoupdatingCurrent))", comment: "“Stops 15:30”, “Stops Tomorrow 10:00”"))
            }
            if let checked = w.lastCheckedAt {
                fact("eye", Text("checked \(TimeText.relative(checked))", comment: "“checked 5 min ago”"))
            }
        }
        .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
    }

    private func fact(_ symbol: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: symbol).foregroundStyle(Theme.inkFaint) }.lineLimit(1)
    }

    @ViewBuilder private func state(_ w: Watcher) -> some View {
        let waiting = home.now.changeWaiting(for: w) != nil
        let tone = ChipTone(StatusTone.watch(w.state, changeWaiting: waiting))
        switch w.state {
        case .active where waiting: Chip("Changed", tone: tone)
        case .active: Chip(verbatim: String(localized: "watch.state.active", defaultValue: "Watching", comment: "Status chip on a watch that is running"), tone: tone)
        case .paused: Chip("Paused", tone: tone)
        case .error: Chip("Having trouble", tone: tone)
        case .triggered: Chip("Spotted", tone: tone)
        case .expired: Chip("Expired", tone: tone)
        }
    }

    /// Why it can't look: amber while it keeps trying, red only when it stopped (D78).
    private func trouble(_ error: String, stopped: Bool) -> some View {
        let tone: StatusTone = stopped ? .danger : .warning
        return Label { Text(verbatim: error).fixedSize(horizontal: false, vertical: true) }
            icon: { Image(systemName: stopped ? "exclamationmark.octagon" : "exclamationmark.triangle") }
            .font(Theme.Font.body).foregroundStyle(Theme.color(tone))
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.soft(tone), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    // MARK: What changed

    /// Page and file watches compare text, so they have a "what changed".
    private func hasText(_ w: Watcher) -> Bool { w.kind == WatchKind.urlChange || w.kind == WatchKind.fileChanges }

    private func change(_ w: Watcher) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("What changed"), detail: changeDetail) {
                if !model.rows.isEmpty {
                    SegmentedPicker(Text("Show the change"), selection: Binding(get: { model.sideBySide }, set: { model.sideBySide = $0 }),
                                    segments: [.init(false, Text("Inline", comment: "What changed: one column")),
                                               .init(true, Text("Side by side", comment: "What changed: before and after in two columns"))],
                                    small: true)
                        .fixedSize()
                }
            }
            SFCard {
                if model.lines.isEmpty {
                    InlineEmpty(text: emptyChange(w), systemImage: "text.magnifyingglass")
                } else if model.sideBySide, let change = model.change {
                    WatchChangeColumns(rows: model.rows,
                                       beforeTitle: Text("Before · \(TimeText.clock(change.before.at))", comment: "What changed: the older version and when it was read"),
                                       afterTitle: Text("After · \(TimeText.clock(change.after.at))", comment: "What changed: the newer version and when it was read"))
                } else {
                    WatchChangeLines(lines: model.lines)
                }
            }
            .environment(\.layoutDirection, model.textDirection)
        }
    }

    private var changeDetail: Text? {
        if let change = model.change {
            return Text("between \(TimeText.clock(change.before.at)) and \(TimeText.clock(change.after.at))", comment: "What changed: the two times compared")
        }
        if let page = model.watcher?.lastPageChange, !model.lines.isEmpty {
            return Text("at \(TimeText.short(page.at)), only the lines that changed", comment: "What changed, for a watch older than its history")
        }
        return nil
    }

    private func emptyChange(_ w: Watcher) -> LocalizedStringKey {
        if model.versions.count == 1 { return "Scout keeps what it read. The next change shows here, line by line." }
        if w.lastCheckedAt == nil { return "Not checked yet." }
        if w.kind == WatchKind.fileChanges { return "This file isn't plain text, so Scout compares its size and time only." }
        return "Scout keeps what it reads from now on. The next change shows here, line by line."
    }

    // MARK: Checks

    private func timeline(_ w: Watcher) -> some View {
        let shown = showingAll ? model.checks : Array(model.checks.prefix(WatchDetailModel.shownRuns))
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("Checks"), detail: Text("kept for \(WatchHistoryLimits.keepDays) days, only on this Mac", comment: "A watch's checks: how long they're kept")) {
                EmptyView()
            }
            if w.mode == .report {
                InlineEmpty(text: "Live values aren't logged: they read every few seconds.", systemImage: "waveform.path.ecg")
            } else {
                RowsCard {
                    let ticks = WatchCheck.ticks(model.checks, count: 48)
                    HStack {
                        CheckTicks(ticks: ticks, slots: 48, tick: CGSize(width: 4, height: 20), gap: 2)
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.l)
                    if model.checks.isEmpty {
                        InlineEmpty(text: "Not checked yet. Scout looks soon, or press Check now.", systemImage: "binoculars")
                    }
                    ForEach(shown, id: \.id) { check in CheckRow(check: check) }
                    if model.checks.count > shown.count {
                        Button { showingAll = true } label: { Text("Show all \(model.checks.count)", comment: "A watch's timeline: show older checks") }
                            .buttonStyle(.sf(.quiet))
                            .padding(Theme.Space.s)
                    }
                }
            }
        }
    }
}
