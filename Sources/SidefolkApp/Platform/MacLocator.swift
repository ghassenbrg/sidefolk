import AppKit
import CoreLocation
import MapKit
import SidefolkCore

/// Whether Sidefolk may use the Mac's location. Reading it never asks; choosing "Use my Mac's location" does.
enum MacLocationAccess: Equatable {
    case allowed, notAsked, denied
}

/// What Settings › Privacy › Your location reads and does: the app's side, or fixtures in snapshots.
@MainActor
protocol LocationServices: AnyObject {
    var macLocation: MacLocationAccess { get }
    /// Called when macOS's answer about the Mac's location changes (the person answered, or changed it in System Settings).
    var onAccessChange: (@MainActor () -> Void)? { get set }
    /// Follows the Mac's location; macOS asks the person the first time. Only ever from their own choice.
    func useMacLocation()
    func stopMacLocation()
    func searchPlaces(_ text: String) async -> Result<[KnownPlace], UserFacingError>
    /// System Settings › Privacy & Security › Location Services.
    func openLocationSettings()
}

/// Follows the Mac's location while the person shares it (D48): a city's accuracy and significant changes only (from
/// Wi-Fi, at little cost), named by Apple's geocoder and kept by `PlaceKeeper`. No position is asked for unless they
/// chose the Mac's location; at launch it resumes only what macOS already allowed, so it never asks on its own.
@MainActor
final class MacLocator: NSObject, LocationServices, CLLocationManagerDelegate {
    private let runtime: SidefolkRuntime
    private let keeper: PlaceKeeper
    private var manager: CLLocationManager?
    var onAccessChange: (@MainActor () -> Void)?

    init(runtime: SidefolkRuntime) {
        self.runtime = runtime
        keeper = PlaceKeeper(settings: runtime.settings, geocoder: AppleGeocoder(), clock: runtime.clock)
    }

    var macLocation: MacLocationAccess {
        switch locationManager.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        default: .allowed
        }
    }

    func useMacLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            // The answer comes to `locationManagerDidChangeAuthorization`, which starts following.
            locationManager.requestWhenInUseAuthorization()
        } else {
            follow()
        }
    }

    func stopMacLocation() {
        manager?.stopMonitoringSignificantLocationChanges()
    }

    /// At launch: follows again when the person chose the Mac's location and macOS allowed it before.
    func resume() {
        guard runtime.settings.current.location.source == .mac, macLocation == .allowed else { return }
        follow()
    }

    func searchPlaces(_ text: String) async -> Result<[KnownPlace], UserFacingError> {
        do {
            return .success(try await PlaceFinder().search(text))
        } catch {
            return .failure(AppCoordinator.userFacing(error, fallback: String(localized: "I couldn't search for that place.")))
        }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Core Location

    /// Made on first use: creating one doesn't ask the person anything, and its callbacks come on the main thread.
    private var locationManager: CLLocationManager {
        if let manager { return manager }
        let made = CLLocationManager()
        made.delegate = self
        made.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        made.distanceFilter = 1_000
        manager = made
        return made
    }

    /// Only called when the person's choice is the Mac's location (their click, or the choice found at launch).
    private func follow() {
        guard macLocation == .allowed else { return }
        locationManager.startMonitoringSignificantLocationChanges()
        // One position now: significant changes only come when the Mac moves.
        locationManager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // Also called once when the manager is made; it follows only when that is the person's choice.
            if runtime.settings.current.location.source == .mac { follow() }
            onAccessChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let fix = LocationFix(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude, at: last.timestamp)
        Task { await keeper.received(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // No position this time (no Wi-Fi, or the person said no); significant changes keep coming when they can.
        Log.shared.info("location", "no position", ["code": String((error as NSError).code)])
    }
}

/// Names a position with Apple's geocoder (MapKit from macOS 26, Core Location before), in English like every place
/// Sidefolk keeps, so the AI and the weather lookups read one name.
struct AppleGeocoder: ReverseGeocoding {
    func place(latitude: Double, longitude: Double, now: Date) async throws -> KnownPlace? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let english = Locale(identifier: "en_US")
        if #available(macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            request.preferredLocale = english
            guard let item = try await request.mapItems.first, let address = item.addressRepresentations,
                  let city = address.cityName else { return nil }
            // "Austin, TX": what follows the city is its state or province, when it has one.
            let region = address.cityWithContext(.short)?.split(separator: ",").dropFirst().first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return KnownPlace(city: city, region: region, country: address.regionName, countryCode: address.region?.identifier,
                              latitude: latitude, longitude: longitude, timeZone: item.timeZone?.identifier, updatedAt: now)
        }
        guard let mark = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: english).first,
              let city = mark.locality ?? mark.subAdministrativeArea else { return nil }
        return KnownPlace(city: city, region: mark.administrativeArea, country: mark.country, countryCode: mark.isoCountryCode,
                          latitude: latitude, longitude: longitude, timeZone: mark.timeZone?.identifier, updatedAt: now)
    }
}
