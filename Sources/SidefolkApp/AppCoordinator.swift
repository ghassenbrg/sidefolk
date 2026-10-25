import AppKit
import KeyboardShortcuts
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
    private var mood = CompanionMood()
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
            self?.renderMood()
        }

        bubbles.anchorProvider = { [weak self] in self?.anchor() }
        bubbles.onRespond = { [weak self] item, action in self?.respond(to: item, action: action) }

        statusItem.install(image: nil)
        statusItem.onAsk = { [weak self] in self?.toggleAsk() }
        statusItem.onOpenHome = { [weak self] in self?.openHome() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onQuiet = { [weak self] seconds in self?.setQuiet(for: seconds) }
        statusItem.isQuiet = { [weak self] in self?.runtime.settings.current.isQuiet(at: Date()) ?? false }
        statusItem.hotkeyLabel = { [weak self] in self?.hotkeyLabel ?? "" }

        KeyboardShortcuts.onKeyUp(for: .ask) { [weak self] in self?.toggleAsk() }

        notifier.configure()
        monitor.start()
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
        Log.shared.info("app", "ready")
    }

    func prepareForQuit() {
        eventTask?.cancel()
    }

    // MARK: Windows

    var hotkeyLabel: String {
        KeyboardShortcuts.getShortcut(for: .ask)?.description ?? "⌘⇧Space"
    }

    /// The companion's frame and screen, which panels and bubbles attach to.
    func anchor() -> (NSRect, NSScreen)? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let v = screen.visibleFrame
        return (NSRect(x: v.maxX - 110, y: v.minY + 12, width: 90, height: 90), screen)
    }

    func toggleAsk() {
        if askPanel.isVisible { askPanel.hide(); return }
        showAsk()
    }

    func showAsk() {
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
            bubbles.setBacklog(count)
            statusItem.setBadge(count)
        case .approvalRequested(let request):
            ask.add(.approval(request))
            if !askPanel.isVisible { showAsk() }
        case .approvalResolved(let id, _):
            ask.removeApproval(id: id)
        case .dataChanged:
            statusItem.refreshNow()
        default:
            break
        }
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        switch presentation {
        case .ambient:
            break
        case .gentle, .attention:
            bubbles.present(item, presentation)
        case .system(let sound, let alsoOnDesktop):
            notifier.show(item, sound: sound)
            if alsoOnDesktop { bubbles.present(item, .attention(expandFor: AttentionPolicy.expandSeconds)) }
        }
    }

    private func respond(to item: AttentionItem, action: String?) {
        if action == "open", item.source == "summary" { openHome() }
        Task { await runtime.attention.respond(id: item.id, actionId: action) }
    }

    private func renderMood() {
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
