import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// How built-in extensions follow the app (D39): installed on or off as the catalog says, kept as the
/// person switched them, replaced when the app brings a different copy, never removed.
@Suite(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
struct BundledExtensionsTests {
    /// A catalog folder like the app's `Resources/Extensions`, with fixture extensions.
    final class Catalog {
        let directory: URL
        init(_ root: URL) throws {
            directory = root.appendingPathComponent("Resources/Extensions", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func ship(_ folder: String, id: String, version: String = "1.0.0", permissions: JSONValue = .object([:]), on: Bool,
                  extra: String = "") throws {
            var manifest = ExtFixtures.manifest(id: id, permissions: permissions)
            manifest = manifest.setting("version", .string(version))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(folder))
            try ExtFixtures.makeExtension(at: directory.appendingPathComponent(folder, isDirectory: true), manifest: manifest,
                                          files: ["server.py": ExtFixtures.server + extra])
            var entries = (try? JSONValue.parse(String(decoding: Data(contentsOf: catalogFile), as: UTF8.self)))?["extensions"]?.arrayValue ?? []
            entries.removeAll { $0.string("folder") == folder }
            entries.append(["folder": .string(folder), "on": .bool(on)])
            try Data(JSONValue.object(["extensions": .array(entries)]).jsonString.utf8).write(to: catalogFile)
        }

        var catalogFile: URL { directory.appendingPathComponent(BundledExtensions.catalogFile) }
    }

    @Test func installsEachOnOrOffAsTheCatalogSays() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("alpha", id: "dev.test.alpha", on: true)
        try catalog.ship("beta", id: "dev.test.beta", on: false)
        let bundled = BundledExtensions(directory: catalog.directory)
        await bundled.install(into: h.host)
        let alpha = try #require(await h.host.info(id: "dev.test.alpha"))
        let beta = try #require(await h.host.info(id: "dev.test.beta"))
        #expect(alpha.origin == .bundled && alpha.enabled)
        #expect(beta.origin == .bundled && !beta.enabled)
        #expect(h.env.registry.tool(named: "ext.alpha.echo") != nil)
        #expect(h.env.registry.tool(named: "ext.beta.echo") == nil, "an optional one adds no tools until switched on")
        #expect(await h.host.isRunning("dev.test.beta") == false)
        await h.host.shutdown()
    }

    @Test func anUnchangedCopyIsLeftAloneAndTheChoiceSurvivesUpdates() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("alpha", id: "dev.test.alpha", on: true)
        let bundled = BundledExtensions(directory: catalog.directory)
        await bundled.install(into: h.host)
        await h.host.shutdown()
        await bundled.install(into: h.host)
        #expect(await h.host.isRunning("dev.test.alpha") == false, "nothing was reinstalled (an install starts it)")

        try await h.host.setEnabled(false, id: "dev.test.alpha")
        try catalog.ship("alpha", id: "dev.test.alpha", version: "1.1.0", on: true, extra: "\n# 1.1\n")
        await bundled.install(into: h.host)
        let updated = try #require(await h.host.info(id: "dev.test.alpha"))
        #expect(updated.version == "1.1.0")
        #expect(!updated.enabled, "switched off stays off across an update")
        await h.host.shutdown()
    }

    @Test func anUpdateThatAsksForMoreWaitsToBeSwitchedOn() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("alpha", id: "dev.test.alpha", on: true)
        let bundled = BundledExtensions(directory: catalog.directory)
        await bundled.install(into: h.host)
        let notices = h.env.events.stream()
        try catalog.ship("alpha", id: "dev.test.alpha", version: "2.0.0", permissions: ["network": true], on: true)
        await bundled.install(into: h.host)
        let info = try #require(await h.host.info(id: "dev.test.alpha"))
        #expect(info.version == "2.0.0" && !info.enabled)
        let said = await ExtFixtures.firstNotice(notices)
        #expect(said?.contains("can now do more (Can use the internet)") == true, "\(String(describing: said))")
        await h.host.shutdown()
    }

    @Test func aCopyInstalledByHandStaysUnlessTheAppIsNewer() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("alpha", id: "dev.test.alpha", version: "1.5.0", on: true)
        let bundled = BundledExtensions(directory: catalog.directory)

        var mine = ExtFixtures.manifest(id: "dev.test.alpha").setting("version", "2.0.0")
        try await h.host.install(from: h.source("alpha", manifest: mine))
        await bundled.install(into: h.host)
        #expect(await h.host.info(id: "dev.test.alpha")?.origin == nil, "a newer copy of your own is kept")
        #expect(await h.host.info(id: "dev.test.alpha")?.version == "2.0.0")

        mine = mine.setting("version", "1.0.0")
        try await h.host.install(from: h.source("alpha-old", manifest: mine))
        await bundled.install(into: h.host)
        let replaced = try #require(await h.host.info(id: "dev.test.alpha"))
        #expect(replaced.origin == .bundled && replaced.version == "1.5.0")
        await h.host.shutdown()
    }

    @Test func aDamagedCopyIsRestoredFromTheApp() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("alpha", id: "dev.test.alpha", on: true)
        let bundled = BundledExtensions(directory: catalog.directory)
        await bundled.install(into: h.host)
        await h.host.shutdown()
        let file = h.paths.extensions.appendingPathComponent("dev.test.alpha/server.py").path
        chmod(file, 0o644)
        try Data("# changed\n".utf8).write(to: URL(fileURLWithPath: file))
        await bundled.install(into: h.host)
        #expect(await h.call("ext.alpha.echo", ["a": 1]).okText?.contains("echoed") == true)
        await h.host.shutdown()
    }

    @Test func oneThatCantRunHereIsListedWithTheReason() async throws {
        let h = try HostEnv()
        let catalog = try Catalog(h.root)
        try catalog.ship("broken", id: "dev.test.broken", permissions: ["exec": ["/nonexistent/program"]], on: true)
        let bundled = BundledExtensions(directory: catalog.directory)
        await bundled.install(into: h.host)
        #expect(bundled.unavailable.map(\.id) == ["dev.test.broken"])
        #expect(bundled.unavailable.first?.message.hasPrefix("“/nonexistent/program” doesn't exist") == true,
                "\(String(describing: bundled.unavailable.first?.message))")
        #expect(await h.host.info(id: "dev.test.broken") == nil)
    }

    @Test func versionsCompareByNumbersThenPreReleases() {
        #expect(ExtensionVersion.compare("1.10.0", "1.9.9") == .orderedDescending)
        #expect(ExtensionVersion.compare("1.2", "1.2.0") == .orderedSame)
        #expect(ExtensionVersion.compare("2.0.0-beta.1", "2.0.0") == .orderedAscending)
        #expect(ExtensionVersion.compare("2.0.0-beta.2", "2.0.0-beta.1") == .orderedDescending)
    }
}
