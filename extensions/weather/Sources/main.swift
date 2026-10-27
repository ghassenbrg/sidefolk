import SidefolkExtensionKit

// Weather, an extension that ships with Sidefolk: the internet and nothing else (no files, no programs).
let place = Schema.string("A city or town, like Lyon or Austin, Texas.", maxLength: 80)
let ext = Extension(name: "weather")

ext.tool("forecast", "Weather forecast",
         "The weather now and for the next days in a place: conditions, temperatures, chance of rain and wind.",
         input: Schema.object([
             "place": place,
             "days": Schema.integer("How many days, today included (3 if not given).", minimum: 1, maximum: 7),
             "units": Schema.string("°C and km/h, or °F and mph (metric if not given).", oneOf: ["metric", "imperial"]),
         ], required: ["place"])) { args in
    try await Weather.forecast(try args.required("place"), days: args.int("days") ?? 3, imperial: args.string("units") == "imperial")
}

ext.tool("sun_and_moon", "Sunrise, sunset and the moon",
         "Today's sunrise, sunset and hours of daylight in a place, and the moon's phase.",
         input: Schema.object(["place": place], required: ["place"])) { args in
    try await Weather.sunAndMoon(try args.required("place"))
}

ext.watcher("rain_soon") { settings, state in
    try await Weather.rainSoon(place: try settings.required("place"), withinHours: settings.int("within_hours") ?? 3,
                               chance: settings.int("chance_percent") ?? 60, state: state)
}

await ext.serve()
