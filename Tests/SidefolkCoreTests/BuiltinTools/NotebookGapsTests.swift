import Foundation
import Testing
@testable import SidefolkCore

/// Notebooks in the person's order, a task's due date, and an agent able to read what the person wrote (D117).
@Suite struct NotebookGapsTests {
    let t: BuiltinEnv
    var notebook: NotebookStore { t.notebook }

    init() throws { t = try BuiltinEnv() }

    func run(_ tool: String, _ input: JSONValue, as caller: Caller = .user) async -> ToolOutcome {
        await t.env.executor.execute(name: tool, input: input, caller: caller)
    }

    func result(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else {
            Issue.record("expected success, got \(outcome.status)")
            throw CancellationError()
        }
        return r
    }

    func saved(_ text: String, kind: String = "task", due: String? = nil) async throws -> NotebookItem {
        var input: [String: JSONValue] = ["text": .string(text), "kind": .string(kind)]
        if let due { input["due"] = .string(due) }
        let r = try result(await run("notes.save", .object(input)))
        let id = try #require(r.card?.refId)
        return try #require(try await notebook.item(id: id))
    }

    // MARK: Order

    @Test func collectionsAreAlphabeticalUntilArranged() async throws {
        _ = try await notebook.inbox()
        for name in ["Zebra", "Apple", "Mango"] { _ = try await notebook.createCollection(name: name, kind: .project) }
        #expect(try await notebook.collections().map(\.name).suffix(3) == ["Apple", "Mango", "Zebra"])
        _ = try result(await run("notes.arrange", ["collections": ["Zebra", "Apple"]]))
        let names = try await notebook.collections().map(\.name)
        #expect(names.first == "Inbox", "the Inbox stays first")
        #expect(Array(names.dropFirst()).starts(with: ["Zebra", "Apple"]))
        // Once arranged, a new one goes last, not by its letter.
        _ = try await notebook.createCollection(name: "Banana", kind: .project)
        #expect(try await notebook.collections().map(\.name).last == "Banana")
    }

    @Test func undoPutsTheOrderBack() async throws {
        for name in ["Zebra", "Apple"] { _ = try await notebook.createCollection(name: name, kind: .project) }
        let outcome = await run("notes.arrange", ["collections": ["Zebra", "Apple"]])
        _ = try await t.env.executor.undo.undo(outcome.activity.id)
        #expect(try await notebook.collections().map(\.name).suffix(2) == ["Apple", "Zebra"])
    }

    // MARK: Changing a collection

    @Test func aCollectionsNameIconAndColourCanBeChanged() async throws {
        _ = try await notebook.createCollection(name: "Trips", kind: .project)
        _ = try result(await run("notes.collection", ["collection": "Trips", "name": "Holidays", "symbol": "airplane", "color": "#AABBCC"]))
        let c = try #require(try await notebook.findCollection(named: "Holidays"))
        #expect(c.symbol == "airplane")
        #expect(c.color == "#aabbcc")
        #expect(!(await run("notes.collection", ["collection": "Holidays", "color": "#xyz"])).isOK)
        #expect(!(await run("notes.collection", ["collection": "Holidays", "symbol": "not.a.symbol"])).isOK)
        #expect(!(await run("notes.collection", ["collection": "Inbox", "name": "Mine"])).isOK)
    }

    @Test func undoPutsTheLookBackAndNothingElse() async throws {
        let c = try await notebook.createCollection(name: "Trips", kind: .project)
        let outcome = await run("notes.collection", ["collection": "Trips", "color": "blue"])
        try await notebook.setArchived(collectionId: c.id, true)
        _ = try await t.env.executor.undo.undo(outcome.activity.id)
        let after = try #require(try await notebook.collection(id: c.id))
        #expect(after.color == nil)
        #expect(after.archivedAt != nil, "what happened since stays")
    }

    @Test func anEmojiIsOneEmoji() async throws {
        _ = try await notebook.createCollection(name: "Trips", kind: .project)
        #expect(await run("notes.collection", ["collection": "Trips", "emoji": "✈️"]).isOK)
        #expect(!(await run("notes.collection", ["collection": "Trips", "emoji": "hello"])).isOK)
        #expect(!(await run("notes.collection", ["collection": "Trips", "emoji": .string("a" + String(repeating: "\u{301}", count: 50))])).isOK)
        #expect(!CollectionLooks.isColor("#+fffff"))
    }

    /// Naming a collection is what other agents otherwise can't do (T4), so it asks whatever the settings say.
    @Test func anotherAgentChangingACollectionIsAlwaysAsked() {
        var access = AgentAccess()
        access.change = .allow
        #expect(ExternalToolPolicy.permission("notes.collection", access: access) == .ask)
    }

    @Test func everyColourNameAndIconIsAcceptedAndNoIconIsThereTwice() {
        #expect(CollectionLooks.colorNames.allSatisfy(CollectionLooks.isColor))
        #expect(Set(CollectionLooks.symbols).count == CollectionLooks.symbols.count)
    }

    // MARK: Due dates

    @Test func aTaskCanBeDueOnADayOrAtATime() async throws {
        let day = try await saved("Send the deck", due: "tomorrow")
        #expect(day.dueAllDay)
        let time = try await saved("Call the bank", due: "tomorrow at 17:00")
        #expect(!time.dueAllDay)
        #expect(time.dueAt != nil)
    }

    @Test func aDueDateIsNoReminder() async throws {
        let item = try await saved("Send the deck", due: "tomorrow")
        #expect(item.dueAt != nil)
        let found = try await notebook.dueTasks(from: .distantPast, to: .distantFuture)
        #expect(found.map(\.id) == [item.id])
    }

    @Test func onlyATaskHasOne() async throws {
        #expect(!(await run("notes.save", ["text": "A thought", "kind": "note", "due": "tomorrow"])).isOK)
    }

    /// As for a reminder's time: one that can't be used changes nothing, a new collection included.
    @Test func aBadDueDateChangesNothing() async throws {
        #expect(!(await run("notes.save", ["text": "A", "kind": "task", "due": "whenever really", "collection": "Brand new"])).isOK)
        #expect(!(await run("notes.save", ["text": "A", "kind": "note", "due": "tomorrow", "collection": "Brand new"])).isOK)
        #expect(try await notebook.findCollection(named: "Brand new") == nil)
    }

    /// A day stays the same day a few time zones away.
    @Test func aDayIsKeptAtNoon() async throws {
        let item = try await saved("Send the deck", due: "tomorrow")
        let cal = Calendar.current
        #expect(cal.component(.hour, from: try #require(item.dueAt)) == 12)
    }

    @Test func aDueDateCantRepeatAndMustBeReadable() async throws {
        let item = try await saved("Send the deck")
        #expect(!(await run("notes.update", ["id": .string(item.id), "due": "every monday"])).isOK)
        #expect(!(await run("notes.update", ["id": .string(item.id), "due": "whenever really"])).isOK)
        #expect(try await notebook.item(id: item.id)?.dueAt == nil, "and nothing changed")
    }

    @Test func updatingSetsClearsAndUndoesIt() async throws {
        let item = try await saved("Send the deck")
        let set = await run("notes.update", ["id": .string(item.id), "due": "tomorrow"])
        #expect(set.isOK)
        #expect(try await notebook.item(id: item.id)?.dueAt != nil)
        _ = try await t.env.executor.undo.undo(set.activity.id)
        #expect(try await notebook.item(id: item.id)?.dueAt == nil)
        #expect(await run("notes.update", ["id": .string(item.id), "due": "tomorrow"]).isOK)
        #expect(await run("notes.update", ["id": .string(item.id), "due": ""]).isOK)
        #expect(try await notebook.item(id: item.id)?.dueAt == nil)
    }

    @Test func aDoneOrTrashedTaskIsNoLongerDue() async throws {
        let done = try await saved("Done one", due: "tomorrow")
        let trashed = try await saved("Trashed one", due: "tomorrow")
        let open = try await saved("Open one", due: "tomorrow")
        _ = try await notebook.setStatus(itemId: done.id, .done)
        _ = try await notebook.trash(itemId: trashed.id)
        #expect(try await notebook.dueTasks(from: .distantPast, to: .distantFuture).map(\.id) == [open.id])
    }

    @Test func theListSaysWhenItsDue() async throws {
        _ = try await saved("Send the deck", due: "tomorrow")
        #expect(try result(await run("notes.list", .object([:]))).text.contains("due "))
    }

    // MARK: Reading what the person wrote

    @Test func aNoteCanBeReadInFull() async throws {
        let long = String(repeating: "word ", count: 200)
        let item = try await saved("Title\n\(long)", kind: "note")
        #expect(try result(await run("notes.list", .object([:]))).text.count < long.count, "the list cuts it")
        let full = try result(await run("notes.get", ["id": .string(item.id)]))
        #expect(full.text.contains(long.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test func aNoteInTheTrashOrGoneIsNotFound() async throws {
        let item = try await saved("Old", kind: "note")
        _ = try await notebook.trash(itemId: item.id)
        #expect(!(await run("notes.get", ["id": .string(item.id)])).isOK)
        #expect(!(await run("notes.get", ["id": "nope"])).isOK)
    }

    @Test func anotherAgentsNoteReadsAsUntrusted() async throws {
        let r = try result(await run("notes.save", ["text": "Hello"], as: .external(client: "codex")))
        let full = try result(await run("notes.get", ["id": .string(try #require(r.card?.refId))]))
        #expect(full.untrusted)
    }

    @Test func otherAgentsMustBeAllowedToReadOrChange() {
        #expect(ExternalToolPolicy.reading.contains("notes.get"))
        #expect(ExternalToolPolicy.changing.contains("notes.arrange"))
        #expect(ExternalToolPolicy.alwaysAsks.contains("notes.collection"))
    }

    @Test func wordsCanBeAddedToANoteWithoutSendingItAllBack() async throws {
        let item = try await saved("Title\nFirst line", kind: "note")
        #expect(await run("notes.update", ["id": .string(item.id), "append": "Second line"]).isOK)
        #expect(try await notebook.item(id: item.id)?.body == "First line\n\nSecond line")
        #expect(!(await run("notes.update", ["id": .string(item.id), "append": "x", "text": "y"])).isOK)
    }

    @Test func addingToANoteFromElsewhereLeavesItFromElsewhere() async throws {
        let r = try result(await run("notes.save", ["text": "Hello"], as: .external(client: "codex")))
        let id = try #require(r.card?.refId)
        #expect(await run("notes.update", ["id": .string(id), "append": "More"]).isOK)
        #expect(try await notebook.item(id: id)?.source == "external:codex")
    }

    @Test func aNoteCantGrowPastItsLimit() async throws {
        let item = try await saved("Title\n" + String(repeating: "x", count: NoteText.maxText - 100), kind: "note")
        #expect(!(await run("notes.update", ["id": .string(item.id), "append": .string(String(repeating: "y", count: 200))])).isOK)
    }

    // MARK: Finding

    @Test func aLooseNameFindsTheCollection() async throws {
        _ = try await notebook.createCollection(name: "Sidefolk-Dev", kind: .project)
        #expect(try await notebook.findCollection(named: "Sidefolk Dev")?.name == "Sidefolk-Dev")
        #expect(try await notebook.findCollection(named: "sidefolk_dev")?.name == "Sidefolk-Dev")
        #expect(try await notebook.findCollection(named: "Side") == nil, "a piece of a word still isn't it")
    }

    @Test func twoLooseMatchesAreNotCertain() async throws {
        _ = try await notebook.createCollection(name: "Side-Folk", kind: .project)
        _ = try await notebook.createCollection(name: "Side Folk!", kind: .project)
        #expect(try await notebook.findCollection(named: "sidefolk") == nil)
    }

    @Test func searchingACollectionsNameFindsWhatsInIt() async throws {
        let c = try await notebook.createCollection(name: "Sidefolk-Dev", kind: .project)
        let says = NotebookItem(collectionId: c.id, kind: .note, title: "About sidefolk", source: "user")
        let inIt = NotebookItem(collectionId: c.id, kind: .note, title: "Sticky card", source: "user")
        try await notebook.add(says)
        try await notebook.add(inIt)
        let found = try await notebook.search("sidefolk")
        #expect(found.map(\.id) == [says.id, inIt.id], "what says the word comes first")
    }

    /// About you's facts aren't found by asking for "about", and a word too short to be a name finds nothing by it.
    @Test func searchingByNameLeavesOutAboutYouAndShortWords() async throws {
        let profile = try await NotebookCollections.profile(notebook, create: true)
        let fact = NotebookItem(collectionId: try #require(profile?.id), kind: .note, title: "Lives in Tunis", source: "user")
        try await notebook.add(fact)
        #expect(try await notebook.search("about").isEmpty)
        let c = try await notebook.createCollection(name: "Books", kind: .project)
        try await notebook.add(NotebookItem(collectionId: c.id, kind: .note, title: "Dune", source: "user"))
        #expect(try await notebook.search("ok").isEmpty)
        #expect(try await notebook.search("books").map(\.title) == ["Dune"])
    }

    @Test func aSearchInACollectionIsntWidenedByItsName() async throws {
        let c = try await notebook.createCollection(name: "Sidefolk", kind: .project)
        try await notebook.add(NotebookItem(collectionId: c.id, kind: .note, title: "Sticky card", source: "user"))
        let elsewhere = try await notebook.createCollection(name: "Other", kind: .project)
        #expect(try await notebook.search("sidefolk", collectionId: elsewhere.id).isEmpty)
    }
}
