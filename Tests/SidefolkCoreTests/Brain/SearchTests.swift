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
}
