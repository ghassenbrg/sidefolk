import Foundation
import Testing
@testable import SidefolkCore

/// Add-ons updating by themselves (D70): which updates may install without the person and which wait for their
/// look, the switch, and Settings › Updates' channel. The gallery is a folder (`AddonStoreTests.Gallery`); extensions
/// install into a host of their own (`HostEnv`).
@Suite struct AddonUpdaterTests {
    typealias Gallery = AddonStoreTests.Gallery

    // MARK: The rule, on its own

    static func side(_ version: String = "1.0.0", _ permissions: ExtensionPermissions = ExtensionPermissions(),
                     tools: [String: Risk] = ["echo": .low], background: Bool = false) -> ExtensionUpdateDiff.Side {
        .init(version: version, permissions: permissions, lines: PermissionSummary.forExtension(permissions).texts,
              tools: tools, background: background)
    }

    @Test func onlyAnUpdateThatAsksForNothingNewInstallsByItself() {
        func diff(_ new: ExtensionUpdateDiff.Side, from old: ExtensionUpdateDiff.Side = Self.side()) -> ExtensionUpdateDiff {
            ExtensionUpdateDiff(from: old, to: new)
        }
        // Same permissions, other files: nothing more it can do.
        #expect(!diff(Self.side("1.1.0")).widens)
        // Asking for less is fine too, though the sheet has a new line for it; so is a new reason for the network.
        let less = diff(Self.side("1.1.0"), from: Self.side("1.0.0", ExtensionPermissions(network: true)))
        #expect(!less.widens && less.addedPermissions == ["No access to your files or the internet"])
        #expect(!diff(Self.side("1.1.0", ExtensionPermissions(network: true, networkPurpose: "to find TVs")),
                      from: Self.side("1.0.0", ExtensionPermissions(network: true))).widens)

        let network = diff(Self.side("1.1.0", ExtensionPermissions(network: true)))
        #expect(network.widens && !network.addedPermissions.isEmpty)
        #expect(diff(Self.side("1.1.0", ExtensionPermissions(read: ["/Users/me/Notes"]))).widensPermissions)
        #expect(diff(Self.side("1.1.0", ExtensionPermissions(clipboard: true))).widens)
        #expect(diff(Self.side("1.1.0", ExtensionPermissions(folders: .write)),
                     from: Self.side("1.0.0", ExtensionPermissions(folders: .read))).widensPermissions)

        // A new tool may be as risky as the riskiest it had, not more; a tool it had may not get riskier.
        #expect(!diff(Self.side("1.1.0", tools: ["echo": .medium, "more": .medium]), from: Self.side(tools: ["echo": .medium])).widens)
        #expect(!diff(Self.side("1.1.0", tools: ["echo": .high, "more": .low]), from: Self.side(tools: ["echo": .high])).widens)
        #expect(diff(Self.side("1.1.0", tools: ["echo": .low, "wipe": .high])).riskierTools == ["wipe"])
        #expect(diff(Self.side("1.1.0", tools: ["echo": .medium])).riskierTools == ["echo"])
        #expect(diff(Self.side("1.1.0", tools: ["first": .low]), from: Self.side(tools: [:])).widens, "tools where it had none")

        #expect(diff(Self.side("1.1.0", background: true)).startsInBackground)
        #expect(!diff(Self.side("1.1.0", background: true), from: Self.side(background: true)).widens)

        // Companions and themes only draw: always by themselves. An extension without a preview never is.
        #expect(AddonUpdateRule.verdict(.companion) == .install)
        #expect(AddonUpdateRule.verdict(.theme) == .install)
        #expect(AddonUpdateRule.verdict(.extension) == .review)
    }

    // MARK: Against a gallery

    static let id = "dev.sidefolk.sample"

    /// Publishes the sample extension at `version` with this manifest's tools and permissions.
    static func publish(_ g: Gallery, _ version: String, tools: JSONValue = ["echo": ["risk": "low"]],
                        permissions: JSONValue = .object([:]), note: String = "") throws {
        var manifest = ExtFixtures.manifest(id: id, tools: tools, permissions: permissions)
        if case .object(var o) = manifest { o["version"] = .string(version); manifest = .object(o) }
        let made = try g.pack("sample", id: id, version: version,
                              files: [ExtensionManifest.fileName: manifest.jsonString, "server.py": ExtFixtures.server + note])
        g.entries.removeAll { $0["id"] as? String == id }
        g.entries.append(["id": id, "kind": "extension", "name": "Sample", "tagline": "A test extension", "description": "",
                          "author": "Sidefolk", "version": version, "file": made.file, "bytes": made.bytes, "sha256": made.sha])
        try g.publish()
    }

    /// The gallery's sample installed as the person would from the gallery (origin `official`), and an updater.
    static func scene() async throws -> (Gallery, HostEnv, AddonUpdater) {
        let g = try Gallery(), h = try HostEnv()
        try publish(g, "1.0.0")
        let entry = try #require(try await g.store.catalog().entry(id))
        try await h.host.install(from: try await g.store.fetch(entry), origin: .official)
        await g.store.discard(entry)
        return (g, h, AddonUpdater(store: g.store, extensions: h.host, themes: ThemeLibrary(paths: g.paths)))
    }

    static func installed(_ h: HostEnv) async -> ExtensionInfo? { await h.host.info(id: id) }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func anExtensionWaitsForReviewWhenItWouldDoMore() async throws {
        let (g, h, updater) = try await Self.scene()

        // Other files, the same permissions and tools: in by itself.
        try Self.publish(g, "1.1.0", note: "\n# a fix\n")
        _ = try await g.store.catalog(refresh: true)
        var report = await updater.run(channel: .releases, automatic: true)
        #expect(report.extensions.map(\.version) == ["1.1.0"] && report.review.isEmpty)
        #expect(await Self.installed(h)?.version == "1.1.0")
        #expect(await Self.installed(h)?.origin == .official)

        // A new permission: it waits, whatever the switch says, and nothing changes.
        try Self.publish(g, "1.2.0", permissions: ["exec": ["/usr/bin/true"]])
        _ = try await g.store.catalog(refresh: true)
        report = await updater.run(channel: .releases, automatic: true)
        #expect(report.extensions.isEmpty && report.review.map(\.version) == ["1.2.0"])
        #expect(await Self.installed(h)?.version == "1.1.0")

        // A new tool riskier than any it had: it waits too.
        try Self.publish(g, "1.3.0", tools: ["echo": ["risk": "low"], "wipe": ["risk": "high"]])
        _ = try await g.store.catalog(refresh: true)
        report = await updater.run(channel: .releases, automatic: true)
        #expect(report.extensions.isEmpty && report.review.map(\.version) == ["1.3.0"])
        #expect(await Self.installed(h)?.version == "1.1.0")
        #expect(h.env.registry.tool(named: "ext.sample.wipe") == nil)

        // The person looks and agrees: the install sheet's path takes it, as from the gallery's Update.
        let folder = try await g.store.fetch(try #require(report.review.first))
        let preview = await h.host.preview(folder: folder)
        #expect(preview.update?.riskierTools == ["wipe"])
        try await h.host.install(from: folder, origin: .official)
        #expect(await updater.run(channel: .releases, automatic: true).review.isEmpty, "nothing newer now")
        await h.host.shutdown()
    }

    /// The founder's case: the gallery's list was kept minutes before a new version went up. A timed look keeps the
    /// list for half an hour and doesn't see it; "Check for Updates…" fetches it again and installs it.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func checkingNowSeesAVersionPublishedSinceTheListWasKept() async throws {
        let (g, h, updater) = try await Self.scene()
        try Self.publish(g, "1.1.0", note: "\n# a fix\n")
        #expect(await updater.run(channel: .releases, automatic: true).extensions.isEmpty, "the kept list is still fresh")
        #expect(await Self.installed(h)?.version == "1.0.0")
        let report = await updater.run(channel: .releases, automatic: true, refresh: true)
        #expect(report.extensions.map(\.version) == ["1.1.0"])
        #expect(await Self.installed(h)?.version == "1.1.0")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func aDisabledExtensionUpdatesAndStaysOff() async throws {
        let (g, h, updater) = try await Self.scene()
        try await h.host.setEnabled(false, id: Self.id)
        try Self.publish(g, "1.1.0", note: "\n# a fix\n")
        _ = try await g.store.catalog(refresh: true)
        let report = await updater.run(channel: .releases, automatic: true)
        #expect(report.extensions.map(\.id) == [Self.id])
        let info = try #require(await Self.installed(h))
        #expect(info.version == "1.1.0" && !info.enabled)
        #expect(h.env.registry.tool(named: "ext.sample.echo") == nil, "its tools stay away while it's off")
        await h.host.shutdown()
    }

    /// Settings › Updates' channel holds for add-ons as for Sidefolk (D65), and with the switch off every update
    /// waits for the person.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func theChannelAndTheSwitchAreFollowed() async throws {
        let (g, h, updater) = try await Self.scene()
        try Self.publish(g, "1.1.0-snapshot.1", note: "\n# a snapshot\n")
        _ = try await g.store.catalog(refresh: true)

        let releases = await updater.run(channel: .releases, automatic: true)
        #expect(releases.installed == 0 && releases.review.isEmpty && releases.waiting.isEmpty, "Releases doesn't see snapshots")
        let off = await updater.run(channel: .snapshots, automatic: false)
        #expect(off.installed == 0 && off.waiting.map(\.version) == ["1.1.0-snapshot.1"])
        #expect(await Self.installed(h)?.version == "1.0.0")
        let on = await updater.run(channel: .snapshots, automatic: true)
        #expect(on.extensions.map(\.version) == ["1.1.0-snapshot.1"])
        await h.host.shutdown()
    }

    /// Companions and themes install by themselves with the switch on, and wait with it off.
    @Test func companionsAndThemesFollowTheSwitch() async throws {
        let g = try Gallery()
        let library = ThemeLibrary(paths: g.paths)
        func publishTheme(_ version: String) throws {
            var file = ThemeFile(.harbor, id: "dev.sidefolk.theme.dusk", name: "Dusk")
            file.version = version
            let made = try g.pack("theme-dusk", id: "dev.sidefolk.theme.dusk", version: version,
                                  files: ["theme.json": String(decoding: try file.encoded(), as: UTF8.self)])
            g.entries.removeAll { $0["id"] as? String == "dev.sidefolk.theme.dusk" }
            g.entries.append(["id": "dev.sidefolk.theme.dusk", "kind": "theme", "name": "Dusk", "tagline": "", "description": "",
                              "author": "Sidefolk", "version": version, "file": made.file, "bytes": made.bytes, "sha256": made.sha])
        }
        try g.companion("otter")
        try publishTheme("1.0.0")
        try g.publish()
        let first = try await g.store.catalog()
        try await g.store.install(companion: try #require(first.companion("otter")))
        try await g.store.install(theme: try #require(first.entry("dev.sidefolk.theme.dusk")), into: library)

        try g.companion("otter", version: "1.1.0")
        try publishTheme("1.1.0")
        try g.publish()
        _ = try await g.store.catalog(refresh: true)
        let updater = AddonUpdater(store: g.store, extensions: try HostEnv().host, themes: library)

        let off = await updater.run(channel: .releases, automatic: false)
        #expect(Set(off.waiting.map(\.id)) == ["dev.sidefolk.companions.otter", "dev.sidefolk.theme.dusk"] && off.installed == 0)
        #expect(await g.store.installedCompanions().first?.version == "1.0.0")

        let on = await updater.run(channel: .releases, automatic: true)
        #expect(on.companions.map(\.version) == ["1.1.0"] && on.themes.map(\.version) == ["1.1.0"] && on.review.isEmpty)
        #expect(library.all().first { $0.id == "dev.sidefolk.theme.dusk" }?.version == "1.1.0")
    }
}
