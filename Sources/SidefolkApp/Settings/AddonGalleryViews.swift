import AppKit
import SidefolkCore
import SwiftUI

/// Settings › Extensions › Gallery (D55): the extensions Sidefolk and others publish, to add with a click. Each row
/// says who made it, with a seal on Sidefolk's own; Get downloads it, checks its signature and opens the install
/// preview, as for any extension.
struct GalleryExtensionsView: View {
    var model: SettingsModel
    private var gallery: AddonGalleryModel { model.gallery }

    var body: some View {
        let entries = gallery.entries(.extension)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !gallery.available {
                RowsCard { InlineEmpty(text: "This copy of Sidefolk has no add-on gallery.", systemImage: "shippingbox") }
            } else if entries.isEmpty {
                RowsCard {
                    if gallery.loading {
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
            } else {
                let official = entries.filter(\.official), others = entries.filter { !$0.official }
                if !official.isEmpty {
                    SettingsGroup(title: "From Sidefolk",
                                  footer: "Made and signed by Sidefolk. Each runs in its own sandbox, and you see what it may do before it is added.") {
                        ForEach(official) { GalleryRow(entry: $0, model: model) }
                    }
                }
                if !others.isEmpty {
                    SettingsGroup(title: "From the community", footer: "Reviewed and signed by Sidefolk; made by the people named.") {
                        ForEach(others) { GalleryRow(entry: $0, model: model) }
                    }
                }
            }
            if let error = gallery.error, !entries.isEmpty {
                Text("Showing the gallery as last seen: \(error.message)").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
        .task { await gallery.load() }
    }
}

/// One extension in the gallery: icon, name (a seal when Sidefolk made it), one line, who and how big, and Get.
private struct GalleryRow: View {
    var entry: AddonEntry
    var model: SettingsModel
    private var gallery: AddonGalleryModel { model.gallery }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                ExtensionBadge(look: ExtensionLook(name: entry.shownName, iconPath: gallery.preview(entry)?.path, folk: nil), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: entry.shownName).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        if entry.official { OfficialSeal() }
                    }
                    if !entry.shownTagline.isEmpty {
                        Text(verbatim: entry.shownTagline).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    Text(verbatim: AddonWords.byline(entry)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
                .help(entry.shownDescription)
                Spacer(minLength: Theme.Space.s)
                GetButton(state: gallery.state(entry), name: entry.shownName) {
                    Task { await gallery.get(extension: entry) }
                }
            }
            if let failure = gallery.failures[entry.id] { InlineError(error: failure).padding(.leading, 32 + Theme.Space.m) }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
    }
}

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

// MARK: Companions

/// A companion in the gallery that isn't on this Mac yet: its profile picture, name and what it is, and a download
/// mark; a click downloads it and makes it the companion.
struct GalleryCompanionCard: View {
    var entry: AddonEntry
    var model: SettingsModel
    private var gallery: AddonGalleryModel { model.gallery }

    var body: some View {
        let choice = entry.companion.flatMap(CompanionChoice.init(rawValue:))
        let role = choice.map(CompanionArt.role) ?? entry.tagline
        let state = gallery.state(entry)
        Button { Task { await gallery.get(companion: entry, choose: true) } } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    picture.frame(width: 84, height: 84)
                    if entry.official { OfficialSeal(size: 13).padding(2) }
                }
                Text(verbatim: entry.name).font(Theme.Font.body).foregroundStyle(Theme.ink)
                Text(verbatim: role).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true).minimumScaleFactor(0.85)
                Group {
                    if case .working(let p) = state {
                        ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 64)
                    } else {
                        Label(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file), systemImage: "arrow.down.circle")
                            .font(Theme.Font.caption).foregroundStyle(Theme.accent)
                    }
                }
                .frame(height: 14)
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state != .get)
        .help(entry.description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(entry.name), \(role). Downloads when chosen.", comment: "A companion in the gallery, not on this Mac yet"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var picture: some View {
        if let url = gallery.preview(entry), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().clipShape(Circle()).padding(6).opacity(0.85)
        } else {
            Circle().fill(Theme.surfaceSunken).padding(6)
        }
    }
}
