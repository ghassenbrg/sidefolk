import SidefolkCore

/// Updates (D46): the menu bar's "Check for Updates…" (or "Update to …" once a version waits), Settings' section,
/// and the first look a minute after launch.
extension AppCoordinator {
    var updates: UpdateModel { updater.model }

    func startUpdates() {
        statusItem.waitingUpdate = { [weak self] in self?.updater.waitingVersion }
        statusItem.onUpdates = { [weak self] in self?.updater.showUpdates() }
        Task { await updater.start() }
    }
}
