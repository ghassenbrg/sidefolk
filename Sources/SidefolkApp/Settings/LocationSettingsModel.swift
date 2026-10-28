import Foundation
import Observation
import SidefolkCore

/// Settings › Privacy › Your location (D48): off, the Mac's location, or a town chosen by name. Every control changes
/// something real; macOS asks about the Mac's location only when the person picks it.
@MainActor @Observable
final class LocationSettingsModel {
    private unowned let parent: SettingsModel
    private var services: any LocationServices { parent.services.locationServices }

    private(set) var access: MacLocationAccess = .notAsked
    var query = ""
    private(set) var results: [KnownPlace] = []
    private(set) var searching = false
    /// The last search found nothing.
    private(set) var foundNothing = false
    private(set) var searchError: UserFacingError?
    /// Settings should bring this group into view (a card's button that asks where the person is).
    var reveal = false

    init(parent: SettingsModel) {
        self.parent = parent
    }

    var settings: LocationSettings { parent.settings.location }

    func refresh() {
        access = services.macLocation
        services.onAccessChange = { [weak self] in
            guard let self else { return }
            access = services.macLocation
        }
    }

    func choose(_ source: LocationSettings.Source) {
        guard source != settings.source else { return }
        // A place from one source never passes for another's: choosing starts empty.
        parent.update { $0.location = LocationSettings(source: source) }
        clearSearch()
        if source == .mac { services.useMacLocation() } else { services.stopMacLocation() }
        access = services.macLocation
    }

    /// Asks macOS again (the person had not answered) or follows the Mac's location now that it is allowed.
    func useMacLocation() {
        services.useMacLocation()
        access = services.macLocation
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        searchError = nil
        foundNothing = false
        switch await services.searchPlaces(text) {
        case .success(let places):
            results = places
            foundNothing = places.isEmpty
        case .failure(let error):
            results = []
            searchError = error
        }
        searching = false
    }

    func pick(_ place: KnownPlace) {
        parent.update { $0.location = LocationSettings(source: .chosen, place: place) }
        clearSearch()
    }

    func openSystemSettings() { services.openLocationSettings() }

    private func clearSearch() {
        query = ""
        results = []
        foundNothing = false
        searchError = nil
    }
}
