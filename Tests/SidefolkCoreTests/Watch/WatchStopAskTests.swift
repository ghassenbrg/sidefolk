import Testing
@testable import SidefolkCore

/// Stopping a watch asks first on every screen (C1): nothing is stopped until the yes, and the yes counts once.
@Suite struct WatchStopAskTests {
    @Test func nothingIsStoppedUntilTheYes() {
        var ask = WatchStopAsk()
        #expect(ask.confirm() == nil, "no question, nothing to stop")
        ask.ask(id: "w1", title: "example.com")
        #expect(ask.pending == WatchStopAsk.Pending(id: "w1", title: "example.com"))
        #expect(ask.confirm() == "w1")
        #expect(ask.pending == nil)
        #expect(ask.confirm() == nil, "a second yes stops nothing")
    }

    @Test func noLeavesTheWatchAloneAndANewQuestionReplacesTheOld() {
        var ask = WatchStopAsk()
        ask.ask(id: "w1", title: "One")
        ask.cancel()
        #expect(ask.pending == nil && ask.confirm() == nil)
        ask.ask(id: "w1", title: "One")
        ask.ask(id: "w2", title: "Two")
        #expect(ask.confirm() == "w2")
    }

    @Test func theQuestionNamesTheWatch() {
        #expect(WatchStopAsk.question("staging.example.com").contains("staging.example.com"))
    }
}
