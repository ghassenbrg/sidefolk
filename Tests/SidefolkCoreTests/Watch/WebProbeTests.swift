import Foundation
import Testing
@testable import SidefolkCore

@Suite struct UrlChangeProbeTests {
    let fetcher = FakeFetcher()
    var probe: UrlChangeProbe { UrlChangeProbe(fetcher: fetcher, throttle: HostThrottle(gap: 0)) }
    let t0 = TestEnv.referenceDate

    func watcher(_ condition: JSONValue = .object([:]), url: String = "https://example.com/pricing", source: String = "user",
                 config: JSONValue? = nil) throws -> Watcher {
        try probe.made(.make(WatchKind.urlChange, config: config ?? ["url": .string(url)], condition: condition, source: source))
    }

    func page(_ body: String) -> String { "<html><body><script>track()</script>\(body)</body></html>" }

    @Test func theFirstLookIsTheBaselineAndLaterChangesTrigger() async throws {
        var w = try watcher()
        fetcher.say(page("<h1>Pricing</h1><p>Pro: $19</p>"))
        let first = try await probe.step(&w)
        #expect(!first.triggered)

        let same = try await probe.step(&w)
        #expect(!same.triggered)

        fetcher.reset()
        fetcher.say(page("<h1>Pricing</h1><p>Pro: $29</p>"))
        let changed = try await probe.step(&w)
        #expect(changed.triggered)
        #expect(changed.summary == "example.com/pricing changed")
        #expect(changed.detail == "“Pro: $19” → “Pro: $29”")
        #expect(changed.openTarget == "https://example.com/pricing")
        // The change is kept for Today's tile, and stays through checks where nothing changes (D58).
        let kept = try #require(w.lastPageChange)
        #expect(kept.removed == ["Pro: $19"] && kept.added == ["Pro: $29"])
        _ = try await probe.step(&w, at: t0.addingTimeInterval(600))
        #expect(w.lastPageChange == kept)
    }

    @Test func noiseDoesNotTrigger() async throws {
        var w = try watcher()
        fetcher.say(page("<p>Pro: $19</p><p>Updated 2 hours ago</p><p>1,204 views</p><script>var n = 1</script>"))
        _ = try await probe.step(&w)
        fetcher.reset()
        fetcher.say(page("<p>Pro: $19</p><p>Updated 5 minutes ago</p><p>1,377 views</p><script>var n = 2</script><!-- build 7 -->"))
        let r = try await probe.step(&w)
        #expect(!r.triggered)
    }

    @Test func sendsValidatorsAndKeepsStateOnNotModified() async throws {
        var w = try watcher()
        fetcher.say(page("<p>Hello</p>"), headers: ["content-type": "text/html", "ETag": "\"v1\"", "Last-Modified": "Wed, 22 Oct 2025 10:00:00 GMT"])
        _ = try await probe.step(&w)
        fetcher.reset()
        fetcher.say("", status: 304, headers: [:])
        let r = try await probe.step(&w)
        #expect(!r.triggered)
        #expect(r.state == w.lastState)
        let request = try #require(fetcher.requests.last)
        #expect(request.ifNoneMatch == "\"v1\"")
        #expect(request.ifModifiedSince == "Wed, 22 Oct 2025 10:00:00 GMT")
        #expect(w.lastState?["text"]?.stringValue == "Hello")
    }

    @Test func containsFiresWhenThePageStartsSayingItAndAgainOnlyAfterItStopped() async throws {
        var w = try watcher(["contains": "In stock"], source: "user")
        w.mode = .repeat
        fetcher.say(page("<p>Sold out</p>"))
        #expect(try await !probe.step(&w).triggered)

        fetcher.reset()
        fetcher.say(page("<p>Great news: in  STOCK now</p>"))
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "example.com/pricing now says “In stock”")
        #expect(r.detail == "Great news: in STOCK now")

        #expect(try await !probe.step(&w).triggered, "still in stock: already told")
        fetcher.reset()
        fetcher.say(page("<p>Sold out</p>"))
        #expect(try await !probe.step(&w).triggered)
        fetcher.reset()
        fetcher.say(page("<p>In stock</p>"))
        #expect(try await probe.step(&w).triggered)
    }

    @Test func alreadyTrueOnTheFirstLookIsNewsToo() async throws {
        var w = try watcher(["contains": "In stock"])
        fetcher.say(page("<p>In stock</p>"))
        #expect(try await probe.step(&w).triggered)
    }

    @Test func notContainsFiresWhenTheWordsDisappear() async throws {
        var w = try watcher(["not_contains": "Sold out"])
        fetcher.say(page("<p>Sold out</p>"))
        #expect(try await !probe.step(&w).triggered)
        fetcher.reset()
        fetcher.say(page("<p>Available</p>"))
        let r = try await probe.step(&w)
        #expect(r.triggered)
        #expect(r.summary == "“Sold out” is gone from example.com/pricing")
    }

    @Test func badAnswersAreFailuresWithFriendlyMessages() async throws {
        var w = try watcher()
        fetcher.say("nope", status: 404)
        await #expect(throws: ProbeError.failed("The page said “not found” (404).")) { try await probe.step(&w) }

        fetcher.reset()
        fetcher.fail(URLError(.notConnectedToInternet))
        await #expect(throws: ProbeError.offline) { try await probe.step(&w) }

        fetcher.reset()
        fetcher.fail(URLError(.timedOut))
        await #expect(throws: ProbeError.failed("The site didn't answer in time.")) { try await probe.step(&w) }

        fetcher.reset()
        fetcher.fail(URLPolicy.Violation.privateDestination("evil.example"))
        await #expect(throws: ProbeError.self) { try await probe.step(&w) }
    }

    @Test func aPageThatSuddenlyComesBackEmptyIsNotAChange() async throws {
        var w = try watcher()
        fetcher.say(page("<p>Content</p>"))
        _ = try await probe.step(&w)
        fetcher.reset()
        fetcher.say("<html></html>")
        await #expect(throws: ProbeError.failed("The page came back empty.")) { try await probe.step(&w) }
    }

    @Test func oneRequestAMinutePerHostAcrossWatchers() async throws {
        let shared = HostThrottle()
        let p = UrlChangeProbe(fetcher: fetcher, throttle: shared)
        fetcher.say(page("<p>x</p>"))
        let a = try p.made(.make(WatchKind.urlChange, config: ["url": "https://example.com/a"]))
        let b = try p.made(.make(WatchKind.urlChange, config: ["url": "https://example.com/b"]))
        _ = try await p.check(a, now: t0)
        do {
            _ = try await p.check(b, now: t0.addingTimeInterval(10))
            Issue.record("expected the second request to wait")
        } catch let error as ProbeError {
            #expect(error == .deferred(until: t0.addingTimeInterval(60)))
        }
        // The user pressing "check now" is not made to wait.
        _ = try await WatchContext.$isManualCheck.withValue(true) { try await p.check(b, now: t0.addingTimeInterval(10)) }
        _ = try await p.check(b, now: t0.addingTimeInterval(61))
    }

    @Test func onlyTheUserCanPointAWatcherAtTheirOwnNetwork() async throws {
        let local: JSONValue = ["url": "http://localhost:3000/", "allow_local": true]
        // An agent's request is refused outright, and the flag never survives.
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.urlChange, config: local, source: "agent")) }
        let ext = try probe.made(.make(WatchKind.urlChange, config: ["url": "https://example.com/", "allow_local": true], source: "external:codex"))
        #expect(ext.config["allow_local"] == nil)
        #expect(!ext.allowsLocal)

        // The user's own watcher keeps it, and the request says so.
        var mine = try probe.made(.make(WatchKind.urlChange, config: local, source: "user"))
        #expect(mine.allowsLocal)
        fetcher.say(page("<p>dev server</p>"))
        _ = try await probe.step(&mine)
        #expect(fetcher.requests.last?.allowLocal == true)

        // A row written by something else with the flag set is still not trusted.
        var forged = mine
        forged.source = "agent"
        #expect(!forged.allowsLocal)
        _ = try await probe.step(&forged)
        #expect(fetcher.requests.last?.allowLocal == false)
    }

    /// D21, T11: Sidefolk's agent acting for the user in a clean turn ("user:agent") may run approved
    /// commands, but local addresses stay for the user's own request only.
    @Test func aCleanAgentTurnStillCannotReachLocalAddresses() async throws {
        let local: JSONValue = ["url": "http://localhost:3000/", "allow_local": true]
        #expect(throws: WatchError.self) { _ = try probe.made(.make(WatchKind.urlChange, config: local, source: "user:agent")) }
        let site = SiteStatusProbe(fetcher: fetcher, throttle: HostThrottle())
        #expect(throws: WatchError.self) { _ = try site.made(.make(WatchKind.siteStatus, config: local, source: "user:agent")) }
        let public_ = try probe.made(.make(WatchKind.urlChange, config: ["url": "https://example.com/", "allow_local": true], source: "user:agent"))
        #expect(public_.config["allow_local"] == nil)

        // Even a row that got the flag some other way never asks for a local address.
        var row = try probe.made(.make(WatchKind.urlChange, config: local, source: "user"))
        row.source = "user:agent"
        #expect(!row.allowsLocal)
        fetcher.say(page("<p>dev server</p>"))
        _ = try await probe.step(&row)
        #expect(fetcher.requests.last?.allowLocal == false)
    }

    @Test func addressesAreNormalisedAndValidatedWhenCreated() throws {
        #expect(try watcher(url: "example.com/pricing").config.string("url") == "https://example.com/pricing")
        #expect(throws: WatchError.self) { _ = try watcher(url: "https://me:pw@example.com/") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "file:///etc/passwd") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "http://169.254.169.254/") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "mailto:someone@example.com") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "javascript:alert(1)") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "localhost:3000") }
        #expect(throws: WatchError.self) { _ = try watcher(url: "http://127.0.0.1:8080/") }
        #expect(try watcher(url: "example.com:8080/x").config.string("url") == "https://example.com:8080/x")
        #expect(throws: WatchError.self) { _ = try watcher(["changed": false]) }
        #expect(throws: WatchError.self) { _ = try watcher(["contains": .string(String(repeating: "x", count: 201))]) }
        #expect(probe.minimumInterval == 300)
        #expect(probe.defaultInterval == 1800)
    }
}

@Suite struct SiteStatusProbeTests {
    let fetcher = FakeFetcher()
    var probe: SiteStatusProbe { SiteStatusProbe(fetcher: fetcher, throttle: HostThrottle(gap: 0)) }

    func watcher(becomes: String? = nil) throws -> Watcher {
        try probe.made(.make(WatchKind.siteStatus, config: ["url": "https://example.com/"], condition: becomes.map { ["becomes": .string($0)] } ?? .object([:]),
                             mode: .repeat))
    }

    func look(_ w: inout Watcher, up: Bool) async throws -> ProbeResult {
        fetcher.reset()
        fetcher.say("", status: up ? 200 : 503)
        return try await probe.step(&w)
    }

    @Test func aFlipNeedsTwoLooksInARow() async throws {
        var w = try watcher()
        #expect(try await !look(&w, up: true).triggered)   // first look
        #expect(try await !look(&w, up: true).triggered)   // confirmed up: a baseline, not news
        #expect(w.lastState?.string("confirmed") == "up")

        #expect(try await !look(&w, up: false).triggered)  // one failure is a blip
        #expect(try await !look(&w, up: true).triggered)   // and it recovered
        #expect(try await !look(&w, up: false).triggered)
        let down = try await look(&w, up: false)           // two in a row
        #expect(down.triggered)
        #expect(down.summary == "example.com is down")
        #expect(down.detail == "It answered “service unavailable” (503).")

        #expect(try await !look(&w, up: false).triggered)  // still down: already told
        #expect(try await !look(&w, up: true).triggered)
        let back = try await look(&w, up: true)
        #expect(back.triggered)
        #expect(back.summary == "example.com is back up")
    }

    @Test func becomesUpIgnoresOutages() async throws {
        var w = try watcher(becomes: "up")
        for _ in 0..<2 { _ = try await look(&w, up: false) }
        #expect(w.lastState?.string("confirmed") == "down")
        #expect(try await !look(&w, up: true).triggered)
        #expect(try await look(&w, up: true).triggered)
        for _ in 0..<2 { #expect(try await !look(&w, up: false).triggered) }
    }

    @Test func becomesDownIgnoresRecoveries() async throws {
        var w = try watcher(becomes: "down")
        for _ in 0..<2 { _ = try await look(&w, up: false) }
        for _ in 0..<2 { #expect(try await !look(&w, up: true).triggered) }
        _ = try await look(&w, up: false)
        #expect(try await look(&w, up: false).triggered)
    }

    @Test func serversThatRefuseHeadAreAskedWithGet() async throws {
        var w = try watcher()
        fetcher.say("", status: 405)
        fetcher.say("", status: 200)
        _ = try await probe.step(&w)
        #expect(fetcher.requests.map(\.method) == ["HEAD", "GET"])
        #expect(w.lastState?.string("pending") == "up")
        #expect(fetcher.requests.allSatisfy { $0.headersOnly })
    }

    @Test func noAnswerCountsAsDownButNoInternetDoesNot() async throws {
        var w = try watcher()
        _ = try await look(&w, up: true)
        _ = try await look(&w, up: true)
        for reason in [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost] {
            fetcher.reset()
            fetcher.fail(URLError(reason))
            _ = try await probe.step(&w)
        }
        #expect(w.lastState?.string("confirmed") == "down")

        fetcher.reset()
        fetcher.fail(URLError(.notConnectedToInternet))
        await #expect(throws: ProbeError.offline) { try await probe.step(&w) }
        #expect(w.lastState?.string("confirmed") == "down", "being offline says nothing about the site")
    }

    @Test func policyRefusalsAreErrorsNotOutages() async throws {
        var w = try watcher()
        fetcher.fail(URLPolicy.Violation.privateDestination("example.com"))
        await #expect(throws: ProbeError.self) { try await probe.step(&w) }
        #expect(probe.minimumInterval == 60)
        #expect(probe.defaultInterval == 60)
    }

    @Test func becomesMustBeUpDownOrAny() throws {
        #expect(throws: WatchError.self) { _ = try watcher(becomes: "sideways") }
    }
}

@Suite struct HostThrottleTests {
    @Test func eachHostGetsOneRequestAMinute() {
        let throttle = HostThrottle()
        let t0 = TestEnv.referenceDate
        #expect(throttle.reserve(host: "a.example", now: t0) == nil)
        #expect(throttle.reserve(host: "b.example", now: t0) == nil)
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(20)) == t0.addingTimeInterval(60))
        // A watcher on a 60 s interval is not pushed back by a little scheduling jitter.
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(59)) == nil)
        #expect(throttle.reserve(host: "a.example", now: t0.addingTimeInterval(59.5)) != nil)
    }

    @Test func namesForDisplayAndTurnTakingIgnoreCaseAndTrailingDots() throws {
        #expect(WebTarget.host(of: URL(string: "https://Example.COM./x")!) == "example.com")
        #expect(WebTarget.displayName(URL(string: "https://example.com:8080/pricing/?a=1")!) == "example.com:8080/pricing?…")
    }
}
