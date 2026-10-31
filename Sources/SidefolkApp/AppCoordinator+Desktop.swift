import AppKit
import SidefolkCore

/// The desktop of D84: the Sidecard above the companion, the light at its feet and the mark on its shoulder, the pins
/// and the agents lane, wired to what really happens.
extension AppCoordinator {
    func installSidecard() {
        sidecard.anchorProvider = { [weak self] in self?.anchor() }
        sidecard.onRespond = { [weak self] item, action in self?.respond(to: item, action: action) }
        sidecard.onAutoDismiss = { [weak self] item in
            guard let self, item.source != Onboarding.source, item.source != Self.ownVoice else { return }
            Task { await self.runtime.attention.respond(id: item.id, actionId: nil) }
        }
        sidecard.waitingItems = { [weak self] in
            guard let self else { return [] }
            return await runtime.attention.open().filter { $0.level >= .attention }.sorted { $0.createdAt < $1.createdAt }
        }
        sidecard.onOpenStack = { [weak self] in self?.showAsk() }
        sidecard.onChange = { [weak self] in self?.renderLight() }
        sidecard.onFold = { [weak self] item in
            self?.mood.quietAlert(id: item.id)
            self?.renderMood()
        }
    }

    /// What waits on the person: open notices that need an answer, and approvals.
    var waitingCount: Int { backlog + mood.approvals.count }

    /// The light at the companion's feet and the mark on its shoulder, from the pose, what waits and quiet mode.
    func renderLight() {
        let settings = runtime.settings.current
        let now = Date()
        let quiet = settings.isQuiet(at: now)
        companion.setLight(DesktopLight.of(pose: mood.pose(at: now), waiting: waitingCount, cardOut: sidecard.cardOut, quiet: quiet))
        sidecard.setWaiting(waitingCount)
        ask.waiting = waitingCount
        // Quiet mode that ends by itself: the light comes back then, and the attention center hears it (its digest).
        quietEnd?.cancel()
        guard quiet, let until = settings.quietUntil, until < .distantFuture else { return }
        quietEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, until.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled, let self else { return }
            await runtime.attention.update { $0.quiet = false }
            renderLight()
        }
    }

    /// Undo on a whisper: through the same undo the Ask panel uses, said back in a whisper.
    func undoFromWhisper(_ activityId: String) {
        Task {
            let label = try? await runtime.executor.undo.undo(activityId)
            let title = label.flatMap { $0 }.map { String(localized: "Undone: \($0).") } ?? String(localized: "That can't be undone anymore.")
            sidecard.present(AttentionItem(level: .gentle, source: Self.ownVoice, title: title, refKind: "undone"),
                             .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
        }
    }

    /// Keeps a live value's recent numbers for its pin's small line: the first number in what it read ("23%",
    /// "↓ 1.2 MB/s"). Words with no number draw no line.
    func noteSpark(_ reading: WatchReading) {
        guard let match = reading.value.firstMatch(of: /-?\d+(?:[.,]\d+)?/),
              let number = Double(match.output.replacingOccurrences(of: ",", with: ".")) else { return }
        var values = sparks[reading.watcherId] ?? []
        values.append(number)
        sparks[reading.watcherId] = Array(values.suffix(Self.sparkLength))
    }

    /// About the last hour at a reading a minute, or the last few minutes of a fast one.
    static let sparkLength = 40
}

extension AppCoordinator {
    func companionReadoutClicked(_ id: String) { openHome() }

    /// A pin's own menu (b12): pause or resume it, stop it, or see it in Home. Through the executor, as the person.
    func companionReadoutMenu(_ id: String) -> NSMenu? {
        guard let watcher = reports.first(where: { $0.id == id }) else { return nil }
        let menu = NSMenu()
        let title = readings[id].map { "\($0.label) · \(Describe.interval(watcher.intervalS))" } ?? watcher.title
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let paused = watcher.state == .paused
        menu.addItem(ClosureTarget.item(paused ? String(localized: "Resume Updates") : String(localized: "Pause Updates")) { [weak self] in
            self?.runWatchTool(paused ? "watch.resume" : "watch.pause", id: id)
        })
        menu.addItem(ClosureTarget.item(String(localized: "Open Sidefolk")) { [weak self] in self?.openHome() })
        menu.addItem(.separator())
        menu.addItem(ClosureTarget.item(String(localized: "Stop Showing It", comment: "A live value's menu beside the companion: stop the report")) { [weak self] in
            self?.runWatchTool("watch.stop", id: id)
        })
        return menu
    }

    private func runWatchTool(_ name: String, id: String) {
        Task { _ = await runtime.executor.execute(name: name, input: ["id": .string(id)], caller: .user) }
    }

    func companionAgentClicked(_ id: String) {
        Task {
            guard let session = (try? await runtime.sessions.live())?.first(where: { $0.id == id }) else { return }
            openSession(session)
        }
    }

    func companionBadgeHovered(_ hovering: Bool) { sidecard.fanStack(hovering) }

    /// Clicking the count opens Ask on top of what waits, as clicking the companion does.
    func companionBadgeClicked() {
        sidecard.fanStack(false)
        showAsk()
    }
}
