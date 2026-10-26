import Foundation
import Testing
@testable import SidefolkCore

/// Copying Apple Notes into the notebook, and removing them from Notes only when that loses nothing.
@Suite struct AppleNotesCopyTests {
    static func handle(_ n: Int) -> String { AppleNotes.handle(for: NotesFixture.id(n)) }

    static func copy(_ pairs: [(Int, String)]) -> JSONValue {
        ["notes": .array(pairs.map { ["id": .string(handle($0.0)), "collection": .string($0.1)] })]
    }

    @Test func copyFilesEachNoteWithWhereItCameFrom() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.list")
        let (out, card) = await h.approved("applenotes.copy", Self.copy([(1, "Cooking"), (2, "Travel"), (4, "Cooking")]), tainted: true)

        let request = try #require(card)
        #expect(request.summary == "Copy 3 notes from Apple Notes into “Cooking”, “Travel”")
        #expect(request.risk == .medium && request.tainted && request.effect == .changesThings)
        let result = try #require(out.result)
        #expect(out.isOK && result.untrusted)
        #expect(result.text.contains("Copied 3 notes into the notebook:"))
        #expect(result.text.contains("- \(Self.handle(1)) “Pasta carbonara” → Cooking (id "))
        #expect(result.text.contains("“Trip to Lyon” → Travel (id ") && result.text.contains("1 attachment left in Notes"))
        // Five notes outside Recently Deleted; one is locked.
        #expect(result.text.contains("Progress: 3 of 5 notes in Apple Notes are in the notebook; 1 to go (and 1 locked)."))
        #expect(out.activity.card?.title == "Copied 3 notes from Apple Notes")
        #expect(out.activity.card?.subtitle == "Cooking, Travel")
        #expect(out.activity.undoAvailable)

        let items = try await h.items()
        #expect(items.count == 3)
        let pasta = try #require(items.first { $0.title == "Pasta carbonara" })
        #expect(pasta.source == "app:notes" && pasta.tagList == ["apple-notes"] && pasta.kind == .note)
        #expect(pasta.body.hasPrefix("Guanciale, eggs, **pecorino**.\n- Boil pasta\n- Mix"))
        #expect(pasta.body.contains("*From Apple Notes › iCloud › Recipes › Weeknight · created "))
        let fixture = h.fake.fixture
        #expect(pasta.createdAt == fixture.notes[0].created && pasta.updatedAt == fixture.notes[0].modified)
        let trip = try #require(items.first { $0.title == "Trip to Lyon" })
        #expect(trip.body.contains("Attachments left in Apple Notes: ticket.pdf"))

        // Collections the agent made while reading outside content are marked as such (SECURITY T3).
        let cooking = try #require(try await h.notebook.findCollection(named: "Cooking"))
        #expect(cooking.source == "agent")

        // The ledger knows what was copied, and whether the copy is whole.
        let ledger = try await h.ledger.load()
        #expect(ledger[NotesFixture.id(1)]?.complete == true)
        #expect(ledger[NotesFixture.id(2)]?.complete == false, "its attachment stayed in Notes")
        #expect(ledger[NotesFixture.id(1)]?.place == "iCloud › Recipes › Weeknight")

        // Copying never asks Notes to change anything.
        #expect(!h.fake.calls.contains("notes.remove"))
    }

    @Test func copiesAreOutsideContentWhenReadBack() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(1, "Cooking")]))
        let search = await h.run("notes.search", ["query": "carbonara"])
        #expect(search.result?.untrusted == true)
        #expect(search.result?.text.contains("copied from Apple Notes") == true)
        #expect(!ContextBuilder.isUserSourced("app:notes"), "never offered to the model unasked")
    }

    @Test func undoTakesTheCopiesBackOut() async throws {
        let h = try MacAppsEnv()
        let (out, _) = await h.approved("applenotes.copy", Self.copy([(1, "Cooking"), (4, "Cooking")]))
        #expect(try await h.items().count == 2)
        let label = try await h.env.executor.undo.undo(out.activity.id)
        #expect(label == "Removed 2 copied notes")
        #expect(try await h.items().isEmpty)
        #expect(try await h.ledger.load().isEmpty, "a second copy starts over")
    }

    @Test func skipsWhatIsCopiedLockedOrDeleted() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(1, "Cooking")]))
        let (again, _) = await h.approved("applenotes.copy", Self.copy([(1, "Cooking"), (3, "Bank"), (5, "Old"), (4, "Bread")]))
        let text = try #require(again.result?.text)
        #expect(text.contains("Copied 1 note into the notebook:"))
        #expect(text.contains("\(Self.handle(1)) “Pasta carbonara”: already in the notebook (id "))
        #expect(text.contains("\(Self.handle(3)) “Bank codes”: it is locked; the user can unlock it in Notes"))
        #expect(text.contains("\(Self.handle(5)) “Old list”: it is in Recently Deleted"))
        #expect(try await h.items().count == 2)
        #expect(try await h.notebook.findCollection(named: "Bank") == nil, "nothing was made for a note that wasn't copied")
        // Only the note that could be copied was read in full.
        let fetched = h.fake.params(of: "notes.fetch").last?["ids"]?.arrayValue?.compactMap(\.stringValue)
        #expect(fetched == [NotesFixture.id(4)])
    }

    @Test func aCopyWhoseItemWasTrashedCanBeMadeAgain() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(1, "Cooking")]))
        let first = try #require(try await h.items().first)
        _ = try await h.notebook.trash(itemId: first.id)
        let (again, _) = await h.approved("applenotes.copy", Self.copy([(1, "Cooking")]))
        #expect(again.result?.text.contains("Copied 1 note into the notebook:") == true)
        #expect(try await h.ledger.load()[NotesFixture.id(1)]?.itemId != first.id)
    }

    @Test func refusesTooManyAndBadEntries() async throws {
        let h = try MacAppsEnv()
        let many: JSONValue = ["notes": .array((1...51).map { ["id": .string("n\($0)"), "collection": "X"] })]
        let tooMany = await h.run("applenotes.copy", many)
        #expect(tooMany.failure?.message == "That request didn't fit the tool: “notes” has too many entries (at most 50).")
        let missing = await h.run("applenotes.copy", ["notes": [["id": .string(Self.handle(1))]]])
        #expect(missing.wasDenied && missing.text == "Each entry in “notes” needs an “id” and a “collection”.")
        #expect(h.fake.calls.isEmpty, "refused before any card or any Apple Event")
        let profile = await h.approved("applenotes.copy", Self.copy([(1, "About you")])).0
        #expect(profile.result?.text.contains("“About you” holds facts about you, so notes can't be filed there.") == true)
        #expect(h.fake.calls.allSatisfy { $0 != "notes.remove" })
    }

    // MARK: Removing (moving)

    @Test func removingANoteThatWasntCopiedIsRefusedBeforeAnyCard() async throws {
        let h = try MacAppsEnv()
        try await h.ledger.load()
        let out = await h.run("applenotes.remove", ["ids": [.string(Self.handle(1))]])
        #expect(out.wasDenied)
        #expect(out.text == "Only notes already copied into the notebook can be removed from Apple Notes. Copy them first.")
        #expect(await h.env.broker.pending().isEmpty)
        #expect(!h.fake.calls.contains("notes.remove"))
    }

    @Test func moveRemovesOnlyWholeCopiesAfterAHighRiskApproval() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(1, "Cooking"), (2, "Travel")]))
        let (out, card) = await h.approved("applenotes.remove", ["ids": [.string(Self.handle(1)), .string(Self.handle(2))]], tainted: true)

        let request = try #require(card)
        #expect(request.risk == .high && !request.canAlways && request.effect == .changesThings)
        #expect(request.summary == "Move 2 notes in Apple Notes to Recently Deleted")
        guard case .text(let listed) = request.details else { Issue.record("expected the notes listed"); return }
        #expect(listed.contains("“Pasta carbonara” (iCloud › Recipes › Weeknight)"))
        #expect(listed.contains("“Trip to Lyon” (iCloud › Notes)"))
        #expect(listed.contains("Notes keeps deleted notes in Recently Deleted for 30 days."))

        let text = try #require(out.result?.text)
        #expect(text.contains("Moved to Recently Deleted in Apple Notes:\n- \(Self.handle(1)) “Pasta carbonara”"))
        #expect(text.contains("Left in Apple Notes:\n- \(Self.handle(2)) “Trip to Lyon”: its copy isn't complete"))
        #expect(out.activity.card?.title == "Moved 1 notes to Recently Deleted in Apple Notes")
        let removed = h.fake.params(of: "notes.remove").first?["ids"]?.arrayValue?.compactMap(\.stringValue)
        #expect(removed == [NotesFixture.id(1)], "only the whole copy left Notes")
        #expect(h.fake.fixture.notes.first { $0.id == NotesFixture.id(1) }?.folder == "f-trash")
        // Its copy is still in the notebook.
        #expect(try await h.items().contains { $0.title == "Pasta carbonara" })
    }

    @Test func notesChangedSinceTheCopyStay() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(4, "Bread")]))
        h.fake.edit { $0.notes[3].modified = $0.notes[3].modified.addingTimeInterval(60) }
        let (out, _) = await h.approved("applenotes.remove", ["ids": [.string(Self.handle(4))]])
        #expect(out.result?.text.contains("it changed in Notes after it was copied; copy it again first") == true)
        #expect(out.result?.text.hasPrefix("Nothing was removed from Apple Notes.") == true)
        #expect(!h.fake.calls.contains("notes.remove"))
    }

    @Test func accountsWithoutRecentlyDeletedKeepTheirNotes() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(6, "Inbox")]))
        let (out, _) = await h.approved("applenotes.remove", ["ids": [.string(Self.handle(6))]])
        #expect(out.result?.text.contains("its account has no Recently Deleted folder, so it would be deleted for good") == true)
        #expect(h.fake.fixture.notes.contains { $0.id == NotesFixture.id(6) })
    }

    @Test func aCopyTrashedInTheNotebookKeepsTheOriginal() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.copy", Self.copy([(1, "Cooking")]))
        let item = try #require(try await h.items().first)
        _ = try await h.notebook.trash(itemId: item.id)
        let (out, _) = await h.approved("applenotes.remove", ["ids": [.string(Self.handle(1))]])
        #expect(out.result?.text.contains("its copy is no longer in the notebook") == true)
        #expect(h.fake.fixture.notes.first { $0.id == NotesFixture.id(1) }?.folder == "f-weeknight")
    }
}
