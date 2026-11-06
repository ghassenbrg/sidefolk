import Foundation
import Testing
@testable import SidefolkCore

/// A field's saves stay in order, and an older one can't take back a newer one.
@MainActor @Suite struct PageFieldSavesTests {
    /// Sends that wait until told, so a test can put them in any state.
    @MainActor final class Sends {
        var started: [String] = []
        var answers: [String: CheckedContinuation<Bool, Never>] = [:]
        func send(_ text: String) async -> Bool {
            started.append(text)
            return await withCheckedContinuation { answers[text] = $0 }
        }
        func answer(_ text: String, _ saved: Bool) { answers.removeValue(forKey: text)?.resume(returning: saved) }
        func until(_ text: String) async {
            for _ in 0..<500 where !started.contains(text) { try? await Task.sleep(for: .milliseconds(2)) }
        }
    }

    @Test func oneAtATimeInOrderAndOnlyTheNewestWaiting() async {
        let saves = PageFieldSaves(), sends = Sends()
        var told: [Bool] = []
        saves.save("a", send: sends.send) { told.append($0) }
        await sends.until("a")
        for text in ["b", "c"] { saves.save(text, send: sends.send) { told.append($0) } }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(sends.started == ["a"], "the next waits for this one")
        sends.answer("a", true)
        await sends.until("c")
        #expect(sends.started == ["a", "c"], "\"b\" was overtaken before its turn, so it's never sent")
        #expect(told.isEmpty, "only the newest is told")
        sends.answer("c", true)
        await saves.settled()
        #expect(told == [true])
        #expect(!saves.isBusy)
    }

    @Test func anOlderOneFailingTellsNothing() async {
        let saves = PageFieldSaves(), sends = Sends()
        var told: [Bool] = []
        saves.save("old", send: sends.send) { told.append($0) }
        await sends.until("old")
        saves.save("new", send: sends.send) { told.append($0) }
        sends.answer("old", false)
        await sends.until("new")
        #expect(told.isEmpty, "its failure can't bring old text back over the newer one")
        sends.answer("new", true)
        await saves.settled()
        #expect(told == [true])
    }

    @Test func theNewestFailingIsToldSoItCanBeTakenBack() async {
        let saves = PageFieldSaves(), sends = Sends()
        var told: [Bool] = []
        saves.save("a", send: sends.send) { told.append($0) }
        await sends.until("a")
        sends.answer("a", false)
        await saves.settled()
        #expect(told == [false])
        #expect(!saves.isBusy)
    }

    @Test func theSameTextOnItsWayIsntSentTwice() async {
        let saves = PageFieldSaves(), sends = Sends()
        var told: [Bool] = []
        saves.save("a", send: sends.send) { told.append($0) }
        saves.save("a", send: sends.send) { told.append($0) }
        await sends.until("a")
        sends.answer("a", true)
        await saves.settled()
        #expect(sends.started == ["a"])
        #expect(told == [true])
    }

    @Test func goingBackToWhatWasSavedOvertakesASaveOnItsWay() async {
        let saves = PageFieldSaves(), sends = Sends()
        saves.save("typed", send: sends.send) { _ in }
        await sends.until("typed")
        #expect(saves.isBusy, "so the field knows to save what's shown again")
        saves.save("original", send: sends.send) { _ in }
        sends.answer("typed", true)
        await sends.until("original")
        sends.answer("original", true)
        await saves.settled()
        #expect(sends.started == ["typed", "original"], "the last thing they wanted lands last")
    }
}
