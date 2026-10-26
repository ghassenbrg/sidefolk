import Foundation

/// What a weather report shows.
public enum WeatherQuantity: String, CaseIterable, Sendable {
    case temperature, feelsLike = "feels_like", humidity, wind, precipitation, conditions

    /// The Open-Meteo "current" variable it reads.
    var variable: String {
        switch self {
        case .temperature, .conditions: "temperature_2m"
        case .feelsLike: "apparent_temperature"
        case .humidity: "relative_humidity_2m"
        case .wind: "wind_speed_10m"
        case .precipitation: "precipitation"
        }
    }

    /// "Temperature in Fukuoka": the report's name, in the person's language.
    func title(_ place: String) -> String {
        switch self {
        case .temperature: String(localized: "Temperature in \(place)")
        case .feelsLike: String(localized: "Feels like in \(place)", comment: "The felt temperature in a place")
        case .humidity: String(localized: "Humidity in \(place)")
        case .wind: String(localized: "Wind in \(place)")
        case .precipitation: String(localized: "Rainfall in \(place)", comment: "How much rain falls in a place, as a live value")
        case .conditions: String(localized: "Weather in \(place)")
        }
    }
}

/// The weather somewhere, from Open-Meteo (free, no key, no account): the place is looked up once, then each
/// check reads the current value. Built in rather than left to a web value, so "temperature in Fukuoka every
/// minute" works without AI, without a model chaining two requests, and without reading a page into the turn (D35).
public struct WeatherProbe: WatcherProbe {
    public let kind = WatchKind.weather
    public var defaultInterval: TimeInterval { 15 * 60 }
    public var minimumInterval: TimeInterval { ReportFloors.web }

    static let geocoder = "https://geocoding-api.open-meteo.com/v1/search"
    static let forecast = "https://api.open-meteo.com/v1/forecast"

    let web: ProbeFetching

    public init(fetcher: any WatchFetcher, throttle: HostThrottle = HostThrottle()) {
        web = ProbeFetching(fetcher: fetcher, throttle: throttle)
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        guard let place = Self.cleanPlace(watcher.config.string("place")) else {
            throw WatchError.invalid(String(localized: "Tell me which place, like “Fukuoka” or “Paris, France”."))
        }
        guard let quantity = WeatherQuantity(rawValue: watcher.config.string("quantity")?.lowercased() ?? "temperature") else {
            throw WatchError.invalid(String(localized: "I can show the temperature, feels like, humidity, wind, rain or conditions."))
        }
        var w = watcher
        w.mode = .report
        w.config = Report.options(of: w.config).setting("place", .string(place)).setting("quantity", .string(quantity.rawValue))
        w.condition = .object([:])
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        guard let place = w.config.string("place"), let quantity = WeatherQuantity(rawValue: w.config.string("quantity") ?? "") else {
            throw ProbeError.invalid(String(localized: "This report doesn't say where."))
        }
        var state = w.lastState?.setting("reading", nil) ?? .object([:])
        if state["lat"]?.doubleValue == nil { state = try await locate(place, now: now) }
        guard let lat = state["lat"]?.doubleValue, let lon = state["lon"]?.doubleValue else {
            throw ProbeError.failed(String(localized: "I couldn't look up that place."))
        }
        let current = try await currentWeather(lat: lat, lon: lon, quantity: quantity, now: now)
        return ProbeResult(state: state, reading: try Self.reading(current, quantity))
    }

    // MARK: Asking Open-Meteo

    /// The place's coordinates and the name it goes by ("Fukuoka, Japan"), remembered with the watcher.
    func locate(_ place: String, now: Date) async throws -> JSONValue {
        let parts = place.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        var url = URLComponents(string: Self.geocoder)!
        url.queryItems = [URLQueryItem(name: "name", value: parts[0]), URLQueryItem(name: "count", value: "10"),
                          URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        let results = try await json(url.url!, now: now)["results"]?.arrayValue ?? []
        // "Paris, France" or "Portland, Oregon": the words after the comma pick among places of that name.
        let region = parts.count > 1 ? parts[1].lowercased() : nil
        let match = results.first { r in
            guard let region else { return true }
            return ["country", "admin1", "country_code"].contains { r.string($0)?.lowercased().hasPrefix(region) == true }
        }
        guard let match, let lat = match["latitude"]?.doubleValue, let lon = match["longitude"]?.doubleValue else {
            throw ProbeError.invalid(String(localized: "I couldn't find a place called “\(place)”."))
        }
        let name = [match.string("name"), match.string("country")].compactMap { $0.flatMap(Self.cleanPlace) }.joined(separator: ", ")
        return ["lat": .number(lat), "lon": .number(lon), "place": .string(name.isEmpty ? place : name)]
    }

    func currentWeather(lat: Double, lon: Double, quantity: WeatherQuantity, now: Date) async throws -> JSONValue {
        var url = URLComponents(string: Self.forecast)!
        var variables = [quantity.variable]
        if quantity == .conditions { variables.append("weather_code") }
        url.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
                          URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
                          URLQueryItem(name: "current", value: variables.joined(separator: ","))]
        guard let current = try await json(url.url!, now: now)["current"], current.objectValue != nil else {
            throw ProbeError.failed(String(localized: "The weather service sent no current weather."))
        }
        return current
    }

    private func json(_ url: URL, now: Date) async throws -> JSONValue {
        switch try await web.fetch(FetchRequest(url: url), now: now) {
        case .unreachable(let why): throw ProbeError.failed(why)
        case .response(let r):
            guard (200..<300).contains(r.status) else {
                throw ProbeError.failed(String(localized: "The weather service said \(ProbeFetching.httpWords(r.status))."))
            }
            guard let value = try? JSONValue.parse(r.body) else { throw ProbeError.failed(String(localized: "The weather service sent something I can't read.")) }
            return value
        }
    }

    // MARK: Words

    static func reading(_ current: JSONValue, _ quantity: WeatherQuantity) throws -> ReadingText {
        guard let value = current[quantity.variable]?.doubleValue, value.isFinite else {
            throw ProbeError.failed(String(localized: "The weather service sent no value."))
        }
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        // Units follow the Mac's region and its temperature setting (°C in Japan even with English words), so the
        // locale is the system's here, not the words' language.
        func shown<U: Dimension>(_ unit: U, _ usage: MeasurementFormatUnitUsage<U>) -> String {
            Measurement(value: value, unit: unit).formatted(.measurement(width: .abbreviated, usage: usage, numberFormatStyle: number)
                .locale(.autoupdatingCurrent))
        }
        let model = String(format: "%.1f", value)
        switch quantity {
        case .temperature, .feelsLike:
            return ReadingText(shown: shown(UnitTemperature.celsius, .weather), forModel: "\(model) °C")
        case .humidity:
            let share = MetricProbe.percent(value / 100)
            return ReadingText(shown: share, forModel: "\(Int(value.rounded()))% humidity")
        case .wind:
            return ReadingText(shown: shown(UnitSpeed.kilometersPerHour, .wind), forModel: "\(model) km/h")
        case .precipitation:
            return ReadingText(shown: shown(UnitLength.millimeters, .rainfall), forModel: "\(model) mm")
        case .conditions:
            let code = current["weather_code"]?.intValue ?? -1
            let temperature = shown(UnitTemperature.celsius, .weather)
            return ReadingText(shown: String(localized: "weather.conditions", defaultValue: "\(Self.sky(code)), \(temperature)", comment: "The sky, then the temperature: “Partly cloudy, 18 °C”"),
                               forModel: "\(Self.skyForModel(code)), \(model) °C")
        }
    }

    /// WMO weather codes as Open-Meteo sends them, in a few words.
    static func sky(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "sky.clear", defaultValue: "Clear", comment: "Weather: a clear sky (not the Clear button)")
        case 1, 2: String(localized: "Partly cloudy")
        case 3: String(localized: "Cloudy")
        case 45, 48: String(localized: "Fog")
        case 51...57: String(localized: "Drizzle")
        case 61...67, 80...82: String(localized: "sky.rain", defaultValue: "Rain", comment: "Weather: it is raining")
        case 71...77, 85, 86: String(localized: "Snow")
        case 95...99: String(localized: "Thunderstorm")
        default: String(localized: "Unknown sky")
        }
    }

    static func skyForModel(_ code: Int) -> String {
        switch code {
        case 0: "clear"
        case 1, 2: "partly cloudy"
        case 3: "cloudy"
        case 45, 48: "fog"
        case 51...57: "drizzle"
        case 61...67, 80...82: "rain"
        case 71...77, 85, 86: "snow"
        case 95...99: "thunderstorm"
        default: "unknown sky"
        }
    }

    /// A place name as it may be stored and shown: letters, spaces and a little punctuation, at most 60 characters.
    /// Whatever the geocoder sends is held to the same rule.
    static func cleanPlace(_ text: String?) -> String? {
        let allowed = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "-'’.,()")).union(.decimalDigits)
        guard let text, text.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let clean = text.displaySafe.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return clean.isEmpty || clean.count > 60 ? nil : clean
    }
}
