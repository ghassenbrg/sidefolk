import Foundation
import Testing
@testable import SidefolkCore

/// 3D companions added from a folder (D60): what a folder must hold, where it lands, and how it is worn.
@Suite struct LocalCompanionsTests {
    final class Fixture {
        let root: URL
        let paths: SidefolkPaths
        let store: AddonStore

        init() throws {
            root = try ExtFixtures.tempDir("local-companions")
            paths = SidefolkPaths(home: root.appendingPathComponent("home", isDirectory: true))
            try paths.prepare()
            store = AddonStore(paths: paths, source: nil)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A companion's folder as its maker leaves it: `addon.json` and the four files, real enough to be checked.
        func folder(_ name: String, manifest: [String: Any]? = nil, files: [String: Data]? = nil) throws -> URL {
            let dir = root.appendingPathComponent("made-\(UUID().uuidString)/\(name)", isDirectory: true)
            let all = files ?? [
                "characters/\(name).js": Data("export default {}".utf8),
                "assets/\(name).glb": Data("glTF\u{2}\0\0\0".utf8),
                "portraits/\(name).png": Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
                "avatars/\(name).png": Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            ]
            for (path, data) in all {
                let url = dir.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
            let json = manifest ?? ["kind": "companion", "name": name.capitalized, "companion": name, "tagline": "Me, as a companion",
                                    "author": "Me", "version": "1.0.0", "engine": 1]
            try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("addon.json"))
            return dir
        }

        var companions: URL { paths.addons.appendingPathComponent("Companions", isDirectory: true) }
    }

    @Test func aFolderIsAddedBesideTheGallerysMarkedAsItsMakers() async throws {
        let f = try Fixture()
        let folder = try f.folder("ghassen")
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        let added = try await f.store.install(companionFolder: folder)
        #expect(added.name == "Ghassen" && added.companion == "ghassen" && added.tagline == "Me, as a companion")
        #expect(added.addedFromFolder && added.body == nil && added.id == "local.ghassen")
        let listed = await f.store.installedCompanions()
        #expect(listed == [added])
        let here = f.companions.appendingPathComponent("ghassen")
        for path in ["characters/ghassen.js", "assets/ghassen.glb", "portraits/ghassen.png", "avatars/ghassen.png", "addon.json"] {
            #expect(FileManager.default.fileExists(atPath: here.appendingPathComponent(path).path), "\(path)")
        }
        #expect(!FileManager.default.fileExists(atPath: here.appendingPathComponent(".DS_Store").path))
    }

    @Test func addingItAgainReplacesIt() async throws {
        let f = try Fixture()
        try await f.store.install(companionFolder: try f.folder("kana"))
        let newer = try f.folder("kana", manifest: ["name": "Kana", "companion": "kana", "version": "1.1.0", "body": "floating"])
        let added = try await f.store.install(companionFolder: newer)
        #expect(added.version == "1.1.0" && added.body == .floating)
        #expect(await f.store.installedCompanions().map(\.version) == ["1.1.0"])
    }

    @Test func aFolderMustHoldExactlyTheFourFiles() throws {
        let f = try Fixture()
        var files: [String: Data] = ["characters/kana.js": Data("x".utf8), "assets/kana.glb": Data("glTF".utf8),
                                     "portraits/kana.png": Data([0x89, 0x50, 0x4E, 0x47])]
        #expect(throws: UserFacingError.self) { try AddonStore.readLocalCompanion(try f.folder("kana", files: files)) }
        files["avatars/kana.png"] = Data([0x89, 0x50, 0x4E, 0x47])
        files["notes.txt"] = Data("hi".utf8)
        #expect(throws: UserFacingError.self) { try AddonStore.readLocalCompanion(try f.folder("kana", files: files)) }
        files["notes.txt"] = nil
        files["assets/kana.glb"] = Data("PK\u{3}\u{4}".utf8)   // a zip named .glb
        #expect(throws: UserFacingError.self) { try AddonStore.readLocalCompanion(try f.folder("kana", files: files)) }
    }

    @Test func itsManifestIsChecked() throws {
        let f = try Fixture()
        func reads(_ manifest: [String: Any], name: String = "kana") throws -> InstalledCompanion {
            try AddonStore.readLocalCompanion(try f.folder(name, manifest: manifest))
        }
        // One of Sidefolk's own, or one from the gallery, keeps its name.
        #expect(throws: UserFacingError.self) { try reads(["name": "Kiko", "companion": "kiko"], name: "kiko") }
        #expect(throws: UserFacingError.self) { try reads(["name": "Kana", "companion": "Kana"]) }
        #expect(throws: UserFacingError.self) { try reads(["name": " ", "companion": "kana"]) }
        #expect(throws: UserFacingError.self) { try reads(["name": "Kana", "companion": "kana", "engine": AddonCatalog.engine + 1]) }
        #expect(throws: UserFacingError.self) { try reads(["name": "Kana", "companion": "kana", "body": "tentacles"]) }
        #expect(throws: UserFacingError.self) { try reads(["kind": "extension", "name": "Kana", "companion": "kana"]) }
        let plain = try reads(["name": "Kana", "companion": "kana"])
        #expect(plain.version == "1.0.0" && plain.author == "" && plain.tagline == nil)
        #expect(throws: UserFacingError.self) {
            try AddonStore.readLocalCompanion(f.root.appendingPathComponent("nothing-here", isDirectory: true))
        }
    }

    @Test func aGalleryCompanionUnderTheSameNameStays() async throws {
        let f = try Fixture()
        // As the gallery leaves one this copy doesn't know yet: no mark of a folder.
        let there = f.companions.appendingPathComponent("nori", isDirectory: true)
        try FileManager.default.createDirectory(at: there, withIntermediateDirectories: true)
        let gallery = InstalledCompanion(id: "dev.sidefolk.companions.nori", name: "Nori", companion: "nori", version: "1.0.0", author: "Sidefolk")
        try JSONEncoder().encode(gallery).write(to: there.appendingPathComponent("addon.json"))
        await #expect(throws: UserFacingError.self) { try await f.store.install(companionFolder: try f.folder("nori")) }
        #expect(await f.store.installedCompanions() == [gallery])
    }

    @Test func wearingOneAndGoingBack() throws {
        var s = AppSettings()
        s.choose(.spark)
        s.choose(local: "ghassen", name: "Ghassen")
        #expect(s.localCompanion == "ghassen" && s.companionName == "Ghassen" && s.companion == .spark)
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(round.localCompanion == "ghassen")
        // Its name gives way like a built-in's when another is chosen.
        s.choose(s.companion)
        #expect(s.localCompanion == nil && s.companionName == "Spark")
        s.choose(local: "kana", name: "Kana")
        s.choose(custom: "blob", name: "Blob")
        #expect(s.localCompanion == nil && s.customCompanion == "blob")
        s.choose(local: "kana", name: "Kana")
        #expect(s.customCompanion == nil && s.localCompanion == "kana")
        // A name the person gave stays.
        s.companionName = "Little me"
        s.choose(local: "ghassen", name: "Ghassen")
        #expect(s.companionName == "Little me")
    }

    /// The four files and a 2D form beside them (D85).
    func withTwoD(_ name: String, _ extra: [String: Data]) -> [String: Data] {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var files: [String: Data] = [
            "characters/\(name).js": Data("export default {}".utf8), "assets/\(name).glb": Data("glTF\u{2}\0\0\0".utf8),
            "portraits/\(name).png": png, "avatars/\(name).png": png,
            "2d/species.json": Data("{}".utf8), "2d/parts/ear.svg": Data("<svg/>".utf8), "2d/paint/head.png": png,
        ]
        files.merge(extra) { $1 }
        return files
    }

    @Test func aTwoDFormComesAlongAndIsCheckedByName() async throws {
        let f = try Fixture()
        let added = try await f.store.install(companionFolder: try f.folder("otter", files: withTwoD("otter", [:])))
        #expect(added.twoD == true)
        let here = f.companions.appendingPathComponent("otter/2d")
        for path in ["species.json", "parts/ear.svg", "paint/head.png"] {
            #expect(FileManager.default.fileExists(atPath: here.appendingPathComponent(path).path), "\(path)")
        }
        #expect(try AddonStore.readLocalCompanion(f.folder("plain")).twoD == nil)
        let refused: [String: [String: Data]] = [
            "2d/notes.txt": ["2d/notes.txt": Data("hi".utf8)],
            "no species.json": ["2d/species.json": Data()].mapValues { _ in Data() },
            "a link-like name": ["2d/paint/../x.png": Data([0x89, 0x50, 0x4E, 0x47])],
            "a PNG that isn't": ["2d/paint/torso.png": Data("nope".utf8)],
            "too large": ["2d/paint/torso.png": Data([0x89, 0x50, 0x4E, 0x47]) + Data(count: 4 * 1024 * 1024)],
            "a folder of its own": ["2d/more/x.svg": Data("<svg/>".utf8)],
        ]
        for (why, extra) in refused {
            var files = withTwoD("otter", extra)
            if why == "no species.json" { files["2d/species.json"] = nil }
            #expect(throws: UserFacingError.self, "\(why)") { try AddonStore.readLocalCompanion(f.folder("otter", files: files)) }
        }
        let many = Dictionary(uniqueKeysWithValues: (0..<9).map { ("2d/paint/p\($0).png", Data([0x89, 0x50, 0x4E, 0x47])) })
        #expect(throws: UserFacingError.self) { try AddonStore.readLocalCompanion(f.folder("otter", files: withTwoD("otter", many))) }
    }

    @Test func itsLookIsKeptApartFromEveryBuiltIns() throws {
        var s = AppSettings()
        #expect(s.dimension(forLocal: "otter") == .threeD)
        s.setDimension(.twoD, forLocal: "otter")
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(round.dimension(forLocal: "otter") == .twoD && round.dimension(forLocal: "kana") == .threeD)
        #expect(round.dimension(for: .spark) == AppSettings().dimension(for: .spark))
        let folder = URL(fileURLWithPath: "/tmp/companions")
        let otter = InstalledCompanion(id: "local.otter", name: "Otter", companion: "otter", version: "1.0.0", author: "", fromFolder: true,
                                       twoD: true)
        var plain = otter
        plain.companion = "plain"
        plain.twoD = nil
        let owned = CompanionLibrary.owned(builtIn: [], installed: [otter, plain], made: [], folder: folder) { _ in "" }
        #expect(owned.map(\.looks) == [[.threeD, .twoD], [.threeD]])
    }
}
