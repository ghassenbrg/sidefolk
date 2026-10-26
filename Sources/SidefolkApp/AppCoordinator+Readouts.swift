import AppKit
import SidefolkCore

/// Reports on the desktop (D35): a pill beside the companion for each live value, the newest value in the menu
/// bar while the companion is away, and a notification only when one was asked for, or when the companion is away
/// and the value comes slower than once a minute, never in quiet mode (`WatchReading.notifies`). A value every few
/// seconds touches no database and no list.
extension AppCoordinator {
    /// A report read a new value.
    func showReading(_ reading: WatchReading) {
        readings[reading.watcherId] = reading
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
            let all = await engine.list()
            let live = all.filter { $0.mode == .report && ($0.state == .active || $0.state == .paused) }
            let latest = await engine.latestReadings()
            guard let self, !Task.isCancelled else { return }
            knownWatches = all.filter { $0.state != .triggered && $0.state != .expired }.map(WatchName.init)
            reports = live.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            let ids = Set(live.map(\.id))
            readings = readings.filter { ids.contains($0.key) }
            for r in latest where readings[r.watcherId] == nil { readings[r.watcherId] = r }
            for gone in notifiedReports.subtracting(ids) { notifier.withdrawReport(gone) }
            notifiedReports.formIntersection(ids)
            renderReadouts()
        }
    }

    func renderReadouts() {
        let items = reports.map { w in
            Readout(id: w.id, label: readings[w.id]?.label ?? w.title, value: readings[w.id]?.value ?? "…", paused: w.state == .paused)
        }
        companion.setReadouts(items)
        // Away from the desktop, the newest value lives in the menu bar instead.
        let newest = reports.compactMap { readings[$0.id] }.max { $0.at < $1.at }
        statusItem.setReadout(companion.isVisible ? nil : newest.map { "\($0.label) \($0.value)" })
    }
}
