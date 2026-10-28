import AppKit
import KeyboardShortcuts
import SidefolkCharacter
import SidefolkCore

extension KeyboardShortcuts.Name {
    /// ⌘⇧Space by default (DECISIONS D11).
    static let ask = Self("ask", default: .init(.space, modifiers: [.command, .shift]))
    /// Hold to talk, when the person gives talking a shortcut of its own (D34). None by default:
    /// holding the Ask shortcut talks until then.
    static let talk = Self("talk")
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
    /// Tricks and games with the companion (D44).
    lazy var player: CompanionPlayer = {
        let player = CompanionPlayer(companion: companion)
        player.anchorProvider = { [weak self] in self?.anchor() }
        return player
    }()
    /// A toss brought the hidden companion out for the moment; it goes away again once the result has gone.
    var tossRevealed = false
    private(set) var onboarding: Onboarding!
    var mood = CompanionMood()
    private var roster = DutyRoster()
    private var backlog = 0
    private var rosterTask: Task<Void, Never>?
    private var nowRefreshTask: Task<Void, Never>?
    let secrets: any SecretStore = KeychainSecretStore()
    private(set) var agent: AgentRuntime!
    var currentRun: String?
    private(set) lazy var home = HomeWindowController(services: self)
    private(set) lazy var settingsWindow = SettingsWindowController(services: self)
    private lazy var about = AboutWindowController()
    /// Collection names for the intent parser ("ideas for Sidefolk").
    var knownCollections: [String] = []
    /// What is watched or reported, so "stop the Fukuoka temperature" can be understood without AI.
    var knownWatches: [WatchName] = []
    private var moodTimer: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    /// Live reports and their latest values (AppCoordinator+Readouts).
    var reports: [Watcher] = []
    var readings: [String: WatchReading] = [:]
    var notifiedReports: Set<String> = []
    var readoutTask: Task<Void, Never>?
    /// Talking and spoken replies (D34).
    private(set) lazy var voice = VoiceController(host: self, secrets: secrets)
    /// The Ask shortcut is down and may become a hold to talk.
    var askKeyHold: Task<Void, Never>?
    var askKeyTalking = false
    /// The Ask shortcut's press silenced the companion; its release doesn't toggle the panel too.
    var askKeySilenced = false
    var talkKeysInstalled = false

    init(runtime: SidefolkRuntime) {
        self.runtime = runtime
        notifier = SystemNotifier(attention: runtime.attention)
        monitor = EnvironmentMonitor(attention: runtime.attention)
    }

    func start() async {
        CompanionArt.reloadMade()
        let s = runtime.settings.current
        askPanel = AskPanelController(model: ask, companionName: s.companionName, portrait: CompanionArt.portrait(for: s, side: 44),
                                      hotkey: hotkeyLabel)
        ask.actions = self
        // Esc silences the companion or drops what is being said before it closes anything.
        askPanel.onEscape = { [weak self] in self?.voice.cancel() ?? false }
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
        statusItem.onAbout = { [weak self] in self?.showAbout() }
        statusItem.onQuiet = { [weak self] seconds in self?.setQuiet(for: seconds) }
        statusItem.isQuiet = { [weak self] in self?.runtime.settings.current.isQuiet(at: Date()) ?? false }
        statusItem.hotkeyLabel = { [weak self] in self?.hotkeyLabel ?? "" }
        statusItem.companionName = { [weak self] in self?.runtime.settings.current.companionName ?? "Sidefolk" }
        statusItem.companionVisible = { [weak self] in self?.companion.isVisible ?? false }
        statusItem.onToggleCompanion = { [weak self] in
            guard let self else { return }
            self.showCompanion(!self.companion.isVisible)
        }
        statusItem.nowProvider = { [weak self] in await self?.nowEntries() ?? [] }
        installModeSwitch()

        // A debug copy must not take ⌘⇧Space from the Sidefolk the developer actually uses (it once
        // swallowed the founder's typing); SIDEFOLK_DEV_HOTKEY=1 opts in.
        #if DEBUG
        let hotkey = ProcessInfo.processInfo.environment["SIDEFOLK_DEV_HOTKEY"] == "1"
        #else
        let hotkey = true
        #endif
        if hotkey { installTalkKeys() }

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
        await refreshExtensionLooks()
        _ = await notificationsAuthorized()
        refreshRoster()
        refreshReadouts()
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
        companion.character.liveliness = CompanionArt.liveliness(s.liveliness)
        companion.apply(look: CompanionArt.look(for: s), name: s.companionName)
        player.companionName = s.companionName
        companion.show(presence: s.presence)
        companion.setFolks(roster.onDuty, visible: s.showFolks)
        // A folk chosen as the companion carries its own duty as a badge (setFolks leaves it out).
        companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0, waiting: backlog)
        askPanel?.update(companionName: s.companionName, portrait: CompanionArt.portrait(for: s, side: 44), hotkey: hotkeyLabel)
        applyVoiceKeys()
        renderMood()
        renderReadouts()
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
            // Only folks standing beside the companion: a folk that is the companion needs no introduction.
            introduceNewFolks(companion.folksShown)
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
        case .tempo: (String(localized: "That's Tempo."), String(localized: "Tempo turns up when a reminder is less than 15 minutes away."))
        case .scout: (String(localized: "That's Scout."), String(localized: "Scout stays out while I'm watching something for you."))
        case .byte: (String(localized: "That's Byte."), String(localized: "Byte keeps me company while an agent or a command is working."))
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
        // A request still running stops with the app: its CLI brain's process group gets SIGTERM rather than
        // finishing its turn on the person's quota with no one to answer it.
        await agent.cancelAll()
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
            entries.append(.init(title: String(localized: "\(s.agent == "codex" ? "Codex" : "Claude") needs you"),
                                 detail: s.projectName ?? String(localized: "a session"),
                                 symbol: "hand.raised", action: { [weak self] in self?.openSession(s) }))
        }
        let open = await runtime.attention.open().filter { $0.level >= .attention }
        if !open.isEmpty {
            entries.append(.init(title: String(localized: "Needs you (\(open.count))"), detail: open[0].title.clipped(30), symbol: "tray.full",
                                 action: { [weak self] in self?.openHome() }))
        }
        if let skipped = await skippedNowEntry() { entries.append(skipped) }
        for r in ((try? await runtime.reminderStore.pending()) ?? []).prefix(3) {
            guard let due = r.nextDue, due.timeIntervalSince(now) < 6 * 3600 else { continue }
            entries.append(.init(title: r.title.clipped(40), detail: TimeFormat.when(due, now: now, calendar: .autoupdatingCurrent),
                                 symbol: "alarm", action: { [weak self] in self?.openHome() }))
        }
        for j in ((try? await runtime.jobs.running()) ?? []).prefix(2) {
            entries.append(.init(title: j.title.clipped(40),
                                 detail: String(localized: "running \(TimeText.duration(now.timeIntervalSince(j.startedAt)))", comment: "“running 4m 12s”"),
                                 symbol: "terminal", action: { [weak self] in self?.openHome() }))
        }
        for w in reports.prefix(3) {
            let value = readings[w.id].map { "\($0.label) \($0.value)" } ?? w.title
            entries.append(.init(title: value.clipped(40), detail: Describe.interval(w.intervalS), symbol: Describe.watcherKind(w.kind).symbol,
                                 action: { [weak self] in self?.openHome() }))
        }
        let watching = ((try? await runtime.watcherStore.active()) ?? []).filter { $0.mode != .report }.count
        if watching > 0 {
            entries.append(.init(title: String(localized: "Watching \(watching) things"), detail: String(localized: "Scout is on it"),
                                 symbol: "binoculars", action: { [weak self] in self?.openHome() }))
        }
        return entries
    }

    #if DEBUG
    func runDevCommand(_ command: String) {
        if command == "home" { openHome(); return }
        if command == "about" { showAbout(); return }
        if command.hasPrefix("language:") {
            let code = String(command.dropFirst(9))
            AppLanguage.chosen = code == "system" ? nil : code
            AppLanguage.relaunch()
            return
        }
        if command.hasPrefix("find:") { home.showSearch(String(command.dropFirst(5))); return }
        if command.hasPrefix("voice:file:") {
            // As if the talk key were held while the file played into the microphone.
            voice.talk(file: URL(fileURLWithPath: String(command.dropFirst("voice:file:".count))))
            return
        }
        if command == "voice:stop" { _ = voice.cancel(); return }
        if command.hasPrefix("play:"), let act = CompanionAct(rawValue: String(command.dropFirst(5))) { runtime.events.publish(.companion(act)); return }
        if command == "click" { companionClicked(); return }
        if command.hasPrefix("toss:") { devToss(command.dropFirst(5).split(separator: ":").map(String.init)); return }
        if command.hasPrefix("swipe:") { askPanel.devSwipe(String(command.dropFirst(6))); return }
        if command.hasPrefix("voice:volume:"), let volume = Double(command.dropFirst("voice:volume:".count)) {
            // 0 checks spoken replies and the mouth without a sound on the developer's Mac.
            Task { await runtime.settings.update { $0.voice.volume = min(max(volume, 0), 1) } }
            return
        }
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
        if command.hasPrefix("review:") {
            // The same tool Sidefolk's AI calls when a draft is ready: the install preview opens over Settings.
            let name = String(command.dropFirst("review:".count))
            Task { _ = await runtime.executor.execute(name: "extensions.review", input: ["name": .string(name)], caller: .user) }
            return
        }
        if command.hasPrefix("companion:") {
            // companion:<id>[:<colour>[:<accessory>]], the same changes the Settings chooser makes.
            let parts = command.split(separator: ":").dropFirst().map(String.init)
            guard let choice = parts.first.flatMap(CompanionChoice.init(rawValue:)) else { return }
            let color = parts.dropFirst().first.flatMap(CompanionAccent.init(rawValue:))
            let accessory = parts.dropFirst(2).first.flatMap(CompanionAccessory.init(rawValue:))
            Task {
                await runtime.settings.update { s in
                    s.choose(choice)
                    var style = s.style(for: choice)
                    if let color { style.color = color }
                    if let accessory { style.accessory = accessory }
                    s.setStyle(style, for: choice)
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

    /// How each extension looks, for its approval and result cards in the Ask panel.
    func refreshExtensionLooks() async {
        ask.extensionLooks = Dictionary(await extensions().map { ($0.id, $0.look) }, uniquingKeysWith: { a, _ in a })
    }

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
        let item = AttentionItem(level: .gentle, source: "external:\(client)",
                                 title: String(localized: "\(name): \(card.title)",
                                               comment: "A label, then what it is about: “Remind me Tomorrow 09:00: Call the bank”, “Claude Code: Saved “Tea ideas””"),
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

    func showAbout() {
        askPanel.hide()
        about.show()
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
        // A new value is not news for the companion's mood: it only updates its pill.
        if case .watchReading(let reading) = event {
            showReading(reading)
            return
        }
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
            announceDoneWithoutAsking(activity, ok: ok)
        case .approvalResolved(let id, _):
            ask.removeApproval(id: id)
        case .reviewExtension(let folder):
            askPanel.hide()
            settingsWindow.review(folder: folder)
        case .companion(let act):
            // A game needs the companion in view and the panel out of the way; a trick plays beside it.
            if act.isGame {
                askPanel.hide()
                if !companion.isVisible { showCompanion(true) }
                // A game keeps it out: the toss that brought it out no longer puts it away.
                tossRevealed = false
            }
            player.play(act)
        case .toss(let toss):
            // The result belongs on the desktop: hidden, the companion comes out for the moment and goes again after.
            if !companion.isVisible {
                showCompanion(true)
                tossRevealed = true
            }
            player.toss(toss) { [weak self] in
                guard let self, tossRevealed else { return }
                tossRevealed = false
                // Only the companion goes: an answer may still be open in the Ask panel.
                guard player.game == nil else { return }
                companion.hide()
                renderReadouts()
            }
        case .dataChanged(let domain):
            if domain == .permissions { refreshMode() }
            if [.reminders, .watchers, .runs, .attention, .skipped].contains(domain) { scheduleNowRefresh() }
            if [.reminders, .watchers, .runs, .attention].contains(domain) { refreshRoster() }
            if domain == .watchers { refreshReadouts() }
            if domain == .reminders { onboarding.reminderCreated() }
            if domain == .settings {
                applyCompanionSettings()
                Task { await runtime.rearm() }
            }
            if domain == .notebook { Task { await refreshCollections() } }
            if domain == .extensions { Task { await refreshExtensionLooks() } }
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

    func renderMood() {
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
    func companionClicked() {
        // In catch-me, a click is a catch (D44).
        if player.click() { return }
        // A click while it talks only silences it (D34).
        if voice.isSpeaking {
            voice.interrupt(cancelRun: true)
            return
        }
        toggleAsk()
    }

    var companionCanTalk: Bool { runtime.settings.current.voice.input }
    func companionHoldBegan() { voice.begin() }
    func companionHoldEnded() { voice.end() }

    func companionDoubleClicked() {
        guard player.game == nil else { return }
        askPanel.hide()
        openHome()
    }

    func companionMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: @escaping () -> Void) {
            menu.addItem(ClosureTarget.item(title, action))
        }
        item(String(localized: "Ask…")) { [weak self] in self?.showAsk() }
        item(String(localized: "Open Sidefolk")) { [weak self] in self?.openHome() }
        menu.addItem(playMenu())
        menu.addItem(.separator())
        if runtime.settings.current.isQuiet(at: Date()) {
            item(String(localized: "Turn Quiet Off")) { [weak self] in self?.setQuiet(for: nil) }
        } else {
            item(String(localized: "Quiet for 1 Hour")) { [weak self] in self?.setQuiet(for: 3600) }
        }
        item(String(localized: "Hide Companion")) { [weak self] in self?.showCompanion(false) }
        menu.addItem(.separator())
        item(String(localized: "Settings…")) { [weak self] in self?.openSettings() }
        return menu
    }

    /// Play (D44): tricks, then the two games, or a way out of the one running.
    private func playMenu() -> NSMenuItem {
        let play = NSMenu()
        if player.game != nil {
            play.addItem(ClosureTarget.item(String(localized: "Stop Playing")) { [weak self] in self?.player.stop() })
        } else {
            for act in [CompanionAct.dance, .wave, .bow, .flip, .giggle, .trick] {
                play.addItem(ClosureTarget.item(act.title) { [weak self] in self?.player.play(act) })
            }
            play.addItem(.separator())
            for act in [CompanionAct.catchMe, .breathe] {
                play.addItem(ClosureTarget.item(act.title) { [weak self] in
                    self?.askPanel.hide()
                    self?.player.play(act)
                })
            }
            // Chance, drawn by the same tool the AI and the person's words reach (D44, amended).
            play.addItem(.separator())
            play.addItem(ClosureTarget.item(String(localized: "Flip a Coin")) { [weak self] in self?.toss(["kind": "coin"]) })
            play.addItem(ClosureTarget.item(String(localized: "Roll a Die")) { [weak self] in self?.toss(["kind": "dice"]) })
            let hands = NSMenu()
            for hand in Hand.allCases {
                hands.addItem(ClosureTarget.item(hand.title) { [weak self] in self?.toss(["kind": "rock_paper_scissors", "hand": .string(hand.rawValue)]) })
            }
            let rps = NSMenuItem(title: String(localized: "Rock, Paper, Scissors", comment: "A menu: pick your hand"), action: nil, keyEquivalent: "")
            rps.submenu = hands
            play.addItem(rps)
        }
        let item = NSMenuItem(title: String(localized: "Play", comment: "The companion's menu: tricks and games"), action: nil, keyEquivalent: "")
        item.submenu = play
        return item
    }

    /// Flips, rolls or plays a hand through the executor, as the person's own action: the event it sends plays it.
    func toss(_ input: JSONValue) {
        Task { _ = await runtime.executor.execute(name: "companion.toss", input: input, caller: .user) }
    }

    /// `toss:coin[:count]`, `toss:dice[:count[:sides]]`, `toss:rps:<hand>`.
    func devToss(_ parts: [String]) {
        var input: [String: JSONValue] = ["kind": .string(parts.first == "rps" ? "rock_paper_scissors" : parts.first ?? "coin")]
        if parts.first == "rps" { input["hand"] = .string(parts.count > 1 ? parts[1] : "rock") }
        if parts.first != "rps", parts.count > 1, let count = Double(parts[1]) { input["count"] = .number(count) }
        if parts.count > 2, let sides = Double(parts[2]) { input["sides"] = .number(sides) }
        toss(.object(input))
    }

    func companionDragChanged(_ dragging: Bool) {
        // Picked up mid-game: the game ends where the person put it.
        if dragging { player.stop() }
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
            // What the AI reads with the request (D28: text for models stays English).
            attachment.text = "Dropped file: \(url.path)"
        }
        ask.attachment = attachment
        showAsk()
    }

    func companionFolkClicked(_ folk: DutyFolk) { openHome() }

    func companionReadoutClicked() { openHome() }

    func showCompanion(_ visible: Bool) {
        if visible {
            companion.show(presence: runtime.settings.current.presence == .menuBarOnly ? .always : runtime.settings.current.presence)
        } else {
            companion.hide()
            askPanel.hide()
        }
        statusItem.companionVisible = { [weak self] in self?.companion.isVisible ?? false }
        // The live values follow: beside the companion, or in the menu bar while it is away.
        renderReadouts()
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
