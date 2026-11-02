import Foundation
import Testing
@testable import SidefolkCore

/// A fresh Mac's first extensions (D98): installed once from packs the app carries, checked as a download is, then the
/// gallery's. Removing one is remembered and an app update touches nothing.
@Suite(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
struct SeedPacksTests {
    /// What the app carries, as scripts/seed-packs.py lays it out, with packs made on the spot.
    final class Carried {
        let env: HostEnv
        let gallery: AddonStoreTests.Gallery
        let store: AddonStore
        let folder: URL
        var seeds: [[String: Any]] = []

        init(checker: CodeChecking = AddonStoreTests.Trusting()) throws {
            env = try HostEnv()
            gallery = try AddonStoreTests.Gallery()
            folder = gallery.site
            store = AddonStore(paths: env.paths, source: AddonSource(base: gallery.site, team: AddonStoreTests.team), checker: checker)
        }

        func carry(_ name: String, id: String, version: String = "1.0.0", on: Bool = true) throws {
            let manifest = ExtFixtures.manifest(id: id).setting("version", .string(version)).setting("name", .string(name))
            let pack = try gallery.pack(name, id: id, version: version, files: [ExtensionManifest.fileName: manifest.jsonString, "server.py": ExtFixtures.server])
            seeds.append(["id": id, "name": name, "version": version, "file": pack.file, "bytes": pack.bytes, "sha256": pack.sha, "on": on])
            try JSONSerialization.data(withJSONObject: ["seeds": seeds]).write(to: folder.appendingPathComponent(SeedPacks.listFile))
        }

        var packs: SeedPacks { SeedPacks(directory: folder, paths: env.paths) }
    }

    @Test func aFreshMacInstallsEachOnceOnOrOffAsTheListSays() async throws {
        let c = try Carried()
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        try c.carry("beta", id: "dev.sidefolk.beta", on: false)
        await c.packs.install(into: c.env.host, store: c.store)
        let alpha = try #require(await c.env.host.info(id: "dev.sidefolk.alpha"))
        let beta = try #require(await c.env.host.info(id: "dev.sidefolk.beta"))
        #expect(alpha.origin == .official && alpha.enabled)
        #expect(beta.origin == .official && !beta.enabled)
        #expect(c.env.env.registry.tool(named: "ext.alpha.echo") != nil)
        #expect(c.env.env.registry.tool(named: "ext.beta.echo") == nil)
        // The pack's unpacked copy doesn't stay behind.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: c.env.paths.addons.appendingPathComponent("Downloads/dev.sidefolk.alpha").path))
        await c.env.host.shutdown()
    }

    @Test func removingOneIsRememberedAndAnAppUpdateTouchesNothing() async throws {
        let c = try Carried()
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        try c.carry("beta", id: "dev.sidefolk.beta")
        await c.packs.install(into: c.env.host, store: c.store)
        try await c.env.host.setEnabled(false, id: "dev.sidefolk.beta")
        try await c.env.host.uninstall(id: "dev.sidefolk.alpha")

        // The next app carries newer packs and one more seed.
        c.seeds = []
        try c.carry("alpha", id: "dev.sidefolk.alpha", version: "2.0.0")
        try c.carry("beta", id: "dev.sidefolk.beta", version: "2.0.0")
        try c.carry("gamma", id: "dev.sidefolk.gamma")
        await c.packs.install(into: c.env.host, store: c.store)

        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") == nil, "what the person removed stays gone")
        let beta = try #require(await c.env.host.info(id: "dev.sidefolk.beta"))
        #expect(beta.version == "1.0.0" && !beta.enabled, "only the gallery updates it, and the switch is the person's")
        #expect(await c.env.host.info(id: "dev.sidefolk.gamma") == nil, "a Mac that has had its seeds gets none from an update")
        await c.env.host.shutdown()
    }

    /// A copy the app shipped before D98 is stored with origin `bundled`: it reads as the gallery's, keeps its data and its
    /// switch, can be removed, and isn't replaced by the pack.
    @Test func aCopyTheAppUsedToShipBecomesTheGallerysWithItsDataAndSwitch() async throws {
        let c = try Carried()
        let host = c.env.host
        let folder = try ExtFixtures.tempDir("old-builtin")
        try ExtFixtures.makeExtension(at: folder.appendingPathComponent("alpha"), manifest: ExtFixtures.manifest(id: "dev.sidefolk.alpha"),
                                      files: ["server.py": ExtFixtures.server])
        try await host.install(from: folder.appendingPathComponent("alpha"), origin: .official, enabled: false)
        let data = c.env.paths.extensionData.appendingPathComponent("dev.sidefolk.alpha")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: data.appendingPathComponent("notes.txt"))
        await host.shutdown()
        // As an older copy wrote it.
        var record = try #require(try await c.env.store.all().first { $0.id == "dev.sidefolk.alpha" })
        let granted = try #require(record.granted).jsonString.replacingOccurrences(of: #""origin":"official""#, with: #""origin":"bundled""#)
        record.granted = try JSONValue.parse(granted)
        #expect(record.granted?.string("origin") == "bundled")
        try await c.env.store.save(record)

        let next = ExtensionHost(paths: c.env.paths, store: c.env.store, registry: c.env.env.registry, events: c.env.env.events)
        await next.start()
        try c.carry("alpha", id: "dev.sidefolk.alpha", version: "9.0.0")
        await c.packs.install(into: next, store: c.store)
        let kept = try #require(await next.info(id: "dev.sidefolk.alpha"))
        #expect(kept.origin == .official && !kept.enabled && kept.version == "1.0.0")
        #expect(FileManager.default.contents(atPath: data.appendingPathComponent("notes.txt").path) == Data("mine".utf8))
        try await next.uninstall(id: "dev.sidefolk.alpha")
        await next.shutdown()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Only what the signed app lists goes in: a pack that isn't the one on the list, or whose signature fails, isn't
    /// installed, says why in Settings, and is tried again.
    @Test func aPackThatDoesntCheckOutIsRefusedAndTriedAgain() async throws {
        let c = try Carried()
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        let zip = c.folder.appendingPathComponent(c.seeds[0]["file"] as! String)
        let good = try Data(contentsOf: zip)
        try Data("swapped".utf8).write(to: zip)
        let packs = c.packs
        await packs.install(into: c.env.host, store: c.store)
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") == nil)
        #expect(packs.unavailable.map(\.id) == ["dev.sidefolk.alpha"])

        try good.write(to: zip)
        await packs.install(into: c.env.host, store: c.store)
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") != nil)
        #expect(packs.unavailable.isEmpty)
        await c.env.host.shutdown()
    }

    @Test func theRealSignatureCheckRefusesAnUnsignedPack() async throws {
        let c = try Carried(checker: AddonCodeCheck())
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        let packs = c.packs
        await packs.install(into: c.env.host, store: c.store)
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") == nil)
        #expect(packs.unavailable.count == 1)
        await c.env.host.shutdown()
    }

    /// A debug build that fetched nothing has the repository's list, which names no packs: nothing is decided yet, so a
    /// later build with packs still counts as a fresh Mac's.
    @Test func aBuildWithoutPacksDecidesNothing() async throws {
        let c = try Carried()
        let list = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/SeedPacks", isDirectory: true)
        let repository = SeedPacks(directory: list, paths: c.env.paths)
        #expect(repository.seeds().isEmpty)
        await repository.install(into: c.env.host, store: c.store)
        #expect(!FileManager.default.fileExists(atPath: c.env.paths.addons.appendingPathComponent(SeedPacks.ledgerFile).path))

        try c.carry("alpha", id: "dev.sidefolk.alpha")
        await c.packs.install(into: c.env.host, store: c.store)
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") != nil)
        await c.env.host.shutdown()
    }

    /// After a restore only what the backup had comes back (D91): one removed there stays gone.
    @Test func aRestoreBringsBackOnlyWhatTheBackupHad() async throws {
        let c = try Carried()
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        try c.carry("beta", id: "dev.sidefolk.beta")
        SeedPacks.restored(["dev.sidefolk.beta"], paths: c.env.paths)
        await c.packs.install(into: c.env.host, store: c.store)
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha") == nil)
        #expect(await c.env.host.info(id: "dev.sidefolk.beta") != nil)
        await c.env.host.shutdown()
    }

    /// After the relaunch each seed gets its switch back, in a backup from before D98 too, and doesn't wait for the gallery.
    @Test func aRestoresFollowUpSwitchesSeedsAndLeavesTheGalleryOut() async throws {
        let c = try Carried()
        try c.carry("alpha", id: "dev.sidefolk.alpha")
        try c.carry("beta", id: "dev.sidefolk.beta", on: false)
        let packs = c.packs
        await packs.install(into: c.env.host, store: c.store)
        let plan = BackupRestore.Plan(backupCreated: Date(), app: "x", device: nil, extensions: [
            .init(id: "dev.sidefolk.alpha", name: "alpha", version: "1.0.0", enabled: false, source: .gallery),
            .init(id: "dev.sidefolk.beta", name: "beta", version: "1.0.0", enabled: true, source: .builtIn),
        ], addons: [])
        let report = await RestoreFollowUp(paths: c.env.paths, seedWait: 1)
            .run(plan, store: c.store, host: c.env.host, themes: ThemeLibrary(paths: c.env.paths), channel: .snapshots, seeds: Set(packs.seeds().map(\.id)))
        #expect(report.failed.isEmpty, "\(report.failed)")
        #expect(await c.env.host.info(id: "dev.sidefolk.alpha")?.enabled == false)
        #expect(await c.env.host.info(id: "dev.sidefolk.beta")?.enabled == true)
        await c.env.host.shutdown()
    }

    /// The list in the repository is the one the founder approved (D98), and every entry's pack is in the gallery.
    @Test func theRepositorysListNamesTheFour() throws {
        let file = ExtFixtures.repoRoot.appendingPathComponent("Resources/SeedPacks/\(SeedPacks.listFile)")
        let list = try JSONValue.parse(String(decoding: Data(contentsOf: file), as: UTF8.self))
        let ids = (list["seeds"]?.arrayValue ?? []).compactMap { $0.string("id") }
        #expect(ids == ["world-clock", "system-vitals", "weather", "calculator"].map { "dev.sidefolk.\($0)" })
        for id in ids where ExtFixtures.hasAddons {
            let folder = String(id.split(separator: ".").last!)
            #expect(FileManager.default.fileExists(atPath: ExtFixtures.source(folder).appendingPathComponent("addon.json").path), "\(id) isn't in the gallery")
        }
    }

    @Test func versionsCompareNumberByNumberAndAPrereleaseComesFirst() {
        #expect(ExtensionVersion.compare("1.10.0", "1.9.9") == .orderedDescending)
        #expect(ExtensionVersion.compare("1.2", "1.2.0") == .orderedSame)
        #expect(ExtensionVersion.compare("2.0.0-beta.1", "2.0.0") == .orderedAscending)
        #expect(ExtensionVersion.compare("2.0.0-beta.2", "2.0.0-beta.1") == .orderedDescending)
    }
}
