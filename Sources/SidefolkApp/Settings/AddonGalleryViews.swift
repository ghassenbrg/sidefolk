import AppKit
import SidefolkCore
import SwiftUI

/// Get, Update, a download's progress, or "Added".
struct GetButton: View {
    var state: AddonGalleryModel.State
    var name: String
    var action: () -> Void

    var body: some View {
        switch state {
        case .get:
            Button("Get", action: action).buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Get \(name)", comment: "A button in the add-on gallery: download and add this"))
        case .update:
            Button("Update", action: action).buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Update \(name)", comment: "A button in the add-on gallery"))
        case .working(let p):
            ProgressView(value: max(p, 0.02)).progressViewStyle(.circular).controlSize(.small)
                .accessibilityLabel(Text("Downloading \(name)", comment: "The add-on gallery, while a download runs"))
        case .installed:
            Label("Added", systemImage: "checkmark").labelStyle(.titleAndIcon).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Made and signed by Sidefolk (D55).
struct OfficialSeal: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "checkmark.seal.fill").font(.system(size: size)).foregroundStyle(Theme.accent)
            .help(Text("Made by Sidefolk", comment: "The seal on Sidefolk's own add-ons in the gallery"))
            .accessibilityLabel(Text("Made by Sidefolk", comment: "The seal on Sidefolk's own add-ons in the gallery"))
    }
}

enum AddonWords {
    /// "By Sidefolk · 1.1.0 · 168 KB".
    static func byline(_ entry: AddonEntry) -> String {
        let size = ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
        return String(localized: "By \(entry.author) · \(entry.version) · \(size)",
                      comment: "Under an add-on's name in the gallery: who made it, its version and its download size")
    }
}

// MARK: Shared by the gallery's pages

/// What a gallery page shows instead of its list (D55, D65), the same for extensions and companions: no gallery in
/// this copy, snapshots hidden on Releases, still looking, or not reached.
struct GalleryStatus: View {
    var gallery: AddonGalleryModel
    var kind: AddonEntry.Kind

    var body: some View {
        RowsCard {
            if !gallery.available {
                InlineEmpty(text: "This copy of Sidefolk has no add-on gallery.", systemImage: "shippingbox")
            } else if gallery.hidesSnapshots(kind) {
                SnapshotsHiddenNote(gallery: gallery)
            } else if gallery.loading {
                HStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Looking in the gallery…").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
            } else {
                InlineEmpty(text: "The gallery couldn't be reached.", systemImage: "wifi.slash", actionTitle: "Try Again") {
                    Task { await gallery.load(refresh: true) }
                }
            }
        }
    }
}

/// Under a gallery list that came from this Mac's copy because the gallery couldn't be reached.
struct GalleryLastSeen: View {
    var gallery: AddonGalleryModel

    var body: some View {
        if let error = gallery.error {
            Text("Showing the gallery as last seen: \(error.message)").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.Space.xs)
        }
    }
}

/// On Releases (the default) the gallery keeps its snapshots out of sight (D65); this says so, so it doesn't look
/// empty, and offers them: the same choice as Settings › General › Updates, which Sidefolk's own updates follow too.
struct SnapshotsHiddenNote: View {
    var gallery: AddonGalleryModel

    var body: some View {
        InlineEmpty(text: "Add-ons in snapshots are hidden: test versions, before their release. Showing them offers Sidefolk's own snapshots too, as in Settings › General › Updates.",
                    systemImage: "testtube.2", actionTitle: "Show Snapshots") { gallery.showSnapshots() }
    }
}
