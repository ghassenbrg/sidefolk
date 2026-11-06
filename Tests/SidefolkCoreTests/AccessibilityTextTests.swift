import Foundation
import Testing
@testable import SidefolkCore

struct AccessibilityTextTests {
    @Test func anAttributedValueReadsAsItsWords() {
        let attributed = NSAttributedString(string: "Fajr 4:41", attributes: [.font: "bold"])
        #expect(AccessibilityText.plain(attributed) == "Fajr 4:41")
    }

    @Test func otherValuesReadAsThemselves() {
        #expect(AccessibilityText.plain("Ask") == "Ask")
        #expect(AccessibilityText.plain(NSNumber(value: 1)) == "1")
        #expect(AccessibilityText.plain(nil) == nil)
    }
}
