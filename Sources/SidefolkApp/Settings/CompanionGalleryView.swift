import AppKit
import ImageIO
import SidefolkCore
import SwiftUI

enum CompanionPageFocus: Hashable { case search }

/// The top of Settings › Companion, outside the scroll: Yours or Gallery, and on Gallery its search, filters and order,
/// so they stay in reach however far the person scrolls through hundreds.
struct CompanionPageHeader: View {
    var model: SettingsModel
    var focus: FocusState<CompanionPageFocus?>.Binding
    private var chooser: CompanionChooserModel { model.chooser }

    var body: some View {
        @Bindable var chooser = model.chooser
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Picker("Page", selection: $chooser.page) {
                Text(String(localized: "companions.yours", defaultValue: "Yours",
                            comment: "Settings › Companion: the page of companions on this Mac, to wear (several companions)"))
                    .tag(CompanionChooserModel.Page.yours)
                Text("Gallery", comment: "Settings › Companion: companions to download from the add-on gallery").tag(CompanionChooserModel.Page.gallery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if chooser.page == .gallery, model.gallery.available, !chooser.galleryEntries.isEmpty {
                SearchBox(text: $chooser.browse.text, prompt: Text("Search companions in the gallery"), focus: focus, focusValue: .search)
                filters
            }
        }
    }

    /// Each filter only when the gallery has something it would tell apart; the order always.
    private var filters: some View {
        @Bindable var chooser = model.chooser
        let entries = chooser.galleryEntries
        return HStack(spacing: Theme.Space.m) {
            if CompanionBrowse.offersLooks(entries) {
                Picker("Look", selection: $chooser.browse.look) {
                    Text("All", comment: "Gallery filter: companions in any look").tag(CompanionBrowse.Look.any)
                    Text(verbatim: "3D").tag(CompanionBrowse.Look.threeD)
                    Text(verbatim: "2D").tag(CompanionBrowse.Look.twoD)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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

/// Settings › Companion › Gallery (D?? companion chooser): the gallery's companions as a grid that loads its pictures
/// as they scroll into sight, narrowed by the header. A card's button downloads (or wears what is here); the card
/// itself opens the details.
struct CompanionGalleryView: View {
    var model: SettingsModel
    private var chooser: CompanionChooserModel { model.chooser }
    private var gallery: AddonGalleryModel { model.gallery }

    var body: some View {
        let entries = chooser.galleryEntries
        let found = chooser.found
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if entries.isEmpty || !gallery.available {
                GalleryStatus(gallery: gallery, kind: .companion)
            } else {
                HStack {
                    (found.count == entries.count
                         ? Text("\(entries.count) companions", comment: "Over the companion gallery: how many it has")
                         : Text("Showing \(found.count) of \(entries.count)", comment: "Over the companion gallery, narrowed: how many companions are shown of how many"))
                        .font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if chooser.browse.isNarrowed {
                        Button("Clear Filters") { chooser.browse = CompanionBrowse(sort: chooser.browse.sort) }.buttonStyle(.sf(.quiet))
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                if found.isEmpty {
                    RowsCard { InlineEmpty(text: "No companion in the gallery matches these filters.", systemImage: "magnifyingglass") }
                }
                ForEach(found.compactMap { gallery.failures[$0.id] }, id: \.message) { InlineError(error: $0) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(found) { entry in
                        GalleryCompanionCard(entry: entry, picture: chooser.preview(entry), state: chooser.state(entry),
                                             failed: gallery.failures[entry.id] != nil,
                                             open: { chooser.detail = entry },
                                             get: { chooser.get(entry, wear: false) },
                                             wear: { chooser.get(entry, wear: true) },
                                             update: { chooser.update(entry) })
                    }
                }
                if gallery.hidesSnapshots(.companion) { RowsCard { SnapshotsHiddenNote(gallery: gallery) } }
                Text("Every companion here is signed by Sidefolk and checked before it's installed. Sidefolk's own carry its seal.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xs)
                GalleryLastSeen(gallery: gallery)
            }
        }
    }
}

/// One companion in the gallery: its picture, name (a seal on Sidefolk's own), one line, its size and looks or that
/// it is here already, and the one thing to do with it.
private struct GalleryCompanionCard: View {
    var entry: AddonEntry
    var picture: URL?
    var state: CompanionChooserModel.EntryState
    var failed: Bool
    var open: () -> Void
    var get: () -> Void
    var wear: () -> Void
    var update: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Button(action: open) {
                VStack(spacing: 3) {
                    GalleryPicture(url: picture, side: 88)
                        .overlay(alignment: .topTrailing) { if entry.official { OfficialSeal(size: 13) } }
                    Text(verbatim: entry.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(verbatim: CompanionChooserModel.tagline(entry)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    meta
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Details of \(entry.name)", comment: "A companion card in the gallery: open its details"))
            action.frame(height: 24)
        }
        .padding(Theme.Space.s)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(failed ? Theme.danger : Theme.line))
        .accessibilityElement(children: .contain)
    }

    /// Here already, or its size; and its looks.
    private var meta: some View {
        let looks = entry.looks.contains(.twoD) ? "3D · 2D" : "3D"
        return Group {
            switch state {
            case .owned, .wearing, .update:
                Label { Text("On this Mac", comment: "A gallery companion already downloaded") } icon: { Image(systemName: "checkmark") }
            default:
                Text(verbatim: "\(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)) · \(looks)")
            }
        }
        .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .get:
            Button("Get", action: get).buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Get \(entry.name)", comment: "A button in the add-on gallery: download and add this"))
        case .working(let p):
            ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 80)
                .accessibilityLabel(Text("Downloading \(entry.name)", comment: "The add-on gallery, while a download runs"))
        case .owned:
            Button("Wear", action: wear).buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Wear \(entry.name)", comment: "A companion's menu or the gallery: make it the companion"))
        case .update:
            Button("Update", action: update).buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Update \(entry.name)", comment: "A button in the add-on gallery"))
        case .wearing:
            Label("Wearing", systemImage: "checkmark.circle.fill").font(Theme.Font.captionStrong).foregroundStyle(Theme.accent)
        }
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
