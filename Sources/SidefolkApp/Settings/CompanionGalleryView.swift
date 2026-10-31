import AppKit
import ImageIO
import SidefolkCore
import SwiftUI

/// The Gallery's companion filters (D77), for a gallery of hundreds: the look, who made it, hiding the ones here, and the
/// order. Each filter only shows when the gallery has something it would tell apart. Home's Gallery shows them (D84).
struct CompanionFilters: View {
    var chooser: CompanionChooserModel

    var body: some View { filters }

    /// Each filter only when the gallery has something it would tell apart; the order always.
    private var filters: some View {
        @Bindable var chooser = chooser
        let entries = chooser.galleryEntries
        return HStack(spacing: Theme.Space.m) {
            if CompanionBrowse.offersLooks(entries) {
                SegmentedPicker("Look", selection: $chooser.browse.look, segments: [
                    .init(CompanionBrowse.Look.any, Text("All", comment: "Gallery filter: companions in any look")),
                    .init(CompanionBrowse.Look.threeD, verbatim: "3D"),
                    .init(CompanionBrowse.Look.twoD, verbatim: "2D"),
                ], small: true)
                .help(Text("Only companions that come in 3D, or in 2D", comment: "The look filter in the companion gallery"))
            }
            if CompanionBrowse.offersMakers(entries) {
                Picker("Made by", selection: $chooser.browse.maker) {
                    Text("Anyone", comment: "Gallery filter: companions by any maker").tag(CompanionBrowse.Maker.anyone)
                    Text("Sidefolk", comment: "Gallery filter: Sidefolk's own companions").tag(CompanionBrowse.Maker.sidefolk)
                    Text("Others", comment: "Gallery filter: companions made by others than Sidefolk").tag(CompanionBrowse.Maker.others)
                }
                .fixedSize()
            }
            Toggle(isOn: $chooser.browse.hideOwned) {
                Text("Hide yours", comment: "Gallery filter: leave out the companions already on this Mac")
            }
            .toggleStyle(.checkbox)
            .fixedSize()
            Spacer(minLength: 0)
            Picker("Sort", selection: $chooser.browse.sort) {
                ForEach(CompanionBrowse.sorts(for: entries), id: \.self) { sort in
                    switch sort {
                    case .name: Text("Name", comment: "Gallery order: by name").tag(sort)
                    case .newest: Text("Newest", comment: "Gallery order: the most recently published first").tag(sort)
                    case .smallest: Text("Smallest", comment: "Gallery order: the smallest download first").tag(sort)
                    }
                }
            }
            .fixedSize()
        }
        .font(Theme.Font.body)
    }
}

/// A gallery picture, read and scaled down off the main thread the first time its card comes into sight, then kept:
/// a gallery of hundreds costs only the cards on screen.
struct GalleryPicture: View {
    var url: URL?
    var side: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().clipShape(Circle())
            } else {
                Circle().fill(Theme.surfaceSunken)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: url) { image = await Self.load(url, side: side) }
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func load(_ url: URL?, side: CGFloat) async -> NSImage? {
        guard let url else { return nil }
        let key = "\(url.path)@\(side)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let pixels = Int(side * 2)
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: CGSize(width: side, height: side))
        cache.setObject(image, forKey: key)
        return image
    }
}
