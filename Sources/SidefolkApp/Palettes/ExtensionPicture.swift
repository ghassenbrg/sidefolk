import AppKit
import ImageIO
import SidefolkCore
import SwiftUI

/// A picture an extension names on its palette or page (D68): read from its data folder through `ExtensionDataFile`,
/// decoded off the main thread at the size it is drawn, and kept while the app runs. Names are never reused for other
/// pictures (the extension makes a new one per copy), so a name and size are enough to cache by.
@MainActor
enum ExtensionPictures {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()

    static func cached(_ name: String, in folder: URL, pixels: Int) -> NSImage? {
        cache.object(forKey: key(name, folder, pixels))
    }

    static func load(_ name: String, in folder: URL, pixels: Int, limit: Int) async -> NSImage? {
        if let hit = cached(name, in: folder, pixels: pixels) { return hit }
        let made = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let data = ExtensionDataFile.read(name, in: folder, limit: limit),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let made else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: made.width, height: made.height))
        cache.setObject(image, forKey: key(name, folder, pixels), cost: made.width * made.height * 4)
        return image
    }

    private static func key(_ name: String, _ folder: URL, _ pixels: Int) -> NSString { "\(folder.path)|\(name)|\(pixels)" as NSString }
}

/// An extension's picture, filling its frame (`fill`) or fitting in it; a quiet placeholder until it is read or when it
/// can't be.
struct ExtensionPictureView: View {
    var name: String
    var folder: URL
    /// The longest side to decode, in pixels: twice the points drawn, for Retina screens.
    var pixels: Int
    var limit = ExtensionDataFile.thumbnailLimit
    var fill = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let shown = image ?? ExtensionPictures.cached(name, in: folder, pixels: pixels) {
                Image(nsImage: shown).resizable().interpolation(.high).aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Theme.surfaceSunken
                Image(systemName: "photo").foregroundStyle(Theme.inkFaint)
            }
        }
        .task(id: name) { image = await ExtensionPictures.load(name, in: folder, pixels: pixels, limit: limit) }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// An extension's `#RRGGBB` (already checked when its list or page was read).
    init?(extensionHex text: String) {
        guard text.count == 7, text.hasPrefix("#"), let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        self.init(hex: value)
    }
}
