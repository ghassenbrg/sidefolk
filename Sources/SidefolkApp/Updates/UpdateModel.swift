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
        /// Downloaded, checked and beside the app, waiting for a calm moment to restart (D70).
        case ready(UpdateOffer)
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

    // Add-ons from the gallery (D70), kept by `AddonUpdateController`.
    /// Extension updates that would let one do more: they wait for the person's look in the install sheet.
    var addonReview: [AddonEntry] = []
    /// Updates left for the person while add-ons don't update by themselves.
    var addonWaiting: [AddonEntry] = []
    /// The names of what the last look updated by itself, and when.
    var addonsUpdated: [String] = []
    var addonsUpdatedAt: Date?
    /// A look or an Update All is under way.
    var addonsBusy = false
    @ObservationIgnored weak var addonActions: AddonUpdateActions?

    /// The offer the phase is about, if any.
    var offer: UpdateOffer? {
        switch phase {
        case .available(let o), .ready(let o), .downloading(let o, _, _), .verifying(let o), .installing(let o), .restarting(let o),
             .downloaded(let o, _, _):
            o
        case .failed(let o, _):
            o
        case .idle, .checking, .upToDate:
            nil
        }
    }

    /// The version waiting for a calm moment, if one is (D70).
    var readyOffer: UpdateOffer? {
        if case .ready(let o) = phase { return o }
        return nil
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
    /// Puts a version that is ready (D70) in place now and restarts.
    func restartNow()
    func skip(_ offer: UpdateOffer)
    /// Closes the window; the offer stays in the menu and in Settings.
    func later()
    func cancel()
    func reveal(_ file: URL)
    func openPage(_ offer: UpdateOffer)
}

/// What Settings › Updates can ask of the add-on updates (D70).
@MainActor
protocol AddonUpdateActions: AnyObject {
    /// Installs every waiting update the rule allows now; those that would do more open for review.
    func updateAddonsNow()
    /// Fetches an extension's update and opens the install sheet, which says what is new.
    func review(_ entry: AddonEntry)
}
