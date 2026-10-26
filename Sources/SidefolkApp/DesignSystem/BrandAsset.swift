import AppKit

/// The brand pictures the app draws (D33), loaded once. SwiftUI can use `Image(nsImage: asset.image)`.
/// The build bundles only production exports; source artwork stays in the repository. Where an export
/// has a vector PDF it is used, so the wordmark stays sharp at any size without a 4096 px bitmap.
enum BrandAsset: String {
    /// Navy "Side", aqua "folk": on light surfaces.
    case wordmarkColor = "wordmark-color"
    /// White "Side", aqua "folk": on dark surfaces.
    case wordmarkReversed = "wordmark-reversed"
    /// Mochi with Byte, Seed and Pip, the full-color family without lettering.
    case familyColor = "family-color"
    case menuBar = "SidefolkMenuBar"

    @MainActor private static var loaded: [BrandAsset: NSImage?] = [:]

    @MainActor var image: NSImage? {
        if let image = Self.loaded[self] { return image }
        let image = load()
        Self.loaded[self] = .some(image)
        return image
    }

    private func load() -> NSImage? {
        guard let resources = ResourceLocator.resources else { return nil }
        // The app bundle flattens the exports into Brand/; the repository keeps them in Brand/exports/.
        let candidates = self == .menuBar ? ["MenuBar/\(rawValue).pdf"]
            : ["pdf", "png"].flatMap { ["Brand/\(rawValue).\($0)", "Brand/exports/\(rawValue).\($0)"] }
        guard let image = candidates.lazy.compactMap({ NSImage(contentsOf: resources.appendingPathComponent($0)) }).first else { return nil }
        if self == .menuBar {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
        }
        return image
    }
}
