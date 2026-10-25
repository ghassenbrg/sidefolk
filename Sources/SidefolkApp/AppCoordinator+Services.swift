import AppKit
import SidefolkCore

extension AppCoordinator {
    // MARK: App

    var openAtLogin: Bool { LoginItem.isEnabled }

    func setOpenAtLogin(_ on: Bool) -> UserFacingError? { LoginItem.set(on) }

    func notificationsAuthorized() async -> Bool {
        let status = await notifier.authorizationStatus()
        let allowed = status == .authorized || status == .provisional
        await runtime.attention.update { $0.systemNotificationsAllowed = allowed }
        return allowed
    }

    func requestNotifications() async {
        _ = await notifier.requestAuthorization()
        _ = await notificationsAuthorized()
    }

    // MARK: Integrations

    /// Where the `sidefolk` helper lives inside the running app bundle.
    var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sidefolk").path
    }

    func integrationStatus() async -> IntegrationStatus {
        let claude = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .map { ($0 as NSString).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        return IntegrationStatus(claudeCodeFound: claude != nil, claudeMCPInstalled: false, claudeHooksInstalled: false,
                                 codexFound: false, codexMCPInstalled: false, cliLinked: false, helperPath: helperPath)
    }

    func connectClaudeCode(hooks: Bool) async -> UserFacingError? {
        UserFacingError("Connecting Claude Code isn't available in this build yet.")
    }
}
