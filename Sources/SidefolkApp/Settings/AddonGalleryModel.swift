import AppKit
import SidefolkCore

/// The add-on gallery as Settings shows it (D55): the signed catalog, what of it is on this Mac, and the downloads
/// under way. Companions install at a click (they only draw); extensions open the usual install preview first,
/// since one can act for the person.
@MainActor @Observable
final class AddonGalleryModel {
    private unowned let parent: SettingsModel
    private var store: AddonStore { parent.runtime.addons }

    private(set) var catalog: AddonCatalog?
    private(set) var loading = false
    private(set) var error: UserFacingError?
    private(set) var companions: [InstalledCompanion] = []
    /// Downloads under way, by add-on id: how far each is (0…1).
    private(set) var progress: [String: Double] = [:]
    /// The last failure of each add-on, said under it until the next try.
    private(set) var failures: [String: UserFacingError] = [:]
    /// Why the last companion added from a folder (D60), removed or moved to the Trash wasn't, said under the
    /// person's companions until the next try.
    var companionError: UserFacingError?

    init(parent: SettingsModel) { self.parent = parent }

    var available: Bool { sampled || store.source != nil }

    /// Showing sample data (UISnapshots): nothing is fetched or read from this Mac's gallery folder.
    private(set) var sampled = false

    /// The person's choice in Settings › Updates, which the gallery follows too (D65).
    private var channel: UpdateChannel { parent.settings.updates.effectiveChannel }

    /// What the gallery offers of one kind, Sidefolk's own first, then by name: snapshots only on Releases and
    /// snapshots (D65).
    func entries(_ kind: AddonEntry.Kind) -> [AddonEntry] {
        (catalog?.offered(on: channel) ?? []).filter { $0.kind == kind }
            .sorted { ($0.official ? 0 : 1, $0.name) < ($1.official ? 0 : 1, $1.name) }
    }

    /// The gallery has snapshots of this kind that Releases keeps out of sight: said, so it doesn't look empty.
    func hidesSnapshots(_ kind: AddonEntry.Kind) -> Bool {
        (catalog?.addons ?? []).contains { $0.kind == kind && !channel.includes($0.version) }
    }

    /// Offers snapshots, of Sidefolk and of the gallery: the same choice as Settings › Updates.
    func showSnapshots() { parent.update { $0.updates.channel = .snapshots } }

    func preview(_ entry: AddonEntry) -> URL? { catalog?.preview(for: entry) }

    /// Reads the companions in `Addons/Companions` again: one may have come by another way (an update by itself, the
    /// chosen one fetched at launch, the debug app).
    func readInstalled() async {
        guard !sampled else { return }
        companions = await store.installedCompanions()
    }

    /// The gallery as last checked on this Mac at once, then a fresh look (unless it is recent).
    func load(refresh: Bool = false) async {
        guard !sampled else { return }
        companions = await store.installedCompanions()
        if catalog == nil { catalog = await store.stored() }
        loading = true
        defer { loading = false }
        do {
            catalog = try await store.catalog(refresh: refresh)
            error = nil
        } catch {
            self.error = error as? UserFacingError ?? UserFacingError("The add-on gallery couldn't be reached.", recovery: "Check the connection and try again.")
        }
    }

    // MARK: What each one is here

    enum State: Equatable {
        case get
        case installed
        case update(from: String)
        case working(Double)
    }

    /// The gallery's newer version of an installed companion, while add-ons don't update by themselves (D70).
    func update(forCompanion name: String) -> AddonEntry? {
        guard let entry = entries(.companion).first(where: { $0.companion == name }), case .update = state(entry) else { return nil }
        return entry
    }

    func state(_ entry: AddonEntry) -> State {
        if let p = progress[entry.id] { return .working(p) }
        guard let version = installedVersion(entry) else { return .get }
        // Updates follow Settings › Updates, as Sidefolk's own do: a snapshot only for people who chose snapshots.
        return parent.settings.updates.effectiveChannel.offers(entry.version, over: version) ? .update(from: version) : .installed
    }

    func installedVersion(_ entry: AddonEntry) -> String? {
        switch entry.kind {
        case .companion: companions.first { $0.id == entry.id }?.version
        case .extension: parent.extensions.first { $0.id == entry.id }?.version
        case .theme: ThemeLibrary.app(parent.runtime.paths).all().first { $0.id == entry.id && $0.folder != nil }?.version
        }
    }

    // MARK: Companions

    /// Downloads and installs a companion, then makes it the companion when `choose`. One this copy has no case for
    /// is worn by its folder's name, as one added from a folder is.
    func get(companion entry: AddonEntry, choose: Bool) async {
        guard progress[entry.id] == nil, let name = entry.companion, entry.wearable else { return }
        failures[entry.id] = nil
        progress[entry.id] = 0
        defer { progress[entry.id] = nil }
        do {
            try await store.install(companion: entry) { [weak self] p in
                Task { @MainActor in if self?.progress[entry.id] != nil { self?.progress[entry.id] = p } }
            }
            let updating = companions.contains { $0.id == entry.id }
            companions = await store.installedCompanions()
            CompanionArt.reloadMade()
            CompanionArt.forgetPictures()
            if choose {
                if let choice = CompanionChoice(rawValue: name) {
                    parent.update { $0.choose(choice) }
                } else {
                    let shown = entry.name
                    parent.update { $0.choose(local: name, name: shown) }
                }
            } else {
                // An update (D70): the one on the desktop, if it is this one, reloads in place.
                parent.services.companionsUpdated(updating ? [name] : [])
            }
        } catch {
            failures[entry.id] = error as? UserFacingError ?? UserFacingError("\(entry.name) couldn't be installed.")
        }
        // The store fetches the catalog again when a pack is newer than it.
        catalog = await store.stored() ?? catalog
    }

    // MARK: Themes

    /// Downloads and installs a theme (D58, D64), then wears it when `use` (a click on its card).
    func get(theme entry: AddonEntry, use: Bool) async {
        guard progress[entry.id] == nil else { return }
        failures[entry.id] = nil
        progress[entry.id] = 0
        defer { progress[entry.id] = nil }
        do {
            let theme = try await store.install(theme: entry, into: .app(parent.runtime.paths)) { [weak self] p in
                Task { @MainActor in if self?.progress[entry.id] != nil { self?.progress[entry.id] = p } }
            }
            if use {
                parent.update {
                    $0.theme = theme.id
                    $0.themeFolder = nil
                }
            } else {
                parent.services.settingsChanged()
            }
        } catch {
            failures[entry.id] = error as? UserFacingError ?? UserFacingError("\(entry.name) couldn't be installed.")
        }
        catalog = await store.stored() ?? catalog
    }

    // MARK: Added from a folder (D60)

    /// Adds the 3D companion in `folder` once the person agrees (its character file is code the 3D page runs), then
    /// makes it the companion.
    func add(companionFolder folder: URL) async {
        companionError = nil
        do {
            let companion = try AddonStore.readLocalCompanion(folder)
            let alert = NSAlert()
            alert.messageText = String(localized: "Add “\(companion.name)” as your companion?")
            alert.informativeText = String(localized: """
                A companion's character file runs as code in Sidefolk's 3D view, and this one isn't from the add-on \
                gallery. Add only a companion you made yourself or got from someone you trust.
                """)
            alert.addButton(withTitle: String(localized: "Add Companion"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let added = try await store.install(companionFolder: folder)
            companions = await store.installedCompanions()
            CompanionArt.reloadMade()
            CompanionArt.forgetPictures()
            parent.update { $0.choose(local: added.companion, name: added.name) }
        } catch {
            companionError = error as? UserFacingError ?? UserFacingError("That companion couldn't be added.", detail: String(describing: error))
        }
    }

    /// Removes a companion from `Addons/Companions` (the gallery's, or the copy of one added from a folder); the one in
    /// use gives way first (`CompanionLibrary.replacement`). Its pictures and the made list are read again.
    func remove(companion name: String, wearing replacement: CompanionChoice?) async {
        companionError = nil
        if let replacement { parent.update { $0.choose(replacement) } }
        do {
            try await store.remove(companion: name)
        } catch {
            companionError = UserFacingError("It couldn't be removed.", detail: String(describing: error))
        }
        companions = await store.installedCompanions()
        CompanionArt.reloadMade()
        CompanionArt.forgetPictures()
        parent.services.settingsChanged()
    }

    // MARK: Extensions

    /// Downloads and checks an extension, then shows the install preview: nothing is installed until the person
    /// agrees there.
    func get(extension entry: AddonEntry) async {
        guard progress[entry.id] == nil else { return }
        failures[entry.id] = nil
        progress[entry.id] = 0
        defer { progress[entry.id] = nil }
        do {
            let folder = try await store.fetch(entry) { [weak self] p in
                Task { @MainActor in if self?.progress[entry.id] != nil { self?.progress[entry.id] = p } }
            }
            switch await parent.services.previewExtension(at: folder) {
            case .success(let preview): parent.installPreview = preview
            case .failure(let error):
                failures[entry.id] = error
                await store.discard(entry)
            }
        } catch {
            failures[entry.id] = error as? UserFacingError ?? UserFacingError("\(entry.name) couldn't be downloaded.")
        }
        catalog = await store.stored() ?? catalog
    }

    #if DEBUG
    /// A gallery to look at (UISnapshots, D77): this catalog and these companions on the Mac.
    func showSample(catalog: AddonCatalog, companions: [InstalledCompanion], progress: [String: Double] = [:]) {
        sampled = true
        self.catalog = catalog
        self.companions = companions
        self.progress = progress
    }
    #endif
}
