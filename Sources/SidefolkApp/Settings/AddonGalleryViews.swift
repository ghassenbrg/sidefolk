import AppKit
import SidefolkCore
import SwiftUI

/// Settings › Extensions › Gallery (D55): the extensions Sidefolk and others publish, to add with a click, on shelves
/// (D56: Everyday, Files and documents, For developers, Fun) and found by the words typed above. Each row says who
/// made it, with a seal on Sidefolk's own; Get downloads it, checks its signature and opens the install preview, as
/// for any extension.
struct GalleryExtensionsView: View {
    var model: SettingsModel
    /// The words typed in the page's search box.
    var search: String
    @State private var shelf: Shelf = .all
    private var gallery: AddonGalleryModel { model.gallery }

    enum Shelf: Hashable {
        case all
        case one(AddonCategory?)
    }

    var body: some View {
        let entries = gallery.entries(.extension)
        let found = entries.filter { $0.matches(search, extra: [Self.title($0.shelf)]) }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !gallery.available {
                RowsCard { InlineEmpty(text: "This copy of Sidefolk has no add-on gallery.", systemImage: "shippingbox") }
            } else if entries.isEmpty, gallery.hidesSnapshots(.extension) {
                RowsCard { SnapshotsHiddenNote(gallery: gallery) }
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
                shelves(found)
                let shown = found.filter { shelf == .all || shelf == .one($0.shelf) }
                if shown.isEmpty {
                    RowsCard {
                        InlineEmpty(text: "Nothing in the gallery matches “\(search.trimmingCharacters(in: .whitespaces))”.",
                                    systemImage: "magnifyingglass")
                    }
                }
                ForEach(Self.order(shown), id: \.self) { category in
                    SettingsGroup(title: Text(verbatim: Self.title(category))) {
                        ForEach(shown.filter { $0.shelf == category }) { GalleryRow(entry: $0, model: model) }
                    }
                }
                if gallery.hidesSnapshots(.extension) { RowsCard { SnapshotsHiddenNote(gallery: gallery) } }
                Text("Sidefolk's own carry its seal. Every extension here is signed by Sidefolk, runs in its own sandbox, and shows what it may do before it is added.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xs)
            }
            if let error = gallery.error, !entries.isEmpty {
                Text("Showing the gallery as last seen: \(error.message)").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
        .task { await gallery.load() }
    }

    /// All, then each shelf that has something, with how many the words find on it.
    private func shelves(_ found: [AddonEntry]) -> some View {
        Picker("Category", selection: $shelf) {
            Text("All \(found.count)", comment: "The gallery's shelves: every extension, with how many: “All 9”").tag(Shelf.all)
            ForEach(Self.order(gallery.entries(.extension)), id: \.self) { category in
                Text(verbatim: "\(Self.title(category)) \(found.filter { $0.shelf == category }.count)").tag(Shelf.one(category))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// The shelves `entries` are on, in their usual order, Other last.
    static func order(_ entries: [AddonEntry]) -> [AddonCategory?] {
        let present = Set(entries.map(\.shelf))
        return (AddonCategory.allCases.map { Optional($0) } + [nil]).filter(present.contains)
    }

    static func title(_ category: AddonCategory?) -> String {
        switch category {
        case .everyday?: String(localized: "Everyday", comment: "A shelf of the add-on gallery: currency, news feeds…")
        case .files?: String(localized: "Files", comment: "A shelf of the add-on gallery: PDFs, pictures, zip files, QR codes")
        case .developer?: String(localized: "Developers", comment: "A shelf of the add-on gallery: Git, developer tools")
        case .fun?: String(localized: "Fun", comment: "A shelf of the add-on gallery: games and trivia")
        case nil: String(localized: "Other", comment: "A shelf of the add-on gallery: what fits none of the others")
        }
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
                            .font(Theme.Font.caption).foregroundStyle(Theme.link)
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

/// On Releases (the default) the gallery keeps its snapshots out of sight (D65); this says so, so it doesn't look
/// empty, and offers them: the same choice as Settings › General › Updates, which Sidefolk's own updates follow too.
struct SnapshotsHiddenNote: View {
    var gallery: AddonGalleryModel

    var body: some View {
        InlineEmpty(text: "Add-ons in snapshots are hidden: test versions, before their release. Showing them offers Sidefolk's own snapshots too, as in Settings › General › Updates.",
                    systemImage: "testtube.2", actionTitle: "Show Snapshots") { gallery.showSnapshots() }
    }
}
