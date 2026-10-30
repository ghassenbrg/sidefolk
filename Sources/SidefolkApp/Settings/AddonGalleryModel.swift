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
    /// Why the last companion added from a folder (D60) wasn't, said under "Made by you" until the next try.
    private(set) var localError: UserFacingError?

    /// 3D companions added from a folder (D60).
    var locals: [InstalledCompanion] { companions.filter(\.addedFromFolder) }

    init(parent: SettingsModel) { self.parent = parent }

    var available: Bool { store.source != nil }

    /// What the gallery offers of one kind, Sidefolk's own first, then by name.
    func entries(_ kind: AddonEntry.Kind) -> [AddonEntry] {
        (catalog?.addons ?? []).filter { $0.kind == kind }.sorted { ($0.official ? 0 : 1, $0.name) < ($1.official ? 0 : 1, $1.name) }
    }

    func preview(_ entry: AddonEntry) -> URL? { catalog?.preview(for: entry) }

    /// The gallery as last checked on this Mac at once, then a fresh look (unless it is recent).
    func load(refresh: Bool = false) async {
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

    func state(_ entry: AddonEntry) -> State {
        if let p = progress[entry.id] { return .working(p) }
        guard let version = installedVersion(entry) else { return .get }
        return ExtensionVersionOrder.newer(entry.version, than: version) ? .update(from: version) : .installed
    }

    func installedVersion(_ entry: AddonEntry) -> String? {
        switch entry.kind {
        case .companion: companions.first { $0.id == entry.id }?.version
        case .extension: parent.extensions.first { $0.id == entry.id }?.version
        }
    }

    // MARK: Companions

    /// Downloads and installs a companion, then makes it the companion when `choose` (a click on its card).
    func get(companion entry: AddonEntry, choose: Bool) async {
        guard progress[entry.id] == nil, let name = entry.companion, let choice = CompanionChoice(rawValue: name) else { return }
        failures[entry.id] = nil
        progress[entry.id] = 0
        defer { progress[entry.id] = nil }
        do {
            try await store.install(companion: entry) { [weak self] p in
                Task { @MainActor in if self?.progress[entry.id] != nil { self?.progress[entry.id] = p } }
            }
            companions = await store.installedCompanions()
            CompanionArt.forgetPictures()
            if choose { parent.update { $0.choose(choice) } } else { parent.services.settingsChanged() }
        } catch {
            failures[entry.id] = error as? UserFacingError ?? UserFacingError("\(entry.name) couldn't be installed.")
        }
        // The store fetches the catalog again when a pack is newer than it.
        catalog = await store.stored() ?? catalog
    }

    /// Removes a companion; the one in use gives way to Mochi first.
    func remove(companion name: String) async {
        if parent.settings.companion.rawValue == name, parent.settings.customCompanion == nil {
            parent.update { $0.choose(.mochi) }
        }
        do {
            try await store.remove(companion: name)
        } catch {
            if let id = companions.first(where: { $0.companion == name })?.id {
                failures[id] = UserFacingError("It couldn't be removed.", detail: String(describing: error))
            }
        }
        companions = await store.installedCompanions()
        CompanionArt.forgetPictures()
        parent.services.settingsChanged()
    }

    // MARK: Added from a folder (D60)

    /// Adds the 3D companion in `folder` once the person agrees (its character file is code the 3D page runs), then
    /// makes it the companion.
    func add(companionFolder folder: URL) async {
        localError = nil
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
            localError = error as? UserFacingError ?? UserFacingError("That companion couldn't be added.", detail: String(describing: error))
        }
    }

    /// Removes a companion added from a folder; the one in use gives way to the companion chosen before it.
    func remove(local name: String) async {
        localError = nil
        if parent.settings.localCompanion == name { parent.update { $0.choose($0.companion) } }
        do {
            try await store.remove(companion: name)
        } catch {
            localError = UserFacingError("It couldn't be removed.", detail: String(describing: error))
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
}

/// Dotted versions in order, as extensions and add-ons number them.
enum ExtensionVersionOrder {
    static func newer(_ a: String, than b: String) -> Bool {
        guard let x = ReleaseVersion(a), let y = ReleaseVersion(b) else { return false }
        return x > y
    }
}
