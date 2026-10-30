import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Reports: a value told every few seconds or minutes, in place, with a floor and an end (D35).
@Suite struct ReportTests {
    let env: WatchEnv
    let sampler = FakeSampler()
    let engine: WatcherEngine

    init() throws {
        env = try WatchEnv()
        engine = env.reportEngine(sampler)
    }

    func run(_ tool: String, _ input: JSONValue, as caller: Caller = .user, typed: String = "") async -> ToolOutcome {
        await env.base.executor.execute(name: tool, input: input, caller: caller, mentions: UserMentions(text: typed))
    }

    func ok(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else {
            Issue.record("expected success, got \(outcome.status)")
            throw CancellationError()
        }
        return r
    }

    func failure(_ outcome: ToolOutcome) -> String? {
        if case .failed(let e) = outcome.status { return e.message }
        return nil
    }

    var now: Date { env.clock.now }

    // MARK: Metrics

    @Test func aCPUReportReadsAtOnceAndSaysWhenItStops() async throws {
        let result = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        #expect(result.text.hasPrefix("Showing CPU every 10 s, live beside the companion; it reads 25% now."))
        #expect(result.text.contains("It stops on its own at") && result.text.contains("in 60 min"))
        #expect(result.card?.title == "Showing CPU every 10 s")
        #expect(result.card?.subtitle == "Now 25%")
        #expect(result.card?.detail?.hasPrefix("Stops ") == true)
        #expect(!result.untrusted, "the Mac's own numbers are not someone else's text")

        let w = try #require(await engine.list().first)
        #expect(w.kind == WatchKind.metric && w.mode == .report && w.intervalS == 10)
        #expect(w.expiresAt == now.addingTimeInterval(WatchLimits.fastReportLifetime))
        #expect(await engine.latestReadings().map(\.value) == ["25%"])
        // The first look took two samples a moment apart, so its first value is a real rate.
        #expect(sampler.samples == 2)
    }

    /// The model quoted "8.59 GB used of 17.18 GB" while the pill said "8 GB of 16 GB": RAM is counted in binary units.
    @Test func memoryReadsTheSameForThePersonAndTheModel() async throws {
        let result = try ok(await run("watch.report", ["source": "metric", "metric": "memory", "every_seconds": 60]))
        #expect(result.text.contains("it reads 8 GB used of 16 GB now"), "\(result.text)")
        #expect(result.card?.subtitle == "Now 8 GB of 16 GB")
    }

    @Test func tooFastIsRaisedToTheFloorAndSaid() async throws {
        let result = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 1]))
        #expect(await engine.list().first?.intervalS == ReportFloors.metric)
        #expect(result.text.contains("Every 1 s is faster than this kind of report allows; 5 s is the fastest, so it reads every 5 s."))
        #expect(result.card?.detail?.contains("Every 5 s is the fastest for this; I'll check every 5 s.") == true)
        #expect(result.card?.title == "Showing CPU every 5 s")
    }

    @Test func theEndFollowsTheIntervalUnlessTheyAskedOtherwise() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "memory", "every_seconds": 300]))
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "disk", "every_seconds": 30, "until_stopped": true]))
        let forever = try ok(await run("watch.report", ["source": "metric", "metric": "battery", "every_seconds": 60, "until": "in 2 hours"]))
        let all = Dictionary(uniqueKeysWithValues: await engine.list().map { ($0.config.string("metric") ?? "", $0) })
        #expect(all["memory"]?.expiresAt == now.addingTimeInterval(WatchLimits.reportLifetime))
        #expect(all["disk"]?.expiresAt == nil)
        #expect(all["battery"]?.expiresAt == now.addingTimeInterval(7200))
        #expect(forever.text.contains("in 2 h"))
        let stopped = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 30, "until_stopped": true]))
        #expect(stopped.card?.detail == "Keeps going until you stop it")
    }

    @Test func otherAgentsReportsStillEndWithinADay() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 60, "until_stopped": true],
                             as: .external(client: "claude-code")))
        #expect(await engine.list().first?.expiresAt == now.addingTimeInterval(WatchLimits.externalExpiry))
    }

    @Test func everyMetricReadsInWords() async throws {
        for metric in ["memory", "battery", "disk", "network"] {
            _ = try ok(await run("watch.report", ["source": "metric", "metric": .string(metric), "every_seconds": 60]))
        }
        let values = Dictionary(uniqueKeysWithValues: await engine.latestReadings().map { ($0.title, $0.value) })
        #expect(values["Memory"] == "8 GB of 16 GB")
        #expect(values["Battery"] == "84%, charging")
        #expect(values["Free disk"] == "182 GB free")
        #expect(values["Network"] == "↓ 2 MB/s ↑ 100 kB/s")
    }

    @Test func aMacWithoutABatterySaysSoAndKeepsNothing() async throws {
        sampler.set { $0.battery = nil }
        let outcome = await run("watch.report", ["source": "metric", "metric": "battery", "every_seconds": 60])
        #expect(failure(outcome) == "This Mac has no battery.")
        #expect(await engine.list().isEmpty)
    }

    @Test func readingsTravelAsEventsNotAsListChanges() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        await engine.start()
        let events = env.base.events.stream()
        let collected = Task { () -> (readings: [WatchReading], lists: Int) in
            var readings: [WatchReading] = []
            var lists = 0
            for await e in events {
                switch e {
                case .watchReading(let r): readings.append(r)
                case .dataChanged(.watchers): lists += 1
                default: break
                }
                if readings.count == 3 { break }
            }
            return (readings, lists)
        }
        for _ in 0..<3 {
            env.clock.advance(10)
            await engine.tick()
        }
        let seen = await collected.value
        #expect(seen.readings.map(\.value) == ["25%", "25%", "25%"])
        #expect(seen.readings.allSatisfy { $0.title == "CPU" && $0.intervalS == 10 && !$0.notify })
        #expect(seen.lists == 0, "a new value alone must not make every list reload")
        await engine.stop()
    }

    @Test func valuesReachTheDatabaseOnlyWithTheRoutineSaves() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        let id = try #require(await engine.list().first?.id)
        let firstSaved = try #require(try await env.store.watcher(id: id)?.lastCheckedAt)
        for _ in 0..<12 {   // two minutes of readings
            env.clock.advance(10)
            await engine.tick()
        }
        #expect(try await env.store.watcher(id: id)?.lastCheckedAt == firstSaved)
        sampler.set { $0.cpuStep = CPUTicks(busy: 50, total: 100) }
        for _ in 0..<20 {   // past five minutes since the last save
            env.clock.advance(10)
            await engine.tick()
        }
        let saved = try #require(try await env.store.watcher(id: id))
        #expect(saved.lastCheckedAt! > firstSaved)
        #expect(saved.lastState?["reading"]?.string("shown") == "50%")
        // After a restart the last saved value shows until the first new reading.
        let restarted = env.engine(probes: WatchProbes.standard(fetcher: env.fetcher, throttle: env.throttle, system: sampler, settle: 0))
        #expect(await restarted.latestReadings().map(\.value) == ["50%"])
    }

    @Test func aReportEndsQuietlyWithAWayToKeepGoing() async throws {
        await engine.start()
        defer { Task { await engine.stop() } }
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        let id = try #require(await engine.list().first?.id)
        env.clock.advance(3601)
        await engine.tick()
        #expect(await engine.watcher(id: id)?.state == .expired)
        let notice = try #require(await env.notices().first)
        #expect(notice.title == "I stopped showing CPU")
        #expect(notice.level == .gentle)
        #expect(notice.actions.map(\.id) == ["keep", "stop"])

        await env.attention.respond(id: notice.id, actionId: "keep")
        let again = try #require(await engine.watcher(id: id))
        #expect(again.state == .active)
        #expect(again.expiresAt == env.clock.now.addingTimeInterval(WatchLimits.fastReportLifetime))
    }

    @Test func liveValuesAreFewAtATime() async throws {
        for metric in ["cpu", "memory", "disk", "network"] {
            _ = try ok(await run("watch.report", ["source": "metric", "metric": .string(metric), "every_seconds": 60]))
        }
        let fifth = await run("watch.report", ["source": "metric", "metric": "battery", "every_seconds": 60])
        #expect(failure(fifth) == "I'm already showing 4 live values. Stop one first.")
    }

    @Test func stoppingAReportSaysShowing() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        let stopped = try ok(await run("watch.stop", ["id": "CPU"]))
        #expect(stopped.text == "Stopped showing CPU.")
        #expect(await engine.list().isEmpty)
        #expect(await engine.latestReadings().isEmpty)
    }

    /// Today's tiles draw a line of the last values (D58): numbers only, the last few, gone with the report.
    @Test func recentValuesMakeALineAndGoWithTheReport() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        let id = try #require(await engine.list().first?.id)
        for _ in 0..<(WatcherEngine.historyLength + 5) {
            env.clock.advance(10)
            await engine.tick()
        }
        let line = try #require(await engine.recentValues()[id])
        #expect(line.count == WatcherEngine.historyLength && line.allSatisfy { $0 == 25 })
        _ = try ok(await run("watch.stop", ["id": "CPU"]))
        #expect(await engine.recentValues()[id] == nil)
    }

    @Test func theFirstNumberInAValueIsRead() {
        #expect(WatchReading.number(in: "34%") == 34)
        #expect(WatchReading.number(in: "18.5 °C") == 18.5)
        #expect(WatchReading.number(in: "1,2 GB") == 1.2)
        #expect(WatchReading.number(in: "-3 °C") == -3)
        #expect(WatchReading.number(in: "Rain") == nil)
    }

    @Test func checksDueAMomentApartShareAWakeUp() async throws {
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 10]))
        env.clock.advance(0.3)
        _ = try ok(await run("watch.report", ["source": "metric", "metric": "memory", "every_seconds": 10]))
        env.clock.advance(9.8)  // the CPU is due, the memory 0.2 s later: one tick reads both
        await engine.tick()
        let checked = await engine.list().map { $0.lastCheckedAt }
        #expect(checked.allSatisfy { $0 == env.clock.now })
    }

    // MARK: Weather

    static let geocode = #"{"results":[{"name":"Fukuoka","latitude":33.6,"longitude":130.41667,"country":"Japan","admin1":"Fukuoka"}]}"#
    static func forecast(_ t: Double) -> String { #"{"current":{"time":"2026-10-26T14:15","interval":900,"temperature_2m":\#(t)}}"# }

    @Test func temperatureInFukuokaEveryMinute() async throws {
        env.fetcher.say(Self.geocode, headers: ["content-type": "application/json"])
        env.fetcher.say(Self.forecast(18.4), headers: ["content-type": "application/json"])
        let result = try ok(await run("watch.report", ["source": "weather", "place": "Fukuoka", "every_seconds": 60],
                                      as: .agent(runId: "r1")))
        #expect(result.text.hasPrefix("Showing Temperature in Fukuoka every 1 min, live beside the companion; it reads 18.4 °C now."))
        #expect(result.text.contains("in 24 h"))
        #expect(!result.untrusted)
        let requests = env.fetcher.requests.map(\.url.absoluteString)
        #expect(requests[0].hasPrefix("https://geocoding-api.open-meteo.com/v1/search?name=Fukuoka"))
        #expect(requests[1] == "https://api.open-meteo.com/v1/forecast?latitude=33.6000&longitude=130.4167&current=temperature_2m")

        // The place is looked up once; after that only the weather is asked for, once a minute.
        env.fetcher.reset()
        env.fetcher.say(Self.forecast(18.9), headers: ["content-type": "application/json"])
        env.clock.advance(60)
        await engine.tick()
        #expect(env.fetcher.requests.count == 3)
        #expect(env.fetcher.requests.last?.url.host == "api.open-meteo.com")
        let w = try #require(await engine.list().first)
        #expect(w.lastState?.string("place") == "Fukuoka, Japan")
        #expect(await engine.latestReadings().first?.value.contains("18") == true || Locale.current.measurementSystem == .us)
    }

    @Test func aPlaceThatDoesNotExistIsSaidAtOnce() async throws {
        env.fetcher.say(#"{"generationtime_ms":0.5}"#, headers: ["content-type": "application/json"])
        let outcome = await run("watch.report", ["source": "weather", "place": "Atlantis", "every_seconds": 60])
        #expect(failure(outcome) == "I couldn't find a place called “Atlantis”.")
        #expect(await engine.list().isEmpty)
    }

    @Test func aRegionPicksAmongPlacesOfOneName() async throws {
        env.fetcher.say(#"{"results":[{"name":"Paris","latitude":33.66,"longitude":-95.55,"country":"United States","admin1":"Texas"},{"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France","admin1":"Île-de-France"}]}"#,
                        headers: ["content-type": "application/json"])
        env.fetcher.say(Self.forecast(12), headers: ["content-type": "application/json"])
        _ = try ok(await run("watch.report", ["source": "weather", "place": "Paris, France", "every_seconds": 600]))
        #expect(env.fetcher.requests[1].url.query?.contains("latitude=48.8500") == true)
        #expect(await engine.list().first?.title == "Temperature in Paris, France")
    }

    @Test func weatherWordsForEveryQuantity() throws {
        let current: JSONValue = ["temperature_2m": 18.4, "apparent_temperature": 17, "relative_humidity_2m": 64, "wind_speed_10m": 12.5,
                                  "precipitation": 0.2, "weather_code": 2]
        #expect(try WeatherProbe.reading(current, .temperature).forModel == "18.4 °C")
        #expect(try WeatherProbe.reading(current, .feelsLike).forModel == "17.0 °C")
        #expect(try WeatherProbe.reading(current, .humidity).forModel == "64% humidity")
        #expect(try WeatherProbe.reading(current, .humidity).shown == "64%")
        #expect(try WeatherProbe.reading(current, .wind).forModel == "12.5 km/h")
        #expect(try WeatherProbe.reading(current, .precipitation).forModel == "0.2 mm")
        #expect(try WeatherProbe.reading(current, .conditions).forModel == "partly cloudy, 18.4 °C")
        #expect(try WeatherProbe.reading(current, .conditions).shown.hasPrefix("Partly cloudy, "))
    }

    @Test func placeNamesStayPlaceNames() {
        #expect(WeatherProbe.cleanPlace("Fukuoka") == "Fukuoka")
        #expect(WeatherProbe.cleanPlace("São Paulo, Brazil") == "São Paulo, Brazil")
        #expect(WeatherProbe.cleanPlace("Paris\u{202E}") == nil)
        #expect(WeatherProbe.cleanPlace("<script>") == nil)
        #expect(WeatherProbe.cleanPlace(String(repeating: "a", count: 61)) == nil)
    }

    // MARK: Web values

    @Test func aWebValueByJSONPath() async throws {
        env.fetcher.say(#"{"data":[{"price":"42.10","currency":"EUR"}]}"#, headers: ["content-type": "application/json"])
        let result = try ok(await run("watch.report", ["source": "web", "url": "https://shop.example.com/api/item", "json_path": "data[0].price",
                                                       "every_seconds": 120], typed: "https://shop.example.com/api/item"))
        #expect(result.text.contains("it reads 42.10 now"))
        #expect(result.untrusted, "a value from a web page is someone else's text")
        #expect(result.card?.title == "Showing Value on shop.example.com/api/item every 2 min")
    }

    @Test func aModelBuiltAddressWaitsForTheUser() async throws {
        env.fetcher.say("<p>Price: <span class=\"price\">$12</span></p>")
        let approvals = env.base.autoAnswer(.allowOnce)
        let outcome = await run("watch.report", ["source": "web", "url": "https://shop.example.com/item?ref=abc", "selector": "span.price",
                                                 "every_seconds": 60], as: .agent(runId: "r1"))
        let asked = try #require(await approvals.value)
        #expect(asked.tool == "watch.report" && asked.risk == .medium)
        #expect(try ok(outcome).text.contains("it reads $12 now"))
    }

    @Test func aValueNeverFoundIsNoReport() async throws {
        env.fetcher.say(#"{"data":[]}"#, headers: ["content-type": "application/json"])
        let outcome = await run("watch.report", ["source": "web", "url": "https://shop.example.com/api", "json_path": "data[0].price",
                                                 "every_seconds": 60], typed: "https://shop.example.com/api")
        #expect(failure(outcome) == "I found no value at “data[0].price” on shop.example.com/api.")
        #expect(await engine.list().isEmpty)
    }

    @Test func extractingValues() throws {
        func value(_ body: String, _ config: JSONValue, type: String = "text/html") throws -> String? {
            ValueExtractor.value(in: Data(body.utf8), contentType: type, rule: try ValueExtractor.rule(from: config))
        }
        let json = #"{"current":{"temperature_2m":18.4,"ok":true,"n":3},"list":[[1,2],[3,4]]}"#
        #expect(try value(json, ["json_path": "current.temperature_2m"]) == "18.4")
        #expect(try value(json, ["json_path": "$.current.n"]) == "3")
        #expect(try value(json, ["json_path": "list[1][0]"]) == "3")
        #expect(try value(json, ["json_path": "current"]) == nil, "an object is not a value")
        let html = #"<div id="total">Total: <b>1 024</b></div><span class='price big'>€9,99</span><td>first</td>"#
        #expect(try value(html, ["selector": "#total"]) == "Total: 1 024")
        #expect(try value(html, ["selector": "span.price"]) == "€9,99")
        #expect(try value(html, ["selector": ".big"]) == "€9,99")
        #expect(try value(html, ["selector": "td"]) == "first")
        #expect(try value(html, ["regex": #"Total:\s*<b>([\d ]+)"#]) == "1 024")
        #expect(try value("CPU usage: 5.12% user", ["regex": #"[\d.]+%"#], type: "text/plain") == "5.12%")
        #expect(throws: WatchError.self) { try ValueExtractor.rule(from: ["selector": "div > span"]) }
        #expect(throws: WatchError.self) { try ValueExtractor.rule(from: ["json_path": "a..b"]) }
        #expect(throws: WatchError.self) { try ValueExtractor.rule(from: ["regex": "("]) }
        #expect(throws: WatchError.self) { try ValueExtractor.rule(from: ["regex": "a", "selector": "b"]) }
    }

    // MARK: Commands

    @Test func aCommandsOutputEveryTenSeconds() async throws {
        let result = try ok(await run("watch.command", ["command": "echo starting; echo 'load 0.42'", "report": true, "every_seconds": 3]))
        let w = try #require(await engine.list().first)
        #expect(w.mode == .report && w.intervalS == ReportFloors.command)
        #expect(result.text.contains("it reads load 0.42 now"))
        #expect(result.text.contains("10 s is the fastest"))
        #expect(result.untrusted)
    }

    @Test func reportIsNotAModeOfItsOwnElsewhere() async throws {
        let outcome = await run("watch.create", ["kind": "file_changes", "target": "/tmp/x", "mode": "report"])
        #expect(failure(outcome) != nil)
    }

    // MARK: The real Mac

    @Test func theMacAnswers() throws {
        let mac = MacSampler()
        let ticks = try #require(mac.cpuTicks())
        #expect(ticks.total > 0 && ticks.busy <= ticks.total)
        let memory = try #require(mac.memory())
        #expect(memory.used > 0 && memory.used <= memory.total)
        let disk = try #require(mac.disk())
        #expect(disk.free > 0 && disk.free <= disk.total)
        #expect(mac.networkBytes() != nil)
        if let battery = mac.battery() { #expect((0...100).contains(battery.percent)) }
    }
}
