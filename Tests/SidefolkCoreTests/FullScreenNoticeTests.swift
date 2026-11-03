import Testing
@testable import SidefolkCore

/// What reaches the person in a full-screen app the companion stays off (D138).
@Suite struct FullScreenNoticeTests {
    private func route(hides: Bool = true, full: Bool = true, _ notice: FullScreenNotice = .menuBar, whisper: Bool = false) -> FullScreenNotice.Route {
        FullScreenNotice.route(hidesOverFullScreen: hides, inFullScreen: full, notice: notice, whisper: whisper)
    }

    @Test func theDefaultChangesNothingForAnyone() {
        for notice in FullScreenNotice.allCases {
            #expect(route(hides: false, notice) == .asUsual)
            #expect(route(hides: false, notice, whisper: true) == .asUsual)
        }
    }

    @Test func offAFullScreenAppItsAsUsual() {
        for notice in FullScreenNotice.allCases { #expect(route(full: false, notice) == .asUsual) }
    }

    @Test func whatNeedsThemGoesTheWayTheyChose() {
        #expect(route(.companion) == .visit)
        #expect(route(.menuBar) == .notify)
        #expect(route(.silent) == .wait)
    }

    @Test func aWhisperAlwaysWaits() {
        for notice in FullScreenNotice.allCases { #expect(route(notice, whisper: true) == .wait) }
    }
}
