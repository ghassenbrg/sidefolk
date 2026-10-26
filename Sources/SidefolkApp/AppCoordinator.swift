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
    private var nowRefreshTask: Task<Void, Never>?
    let secrets: any SecretStore = KeychainSecretStore()
    private(set) var agent: AgentRuntime!
    var currentRun: String?
    private(set) lazy var home = HomeWindowController(services: self)
    private(set) lazy var settingsWindow = SettingsWindowController(services: self)
    /// Collection names for the intent parser ("ideas for Sidefolk").
    var knownCollections: [String] = []
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

        agent = makeAgentRuntime()
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
        bubbles.onAutoDismiss = { [weak self] item in
            guard let self, item.source != Onboarding.source, item.source != Self.ownVoice else { return }
            Task { await self.runtime.attention.respond(id: item.id, actionId: nil) }
        }

        let menuBarImage = BrandAsset.menuBar.image ?? NSImage(
            cgImage: CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: 2),
            size: NSSize(width: 18, height: 18))
        statusItem.install(image: menuBarImage)
        statusItem.onAsk = { [weak self] in self?.toggleAsk() }
        statusItem.onOpenHome = { [weak self] in self?.openHome() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onQuiet = { [weak self] seconds in self?.setQuiet(for: seconds) }
        statusItem.isQuiet = { [weak self] in self?.runtime.settings.current.isQuiet(at: Date()) ?? false }
        statusItem.hotkeyLabel = { [weak self] in self?.hotkeyLabel ?? "" }
        statusItem.companionVisible = { [weak self] in self?.companion.isVisible ?? false }
        statusItem.onToggleCompanion = { [weak self] in
            guard let self else { return }
            self.showCompanion(!self.companion.isVisible)
        }
        statusItem.nowProvider = { [weak self] in await self?.nowEntries() ?? [] }

        KeyboardShortcuts.onKeyUp(for: .ask) { [weak self] in self?.toggleAsk() }

        notifier.configure()
        monitor.onAwayChanged = { [weak self] away in self?.setAsleep(away) }
        monitor.onWake = { [weak self] in
            guard let self else { return }
            Task { await self.runtime.rearm() }
        }
        monitor.onClockChange = monitor.onWake
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
        #if DEBUG
        DebugSnapshots.handler = { [weak self] command in self?.runDevCommand(command) }
        #endif
        await runtime.attention.onAction(kind: "brief") { [weak self] _, action in
            guard action == "open" else { return }
            await MainActor.run { self?.openHome() }
        }
        await runtime.attention.onAction(kind: "job") { [weak self] item, action in
            guard let id = item.refId, let job = try? await self?.runtime.jobs.job(id: id) else { return }
            await MainActor.run { Self.jobAction(action, job) }
        }
        await runtime.housekeeping()
        do {
            try await runtime.start()
        } catch BridgeError.alreadyRunning {
            AlreadyRunning.showAndQuit()
            return
        } catch {
            // Without the socket, agents can't reach Sidefolk; everything else still works.
            Log.shared.error("bridge", "local API failed to start", ["error": String(describing: error)])
        }
        installHelperLink()
        await refreshCollections()
        _ = await notificationsAuthorized()
        refreshRoster()
        statusItem.refreshNow()
        Log.shared.info("app", "ready")
        if !runtime.settings.current.onboardingDone {
            // A beat after launch, so the companion has landed before it speaks.
            try? await Task.sleep(for: .seconds(1))
            onboarding.start()
        }
    }

    // MARK: Companion

    func applyCompanionSettings() {
        let s = runtime.settings.current
        companion.eyesFollowPointer = s.eyesFollowPointer
        companion.apply(size: s.size, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        companion.apply(look: CompanionArt.look(for: s), name: s.companionName)
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
            introduceNewFolks(roster.onDuty)
        }
    }

    /// The first time a folk turns up, the companion says who it is: once, gently, never during onboarding.
    private func introduceNewFolks(_ folks: [DutyFolk]) {
        guard runtime.settings.current.showFolks, !onboarding.isRunning else { return }
        let key = "introducedFolks"
        var met = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard let folk = folks.first(where: { !met.contains($0.rawValue) }) else { return }
        met.insert(folk.rawValue)
        UserDefaults.standard.set(met.sorted(), forKey: key)
        let (title, body) = Self.introduction(folk)
        let item = AttentionItem(level: .gentle, source: Self.ownVoice, title: title, body: body, refKind: "intro")
        bubbles.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
    }

    static func introduction(_ folk: DutyFolk) -> (String, String) {
        switch folk {
        case .tempo: ("That's Tempo.", "Tempo turns up when a reminder is less than 15 minutes away.")
        case .scout: ("That's Scout.", "Scout stays out while I'm watching something for you.")
        case .byte: ("That's Byte.", "Byte keeps me company while an agent or a command is working.")
        }
    }

    /// Bubbles the companion says itself, outside the attention center (folk introductions).
    static let ownVoice = "companion"

    /// Shows a bubble that doesn't go through the attention center (onboarding).
    func presentLocal(_ item: AttentionItem) {
        companion.stepForward()
        bubbles.present(item, .attention(expandFor: 600))
    }

    /// Stops the engines and covers the next week of reminders with system notifications.
    func prepareForQuit() async {
        eventTask?.cancel()
        let fallback = await runtime.stop()
        notifier.scheduleFallback(fallback.map { (id: $0.id, title: $0.title, body: $0.body, date: $0.date) })
        Log.shared.info("app", "quit", ["fallbackReminders": String(fallback.count)])
    }

    /// The buttons on a failed `sidefolk run` notice.
    static func jobAction(_ action: String?, _ job: Job) {
        switch action {
        case "copy":
            guard let command = job.command else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case "open":
            // Shown in Finder, never "opened": a folder named Foo.app would launch.
            guard let cwd = job.cwd, FileManager.default.fileExists(atPath: cwd) else { return }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
        default:
            break
        }
    }

    /// Coalesces bursts of changes into one refresh of the menu bar list.
    func scheduleNowRefresh() {
        nowRefreshTask?.cancel()
        nowRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.statusItem.refreshNow()
        }
    }

    /// The menu bar's "Now" list: what needs you, what's due soon, what's running.
    func nowEntries() async -> [StatusItemController.NowEntry] {
        var entries: [StatusItemController.NowEntry] = []
        let now = Date()
        for s in ((try? await runtime.sessions.live()) ?? []) where s.state == .needsYou {
            entries.append(.init(title: "\(s.agent == "codex" ? "Codex" : "Claude") needs you", detail: s.projectName ?? "a session",
                                 symbol: "hand.raised", action: { [weak self] in self?.openSession(s) }))
        }
        let open = await runtime.attention.open().filter { $0.level >= .attention }
        if !open.isEmpty {
            entries.append(.init(title: "Needs you (\(open.count))", detail: open[0].title.clipped(30), symbol: "tray.full",
                                 action: { [weak self] in self?.openHome() }))
        }
        for r in ((try? await runtime.reminderStore.pending()) ?? []).prefix(3) {
            guard let due = r.nextDue, due.timeIntervalSince(now) < 6 * 3600 else { continue }
            entries.append(.init(title: r.title.clipped(40), detail: TimeFormat.when(due, now: now, calendar: .autoupdatingCurrent),
                                 symbol: "alarm", action: { [weak self] in self?.openHome() }))
        }
        for j in ((try? await runtime.jobs.running()) ?? []).prefix(2) {
            entries.append(.init(title: j.title.clipped(40), detail: "running \(TimeText.duration(now.timeIntervalSince(j.startedAt)))",
                                 symbol: "terminal", action: { [weak self] in self?.openHome() }))
        }
        let watching = ((try? await runtime.watcherStore.active()) ?? []).count
        if watching > 0 {
            entries.append(.init(title: "Watching \(watching) thing\(watching == 1 ? "" : "s")", detail: "Scout is on it",
                                 symbol: "binoculars", action: { [weak self] in self?.openHome() }))
        }
        return entries
    }

    #if DEBUG
    func runDevCommand(_ command: String) {
        if command == "home" { openHome(); return }
        if command.hasPrefix("find:") { home.showSearch(String(command.dropFirst(5))); return }
        if command.hasPrefix("drop:") {
            let value = String(command.dropFirst(5))
            if let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") {
                companionReceived(Attachment(kind: .url(url), label: url.host ?? value, text: value))
            } else {
                let file = URL(fileURLWithPath: value)
                companionReceived(Attachment(kind: .file(file), label: file.lastPathComponent, text: nil))
            }
            return
        }
        if command.hasPrefix("settings") {
            openSettings(tab: SettingsTab(rawValue: String(command.dropFirst("settings:".count))))
            return
        }
        if command.hasPrefix("companion:") {
            // companion:<sidefolk|mochi|spark>[:<accent>], the same change the Settings picker makes.
            let parts = command.split(separator: ":").dropFirst().map(String.init)
            let choice = parts.first.flatMap(CompanionChoice.init(rawValue:))
            let accent = parts.dropFirst().first.flatMap(CompanionAccent.init(rawValue:))
            Task {
                await runtime.settings.update { s in
                    if let choice { s.choose(choice) }
                    if let accent { s.accent = accent }
                }
            }
            return
        }
        if command.hasPrefix("ask:") {
            showAsk()
            ask.text = String(command.dropFirst(4))
            ask.submit()
        } else if command.hasPrefix("respond:"), let item = bubbles.model.item {
            respond(to: item, action: String(command.dropFirst(8)))
            bubbles.withdraw(id: item.id)
        } else if command == "dismiss", let item = bubbles.model.item {
            respond(to: item, action: nil)
            bubbles.withdraw(id: item.id)
        } else if command == "hideAsk" {
            askPanel.hide()
        } else if command.hasPrefix("approve") || command == "deny" {
            let decision: ApprovalDecision = command == "deny" ? .deny : (command == "approveAlways" ? .allowAlways : .allowOnce)
            Task {
                guard let first = await runtime.broker.pending().first else { return }
                answer(approval: first, decision: decision)
            }
        }
    }
    #endif

    func refreshCollections() async {
        knownCollections = ((try? await runtime.notebook.collections()) ?? []).map(\.name)
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

    func showAsk(prefill: String? = nil, focus: Bool = true) {
        if let prefill { ask.text = prefill }
        companion.keepRaised(true)
        guard let (frame, screen) = anchor() else { return }
        askPanel.show(beside: frame, on: screen, focus: focus)
    }

    /// An agent saved or set something through Sidefolk: say so, briefly, and credit it.
    private func creditExternal(_ activity: ToolActivity, ok: Bool) {
        guard ok, activity.mutates, case .external(let client) = activity.caller, let card = activity.card else { return }
        let name = AgentFacingTools.displayName(client)
        let item = AttentionItem(level: .gentle, source: "external:\(client)", title: "\(name): \(card.title)",
                                 body: card.subtitle, refKind: "credit")
        companion.character.play(.nod)
        bubbles.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
    }

    func openHome() {
        askPanel.hide()
        home.show()
    }

    func openHome(item: NotebookItem) {
        askPanel.hide()
        home.show(item: item)
    }

    func openSettings(tab: SettingsTab? = nil) {
        askPanel.hide()
        settingsWindow.show(tab: tab)
    }

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
            ask.removeQuestion(id: id)
        case .attention(.backlog(let count)):
            backlog = count
            bubbles.setBacklog(count)
            statusItem.setBadge(count)
            companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0, waiting: count)
        case .approvalRequested(let request):
            ask.add(.approval(request))
            // Other apps' requests appear without taking the keyboard, so a stray Return can't approve them.
            let trusted = request.caller.kind == "user" || request.caller.kind == "agent"
            if !askPanel.isVisible { showAsk(focus: trusted) }
        case .toolFinished(let activity, let ok):
            creditExternal(activity, ok: ok)
        case .approvalResolved(let id, _):
            ask.removeApproval(id: id)
        case .dataChanged(let domain):
            if [.reminders, .watchers, .runs, .attention].contains(domain) { scheduleNowRefresh() }
            if [.reminders, .watchers, .runs, .attention].contains(domain) { refreshRoster() }
            if domain == .reminders { onboarding.reminderCreated() }
            if domain == .settings {
                applyCompanionSettings()
                Task { await runtime.rearm() }
            }
            if domain == .notebook { Task { await refreshCollections() } }
        default:
            break
        }
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        // Questions that want a typed answer (and all of Sidefolk's own) go in the panel, where the user can type.
        if item.refKind == "ask", item.source == "agent" || item.actions.isEmpty {
            ask.add(.question(item))
            let own = item.source == "agent"
            if !askPanel.isVisible { showAsk(focus: own) }
            if own { ask.focusRequest += 1 }
            return
        }
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

    func respond(to item: AttentionItem, action: String?) {
        if item.source == Onboarding.source {
            onboarding.respond(action: action)
            return
        }
        if item.source == Self.ownVoice { return }
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
