import Foundation

/// Where the person is, when they let Sidefolk know (D48): a town or city, never an address.
public struct KnownPlace: Codable, Sendable, Hashable {
    public var city: String
    /// The state, prefecture or province, when it says more than the city does.
    public var region: String?
    public var country: String?
    /// "JP".
    public var countryCode: String?
    /// Rounded to two decimals (about a kilometre). Only weather lookups use them (Open-Meteo, as for any place);
    /// they never reach an AI, a log or the diagnostics.
    public var latitude: Double
    public var longitude: Double
    /// The place's own time zone, when the lookup gave one ("Asia/Tokyo").
    public var timeZone: String?
    public var updatedAt: Date

    /// Names are held to the rule place names follow everywhere (`WeatherProbe.cleanPlace`): they come from a geocoder
    /// and end up in the AI's context, so nothing but a name gets through. Nil when the city isn't one.
    public init?(city: String, region: String? = nil, country: String? = nil, countryCode: String? = nil,
                 latitude: Double, longitude: Double, timeZone: String? = nil, updatedAt: Date) {
        guard let city = WeatherProbe.cleanPlace(city), latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        self.city = city
        self.region = WeatherProbe.cleanPlace(region)
        self.country = WeatherProbe.cleanPlace(country)
        self.countryCode = countryCode.flatMap { $0.count == 2 && $0.allSatisfy(\.isLetter) ? $0.uppercased() : nil }
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
        self.timeZone = timeZone.flatMap { TimeZone(identifier: $0)?.identifier }
        self.updatedAt = updatedAt
    }

    /// "Fukuoka, Japan": how the person, the AI and the weather lookups name it.
    public var name: String { [city, country].compactMap { $0 }.joined(separator: ", ") }

    /// "Austin, Texas, United States", without the repeats of "Tokyo, Tokyo, Japan".
    public var fullName: String {
        var parts: [String] = []
        for part in [city, region, country].compactMap({ $0 }) where !parts.contains(where: { Self.same($0, part) }) {
            parts.append(part)
        }
        return parts.joined(separator: ", ")
    }

    /// Whether `words` name this place: its name, its full name or its city, in any case and with or without accents.
    public func isNamed(by words: String) -> Bool {
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, fullName, city].contains { Self.same($0, w) }
    }

    /// Metres between this place and a position, along the Earth's surface.
    public func distance(toLatitude lat: Double, longitude lon: Double) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (lat - latitude) * rad, dLon = (lon - longitude) * rad
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(latitude * rad) * cos(lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Whether Sidefolk knows where the person is, and from where (D48). Off unless they choose: nothing about where
/// they are goes anywhere until then.
public struct LocationSettings: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        case off
        /// Location Services, at the accuracy of a city; macOS asks the person the first time.
        case mac
        /// A town they picked by name in Settings.
        case chosen
    }

    public var source: Source = .off
    /// The place last known. Cleared when the source changes, so a place from one never passes for the other.
    public var place: KnownPlace?

    public init(source: Source = .off, place: KnownPlace? = nil) {
        self.source = source
        self.place = place
    }

    /// The place to use, when the person shares one.
    public var current: KnownPlace? { source == .off ? nil : place }
}
