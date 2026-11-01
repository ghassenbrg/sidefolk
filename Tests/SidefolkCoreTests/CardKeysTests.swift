import Foundation
import Testing
@testable import SidefolkCore

/// Answering the card beside the companion from the keyboard (D88).
@Suite struct CardKeysTests {
    func item(_ source: String) -> AttentionItem { AttentionItem(level: .attention, source: source, title: "x") }

    @Test func returnAnswersOnlyThePersonsOwnCards() {
        for calm in ["reminder", "brief", "job", "summary", "onboarding", "companion", "update"] { #expect(item(calm).takesReturn, "\(calm)") }
        // Another app, an agent session, a script calling `sidefolk notify`, an extension, a watched page: ⌘Return.
        for firm in ["external:codex", "session:cc", "cli", "extension:dev.x", "watcher", "app:notes", "something new"] {
            #expect(!item(firm).takesReturn, "\(firm)")
        }
    }

    @Test func theFocusStartsOnTheMainAnswerAndReturnPressesIt() {
        var keys = CardKeys(answers: ["snooze", "done"], main: "done", takesReturn: true)
        #expect(keys.focusedAnswer == "done")
        #expect(keys.press(.enter(command: false)) == .press("done"))
        #expect(keys.press(.left) == .moved && keys.focusedAnswer == "snooze")
        #expect(keys.press(.enter(command: false)) == .press("snooze"))
        // The arrows stop at the ends; Tab goes round.
        #expect(keys.press(.left) == .ignored)
        #expect(keys.press(.tab(back: true)) == .moved && keys.focusedAnswer == "done")
        #expect(keys.press(.tab(back: false)) == .moved && keys.focusedAnswer == "snooze")
    }

    @Test func aFirmCardNeedsCommandReturn() {
        var keys = CardKeys(answers: ["deny", "allow"], main: "allow", takesReturn: false)
        #expect(keys.press(.enter(command: false)) == .needsCommand)
        #expect(keys.press(.enter(command: true)) == .press("allow"))
    }

    @Test func theArrowsFollowTheScreenInRightToLeft() {
        var keys = CardKeys(answers: ["more", "snooze", "done"], main: "done", takesReturn: true, rightToLeft: true)
        // Mirrored, the main answer is at the left end: → moves toward the leading answers.
        #expect(keys.press(.left) == .ignored)
        #expect(keys.press(.right) == .moved && keys.focusedAnswer == "snooze")
    }

    @Test func upAndDownMoveThroughTheHeldCards() {
        var keys = CardKeys(answers: ["done"], main: "done", takesReturn: true, deck: ["a", "b", "c"], current: "b")
        #expect(keys.position?.index == 2 && keys.position?.count == 3)
        #expect(keys.press(.up) == .show("a"))
        #expect(keys.press(.down) == .show("c"))
        keys.current = "c"
        #expect(keys.press(.down) == .ignored)
        // A card that isn't held (onboarding's) has nowhere to go and no position.
        var alone = CardKeys(answers: ["ok"], main: nil, takesReturn: true, deck: ["a"], current: "z")
        #expect(alone.press(.up) == .ignored && alone.position == nil)
        #expect(alone.press(.escape) == .putAway)
    }

    @Test func aCardWithoutAnswersIgnoresReturn() {
        var keys = CardKeys(answers: [], main: nil, takesReturn: true)
        #expect(keys.press(.enter(command: true)) == .ignored)
        #expect(keys.press(.tab(back: false)) == .ignored)
    }
}
