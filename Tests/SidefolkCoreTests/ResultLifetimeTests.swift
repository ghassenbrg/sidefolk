import Foundation
import Testing
@testable import SidefolkCore

/// Ask tidies itself by each result's weight (D90, D136).
@Suite struct ResultLifetimeTests {
    let now = TimeTest.wednesday10

    /// `seen` seconds ago; made at the same moment unless `made` says it came earlier, while they were away.
    func gone(_ w: ResultLifetime.Weight, seen: TimeInterval?, made: TimeInterval? = nil, pinned: Bool = false) -> Bool {
        ResultLifetime.expired(w, createdAt: now.addingTimeInterval(made ?? seen ?? -60), seenAt: seen.map { now.addingTimeInterval($0) },
                               pinned: pinned, now: now)
    }

    @Test func whatTheyWatchedArriveGoesSoon() {
        #expect(!gone(.quick, seen: -10))
        #expect(gone(.quick, seen: -25))
        #expect(!gone(.normal, seen: -100))
        #expect(gone(.normal, seen: -130))
    }

    @Test func whatCameWhileTheyWereAwayGetsLongerFromTheirFirstLook() {
        #expect(!gone(.quick, seen: -30, made: -3600))
        #expect(gone(.quick, seen: -70, made: -3600))
        #expect(!gone(.normal, seen: -500, made: -3600))
        #expect(gone(.normal, seen: -700, made: -3600))
    }

    @Test func nothingGoesBeforeItReachedThem() {
        #expect(!gone(.quick, seen: nil, made: -86_400))
        #expect(!gone(.normal, seen: nil, made: -86_400))
    }

    @Test func whatNeedsThePersonAndWhatTheyPinnedStays() {
        #expect(!gone(.needsYou, seen: -86_400 * 3))
        #expect(!gone(.quick, seen: -3600, pinned: true))
        #expect(!gone(.normal, seen: -86_400, pinned: true))
    }

    @Test func aHundredRequestsAreNeverAHundredCards() {
        let many = (0..<100).map { (id: $0, kept: false) }
        #expect(ResultLifetime.overflow(many, limit: 8) == Set(0..<92))
        #expect(ResultLifetime.overflow(Array(many.prefix(8)), limit: 8).isEmpty)
        // A pin isn't counted and never goes.
        var pinned = many.suffix(10).map { $0 }
        pinned[0].kept = true
        #expect(ResultLifetime.overflow(pinned, limit: 8) == [91])
    }

    @Test func valuesAndLookupsAreQuickWhatWasMadeIsNot() {
        #expect(ResultLifetime.weight(of: .reading) == .quick)
        #expect(ResultLifetime.weight(of: .extensionResult) == .quick)
        #expect(ResultLifetime.weight(of: .reminder) == .normal)
        #expect(ResultLifetime.weight(of: .note) == .normal)
    }

    @Test func aCardWithATreeSaysWhatWasMade() {
        var card = ResultCard(kind: .extensionResult, title: "Make a routine")
        #expect(ResultLifetime.weight(of: card) == .quick)
        card.tree = ["nodes": []]
        #expect(ResultLifetime.weight(of: card) == .normal)
    }
}
