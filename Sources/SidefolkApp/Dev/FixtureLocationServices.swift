#if DEBUG
import Foundation
import SidefolkCore

/// Settings › Privacy › Your location with sample answers, for snapshots: no Location Services, prompt or network.
@MainActor
final class FixtureLocationServices: LocationServices {
    var macLocation = MacLocationAccess.notAsked
    var onAccessChange: (@MainActor () -> Void)?

    func useMacLocation() {}
    func stopMacLocation() {}

    func searchPlaces(_ text: String) async -> Result<[KnownPlace], UserFacingError> {
        .success(Self.samples.filter { $0.city.localizedCaseInsensitiveContains(text) })
    }

    func openLocationSettings() {}

    nonisolated static let fukuoka = KnownPlace(city: "Fukuoka", region: "Fukuoka", country: "Japan", countryCode: "JP", latitude: 33.6,
                                                longitude: 130.42, timeZone: "Asia/Tokyo", updatedAt: Date().addingTimeInterval(-3600))!
    nonisolated static let samples = [
        fukuoka,
        KnownPlace(city: "Portland", region: "Oregon", country: "United States", countryCode: "US", latitude: 45.52,
                   longitude: -122.68, timeZone: "America/Los_Angeles", updatedAt: Date())!,
        KnownPlace(city: "Portland", region: "Maine", country: "United States", countryCode: "US", latitude: 43.66,
                   longitude: -70.26, timeZone: "America/New_York", updatedAt: Date())!,
    ]
}
#endif
