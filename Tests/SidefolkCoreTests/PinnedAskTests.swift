import Foundation
import Testing
@testable import SidefolkCore

/// Pinned results in Ask outlast quitting (D136).
@Suite struct PinnedAskTests {
    private func store() throws -> PinnedAskStore { PinnedAskStore(try AppDatabase.inMemory()) }

    private let requests = [
        SavedAskRequest(caption: "what's the shortcut", createdAt: Date(timeIntervalSince1970: 1000), seenAt: Date(timeIntervalSince1970: 1010), parts: [
            .answer("Cmd + Shift + 3", tainted: false, thread: "t1"),
        ]),
        SavedAskRequest(caption: "save this", createdAt: Date(timeIntervalSince1970: 2000), seenAt: nil, parts: [
            .result(ResultCard(kind: .note, title: "Saved", subtitle: "Inbox", refId: "n1", itemKind: .note)),
            .list(title: "Found", cards: [ResultCard(kind: .web, title: "A page", url: "https://example.com")]),
            .info("Done"), .doneWithoutAsking("Ran it", fullAccess: true), .skipped("Sent nothing", why: "No answer"),
        ]),
    ]

    @Test func theyComeBackAsTheyWere() async throws {
        let pins = try store()
        #expect(await pins.load().isEmpty)
        try await pins.save(requests)
        #expect(await pins.load() == requests)
    }

    @Test func anAnswerWhoseConversationWentComesBackWithoutIt() async throws {
        let pins = try store()
        try await pins.save(requests)
        let loaded = await pins.load(conversationKept: { _ in false })
        #expect(loaded[0].parts == [.answer("Cmd + Shift + 3", tainted: false, thread: nil)])
        #expect(loaded[1] == requests[1])
    }

    @Test func unpinningTheLastLeavesNothingBehind() async throws {
        let pins = try store()
        try await pins.save(requests)
        try await pins.save([])
        #expect(await pins.load().isEmpty)
        let left = try await pins.db.writer.read { db in try KeyValue.fetchOne(db, key: PinnedAskStore.key) }
        #expect(left == nil)
    }

    @Test func somethingUnreadableIsNoPins() async throws {
        let pins = try store()
        try await pins.db.writer.write { db in try KeyValue(key: PinnedAskStore.key, value: .string("not this")).save(db) }
        #expect(await pins.load().isEmpty)
    }
}
