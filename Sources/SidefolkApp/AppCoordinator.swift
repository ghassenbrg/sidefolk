import AppKit
import KeyboardShortcuts
import SidefolkCharacter
import SidefolkCore

extension KeyboardShortcuts.Name {
    /// ⌘⇧Space by default (DECISIONS D11).
    static let ask = Self("ask", default: .init(.space, modifiers: [.command, .shift]))
}

/// Owns the windows and routes events between the core runtime and the UI.
final class AppCoordinator {
    let runtime: SidefolkRuntime
    let ask = AskModel()
    private(set) var askPanel: AskPanelController!
    let bubbles = BubbleController()
    let statusItem = StatusItemController()
    let notifier: SystemNotifier
    let monitor: EnvironmentMonitor
    let companion = CompanionWindowController()
    private(set) var onboarding: Onboarding!
    private var mood = CompanionMood()
    private var roster = DutyRoster()
    private var backlog = 0
    private var rosterTask: Task<Void, Never>?
    private var moodTimer: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    init(runtime: SidefolkRuntime) {
        self.runtime = runtime
        notifier = SystemNotifier(attention: runtime.attention)
        monitor = EnvironmentMonitor(attention: runtime.attention)
    }

    func start() async {
        let s = runtime.settings.current
        askPanel = AskPanelController(model: ask, companionName: s.companionName, hotkey: hotkeyLabel)
        ask.actions = self
        askPanel.onVisibilityChange = { [weak self] visible in
            self?.mood.panelOpen = visible
            if !visible { self?.companion.keepRaised(false) }
            self?.renderMood()
        }

        onboarding = Onboarding(coordinator: self)
        companion.delegate = self
        applyCompanionSettings()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyCompanionSettings() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.companion.restorePosition() }
        }

        bubbles.anchorProvider = { [weak self] in self?.anchor() }
        bubbles.onRespond = { [weak self] item, action in self?.respond(to: item, action: action) }

        let template = CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: 2)
        statusItem.install(image: NSImage(cgImage: template, size: NSSize(width: 18, height: 18)))
        statusItem.onAsk = { [weak self] in self?.toggleAsk() }
        statusItem.onOpenHome = { [weak self] in self?.openHome() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onQuiet = { [weak self] seconds in self?.setQuiet(for: seconds) }
        statusItem.isQuiet = { [weak self] in self?.runtime.settings.current.isQuiet(at: Date()) ?? false }
        statusItem.hotkeyLabel = { [weak self] in self?.hotkeyLabel ?? "" }

        KeyboardShortcuts.onKeyUp(for: .ask) { [weak self] in self?.toggleAsk() }

        notifier.configure()
        monitor.onAwayChanged = { [weak self] away in self?.setAsleep(away) }
        monitor.start()
        await notifier.clearFallback()
        await runtime.attention.update { env in
            env.quiet = s.isQuiet(at: Date())
            env.presence = s.presence
            env.sounds = s.sounds
        }

        eventTask = Task { [weak self] in
            guard let stream = self?.runtime.events.stream() else { return }
            for await event in stream { self?.handle(event) }
        }
        await runtime.housekeeping()
        refreshRoster()
        if !runtime.settings.current.onboardingDone {
            try? await Task.sleep(for: .seconds(1))
            onboarding.start()
        }
        Log.shared.info("app", "ready")
    }

    // MARK: Companion

    func applyCompanionSettings() {
        let s = runtime.settings.current
        companion.eyesFollowPointer = s.eyesFollowPointer
        companion.apply(size: s.size, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        companion.show(presence: s.presence)
        companion.setFolks(roster.onDuty, visible: s.showFolks)
        askPanel?.update(companionName: s.companionName, hotkey: hotkeyLabel)
        renderMood()
    }

    private func setAsleep(_ asleep: Bool) {
        guard runtime.settings.current.sleepWhenIdle || !asleep else { return }
        let wasAsleep = mood.asleep
        mood.asleep = asleep
        renderMood()
        if wasAsleep && !asleep { companion.character.play(.wave) }
    }

    /// Which folks are on duty and which badges show, from live data.
    func refreshRoster() {
        rosterTask?.cancel()
        rosterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            let soon = Date().addingTimeInterval(15 * 60)
            let reminders = (try? await runtime.reminderStore.pending()) ?? []
            let watchers = (try? await runtime.watcherStore.active()) ?? []
            let jobs = (try? await runtime.jobs.running()) ?? []
            let sessions = (try? await runtime.sessions.live()) ?? []
            let working = sessions.filter { $0.state == .working }.count
            roster = DutyRoster(reminderDueSoon: reminders.contains { ($0.nextDue ?? .distantFuture) <= soon },
                                activeWatchers: watchers.count, liveAgentWork: jobs.count + working)
            companion.setFolks(roster.onDuty, visible: runtime.settings.current.showFolks)
            companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0, waiting: backlog)
        }
    }

    /// Shows a bubble that doesn't go through the attention center (onboarding).
    func presentLocal(_ item: AttentionItem) {
        companion.stepForward()
        bubbles.present(item, .attention(expandFor: 600))
    }

    func prepareForQuit() {
        eventTask?.cancel()
    }

    // MARK: Windows

    var hotkeyLabel: String {
        KeyboardShortcuts.getShortcut(for: .ask)?.description ?? "⌘⇧Space"
    }

    /// The companion's frame and screen, which panels and bubbles attach to. In menu-bar-only mode
    /// they attach under the menu bar icon's area instead.
    func anchor() -> (NSRect, NSScreen)? {
        if companion.isVisible { return (companion.characterFrameOnScreen, companion.screen) }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let v = screen.visibleFrame
        return (NSRect(x: v.maxX - 120, y: v.maxY - 90, width: 80, height: 80), screen)
    }

    func toggleAsk() {
        if askPanel.isVisible { askPanel.hide(); return }
        showAsk()
    }

    func showAsk(prefill: String? = nil) {
        if let prefill { ask.text = prefill }
        companion.keepRaised(true)
        guard let (frame, screen) = anchor() else { return }
        askPanel.show(beside: frame, on: screen)
    }

    func openHome() {}

    func openSettings() {}

    func setQuiet(for seconds: TimeInterval?) {
        let until = seconds.map { Date().addingTimeInterval($0) }
        Task {
            await runtime.settings.update { $0.quietUntil = until }
            await runtime.attention.update { $0.quiet = until != nil }
        }
    }

    // MARK: Events

    private func handle(_ event: AppEvent) {
        mood.apply(event, now: Date())
        renderMood()
        switch event {
        case .attention(.present(let item, let presentation)):
            present(item, presentation)
        case .attention(.withdraw(let id)):
            bubbles.withdraw(id: id)
            notifier.withdraw(id: id)
        case .attention(.backlog(let count)):
            backlog = count
            bubbles.setBacklog(count)
            statusItem.setBadge(count)
            companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0, waiting: count)
        case .approvalRequested(let request):
            ask.add(.approval(request))
            if !askPanel.isVisible { showAsk() }
        case .approvalResolved(let id, _):
            ask.removeApproval(id: id)
        case .dataChanged(let domain):
            statusItem.refreshNow()
            if [.reminders, .watchers, .runs, .attention].contains(domain) { refreshRoster() }
            if domain == .reminders { onboarding.reminderCreated() }
            if domain == .settings { applyCompanionSettings() }
        default:
            break
        }
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        switch presentation {
        case .ambient:
            break
        case .gentle:
            bubbles.present(item, presentation)
        case .attention:
            companion.stepForward()
            bubbles.present(item, presentation)
        case .system(let sound, let alsoOnDesktop):
            notifier.show(item, sound: sound && runtime.settings.current.sounds)
            if alsoOnDesktop, companion.isVisible {
                companion.stepForward()
                bubbles.present(item, .attention(expandFor: AttentionPolicy.expandSeconds))
            }
        }
    }

    private func respond(to item: AttentionItem, action: String?) {
        if item.source == Onboarding.source {
            onboarding.respond(action: action)
            return
        }
        if action == "open", item.source == "summary" { openHome() }
        Task { await runtime.attention.respond(id: item.id, actionId: action) }
    }

    private func renderMood() {
        companion.render(mood.pose(at: Date()))
        moodTimer?.cancel()
        if let next = mood.nextChange(after: Date()) {
            moodTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.renderMood()
            }
        }
    }
}

extension AppCoordinator: AskActions {
    func hint(for text: String) -> String? { nil }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel) {
        model.add(.needsBrain, caption: text)
    }

    func stop() {}

    func undo(activityId: String, in model: AskModel) {
        Task {
            do {
                if let label = try await runtime.executor.undo.undo(activityId) {
                    model.add(.info("Undone: \(label)."))
                } else {
                    model.add(.info("That can't be undone anymore."))
                }
            } catch {
                model.add(.error(UserFacingError("I couldn't undo that.", detail: String(describing: error)), retryable: false))
            }
        }
    }

    func answer(approval: ApprovalRequest, decision: ApprovalDecision) {
        ask.removeApproval(id: approval.id)
        Task { await runtime.broker.resolve(id: approval.id, decision: decision) }
    }

    func open(card: ResultCard) {
        if let url = card.url, let u = URL(string: url), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(u)
            return
        }
        openHome()
    }

    func saveAnswer(_ text: String, in model: AskModel) {}

    func openSettingsAI() { openSettings() }
}

extension AppCoordinator: CompanionDelegate {
    func companionClicked() { toggleAsk() }

    func companionDoubleClicked() {
        askPanel.hide()
        openHome()
    }

    func companionMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: @escaping () -> Void) {
            menu.addItem(ClosureTarget.item(title, action))
        }
        item("Ask…") { [weak self] in self?.showAsk() }
        item("Open Sidefolk") { [weak self] in self?.openHome() }
        menu.addItem(.separator())
        if runtime.settings.current.isQuiet(at: Date()) {
            item("Turn Quiet Off") { [weak self] in self?.setQuiet(for: nil) }
        } else {
            item("Quiet for 1 Hour") { [weak self] in self?.setQuiet(for: 3600) }
        }
        item("Hide Companion") { [weak self] in self?.showCompanion(false) }
        menu.addItem(.separator())
        item("Settings…") { [weak self] in self?.openSettings() }
        return menu
    }

    func companionDragChanged(_ dragging: Bool) {
        mood.dragging = dragging
        if dragging { askPanel.hide() }
        renderMood()
    }

    func companionMoved() {
        bubbles.reposition()
    }

    func companionReceived(_ drop: Attachment) {
        var attachment = drop
        if case .file(let url) = drop.kind {
            attachment.text = "Dropped file: \(url.path)"
        }
        ask.attachment = attachment
        showAsk()
    }

    func companionFolkClicked(_ folk: DutyFolk) { openHome() }

    func showCompanion(_ visible: Bool) {
        if visible {
            companion.show(presence: runtime.settings.current.presence == .menuBarOnly ? .always : runtime.settings.current.presence)
        } else {
            companion.hide()
            askPanel.hide()
        }
        statusItem.companionVisible = { [weak self] in self?.companion.isVisible ?? false }
    }
}

/// Menu items that run a closure (the target is kept alive by the item).
final class ClosureTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }

    static func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let target = ClosureTarget(handler)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }
}
