import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Reports (D35) meet quiet mode: "every 10 seconds tell me the CPU and notify me" while quiet is on. The pill keeps
/// updating, but no notification goes out for a value, and the report's end waits until quiet is over.
@Suite struct QuietReportTests {
    @Test func aReportInQuietModeUpdatesInPlaceAndInterruptsNothing() async throws {
        let world = try await World([])
        await world.settingsStore.update { $0.quietUntil = .distantFuture }
        await world.attention.update { $0.quiet = true }

        let readings = Shared<[WatchReading]>([])
        let lists = Shared(0)
        let stream = world.env.events.stream()
        let listener = Task {
            for await event in stream {
                if case .watchReading(let r) = event { readings.change { $0.append(r) } }
                if case .dataChanged(.watchers) = event { lists.change { $0 += 1 } }
            }
        }

        let made = await world.executor.execute(name: "watch.report", input: ["source": "metric", "metric": "cpu", "every_seconds": 10,
                                                                             "notify": true], caller: .user)
        #expect(made.isOK, "\(made.status)")
        let report = try #require(await world.engine.list().first)
        let listsAfterCreating = lists.value

        // Five minutes of readings, every 10 s.
        for _ in 0..<30 {
            world.clock.advance(10)
            _ = await world.engine.checkNow(report.id)
        }
        try await Task.sleep(for: .milliseconds(50))
        let seen = readings.value
        #expect(seen.count >= 30)
        #expect(seen.allSatisfy { $0.notify && !$0.notifies(companionVisible: true, quiet: true) }, "no banner for a value in quiet mode")
        #expect(seen.last?.notifies(companionVisible: true, quiet: false) == true, "it was asked for, so it notifies once quiet ends")
        #expect(lists.value - listsAfterCreating <= 1, "a reading every 10 s reloads no list (D35)")

        // An hour later the report ends by design: its gentle notice waits while quiet is on.
        world.clock.advance(WatchLimits.fastReportLifetime)
        _ = await world.engine.checkNow(report.id)
        let ended = try #require(try await AttentionStore(world.env.db).recent().first { $0.title.hasPrefix("I stopped showing") })
        #expect(ended.state == .pending, "held, not shown, in quiet mode")
        #expect(await world.engine.watcher(id: report.id)?.state == .expired)

        // Quiet ends: it is shown.
        await world.settingsStore.update { $0.quietUntil = nil }
        await world.attention.update { $0.quiet = false }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await AttentionStore(world.env.db).item(id: ended.id)?.state == .shown)
        listener.cancel()
        await world.engine.stop()
    }
}
