import Foundation

/// A position from Location Services, at the accuracy of a city.
public struct LocationFix: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var at: Date

    public init(latitude: Double, longitude: Double, at: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.at = at
    }
}

/// Names a position: Apple's geocoder in the app, a fake in tests.
public protocol ReverseGeocoding: Sendable {
    func place(latitude: Double, longitude: Double, now: Date) async throws -> KnownPlace?
}

/// Keeps the person's place current while they share their Mac's location (D48). A position is named again only when
/// it is somewhere else (more than 5 km away) or the name is a day old, and at most once every 10 minutes: Wi-Fi
/// positions wobble, and the geocoder is Apple's to be polite to. The place is saved in settings, the one place it
/// lives; the log says that it changed, never where.
public actor PlaceKeeper {
    static let moved: Double = 5_000
    static let stale: TimeInterval = 86_400
    static let spacing: TimeInterval = 600

    private let settings: SettingsStore
    private let geocoder: any ReverseGeocoding
    private let clock: any Clock
    private var lastLookup: Date?

    public init(settings: SettingsStore, geocoder: any ReverseGeocoding, clock: any Clock = SystemClock()) {
        self.settings = settings
        self.geocoder = geocoder
        self.clock = clock
    }

    /// Takes a new position; true when the place it names was saved.
    @discardableResult
    public func received(_ fix: LocationFix) async -> Bool {
        let location = settings.current.location
        guard location.source == .mac else { return false }
        let now = clock.now
        if let known = location.place, known.distance(toLatitude: fix.latitude, longitude: fix.longitude) < Self.moved,
           now.timeIntervalSince(known.updatedAt) < Self.stale {
            return false
        }
        if let lastLookup, now.timeIntervalSince(lastLookup) < Self.spacing { return false }
        lastLookup = now
        let named: KnownPlace?
        do {
            named = try await geocoder.place(latitude: fix.latitude, longitude: fix.longitude, now: now)
        } catch {
            Log.shared.info("location", "naming the place failed", ["error": String(describing: type(of: error))])
            return false
        }
        guard var place = named else { return false }
        place.updatedAt = now
        let found = place
        // The person may have switched it off while the geocoder answered.
        await settings.update { s in
            if s.location.source == .mac { s.location.place = found }
        }
        let saved = settings.current.location.place == found
        if saved { Log.shared.info("location", "place updated") }
        return saved
    }
}
