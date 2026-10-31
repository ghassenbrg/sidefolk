import AppKit
import SidefolkCharacter
import SidefolkCore

/// Settings › Companion's chooser (D?? companion chooser): every companion the person can wear in one list, what each
/// one's menu offers, and the gallery to browse for more, with what is narrowed, open or waiting for a yes. State
/// lives here rather than in the views, so the debug app and the snapshots can show any of it.
@MainActor @Observable
final class CompanionChooserModel {
    enum Page: Hashable { case yours, gallery }

    /// What a gallery companion is here: to get, on its way, here, worn, or here with a newer version.
    enum EntryState: Equatable {
        case get
        case working(Double)
        case owned
        case wearing
        case update
    }

    private unowned let parent: SettingsModel
    var page = Page.yours
    var browse = CompanionBrowse()
    /// The gallery companion whose details are open.
    var detail: AddonEntry?
    /// The companion waiting for the person to confirm its removal.
    var removing: OwnedCompanion?
    /// The ways to add one's own, open beside the Add tile.
    var adding = false
    /// Bumped when the made and folder lists are read again (they live in `CompanionArt`, outside observation).
    private var revision = 0

    init(parent: SettingsModel) { self.parent = parent }

    private var gallery: AddonGalleryModel { parent.gallery }
    private var settings: AppSettings { parent.settings }

    // MARK: Yours

    /// Everyone the person can wear: Sidefolk's own, then the gallery's, made-by-you and added-from-a-folder by name.
    var owned: [OwnedCompanion] {
        _ = revision
        let builtIn = CompanionArt.offered.filter { !CompanionArt.species($0).inGallery }
        // Only those whose files are all here can be worn (a download cut short leaves a folder behind).
        let installed = gallery.companions.filter { gallery.sampled || Companion3DStage.has($0.companion) }
        let extensions = SidefolkPaths.standard().home.appendingPathComponent("Extensions", isDirectory: true).path + "/"
        let made = CompanionArt.made.compactMap { report in
            report.companion.map {
                CompanionLibrary.Made(id: $0.id, name: $0.name, summary: $0.summary, folder: report.folder,
                                      fromExtension: report.folder.path.hasPrefix(extensions))
            }
        }
        return CompanionLibrary.owned(builtIn: builtIn, installed: installed, made: made, folder: CompanionAddons.folder,
                                      role: CompanionArt.role)
    }

    /// Made-by-you folders that couldn't be read, with the first reason: said under the grid, as before.
    var unreadable: [(name: String, reason: String)] {
        _ = revision
        return CompanionArt.made.filter { $0.companion == nil }.map { ($0.folder.lastPathComponent, $0.errors.first ?? "") }
    }

    func worn(in owned: [OwnedCompanion]) -> OwnedCompanion.Wear { CompanionLibrary.worn(settings, in: owned) }

    /// The one worn now, as listed.
    var wornCompanion: OwnedCompanion? {
        let list = owned
        let wear = worn(in: list)
        return list.first { $0.wear == wear }
    }

    func actions(for companion: OwnedCompanion, worn: Bool) -> [CompanionAction] {
        let name = companion.character
        let downloadable = name.map { gallery.catalog?.companion($0, on: settings.updates.effectiveChannel) != nil } ?? false
        return CompanionLibrary.actions(for: companion, worn: worn, update: name.flatMap { gallery.update(forCompanion: $0)?.version },
                                        downloadable: downloadable)
    }

    func perform(_ action: CompanionAction, on companion: OwnedCompanion) {
        switch action {
        case .wear: wear(companion)
        case .update:
            guard let name = companion.character, let entry = gallery.update(forCompanion: name) else { return }
            Task { await gallery.get(companion: entry, choose: false) }
        case .showInFinder:
            if let folder = companion.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        case .remove: removing = companion
        case .keep: break
        }
    }

    func wear(_ companion: OwnedCompanion) {
        let name = companion.name
        switch companion.wear {
        case .choice(let choice): parent.update { $0.choose(choice) }
        case .custom(let id): parent.update { $0.choose(custom: id, name: name) }
        case .local(let folder): parent.update { $0.choose(local: folder, name: name) }
        }
    }

    /// Removes `companion` once the person said yes: the one worn gives way first.
    func remove(_ companion: OwnedCompanion) async {
        removing = nil
        let list = owned
        let replacement = CompanionLibrary.replacement(removing: companion, in: settings, owned: list)
        if companion.origin == .made {
            guard let folder = companion.folder else { return }
            if let replacement { parent.update { $0.choose(replacement) } }
            // Their own work: to the Trash, where they can put it back, never deleted outright.
            do {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
                gallery.companionError = nil
            } catch {
                gallery.companionError = UserFacingError("It couldn't be moved to the Trash.", detail: String(describing: error))
            }
            reload()
            parent.services.settingsChanged()
        } else if let name = companion.character {
            await gallery.remove(companion: name, wearing: replacement)
            revision += 1
        }
    }

    /// Reads the made and folder companions again (Settings opened, or Sidefolk came back to the front after the
    /// person worked in the companions folder), then the gallery.
    func reload() {
        CompanionArt.reloadMade()
        revision += 1
        Task { await gallery.readInstalled() }
    }

    // MARK: The gallery

    /// The characters already here, by their folder's name, the built-ins included.
    var ownedNames: Set<String> {
        Set(owned.compactMap { companion in
            switch companion.wear {
            case .choice(let choice): choice.rawValue
            case .local(let name): name
            case .custom: nil
            }
        })
    }

    /// The gallery's companions this copy can wear, on the person's channel (D65).
    var galleryEntries: [AddonEntry] { gallery.entries(.companion).filter(\.wearable) }

    /// What the words, filters and order leave.
    var found: [AddonEntry] { browse.apply(galleryEntries, owned: ownedNames) { [Self.tagline($0)] } }

    /// A gallery companion's line: Sidefolk's own in the person's language (D28), anyone else's as published.
    static func tagline(_ entry: AddonEntry) -> String {
        entry.companion.flatMap(CompanionChoice.init(rawValue:)).map(CompanionArt.role).flatMap { $0.isEmpty ? nil : $0 } ?? entry.tagline
    }

    /// How many the gallery has that aren't here yet, for the tile that leads to it.
    var notYetHere: Int {
        let names = ownedNames
        return galleryEntries.filter { !names.contains($0.companion ?? "") }.count
    }

    func state(_ entry: AddonEntry) -> EntryState {
        switch gallery.state(entry) {
        case .working(let p): return .working(p)
        case .update: return .update
        default: break
        }
        let list = owned
        guard let here = entry.companion.flatMap({ Self.here($0, in: list) }) else { return .get }
        return worn(in: list) == here.wear ? .wearing : .owned
    }

    /// Downloads it, then wears it when `wear` (or wears it at once when it is already here).
    func get(_ entry: AddonEntry, wear: Bool) {
        if wear, let here = entry.companion.flatMap({ Self.here($0, in: owned) }) {
            self.wear(here)
            return
        }
        Task {
            await gallery.get(companion: entry, choose: wear)
            revision += 1
        }
    }

    func update(_ entry: AddonEntry) {
        Task { await gallery.get(companion: entry, choose: false) }
    }

    /// The companion here that a gallery entry names: by its 3D folder, or one of Sidefolk's own of that name.
    private static func here(_ name: String, in owned: [OwnedCompanion]) -> OwnedCompanion? {
        owned.first { $0.character == name || $0.origin == .builtIn && $0.wear == CompanionChoice(rawValue: name).map { .choice($0) } }
    }

    /// Picture for a gallery companion: its own preview in the catalog.
    func preview(_ entry: AddonEntry) -> URL? { gallery.preview(entry) }
}
