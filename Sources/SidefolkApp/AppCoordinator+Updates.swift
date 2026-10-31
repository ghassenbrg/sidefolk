import SidefolkCore

/// Updates (D46, D70): the menu bar's "Check for Updates…" (or "Update to …" once a version waits), Settings'
/// section, the first look a minute after launch, and the gallery's add-ons keeping up by themselves.
extension AppCoordinator {
    var updates: UpdateModel { updater.model }

    func startUpdates() {
        statusItem.waitingUpdate = { [weak self] in self?.updater.waitingVersion }
        statusItem.onUpdates = { [weak self] in self?.updater.showUpdates() }
        updater.signals = { [weak self] in await self?.installSignals() ?? InstallMoment.Signals(conversation: true) }
        addonUpdater.onUpdated = { [weak self] report in self?.companionsUpdated(report.companions.map(\.companion)) }
        addonUpdater.openReview = { [weak self] folder in self?.settingsWindow.review(folder: folder) }
        addonUpdater.openSettings = { [weak self] in self?.openSettings(tab: .general) }
        updater.onCheckNow = { [weak self] in self?.addonUpdater.checkNow() }
        Task {
            await updater.start()
            await addonUpdater.start()
        }
    }

    func companionsUpdated(_ names: [String]) {
        CompanionArt.forgetPictures()
        // The companion on the desktop, if it was one of them, reloads in place (D55).
        if !names.isEmpty { companion.reload3D(names) }
        settingsChanged()
    }

    /// What an automatic update weighs before restarting Sidefolk (D70): anything the person would lose or have to
    /// start again, and how long since they last touched the Mac.
    func installSignals() async -> InstallMoment.Signals {
        let approvals = await runtime.broker.pending()
        let jobs = (try? await runtime.jobs.running()) ?? []
        return InstallMoment.Signals(conversation: currentRun != nil || ask.busy || onboarding.isRunning,
                                     approval: !approvals.isEmpty, voice: voice.isActive, asking: askPanel.isVisible,
                                     work: !jobs.isEmpty, secondsSinceInput: EnvironmentMonitor.secondsSinceInput)
    }
}
