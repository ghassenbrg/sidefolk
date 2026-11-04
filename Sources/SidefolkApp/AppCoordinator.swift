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
    var fullScreenVisit: Task<Void, Never>?
    private(set) var askPanel: AskPanelController!
    /// Whispers, cards and the stack above the companion (D84).
    let sidecard = SidecardController()
    let statusItem = StatusItemController()
    /// Extensions' palettes on their shortcuts (D63).
    private(set) lazy var palettes = PaletteController(host: runtime.extensions)
    /// Which app a copy came from, for the clipboard extensions that ask (D68).
    let clipboardSource = ClipboardSource()
    let notifier: SystemNotifier
    let monitor: EnvironmentMonitor
    let companion = CompanionWindowController()
    /// Tricks and little games with the companion (D44).
    lazy var player: CompanionPlayer = {
        let player = CompanionPlayer(companion: companion)
        player.anchorProvider = { [weak self] in self?.anchor() }
        return player
    }()
    /// The overlay that brought a hidden companion out, which goes again with it.
    var surfaceRevealedCompanion: ObjectIdentifier?
    lazy var surfacePanel: SurfacePanelController = makeSurfacePanel(.panel)
    lazy var surfaceOverlay: SurfacePanelController = makeSurfacePanel(.overlay)
    lazy var cues: CueDirector = makeCueDirector()
    private(set) var onboarding: Onboarding!
    var mood = CompanionMood()
    private var roster = DutyRoster()
    /// Open notices that need an answer (the attention center's count).
    var backlog = 0
    /// Live values' recent numbers, for their pins' small lines; in memory only.
    var sparks: [String: [Double]] = [:]
    private var rosterTask: Task<Void, Never>?
    private var nowRefreshTask: Task<Void, Never>?
    let secrets: any SecretStore = KeychainSecretStore()
    private(set) var agent: AgentRuntime!
    var currentRun: String?
    private(set) lazy var home = HomeWindowController(services: self)
    private(set) lazy var settingsWindow = SettingsWindowController(services: self)
    private lazy var about = AboutWindowController(updates: updater.model)
    /// Looking for a newer Sidefolk and installing it when asked (D46).
    private(set) lazy var updater = UpdateController(runtime: runtime)
    private(set) lazy var addonUpdater = AddonUpdateController(runtime: runtime, model: updater.model, themes: .app(runtime.paths))
    /// The folder a theme is being made in, followed while Settings says so (D58).
    let themeFollower = ThemeFollower()
    /// Collection names for the intent parser ("ideas for Sidefolk").
    var knownCollections: [String] = []
    /// What is watched or reported, so "stop the Fukuoka temperature" can be understood without AI.
    var knownWatches: [WatchName] = []
    private var moodTimer: Task<Void, Never>?
    /// The launch's try and a look's can overlap, and two downloads of one add-on share a folder.
    var fetchingThemeThatMoved = false
    /// A look ended while a fetch of the theme that moved was running (`fetchThemeThatMoved`).
    var fetchThemeAgain = false
    private var eventTask: Task<Void, Never>?
    /// Live reports and their latest values (AppCoordinator+Readouts).
    var reports: [Watcher] = []
    var readings: [String: WatchReading] = [:]
    var notifiedReports: Set<String> = []
    var readoutTask: Task<Void, Never>?
    /// The value having its moment beside the companion, and when each last had one (D116).
    var momentId: String?
    var moments: [String: Date] = [:]
    /// Talking and spoken replies (D34).
    private(set) lazy var voice = VoiceController(host: self, secrets: secrets)
    /// Where the person is, while they share their Mac's location (D48).
    private(set) lazy var locator = MacLocator(runtime: runtime)
    /// The Ask shortcut is down and may become a hold to talk.
    var askKeyHold: Task<Void, Never>?
    var askKeyTalking = false
    /// The Ask shortcut's press silenced the companion; its release doesn't toggle the panel too.
    var askKeySilenced = false
    var talkKeysInstalled = false
    /// The card shortcut (D84): installed, and registered right now.
    var cardKeysInstalled = false
    var cardKeysOn = false
    /// Looks again when Focus or Quiet ends, quiet hours start or end, or Full access runs out (D84).
    var attentionTimer: Task<Void, Never>?
    /// What a "Fewer like this" changed, by the id of the whisper that offers Undo (D88).
    var levelUndo: [String: (source: InterruptSource, before: InterruptLevel?)] = [:]
    var fullAccessTimer: Task<Void, Never>?
    /// What this launch's restore did, set before `start` (D91), and the restore's state for Settings.
    var restoreOutcome: BackupRestore.Outcome?
    let restoreModel = RestoreModel()
    #if DEBUG
    /// Set by the `connect:` dev command so a QA copy's Connect can run without a click (D86).
    var devAcceptsNextConfirmation = false
    #endif

    init(runtime: SidefolkRuntime) {
        self.runtime = runtime
        notifier = SystemNotifier(attention: runtime.attention)
        monitor = EnvironmentMonitor(attention: runtime.attention)
        notifier.opened = { [weak self] id in self?.notificationOpened(id) }
    }

    let fileRing = FileRingController()

    func start() async {
        CompanionArt.reloadMade()
        let s = runtime.settings.current
        askPanel = AskPanelController(model: ask, companionName: s.companionName, portrait: CompanionArt.avatar(for: s, side: 26),
                                      hotkey: hotkeyLabel)
        ask.actions = self
        installFileRing()
        let pins = PinnedAskStore(runtime.db)
        let exchanges = runtime.exchanges
        ask.restorePins(await pins.load(conversationKept: { (try? await exchanges.contains(threadId: $0)) ?? false }))
        // One at a time and only the latest, so an older list can't land after a newer one.
        let (saves, save) = AsyncStream.makeStream(of: [SavedAskRequest].self, bufferingPolicy: .bufferingNewest(1))
        Task { for await saved in saves { try? await pins.save(saved) } }
        ask.onPinsChanged = { save.yield($0) }
        // Esc silences the companion or drops what is being said before it closes anything.
        askPanel.onEscape = { [weak self] in self?.voice.cancel() ?? false }
        askPanel.onVisibilityChange = { [weak self] visible in
            self?.mood.panelOpen = visible
            if !visible {
                self?.companion.keepRaised(false)
                self?.sidecard.askClosed()
            }
            self?.renderMood()
            self?.applyCardKeys()
        }

        agent = makeAgentRuntime()
        runtime.companionAgent.use(agent)
        installAIHelp()
        ExtensionCompanionWords.set(runtime.settings.current.companionName)
        onboarding = Onboarding(coordinator: self)
        companion.delegate = self
        applyCompanionSettings()
        applyAppearance()
        let succession = await succeedRetiredTheme()
        applyTheme()
        restoreCompanionAddon()
        // The Mac switching Light/Dark: the menu bar icon follows it even when Sidefolk's own look is fixed.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyCompanionSettings() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.companion.restorePosition() }
        }

        installSidecard()
        if let succession { announceSuccession(succession) }
        Task { await fetchThemeThatMoved() }

        let menuBarImage = BrandAsset.menuBar.image ?? NSImage(
            cgImage: CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: 2),
            size: NSSize(width: 18, height: 18))
        statusItem.install(image: menuBarImage)
        installPocket()
        installModeSwitch()

        // A debug copy must not take ⌘⇧Space from the Sidefolk the developer actually uses (it once
        // swallowed the founder's typing); SIDEFOLK_DEV_HOTKEY=1 opts in.
        #if DEBUG
        let hotkey = ProcessInfo.processInfo.environment["SIDEFOLK_DEV_HOTKEY"] == "1"
        #else
        let hotkey = true
        #endif
        if hotkey {
            installTalkKeys()
            installCardKeys()
        }

        notifier.configure()
        monitor.onAwayChanged = { [weak self] away in self?.setAsleep(away) }
        sidecard.holds = { [weak self] whisper in
            guard let route = self?.fullScreenRoute(whisper: whisper) else { return false }
            return route == .wait || route == .notify
        }
        monitor.onSpaceChanged = { [weak self] in self?.leftFullScreenMaybe() }
        monitor.onWake = { [weak self] in
            guard let self else { return }
            Task { await self.runtime.rearm() }
        }
        monitor.onClockChange = monitor.onWake
        monitor.start()
        await notifier.clearFallback()
        applyAttention()

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
        await resumeRestore()
        IntegrationLocations.prepareStandIns(paths: runtime.paths)
        // Extension pages' charts reach back a day, and Today's tiles stay current (D62).
        await runtime.extensions.startPageSampling()
        await palettes.refresh()
        await refreshCollections()
        await refreshExtensionLooks()
        _ = await notificationsAuthorized()
        refreshRoster()
        refreshReadouts()
        locator.resume()
        refreshMark()
        startUpdates()
        Log.shared.info("app", "ready")
        if !runtime.settings.current.onboardingDone {
            // A beat after launch, so the companion has landed before it speaks.
            try? await Task.sleep(for: .seconds(1))
            onboarding.start()
        }
    }

    // MARK: Companion

    /// A companion chosen before it moved to the add-on gallery (D55), or whose files went missing, comes back by
    /// itself: the person chose it. Mochi stands in until it has arrived.
    private func restoreCompanionAddon() {
        let s = runtime.settings.current
        let species = CompanionArt.species(s.companion)
        guard s.customCompanion == nil, s.localCompanion == nil, species.inGallery, !Companion3DStage.has(species) else { return }
        let addons = runtime.addons, name = s.companion.rawValue, channel = s.updates.effectiveChannel
        Task {
            do {
                // A release on Releases when there is one; else the newest: the person chose this companion.
                let catalog = try await addons.catalog()
                guard let entry = catalog.companion(name, on: channel) ?? catalog.companion(name) else { return }
                try await addons.install(companion: entry)
                CompanionArt.forgetPictures()
                settingsChanged()
            } catch {
                Log.shared.warning("addons", "chosen companion not restored", ["companion": name, "error": String(describing: error)])
            }
        }
    }

    func applyCompanionSettings() {
        let s = runtime.settings.current
        companion.eyesFollowPointer = s.eyesFollowPointer
        companion.apply(size: s.size, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        companion.character.liveliness = CompanionArt.liveliness(s.liveliness)
        companion.apply(look: CompanionArt.look(for: s), name: s.companionName)
        companion.show(presence: s.presence)
        companion.setFolks(roster.onDuty, visible: s.showFolks)
        applyFullScreenHiding()
        sidecard.hidesOverFullScreen = s.hideOverFullScreen
        applyAppIcon(s)
        // A folk chosen as the companion carries its own duty as a badge (setFolks leaves it out).
        companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0)
        sidecard.model.companionName = s.companionName
        sidecard.model.face = CompanionArt.avatar(for: s, side: 48)
        askPanel?.update(companionName: s.companionName, portrait: CompanionArt.avatar(for: s, side: 26), hotkey: hotkeyLabel)
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
            companion.setBadges(watching: roster.activeWatchers > 0, busy: roster.liveAgentWork > 0)
            companion.setAgents(AgentLane.chips(sessions))
            sidecard.model.sessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Only folks standing beside the companion: a folk that is the companion needs no introduction.
            introduceNewFolks(companion.folksShown)
        }
    }

    /// The first time a folk turns up, the companion says who it is: once, gently, never during onboarding.
    private func introduceNewFolks(_ folks: [DutyFolk]) {
        guard runtime.settings.current.showFolks, !onboarding.isRunning, ownRemarksShown else { return }
        let key = "introducedFolks"
        var met = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard let folk = folks.first(where: { !met.contains($0.rawValue) }) else { return }
        met.insert(folk.rawValue)
        UserDefaults.standard.set(met.sorted(), forKey: key)
        let (title, body) = Self.introduction(folk)
        let item = AttentionItem(level: .gentle, source: Self.ownVoice, title: title, body: body, refKind: "intro")
        sidecard.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
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

    /// The companion's remarks of its own (folk introductions, "All clear") come only at Card or Whisper (D88); they are
    /// passing words, so Only in Today keeps nothing of them. Answers to the person's own clicks always come.
    var ownRemarksShown: Bool { runtime.settings.current.interruptions.level(for: .companion) >= .whisper }

    /// Shows a bubble that doesn't go through the attention center (onboarding).
    func presentLocal(_ item: AttentionItem) {
        companion.stepForward()
        sidecard.present(item, .attention(expandFor: 600))
    }

    /// Stops the engines and covers the next week of reminders with system notifications.
    func prepareForQuit() async {
        eventTask?.cancel()
        // An update ready to go in goes in now, so the next launch is the new version (D70).
        await updater.installAtQuit()
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
            self?.refreshMark()
            if self?.statusItem.isPocketShown == true { self?.statusItem.refresh() }
            self?.refreshGlance()
        }
    }

    #if DEBUG
    func runDevCommand(_ command: String) {
        if command == "home" { openHome(); return }
        if command == "companionHide" { showCompanion(false); return }
        if command == "askPinNewest" {
            if let newest = ask.visibleRequests.first { ask.togglePin(newest) }
            return
        }
        if command.hasPrefix("home:") { home.showPlace(String(command.dropFirst(5))); return }
        if command == "homeSmall" { home.devWindow?.setContentSize(NSSize(width: 860, height: 612)); return }
        if command.hasPrefix("flip:") {
            // flip:<extension id>/<page>:on|off: the page's main switch, as from its sidebar row (D67).
            let rest = command.dropFirst(5)
            guard let colon = rest.lastIndex(of: ":") else { return }
            home.flip(page: String(rest[..<colon]), on: rest[rest.index(after: colon)...] == "on")
            return
        }
        if command == "about" { showAbout(); return }
        if devBackup(command) { return }
        if devConnect(command) { return }
        if devCalendar(command) { return }
        if command == "calendar" || command.hasPrefix("calendar:") {
            let parts = command.split(separator: ":").dropFirst().map(String.init)
            let day = parts.count > 1 ? try? Date(parts[1] + "T12:00:00Z", strategy: .iso8601) : nil
            home.showCalendar(parts.first, day: day)
            return
        }
        if command.hasPrefix("update:") { updater.dev(String(command.dropFirst(7))); return }
        if command.hasPrefix("addons:") { addonUpdater.dev(String(command.dropFirst(7))); return }
        if command.hasPrefix("installSheet:") {
            NotificationCenter.default.post(name: InstallPreviewSheet.devPress, object: String(command.dropFirst(13)))
            return
        }
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
        if command.hasPrefix("brain:scripted:") {
            let value = String(command.dropFirst("brain:scripted:".count))
            Task { await DevBrain.set(value, paths: runtime.paths, settings: runtime.settings) }
            return
        }
        if command.hasPrefix("play:"), let act = CompanionAct(rawValue: String(command.dropFirst(5))) { runtime.events.publish(.companion(act)); return }
        if command == "click" { companionClicked(); return }
        if command.hasPrefix("tip:") || command.hasPrefix("recede:") { companion.devFloor(command); return }
        if devSurface(command) { return }
        if command.hasPrefix("swipe:") { askPanel.devSwipe(String(command.dropFirst(6))); return }
        if command.hasPrefix("voice:volume:"), let volume = Double(command.dropFirst("voice:volume:".count)) {
            // 0 checks spoken replies and the mouth without a sound on the developer's Mac.
            Task { await runtime.settings.update { $0.voice.volume = min(max(volume, 0), 1) } }
            return
        }
        if command.hasPrefix("dropChoice:") {
            // One of the drop card's choices, as a click on it (D84), or `<offer>/<menu title>` from its menu.
            let parts = command.dropFirst("dropChoice:".count).split(separator: "/", maxSplits: 1).map(String.init)
            if let attachment = ask.attachment, let name = parts.first {
                if let choice = DropChoice(rawValue: name) {
                    perform(choice, with: attachment, in: ask)
                } else if let offer = extensionDrops(for: attachment).first(where: { $0.key == name }) {
                    perform(offer, choosing: parts.count > 1 ? offer.menu.first { $0.title == parts[1] } : nil, with: attachment, in: ask)
                }
            }
            return
        }
        if command.hasPrefix("ring:") { fileRing.dev(String(command.dropFirst(5))); return }
        if command == "stopWork", let working = ask.working { stopWork(working, in: ask); return }
        if command.hasPrefix("drops:") {
            // Several files dropped at once: paths between | signs.
            if let files = Attachment.files(command.dropFirst(6).split(separator: "|").map { URL(fileURLWithPath: String($0)) }) { companionReceived(files) }
            return
        }
        if command.hasPrefix("uninstall:") {
            // uninstall:<extension id>: as Settings › Add-ons' Remove does, without its question.
            Task { _ = await uninstallExtension(String(command.dropFirst("uninstall:".count))) }
            return
        }
        if command.hasPrefix("entry:") {
            // An extension's menu item or tab (D100), as a click on it.
            func flat(_ list: [ExtensionEntry]) -> [ExtensionEntry] { list.flatMap { [$0] + flat($0.items) } }
            if let entry = flat(runtime.extensions.shelf.entries).first(where: { $0.id == command.dropFirst("entry:".count) }) { run(entry) }
            return
        }
        if command.hasPrefix("drop:") {
            let value = String(command.dropFirst(5))
            if value.hasPrefix("text:") {
                // Dropped words, as the companion takes them from another app (D84's drop card for text).
                let text = String(value.dropFirst(5))
                companionReceived(Attachment(kind: .text, label: "“\(text.clipped(40))”", text: text))
            } else if let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") {
                companionReceived(Attachment(kind: .url(url), label: url.host ?? value, text: value))
            } else {
                let file = URL(fileURLWithPath: value)
                companionReceived(Attachment(kind: .file(file), label: file.lastPathComponent, text: nil))
            }
            return
        }
        if command.hasPrefix("chooser:") {
            // chooser:yours|gallery|search:<words>|detail:<name>|get:<name>|remove:<id>|add|close (D77).
            let sub = String(command.dropFirst("chooser:".count))
            // The Gallery lives in Home now (D84): its page and search open there.
            if sub == "gallery" || sub.hasPrefix("search:") { home.show(section: .gallery); return }
            settingsWindow.chooser(sub)
            return
        }
        if command.hasPrefix("settings") {
            settingsWindow.dev(String(command.dropFirst("settings:".count)))
            return
        }
        if command == "pocket" { statusItem.togglePocket(); return }
        if command.hasPrefix("attention:") {
            // attention:open | attention:focus[:minutes] | attention:quiet[:minutes], as the Pocket's dial (D84).
            let parts = command.split(separator: ":").map(String.init)
            if parts.count > 1, let mode = AttentionMode(rawValue: parts[1]) {
                setAttention(mode, until: parts.count > 2 ? Double(parts[2]).map { Date().addingTimeInterval($0 * 60) } : nil)
            }
            return
        }
        if command.hasPrefix("interrupt:") {
            // interrupt:<source key>:<card|whisper|today|off> ("interrupt:agent:claude-code:today"), as Settings › Attention's
            // table does (D88); "default" clears it.
            let rest = command.dropFirst("interrupt:".count)
            guard let cut = rest.lastIndex(of: ":"), let source = InterruptSource(key: String(rest[..<cut])) else { return }
            let level = InterruptLevel(rawValue: String(rest[rest.index(after: cut)...]))
            Task {
                await runtime.settings.update { $0.interruptions.set(level, for: source) }
                settingsChanged()
            }
            return
        }
        if command.hasPrefix("scroll:"), let fraction = Double(command.dropFirst(7)) {
            // scroll:<0…1>: the tallest scroll view on screen that far down, so `snap` sees below the fold.
            DebugSnapshots.scroll(to: fraction)
            return
        }
        if command.hasPrefix("page:") {
            // page:<extension id>/<page>: Home on an extension's page (D62).
            home.show(page: String(command.dropFirst(5)))
            return
        }
        if command.hasPrefix("pageState:") {
            // pageState:<extension id>/<page>:<json>: Home on that page, showing this state, as an entry opens it (D105).
            let rest = command.dropFirst("pageState:".count)
            guard let colon = rest.firstIndex(of: ":"), let state = try? JSONValue.parse(Data(rest[rest.index(after: colon)...].utf8)).objectValue else { return }
            let id = String(rest[..<colon])
            Task {
                await runtime.extensions.movePage(id, PageGo(set: state))
                home.show(page: id)
                await home.pageMoved(id)
            }
            return
        }
        if command.hasPrefix("pageTool:") {
            // pageTool:<extension id>/<page>:<tool>:<json>: that tool, run as the person, as a click on the page runs it (D105).
            let rest = command.dropFirst("pageTool:".count).split(separator: ":", maxSplits: 2).map(String.init)
            guard rest.count == 3, let input = try? JSONValue.parse(Data(rest[2].utf8)) else { return }
            let extensionId = String(rest[0].split(separator: "/").first ?? ""), short = String(extensionId.split(separator: ".").last ?? "")
            Task {
                let outcome = await runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: rest[1]), input: input, caller: .user, pickedFile: input.string("path"))
                Log.shared.info("dev", "pageTool", ["tool": rest[1], "ok": "\(outcome.isOK)", "problem": outcome.problem?.message ?? ""])
                await home.pageMoved(rest[0])
            }
            return
        }
        if command.hasPrefix("pageInlay:") {
            // pageInlay:<extension id>/<page>:<label>: a button or switch laid into the open page's scene, pressed through what its click runs (D109).
            let rest = command.dropFirst("pageInlay:".count)
            guard let colon = rest.firstIndex(of: ":") else { return }
            let id = String(rest[..<colon]), label = String(rest[rest.index(after: colon)...])
            Task {
                let found = await home.pagePressesInlay(id, label: label)
                Log.shared.info("dev", "pageInlay", ["label": label, "found": "\(found)"])
            }
            return
        }
        if command.hasPrefix("pageAsk:") {
            // pageAsk:<extension id>/<page>:place|schedule: Sidefolk's question, as a page's `allow` shows it (D106, D107).
            let rest = command.dropFirst("pageAsk:".count).split(separator: ":").map(String.init)
            if rest.count == 2, let consent = PageConsent(rawValue: rest[1]) { home.pageAsks(rest[0], consent) }
            return
        }
        if command.hasPrefix("pageShare:") {
            // pageShare:<extension id>/<page>:<path>: a press of a page's `share`; pageShare:<extension id>/<page>:yes: the person's yes to the question.
            let rest = command.dropFirst("pageShare:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if rest.count == 2 {
                Task {
                    if rest[1] == "yes" { await home.pageAnswersShare(rest[0]) } else { await home.pageAsksToShare(rest[0], path: rest[1]) }
                }
            }
            return
        }
        if command.hasPrefix("pageConsent:") {
            // pageConsent:<extension id>:place|schedule:on|off: the person's answer, through the tool that records it.
            let rest = command.dropFirst("pageConsent:".count).split(separator: ":").map(String.init)
            guard rest.count == 3 else { return }
            Task {
                let outcome = await runtime.executor.execute(name: "extensions.consent", input: ["extension": .string(rest[0]), "what": .string(rest[1]), "on": .bool(rest[2] == "on")], caller: .user)
                Log.shared.info("dev", "pageConsent", ["ok": "\(outcome.isOK)", "problem": outcome.problem?.message ?? ""])
            }
            return
        }
        if command.hasPrefix("pageKey:") {
            // pageKey:<scene index>:focus|tab|backtab|press: the keyboard in a page's scene, there being no one at it.
            let rest = command.dropFirst("pageKey:".count).split(separator: ":").map(String.init)
            let scenes = PageSceneBlock.shown.filter { $0.window != nil }.sorted { $0.convert(CGPoint.zero, to: nil).y > $1.convert(CGPoint.zero, to: nil).y }
            guard rest.count == 2, let index = Int(rest[0]), scenes.indices.contains(index) else { return }
            switch rest[1] {
            case "tab": scenes[index].devKey(48)
            case "backtab": scenes[index].devKey(48, shift: true)
            case "press": scenes[index].devKey(49)
            default: scenes[index].devKey(0)
            }
            return
        }
        if command.hasPrefix("pageLook:") {
            // pageLook:dark | light | system: this app's appearance alone, to see a page both ways without touching the Mac's setting.
            switch command.dropFirst("pageLook:".count) {
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            default: NSApp.appearance = nil
            }
            return
        }
        if command.hasPrefix("pageWidth:") {
            // pageWidth:<points>: the Home window this wide, to see a page at a narrower width.
            if let width = Double(command.dropFirst("pageWidth:".count)), let window = NSApp.windows.first(where: { $0.title == "Sidefolk" || $0.contentView is NSVisualEffectView || $0.frame.width > 800 }) {
                var frame = window.frame
                frame.size.width = width
                window.setFrame(frame, display: true)
            }
            return
        }
        if command.hasPrefix("homeSize:") {
            // homeSize:<width>x<height>: Home's window at this size, to see a page narrow and wide.
            let sides = command.dropFirst("homeSize:".count).split(separator: "x").compactMap { Double($0) }
            if sides.count == 2, let window = home.devWindow {
                window.setContentSize(NSSize(width: sides[0], height: sides[1]))
            }
            return
        }
        if command.hasPrefix("pageFile:") {
            // pageFile:<path>: the next page `file` panel takes this, there being no one to click in it (D105).
            PageFilePanel.choiceForTest = String(command.dropFirst("pageFile:".count))
            return
        }
        if command.hasPrefix("palette:") {
            // palette:<extension id>/<palette>: as if its shortcut were pressed (D63).
            Task { await palettes.toggle(String(command.dropFirst(8))) }
            return
        }
        if command.hasPrefix("paletteKey:") {
            // paletteKey:down | up | <key code>[:cmd][:opt][:shift]: a key in the open palette, as PaletteKeys reads it (D68).
            palettes.press(String(command.dropFirst("paletteKey:".count)))
            return
        }
        if command.hasPrefix("mcpServer:") {
            // mcpServer:<name>:<command>:<argument>: adds a plain MCP server, as Settings does once the person confirmed.
            let parts = command.dropFirst("mcpServer:".count).split(separator: ":").map(String.init)
            guard parts.count >= 2 else { return }
            Task {
                do { _ = try await runtime.extensions.addMCPServer(name: parts[0], command: parts[1], arguments: Array(parts.dropFirst(2))) } catch {
                    Log.shared.warning("dev", "mcp server failed", ["error": String(describing: error)])
                }
            }
            return
        }
        if command.hasPrefix("installFolder:") {
            // installFolder:<folder>: installs an extension as Settings does once the person approved its preview.
            let folder = URL(fileURLWithPath: String(command.dropFirst("installFolder:".count)))
            Task {
                do { _ = try await runtime.extensions.install(from: folder) } catch {
                    Log.shared.warning("dev", "install failed", ["error": String(describing: error)])
                }
            }
            return
        }
        if command.hasPrefix("reviewFolder:") {
            // reviewFolder:<folder>: the install preview of an extension folder, as Settings shows it once one is chosen.
            settingsWindow.review(folder: URL(fileURLWithPath: String(command.dropFirst("reviewFolder:".count))))
            return
        }
        if command.hasPrefix("review:") {
            // The same tool Sidefolk's AI calls when a draft is ready: the install preview opens over Settings.
            let name = String(command.dropFirst("review:".count))
            Task { _ = await runtime.executor.execute(name: "extensions.review", input: ["name": .string(name)], caller: .user) }
            return
        }
        if command.hasPrefix("addCompanion:") {
            // addCompanion:<folder>: adds a 3D companion from a folder and wears it, as Settings does once the
            // person agrees (D60).
            let folder = URL(fileURLWithPath: String(command.dropFirst("addCompanion:".count)))
            Task {
                do {
                    try CompanionArt.checkForm(try AddonStore.readLocalCompanion(folder), in: folder)
                    let added = try await runtime.addons.install(companionFolder: folder)
                    CompanionArt.reloadMade()
                    CompanionArt.forgetPictures()
                    await runtime.settings.update { $0.choose(local: added.companion, name: added.name) }
                    settingsChanged()
                } catch {
                    NSLog("addCompanion: \(error)")
                }
            }
            return
        }
        if command.hasPrefix("themeFolder:") || command.hasPrefix("theme:") {
            // theme:<id> picks a theme, themeFolder:<path> follows a folder, as Settings › Appearance › Theme does (D58).
            let folder = command.hasPrefix("themeFolder:") ? String(command.dropFirst("themeFolder:".count)) : nil
            let id = folder == nil ? String(command.dropFirst("theme:".count)) : nil
            Task {
                await runtime.settings.update { s in
                    s.themeFolder = folder
                    if let id { s.theme = id }
                }
                settingsChanged()
            }
            return
        }
        if command.hasPrefix("companion:local:") {
            // companion:local:<name>[:2d|3d]: wears a companion added from a folder (D60), in one of its looks (D85).
            let parts = command.dropFirst("companion:local:".count).split(separator: ":").map(String.init)
            guard let name = parts.first, let local = CompanionArt.local(name) else { return }
            let look = parts.dropFirst().first.flatMap(CompanionDimension.init(rawValue:))
            Task {
                await runtime.settings.update { s in
                    s.choose(local: local.companion, name: local.name)
                    if let look { s.setDimension(look, forLocal: local.companion) }
                }
                settingsChanged()
            }
            return
        }
        if command.hasPrefix("companion:") {
            // companion:<id>[:2d|3d][:<colour>[:<accessory>]], the same changes the Settings chooser makes.
            var parts = command.split(separator: ":").dropFirst().map(String.init)
            guard let choice = parts.first.flatMap(CompanionChoice.init(rawValue:)) else { return }
            let dimension = parts.dropFirst().first.flatMap(CompanionDimension.init(rawValue:))
            if dimension != nil { parts.remove(at: 1) }
            let color = parts.dropFirst().first.flatMap(CompanionAccent.init(rawValue:))
            let accessory = parts.dropFirst(2).first.flatMap(CompanionAccessory.init(rawValue:))
            Task {
                await runtime.settings.update { s in
                    s.choose(choice)
                    if let dimension { s.setDimension(dimension, for: choice) }
                    var style = s.style(for: choice)
                    if let color { style.color = color }
                    if let accessory { style.accessory = accessory }
                    s.setStyle(style, for: choice)
                }
                // As the Settings chooser does: the companion, the Ask panel's header and the rest follow.
                settingsChanged()
            }
            return
        }
        if command.hasPrefix("ask:") {
            showAsk()
            ask.text = String(command.dropFirst(4))
            ask.submit()
        } else if command.hasPrefix("type:") {
            // Typed but not sent: the hint under the field says what Enter would do.
            showAsk()
            ask.text = String(command.dropFirst(5))
        } else if command.hasPrefix("respond:") {
            // The card in view, or else the oldest one waiting in the stack (as Ask on top of it would answer).
            let action = String(command.dropFirst(8))
            if let item = sidecard.model.item {
                respond(to: item, action: action)
                sidecard.withdraw(id: item.id)
            } else {
                Task { if let held = await runtime.attention.open().filter({ $0.level >= .attention }).first { respond(to: held, action: action) } }
            }
        } else if command == "dismiss", let item = sidecard.model.item {
            respond(to: item, action: nil)
            sidecard.withdraw(id: item.id)
        } else if command == "ax", let home = ProcessInfo.processInfo.environment["SIDEFOLK_HOME"] {
            // The accessibility tree of every visible window, beside the snapshots (D84).
            AccessibilityDump.write(to: URL(fileURLWithPath: home).appendingPathComponent("snapshots", isDirectory: true))
        } else if command == "cardKeys" {
            // The card shortcut (D84), which debug copies don't register unless SIDEFOLK_DEV_HOTKEY=1.
            sidecard.devKeys = true
            focusFrontCard()
        } else if command.hasPrefix("cardKey:") {
            sidecard.devKey(String(command.dropFirst("cardKey:".count)))
        } else if command == "grow" {
            sidecard.model.grow?()
        } else if command.hasPrefix("stack:") {
            sidecard.fanStack(command == "stack:on")
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
        // A slip standing alone opens into Ask, on top of what waits (D84); open Ask closes.
        if askPanel.isVisible, !ask.compact { askPanel.hide(); return }
        showAsk()
    }

    /// `slipsOnly`: a permission slip arrived while Ask was closed; it stands alone above the companion.
    func showAsk(prefill: String? = nil, focus: Bool = true, slipsOnly: Bool = false) {
        if let prefill { ask.text = prefill }
        // As they are now: an extension that is gone leaves no tab (D100).
        ask.entryTabs = runtime.extensions.shelf.entries(in: .ask)
        // Opened with nothing to say yet while something waits or comes up: Today first (D84); otherwise the
        // conversation, where typing goes either way.
        if !askPanel.isVisible || ask.compact {
            let fresh = ask.text.isEmpty && ask.attachment == nil && !ask.hasResults && ask.pinnedEntries.isEmpty
            ask.tab = fresh && (waitingCount > 0 || !ask.glance.isEmpty) && !slipsOnly ? .today : .ask
        }
        // One panel at a time: a surface is kept and comes back as it was (D99); a card folds into what Ask shows.
        surfacePanel.hide()
        if !slipsOnly { sidecard.yieldToAsk() }
        refreshGlance()
        companion.keepRaised(true)
        guard let (frame, screen) = anchor() else { return }
        askPanel.show(beside: frame, on: screen, focus: focus, slipsOnly: slipsOnly)
    }

    /// An agent saved or set something through Sidefolk: say so, briefly, and credit it.
    private func creditExternal(_ activity: ToolActivity, ok: Bool) {
        guard ok, activity.mutates, case .external(let client) = activity.caller, let card = activity.card else { return }
        // Only in Today or Off for this agent (D88): what it saved shows in Today and History, not on the desktop.
        guard runtime.settings.current.interruptions.level(for: .agent(InterruptSource.agentName(client))) >= .whisper else { return }
        let name = AgentFacingTools.displayName(client)
        let item = AttentionItem(level: .gentle, source: "external:\(client)",
                                 title: String(localized: "\(name): \(card.title)",
                                               comment: "A label, then what it is about: “Remind me Tomorrow 09:00: Call the bank”, “Claude Code: Saved “Tea ideas””"),
                                 body: card.subtitle,
                                 // Undo on the whisper itself when what it did can be taken back (D84).
                                 actions: activity.undoAvailable ? [AttentionAction(id: SidecardItemCard.undo, title: String(localized: "Undo"))] : [],
                                 refKind: "credit", refId: activity.id)
        companion.character.play(.nod)
        sidecard.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
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

    func openGallery() { home.show(section: .gallery) }

    func showAbout() {
        askPanel.hide()
        about.show()
    }

    func setQuiet(for seconds: TimeInterval?) {
        setAttention(seconds == nil ? .open : .quiet, until: seconds.map { Date().addingTimeInterval($0) })
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
        holdSurfacesForApprovals()
        switch event {
        case .nudge:
            PaletteController.nudge()
        case .clipboardSource(let id):
            clipboardSource.answer(id, host: runtime.extensions)
        case .attention(.present(let item, let presentation)):
            present(item, presentation)
        case .attention(.withdraw(let id)):
            sidecard.withdraw(id: id)
            notifier.withdraw(id: id)
            ask.removeQuestion(id: id)
        case .attention(.backlog(let count)):
            backlog = count
            refreshMark()
            renderLight()
        case .approvalRequested(let request):
            ask.add(.approval(request))
            // Other apps' requests appear without taking the keyboard, so a stray Return can't approve them.
            let trusted = ["user", "agent", "command"].contains(request.caller.kind)
            let notice = AttentionItem(id: Self.approvalNotice(request.id), level: .attention, source: "approval", title: request.summary)
            guard reachInFullScreen(notice) else { break }
            if !askPanel.isVisible || ask.compact { showAsk(focus: trusted, slipsOnly: true) }
        case .toolFinished(let activity, let ok):
            creditExternal(activity, ok: ok)
            announceDoneWithoutAsking(activity, ok: ok)
        case .approvalResolved(let id, _):
            ask.removeApproval(id: id)
            notifier.withdraw(id: Self.approvalNotice(id))
        case .reviewExtension(let folder):
            askPanel.hide()
            settingsWindow.review(folder: folder)
        case .companion(let act):
            // Its little games need it in view and the panel out of the way; a trick plays beside it.
            if act.takesAWhile {
                askPanel.hide()
                if !companion.isVisible { showCompanion(true) }
            }
            player.play(act)
        case .speak(let line):
            voice.sayForATool(line, with: runtime.settings.current.voice)
        case .settingsChangedByTool:
            settingsChanged()
        case .surface(let request):
            openSurface(request)
        case .surfaceGone(let id):
            dropSurfaces(of: id)
        case .surfaceAway(let id, let surface):
            putSurfaceAway(of: id, surface: surface)
        case .extensionPage(let id):
            home.show(section: .page(id))
            Task { await home.pageMoved(id) }
        case .dataChanged(let domain):
            if domain == .permissions { refreshMode() }
            if [.reminders, .watchers, .runs, .attention, .skipped].contains(domain) { scheduleNowRefresh() }
            if [.reminders, .watchers, .runs, .attention].contains(domain) { refreshRoster() }
            if domain == .watchers { refreshReadouts() }
            if domain == .reminders { onboarding.reminderCreated() }
            if domain == .settings {
                applyCompanionSettings()
                applyAttention()
                Task { await runtime.rearm() }
            }
            if domain == .notebook { Task { await refreshCollections() } }
            if domain == .extensions {
                Task {
                    await refreshExtensionLooks()
                    await palettes.refresh()
                }
            }
        default:
            break
        }
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        // An agent session's notice names its agent and project: know the session before it shows.
        if item.refKind == "session", let id = item.refId, sidecard.model.sessions[id] == nil {
            Task {
                if let session = try? await runtime.sessions.live().first(where: { $0.id == id }) { sidecard.model.sessions[id] = session }
                presentKnown(item, presentation)
            }
            return
        }
        presentKnown(item, presentation)
    }

    private func presentKnown(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        // Questions that want a typed answer (and all of Sidefolk's own) go in the panel, where the user can type.
        if item.refKind == "ask", item.source == "agent" || item.actions.isEmpty {
            ask.add(.question(item))
            let own = item.source == "agent"
            guard reachInFullScreen(item) else { return }
            if !askPanel.isVisible { showAsk(focus: own) }
            if own { ask.focusRequest += 1 }
            return
        }
        switch presentation {
        case .ambient:
            break
        case .gentle:
            sidecard.present(item, presentation)
        case .attention:
            if reachInFullScreen(item) { companion.stepForward() }
            sidecard.present(item, presentation)
        case .system(let sound, let alsoOnDesktop):
            notifier.show(item, sound: sound && runtime.settings.current.sounds)
            if alsoOnDesktop, companion.isVisible {
                companion.stepForward()
                sidecard.present(item, .attention(expandFor: AttentionPolicy.expandSeconds))
            }
        }
    }

    func respond(to item: AttentionItem, action: String?) {
        if item.source == Onboarding.source {
            onboarding.respond(action: action)
            return
        }
        if action == SidecardItemCard.undo, item.refKind == Self.levelChanged { return undoLevel(item.id) }
        if action == Self.useSuccessor, item.refKind == Self.themeSuccessor, let id = item.refId { return useTheme(id) }
        if item.source == Self.ownVoice { return }
        if action == SidecardItemCard.undo, item.refKind == "credit", let id = item.refId { return undoFromWhisper(id) }
        if action == "open", item.source == "summary" { openHome() }
        if action == ReminderScheduler.ActionID.open, item.refKind == "reminder", let id = item.refId { openReminderItem(id) }
        Task { await runtime.attention.respond(id: item.id, actionId: action) }
    }

    /// Open on a reminder that belongs to a note or task (D49): that item in the Notebook, or Home if it went to the
    /// Trash since. A reminder of its own opens nothing.
    private func openReminderItem(_ reminderId: String) {
        Task {
            guard let itemId = try? await runtime.reminderStore.reminder(id: reminderId)?.itemId else { return }
            if let item = try? await runtime.notebook.item(id: itemId), item.deletedAt == nil { openHome(item: item) } else { openHome() }
        }
    }

    /// A click on a notification: a reminder's opens its note or task.
    private func notificationOpened(_ attentionId: String) {
        if attentionId.hasPrefix(Self.approvalNoticePrefix) {
            showAsk(focus: false, slipsOnly: true)
            return
        }
        Task {
            guard let item = try? await AttentionStore(runtime.db).item(id: attentionId), item.refKind == "reminder", let id = item.refId else { return }
            openReminderItem(id)
        }
    }

    func renderMood() {
        companion.render(mood.pose(at: Date()))
        renderLight()
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
        if let quiet = unseenValuesMenu() { menu.addItem(quiet) }
        for entry in runtime.extensions.shelf.entries(in: .companion) { menu.addItem(menuItem(entry)) }
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

    /// Play (D44): tricks, then its two little games, or a way out of the one running.
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
        }
        let item = NSMenuItem(title: String(localized: "Play", comment: "The companion's menu: its tricks and little games"), action: nil, keyEquivalent: "")
        item.submenu = play
        return item
    }

    func companionDragChanged(_ dragging: Bool) {
        // Picked up mid-game: the game ends where the person put it.
        if dragging { player.stop() }
        mood.dragging = dragging
        if dragging { askPanel.hide() }
        renderMood()
    }

    func companionMoved() {
        sidecard.reposition()
        if let (frame, screen) = anchor() {
            surfacePanel.reposition(beside: frame, on: screen)
            surfaceOverlay.reposition(beside: frame, on: screen)
        }
    }

    /// Finder's Send to Sidefolk (D151). Any app can call a Service, with no click behind it, unlike a drag: so it doesn't take the
    /// keyboard, and doesn't replace or join what the person is in the middle of. False: it was left alone.
    func filesFromAnotherApp(_ files: Attachment) -> Bool {
        guard ask.attachment == nil, ask.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var files = files
        files.fromAnotherApp = true
        receive(files, focus: false)
        return true
    }

    func companionReceived(_ drop: Attachment) { receive(drop, focus: true) }

    private func receive(_ drop: Attachment, focus: Bool) {
        ask.attachment = withWordsForAI(drop)
        showAsk(focus: focus)
    }

    func withWordsForAI(_ drop: Attachment) -> Attachment {
        var attachment = drop
        if case .file(let url) = drop.kind {
            // What the AI reads with the request (D28: text for models stays English).
            attachment.text = drop.files.count > 1 ? "Dropped files:\n" + drop.files.map(\.path).joined(separator: "\n") : "Dropped file: \(url.path)"
        }
        return attachment
    }

    func companionFolkClicked(_ folk: DutyFolk) { openHome() }

    func showCompanion(_ visible: Bool) {
        if visible {
            companion.show(presence: runtime.settings.current.presence == .menuBarOnly ? .always : runtime.settings.current.presence)
        } else {
            companion.hide()
            askPanel.hide()
        }
        statusItem.setCompanionHidden(!companion.isVisible)
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

// MARK: - Over full-screen apps (D138)

extension AppCoordinator {
    static let approvalNoticePrefix = "approval."
    static func approvalNotice(_ id: String) -> String { approvalNoticePrefix + id }
    /// How long the companion stays on a full-screen space it came to, with nothing done and the pointer elsewhere.
    static let visitSeconds: TimeInterval = 30

    var inFullScreen: Bool {
        NSWorkspace.shared.frontmostApplication.map { Fullscreen.isFrontmostFullscreen(pid: $0.processIdentifier) } ?? false
    }

    /// What the person is on now decides whether the companion shows: while it visits, it does.
    func applyFullScreenHiding() {
        let hide = runtime.settings.current.hideOverFullScreen && inFullScreen
        sidecard.overFullScreenNow = hide
        companion.hideOverFullScreen(hide && fullScreenVisit == nil)
        player.caption.hideOverFullScreen(hide && fullScreenVisit == nil)
    }

    func fullScreenRoute(whisper: Bool) -> FullScreenNotice.Route {
        let s = runtime.settings.current
        return FullScreenNotice.route(hidesOverFullScreen: s.hideOverFullScreen, inFullScreen: inFullScreen, notice: s.fullScreenNotice, whisper: whisper)
    }

    /// Something that needs the person came up. Whether to show it now; if not, a notification may go out, and it waits.
    func reachInFullScreen(_ item: AttentionItem) -> Bool {
        switch fullScreenRoute(whisper: false) {
        case .asUsual:
            return true
        case .visit:
            visitFullScreen()
            return true
        case .notify:
            notifier.show(item, sound: runtime.settings.current.sounds)
            return false
        case .wait:
            return false
        }
    }

    /// The companion comes to the full-screen space, and goes back once it's answered or left alone.
    private func visitFullScreen() {
        fullScreenVisit?.cancel()
        companion.hideOverFullScreen(false)
        player.caption.hideOverFullScreen(false)
        fullScreenVisit = Task { [weak self] in
            let giveUp = Date().addingTimeInterval(Self.visitSeconds)
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let waiting = self.sidecard.cardOut || (self.askPanel.isVisible && self.ask.compact)
                let looking = self.sidecard.isUnderPointer || (self.askPanel.isVisible && self.askPanel.frame.contains(NSEvent.mouseLocation))
                if !waiting || (Date() >= giveUp && !looking) { break }
            }
            guard let self, !Task.isCancelled else { return }
            // Left alone it isn't lost: the card folds into the count, and a slip still waits for an answer there.
            if let id = self.sidecard.currentId, self.sidecard.cardOut { self.sidecard.foldCurrent(id: id) }
            if self.askPanel.isVisible, self.ask.compact { self.askPanel.hide() }
            // A folded card flies to the companion's count: it leaves after that.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self.fullScreenVisit = nil
            self.applyFullScreenHiding()
        }
    }

    /// The space changed: what waited can show now, and a slip that waited opens.
    func leftFullScreenMaybe() {
        applyFullScreenHiding()
        sidecard.spaceChanged()
        guard !inFullScreen, runtime.settings.current.hideOverFullScreen else { return }
        if !ask.pinnedEntries.isEmpty, !askPanel.isVisible { showAsk(focus: false, slipsOnly: true) }
    }
}
