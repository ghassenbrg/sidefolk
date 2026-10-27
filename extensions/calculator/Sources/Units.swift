import Foundation
import SidefolkExtensionKit

/// Unit conversions by exact factors to one base unit per kind, temperatures by formula. Symbols are matched with
/// their case first (MB is megabytes, Mb megabits), then any name in lower case.
enum Units {
    struct Unit {
        let kind: String
        /// Base units per one of this unit (metres per mile); unused for temperatures.
        let factor: Double
        let symbol: String
    }

    private static let groups: [(kind: String, units: [(names: [String], factor: Double)])] = [
        ("length", [(["m", "meter", "meters", "metre", "metres"], 1), (["km", "kilometer", "kilometers", "kilometre", "kilometres"], 1000),
                    (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], 0.01), (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], 0.001),
                    (["mi", "mile", "miles"], 1609.344), (["yd", "yard", "yards"], 0.9144), (["ft", "foot", "feet"], 0.3048),
                    (["in", "inch", "inches"], 0.0254), (["nmi", "nautical mile", "nautical miles"], 1852)]),
        ("mass", [(["kg", "kilogram", "kilograms", "kilo", "kilos"], 1), (["g", "gram", "grams"], 0.001), (["mg", "milligram", "milligrams"], 1e-6),
                  (["t", "tonne", "tonnes", "metric ton", "metric tons"], 1000), (["lb", "lbs", "pound", "pounds"], 0.45359237),
                  (["oz", "ounce", "ounces"], 0.028349523125), (["st", "stone", "stones"], 6.35029318), (["short ton", "short tons", "us ton"], 907.18474)]),
        ("volume", [(["l", "L", "liter", "liters", "litre", "litres"], 1), (["ml", "mL", "milliliter", "milliliters", "millilitre", "millilitres"], 0.001),
                    (["cl", "centiliter", "centilitre"], 0.01), (["dl", "deciliter", "decilitre"], 0.1), (["m3", "cubic meter", "cubic meters", "cubic metre"], 1000),
                    (["gal", "gallon", "gallons", "us gallon", "us gallons"], 3.785411784), (["imperial gallon", "imperial gallons", "uk gallon", "uk gallons"], 4.54609),
                    (["qt", "quart", "quarts"], 0.946352946), (["pt", "pint", "pints"], 0.473176473), (["cup", "cups"], 0.2365882365),
                    (["fl oz", "floz", "fluid ounce", "fluid ounces"], 0.0295735295625), (["tbsp", "tablespoon", "tablespoons"], 0.01478676478125),
                    (["tsp", "teaspoon", "teaspoons"], 0.00492892159375)]),
        ("area", [(["m2", "m²", "sq m", "square meter", "square meters", "square metre", "square metres"], 1),
                  (["km2", "km²", "sq km", "square kilometer", "square kilometers", "square kilometre"], 1e6), (["cm2", "cm²", "square centimeter"], 1e-4),
                  (["ha", "hectare", "hectares"], 1e4), (["acre", "acres", "ac"], 4046.8564224),
                  (["ft2", "ft²", "sq ft", "square foot", "square feet"], 0.09290304), (["mi2", "mi²", "sq mi", "square mile", "square miles"], 2_589_988.110336),
                  (["yd2", "sq yd", "square yard", "square yards"], 0.83612736), (["in2", "sq in", "square inch", "square inches"], 0.00064516)]),
        ("speed", [(["m/s", "mps", "meters per second"], 1), (["km/h", "kmh", "kph", "kilometers per hour", "kilometres per hour"], 1 / 3.6),
                   (["mph", "miles per hour"], 0.44704), (["knot", "knots", "kn", "kt"], 1852.0 / 3600), (["ft/s", "feet per second"], 0.3048)]),
        ("time", [(["s", "sec", "secs", "second", "seconds"], 1), (["ms", "millisecond", "milliseconds"], 0.001), (["min", "mins", "minute", "minutes"], 60),
                  (["h", "hr", "hrs", "hour", "hours"], 3600), (["d", "day", "days"], 86_400), (["wk", "week", "weeks"], 604_800),
                  (["month", "months"], 2_629_746), (["yr", "year", "years"], 31_556_952)]),
        ("data", [(["B", "byte", "bytes"], 1), (["bit", "bits"], 0.125), (["KB", "kB", "kilobyte", "kilobytes"], 1e3), (["MB", "megabyte", "megabytes"], 1e6),
                  (["GB", "gigabyte", "gigabytes"], 1e9), (["TB", "terabyte", "terabytes"], 1e12), (["KiB", "kibibyte"], 1024), (["MiB", "mebibyte"], 1_048_576),
                  (["GiB", "gibibyte"], 1_073_741_824), (["TiB", "tebibyte"], 1_099_511_627_776), (["kb", "Kb", "kbit", "kilobit", "kilobits"], 125),
                  (["Mb", "Mbit", "megabit", "megabits"], 125_000), (["Gb", "Gbit", "gigabit", "gigabits"], 1.25e8)]),
        ("energy", [(["J", "joule", "joules"], 1), (["kJ", "kilojoule", "kilojoules"], 1000), (["cal", "calorie", "calories"], 4.184),
                    (["kcal", "Cal", "kilocalorie", "kilocalories"], 4184), (["Wh", "watt hour", "watt hours"], 3600),
                    (["kWh", "kilowatt hour", "kilowatt hours"], 3.6e6), (["BTU", "btu"], 1055.05585)]),
        ("pressure", [(["Pa", "pascal", "pascals"], 1), (["kPa", "kilopascal"], 1000), (["hPa", "mbar", "millibar"], 100), (["bar"], 1e5),
                      (["psi"], 6894.757293168), (["atm", "atmosphere", "atmospheres"], 101_325), (["mmHg"], 133.322387415)]),
        ("angle", [(["deg", "degree", "degrees", "°"], 1), (["rad", "radian", "radians"], 180 / Double.pi), (["turn", "turns"], 360)]),
        ("temperature", [(["°C", "C", "celsius", "centigrade"], 0), (["°F", "F", "fahrenheit"], 0), (["K", "kelvin"], 0)]),
    ]

    private static let table: (exact: [String: Unit], lower: [String: Unit]) = {
        var exact: [String: Unit] = [:], lower: [String: Unit] = [:]
        for group in groups {
            for unit in group.units {
                let made = Unit(kind: group.kind, factor: unit.factor, symbol: unit.names[0])
                for name in unit.names {
                    exact[name] = exact[name] ?? made
                    lower[name.lowercased()] = lower[name.lowercased()] ?? made
                }
            }
        }
        return (exact, lower)
    }()

    static func find(_ raw: String) -> Unit? {
        let name = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "degrees ", with: "")
        return table.exact[name] ?? table.lower[name.lowercased()]
    }

    static func convert(_ value: Double, from: String, to: String) throws -> String {
        guard let a = find(from) else { throw Problem("I don't know the unit “\(from)”.") }
        guard let b = find(to) else { throw Problem("I don't know the unit “\(to)”.") }
        guard a.kind == b.kind else { throw Problem("\(a.symbol) is a \(a.kind) and \(b.symbol) is a \(b.kind): they don't convert.") }
        let result = a.kind == "temperature" ? kelvinTo(b.symbol, kelvin(value, a.symbol)) : value * a.factor / b.factor
        guard result.isFinite else { throw Problem("That's too big to convert.") }
        let note = a.kind == "time" && [a.symbol, b.symbol].contains(where: { $0 == "month" || $0 == "yr" })
            ? " (an average month or year)" : a.kind == "volume" && [a.symbol, b.symbol].contains(where: { ["gal", "qt", "pt", "cup", "fl oz"].contains($0) })
            ? " (US measures)" : ""
        // The person's own words for the units ("2 cups"), the symbol only for temperatures (°C, not C).
        func shown(_ raw: String, _ unit: Unit) -> String { unit.kind == "temperature" ? unit.symbol : raw.trimmingCharacters(in: .whitespaces) }
        return "\(show(value)) \(shown(from, a)) = \(show(result)) \(shown(to, b))\(note)"
    }

    private static func kelvin(_ value: Double, _ unit: String) -> Double {
        switch unit {
        case "°C", "C": value + 273.15
        case "°F", "F": (value - 32) * 5 / 9 + 273.15
        default: value
        }
    }

    private static func kelvinTo(_ unit: String, _ k: Double) -> Double {
        switch unit {
        case "°C", "C": k - 273.15
        case "°F", "F": (k - 273.15) * 9 / 5 + 32
        default: k
        }
    }

    /// Six significant digits are plenty for a conversion; big whole amounts (bytes in a GiB) are shown in full.
    static func show(_ value: Double) -> String {
        abs(value) >= 1e6 && abs(value) < 1e15 ? String(format: "%.0f", value) : String(format: "%.6g", value)
    }
}
