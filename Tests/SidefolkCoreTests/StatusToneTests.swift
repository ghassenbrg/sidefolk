import Testing
@testable import SidefolkCore

/// Colours have meanings (StatusTone): red only for an error, a failure or a real risk; amber for what waits;
/// green for good outcomes; calm for "no", "off", "nothing happened" and news that isn't trouble.
@Suite struct StatusToneTests {
    @Test func onlyAFailedStepIsRedInActivity() {
        #expect(StatusTone.decision(.failed) == .danger)
        #expect(StatusTone.decision(.allowed) == .success)
        #expect(StatusTone.decision(.always) == .success)
        // Saying no and nobody answering are the person's own outcomes, not failures.
        #expect(StatusTone.decision(.denied) == .neutral)
        #expect(StatusTone.decision(.skipped) == .neutral)
        #expect(StatusTone.decision(.blocked) == .warning)
        // A mode answering for the person never looks like they allowed it.
        for mode: ActivityEntry.Decision in [.auto, .autoMode, .autoModePaired, .webSetting] {
            #expect(StatusTone.decision(mode) == .neutral, "\(mode)")
        }
        #expect(StatusTone.decision(.fullAccess) == .warning)
        #expect(StatusTone.decision(.fullAccessPaired) == .warning)
    }

    @Test func aChangedPageIsNewsAndOnlyATroubledWatchIsRed() {
        #expect(StatusTone.watch(.active, changeWaiting: true) == .news)
        #expect(StatusTone.watch(.active, changeWaiting: false) == .neutral)
        #expect(StatusTone.watch(.paused, changeWaiting: false) == .neutral)
        #expect(StatusTone.watch(.expired, changeWaiting: false) == .neutral)
        #expect(StatusTone.watch(.triggered, changeWaiting: false) == .success)
        #expect(StatusTone.watch(.error, changeWaiting: false) == .danger)
        #expect(StatusTone.watch(.error, changeWaiting: true) == .danger)
    }

    @Test func waitingIsAmberNeverRed() {
        #expect(StatusTone.reminder(late: true) == .warning)
        #expect(StatusTone.reminder(late: false) == .neutral)
        #expect(StatusTone.session(.needsYou) == .warning)
        #expect(StatusTone.session(.working) == .neutral)
        #expect(StatusTone.session(.finished) == .neutral)
    }

    @Test func riskIsCalmWhenLow() {
        #expect(StatusTone.risk(.low) == .neutral)
        #expect(StatusTone.risk(nil) == .neutral)
        #expect(StatusTone.risk(.medium) == .warning)
        #expect(StatusTone.risk(.high) == .danger)
    }

    @Test func anExtensionsTonesMeanTheSame() {
        #expect(StatusTone.page(.good) == .success)
        #expect(StatusTone.page(.warn) == .warning)
        #expect(StatusTone.page(.bad) == .danger)
        #expect(StatusTone.page(.info) == .news)
        #expect(StatusTone.page(.neutral) == .neutral)
    }
}
