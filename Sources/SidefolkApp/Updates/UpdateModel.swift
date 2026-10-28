import Foundation
import SidefolkCore

/// What Settings, the menu bar and the update window show about updates (D46). `UpdateController` keeps it.
@MainActor @Observable
final class UpdateModel {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateOffer)
        case downloading(UpdateOffer, received: Int64, total: Int64)
        case verifying(UpdateOffer)
        case installing(UpdateOffer)
        case restarting(UpdateOffer)
        /// The checked disk image is in Downloads: this copy can't replace itself, for the reason given.
        case downloaded(UpdateOffer, URL, InstallPlan.Reason)
        case failed(UpdateOffer?, UserFacingError)
    }

    var phase: Phase = .idle
    var lastCheck: Date?
    /// "0.1.0 snapshot 411" or, for a copy built on this Mac, "0.1.0 (built on this Mac)".
    var running = ""
    /// What offers are compared with (`RunningApp.version`).
    var version = ReleaseVersion(SidefolkVersion.current)!
    /// A published release: it looks by itself. A copy built on this Mac looks only when asked.
    var published = true
    var plan: InstallPlan = .replace
    @ObservationIgnored weak var actions: UpdateActions?

    /// The offer the phase is about, if any.
    var offer: UpdateOffer? {
        switch phase {
        case .available(let o), .downloading(let o, _, _), .verifying(let o), .installing(let o), .restarting(let o),
             .downloaded(let o, _, _):
            o
        case .failed(let o, _):
            o
        case .idle, .checking, .upToDate:
            nil
        }
    }

    /// Downloading, checking or installing: the window's Cancel stops it, and nothing else may start.
    var busy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .installing, .restarting: true
        default: false
        }
    }
}

/// What the update window and Settings can ask for.
@MainActor
protocol UpdateActions: AnyObject {
    /// Looks now and shows what it found in the update window.
    func checkNow()
    /// Shows the update window as it stands (the menu's "Update to …").
    func showUpdates()
    func install(_ offer: UpdateOffer)
    func skip(_ offer: UpdateOffer)
    /// Closes the window; the offer stays in the menu and in Settings.
    func later()
    func cancel()
    func reveal(_ file: URL)
    func openPage(_ offer: UpdateOffer)
}
