import Foundation
import Testing
@testable import SidefolkCore

/// When the companion listens and when it speaks (D34).
@Suite struct VoicePolicyTests {
    @Test func emptyOrHesitantPressesSendNothing() {
        #expect(VoicePolicy.usableTranscript("") == nil)
        #expect(VoicePolicy.usableTranscript("   ") == nil)
        #expect(VoicePolicy.usableTranscript("Um.") == nil)
        #expect(VoicePolicy.usableTranscript("euh…") == nil)
        #expect(VoicePolicy.usableTranscript("a") == nil)
        #expect(VoicePolicy.usableTranscript(" Remind me at 5 to stretch. ") == "Remind me at 5 to stretch.")
        // Two characters carry meaning in Japanese and Chinese.
        #expect(VoicePolicy.usableTranscript("はい") == "はい")
    }

    func decide(spoken: Bool = true, replies: SpokenReplies = .whenSpoken, quiet: Bool = false, mic: Bool = false, typed: Bool = false,
                voiceOver: Bool = false) -> VoicePolicy.Decision {
        VoicePolicy.reply(spokenRequest: spoken, replies: replies, quiet: quiet, micInUseElsewhere: mic, typedSince: typed, voiceOver: voiceOver)
    }

    @Test func spokenRequestsGetSpokenRepliesByDefault() {
        #expect(decide() == .speak)
        #expect(decide(spoken: false) == VoicePolicy.Decision.none)
        #expect(decide(spoken: false, replies: .always) == .speak)
        #expect(decide(replies: .off) == VoicePolicy.Decision.none)
    }

    @Test func quietCallsAndTypingKeepItSilentButShown() {
        #expect(decide(quiet: true) == .muted(.quiet))
        #expect(decide(mic: true) == .muted(.micInUse))
        #expect(decide(typed: true) == .muted(.typing))
        // Off means nothing was going to be said: no muted line either.
        #expect(decide(replies: .off, quiet: true) == VoicePolicy.Decision.none)
    }

    @Test func voiceOverReadsItInsteadOfTalkingOverIt() {
        #expect(decide(voiceOver: true) == .announce)
        #expect(decide(quiet: true, voiceOver: true) == .muted(.quiet))
    }
}

@Suite struct VoiceSettingsTests {
    @Test func offByDefaultWithRepliesToSpokenRequests() {
        let v = AppSettings().voice
        #expect(!v.input)
        #expect(v.talkKey == .askShortcut)
        #expect(v.replies == .whenSpoken)
        #expect(v.engine == .apple)
        #expect(v.language == nil)
    }

    @Test func olderAndPartialSettingsStillLoad() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName":"Pip"}"#.utf8))
        #expect(old.companionName == "Pip")
        #expect(old.voice == VoiceSettings())
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"voice":{"input":true,"replies":"always","rate":9,"engine":"warp"}}"#.utf8))
        #expect(partial.voice.input)
        #expect(partial.voice.replies == .always)
        #expect(partial.voice.engine == .apple)
        #expect(partial.voice.rate == VoiceSettings.rates.upperBound)
        var changed = AppSettings()
        changed.voice.language = "fr-FR"
        changed.voice.elevenLabsVoice = "v1"
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
        #expect(back.voice == changed.voice)
    }

    @Test func deletingEverythingFindsTheElevenLabsKey() {
        #expect(SecretKey.providerKeys.contains(SecretKey.elevenLabsAPIKey))
    }
}

@Suite struct VoiceMoodTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func theMicrophoneShowsOverEverythingButADrag() {
        var m = CompanionMood()
        m.apply(.approvalRequested(ApprovalRequest(tool: "files.move", title: "Move?", summary: "", risk: .medium, caller: .user,
                                                   details: .none, canAlways: false)), now: now)
        #expect(m.pose(at: now) == .waiting)
        m.hearing = true
        #expect(m.pose(at: now) == .hearing)
        m.dragging = true
        #expect(m.pose(at: now) == .dragging)
    }

    @Test func settlingWordsThinkAndMissedWordsLookSad() {
        var m = CompanionMood()
        m.panelOpen = true
        m.transcribing = true
        #expect(m.pose(at: now) == .thinking)
        m.transcribing = false
        m.missedSpeech(now: now)
        #expect(m.pose(at: now) == .error)
        #expect(m.pose(at: now.addingTimeInterval(CompanionMood.errorHold + 0.1)) == .listening)
    }
}

@Suite struct SpokenRequestContextTests {
    @Test func aSpokenRequestAsksForAFirstSentenceThatStandsAlone() async throws {
        let f = try await ContextBuilderTests.Fixture()
        let typed = await f.build("what's next?")
        #expect(!typed.sections.contains("spoken"))
        let spoken = await f.builder.build(text: "what's next?", attachment: nil, threadId: nil, thinkHarder: false, spoken: true,
                                           settings: AppSettings())
        #expect(spoken.sections.prefix(5) == ["persona", "rules", "reach", "environment", "spoken"])
        #expect(spoken.system.contains("# Spoken request"))
        #expect(spoken.system.contains("first sentence will be read aloud"))
    }

    @Test func historyMarksSpokenRequestsAndKeepsNoAudio() {
        #expect(ExchangeMeta.user(attachment: nil, tainted: false, spoken: true)["spoken"]?.boolValue == true)
        #expect(ExchangeMeta.user(attachment: nil, tainted: false)["spoken"] == nil)
    }
}
