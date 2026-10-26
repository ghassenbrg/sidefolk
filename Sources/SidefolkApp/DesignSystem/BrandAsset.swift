import AppKit

/// Standalone, tightly framed assets. SwiftUI can use `Image(nsImage: asset.image)`.
/// The build bundles only production exports; source artwork stays in the repository.
enum BrandAsset: String {
    case logoStackedColor = "logo-stacked-color"
    case logoStackedNavy = "logo-stacked-navy"
    case logoStackedWhite = "logo-stacked-white"
    case logoHorizontalColor = "logo-horizontal-color"
    case logoHorizontalNavy = "logo-horizontal-navy"
    case logoHorizontalWhite = "logo-horizontal-white"
    case wordmarkColor = "wordmark-color"
    case wordmarkNavy = "wordmark-navy"
    case wordmarkWhite = "wordmark-white"
    case markColor = "mark-color"
    case markNavy = "mark-navy"
    case markWhite = "mark-white"
    case menuBar = "SidefolkMenuBar"

    var image: NSImage? {
        guard let resources = ResourceLocator.resources else { return nil }
        let path = self == .menuBar ? "MenuBar/\(rawValue).pdf" : "Brand/\(rawValue).png"
        guard let image = NSImage(contentsOf: resources.appendingPathComponent(path)) else { return nil }
        if self == .menuBar {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
        }
        return image
    }
}
