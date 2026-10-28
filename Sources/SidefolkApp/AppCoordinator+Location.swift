import AppKit
import SidefolkCore

/// Where the person is (D48): Settings' side of it, and the way there from a card that asked which place.
extension AppCoordinator {
    var locationServices: any LocationServices { locator }

    /// Opens a page of Sidefolk's own Settings a result pointed to.
    func open(_ link: SettingsLink) {
        askPanel.hide()
        switch link {
        case .yourLocation: settingsWindow.showYourLocation()
        }
    }
}
