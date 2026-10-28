import Foundation
import Testing
@testable import ext_calculator
@testable import ext_currency
@testable import ext_dev_toolbox
@testable import ext_feeds
@testable import ext_playtime
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

    @Test func currencyReadsTheECBFile() throws {
        let xml = """
            <gesmes:Envelope><Cube><Cube time='2026-10-27'>
            <Cube currency='USD' rate='1.1150'/><Cube currency='JPY' rate='175.97'/><Cube currency='GBP' rate='0.8366'/>
            </Cube></Cube></gesmes:Envelope>
            """
        let table = try Rates.parse(xml)
        #expect(table.day == "2026-10-27")
        #expect(table.perEuro == ["EUR": 1, "USD": 1.115, "JPY": 175.97, "GBP": 0.8366])
        #expect(abs(Rates.rate("USD", "JPY", in: table) - 175.97 / 1.115) < 1e-9)
        #expect(Rates.money(1234.5) == "1,234.50")
        #expect(Rates.rateText(0.896861) == "0.8969")
        #expect(throws: (any Error).self) { try Rates.parse("<html>maintenance</html>") }
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

    @Test func feedsReadRSSAtomAndFindTheFeedOfASite() throws {
        let rss = Parser.parse(Data("""
            <rss version="2.0"><channel><title>Tea Blog</title>
            <item><title>Green tea</title><link>https://tea.example/green</link><pubDate>Tue, 27 Oct 2026 09:00:00 GMT</pubDate></item>
            <item><title><![CDATA[Oolong & more]]></title><link>https://tea.example/oolong</link></item>
            </channel></rss>
            """.utf8))
        #expect(rss.isFeed && rss.title == "Tea Blog")
        #expect(rss.items.map(\.title) == ["Green tea", "Oolong & more"])
        #expect(rss.items.first?.date == "Tue, 27 Oct 2026 09:00:00 GMT")
        let atom = Parser.parse(Data("""
            <feed xmlns="http://www.w3.org/2005/Atom"><title>Notes</title>
            <entry><title>Hello</title><link rel="alternate" href="https://notes.example/hello"/><updated>2026-10-27T10:00:00Z</updated></entry>
            </feed>
            """.utf8))
        #expect(atom.items.first?.link == "https://notes.example/hello" && atom.items.first?.date == "2026-10-27T10:00:00Z")
        let html = #"<head><link rel="alternate" type="application/rss+xml" title="Feed" href="/feed.xml?a=1&amp;b=2"></head>"#
        #expect(Feeds.discover(html, base: URL(string: "https://tea.example/blog")!)?.absoluteString == "https://tea.example/feed.xml?a=1&b=2")
        #expect(!Parser.parse(Data("<html><body>No feed</body></html>".utf8)).isFeed)
    }

    @Test func devToolboxConversions() throws {
        #expect(try Toolbox.transform("json_pretty", #"{"b":1,"a":[1,2]}"#) == "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1\n}")
        #expect(try Toolbox.transform("json_minify", "{ \"a\" : \"x/y\" }") == #"{"a":"x/y"}"#)
        #expect(throws: (any Error).self, "Foundation accepts it; JSON doesn't") { try Toolbox.transform("json_pretty", #"[1, 2,]"#) }
        #expect(Toolbox.trailingComma(#"{"s":"a,]","t":[1]}"#) == nil, "a comma inside a string is text")
        #expect(try Toolbox.transform("base64_decode", "aGVsbG8gd29ybGQ") == "hello world", "URL-safe, no padding")
        #expect(try Toolbox.transform("url_encode", "a b&c=d") == "a%20b%26c%3Dd")
        #expect(try Toolbox.transform("hex_decode", try Toolbox.transform("hex_encode", "Sidefolk")) == "Sidefolk")
        #expect(try Toolbox.transform("md5", "") == "d41d8cd98f00b204e9800998ecf8427e")
        let jwt = try Toolbox.transform("jwt_decode", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMiLCJleHAiOjE3MDAwMDAwMDB9.sig")
        #expect(jwt.contains("\"sub\" : \"123\"") && jwt.contains("Expires: 2023-11-14T22:13:20Z (expired)"), "\(jwt)")
        #expect(try Toolbox.timestamp("1700000000000").contains("UTC: 2023-11-14T22:13:20Z"), "milliseconds are recognised")
        #expect(try Toolbox.transform("count", "one two\nthree") == "13 characters, 3 words, 2 lines, 13 bytes in UTF-8.")
    }

    @Test func playtimeQuestionsAndPicks() throws {
        #expect(Trivia.bank.count >= 50)
        #expect(Set(Trivia.bank.map(\.text)).count == Trivia.bank.count, "no question twice")
        #expect(Trivia.categories.count >= 8)
        for q in Trivia.bank {
            #expect(q.choices.count == 4 && (0..<4).contains(q.answer) && Set(q.choices).count == 4 && !q.fact.isEmpty, "\(q.text)")
        }
        let number = try Chance.number(3, 3)
        #expect(number == "Picked 3 (from 3 to 3).")
        #expect(throws: (any Error).self) { try Chance.number(5, 1) }
        #expect(try Chance.pick(["tea"], count: 1) == "Picked: tea.")
        #expect(throws: (any Error).self) { try Chance.pick(["tea"], count: 2) }
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
