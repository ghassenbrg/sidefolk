import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The founder's three requests, end to end: without AI through the local parser, and with a scripted model
/// through the real agent loop, Guard, the watcher engine and the scheduler. Before D35 Sidefolk refused all three:
/// the parser left them to the AI, the weather and CPU could only be change alerts clamped to 5 min and 1 min,
/// and "every 30 minutes" was not a time a reminder could take.
@Suite struct RepeatingRequestsTests {
    let runtime: SidefolkRuntime
    let clock = ManualClock(TestEnv.referenceDate)
    let fetcher = FakeFetcher()
    let sampler = FakeSampler()

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-founder-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
        // The real engine and tools, with the Mac and the web played by the test.
        await runtime.watchers.register(MetricProbe(system: sampler, settle: 0))
        await runtime.watchers.register(WeatherProbe(fetcher: fetcher))
    }

    /// The agent loop over `model`, as the Ask panel runs it, with the live state in its context.
    func agent(_ model: ScriptedModel) -> AgentRuntime {
        var settings = AppSettings()
        settings.provider.kind = .anthropic
        let clock = self.clock
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let live = LiveStateSummary.provider(db: runtime.db, clock: clock)
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, sources: ContextSources(liveState: live), clock: clock)
        return AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context, factory: factory,
                            settings: { [settings] in settings }, clock: clock)
    }

    func ask(_ text: String, _ model: ScriptedModel) async -> [AgentEvent] {
        await collect(await agent(model).submit(AgentRequest(text: text)).events)
    }

    /// Without AI, as the Ask panel does it: parse, then run through the tools as the user.
    func local(_ text: String) async throws -> LocalOutcome {
        let runner = LocalIntentRunner(runtime: runtime)
        let parsed = try #require(await runner.parse(text), "“\(text)” should be understood without AI")
        return await runner.run(parsed.intent)
    }

    func card(_ outcome: LocalOutcome) throws -> ResultCard {
        guard case .card(let card, _, _) = outcome else {
            Issue.record("expected a card, got \(outcome)")
            throw CancellationError()
        }
        return card
    }

    /// What the model was told after its tool calls.
    func results(_ model: ScriptedModel) -> [ToolResultMessage] {
        model.requests.flatMap { r in r.messages.compactMap { m -> [ToolResultMessage]? in
            if case .toolResults(let results) = m { return results } else { return nil }
        }.flatMap { $0 } }
    }

    func decisions(_ tool: String) async throws -> [ActivityEntry.Decision] {
        try await runtime.activity.recent().filter { $0.tool == tool }.map(\.decision)
    }

    /// The next `count` live values published on the bus while `work` runs.
    func readings(_ count: Int, during work: () async -> Void) async -> [WatchReading] {
        let stream = runtime.events.stream()
        let listener = Task { () -> [WatchReading] in
            var seen: [WatchReading] = []
            for await e in stream {
                if case .watchReading(let r) = e { seen.append(r) }
                if seen.count == count { break }
            }
            return seen
        }
        await work()
        return await listener.value
    }

    static let geocode = #"{"results":[{"name":"Fukuoka","latitude":33.6,"longitude":130.41667,"country":"Japan"}]}"#
    static func forecast(_ t: Double) -> String { #"{"current":{"temperature_2m":\#(t)}}"# }

    // MARK: "check the temperature in Fukuoka every 1 minute and tell me"

    @Test func fukuokaWithoutAI() async throws {
        fetcher.say(Self.geocode, headers: ["content-type": "application/json"])
        fetcher.say(Self.forecast(18.4), headers: ["content-type": "application/json"])
        let shown = try card(try await local("check the temperature in Fukuoka every 1 minute and tell me"))
        #expect(shown.title == "Showing Temperature in Fukuoka every 1 min")
        #expect(shown.subtitle?.hasPrefix("Now ") == true)
        #expect(shown.detail == "Stops Tomorrow \(TimeFormat.clock(clock.now, calendar: .autoupdatingCurrent))")
        #expect(try await decisions("watch.report") == [.auto], "the user's own request needs no approval")

        // Every minute a new value, in place.
        fetcher.say(Self.forecast(19.1), headers: ["content-type": "application/json"])
        let next = await readings(1) {
            clock.advance(60)
            await runtime.watchers.tick()
        }
        #expect(next.first?.title == "Temperature in Fukuoka")
        #expect(next.first?.intervalS == 60)

        let stopped = try card(try await local("stop the Fukuoka temperature"))
        #expect(stopped.title == "Stopped showing Temperature in Fukuoka")
        #expect(await runtime.watchers.list().isEmpty)
    }

    @Test func fukuokaWithAI() async throws {
        fetcher.say(Self.geocode, headers: ["content-type": "application/json"])
        fetcher.say(Self.forecast(18.4), headers: ["content-type": "application/json"])
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "watch_report", input: ["source": "weather", "place": "Fukuoka", "every_seconds": 60])])),
            .turn(.reply("It's 18.4 °C in Fukuoka. I'll update it every minute until tomorrow at 10:00.")),
        ])
        let events = await ask("check the temperature in Fukuoka every 1 minute and tell me", model)

        // The model was told how to do it, and was offered the tool.
        let first = try #require(model.requests.first)
        #expect(first.system.contains("use watch.report"))
        #expect(first.system.contains("never refuse a request for being too frequent"))
        #expect(first.tools.contains { $0.name == "watch.report" })
        // Guard let it through without asking: low risk, no address the model built.
        #expect(try await decisions("watch.report") == [.auto])
        let result = try #require(results(model).first)
        #expect(!result.isError)
        #expect(result.content.contains("it reads 18.4 °C now"))
        #expect(result.content.contains("It stops on its own at"))
        #expect(events.compactMap(\.reply).first?.cards.first?.title == "Showing Temperature in Fukuoka every 1 min")

        let w = try #require(await runtime.watchers.list().first)
        #expect(w.kind == WatchKind.weather && w.mode == .report && w.intervalS == 60 && w.source == "user:agent")
        #expect(w.expiresAt == clock.now.addingTimeInterval(WatchLimits.reportLifetime))

        // A follow-up turn sees it in "Right now", and stopping is one call.
        let stop = ScriptedModel([
            .turn(.calling([ToolCall(id: "c2", name: "watch_stop", input: ["id": "Temperature in Fukuoka"])])),
            .turn(.reply("Stopped.")),
        ])
        _ = await ask("stop the Fukuoka temperature", stop)
        #expect(stop.requests.first?.system.contains("Showing live: “Temperature in Fukuoka” every 1 min") == true)
        #expect(results(stop).first?.content == "Stopped showing Temperature in Fukuoka.")
        #expect(await runtime.watchers.list().isEmpty)
    }

    // MARK: "watch the CPU usage and every 10 seconds tell me how much it is now"

    @Test func cpuEveryTenSecondsWithoutAI() async throws {
        let shown = try card(try await local("watch the CPU usage and every 10 seconds tell me how much it is now"))
        #expect(shown.title == "Showing CPU every 10 s")
        #expect(shown.subtitle == "Now 25%")
        let w = try #require(await runtime.watchers.list().first)
        #expect(w.expiresAt == clock.now.addingTimeInterval(3600), "under a minute: an hour, then it stops")

        sampler.set { $0.cpuStep = CPUTicks(busy: 60, total: 100) }
        let values = await readings(3) {
            for _ in 0..<3 {
                clock.advance(10)
                await runtime.watchers.tick()
            }
        }
        #expect(values.map(\.value) == ["60%", "60%", "60%"])

        let stopped = try card(try await local("stop telling me the CPU"))
        #expect(stopped.title == "Stopped showing CPU")
        #expect(await runtime.watchers.list().isEmpty)
    }

    @Test func cpuEveryTwoSecondsWithAIIsRaisedAndSaid() async throws {
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "watch_report", input: ["source": "metric", "metric": "cpu", "every_seconds": 2,
                                                                                    "until_stopped": true])])),
            .turn(.reply("Every 5 seconds is the fastest; showing the CPU every 5 s until you stop it.")),
        ])
        _ = await ask("every 2 seconds tell me the CPU until I stop it", model)
        let result = try #require(results(model).first)
        #expect(result.content.contains("Every 2 s is faster than this kind of report allows; 5 s is the fastest"))
        #expect(result.content.contains("It keeps going until the user stops it."))
        let w = try #require(await runtime.watchers.list().first)
        #expect(w.intervalS == 5 && w.expiresAt == nil)
    }

    // MARK: Reminders more often than daily

    @Test func remindersEveryFewMinutesWithoutAI() async throws {
        await runtime.scheduler.start()
        let set = try card(try await local("remind me every 30 minutes to stretch"))
        #expect(set.title == "Stretch")
        #expect(set.subtitle?.hasSuffix("every 30 minutes") == true)
        let r = try #require(await runtime.scheduler.upcoming().first)
        #expect(r.recurrence == Recurrence(frequency: .minutely, interval: 30))
        #expect(r.fireAt == clock.now.addingTimeInterval(1800))

        clock.advance(1800)
        await runtime.scheduler.tick()
        let bubble = try #require(await runtime.attention.open().first)
        #expect(bubble.title == "Stretch")
        #expect(bubble.body == "Every 30 minutes")
        #expect(bubble.actions.map(\.id) == ["done", "snooze10", "stop"])
        #expect(await runtime.scheduler.upcoming().first?.fireAt == clock.now.addingTimeInterval(1800))
        await runtime.scheduler.stop()
    }

    @Test func remindersEveryTwoHoursUntilSixWithAI() async throws {
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "reminders_create", input: ["title": "Drink water", "when": "every 2 hours until 6pm"])])),
            .turn(.reply("I'll remind you to drink water every 2 hours until 18:00.")),
        ])
        _ = await ask("remind me to drink water every 2 hours until 6pm", model)
        #expect(try await decisions("reminders.create") == [.auto])
        let result = try #require(results(model).first)
        #expect(result.content.contains("repeating every 2 hours until"))
        let r = try #require(await runtime.scheduler.upcoming().first)
        #expect(r.recurrence?.frequency == .hourly && r.recurrence?.interval == 2)
        #expect(r.recurrence?.until != nil)
    }
}
