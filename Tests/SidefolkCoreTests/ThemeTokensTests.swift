import Foundation
import Testing
@testable import SidefolkCore

/// The default theme is the app's design, read through themes (D58), since D130 drawn from the app icon and logo: navy ink
/// and action, the brand aqua and amber as light only, and every text colour at 4.5:1 on every surface, in both appearances.
@Suite struct ThemeTokensTests {
    let theme = ThemeTokens.sidefolk

    @Test func theDefaultKeepsTheApprovedIdentity() {
        #expect(theme.id == "sidefolk")
        #expect(theme.colors.ink.light == 0x1E3457)
        #expect(theme.colors.accent == .init(light: 0x2A4A7C, dark: 0x7CC9CF))
        #expect(theme.colors.glow == .init(0x2ED4D9) && theme.colors.waitGlow == .init(0xF5A524))
        #expect(theme.type.display == .rounded)
        #expect(theme.space.l == 16)
        #expect(theme.radius.card == 16)
        #expect(theme.layout == .desk)
        #expect(AppSettings().theme == "sidefolk")
    }

    /// The founder's finding (D130): a selected row must be seen, in both appearances.
    @Test func aSelectedRowStandsFromItsSidebar() {
        #expect(ThemeCheck.selectionProblems(theme.colors).isEmpty)
        var pale = theme.colors
        pale.sidebarSelected.light = 0xD5EEF1
        #expect(ThemeCheck.selectionProblems(pale).count == 1)
    }

    /// The pale brand aqua under navy read as a disabled button; the action colour now reads with its label at 4.5:1,
    /// and as a control on a card at 3:1, in both appearances (D84).
    @Test func theActionColourDoesNotLookDisabled() {
        let c = theme.colors
        #expect(ThemeCheck.contrast(c.onAccent.light, c.accent.light) >= 4.5)
        #expect(ThemeCheck.contrast(c.onAccent.dark, c.accent.dark) >= 4.5)
        #expect(ThemeCheck.contrast(c.accent.light, c.surfaceRaised.light) >= 3)
        #expect(ThemeCheck.contrast(c.accent.dark, c.surfaceRaised.dark) >= 3)
    }

    @Test func everyTextColourReadsOnEverySurface() {
        let failing = ThemeCheck.contrastRows(theme.colors).filter { !$0.passes }.map(\.label)
        #expect(failing.isEmpty, "\(failing)")
    }
}
