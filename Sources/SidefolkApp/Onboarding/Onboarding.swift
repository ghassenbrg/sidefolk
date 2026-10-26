import AppKit
import SidefolkCore

/// First run happens on the desktop, through the companion — no wizard (DECISIONS D4, PRODUCT §5).
/// Each step is one bubble; Esc/× skips the step, nothing blocks using Sidefolk meanwhile.
final class Onboarding {
    enum Step: CaseIterable { case hello, tryReminder, notifications, agents, login, done }

    private unowned let coordinator: AppCoordinator
    private(set) var step: Step?
    private var waitingForReminder = false

    init(coordinator: AppCoordinator) { self.coordinator = coordinator }

    static let source = "onboarding"

    func start() {
        step = .hello
        show(.hello)
    }

    var isRunning: Bool { step != nil }

    /// Bubble answers for onboarding items arrive here instead of the attention center.
    func respond(action: String?) {
        guard let step else { return }
        switch (step, action) {
        case (.hello, "skip"):
            finish()
        case (.hello, _):
            advance(to: .tryReminder)
        case (.tryReminder, "show"):
            waitingForReminder = true
            coordinator.showAsk(prefill: "remind me in 2 minutes to stretch")
        case (.tryReminder, _):
            advance(to: .notifications)
        case (.notifications, "allow"):
            Task {
                await coordinator.requestNotifications()
                advance(to: .agents)
            }
        case (.notifications, _):
            advance(to: .agents)
        case (.agents, "connect"):
            Task {
                let status = await coordinator.integrationStatus()
                if status.claudeCodeFound { _ = await coordinator.connectClaudeCode(hooks: true) }
                if status.codexFound, !status.codexMCPInstalled { _ = await coordinator.connectCodex() }
                advance(to: .login)
            }
        case (.agents, _):
            advance(to: .login)
        case (.login, "yes"):
            _ = coordinator.setOpenAtLogin(true)
            advance(to: .done)
        case (.login, _):
            advance(to: .done)
        case (.done, _):
            finish()
        }
    }

    /// The first reminder made during onboarding moves things along.
    func reminderCreated() {
        guard waitingForReminder, step == .tryReminder else { return }
        waitingForReminder = false
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            advance(to: .notifications)
        }
    }

    private func advance(to next: Step) {
        Task {
            var target = next
            if target == .notifications, await coordinator.notificationsAuthorized() { target = .agents }
            if target == .agents {
                let status = await coordinator.integrationStatus()
                let claudeDone = !status.claudeCodeFound || status.claudeHooksInstalled
                let codexDone = !status.codexFound || status.codexMCPInstalled
                if claudeDone && codexDone { target = .login }
            }
            if target == .login, coordinator.openAtLogin { target = .done }
            step = target
            show(target)
        }
    }

    private func finish() {
        step = nil
        Task { await coordinator.runtime.settings.update { $0.onboardingDone = true } }
    }

    private func show(_ step: Step) {
        let name = coordinator.runtime.settings.current.companionName
        let item: AttentionItem
        switch step {
        case .hello:
            item = bubble("Hi, I'm \(name).", "I'll sit down here and keep track of things for you: notes, reminders, and things to watch.",
                          [("hi", "Hi \(name)", true), ("skip", "Skip intro", false)])
        case .tryReminder:
            item = bubble("Give me something to remember.", "Click me or press \(coordinator.hotkeyLabel). Try a reminder: no AI needed.",
                          [("show", "Show me", true), ("later", "Not now", false)])
        case .notifications:
            item = bubble("Can I use Mac notifications?", "Only when I'm hidden, you're in fullscreen, or something is urgent.",
                          [("allow", "Allow notifications", true), ("later", "Not now", false)])
        case .agents:
            item = bubble("Want a tap when your coding agents need you?",
                          "I'll add myself to Claude Code and Codex. You'll see exactly what changes, and I keep a backup.",
                          [("connect", "Connect…", true), ("later", "Not now", false)])
        case .login:
            item = bubble("Start me when you log in?", "Reminders and watches only work while I'm running.",
                          [("yes", "Start at login", true), ("no", "Not now", false)])
        case .done:
            item = bubble("That's it.", "Ask “what did I save about…” any time. Drop files or links on me, double-click me for your notebook, or find me in the menu bar.",
                          [("ok", "Got it", true)])
        }
        coordinator.presentLocal(item)
    }

    private func bubble(_ title: String, _ body: String, _ actions: [(String, String, Bool)]) -> AttentionItem {
        AttentionItem(level: .attention, source: Self.source, title: title, body: body,
                      actions: actions.map { AttentionAction(id: $0.0, title: $0.1, isPrimary: $0.2) })
    }
}
