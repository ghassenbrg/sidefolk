import Foundation
import SidefolkExtensionKit

/// Open-Meteo (free, no account): where a place is, then its weather. The place's name is all that leaves the Mac.
@MainActor
enum Weather {
    static let geocoding = "https://geocoding-api.open-meteo.com/v1/search"
    static let forecastAddress = "https://api.open-meteo.com/v1/forecast"

    /// WMO weather codes, as Open-Meteo reports them.
    static let conditions: [Int: String] = [
        0: "clear", 1: "mostly clear", 2: "partly cloudy", 3: "overcast", 45: "fog", 48: "freezing fog",
        51: "light drizzle", 53: "drizzle", 55: "heavy drizzle", 56: "freezing drizzle", 57: "freezing drizzle",
        61: "light rain", 63: "rain", 65: "heavy rain", 66: "freezing rain", 67: "freezing rain",
        71: "light snow", 73: "snow", 75: "heavy snow", 77: "snow grains", 80: "light showers", 81: "showers",
        82: "violent showers", 85: "snow showers", 86: "heavy snow showers", 95: "thunderstorms",
        96: "thunderstorms with hail", 99: "thunderstorms with hail",
    ]

    static func condition(_ code: Any?) -> String {
        guard let code = (code as? NSNumber)?.intValue else { return "unknown weather" }
        return conditions[code] ?? "weather code \(code)"
    }

    struct Place {
        var latitude: Double
        var longitude: Double
        var label: String
    }

    static func locate(_ place: String) async throws -> Place {
        let found = try await Web.json(Web.url(geocoding, [("name", place), ("count", "1"), ("language", "en"), ("format", "json")]))
        guard let spot = (found["results"] as? [[String: Any]])?.first, let latitude = spot["latitude"] as? Double,
              let longitude = spot["longitude"] as? Double else {
            throw Problem("I couldn't find a place called “\(place)”. Try the nearest city, or add the country.")
        }
        let label = ["name", "admin1", "country"].compactMap { spot[$0] as? String }.filter { !$0.isEmpty }.joined(separator: ", ")
        return Place(latitude: latitude, longitude: longitude, label: label)
    }

    static func forecast(_ place: String, days: Int, imperial: Bool) async throws -> String {
        let spot = try await locate(place)
        var query = [("latitude", "\(spot.latitude)"), ("longitude", "\(spot.longitude)"), ("timezone", "auto"), ("forecast_days", "\(days)"),
                     ("current", "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation"),
                     ("daily", "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max")]
        if imperial { query += [("temperature_unit", "fahrenheit"), ("wind_speed_unit", "mph"), ("precipitation_unit", "inch")] }
        return describe(try await Web.json(Web.url(forecastAddress, query)), label: spot.label)
    }

    /// "Lyon, France, now: light rain, 12°C (feels like 10°C), wind 15 km/h." then a line a day.
    static func describe(_ data: [String: Any], label: String) -> String {
        let units = data["current_units"] as? [String: Any] ?? [:]
        let degree = units["temperature_2m"] as? String ?? "°C"
        let now = data["current"] as? [String: Any] ?? [:]
        func rounded(_ value: Any?) -> String { "\(Int(((value as? NSNumber)?.doubleValue ?? 0).rounded()))" }
        var lines = ["\(label), now: \(condition(now["weather_code"])), \(rounded(now["temperature_2m"]))\(degree) (feels like "
            + "\(rounded(now["apparent_temperature"]))\(degree)), wind \(rounded(now["wind_speed_10m"])) \(units["wind_speed_10m"] as? String ?? "km/h")."]
        let daily = data["daily"] as? [String: Any] ?? [:]
        let days = daily["time"] as? [String] ?? []
        func column(_ name: String) -> [Any] { daily[name] as? [Any] ?? [] }
        for (i, day) in days.enumerated() {
            let name = i == 0 ? "Today" : i == 1 ? "Tomorrow" : day
            let chance = column("precipitation_probability_max")[safe: i].flatMap { ($0 as? NSNumber)?.stringValue } ?? "?"
            lines.append("\(name): \(condition(column("weather_code")[safe: i])), \(rounded(column("temperature_2m_min")[safe: i])) to "
                + "\(rounded(column("temperature_2m_max")[safe: i]))\(degree), \(chance)% chance of rain.")
        }
        return lines.joined(separator: "\n")
    }

    /// Fires once per wet spell: when rain becomes likely within the window, and again only after a dry spell.
    static func rainSoon(place: String, withinHours: Int, chance: Int, state: [String: Any]) async throws -> Check {
        let spot = try await locate(place)
        let data = try await Web.json(Web.url(forecastAddress, [("latitude", "\(spot.latitude)"), ("longitude", "\(spot.longitude)"),
                                                                ("timezone", "auto"), ("hourly", "precipitation_probability"),
                                                                ("forecast_days", "2"), ("current", "weather_code")]))
        return rainCheck(data, label: spot.label, withinHours: withinHours, chance: chance, state: state)
    }

    static func rainCheck(_ data: [String: Any], label: String, withinHours: Int, chance: Int, state: [String: Any]) -> Check {
        // "2026-10-26T14": the current hour, in local time where the place is; earlier hours never count.
        let hour = String(((data["current"] as? [String: Any])?["time"] as? String ?? "").prefix(13))
        let hourly = data["hourly"] as? [String: Any] ?? [:]
        let times = hourly["time"] as? [String] ?? [], chances = hourly["precipitation_probability"] as? [Any] ?? []
        let ahead = zip(times, chances).compactMap { time, p -> (String, Int)? in
            guard String(time.prefix(13)) >= hour, let p = (p as? NSNumber)?.intValue else { return nil }
            return (time, p)
        }.prefix(withinHours)
        guard let (when, probability) = ahead.first(where: { $0.1 >= chance }) else {
            return Check(triggered: false, state: ["wet": false], summary: "No rain likely in \(label) in the next \(withinHours) hours.")
        }
        let at = when.dropFirst(11).prefix(5)
        return Check(triggered: state["wet"] as? Bool != true, state: ["wet": true],
                     summary: "Rain is likely in \(label) around \(at) (\(probability)% chance).")
    }

    /// Sunrise, sunset and daylight from Open-Meteo; the moon worked out here.
    static func sunAndMoon(_ place: String, now: Date = Date()) async throws -> String {
        let spot = try await locate(place)
        let data = try await Web.json(Web.url(forecastAddress, [("latitude", "\(spot.latitude)"), ("longitude", "\(spot.longitude)"),
                                                                ("timezone", "auto"), ("forecast_days", "1"),
                                                                ("daily", "sunrise,sunset,daylight_duration")]))
        let daily = data["daily"] as? [String: Any] ?? [:]
        func first(_ name: String) -> Any? { (daily[name] as? [Any])?.first }
        let rise = (first("sunrise") as? String)?.dropFirst(11).prefix(5), set = (first("sunset") as? String)?.dropFirst(11).prefix(5)
        let light = Int(((first("daylight_duration") as? NSNumber)?.doubleValue ?? 0) / 60)
        guard let rise, let set else { throw Problem("Open-Meteo didn't give sunrise and sunset for \(spot.label).") }
        return "\(spot.label): sunrise \(rise), sunset \(set), \(light / 60) h \(String(format: "%02d", light % 60)) of daylight. " + moon(at: now)
    }

    /// The moon's phase from its age since a known new moon (6 January 2000, 18:14 UTC).
    static func moon(at moment: Date) -> String {
        let month = 29.530588853
        let age = (moment.timeIntervalSince1970 - 947_182_440) / 86_400
        let day = (age.truncatingRemainder(dividingBy: month) + month).truncatingRemainder(dividingBy: month)
        let lit = Int(((1 - cos(2 * Double.pi * day / month)) / 2 * 100).rounded())
        let names = ["new moon", "waxing crescent", "first quarter", "waxing gibbous", "full moon", "waning gibbous", "last quarter",
                     "waning crescent"]
        let name = names[Int((day / month * 8 + 0.5).rounded(.down)) % 8]
        return "The moon is a \(name), \(lit)% lit."
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
