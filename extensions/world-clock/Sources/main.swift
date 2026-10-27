import SidefolkExtensionKit

// World Clock, an extension that ships with Sidefolk. It needs no permission at all.
let place = Schema.string("A city (Tokyo, San Francisco), a country with one time zone (Japan), an IANA zone (Europe/Paris), "
    + "a UTC offset (UTC+2) or \"here\".", maxLength: 80)
let ext = Extension(name: "world-clock")

ext.tool("current_time", "Time around the world",
         "The current date and time in one or more places: cities (Tokyo, San Francisco), countries with one time zone (Japan), "
         + "IANA zones (Europe/Paris), UTC offsets (UTC+2) or \"here\".",
         input: Schema.object(["places": Schema.array(of: place, "Where; \"here\" if not given.", maxItems: 12)])) { args in
    try WorldClock.currentTime(args.strings("places"))
}

ext.tool("convert_time", "Convert a time between places",
         "What a time in one place is in other places, like 09:30 in Paris for New York and Tokyo. The time is \"HH:MM\", "
         + "\"9am\", \"noon\", or \"YYYY-MM-DD HH:MM\" for another day (today in the first place otherwise).",
         input: Schema.object([
             "time": Schema.string("The time to convert.", maxLength: 40),
             "from": Schema.string("Where that time is; \"here\" if not given.", maxLength: 80),
             "to": Schema.array(of: place, "Where to convert it to.", maxItems: 12),
         ], required: ["time", "to"])) { args in
    try WorldClock.convert(try args.required("time"), from: args.string("from"), to: args.strings("to"))
}

await ext.serve()
