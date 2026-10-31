import Foundation
import SidefolkExtensionKit

/// Open-Meteo (free, no account): where a place is, then its weather. The place's name is all that leaves the Mac.
@MainActor
enum Weather {
    static let geocoding = "https://geocoding-api.open-meteo.com/v1/search"
    static let forecastAddress = "https://api.open-meteo.com/v1/forecast"

    /// WMO weather codes, as Open-Meteo reports them, in the person's language.
    static var conditions: [Int: String] {
        [
            0: L("clear"), 1: L("mostly clear"), 2: L("partly cloudy"), 3: L("overcast"), 45: L("fog"), 48: L("freezing fog"),
            51: L("light drizzle"), 53: L("drizzle"), 55: L("heavy drizzle"), 56: L("freezing drizzle"), 57: L("freezing drizzle"),
            61: L("light rain"), 63: L("rain"), 65: L("heavy rain"), 66: L("freezing rain"), 67: L("freezing rain"),
            71: L("light snow"), 73: L("snow"), 75: L("heavy snow"), 77: L("snow grains"), 80: L("light showers"), 81: L("showers"),
            82: L("violent showers"), 85: L("snow showers"), 86: L("heavy snow showers"), 95: L("thunderstorms"),
            96: L("thunderstorms with hail"), 99: L("thunderstorms with hail"),
        ]
    }

    static func condition(_ code: Any?) -> String {
        guard let code = (code as? NSNumber)?.intValue else { return L("unknown weather") }
        return conditions[code] ?? L("weather code {code}", ["code": String(code)])
    }

    struct Place {
        var latitude: Double
        var longitude: Double
        var label: String
    }

    /// "Fukuoka, Japan" or "Portland, Oregon": the geocoder only knows names, so the words after the first comma pick
    /// among the places of that name. The person's own place reaches the model written that way (D48).
    static func locate(_ place: String) async throws -> Place {
        let parts = place.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let found = try await Web.json(Web.url(geocoding, [("name", parts.first ?? place), ("count", parts.count > 1 ? "10" : "1"),
                                                           ("language", "en"), ("format", "json")]))
        guard let spot = pick(found["results"] as? [[String: Any]] ?? [], within: parts.count > 1 ? parts[1] : nil),
              let latitude = spot["latitude"] as? Double, let longitude = spot["longitude"] as? Double else {
            throw Problem(L("I couldn't find a place called “{place}”. Try the nearest city, or add the country.", ["place": place]))
        }
        let label = ["name", "admin1", "country"].compactMap { spot[$0] as? String }.filter { !$0.isEmpty }.joined(separator: ", ")
        return Place(latitude: latitude, longitude: longitude, label: label)
    }

    /// The first result, or with `region` ("Oregon", "Fukuoka, Japan", "US") the first whose state, country or country
    /// code starts like one of its parts.
    nonisolated static func pick(_ results: [[String: Any]], within region: String?) -> [String: Any]? {
        guard let region else { return results.first }
        let wanted = region.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        return results.first { r in
            ["admin1", "country", "country_code"].contains { key in
                guard let value = (r[key] as? String)?.lowercased() else { return false }
                return wanted.contains { value.hasPrefix($0) }
            }
        }
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
        var lines = [L("{place}, now: {weather}, {temperature} (feels like {feels}), wind {wind}.", [
            "place": label, "weather": condition(now["weather_code"]), "temperature": rounded(now["temperature_2m"]) + degree,
            "feels": rounded(now["apparent_temperature"]) + degree,
            "wind": rounded(now["wind_speed_10m"]) + " " + (units["wind_speed_10m"] as? String ?? "km/h"),
        ])]
        let daily = data["daily"] as? [String: Any] ?? [:]
        let days = daily["time"] as? [String] ?? []
        func column(_ name: String) -> [Any] { daily[name] as? [Any] ?? [] }
        for (i, day) in days.enumerated() {
            let name = i == 0 ? L("Today") : i == 1 ? L("Tomorrow") : Self.day(day)
            let chance = column("precipitation_probability_max")[safe: i].flatMap { ($0 as? NSNumber)?.doubleValue }
            lines.append(L("{day}: {weather}, {low} to {high}, {chance} chance of rain.", [
                "day": name, "weather": condition(column("weather_code")[safe: i]), "low": rounded(column("temperature_2m_min")[safe: i]),
                "high": rounded(column("temperature_2m_max")[safe: i]) + degree, "chance": chance.map { Format.percent(points: $0) } ?? "?%",
            ]))
        }
        return lines.joined(separator: "\n")
    }

    /// "Wed 28 Oct" for Open-Meteo's "2026-10-28", in the person's language (the day as it is there).
    static func day(_ iso: String) -> String {
        let read = DateFormatter()
        read.locale = Locale(identifier: "en_US_POSIX")
        read.timeZone = TimeZone(identifier: "UTC")
        read.dateFormat = "yyyy-MM-dd"
        guard let date = read.date(from: iso) else { return iso }
        return Format.date(date, weekday: true, timeZone: TimeZone(identifier: "UTC")!)
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
            return Check(triggered: false, state: ["wet": false],
                         summary: L(one: "No rain likely in {place} in the next hour.", other: "No rain likely in {place} in the next {count} hours.",
                                    count: withinHours, ["place": label]))
        }
        let at = when.dropFirst(11).prefix(5)
        return Check(triggered: state["wet"] as? Bool != true, state: ["wet": true],
                     summary: L("Rain is likely in {place} around {time} ({chance} chance).",
                                ["place": label, "time": String(at), "chance": Format.percent(points: Double(probability))]))
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
        guard let rise, let set else { throw Problem(L("Open-Meteo didn't give sunrise and sunset for {place}.", ["place": spot.label])) }
        return L("{place}: sunrise {sunrise}, sunset {sunset}, {daylight} of daylight.", [
            "place": spot.label, "sunrise": String(rise), "sunset": String(set),
            "daylight": Format.duration(Double(light) * 60, units: [.hours, .minutes]),
        ]) + " " + moon(at: now)
    }

    /// The moon's phase from its age since a known new moon (6 January 2000, 18:14 UTC).
    static func moon(at moment: Date) -> String {
        let month = 29.530588853
        let age = (moment.timeIntervalSince1970 - 947_182_440) / 86_400
        let day = (age.truncatingRemainder(dividingBy: month) + month).truncatingRemainder(dividingBy: month)
        let lit = Int(((1 - cos(2 * Double.pi * day / month)) / 2 * 100).rounded())
        let phase = Int((day / month * 8 + 0.5).rounded(.down)) % 8
        let lighted = Format.percent(points: Double(lit))
        // Whole sentences, so each language can say the phase its own way.
        switch phase {
        case 0: return L("The moon is a new moon, {lit} lit.", ["lit": lighted])
        case 1: return L("The moon is a waxing crescent, {lit} lit.", ["lit": lighted])
        case 2: return L("The moon is at its first quarter, {lit} lit.", ["lit": lighted])
        case 3: return L("The moon is a waxing gibbous, {lit} lit.", ["lit": lighted])
        case 4: return L("The moon is full, {lit} lit.", ["lit": lighted])
        case 5: return L("The moon is a waning gibbous, {lit} lit.", ["lit": lighted])
        case 6: return L("The moon is at its last quarter, {lit} lit.", ["lit": lighted])
        default: return L("The moon is a waning crescent, {lit} lit.", ["lit": lighted])
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
