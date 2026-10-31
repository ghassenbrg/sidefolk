import Foundation

/// One companion the person can wear now, wherever it came from (D?? companion chooser): Sidefolk's own, one the
/// gallery downloaded, one made from data (D43) or a 3D one added from a folder (D60). Settings › Companion shows
/// them in one grid, each with where it came from, so the person's own sit beside the others instead of in a
/// separate list.
public struct OwnedCompanion: Identifiable, Hashable, Sendable {
    public enum Origin: String, Hashable, Sendable {
        case builtIn, gallery, made, folder
    }

    /// How the settings wear it: a companion this copy knows, one made from data, or one worn by the name of its
    /// folder in `Addons/Companions` (added from a folder, or a gallery companion this copy has no case for).
    public enum Wear: Hashable, Sendable {
        case choice(CompanionChoice)
        case custom(String)
        case local(String)
    }

    public var wear: Wear
    public var name: String
    public var tagline: String
    public var origin: Origin
    /// The looks it comes in, the one it comes in first (D51, D59).
    public var looks: [CompanionDimension]
    /// Its gallery id and version, when the gallery brought it.
    public var galleryID: String?
    public var version: String?
    public var author: String?
    /// Where its files are, for Show in Finder: a companion made from data, or one added from a folder.
    public var folder: URL?
    /// Made from data an installed extension brought: it goes when the extension does.
    public var fromExtension = false

    public var id: String {
        switch wear {
        case .choice(let choice): "choice:\(choice.rawValue)"
        case .custom(let id): "custom:\(id)"
        case .local(let name): "local:\(name)"
        }
    }

    /// The name of its folder of 3D files, when it has one: a gallery companion's or one added from a folder.
    public var character: String? {
        switch wear {
        case .choice(let choice): origin == .gallery ? choice.rawValue : nil
        case .local(let name): name
        case .custom: nil
        }
    }

    public init(wear: Wear, name: String, tagline: String, origin: Origin, looks: [CompanionDimension],
                galleryID: String? = nil, version: String? = nil, author: String? = nil, folder: URL? = nil,
                fromExtension: Bool = false) {
        self.wear = wear
        self.name = name
        self.tagline = tagline
        self.origin = origin
        self.looks = looks
        self.galleryID = galleryID
        self.version = version
        self.author = author
        self.folder = folder
        self.fromExtension = fromExtension
    }
}

/// What can be done with one companion, each said in its "…" menu and its context menu: nothing is reached by a
/// hidden gesture.
public enum CompanionAction: Hashable, Sendable {
    case wear
    /// The gallery has a newer version, and add-ons don't update by themselves (D70).
    case update(version: String)
    case showInFinder
    case remove(CompanionRemoval)
    /// Why Remove isn't offered, said where Remove would be.
    case keep(CompanionKeep)
}

/// What removing takes away, which the confirmation says.
public enum CompanionRemoval: Hashable, Sendable {
    /// A gallery download: its files go; `again` when the gallery still has it to download again.
    case download(again: Bool)
    /// The copy Sidefolk made of a folder (D60): the person's folder stays where it is.
    case copy
    /// A companion made from data in Sidefolk's companions folder: its folder goes to the Trash, to put back from there.
    case trash
}

public enum CompanionKeep: Hashable, Sendable {
    /// Sidefolk's own: part of the app.
    case builtIn
    /// Made from data an extension brought: remove the extension instead.
    case fromExtension
}

/// The person's companions as one list, and what applies to each.
public enum CompanionLibrary {
    /// A companion made from data (D43), as Settings reads it from the companions folder or an extension.
    public struct Made: Sendable {
        public var id: String
        public var name: String
        public var summary: String?
        public var folder: URL
        public var fromExtension: Bool

        public init(id: String, name: String, summary: String?, folder: URL, fromExtension: Bool) {
            self.id = id
            self.name = name
            self.summary = summary
            self.folder = folder
            self.fromExtension = fromExtension
        }
    }

    /// Everyone the person can wear: Sidefolk's own first (`builtIn`, in its order), then everything else by name.
    /// `installed` are the companions in `Addons/Companions` whose files are all there (`folder` is that folder);
    /// a gallery companion named after one of Sidefolk's retired characters is left out, as it can't be worn.
    public static func owned(builtIn: [CompanionChoice], installed: [InstalledCompanion], made: [Made], folder: URL,
                             role: (CompanionChoice) -> String) -> [OwnedCompanion] {
        let own = builtIn.filter { !$0.isRetired }.map { choice in
            OwnedCompanion(wear: .choice(choice), name: choice.defaultName, tagline: role(choice), origin: .builtIn,
                           looks: choice.dimensions)
        }
        let added = installed.compactMap { have -> OwnedCompanion? in
            let files = folder.appendingPathComponent(have.companion, isDirectory: true)
            if have.addedFromFolder {
                return OwnedCompanion(wear: .local(have.companion), name: have.name, tagline: have.tagline ?? "", origin: .folder,
                                      looks: [.threeD], version: have.version, author: have.author.isEmpty ? nil : have.author,
                                      folder: files)
            }
            if let choice = CompanionChoice(rawValue: have.companion) {
                guard !choice.isRetired, !builtIn.contains(choice) else { return nil }
                return OwnedCompanion(wear: .choice(choice), name: choice.defaultName, tagline: role(choice), origin: .gallery,
                                      looks: choice.dimensions, galleryID: have.id, version: have.version, author: have.author)
            }
            return OwnedCompanion(wear: .local(have.companion), name: have.name, tagline: have.tagline ?? "", origin: .gallery,
                                  looks: [.threeD], galleryID: have.id, version: have.version, author: have.author)
        }
        let drawn = made.map { m in
            OwnedCompanion(wear: .custom(m.id), name: m.name, tagline: m.summary ?? "", origin: .made, looks: [.twoD],
                           folder: m.folder, fromExtension: m.fromExtension)
        }
        return own + (added + drawn).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The one the settings wear, as listed in `owned`; Mochi when what they name isn't here (yet).
    public static func worn(_ settings: AppSettings, in owned: [OwnedCompanion]) -> OwnedCompanion.Wear {
        let candidates: [OwnedCompanion.Wear] = [settings.localCompanion.map { .local($0) }, settings.customCompanion.map { .custom($0) },
                                                 .choice(settings.companion)].compactMap { $0 }
        return candidates.first { wear in owned.contains { $0.wear == wear } } ?? .choice(.mochi)
    }

    /// What applies to `companion`, in the order its menu lists them. `update` is the gallery's newer version while
    /// add-ons wait to be updated by hand; `downloadable` whether the gallery (on the person's channel) still has it.
    public static func actions(for companion: OwnedCompanion, worn: Bool, update: String? = nil,
                               downloadable: Bool = false) -> [CompanionAction] {
        var actions: [CompanionAction] = worn ? [] : [.wear]
        if let update, companion.origin == .gallery { actions.append(.update(version: update)) }
        if companion.folder != nil { actions.append(.showInFinder) }
        switch companion.origin {
        case .builtIn: actions.append(.keep(.builtIn))
        case .gallery: actions.append(.remove(.download(again: downloadable)))
        case .folder: actions.append(.remove(.copy))
        case .made: actions.append(companion.fromExtension ? .keep(.fromExtension) : .remove(.trash))
        }
        return actions
    }

    /// Whom to wear instead when `companion` is removed while worn: one of Sidefolk's companions in place of a gallery
    /// one Sidefolk knows (Mochi), the companion chosen before it otherwise (D60). Nil when it isn't worn.
    public static func replacement(removing companion: OwnedCompanion, in settings: AppSettings,
                                   owned: [OwnedCompanion]) -> CompanionChoice? {
        guard worn(settings, in: owned) == companion.wear else { return nil }
        switch companion.wear {
        case .choice: return .mochi
        case .custom, .local:
            let before = settings.companion
            return owned.contains { $0.wear == .choice(before) } ? before : .mochi
        }
    }
}
