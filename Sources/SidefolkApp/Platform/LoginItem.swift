import ServiceManagement
import SidefolkCore

/// "Open at login" through the system's login items (no helper, no admin rights).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) -> UserFacingError? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return UserFacingError("macOS wants you to approve Sidefolk in Login Items.",
                                       recovery: "System Settings is open — switch Sidefolk on there.", detail: String(describing: error))
            }
            return UserFacingError(on ? "I couldn't add myself to your login items." : "I couldn't remove myself from your login items.",
                                   recovery: "You can change it in System Settings › General › Login Items.",
                                   detail: String(describing: error))
        }
    }
}
