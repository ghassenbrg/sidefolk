import Foundation

/// A page of Sidefolk's own Settings a result can point to: the card shows a button that opens it.
public enum SettingsLink: String, Sendable, CaseIterable {
    case yourLocation = "sidefolk-settings:privacy/location"

    public static func isKnown(_ url: String?) -> Bool { url.flatMap(SettingsLink.init(rawValue:)) != nil }
}

/// What a request that needs a place says when none was named and Sidefolk doesn't know where the person is (D48):
/// how to name one, with a button to Settings › Privacy › Your location, instead of a guess.
public enum PlaceNeeded {
    public static var card: ResultCard {
        ResultCard(kind: .info, title: String(localized: "Which place?", comment: "Asked when weather is wanted and no place is known"),
                   subtitle: String(localized: "Name it, like “temperature in Fukuoka every 10 minutes”, or let me know where you are in Settings."),
                   url: SettingsLink.yourLocation.rawValue)
    }

    static var result: ToolResult {
        ToolResult(text: "No place was given and the user's location isn't known, so nothing was started. Ask which place; they can "
                   + "also set their location in Settings › Privacy & Permissions › Your location (a button for it is shown to them).",
                   card: card, isError: true)
    }
}

extension WeatherProbe {
    /// A weather report's settings: the place named, else the person's own (D48). Their own comes with its coordinates,
    /// so Open-Meteo is asked about exactly where they are rather than the first town of that name. Nil when there is no
    /// place at all.
    static func config(place named: String?, here: KnownPlace?, quantity: JSONValue) -> JSONValue? {
        let named = named.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard let place = named ?? here?.name else { return nil }
        var config: JSONValue = ["place": .string(place), "quantity": quantity]
        if let here, named.map(here.isNamed) ?? true {
            config = config.setting("latitude", .number(here.latitude)).setting("longitude", .number(here.longitude))
        }
        return config
    }

    /// The coordinates a report came with (the person's own place), as a looked-up place is remembered.
    static func pinned(_ config: JSONValue, place: String) -> JSONValue? {
        guard let lat = config["latitude"]?.doubleValue, let lon = config["longitude"]?.doubleValue,
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return ["lat": .number(lat), "lon": .number(lon), "place": .string(place)]
    }
}
