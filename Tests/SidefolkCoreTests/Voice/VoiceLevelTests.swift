import Foundation
import Testing
@testable import SidefolkCore

/// The light that listens (D84): a voice's loudness in a few steps.
@Suite struct VoiceLevelTests {
    @Test func silenceIsDarkAndARaisedVoiceIsFull() {
        #expect(VoiceLevel.step(0) == 0)
        #expect(VoiceLevel.step(0.001) == 0)  // -60 dBFS: a quiet room
        #expect(VoiceLevel.step(1) == 1)
        #expect(VoiceLevel.step(0.5) == 1)    // -6 dBFS
    }

    @Test func aSpeakingVoiceLandsOnAStep() {
        let talk = VoiceLevel.step(0.05)      // -26 dBFS
        #expect(talk > 0.4 && talk < 0.7)
        #expect((talk * VoiceLevel.steps).rounded() == talk * VoiceLevel.steps)
        // A little louder or quieter within a step doesn't change it: the screen isn't touched for nothing.
        #expect(VoiceLevel.step(0.0505) == talk)
    }
}
