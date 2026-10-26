import Foundation
import GRDB
import Testing
@testable import SidefolkCore

/// Collection kinds on save, and the edges QA found: Windows line breaks, a collection called "inbox", and Undo after Trash.
@Suite struct NotebookEdgeTests {
    private func names(_ t: BuiltinEnv) async throws -> [String] { try await t.notebook.collections().map(\.name) }

    // MARK: collection_kind

    @Test func aNewCollectionIsMadeAsTheKindAskedFor() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let out = await t.run("notes.save", ["text": "Milk", "kind": "task", "collection": "Groceries", "collection_kind": "list"], as: .user)
        let result = try #require(out.result)
        #expect(result.text.contains("created it as a new list"))
        #expect(result.card?.detail == "New list “Groceries” created.")
        #expect(try await t.notebook.findCollection(named: "Groceries")?.kind == .list)

        _ = await t.run("notes.save", ["text": "Trip ideas", "collection": "Travel", "collection_kind": "topic"], as: .user)
        #expect(try await t.notebook.findCollection(named: "Travel")?.kind == .topic)
        _ = await t.run("notes.save", ["text": "x", "collection": "Plain"], as: .user)
        #expect(try await t.notebook.findCollection(named: "Plain")?.kind == .project, "project unless asked")
    }

    @Test func theKindIsOnlyUsedWhenTheCollectionIsCreated() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        _ = await t.run("collections.create", ["name": "Sidefolk"], as: .user)
        let out = await t.run("notes.save", ["text": "an idea", "collection": "sidefolk", "collection_kind": "list"], as: .user)
        #expect(out.result?.text.contains("didn't exist") == false)
        #expect(try await t.notebook.findCollection(named: "Sidefolk")?.kind == .project, "an existing collection keeps its kind")
        #expect(try await t.notebook.collections().filter { $0.name.lowercased() == "sidefolk" }.count == 1)
    }

    @Test func aBadKindIsRefusedInPlainWords() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        for bad in ["galaxy", "profile", "inbox"] {
            let out = await t.run("notes.save", ["text": "x", "collection": "Z", "collection_kind": .string(bad)], as: .user)
            #expect(out.failure != nil, "\(bad)")
        }
        #expect(try await t.notebook.findCollection(named: "Z") == nil)
    }

    // MARK: Edges found by QA

    @Test func crlfIsALineBreak() async throws {
        let (title, body) = NoteText.split("Title\r\nBody line\r\nmore\rlast")
        #expect(title == "Title")
        #expect(body == "Body line\nmore\nlast")

        let t = try BuiltinEnv()
        defer { t.cleanup() }
        _ = await t.run("notes.save", ["text": "Windows title\r\nand its body"], as: .user)
        let item = try #require(try await t.notebook.items().first)
        #expect(item.title == "Windows title" && item.body == "and its body")
    }

    @Test func creatingACollectionCalledInboxDoesNotDuplicateTheInbox() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        let out = await t.run("collections.create", ["name": "inbox"], as: .user)
        #expect(out.result?.text == "“Inbox” already exists.")
        _ = await t.run("notes.save", ["text": "x"], as: .user)
        #expect(try await names(t).filter { $0.lowercased() == "inbox" }.count == 1)
    }

    @Test func undoingAnEditDoesNotUntrashTheNote() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        _ = await t.run("notes.save", ["text": "first version"], as: .user)
        let id = try #require(try await t.notebook.items().first?.id)
        let edit = await t.run("notes.update", ["id": .string(id), "text": "second version"], as: .user)
        _ = await t.run("notes.trash", ["id": .string(id)], as: .user)
        _ = try await t.env.executor.undo.undo(edit.activity.id)
        let note = try #require(try await t.notebook.item(id: id))
        #expect(note.deletedAt != nil, "still in the Trash")
        #expect(note.title == "first version", "the words did go back")
    }

    @Test func undoingAnEditStillWorksWhenTheNoteIsNotTrashed() async throws {
        let t = try BuiltinEnv()
        defer { t.cleanup() }
        _ = await t.run("notes.save", ["text": "first version"], as: .user)
        let id = try #require(try await t.notebook.items().first?.id)
        let edit = await t.run("notes.update", ["id": .string(id), "text": "second version"], as: .user)
        _ = try await t.env.executor.undo.undo(edit.activity.id)
        let note = try #require(try await t.notebook.item(id: id))
        #expect(note.deletedAt == nil && note.title == "first version")
    }
}

/// Collections made before their source was recorded count as the user's after the upgrade.
@Suite struct CollectionSourceMigrationTests {
    @Test func olderCollectionsBecomeTheUsers() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO collections (id, name, kind, created_at, updated_at) VALUES ('c1', 'Old', 'project', 0, 0)")
        }
        let upgraded = try AppDatabase(queue)
        let old = try #require(try await NotebookStore(upgraded).collection(id: "c1"))
        #expect(old.source == "user")
        #expect(old.name == "Old")
    }
}
