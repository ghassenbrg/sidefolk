import Testing
@testable import SidefolkCore

/// Show and Hide from the menu bar stick across the settings writes that re-apply the companion.
@Suite struct CompanionVisibilityTests {
    @Test func theSettingDecidesUntilThePersonChooses() {
        let none = CompanionVisibility()
        #expect(none.decide(presence: .always) == .init(visible: true, presence: .always))
        #expect(none.decide(presence: .whenNeeded) == .init(visible: true, presence: .whenNeeded))
        #expect(none.decide(presence: .menuBarOnly).visible == false)
    }

    @Test func showFromAMenuBarOnlyMacStaysOnScreen() {
        var v = CompanionVisibility()
        v.choose(visible: true, under: .menuBarOnly)
        // The settings are written again and again: it is still shown, out, every time.
        for _ in 0..<3 { #expect(v.decide(presence: .menuBarOnly) == .init(visible: true, presence: .always)) }
    }

    @Test func showWhileTuckedAwayComesOutInFull() {
        var v = CompanionVisibility()
        v.choose(visible: true, under: .whenNeeded)
        #expect(v.decide(presence: .whenNeeded) == .init(visible: true, presence: .always))
    }

    @Test func hideStaysHiddenThroughSettingsWrites() {
        var v = CompanionVisibility()
        v.choose(visible: false, under: .always)
        for _ in 0..<3 { #expect(v.decide(presence: .always).visible == false) }
    }

    @Test func changingWhereItLivesGivesTheSettingTheLastWord() {
        var v = CompanionVisibility()
        v.choose(visible: false, under: .always)
        #expect(v.decide(presence: .whenNeeded) == .init(visible: true, presence: .whenNeeded))
        v.choose(visible: true, under: .menuBarOnly)
        #expect(v.decide(presence: .always) == .init(visible: true, presence: .always))
        #expect(v.decide(presence: .menuBarOnly).visible, "and back, the choice is still the person's")
    }
}
