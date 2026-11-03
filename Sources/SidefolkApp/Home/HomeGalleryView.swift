import SidefolkCore
import SwiftUI

/// Home › Gallery (D84; moved out of Settings): companions, extensions and themes from the add-on gallery, with big
/// pictures and a passport of who made each and what it can touch. The models are Settings' own (`AddonGalleryModel`,
/// `CompanionChooserModel`), so getting, wearing, updating and the extension install preview work exactly as before.
/// What an extension can touch is known once it's here (its permission summary); before, its install preview says it.
struct HomeGalleryView: View {
    var settings: SettingsModel
    @State private var shelf: Shelf
    @State private var search: String
    @FocusState private var focus: GalleryFocus?

    /// `shelf` and `search` are where it opens (UI snapshots show a filter or a search).
    init(settings: SettingsModel, shelf: Shelf = .all, search: String = "") {
        self.settings = settings
        _shelf = State(initialValue: shelf)
        _search = State(initialValue: search)
    }

    enum Shelf: Hashable {
        case all, companions, extensions, themes

        /// The add-ons this shelf shows, nil for every kind.
        var kind: AddonEntry.Kind? {
            switch self {
            case .all: nil
            case .companions: .companion
            case .extensions: .extension
            case .themes: .theme
            }
        }
    }
    enum GalleryFocus: Hashable { case search }

    private var gallery: AddonGalleryModel { settings.gallery }
    private var chooser: CompanionChooserModel { settings.chooser }

    var body: some View {
        let companions = chooser.found
        let extensions = gallery.entries(.extension).filter { $0.matches(search) }
        let themes = gallery.entries(.theme).filter { $0.matches(search) }
        HomePage {
            WrapRow(minimum: 420, spacing: Theme.Space.m) {
                SegmentedPicker("Show", selection: $shelf, segments: [
                    .init(Shelf.all, Text("All", comment: "The Gallery's filter: everything")),
                    .init(Shelf.companions, Text("Companions \(companions.count)", comment: "The Gallery's filter, with how many")),
                    .init(Shelf.extensions, Text("Extensions \(extensions.count)", comment: "The Gallery's filter, with how many")),
                    .init(Shelf.themes, Text("Themes \(themes.count)", comment: "The Gallery's filter, with how many")),
                ])
                SearchBox(text: $search, prompt: Text("Search the Gallery"), focus: $focus, focusValue: .search)
                    .frame(maxWidth: 300)
            }
            if shelf == .companions && !chooser.galleryEntries.isEmpty { CompanionFilters(chooser: chooser) }
            AddonUpdatesSection(updates: settings.services.updates, gallery: gallery, kind: shelf.kind, search: search)
            channelNote
            if !gallery.available || (gallery.catalog == nil && (gallery.loading || gallery.error != nil)) {
                GalleryStatus(gallery: gallery, kind: .extension)
            } else {
                if shelf == .all || shelf == .companions { companionShelf(companions) }
                if shelf == .all || shelf == .extensions { extensionShelf(extensions) }
                if shelf == .all || shelf == .themes { themeShelf(themes) }
                if companions.isEmpty && extensions.isEmpty && themes.isEmpty && !search.isEmpty {
                    RowsCard {
                        InlineEmpty(text: "Nothing in the Gallery matches “\(search.trimmingCharacters(in: .whitespaces))”.", systemImage: "magnifyingglass")
                    }
                }
                GalleryLastSeen(gallery: gallery)
            }
        }
        .background {
            Button("Find") { focus = .search }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: search) { chooser.browse.text = search }
        .onAppear { if !search.isEmpty { chooser.browse.text = search } }
        .sheet(item: Binding(get: { settings.installPreview }, set: { settings.installPreview = $0 })) { p in
            InstallPreviewSheet(preview: p, model: settings)
        }
        .sheet(item: Binding(get: { chooser.detail }, set: { chooser.detail = $0 })) { entry in
            CompanionGalleryDetail(entry: entry, model: settings)
        }
    }

    /// On snapshots, add-ons here are previews; on Releases, hidden snapshots are said, so the Gallery doesn't look empty.
    @ViewBuilder private var channelNote: some View {
        if settings.settings.updates.effectiveChannel == .snapshots {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: "flag").foregroundStyle(Theme.inkMuted)
                (Text("You're on the snapshot channel.").fontWeight(.semibold).foregroundStyle(Theme.ink)
                    + Text(" Add-ons here are previews and may change before they're final. Each still shows who made it and what it can touch.")
                    .foregroundStyle(Theme.inkMuted))
                    .font(Theme.Font.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Switch in Settings") { settings.services.openSettings(tab: .general) }.buttonStyle(.sf(.quiet)).fixedSize()
            }
            .padding(Theme.Space.l)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if gallery.hidesSnapshots(.extension) || gallery.hidesSnapshots(.companion) {
            RowsCard { SnapshotsHiddenNote(gallery: gallery) }
        }
    }

    // MARK: Shelves

    private func shelfHeader(_ title: Text, _ detail: Text, count: Int, limit: Int, to target: Shelf) -> some View {
        SectionHeader(title: title, detail: detail) {
            if shelf == .all && count > limit {
                Button { shelf = target } label: { Text("See all \(count)", comment: "A Gallery shelf: show every one") }.buttonStyle(.sf(.quiet))
            }
        }
    }

    @ViewBuilder private func companionShelf(_ entries: [AddonEntry]) -> some View {
        if !entries.isEmpty {
            let shown = shelf == .all ? Array(entries.prefix(5)) : entries
            shelfHeader(Text("Companions"), Text("Someone to keep you company. They can't touch anything."),
                        count: entries.count, limit: 5, to: .companions)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Space.m, alignment: .top)], spacing: Theme.Space.m) {
                ForEach(shown) { entry in CompanionGalleryCard(entry: entry, chooser: chooser, failed: gallery.failures[entry.id] != nil) }
            }
            if let error = gallery.companionError { InlineError(error: error) }
        }
    }

    @ViewBuilder private func extensionShelf(_ entries: [AddonEntry]) -> some View {
        if !entries.isEmpty {
            let shown = shelf == .all ? Array(entries.prefix(4)) : entries
            shelfHeader(Text("Extensions"), Text("New things \(settings.settings.companionName) can do. Each shows what it can touch before you add it."),
                        count: entries.count, limit: 4, to: .extensions)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.Space.m, alignment: .top)], spacing: Theme.Space.m) {
                ForEach(shown) { entry in ExtensionGalleryCard(entry: entry, settings: settings) }
            }
        }
    }

    @ViewBuilder private func themeShelf(_ entries: [AddonEntry]) -> some View {
        if !entries.isEmpty {
            let shown = shelf == .all ? Array(entries.prefix(4)) : entries
            shelfHeader(Text("Themes"), Text("Colour, type and light for the whole app."), count: entries.count, limit: 4, to: .themes)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.m, alignment: .top)], spacing: Theme.Space.m) {
                ForEach(shown) { entry in ThemeGalleryCard(entry: entry, settings: settings) }
            }
        }
    }
}

/// A companion with its painted portrait large (A13), its name, size and looks, and the one thing to do.
private struct CompanionGalleryCard: View {
    var entry: AddonEntry
    var chooser: CompanionChooserModel
    var failed: Bool

    var body: some View {
        let state = chooser.state(entry)
        VStack(alignment: .leading, spacing: 0) {
            Button { chooser.detail = entry } label: {
                GalleryArt(url: chooser.preview(entry), height: 132)
                    .overlay(alignment: .topLeading) {
                        if state == .wearing { badge(Text("In use", comment: "A Gallery companion: the one worn now")) }
                    }
            }
            .buttonStyle(.sfBare)
            .help(Text("Details of \(entry.name)", comment: "A companion card in the gallery: open its details"))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: entry.name).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    if entry.official { OfficialSeal() }
                }
                Text(verbatim: meta).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                HStack {
                    switch state {
                    case .owned, .wearing: Chip("Yours", tone: .success, systemImage: "checkmark")
                    default: Chip("Free", tone: .neutral)
                    }
                    Spacer(minLength: 0)
                    action(state)
                }
                .padding(.top, Theme.Space.s)
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(failed ? Theme.danger : .clear))
        .elevation(.e1, radius: Theme.Radius.card)
        .accessibilityElement(children: .contain)
    }

    private var meta: String {
        let looks = entry.looks.contains(.twoD) ? "3D · 2D" : "3D"
        return "\(looks) · \(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)) · " + String(localized: "by \(entry.author)", comment: "Who made an add-on")
    }

    private func badge(_ text: Text) -> some View {
        text.font(Theme.Font.caption).fontWeight(.semibold).foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .padding(Theme.Space.s)
    }

    @ViewBuilder private func action(_ state: CompanionChooserModel.EntryState) -> some View {
        switch state {
        case .get:
            Button("Get") { chooser.get(entry, wear: false) }.buttonStyle(.sf(.primary))
                .accessibilityLabel(Text("Get \(entry.name)", comment: "A button in the add-on gallery: download and add this"))
        case .working(let p):
            ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 64)
                .accessibilityLabel(Text("Downloading \(entry.name)", comment: "The add-on gallery, while a download runs"))
        case .owned:
            Button("Use") { chooser.get(entry, wear: true) }.buttonStyle(.sf(.secondary))
                .accessibilityLabel(Text("Wear \(entry.name)", comment: "A companion's menu or the gallery: make it the companion"))
        case .update:
            Button("Update") { chooser.update(entry) }.buttonStyle(.sf(.secondary))
        case .wearing:
            EmptyView()
        }
    }
}

/// An extension with its passport (A13): its icon, name and line, then what it can touch (once it's here) and who made
/// and signed it; a maker the gallery doesn't vouch for reads amber, never red.
private struct ExtensionGalleryCard: View {
    var entry: AddonEntry
    var settings: SettingsModel

    private var gallery: AddonGalleryModel { settings.gallery }

    var body: some View {
        let installed = settings.extensions.first { $0.id == entry.id }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ExtensionBadge(look: ExtensionLook(name: entry.shownName, iconPath: gallery.preview(entry)?.path, folk: nil), size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.shownName).font(Theme.Font.headline).foregroundStyle(Theme.ink)
                    Text(verbatim: entry.shownTagline).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.shownDescription)
                GetButton(state: gallery.state(entry), name: entry.shownName) { Task { await gallery.get(extension: entry) } }
                    .buttonStyle(.sf(.primary))
            }
            ButtonRow(spacing: Theme.Space.xs) {
                if let installed {
                    ForEach(installed.permissionLines.prefix(3), id: \.self) { line in
                        Chip(verbatim: line.clipped(44), tone: .neutral)
                    }
                } else {
                    Chip("Shows what it can touch before you add it", tone: .neutral, systemImage: "checklist")
                }
                if entry.official {
                    Label("Signed by Sidefolk", systemImage: "checkmark.shield").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                } else {
                    Chip(text: Text("Not checked by Sidefolk · by \(entry.author)", comment: "A community add-on in the Gallery"),
                         tone: .warning, systemImage: "person")
                }
            }
            .padding(.leading, 48 + Theme.Space.m)
            if let failure = gallery.failures[entry.id] { InlineError(error: failure).padding(.leading, 48 + Theme.Space.m) }
        }
        .padding(Theme.Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}

/// A theme with its picture large, its name and line, and Get, Update or Use.
private struct ThemeGalleryCard: View {
    var entry: AddonEntry
    var settings: SettingsModel

    var body: some View {
        let gallery = settings.gallery
        let state = gallery.state(entry)
        let inUse = settings.settings.theme == entry.id && settings.settings.themeFolder == nil
        VStack(alignment: .leading, spacing: 0) {
            GalleryArt(url: gallery.preview(entry), height: 112)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: entry.name).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.xs)
                    switch state {
                    case .working(let p): ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 44)
                    case .installed where inUse: Chip("In use", tone: .success, systemImage: "checkmark")
                    case .installed:
                        Button("Use") { settings.update { $0.theme = entry.id; $0.themeFolder = nil } }.buttonStyle(.sf(.secondary))
                    case .update: Button("Update") { Task { await gallery.get(theme: entry, use: false) } }.buttonStyle(.sf(.secondary))
                    case .get: Button("Get") { Task { await gallery.get(theme: entry, use: true) } }.buttonStyle(.sf(.secondary))
                    }
                }
                Text(verbatim: entry.shownTagline).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .elevation(.e1, radius: Theme.Radius.card)
        .accessibilityElement(children: .contain)
    }
}

/// A gallery picture as a wide image filling the card's top, read off the main thread and kept (GalleryPicture's cache).
struct GalleryArt: View {
    var url: URL?
    var height: CGFloat
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.accentSoft
            // Pale pictures glare on a dark page.
            if let image { Image(nsImage: image).resizable().scaledToFill().brightness(scheme == .dark ? -0.14 : 0) }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) { image = await GalleryPicture.load(url, side: height * 1.6) }
    }
}
