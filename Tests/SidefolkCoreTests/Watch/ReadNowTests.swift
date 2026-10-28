import Foundation
import Testing
@testable import SidefolkCore

/// "What's my CPU usage?": one value now, nothing left running (D35, amended). The model used to start a report and
/// stop it again to answer that.
@Suite struct ReadNowTests {
    let env: WatchEnv
    let sampler = FakeSampler()
    let engine: WatcherEngine

    init() throws {
        env = try WatchEnv()
        engine = env.reportEngine(sampler)
    }

    func run(_ input: JSONValue, as caller: Caller = .user) async -> ToolOutcome {
        await env.base.executor.execute(name: "watch.read", input: input, caller: caller)
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

    @Test func theCPUIsReadOnceAndNothingKeepsRunning() async throws {
        let result = try ok(await run(["source": "metric", "metric": "cpu"], as: .agent(runId: "r1")))
        #expect(result.text == "CPU use right now: 25%. Nothing keeps running.")
        #expect(result.card?.kind == .reading && result.card?.title == "CPU: 25%")
        #expect(!result.untrusted)
        #expect(await engine.list().isEmpty, "no watcher was made, so none needs stopping")
        #expect(await engine.latestReadings().isEmpty, "and no pill appears beside the companion")
        #expect(sampler.samples == 2, "a rate needs two samples a moment apart")
    }

    /// A report sampled minutes ago must not turn "now" into an average since then.
    @Test func aReadingNowTakesItsOwnTwoSamples() async throws {
        _ = try ok(await env.base.executor.execute(name: "watch.report", input: ["source": "metric", "metric": "cpu", "every_seconds": 10],
                                                   caller: .user))
        #expect(sampler.samples == 2)
        _ = try ok(await run(["source": "metric", "metric": "cpu"]))
        #expect(sampler.samples == 4)
        #expect(await engine.list().count == 1, "the report goes on as it was")
    }

    @Test func memoryAndTheBattery() async throws {
        let memory = try ok(await run(["source": "metric", "metric": "memory"]))
        #expect(memory.card?.title == "Memory: 8 GB of 16 GB")
        #expect(memory.text == "Memory in use right now: 8 GB used of 16 GB. Nothing keeps running.")
        sampler.set { $0.battery = nil }
        #expect(failure(await run(["source": "metric", "metric": "battery"])) == "This Mac has no battery.")
    }

    @Test func theTemperatureInFukuokaSaysWhichFukuoka() async throws {
        env.fetcher.say(ReportTests.geocode, headers: ["content-type": "application/json"])
        env.fetcher.say(ReportTests.forecast(18.4), headers: ["content-type": "application/json"])
        let result = try ok(await run(["source": "weather", "place": "Fukuoka"], as: .agent(runId: "r1")))
        #expect(result.text == "The temperature in Fukuoka right now (Fukuoka, Japan): 18.4 °C. Nothing keeps running.")
        #expect(result.card?.subtitle == "Fukuoka, Japan")
        #expect(result.card?.title.hasPrefix("Temperature in Fukuoka: ") == true)
        #expect(env.fetcher.requests.count == 2)
        #expect(await engine.list().isEmpty)

        env.fetcher.say(#"{"generationtime_ms":0.5}"#, headers: ["content-type": "application/json"])
        #expect(failure(await run(["source": "weather", "place": "Atlantis"])) == "I couldn't find a place called “Atlantis”.")
    }

    @Test func aWebValueIsReadLikeAReportsFirstLook() async throws {
        env.fetcher.say(#"{"data":[{"price":42.5}]}"#, headers: ["content-type": "application/json"])
        let result = try ok(await run(["source": "web", "url": "https://api.example.com/price", "json_path": "data[0].price"]))
        #expect(result.card?.title == "Value on api.example.com/price: 42.5")
        #expect(result.card?.url == "https://api.example.com/price")
        #expect(result.untrusted, "a page's value is someone else's text")
    }

    @Test func theSpecReadsWithoutChangingAnything() {
        let spec = WatchReadTool(engine: engine).spec
        #expect(spec.risk == .low && !spec.mutates && !spec.external)
        #expect(spec.capabilities == [.system, .network])
        #expect(spec.description.contains("watch.report"))
        #expect(WatchReportTool(engine: engine).spec.description.contains("is watch.read"))
    }
}
