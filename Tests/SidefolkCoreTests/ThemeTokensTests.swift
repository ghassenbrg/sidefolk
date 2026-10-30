import Foundation
import Testing
@testable import SidefolkCore

/// Harbor is the app's original design, now read through themes (D58): it keeps the approved identity and the
/// contrast its text was designed for, in both appearances.
@Suite struct ThemeTokensTests {
    let harbor = ThemeTokens.harbor

    @Test func harborKeepsTheApprovedIdentity() {
        #expect(harbor.colors.ink.light == 0x0F2D5B)
        #expect(harbor.colors.accent == .init(0x2ED4D9))
        #expect(harbor.display == .rounded)
        #expect(harbor.space.l == 16)
        #expect(harbor.radius.card == 12)
    }

    @Test(arguments: [true, false])
    func textIsReadableOnEverySurface(dark: Bool) {
        let c = harbor.colors
        for surface in [c.surface, c.surfaceSunken, c.surfaceRaised] {
            for text in [c.ink, c.inkMuted] {
                #expect(contrast(pick(text, dark), pick(surface, dark)) >= 4.5)
            }
        }
        #expect(contrast(pick(c.onAccent, dark), pick(c.accent, dark)) >= 7)
    }

    private func pick(_ pair: ThemeTokens.Pair, _ dark: Bool) -> UInt32 { dark ? pair.dark : pair.light }

    /// WCAG 2 contrast ratio.
    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { Double((hex >> $0) & 0xFF) / 255 }
                .map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }
}
