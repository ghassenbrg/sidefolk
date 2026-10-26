import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The wordmark in the variant that reads on this appearance (D33): navy and aqua on light surfaces,
/// white and aqua on dark ones, so "folk" and its rays keep the brand's aqua either way.
struct Wordmark: View {
    var height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image = (scheme == .dark ? BrandAsset.wordmarkReversed : BrandAsset.wordmarkColor).image {
            Image(nsImage: image).resizable().scaledToFit().frame(height: height)
                .accessibilityLabel("Sidefolk")
        }
    }
}

/// Your own companion, drawn by the same rig as on the desktop and in the style you chose, in a
/// still pose: the windows show the one you live with, not a stock picture.
struct CompanionPortrait: View {
    var settings: AppSettings
    var state: CharacterState = .idle
    var side: CGFloat

    var body: some View {
        Image(nsImage: CompanionArt.portrait(for: settings, state: state, side: side))
            .resizable()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
