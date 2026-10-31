import AppKit
import SidefolkCore

/// Looks for a newer Sidefolk and asks before installing it (D46), or installs it by itself (D70). A published copy
/// looks a minute after launch (unless it looked within the hour) and once a day unless Settings › Updates says
/// "Don't check"; a copy built on this Mac only when asked. On "Tell me", a version found by itself is brought up in
/// a gentle bubble, which waits through quiet mode and full screen and isn't repeated for three days; Settings and
/// the menu bar keep it in reach. On "Install automatically", it is downloaded and checked as Update does, then put
/// in place at a calm moment (`InstallMoment`) or as Sidefolk quits; when that can't be done, it tells instead.
@MainActor
final class UpdateController: UpdateActions {
    let model = UpdateModel()
    private let runtime: SidefolkRuntime
    private let app: RunningApp
    private let checker: UpdateChecker
    private let installer: UpdateInstaller
    private lazy var window: UpdateWindowController = {
        let window = UpdateWindowController(model: model)
        window.onClose = { [weak self] in self?.windowClosed() }
        return window
    }()
    private var loop: Task<Void, Never>?
    private var work: Task<Void, Never>?
    /// The checked copy beside the app, waiting for a calm moment (D70).
    private var staged: URL?
    private var calm: Task<Void, Never>?
    /// A version that couldn't be installed by itself in this run: it's told about, not tried again until relaunch
    /// (Update still tries).
    private var gaveUp: ReleaseVersion?
    /// What is going on around the app, read when an automatic install considers restarting (the coordinator's).
    var signals: () async -> InstallMoment.Signals = { InstallMoment.Signals() }
    /// Quits so the new copy can open: the app's own quit, which tidies up first.
    var quit: () -> Void = { AppDelegate.quit() }

    static let source = "update"
    /// The note after an automatic install: "Updated to …", with What's New.
    static let updatedKind = "updated"
    /// How often a ready update looks for its calm moment.
    static let calmCheck: Duration = .seconds(30)

    init(runtime: SidefolkRuntime, app: RunningApp = .current()) {
        self.runtime = runtime
        self.app = app
        checker = UpdateChecker(kv: KVStore(runtime.db), clock: runtime.clock)
        installer = UpdateInstaller(app: app, workFolder: runtime.paths.updates,
                                    downloadsFolder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        model.version = app.version
        model.published = app.release != nil
        model.running = app.release?.shown
            ?? String(localized: "\(SidefolkVersion.current) (built on this Mac)", comment: "Settings › Updates: a copy that isn't a published release")
        model.plan = installer.plan
        model.actions = self
    }

    func start() async {
        await installer.removeLeftovers()
        let state = await checker.state()
        model.lastCheck = state.lastCheck
        if let offer = newest(in: state.offers) {
            model.phase = .available(offer)
            // Found by an earlier run, on "Install automatically": prepared now rather than at tomorrow's look.
            if app.release != nil, installsByItself { prepareByItself(offer) }
        }
        await runtime.attention.onAction(kind: Self.source) { [weak self] item, action in
            await MainActor.run { self?.answer(item, action) }
        }
        await runtime.attention.onAction(kind: Self.updatedKind) { item, action in
            guard action == "notes", let page = item.refId.flatMap(URL.init(string:)), page.scheme == "https" else { return }
            await MainActor.run { _ = NSWorkspace.shared.open(page) }
        }
        if let installed = await checker.takeInstalled(), installed.version == app.version {
            Log.shared.info("updates", "opened after installing by itself", ["version": installed.version.description])
            _ = await runtime.attention.post(Self.updatedNotice(installed))
        }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            var gap: TimeInterval = 3600
            while !Task.isCancelled {
                await self?.lookIfDue(gap: gap)
                gap = UpdateChecker.interval
                // Hourly, so a Mac that slept through the day's look catches up soon after it wakes.
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// The channel or the skipped version changed: what's on offer may have too.
    func settingsChanged() {
        guard !model.busy, staged == nil else { return }
        Task {
            let offers = await checker.state().offers
            guard !model.busy else { return }
            if let offer = newest(in: offers) {
                model.phase = .available(offer)
                // Just switched to "Install automatically" with a version on offer: it goes ahead.
                if app.release != nil, installsByItself { prepareByItself(offer) }
            } else if model.offer != nil, case .available = model.phase {
                model.phase = .upToDate
            }
        }
    }

    /// The version the menu bar offers, if one is waiting.
    var waitingVersion: String? {
        switch model.phase {
        case .available(let offer), .ready(let offer): offer.version.shown
        default: nil
        }
    }

    // MARK: Looking

    private func lookIfDue(gap: TimeInterval) async {
        guard app.release != nil, runtime.settings.current.updates.automatic, !model.busy, staged == nil,
              await checker.isDue(after: gap) else { return }
        await look(manual: false)
    }

    private func look(manual: Bool) async {
        let before = model.phase
        if manual { model.phase = .checking }
        do {
            let offers = try await checker.check()
            model.lastCheck = await checker.state().lastCheck
            guard let offer = newest(in: offers) else {
                if manual || !model.busy { model.phase = .upToDate }
                return
            }
            if manual || !model.busy { model.phase = .available(offer) }
            if !manual, installsByItself {
                prepareByItself(offer)
            } else if !manual, await checker.shouldAsk(about: offer) {
                await bringUp(offer)
            }
            Log.shared.info("updates", "looked", ["newest": offer.version.description, "manual": String(manual)])
        } catch {
            let e = AppCoordinator.userFacing(error, fallback: String(localized: "Sidefolk couldn't look for updates."))
            Log.shared.info("updates", "look failed", ["error": e.description, "manual": String(manual)])
            // A look by itself fails quietly; one the person asked for says why.
            model.phase = manual ? .failed(nil, e) : before
        }
    }

    private func newest(in offers: [UpdateOffer]) -> UpdateOffer? {
        let s = runtime.settings.current.updates
        return ReleaseFeed.newest(offers, channel: s.effectiveChannel, after: app.version, skipping: s.skipped)
    }

    /// A gentle bubble beside the companion: it waits through quiet mode and full screen, and only adds to the
    /// badge when the companion lives in the menu bar.
    private func bringUp(_ offer: UpdateOffer) async {
        await checker.markAsked(offer)
        _ = await runtime.attention.post(Self.notice(offer))
    }

    static func notice(_ offer: UpdateOffer) -> AttentionRequest {
        AttentionRequest(
            level: .gentle, source: source,
            title: String(localized: "Sidefolk \(offer.version.shown) is ready", comment: "An update: “Sidefolk 0.1.0 snapshot 430 is ready”"),
            body: offer.summary(),
            actions: [AttentionAction(id: "update", title: String(localized: "Update"), isPrimary: true),
                      AttentionAction(id: "later", title: String(localized: "Later")),
                      AttentionAction(id: "skip", title: String(localized: "Skip This Version"))],
            refKind: source, refId: offer.tag)
    }

    private func answer(_ item: AttentionItem, _ action: String) {
        guard let offer = model.offer, offer.tag == item.refId else { return }
        switch action {
        case "update": install(offer)
        case "skip": skip(offer)
        default: break
        }
    }

    // MARK: Installing by itself (D70)

    /// "Install automatically", and this copy can replace itself (D46's cases: otherwise it tells, as on "Tell me").
    private var installsByItself: Bool {
        runtime.settings.current.updates.app == .install && installer.plan == .replace
    }

    /// Downloads and checks `offer` exactly as Update does, out of sight, then waits for a calm moment. If anything
    /// fails, it tells the person instead, as on "Tell me".
    private func prepareByItself(_ offer: UpdateOffer) {
        guard work == nil, staged == nil, gaveUp != offer.version else { return }
        model.plan = installer.plan
        model.phase = .downloading(offer, received: 0, total: offer.image.size)
        let installer = self.installer
        let progress: @Sendable (UpdateInstaller.Step) -> Void = { [weak self] step in
            let owner = self
            Task { @MainActor in owner?.show(step, of: offer) }
        }
        Log.shared.info("updates", "installing by itself", ["version": offer.version.description])
        work = Task { [weak self] in
            do {
                let prepared = try await installer.prepare(offer, step: progress)
                try Task.checkCancellation()
                guard case .staged(let staged) = prepared else { throw UserFacingError("This copy of Sidefolk can't update itself.") }
                self?.wait(with: staged, offer)
            } catch {
                await self?.tell(offer, after: error)
            }
            self?.work = nil
        }
    }

    /// Something went wrong on the way: the person hears of the version as on "Tell me", and Update tries again.
    private func tell(_ offer: UpdateOffer, after error: Error) async {
        let cancelled = error is CancellationError
        if !cancelled {
            gaveUp = offer.version
            Log.shared.warning("updates", "couldn't install by itself; telling instead",
                               ["version": offer.version.description, "error": String(describing: error)])
        }
        model.phase = .available(offer)
        if !cancelled, await checker.shouldAsk(about: offer) { await bringUp(offer) }
    }

    /// Holds the checked copy and looks for a calm moment every half minute; quitting puts it in place too.
    private func wait(with staged: URL, _ offer: UpdateOffer) {
        self.staged = staged
        model.phase = .ready(offer)
        calm?.cancel()
        calm = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.calmCheck)
                guard let self, !Task.isCancelled, self.staged == staged else { return }
                // The person may have changed their mind: then it waits for Restart Now or the quit.
                guard runtime.settings.current.updates.app == .install else { continue }
                let decision = InstallMoment.decide(await signals())
                guard decision == .now, self.staged == staged else { continue }
                Log.shared.info("updates", "calm moment: installing", ["version": offer.version.description])
                put(staged, offer, byItself: true)
                return
            }
        }
    }

    /// Sidefolk is quitting with a checked copy waiting: it goes in place now, without reopening, so the next
    /// launch is the new version. Called while the app quits; a failure leaves the old copy, which the next launch
    /// tidies.
    func installAtQuit() async {
        guard let staged, let offer = model.readyOffer else { return }
        self.staged = nil
        calm?.cancel()
        await checker.markInstalling(offer)
        do {
            try installer.installAtQuit(staged)
            Log.shared.info("updates", "installed at quit", ["version": offer.version.description])
        } catch {
            _ = await checker.takeInstalled()
            Log.shared.warning("updates", "couldn't install at quit", ["version": offer.version.description, "error": String(describing: error)])
        }
    }

    /// "Updated to Sidefolk 0.1.0 snapshot 540", once, the first time the new copy opens.
    static func updatedNotice(_ installed: UpdateState.Installed) -> AttentionRequest {
        AttentionRequest(
            level: .gentle, source: source,
            title: String(localized: "Updated to Sidefolk \(installed.version.shown)", comment: "After Sidefolk installed an update by itself: “Updated to Sidefolk 0.1.0 snapshot 540”"),
            body: String(localized: "It installed by itself, as you chose in Settings › Updates."),
            actions: [AttentionAction(id: "notes", title: String(localized: "What's New"), isPrimary: true),
                      AttentionAction(id: "ok", title: String(localized: "OK"))],
            refKind: updatedKind, refId: installed.page.absoluteString)
    }

    // MARK: UpdateActions

    func checkNow() {
        guard !model.busy, staged == nil else { window.show(); return }
        window.show()
        Task { await look(manual: true) }
    }

    func showUpdates() {
        if model.offer == nil, !model.busy { checkNow() } else { window.show() }
    }

    func install(_ offer: UpdateOffer) {
        window.show()
        // Ready already: Update and Restart restarts now.
        if staged != nil { return restartNow() }
        guard work == nil else { return }
        Task { await runtime.attention.withdraw(refKind: Self.source, refId: offer.tag) }
        model.plan = installer.plan
        model.phase = .downloading(offer, received: 0, total: offer.image.size)
        let installer = self.installer
        let progress: @Sendable (UpdateInstaller.Step) -> Void = { [weak self] step in
            let owner = self
            Task { @MainActor in owner?.show(step, of: offer) }
        }
        work = Task { [weak self] in
            do {
                let prepared = try await installer.prepare(offer, step: progress)
                try Task.checkCancellation()
                self?.finish(prepared, offer)
            } catch {
                self?.failed(offer, error)
            }
            self?.work = nil
        }
    }

    /// Puts the waiting copy in place now, whatever is going on: the person asked.
    func restartNow() {
        guard let staged, let offer = model.readyOffer else { return }
        window.show()
        calm?.cancel()
        put(staged, offer, byItself: false)
    }

    func skip(_ offer: UpdateOffer) {
        Task { await runtime.attention.withdraw(refKind: Self.source, refId: offer.tag) }
        Task { await runtime.settings.update { $0.updates.skipped = offer.version } }
        model.phase = .upToDate
        window.close()
    }

    func later() {
        window.close()
        settle()
    }

    /// Stops a download or its checks; a look is quick and harmless, so the window just goes.
    func cancel() {
        if let work { work.cancel() } else { window.close() }
    }

    func reveal(_ file: URL) { NSWorkspace.shared.activateFileViewerSelecting([file]) }

    func openPage(_ offer: UpdateOffer) { NSWorkspace.shared.open(offer.page) }

    // MARK: Installing

    /// Downloading steps arrive from the network's queue: a late one never takes the window back a step.
    private func show(_ step: UpdateInstaller.Step, of offer: UpdateOffer) {
        switch step {
        case .downloading(let received, let total):
            if case .downloading = model.phase { model.phase = .downloading(offer, received: received, total: total) }
        case .checking: model.phase = .verifying(offer)
        case .installing: model.phase = .installing(offer)
        }
    }

    private func finish(_ prepared: UpdateInstaller.Prepared, _ offer: UpdateOffer) {
        switch prepared {
        case .staged(let staged):
            put(staged, offer, byItself: false)
        case .downloaded(let file, let reason):
            model.phase = .downloaded(offer, file, reason)
            Log.shared.info("updates", "downloaded", ["version": offer.version.description, "reason": reason.rawValue])
            reveal(file)
        }
    }

    /// Swaps the checked copy in and quits so it opens. On failure nothing has changed and the window says why.
    private func put(_ staged: URL, _ offer: UpdateOffer, byItself: Bool) {
        self.staged = nil
        Task { [weak self] in
            guard let self else { return }
            // Written first: the copy that opens says "Updated to …" once.
            if byItself { await checker.markInstalling(offer) }
            do {
                // The developer's own data folder (SIDEFOLK_HOME) travels with a dev copy, as with a language change.
                try installer.install(staged, environment: ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("SIDEFOLK_") })
            } catch {
                if byItself { _ = await checker.takeInstalled() }
                failed(offer, error)
                return
            }
            model.phase = .restarting(offer)
            Log.shared.info("updates", "installed, restarting", ["version": offer.version.description, "byItself": String(byItself)])
            try? await Task.sleep(for: .seconds(0.8))   // long enough to read "Restarting"
            quit()
        }
    }

    private func failed(_ offer: UpdateOffer, _ error: Error) {
        if error is CancellationError || Task.isCancelled {
            model.phase = .available(offer)
            return
        }
        let e = AppCoordinator.userFacing(error, fallback: String(localized: "The update didn't finish."))
        Log.shared.error("updates", "update failed", ["version": offer.version.description, "error": e.description,
                                                     "detail": e.detail ?? ""])
        model.phase = .failed(offer, e)
    }

    /// The window went away: a finished look or a failure settles back to what is on offer. Work in progress
    /// carries on (Settings shows it); Cancel is how it stops.
    private func windowClosed() { settle() }

    private func settle() {
        if case .failed(let offer, _) = model.phase { model.phase = offer.map { .available($0) } ?? .idle }
    }

    #if DEBUG
    /// `update:offer | notice | downloading | downloaded | failed | uptodate | check` from scripts/dev.swift: the
    /// window and the bubble in each state, without a release to find.
    func dev(_ command: String) {
        let offer = Self.sampleOffer
        switch command {
        case "offer": model.phase = .available(offer); window.show()
        case "notice": model.phase = .available(offer); Task { await bringUp(offer) }
        case "downloading": model.phase = .downloading(offer, received: 9_400_000, total: offer.image.size); window.show()
        case "downloaded":
            model.phase = .downloaded(offer, URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/Sidefolk-0.1.0-snapshot.430.dmg"), .notWritable)
            window.show()
        case "failed":
            model.phase = .failed(offer, UserFacingError("The download doesn't match the release's checksum, so it wasn't installed.",
                                                         recovery: "Try again; if it happens again, download it from the release page."))
            window.show()
        case "uptodate": model.phase = .upToDate; window.show()
        case "ready": model.phase = .ready(offer); window.show()
        case "updated":
            Task { _ = await runtime.attention.post(Self.updatedNotice(UpdateState.Installed(version: offer.version, page: offer.page))) }
        case "check": checkNow()
        default: break
        }
    }
    #endif

    /// A made-up release for the dev commands and the UI snapshots.
    static var sampleOffer: UpdateOffer {
        let base = "https://github.com/ghassenbrg/sidefolk/releases/download/v0.1.0-snapshot.430/"
        return UpdateOffer(
            version: ReleaseVersion("0.1.0-snapshot.430")!, tag: "v0.1.0-snapshot.430", title: "Sidefolk 0.1.0 snapshot 430",
            notes: """
                **What's new**
                - Start a fresh conversation, or go back to an earlier one in Home.
                - Coins and dice land on the desktop, thrown by your companion.
                - Sidefolk looks for updates and asks before installing them.
                """,
            page: URL(string: "https://github.com/ghassenbrg/sidefolk/releases/tag/v0.1.0-snapshot.430")!,
            published: Date(), isSnapshot: true,
            image: UpdateOffer.Asset(name: "Sidefolk-0.1.0-snapshot.430.dmg", size: 23_676_873,
                                     url: URL(string: base + "Sidefolk-0.1.0-snapshot.430.dmg")!),
            checksum: nil)
    }
}
