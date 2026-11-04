import Foundation
import Testing
@testable import SidefolkCore

/// One search across Sidefolk (D58): what the one bar shows in Home and the Ask panel.
@Suite struct SearchTests {
    let runtime: SidefolkRuntime

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-search-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                        clock: ManualClock(TestEnv.referenceDate))
    }

    func fill() async throws {
        let inbox = try await runtime.notebook.inbox()
        try await runtime.notebook.add(NotebookItem(collectionId: inbox.id, kind: .note, title: "Bank details", body: "IBAN for the rent", source: "user"))
        var trashed = NotebookItem(collectionId: inbox.id, kind: .note, title: "Old bank card", source: "user")
        trashed.deletedAt = Date()
        try await runtime.notebook.add(trashed)
        try await runtime.reminderStore.save(Reminder(title: "Call the bank", fireAt: Date().addingTimeInterval(3600), source: "user"))
        var done = Reminder(title: "Visit the bank", fireAt: Date().addingTimeInterval(-3600), source: "user")
        done.state = .done
        try await runtime.reminderStore.save(done)
        try await runtime.watcherStore.save(Watcher(kind: "web.page", title: "Bank holiday hours", config: ["url": "https://example.com"],
                                                    intervalS: 900, source: "user"))
        try await runtime.exchanges.append(Exchange(threadId: "t1", role: .user, content: "What does my bank charge for transfers?"))
        _ = try await runtime.activity.log(ActivityEntry(caller: "agent", tool: "web.fetch", risk: "medium", decision: .allowed,
                                                         summary: "Fetch the bank's fee page"))
        _ = try await runtime.activity.log(ActivityEntry(caller: "agent", tool: "notes.search", risk: "low", decision: .auto,
                                                         summary: "Search the notebook for “tea”"))
    }

    @Test func oneSearchFindsEveryKind() async throws {
        try await fill()
        let found = try await runtime.find("BANK")
        #expect(found.notes.map(\.title) == ["Bank details"])
        #expect(found.conversations.map(\.title) == ["What does my bank charge for transfers?"])
        #expect(found.reminders.map(\.title) == ["Call the bank"])
        #expect(found.watches.map(\.title) == ["Bank holiday hours"])
        #expect(found.activity.map(\.summary) == ["Fetch the bank's fee page"])
    }

    @Test func everyWordMustAppear() async throws {
        try await fill()
        let found = try await runtime.find("bank fee")
        #expect(found.activity.map(\.summary) == ["Fetch the bank's fee page"])
        #expect(found.reminders.isEmpty && found.watches.isEmpty)
        // Accents and case don't matter; the text is literal, so % is not a wildcard.
        #expect(try await runtime.find("BÂNK").reminders.map(\.title) == ["Call the bank"])
        #expect(try await runtime.find("%%").isEmpty)
    }

    @Test func tooShortOrTooManyFindsLittle() async throws {
        try await fill()
        #expect(try await runtime.find("b").isEmpty)
        #expect(try await runtime.find("  ").isEmpty)
        for i in 0..<8 {
            try await runtime.reminderStore.save(Reminder(title: "Bank errand \(i)", fireAt: Date().addingTimeInterval(Double(i + 2) * 3600), source: "user"))
        }
        #expect(try await runtime.find("bank", limit: 5).reminders.count == 5)
    }

    // MARK: Extensions, installed and in the gallery (B1)

    private func catalog(_ entries: [(id: String, name: String, tagline: String, kind: String, version: String)]) throws -> AddonCatalog {
        let data = try JSONSerialization.data(withJSONObject: ["format": 1, "addons": entries.map { e in
            ["id": e.id, "kind": e.kind, "name": e.name, "tagline": e.tagline, "description": "", "author": "Sidefolk", "version": e.version,
             "file": "\(e.name)-\(e.version).zip", "bytes": 10, "sha256": String(repeating: "a", count: 64)] as [String: Any]
        }])
        return try AddonCatalog.parse(data, folder: URL(fileURLWithPath: "/tmp"), fetched: Date())
    }

    @Test func anExtensionIsFoundByNameFromWhatIsInstalledAndTheGalleryWithoutAsking() throws {
        let clock = ExtensionInfo.sample(id: "dev.sidefolk.world-clock", name: "World Clock", enabled: true, origin: .official,
                                         description: "Times in other cities")
        let off = ExtensionInfo.sample(id: "dev.sidefolk.calculator", name: "Calculator", enabled: false, origin: .official, description: "Sums")
        let gallery = try catalog([("dev.sidefolk.currency", "Currency", "Money in 30 currencies", "extension", "1.1.0"),
                                   ("dev.sidefolk.world-clock", "World Clock", "Times in other cities", "extension", "1.1.0"),
                                   ("dev.sidefolk.companions.ember", "Ember", "A fox", "companion", "1.0.0")])
        func names(_ query: String, channel: UpdateChannel = .releases) -> [String] {
            ExtensionHit.matching(query, installed: [clock, off], catalog: gallery, channel: channel, limit: 5).map(\.name)
        }
        #expect(names("world clock") == ["World Clock"], "installed, and not listed twice because the gallery has it too")
        #expect(names("CLOCK") == ["World Clock"], "case does not matter")
        #expect(names("calc") == ["Calculator"], "a switched-off one is found too")
        #expect(names("currency") == ["Currency"], "one in the gallery that isn't installed")
        #expect(names("ember").isEmpty, "companions are not extensions")
        let hit = ExtensionHit.matching("calculator", installed: [clock, off], catalog: gallery, channel: .releases, limit: 5)
        #expect(hit.first?.place == .installed(enabled: false) && hit.first?.byName == true)
        #expect(ExtensionHit.matching("currency", installed: [], catalog: gallery, channel: .releases, limit: 5).first?.place == .gallery)
    }

    @Test func wordsInADescriptionFindAnExtensionButNeverMakeItTheOneThatOpens() throws {
        let clock = ExtensionInfo.sample(id: "dev.sidefolk.world-clock", name: "World Clock", enabled: true, origin: .official,
                                         description: "Times in other cities")
        let found = ExtensionHit.matching("cities", installed: [clock], catalog: nil, channel: .releases, limit: 5)
        #expect(found.map(\.name) == ["World Clock"] && found.first?.byName == false)
        #expect(ExtensionHit.matching("remind me at 5 to call", installed: [clock], catalog: nil, channel: .releases, limit: 5).isEmpty)
        // The maker and the id are not searched: "sidefolk" would match every official extension.
        #expect(ExtensionHit.matching("sidefolk", installed: [clock], catalog: nil, channel: .releases, limit: 5).isEmpty)
    }

    @Test func theGalleryShowsSnapshotsOnlyToThoseWhoChoseThem() throws {
        let gallery = try catalog([("dev.sidefolk.formatic", "Formatic", "Convert files", "extension", "1.0.0-snapshot.1")])
        #expect(ExtensionHit.matching("formatic", installed: [], catalog: gallery, channel: .releases, limit: 5).isEmpty)
        #expect(ExtensionHit.matching("formatic", installed: [], catalog: gallery, channel: .snapshots, limit: 5).map(\.name) == ["Formatic"])
    }

    /// Through the runtime, as the one bar and the Ask panel search: an installed extension is found by its name, the
    /// gallery's last checked list needs no network, and nothing here asks an AI.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func theRuntimeSearchFindsAnInstalledExtensionByName() async throws {
        let folder = try ExtFixtures.makeExtension(at: try ExtFixtures.tempDir("find").appendingPathComponent("sample"),
                                                   manifest: ExtFixtures.manifest(id: "dev.test.sample"), files: ["server.py": ExtFixtures.server])
        let installed = try await runtime.extensions.install(from: folder)
        let found = try await runtime.find(String(installed.name.prefix(4)))
        #expect(found.extensions.map(\.id) == ["dev.test.sample"])
        #expect(found.extensions.first?.place == .installed(enabled: installed.enabled))
        #expect(!found.isEmpty)
        await runtime.extensions.shutdown()
    }
}
