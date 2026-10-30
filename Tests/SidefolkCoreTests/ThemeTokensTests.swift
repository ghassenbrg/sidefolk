import Foundation
import Testing
@testable import SidefolkCore

/// Harbor is the app's design, read through themes (D58): it keeps the approved identity, and since D58 every text
/// colour reads at 4.5:1 on every surface, in both appearances.
@Suite struct ThemeTokensTests {
    let harbor = ThemeTokens.harbor

    @Test func harborKeepsTheApprovedIdentity() {
        #expect(harbor.colors.ink.light == 0x0F2D5B)
        #expect(harbor.colors.accent == .init(0x2ED4D9))
        #expect(harbor.type.display == .rounded)
        #expect(harbor.space.l == 16)
        #expect(harbor.radius.card == 12)
        #expect(harbor.recipes == ThemeTokens.Recipes())
    }

    @Test func everyTextColourReadsOnEverySurface() {
        let failing = ThemeCheck.contrastRows(harbor.colors).filter { !$0.passes }.map(\.label)
        #expect(failing.isEmpty, "\(failing)")
    }
}
