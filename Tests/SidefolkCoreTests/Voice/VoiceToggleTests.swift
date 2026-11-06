import Testing
@testable import SidefolkCore

/// The microphone button (D232, T64): the person's click starts it, only the person sends, and everything else stops it unsent.
@Suite struct VoiceToggleTests {
    @Test func clickListensAndTheSecondClickSends() {
        var t = VoiceToggle()
        #expect(t.handle(.click(replyPlaying: false)) == .listen)
        #expect(t.listening)
        #expect(t.handle(.click(replyPlaying: false)) == .send)
        #expect(!t.listening)
    }

    @Test func returnSendsAndEscapeSendsNothing() {
        var t = VoiceToggle()
        _ = t.handle(.click(replyPlaying: false))
        #expect(t.handle(.returnKey) == .send)
        _ = t.handle(.click(replyPlaying: false))
        #expect(t.handle(.escape) == .cancel)
        #expect(!t.listening)
    }

    @Test func nothingButAClickStartsIt() {
        var t = VoiceToggle()
        for event in [VoiceToggle.Event.returnKey, .escape, .timeUp, .panelClosed, .leftSidefolk, .sleptOrLocked] {
            #expect(t.handle(event) == .none, "\(event)")
            #expect(!t.listening)
        }
    }

    @Test func everythingElseStopsItWithoutSending() {
        for event in [VoiceToggle.Event.timeUp, .panelClosed, .leftSidefolk, .sleptOrLocked] {
            var t = VoiceToggle()
            _ = t.handle(.click(replyPlaying: false))
            #expect(t.handle(event) == .stopKeepingWords, "\(event)")
            #expect(!t.listening)
        }
        #expect(VoiceToggle.limit == .seconds(60))
    }

    @Test func aClickWhileAnAnswerIsSaidSilencesItFirst() {
        var t = VoiceToggle()
        #expect(t.handle(.click(replyPlaying: true)) == .silence)
        #expect(!t.listening, "the microphone stays off")
        #expect(t.handle(.click(replyPlaying: false)) == .listen)
    }

    @Test func talkingEndedElsewhereStartsAfresh() {
        var t = VoiceToggle()
        _ = t.handle(.click(replyPlaying: false))
        t.reset()
        #expect(t.handle(.click(replyPlaying: false)) == .listen)
    }
}
