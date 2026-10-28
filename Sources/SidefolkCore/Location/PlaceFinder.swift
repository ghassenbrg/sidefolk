import Foundation

/// Finds a town by its name for "A place I choose" (Settings › Privacy › Your location), with Open-Meteo's geocoding:
/// free, no key, no account, and the same service the weather already asks. The typed name is all it sends.
public struct PlaceFinder: Sendable {
    static let endpoint = "https://geocoding-api.open-meteo.com/v1/search"
    let fetcher: any WatchFetcher

    public init(fetcher: any WatchFetcher = WatchSessionFetcher()) {
        self.fetcher = fetcher
    }

    /// Up to ten places, best match first. "Portland, Oregon" keeps the ones whose state or country starts that way.
    public func search(_ text: String, now: Date = Date()) async throws -> [KnownPlace] {
        let parts = text.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = parts.first, name.count >= 2, WeatherProbe.cleanPlace(name) != nil else {
            throw UserFacingError("Type the name of a town or city, like Fukuoka or Austin, Texas.")
        }
        var url = URLComponents(string: Self.endpoint)!
        url.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "10"),
                          URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        let response: FetchResponse
        do {
            response = try await fetcher.fetch(FetchRequest(url: url.url!))
        } catch {
            throw UserFacingError("I couldn't reach the place search. Check the internet connection and try again.",
                                  detail: String(describing: error))
        }
        guard (200..<300).contains(response.status), let json = try? JSONValue.parse(response.body) else {
            throw UserFacingError("The place search didn't answer properly. Try again in a moment.")
        }
        let region = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        return Self.places(from: json, region: region, now: now)
    }

    /// Open-Meteo's results as places, without duplicates; with `region`, only those it fits.
    static func places(from json: JSONValue, region: String? = nil, now: Date) -> [KnownPlace] {
        var found: [KnownPlace] = []
        for r in json["results"]?.arrayValue ?? [] {
            guard let lat = r["latitude"]?.doubleValue, let lon = r["longitude"]?.doubleValue,
                  let place = KnownPlace(city: r.string("name") ?? "", region: r.string("admin1"), country: r.string("country"),
                                         countryCode: r.string("country_code"), latitude: lat, longitude: lon,
                                         timeZone: r.string("timezone"), updatedAt: now) else { continue }
            if let region, ![place.region, place.country, place.countryCode].contains(where: { $0.map { Self.starts($0, with: region) } == true }) {
                continue
            }
            guard !found.contains(where: { $0.fullName == place.fullName }) else { continue }
            found.append(place)
        }
        return found
    }

    private static func starts(_ text: String, with prefix: String) -> Bool {
        text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}
