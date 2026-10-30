import Foundation
import Testing
@testable import SidefolkCore

@Suite struct UpdateCheckerTests {
    private func checker(_ replies: [FakeTransport.Reply], clock: ManualClock, db: AppDatabase) -> (UpdateChecker, FakeTransport) {
        let transport = FakeTransport(replies)
        return (UpdateChecker(transport: transport, kv: KVStore(db), clock: clock), transport)
    }

    private var list: Data { ReleaseFeedTests.feed(ReleaseFeedTests.release("v0.1.0-snapshot.430")) }

    @Test func asksGitHubPlainlyAndReusesAnUnchangedList() async throws {
        let db = try AppDatabase.inMemory()
        let clock = ManualClock(TestEnv.referenceDate)
        let (checker, transport) = checker([
            .response(HTTPResponse(status: 200, headers: ["ETag": #"W/"abc""#], body: list)),
            .response(HTTPResponse(status: 304)),
        ], clock: clock, db: db)

        #expect(try await checker.check().map(\.tag) == ["v0.1.0-snapshot.430"])
        clock.advance(60)
        #expect(try await checker.check().map(\.tag) == ["v0.1.0-snapshot.430"])

        let first = transport.requests[0], second = transport.requests[1]
        #expect(first.method == "GET")
        #expect(first.url.absoluteString == "https://api.github.com/repos/ghassenbrg/sidefolk/releases?per_page=30")
        #expect(first.headers["User-Agent"] == "Sidefolk/\(SidefolkVersion.current)")
        #expect(first.headers["If-None-Match"] == nil)
        #expect(first.body == nil)
        // Nothing but what GitHub asks of a client: no account, no key, nothing about the person.
        #expect(Set(first.headers.keys) == ["Accept", "X-GitHub-Api-Version", "User-Agent"])
        #expect(second.headers["If-None-Match"] == #"W/"abc""#)

        // Kept between launches.
        let again = UpdateChecker(transport: FakeTransport([]), kv: KVStore(db), clock: clock)
        let state = await again.state()
        #expect(state.offers.map(\.tag) == ["v0.1.0-snapshot.430"])
        #expect(state.lastCheck == clock.now)
    }

    @Test func failuresSayWhatHappenedAndKeepTheLastList() async throws {
        let db = try AppDatabase.inMemory()
        let clock = ManualClock(TestEnv.referenceDate)
        let (checker, _) = checker([
            .response(HTTPResponse(status: 200, body: list)),
            .response(HTTPResponse(status: 403)),
            .failure(URLError(.notConnectedToInternet)),
            .response(HTTPResponse(status: 200, body: Data("<html>".utf8))),
            .response(HTTPResponse(status: 502)),
        ], clock: clock, db: db)
        _ = try await checker.check()
        let when = await checker.state().lastCheck

        for expected in ["GitHub asked Sidefolk to wait", "couldn't reach GitHub", "doesn't read", "status 502"] {
            clock.advance(60)
            let error = await #expect(throws: UserFacingError.self) { try await checker.check() }
            #expect(error?.message.contains(expected) == true, "\(error?.message ?? "")")
        }
        let state = await checker.state()
        #expect(state.offers.count == 1)
        #expect(state.lastCheck == when)
    }

    @Test func dueOnceADayAndAgainIfTheClockMovesBack() async throws {
        let db = try AppDatabase.inMemory()
        let clock = ManualClock(TestEnv.referenceDate)
        let (checker, _) = checker([.response(HTTPResponse(status: 200, body: list))], clock: clock, db: db)
        #expect(await checker.isDue())
        _ = try await checker.check()
        #expect(await !checker.isDue())
        clock.advance(3600)
        #expect(await checker.isDue(after: 3600))
        #expect(await !checker.isDue())
        clock.advance(UpdateChecker.interval)
        #expect(await checker.isDue())
        clock.set(TestEnv.referenceDate.addingTimeInterval(-60))
        #expect(await checker.isDue())
    }

    @Test func aVersionIsBroughtUpAgainTheNextDay() async throws {
        let db = try AppDatabase.inMemory()
        let clock = ManualClock(TestEnv.referenceDate)
        let (checker, _) = checker([.response(HTTPResponse(status: 200, body: list))], clock: clock, db: db)
        let offer = try #require(try await checker.check().first)
        #expect(await checker.shouldAsk(about: offer))
        await checker.markAsked(offer)
        clock.advance(6 * 3_600)
        #expect(await !checker.shouldAsk(about: offer))
        var newer = offer
        newer.version = ReleaseVersion("0.1.0-snapshot.431")!
        #expect(await checker.shouldAsk(about: newer))
        clock.advance(UpdateChecker.askAgainAfter)
        #expect(await checker.shouldAsk(about: offer))
    }

    /// Reads the real list of releases. Opt in: SIDEFOLK_LIVE_NETWORK=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIDEFOLK_LIVE_NETWORK"] == "1"))
    func liveReleases() async throws {
        let checker = UpdateChecker(kv: nil)
        let offers = try await checker.check()
        #expect(!offers.isEmpty)
        for offer in offers {
            #expect(offer.image.url.host == "github.com")
            #expect(offer.checksum != nil)
            #expect(offer.image.size > 1_000_000)
        }
    }
}
