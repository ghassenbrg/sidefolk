import Foundation
import Synchronization
import Testing
@testable import SidefolkCore
@testable import ext_weather

/// Requests that need a place and name none (D48): the person's own place when they share it, else a question with a
/// way to Settings, never a guess.
@Suite struct PlaceInRequestsTests {
    let fukuoka = LocationTests.fukuoka

    // MARK: Understood without AI

    func parse(_ text: String, here: String?) -> ParsedIntent? {
        IntentParser(when: TimeTest.parser(), home: "/Users/test", here: here).parse(text, now: TimeTest.wednesday10)
    }

    @Test func noPlaceNamedIsWhereThePersonIs() {
        let found = parse("every minute tell me the temperature", here: "Fukuoka, Japan")
        #expect(found?.intent == .report(ReportIntent(source: .weather(place: "Fukuoka, Japan", quantity: .temperature), everySeconds: 60)))
        #expect(found?.hint == "Show Temperature in Fukuoka, Japan every 1 min · no AI")
        #expect(parse("show me the weather here every hour", here: "Fukuoka, Japan")?.intent
            == .report(ReportIntent(source: .weather(place: "Fukuoka, Japan", quantity: .conditions), everySeconds: 3600)))
        // A place named is that place, wherever the person is.
        #expect(parse("temperature in Lyon every minute", here: "Fukuoka, Japan")?.intent
            == .report(ReportIntent(source: .weather(place: "Lyon", quantity: .temperature), everySeconds: 60)))
    }

    @Test func noPlaceKnownAsksWhich() {
        let asked = parse("every minute tell me the temperature", here: nil)
        #expect(asked?.intent == .needsPlace(.temperature))
        #expect(asked?.hint == "Needs a place · no AI")
        #expect(parse("humidity every 10 minutes", here: nil)?.intent == .needsPlace(.humidity))
        // Not about the weather, or about two things: left alone as before.
        #expect(parse("tell me the cpu temperature every minute", here: nil) == nil)
        #expect(parse("temperature and humidity every minute", here: nil) == nil)
    }

    @Test func theAppsParserKnowsThePlaceTheRunnerAsksWithoutIt() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-place-\(UUID().uuidString)", isDirectory: true)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                            clock: ManualClock(TestEnv.referenceDate))
        let runner = LocalIntentRunner(runtime: runtime)
        let asked = try #require(await runner.parse("every minute tell me the temperature"))
        guard case .needsPlace(let card) = await runner.run(asked.intent) else {
            Issue.record("expected the question")
            return
        }
        #expect(card.url == SettingsLink.yourLocation.rawValue && SettingsLink.isKnown(card.url))
        #expect(await runtime.watchers.list().isEmpty)

        let place = fukuoka
        await runtime.settings.update { $0.location = LocationSettings(source: .chosen, place: place) }
        #expect(await runner.parse("every minute tell me the temperature")?.intent
            == .report(ReportIntent(source: .weather(place: "Fukuoka, Japan", quantity: .temperature), everySeconds: 60)))
    }

    // MARK: Reports from the AI or the parser

    final class Here: Sendable {
        let place = Mutex<KnownPlace?>(nil)
    }

    struct Fixture {
        let env: WatchEnv
        let engine: WatcherEngine
        let here = Here()

        init() throws {
            env = try WatchEnv()
            engine = env.engine(probes: WatchProbes.standard(fetcher: env.fetcher, throttle: env.throttle, settle: 0))
            let here = self.here
            env.base.registry.register(WatchTools.make(engine: engine, parser: { WhenParser(calendar: .current) },
                                                       here: { here.place.withLock { $0 } }))
        }

        func report(_ input: JSONValue) async -> ToolOutcome {
            await env.base.executor.execute(name: "watch.report", input: input, caller: .agent(runId: "r1"))
        }
    }

    static let forecast = #"{"current":{"time":"2026-10-26T14:15","interval":900,"temperature_2m":18.4}}"#

    @Test func theWeatherHereAsksAboutExactlyHere() async throws {
        let f = try Fixture()
        f.here.place.withLock { $0 = fukuoka }
        f.env.fetcher.say(Self.forecast, headers: ["content-type": "application/json"])
        guard case .ok(let result) = await f.report(["source": "weather", "every_seconds": 60]).status else {
            Issue.record("expected a report")
            return
        }
        #expect(result.text.hasPrefix("Showing Temperature in Fukuoka, Japan every 1 min"))
        // No lookup by name: the person's own coordinates, straight to the forecast.
        let asked = f.env.fetcher.requests.map(\.url.absoluteString)
        #expect(asked == ["https://api.open-meteo.com/v1/forecast?latitude=33.5900&longitude=130.4000&current=temperature_2m"])
        let watcher = try #require(await f.engine.list().first)
        #expect(watcher.config["latitude"]?.doubleValue == 33.59)
        let activity = try #require(try await f.env.base.activity.recent(limit: 1).first)
        #expect(activity.summary == "Show Temperature in Fukuoka, Japan every 1 min", "Activity names the place too")
        // Named by its city, it is still here.
        f.env.fetcher.reset()
        f.env.fetcher.say(Self.forecast, headers: ["content-type": "application/json"])
        _ = await f.report(["source": "weather", "place": "Fukuoka", "quantity": "humidity", "every_seconds": 600])
        #expect(f.env.fetcher.requests.last?.url.query?.contains("latitude=33.5900") == true)
    }

    @Test func anotherPlaceIsLookedUpByName() async throws {
        let f = try Fixture()
        f.here.place.withLock { $0 = fukuoka }
        f.env.fetcher.say(ReportTests.geocode.replacingOccurrences(of: "Fukuoka", with: "Lyon"), headers: ["content-type": "application/json"])
        f.env.fetcher.say(Self.forecast, headers: ["content-type": "application/json"])
        _ = await f.report(["source": "weather", "place": "Lyon", "every_seconds": 60])
        #expect(f.env.fetcher.requests.first?.url.host == "geocoding-api.open-meteo.com")
        #expect(try #require(await f.engine.list().first).config["latitude"] == nil)
    }

    @Test func noPlaceAndNoneKnownStartsNothingAndShowsTheWay() async throws {
        let f = try Fixture()
        guard case .ok(let result) = await f.report(["source": "weather", "every_seconds": 60]).status else {
            Issue.record("expected the tool's own answer")
            return
        }
        #expect(result.isError)
        #expect(result.text.contains("Settings › Privacy & Permissions › Your location"))
        #expect(result.card?.url == SettingsLink.yourLocation.rawValue)
        #expect(await f.engine.list().isEmpty)
        #expect(f.env.fetcher.requests.isEmpty)
    }

    // MARK: The Weather extension

    @Test func theWeatherExtensionReadsTheWayThePlaceIsWritten() {
        let paris: [[String: Any]] = [["name": "Paris", "admin1": "Texas", "country": "United States", "country_code": "US"],
                                      ["name": "Paris", "admin1": "Île-de-France", "country": "France", "country_code": "FR"]]
        #expect(Weather.pick(paris, within: nil)?["admin1"] as? String == "Texas")
        #expect(Weather.pick(paris, within: "France")?["admin1"] as? String == "Île-de-France")
        #expect(Weather.pick(paris, within: "Texas, United States")?["admin1"] as? String == "Texas")
        #expect(Weather.pick(paris, within: "fr")?["country"] as? String == "France")
        #expect(Weather.pick(paris, within: "Japan") == nil, "never another country's town of that name")
    }
}
