import AppKit
import SidefolkCore

/// Reports on the desktop (D35): a pin beside the companion (D84) for each live value, the newest value in the menu
/// bar while the companion is away, and a notification only when one was asked for, or when the companion is away
/// and the value comes slower than once a minute, never in quiet mode (`WatchReading.notifies`). A value every few
/// seconds touches no database and no list. Only those set to show beside it take a place (D116); the rest run on.
extension AppCoordinator {
    /// A report read a new value.
    func showReading(_ reading: WatchReading) {
        readings[reading.watcherId] = reading
        noteSpark(reading)
        showMomentIfDue(reading)
        renderReadouts()
        if reading.notifies(companionVisible: companion.isVisible, quiet: runtime.settings.current.isQuiet(at: Date())) {
            notifier.showReport(reading)
            notifiedReports.insert(reading.watcherId)
        }
    }

    /// Watchers came, went, paused or resumed: ask the engine which reports are live, and what the parser may stop.
    func refreshReadouts() {
        readoutTask?.cancel()
        readoutTask = Task { [weak self] in
            guard let engine = self?.runtime.watchers else { return }
            let all = await engine.arranged()
            let live = all.filter { $0.mode == .report && ($0.state == .active || $0.state == .paused) }
            let latest = await engine.latestReadings()
            guard let self, !Task.isCancelled else { return }
            knownWatches = all.filter { $0.state != .triggered && $0.state != .expired }.map(WatchName.init)
            reports = live
            let ids = Set(live.map(\.id))
            readings = readings.filter { ids.contains($0.key) }
            sparks = sparks.filter { ids.contains($0.key) }
            // The engine's are as new as any here, and carry what was just set around a value.
            for r in latest { readings[r.watcherId] = r }
            for gone in notifiedReports.subtracting(ids) { notifier.withdrawReport(gone) }
            notifiedReports.formIntersection(ids)
            renderReadouts()
        }
    }

    func renderReadouts() {
        let beside = reports.filter { $0.display == .beside }
        let moment = reports.first { $0.id == momentId }
        let items = (beside + (moment.map { [$0] } ?? [])).map { w in
            Readout(id: w.id, label: readings[w.id]?.label ?? w.title, value: readings[w.id]?.value ?? "…", atRest: readings[w.id]?.atRest ?? "…",
                    symbol: Describe.watcherKind(w.kind).symbol, spark: sparks[w.id] ?? [], paused: w.state == .paused,
                    at: readings[w.id]?.at, interval: w.intervalS)
        }
        companion.setReadouts(items)
        // Away from the desktop, the newest value lives in the menu bar instead.
        let newest = beside.compactMap { readings[$0.id] }.max { $0.at < $1.at }
        statusItem.setReadout(companion.isVisible ? nil : newest.map { "\($0.label) \($0.value)" })
    }

    /// A value set to come and go stands beside the companion for a few seconds at its reading: a pin like the others,
    /// one at a time, kept nowhere, so it fills no History and takes no place in what waits. Focus and Quiet hold it.
    private func showMomentIfDue(_ reading: WatchReading) {
        guard reading.dueItsMoment(last: moments[reading.watcherId]), momentId == nil,
              runtime.settings.current.attentionMode(at: Date()) == .open else { return }
        moments[reading.watcherId] = reading.at
        momentId = reading.watcherId
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(WatchLimits.momentLength))
            self?.momentId = nil
            self?.renderReadouts()
        }
    }

    /// The live values that don't stand beside the companion, for its menu and the Pocket's (D116): each with what it
    /// last read. Empty when there are none, and the menus then say nothing.
    var unseenValues: [(id: String, line: String)] {
        reports.filter { $0.display != .beside }.map { w in
            let reading = readings[w.id]
            return (w.id, "\(reading?.label ?? w.title): \(reading?.value ?? "…")")
        }
    }

    /// "Running Quietly ›" in a menu, or nil. A click opens its page.
    func unseenValuesMenu() -> NSMenuItem? {
        let values = unseenValues
        guard !values.isEmpty else { return nil }
        let menu = NSMenu()
        for value in values {
            menu.addItem(ClosureTarget.item(value.line) { [weak self] in self?.home.showWatch(value.id) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureTarget.item(String(localized: "All Watchers…")) { [weak self] in self?.home.showWatchers() })
        let item = NSMenuItem(title: String(localized: "Running Quietly"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
