import Foundation
import Testing
@testable import ext_calculator
@testable import ext_system_vitals
@testable import ext_weather
@testable import ext_world_clock

/// The shipped extensions' own logic, read directly with canned data: their words, their sums, their parsers. Nothing
/// here starts a process or reaches the network (ShippedExtensionSandboxTests runs them for real).
struct ShippedExtensionLogicTests {
    static func day(_ text: String) throws -> Date { try Dates.parse(text) }

    @Test func calculatorSums() throws {
        let cases: [(String, Double)] = [("2 + 3 * 4", 14), ("(2+3)*4", 20), ("2^3^2", 512), ("-2^2", -4), ("2^-1", 0.5), ("15% of 80", 12),
                                         ("200 + 10%", 220), ("50 - 10%", 45), ("10%", 0.1), ("sqrt(16) + 1", 5), ("1,000 + 1", 1001),
                                         ("3x4", 12), ("17 mod 5", 2), ("2 × 3 ÷ 4", 1.5)]
        for (text, expected) in cases { #expect(try Arithmetic.evaluate(text) == expected, "\(text)") }
        #expect(abs(try Arithmetic.evaluate("sin(30)") - 0.5) < 1e-12)
        #expect(Arithmetic.show(0.1 + 0.2) == "0.3")
        #expect(Arithmetic.show(1_000_000 / 3) == "333333.333333")
        for bad in ["1/0", "2 +", "(1 + 2", "1,5 + 1", "foo(2)"] { #expect(throws: (any Error).self, "\(bad)") { try Arithmetic.evaluate(bad) } }
    }

    @Test func calculatorUnitsAndDates() throws {
        #expect(try Units.convert(5, from: "km", to: "mi") == "5 km = 3.10686 mi")
        #expect(try Units.convert(100, from: "fahrenheit", to: "C") == "100 °F = 37.7778 °C")
        #expect(try Units.convert(100, from: "Mb", to: "MB") == "100 Mb = 12.5 MB", "megabits, not megabytes")
        #expect(try Units.convert(1, from: "GiB", to: "B") == "1 GiB = 1073741824 B")
        #expect(try Units.convert(2, from: "cups", to: "ml") == "2 cups = 473.176 ml (US measures)")
        #expect(throws: (any Error).self) { try Units.convert(1, from: "km", to: "kg") }

        // Thursday 24 December 2026 to Monday 4 January 2027: the weekdays after the first day, up to the last.
        #expect(Dates.between(try Self.day("2026-12-24"), try Self.day("2027-01-04"))
            == "From Thursday 24 December 2026 to Monday 4 January 2027: 11 days (1 week and 4 days), 7 of them weekdays.")
        #expect(Dates.show(try Dates.add("5 weekdays", to: try Self.day("2026-10-30"))) == "Friday 6 November 2026")
        #expect(Dates.show(try Dates.add("1 month", to: try Self.day("2026-01-31"))) == "Saturday 28 February 2026")
        #expect(Dates.show(try Dates.add("-10 days", to: try Self.day("2026-10-28"))) == "Sunday 18 October 2026")
        #expect(throws: (any Error).self) { try Dates.parse("2026-02-29") }
        #expect(Dates.show(try Self.day("25 December 2026")) == "Friday 25 December 2026")
    }


    @MainActor @Test func weatherWordsAndOneWarningPerWetSpell() {
        let data: [String: Any] = [
            "current_units": ["temperature_2m": "°C", "wind_speed_10m": "km/h"],
            "current": ["temperature_2m": 12.4, "apparent_temperature": 10.2, "weather_code": 61, "wind_speed_10m": 14.6],
            "daily": ["time": ["2026-10-26", "2026-10-27"], "weather_code": [61, 2], "temperature_2m_min": [8.2, 6.9],
                      "temperature_2m_max": [13.1, 15.4], "precipitation_probability_max": [80, NSNull()]],
        ]
        #expect(Weather.describe(data, label: "Lyon, France").split(separator: "\n") == [
            "Lyon, France, now: light rain, 12°C (feels like 10°C), wind 15 km/h.",
            "Today: light rain, 8 to 13°C, 80% chance of rain.",
            "Tomorrow: partly cloudy, 7 to 15°C, ?% chance of rain.",
        ])
        func hours(_ chances: [Int]) -> [String: Any] {
            ["current": ["time": "2026-10-26T14:00"], "hourly": ["precipitation_probability": chances,
                                                                 "time": ["2026-10-26T13:00", "2026-10-26T14:00", "2026-10-26T15:00", "2026-10-26T16:00"]]]
        }
        let first = Weather.rainCheck(hours([90, 10, 70, 80]), label: "Lyon", withinHours: 3, chance: 60, state: [:])
        let again = Weather.rainCheck(hours([90, 10, 70, 80]), label: "Lyon", withinHours: 3, chance: 60, state: first.state)
        let dry = Weather.rainCheck(hours([90, 0, 0, 0]), label: "Lyon", withinHours: 3, chance: 60, state: again.state)
        let wet = Weather.rainCheck(hours([0, 0, 0, 65]), label: "Lyon", withinHours: 3, chance: 60, state: dry.state)
        #expect([first, again, dry, wet].map(\.triggered) == [true, false, false, true], "the past hour (13:00) never counts")
        #expect(first.summary == "Rain is likely in Lyon around 15:00 (70% chance).")
        // The eclipse of 8 April 2024 was a new moon; 23 April 2024 a full one.
        #expect(Weather.moon(at: Date(timeIntervalSince1970: 1_712_600_460)).hasPrefix("The moon is a new moon"))
        #expect(Weather.moon(at: Date(timeIntervalSince1970: 1_713_916_140)).hasPrefix("The moon is a full moon"))
    }




    @Test func systemVitalsReadsPmset() {
        let onBattery = Vitals.battery(from: "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4653155)\t84%; discharging; 5:12 remaining present: true")
        #expect(Vitals.describe(onBattery) == "Battery at 84%, discharging (5:12 left).")
        let full = Vitals.battery(from: "Now drawing from 'AC Power'\n -InternalBattery-0 (id=4653155)\t100%; charged; 0:00 remaining present: true")
        #expect(Vitals.describe(full) == "Battery at 100%, charged." && Vitals.charging(full))
        #expect(Vitals.describe(Vitals.battery(from: "Now drawing from 'AC Power'\n")) == "This Mac has no battery; it runs on AC Power.")
    }

    @Test func worldClockZonesAndTheirNames() throws {
        let converted = try WorldClock.convert("2026-01-15 12:00", from: "UTC", to: ["Asia/Tokyo", "New York", "Fukuoka"])
        #expect(converted.contains("21:00 in Asia/Tokyo (JST, UTC+9)") && converted.contains("07:00 in New York (EST, UTC−5)"), "\(converted)")
        #expect(converted.hasPrefix("Thursday 15 January, 12:00 in UTC (UTC+0) is:"), "\(converted)")
        #expect(converted.contains("21:00 in Fukuoka (JST, UTC+9)"))
        #expect(Set(TZif.types("Europe/Paris").map(\.name)).isSuperset(of: ["CET", "CEST"]))
        #expect(throws: (any Error).self) { try WorldClock.convert("25:00", from: "UTC", to: ["Paris"]) }
        #expect(try WorldClock.resolve("UTC+5:30").zone.secondsFromGMT() == 19_800)
    }
}
