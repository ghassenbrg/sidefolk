import AppKit
import SwiftUI

/// Sidefolk's own pictures for the games' parts (Play/Art, made for the panel in one toy-like style): drawn where a
/// part asks for that object (a cup, the gem, a balloon of lives, the trophy of a win), never a file from a game (D75).
/// A missing picture falls back to the part's drawing in code.
enum GameArt: String {
    case cup = "game-cup"
    case gem = "game-gem"
    case balloon = "game-balloon"
    case trophy = "game-trophy"

    private static var cache: [GameArt: NSImage] = [:]

    var image: NSImage? {
        if let cached = Self.cache[self] { return cached }
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png", subdirectory: "Art"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.cache[self] = image
        return image
    }

    /// A white picture (the balloon) in `color`, its light and shade kept.
    @ViewBuilder func tinted(_ color: Color, height: CGFloat) -> some View {
        if let image {
            let picture = Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            picture.overlay(color.blendMode(.multiply).mask(picture)).frame(height: height).accessibilityHidden(true)
        }
    }

    /// The picture at `height` points, or nothing.
    @ViewBuilder func view(height: CGFloat) -> some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: height)
                .accessibilityHidden(true)
        }
    }
}
