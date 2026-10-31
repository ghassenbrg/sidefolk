import Foundation
import Testing
@testable import SidefolkCore

/// Harbor is the app's design, read through themes (D58), in the Lantern look since D84: the brand navy as ink, one
/// deep aqua for actions, the brand aqua and amber as light only, and every text colour at 4.5:1 on every surface, in
/// both appearances.
@Suite struct ThemeTokensTests {
    let harbor = ThemeTokens.harbor

    @Test func harborKeepsTheApprovedIdentity() {
        #expect(harbor.colors.ink.light == 0x0F1E36)
        #expect(harbor.colors.accent == .init(light: 0x0B7783, dark: 0x3CD6DB))
        #expect(harbor.colors.glow == .init(0x2ED4D9) && harbor.colors.waitGlow == .init(0xF5A524))
        #expect(harbor.type.display == .rounded)
        #expect(harbor.space.l == 16)
        #expect(harbor.radius.card == 12)
        #expect(harbor.layout == .desk)
    }

    /// The pale brand aqua under navy read as a disabled button; the action colour now reads with its label at 4.5:1,
    /// and as a control on a card at 3:1, in both appearances (D84).
    @Test func theActionColourDoesNotLookDisabled() {
        let c = harbor.colors
        #expect(ThemeCheck.contrast(c.onAccent.light, c.accent.light) >= 4.5)
        #expect(ThemeCheck.contrast(c.onAccent.dark, c.accent.dark) >= 4.5)
        #expect(ThemeCheck.contrast(c.accent.light, c.surfaceRaised.light) >= 3)
        #expect(ThemeCheck.contrast(c.accent.dark, c.surfaceRaised.dark) >= 3)
    }

    @Test func everyTextColourReadsOnEverySurface() {
        let failing = ThemeCheck.contrastRows(harbor.colors).filter { !$0.passes }.map(\.label)
        #expect(failing.isEmpty, "\(failing)")
    }
}
