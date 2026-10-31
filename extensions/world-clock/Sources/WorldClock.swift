import Foundation
import SidefolkExtensionKit

/// The time anywhere, from macOS's own time zone database (which every extension may read), so daylight
/// saving is exact where a model's guess wouldn't be.
enum WorldClock {
    /// Places people name that aren't the last part of an IANA zone, or that would be ambiguous.
    static let aliases: [String: String] = [
        "san francisco": "America/Los_Angeles", "silicon valley": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "portland": "America/Los_Angeles", "san diego": "America/Los_Angeles", "las vegas": "America/Los_Angeles",
        "la": "America/Los_Angeles", "california": "America/Los_Angeles", "washington": "America/New_York",
        "washington dc": "America/New_York", "boston": "America/New_York", "miami": "America/New_York",
        "atlanta": "America/New_York", "philadelphia": "America/New_York", "nyc": "America/New_York",
        "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago",
        "salt lake city": "America/Denver", "montreal": "America/Toronto", "ottawa": "America/Toronto",
        "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo", "beijing": "Asia/Shanghai",
        "shenzhen": "Asia/Shanghai", "guangzhou": "Asia/Shanghai", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "new delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "chennai": "Asia/Kolkata",
        "hyderabad": "Asia/Kolkata", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "fukuoka": "Asia/Tokyo",
        "lahore": "Asia/Karachi", "tel aviv": "Asia/Jerusalem", "abu dhabi": "Asia/Dubai", "munich": "Europe/Berlin",
        "frankfurt": "Europe/Berlin", "hamburg": "Europe/Berlin", "geneva": "Europe/Zurich", "barcelona": "Europe/Madrid",
        "milan": "Europe/Rome", "manchester": "Europe/London", "edinburgh": "Europe/London", "lyon": "Europe/Paris",
        "marseille": "Europe/Paris", "cape town": "Africa/Johannesburg", "sfax": "Africa/Tunis", "sousse": "Africa/Tunis",
        "uk": "Europe/London", "united kingdom": "Europe/London", "england": "Europe/London", "ireland": "Europe/Dublin",
        "france": "Europe/Paris", "germany": "Europe/Berlin", "spain": "Europe/Madrid", "italy": "Europe/Rome",
        "netherlands": "Europe/Amsterdam", "belgium": "Europe/Brussels", "switzerland": "Europe/Zurich",
        "austria": "Europe/Vienna", "poland": "Europe/Warsaw", "sweden": "Europe/Stockholm", "norway": "Europe/Oslo",
        "denmark": "Europe/Copenhagen", "finland": "Europe/Helsinki", "greece": "Europe/Athens", "turkey": "Europe/Istanbul",
        "ukraine": "Europe/Kyiv", "portugal": "Europe/Lisbon", "japan": "Asia/Tokyo", "korea": "Asia/Seoul",
        "south korea": "Asia/Seoul", "china": "Asia/Shanghai", "india": "Asia/Kolkata", "singapore": "Asia/Singapore",
        "israel": "Asia/Jerusalem", "uae": "Asia/Dubai", "saudi arabia": "Asia/Riyadh", "egypt": "Africa/Cairo",
        "tunisia": "Africa/Tunis", "morocco": "Africa/Casablanca", "algeria": "Africa/Algiers", "nigeria": "Africa/Lagos",
        "kenya": "Africa/Nairobi", "south africa": "Africa/Johannesburg", "new zealand": "Pacific/Auckland",
        "argentina": "America/Argentina/Buenos_Aires", "colombia": "America/Bogota", "peru": "America/Lima",
        "vietnam": "Asia/Ho_Chi_Minh", "thailand": "Asia/Bangkok", "philippines": "Asia/Manila", "pakistan": "Asia/Karachi",
        "bangladesh": "Asia/Dhaka", "nepal": "Asia/Kathmandu", "iran": "Asia/Tehran", "iceland": "Atlantic/Reykjavik",
    ]
    static let regions = ["Africa/", "America/", "Antarctica/", "Asia/", "Atlantic/", "Australia/", "Europe/", "Indian/", "Pacific/"]
    static let here: Set<String> = ["", "here", "local", "local time", "my time", "my place", "home"]

    /// Lowercase, accents and underscores gone, spaces collapsed: "São_Paulo" and "sao paulo" match.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// By folded full name and by folded city name, regional zones first.
    static let zones: (full: [String: String], city: [String: String]) = {
        let names = TimeZone.knownTimeZoneIdentifiers.sorted { a, b in
            let (ra, rb) = (regions.contains { a.hasPrefix($0) }, regions.contains { b.hasPrefix($0) })
            return ra != rb ? ra : a < b
        }
        var full: [String: String] = [:], city: [String: String] = [:]
        for name in names {
            full[fold(name)] = full[fold(name)] ?? name
            let last = fold(String(name.split(separator: "/").last ?? ""))
            city[last] = city[last] ?? name
        }
        return (full, city)
    }()

    /// Where a time is, as an answer says it ("in Tokyo", "here in Paris", "at UTC+2").
    enum Spot {
        case here(city: String?)
        case utc
        case offset(String)
        case named(String)
    }

    /// The zone for a place, and how to say where it is.
    static func resolve(_ place: String) throws -> (spot: Spot, zone: TimeZone) {
        let key = fold(place)
        let shown = place.trimmingCharacters(in: .whitespaces)
        if here.contains(key) {
            let local = TimeZone.current
            let city = local.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            return (.here(city: city), local)
        }
        if ["utc", "gmt", "z", "zulu"].contains(key) { return (.utc, TimeZone(identifier: "UTC")!) }
        let compact = place.lowercased().replacingOccurrences(of: " ", with: "")
        if let m = compact.wholeMatch(of: /(?:utc|gmt)([+\-−])(\d{1,2})(?::?(\d{2}))?/) {
            let seconds = (Int(m.2)! * 60 + (m.3.map { Int($0)! } ?? 0)) * 60
            guard seconds <= 14 * 3600 else { throw Problem(L("{offset} isn't a real UTC offset.", ["offset": shown])) }
            return (.offset(shown), TimeZone(secondsFromGMT: m.1 == "+" ? seconds : -seconds)!)
        }
        guard let name = zones.full[key] ?? aliases[key] ?? zones.city[key], let zone = TimeZone(identifier: name) else {
            throw Problem(L("I don't know where “{place}” is. Try a big city nearby, a country with one time zone, or an IANA zone like Europe/Paris.",
                            ["place": shown]))
        }
        return (.named(shown), zone)
    }

    static func offset(_ zone: TimeZone, at moment: Date) -> String {
        let minutes = zone.secondsFromGMT(for: moment) / 60
        let (hours, rest) = (abs(minutes) / 60, abs(minutes) % 60)
        return "UTC\(minutes >= 0 ? "+" : "−")\(hours)\(rest == 0 ? "" : String(format: ":%02d", rest))"
    }

    /// "Thursday 15 January, 21:00 in Asia/Tokyo (JST, UTC+9)", in the person's language.
    static func describe(_ moment: Date, in zone: TimeZone, at spot: Spot) -> String {
        let format = DateFormatter()
        format.timeZone = zone
        if Language.code == "en" {
            // Sidefolk's own English way of writing a day and a time.
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "EEEE d MMMM, HH:mm"
        } else {
            format.locale = Language.locale
            format.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEEdMMMMHHmm", options: 0, locale: Language.locale)
        }
        // Named zones have an abbreviation (CET, JST); offsets and UTC itself only repeat the offset.
        // UTC's own zone is called GMT on Apple's systems: it gets no name beside its offset either.
        let abbreviation = ["GMT", "UTC"].contains(zone.identifier) ? "" : TZif.abbreviation(zone, at: moment) ?? ""
        let named = !abbreviation.isEmpty && !["+", "-", "UTC"].contains { abbreviation.hasPrefix($0) }
        let values = ["date": format.string(from: moment), "zone": (named ? abbreviation + ", " : "") + offset(zone, at: moment)]
        switch spot {
        case .here(let city?): return L("{date} here in {place} ({zone})", values.merging(["place": city]) { a, _ in a })
        case .here(nil): return L("{date} here ({zone})", values)
        case .utc: return L("{date} in UTC ({zone})", values)
        case .offset(let name): return L("{date} at {offset} ({zone})", values.merging(["offset": name]) { a, _ in a })
        case .named(let name): return L("{date} in {place} ({zone})", values.merging(["place": name]) { a, _ in a })
        }
    }

    static func difference(_ zone: TimeZone, from reference: TimeZone, at moment: Date) -> String {
        let minutes = (zone.secondsFromGMT(for: moment) - reference.secondsFromGMT(for: moment)) / 60
        guard minutes != 0 else { return L("the same time as you") }
        let span = Format.duration(Double(abs(minutes)) * 60, units: [.hours, .minutes], width: .wide)
        return minutes > 0 ? L("{span} ahead of you", ["span": span]) : L("{span} behind you", ["span": span])
    }

    /// "09:30", "9am", "noon", or "2026-03-29 02:30", in `zone`; today there when no date is given.
    static func parse(_ text: String, in zone: TimeZone, now: Date = Date()) throws -> Date {
        let shown = text.trimmingCharacters(in: .whitespaces)
        var key = shown.lowercased().replacingOccurrences(of: ".", with: "")
        if key == "noon" || key == "midday" { key = "12:00" } else if key == "midnight" { key = "00:00" }
        guard let m = key.wholeMatch(of: /(?:(\d{4})-(\d{2})-(\d{2})[ t])?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/) else {
            throw Problem(L("I couldn't read “{time}” as a time. Use HH:MM, 9am, noon, or YYYY-MM-DD HH:MM.", ["time": shown]))
        }
        var hour = Int(m.4)!
        let minute = m.5.map { Int($0)! } ?? 0
        if let half = m.6 {
            guard (1...12).contains(hour) else { throw Problem(L("“{time}” isn't a time on a 12-hour clock.", ["time": shown])) }
            hour = hour % 12 + (half == "pm" ? 12 : 0)
        }
        guard hour <= 23, minute <= 59 else { throw Problem(L("“{time}” isn't a time of day.", ["time": shown])) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var wanted = calendar.dateComponents([.year, .month, .day], from: now)
        if let y = m.1, let mo = m.2, let d = m.3 { (wanted.year, wanted.month, wanted.day) = (Int(y), Int(mo), Int(d)) }
        wanted.hour = hour
        wanted.minute = minute
        guard let moment = calendar.date(from: wanted) else { throw Problem(L("“{time}” isn't a real date.", ["time": shown])) }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        guard back.year == wanted.year, back.month == wanted.month, back.day == wanted.day else { throw Problem(L("“{time}” isn't a real date.", ["time": shown])) }
        // In the hour the clocks skip in spring, that wall time never happens there.
        guard back.hour == hour, back.minute == minute else {
            throw Problem(L("{time} doesn't happen on that day: the clocks skip that hour. Try an hour later.", ["time": shown]))
        }
        return moment
    }

    static func currentTime(_ places: [String], now: Date = Date()) throws -> String {
        var lines: [String] = [], problems: [String] = []
        for place in places.isEmpty ? ["here"] : places {
            do {
                let (spot, zone) = try resolve(place)
                let time = describe(now, in: zone, at: spot)
                lines.append(here.contains(fold(place)) ? L("It is {time}.", ["time": time])
                    : L("It is {time}, {difference}.", ["time": time, "difference": difference(zone, from: .current, at: now)]))
            } catch let problem as Problem {
                problems.append(problem.message)
            }
        }
        guard !lines.isEmpty else { throw Problem(problems.joined(separator: " ")) }
        return (lines + problems).joined(separator: "\n")
    }

    static func convert(_ time: String, from origin: String?, to places: [String], now: Date = Date()) throws -> String {
        let (originSpot, originZone) = try resolve(origin ?? "here")
        let moment = try parse(time, in: originZone, now: now)
        var lines = [L("{time} is:", ["time": describe(moment, in: originZone, at: originSpot)])], problems: [String] = []
        for place in places {
            do {
                let (spot, zone) = try resolve(place)
                lines.append("- " + describe(moment, in: zone, at: spot))
            } catch let problem as Problem {
                problems.append(problem.message)
            }
        }
        guard lines.count > 1 else { throw Problem(problems.joined(separator: " ")) }
        return (lines + problems).joined(separator: "\n")
    }
}

/// The time zone database's own abbreviations (EST, CET, JST), read from its files in /usr/share/zoneinfo:
/// Foundation's depend on the language and often say "GMT-5" instead.
enum TZif {
    static func abbreviation(_ zone: TimeZone, at moment: Date) -> String? {
        let offset = zone.secondsFromGMT(for: moment), dst = zone.isDaylightSavingTime(for: moment)
        // The newest type with this offset and daylight saving is the one in use.
        return types(zone.identifier).last { $0.offset == offset && $0.dst == dst }?.name
    }

    /// Every local time type a zone has had: its offset, whether it is daylight saving, and its abbreviation.
    static func types(_ identifier: String) -> [(offset: Int, dst: Bool, name: String)] {
        guard !identifier.contains(".."), let data = FileManager.default.contents(atPath: "/usr/share/zoneinfo/" + identifier),
              data.count > 44, data.prefix(4) == Data("TZif".utf8) else { return [] }
        let bytes = [UInt8](data)
        func int32(_ at: Int) -> Int { Int(Int32(bitPattern: UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3]))) }
        // Version 2 and later repeat the data with 64-bit times after the first block; that copy is the complete one.
        var header = 0, timeSize = 4
        func counts() -> (isut: Int, isstd: Int, leap: Int, time: Int, type: Int, char: Int) {
            (int32(header + 20), int32(header + 24), int32(header + 28), int32(header + 32), int32(header + 36), int32(header + 40))
        }
        if bytes[4] >= 0x32 {
            let c = counts()
            header += 44 + c.time * 4 + c.time + c.type * 6 + c.char + c.leap * 8 + c.isstd + c.isut
            timeSize = 8
            guard bytes.count > header + 44 else { return [] }
        }
        let c = counts()
        let typesAt = header + 44 + c.time * timeSize + c.time, charsAt = typesAt + c.type * 6
        guard bytes.count >= charsAt + c.char else { return [] }
        return (0..<c.type).map { i in
            let at = typesAt + i * 6
            let start = charsAt + Int(bytes[at + 5])
            let end = bytes[start..<(charsAt + c.char)].firstIndex(of: 0) ?? (charsAt + c.char)
            return (int32(at), bytes[at + 4] != 0, String(decoding: bytes[start..<end], as: UTF8.self))
        }
    }
}
