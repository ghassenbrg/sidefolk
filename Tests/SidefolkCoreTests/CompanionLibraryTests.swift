import Foundation
import Testing
@testable import SidefolkCore

/// Settings › Companion's chooser (D77): every source in one list, what each companion's menu
/// offers, who takes the place of one removed while worn, and the gallery's search, filters and order.
@Suite struct CompanionLibraryTests {
    static let folder = URL(fileURLWithPath: "/tmp/Addons/Companions", isDirectory: true)

    static func installed(_ name: String, id: String? = nil, version: String = "1.0.0", fromFolder: Bool = false,
                          tagline: String? = nil) -> InstalledCompanion {
        InstalledCompanion(id: id ?? "dev.sidefolk.companions.\(name)", name: name.capitalized, companion: name, version: version,
                           author: fromFolder ? "" : "Sidefolk", tagline: tagline, fromFolder: fromFolder ? true : nil)
    }

    static let made = CompanionLibrary.Made(id: "miso", name: "Miso", summary: "A little cat", folder: URL(fileURLWithPath: "/tmp/companions/miso"),
                                            fromExtension: false)

    static func list(installed: [InstalledCompanion] = [], made: [CompanionLibrary.Made] = []) -> [OwnedCompanion] {
        CompanionLibrary.owned(builtIn: [.mochi, .spark], installed: installed, made: made, folder: folder, role: { "role of \($0.rawValue)" })
    }

    // MARK: One list

    @Test func everySourceIsInOneListBuiltInsFirstThenByName() {
        let owned = Self.list(installed: [Self.installed("nimbo"), Self.installed("cumulus", id: "local.cumulus", fromFolder: true, tagline: "Mine"),
                                          Self.installed("pebble", id: "io.github.lena.pebble", tagline: "A shy stone"), Self.installed("ember")],
                              made: [Self.made])
        #expect(owned.map(\.name) == ["Mochi", "Spark", "Cumulus", "Ember", "Miso", "Nimbo", "Pebble"])
        #expect(owned.map(\.origin) == [.builtIn, .builtIn, .folder, .gallery, .made, .gallery, .gallery])
        let byName = Dictionary(uniqueKeysWithValues: owned.map { ($0.name, $0) })
        #expect(byName["Ember"]?.wear == .choice(.ember) && byName["Ember"]?.looks == [.threeD, .twoD])
        #expect(byName["Ember"]?.tagline == "role of ember" && byName["Ember"]?.galleryID == "dev.sidefolk.companions.ember")
        // One the gallery brought that this copy has no case for is worn by its folder's name, in 3D.
        #expect(byName["Pebble"]?.wear == .local("pebble") && byName["Pebble"]?.looks == [.threeD])
        #expect(byName["Pebble"]?.tagline == "A shy stone" && byName["Pebble"]?.folder == nil)
        #expect(byName["Cumulus"]?.wear == .local("cumulus") && byName["Cumulus"]?.folder?.path == Self.folder.appendingPathComponent("cumulus").path)
        #expect(byName["Miso"]?.wear == .custom("miso") && byName["Miso"]?.looks == [.twoD])
        #expect(byName["Mochi"]?.character == nil && byName["Ember"]?.character == "ember" && byName["Cumulus"]?.character == "cumulus")
    }

    @Test func retiredCharactersAndBuiltInsFromTheGalleryAreLeftOut() {
        let owned = Self.list(installed: [Self.installed("pip"), Self.installed("sidefolk"), Self.installed("spark")])
        #expect(owned.map(\.name) == ["Mochi", "Spark"])
        #expect(owned.allSatisfy { $0.origin == .builtIn })
    }

    @Test func theWornOneIsFoundWhereverItCameFrom() {
        let owned = Self.list(installed: [Self.installed("ember"), Self.installed("cumulus", fromFolder: true)], made: [Self.made])
        var s = AppSettings()
        #expect(CompanionLibrary.worn(s, in: owned) == .choice(.mochi))
        s.choose(.ember)
        #expect(CompanionLibrary.worn(s, in: owned) == .choice(.ember))
        s.choose(local: "cumulus", name: "Cumulus")
        #expect(CompanionLibrary.worn(s, in: owned) == .local("cumulus"))
        s.choose(custom: "miso", name: "Miso")
        #expect(CompanionLibrary.worn(s, in: owned) == .custom("miso"))
        // Chosen but not here (yet): Mochi stands in, as on the desktop.
        s.choose(.kiko)
        #expect(CompanionLibrary.worn(s, in: owned) == .choice(.mochi))
        s.choose(local: "gone", name: "Gone")
        #expect(CompanionLibrary.worn(s, in: owned) == .choice(.mochi))
    }

    // MARK: What each menu offers

    @Test func eachCompanionsMenuSaysWhatAppliesAndWhyRemoveIsMissing() {
        let owned = Self.list(installed: [Self.installed("ember"), Self.installed("cumulus", fromFolder: true)], made: [Self.made])
        func one(_ name: String) -> OwnedCompanion { owned.first { $0.name == name }! }
        #expect(CompanionLibrary.actions(for: one("Mochi"), worn: true) == [.keep(.builtIn)])
        #expect(CompanionLibrary.actions(for: one("Spark"), worn: false) == [.wear, .keep(.builtIn)])
        #expect(CompanionLibrary.actions(for: one("Ember"), worn: false, update: "1.1.0", downloadable: true)
                == [.wear, .update(version: "1.1.0"), .remove(.download(again: true))])
        #expect(CompanionLibrary.actions(for: one("Ember"), worn: true) == [.remove(.download(again: false))])
        #expect(CompanionLibrary.actions(for: one("Cumulus"), worn: false) == [.wear, .showInFinder, .remove(.copy)])
        // An update is offered only for what the gallery brought.
        #expect(CompanionLibrary.actions(for: one("Cumulus"), worn: true, update: "9.0.0") == [.showInFinder, .remove(.copy)])
        #expect(CompanionLibrary.actions(for: one("Miso"), worn: false) == [.wear, .showInFinder, .remove(.trash)])
        var fromExtension = Self.made
        fromExtension.fromExtension = true
        let brought = Self.list(made: [fromExtension]).first { $0.origin == .made }!
        #expect(CompanionLibrary.actions(for: brought, worn: false) == [.wear, .showInFinder, .keep(.fromExtension)])
    }

    @Test func removingTheWornOneWearsMochiOrTheOneChosenBefore() {
        let owned = Self.list(installed: [Self.installed("ember"), Self.installed("cumulus", fromFolder: true)], made: [Self.made])
        func one(_ name: String) -> OwnedCompanion { owned.first { $0.name == name }! }
        var s = AppSettings()
        s.choose(.ember)
        #expect(CompanionLibrary.replacement(removing: one("Ember"), in: s, owned: owned) == .mochi)
        #expect(CompanionLibrary.replacement(removing: one("Cumulus"), in: s, owned: owned) == nil)   // not worn
        s.choose(.spark)
        s.choose(local: "cumulus", name: "Cumulus")
        #expect(CompanionLibrary.replacement(removing: one("Cumulus"), in: s, owned: owned) == .spark)
        s.choose(custom: "miso", name: "Miso")
        #expect(CompanionLibrary.replacement(removing: one("Miso"), in: s, owned: owned) == .spark)
        // The one chosen before is itself gone: Mochi.
        var t = AppSettings()
        t.choose(.kiko)
        t.choose(custom: "miso", name: "Miso")
        #expect(CompanionLibrary.replacement(removing: one("Miso"), in: t, owned: owned) == .mochi)
    }

    // MARK: The gallery

    static func entry(_ name: String, author: String = "Sidefolk", official: Bool = true, tagline: String = "", bytes: Int64 = 1000,
                      published: String? = nil, kind: String = "companion") -> AddonEntry {
        var json: [String: Any] = ["id": official ? "dev.sidefolk.companions.\(name)" : "io.github.someone.\(name)", "kind": kind,
                                   "name": name.capitalized, "tagline": tagline, "description": "", "author": author, "version": "1.0.0",
                                   "file": "\(name).zip", "bytes": bytes, "sha256": String(repeating: "0", count: 64)]
        if kind == "companion" { json["companion"] = name; json["engine"] = 1 }
        if let published { json["published"] = published }
        return try! JSONDecoder().decode(AddonEntry.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static let gallery = [
        entry("nori", tagline: "A bookish little cat", bytes: 3000, published: "2026-10-20"),
        entry("ember", tagline: "A curious little fox", bytes: 2000, published: "2026-10-01"),
        entry("cosmo", author: "Aiko M.", official: false, tagline: "A cat astronaut", bytes: 500, published: "2026-10-28"),
        entry("pebble", author: "Lena K.", official: false, tagline: "A shy river stone", bytes: 1500),
        entry("pip", tagline: "A retired folk"),
        entry("git", kind: "extension"),
    ]

    @Test func onlyCompanionsThisCopyCanWearAreListedByName() {
        let found = CompanionBrowse().apply(Self.gallery, owned: [])
        #expect(found.map(\.name) == ["Cosmo", "Ember", "Nori", "Pebble"])
        #expect(Self.gallery[0].looks == [.threeD, .twoD] && Self.gallery[2].looks == [.threeD])
    }

    @Test func wordsLooksMakersAndOwnedNarrowTheList() {
        let names = { (b: CompanionBrowse, owned: Set<String>) in b.apply(Self.gallery, owned: owned).map(\.name) }
        #expect(names(CompanionBrowse(text: "CAT"), []) == ["Cosmo", "Nori"])
        #expect(names(CompanionBrowse(text: "cat", look: .twoD), []) == ["Nori"])
        #expect(names(CompanionBrowse(look: .threeD), []) == ["Cosmo", "Ember", "Nori", "Pebble"])
        #expect(names(CompanionBrowse(maker: .others), []) == ["Cosmo", "Pebble"])
        #expect(names(CompanionBrowse(maker: .sidefolk), []) == ["Ember", "Nori"])
        #expect(names(CompanionBrowse(text: "lena"), []) == ["Pebble"])
        // Words in the person's language, as Settings passes them for Sidefolk's own.
        let local = CompanionBrowse(text: "renard").apply(Self.gallery, owned: []) { $0.companion == "ember" ? ["Un petit renard curieux"] : [] }
        #expect(local.map(\.name) == ["Ember"])
        #expect(names(CompanionBrowse(hideOwned: true), ["ember", "pebble"]) == ["Cosmo", "Nori"])
        #expect(!CompanionBrowse(sort: .smallest).isNarrowed && CompanionBrowse(hideOwned: true).isNarrowed)
    }

    @Test func ordersAreOfferedOnlyWhenTheCatalogHasWhatTheyNeed() {
        #expect(CompanionBrowse(sort: .newest).apply(Self.gallery, owned: []).map(\.name) == ["Cosmo", "Nori", "Ember", "Pebble"])
        #expect(CompanionBrowse(sort: .smallest).apply(Self.gallery, owned: []).map(\.name) == ["Cosmo", "Pebble", "Ember", "Nori"])
        #expect(CompanionBrowse.sorts(for: Self.gallery) == [.name, .newest, .smallest])
        #expect(CompanionBrowse.sorts(for: [Self.gallery[3]]) == [.name, .smallest])
        #expect(CompanionBrowse.offersMakers(Self.gallery) && !CompanionBrowse.offersMakers([Self.gallery[0], Self.gallery[1]]))
        #expect(CompanionBrowse.offersLooks(Self.gallery) && !CompanionBrowse.offersLooks([Self.gallery[2], Self.gallery[3]]))
    }

    @Test func aBadPublishedDateOrBodyDropsTheEntry() throws {
        func item(_ change: (inout [String: Any]) -> Void) -> [String: Any] {
            var e: [String: Any] = ["id": "io.github.someone.pebble", "kind": "companion", "name": "Pebble", "tagline": "", "description": "",
                                    "author": "Lena", "version": "1.0.0", "file": "p.zip", "bytes": 10, "sha256": String(repeating: "a", count: 64),
                                    "companion": "pebble", "engine": 1]
            change(&e)
            return e
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": 1, "addons": [
            item { $0["published"] = "2026-10-30"; $0["body"] = "floating" },
            item { $0["id"] = "io.github.someone.b"; $0["published"] = "yesterday" },
            item { $0["id"] = "io.github.someone.c"; $0["body"] = "tentacles" },
        ]])
        let catalog = try AddonCatalog.parse(data, folder: URL(fileURLWithPath: "/tmp"), fetched: Date())
        #expect(catalog.addons.map(\.id) == ["io.github.someone.pebble"])
        #expect(catalog.addons.first?.published == "2026-10-30" && catalog.addons.first?.body == .floating)
    }
}
