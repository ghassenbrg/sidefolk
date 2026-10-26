import Foundation
import Testing
@testable import SidefolkCore

/// The real JavaScript programs, run by the real osascript, against a stand-in object model shaped
/// like Notes' and Reminders' scripting (`NotesFixture.standIn`). No Apple Event is sent: the
/// stand-in replaces `Application(…)`, so nothing asks for permission and no real notes are read.
@Suite(.serialized) struct AutomationScriptTests {
    @Test func indexReadsTheTreeWhicheverWayNotesReportsIt() async throws {
        for flat in [false, true] {
            var fixture = NotesFixture.sample()
            fixture.flatAccountFolders = flat
            let index = try await AppleNotes(runner: fixture.standInRunner).index()
            #expect(index.folders.map(\.place) == ["iCloud › Notes", "iCloud › Recipes", "iCloud › Recipes › Weeknight",
                                                   "iCloud › Recently Deleted", "On My Mac › Notes"], "flat: \(flat)")
            #expect(index.folders.filter(\.isRecentlyDeleted).map(\.id) == ["f-trash"])
            #expect(index.notes.count == 6 && index.live.count == 5)
            let pasta = try #require(index.note(AppleNotes.handle(for: NotesFixture.id(1))))
            #expect(index.place(of: pasta) == "iCloud › Recipes › Weeknight")
            #expect(pasta.modified == fixture.notes[0].modified)
            #expect(index.note(NotesFixture.id(3))?.locked == true)
        }
    }

    @Test func toolsGiveTheSameAnswerOnTheRealScriptsAsOnTheFake() async throws {
        let fixture = NotesFixture.sample()
        let real = try MacAppsEnv(fixture.standInRunner)
        let fake = try MacAppsEnv(FakeAppleEvents(fixture))
        for (tool, input) in [("applenotes.list", JSONValue.object([:])),
                              ("applenotes.read", ["ids": [.string(AppleNotes.handle(for: NotesFixture.id(2))),
                                                           .string(AppleNotes.handle(for: NotesFixture.id(1)))]]),
                              ("applereminders.list", .object([:]))] {
            let a = await real.approved(tool, input).0
            let b = await fake.approved(tool, input).0
            #expect(a.result?.text != nil)
            #expect(a.result?.text == b.result?.text, "\(tool)")
        }
    }

    @Test func fetchStripsEmbeddedImagesAndNamesAttachments() async throws {
        var fixture = NotesFixture.sample()
        let photo = String(repeating: "A", count: 200_000)
        fixture.notes[1].html = "<div>Trip to Lyon</div><div><img src=\"data:image/png;base64,\(photo)\"><img src='cid:img-1'></div>"
        let notes = try await AppleNotes(runner: fixture.standInRunner).fetch([NotesFixture.id(2), "x-coredata://gone"], maxChars: 400_000)
        #expect(notes.count == 1, "a note that's gone is left out")
        #expect(notes[0].markdown == "[image] [image: ticket.pdf]")
        #expect(notes[0].attachments == ["ticket.pdf"] && notes[0].folderName == "Notes" && !notes[0].truncated)
    }

    /// The founder's real library: Notes answered "Can't get object" (-1728) partway through a note, and
    /// the whole copy failed three times. One stubborn part now costs only itself.
    @Test func oneStubbornPartCostsOnlyItself() async throws {
        var fixture = NotesFixture.sample()
        fixture.notes[0].html = "!-1728"
        fixture.notes[1].attachments.append(("!-1728", ""))
        let notes = try await AppleNotes(runner: fixture.standInRunner).fetch([NotesFixture.id(1), NotesFixture.id(2)], maxChars: 400_000)
        #expect(notes.count == 2)
        #expect(notes[0].unreadable == -1728)
        #expect(notes[1].unreadable == nil && notes[1].attachmentsPartial)
        #expect(notes[1].attachments == ["ticket.pdf", "attachment"])
    }

    @Test func removeMovesToRecentlyDeletedAndSaysWhereItWent() async throws {
        let fixture = NotesFixture.sample()
        let notes = AppleNotes(runner: fixture.standInRunner)
        let outcome = try await notes.remove([NotesFixture.id(1), NotesFixture.id(6), "x-coredata://gone"])
        #expect(outcome[NotesFixture.id(1)] == .movedToRecentlyDeleted)
        #expect(outcome[NotesFixture.id(6)] == .removed, "On My Mac has no Recently Deleted in the stand-in")
        #expect(outcome["x-coredata://gone"] == .missing)
    }

    @Test func remindersComeOpenAndSoonestFirst() async throws {
        let snapshot = try await AppleReminders(runner: NotesFixture.sample().standInRunner).open()
        #expect(snapshot.items.map(\.title) == ["Call the bank", "Eggs", "Milk"])
        #expect(snapshot.items[1].allDay && !snapshot.items[0].allDay)
        #expect(snapshot.lists.map(\.name) == ["Reminders", "Groceries"] && snapshot.lists.map(\.open) == [1, 2])
    }

    @Test func paramsNeverBecomeCode() async throws {
        let runner = OsascriptRunner(standIn: "function makeStandIn() { return {}; }", expression: "makeStandIn()")
        let tricky: JSONValue = ["a": "\"; throw 1; //", "b": "</script>\u{2028}\u{2029}\\", "c": "Café 日本 😀", "d": [1, true, .null]]
        let echoed = try await runner.run("function main(app, params) { return params; }", name: "echo", params: tricky, app: .notes, timeout: 20)
        #expect(echoed == tricky)
    }

    @Test func scriptErrorsBecomeAppleEventsErrors() async throws {
        let runner = OsascriptRunner(standIn: "function makeStandIn() { return {}; }", expression: "makeStandIn()")
        let refuse = "function main(app, params) { const e = new Error('Not authorized'); e.errorNumber = -1743; throw e; }"
        await #expect(throws: AppleEventsError.notPermitted(.notes)) {
            try await runner.run(refuse, name: "refuse", params: [:], app: .notes, timeout: 20)
        }
        let other = "function main(app, params) { const e = new Error('Odd'); e.errorNumber = -10000; throw e; }"
        await #expect(throws: AppleEventsError.failed(.reminders, code: -10000, message: "Odd")) {
            try await runner.run(other, name: "other", params: [:], app: .reminders, timeout: 20)
        }
    }

    @Test func aScriptThatNeverEndsIsStopped() async throws {
        let runner = OsascriptRunner(standIn: "function makeStandIn() { return {}; }", expression: "makeStandIn()")
        let started = Date()
        await #expect(throws: AppleEventsError.noAnswer(.notes)) {
            try await runner.run("function main(app, params) { while (true) {} }", name: "spin", params: [:], app: .notes, timeout: 1)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func osascriptErrorNumbers() {
        #expect(OsascriptRunner.errorNumber(in: "36:52: execution error: Not authorized to send Apple events to Notes. (-1743)\n") == -1743)
        #expect(OsascriptRunner.errorNumber(in: "syntax error") == nil)
    }

    @Test func recentlyDeletedNamesComeFromNotesItself() throws {
        // On this Mac Notes' strings are readable; a missing table leaves only the English name.
        #expect(NotesTrash.load(table: "/nonexistent") == ["Recently Deleted"])
        let table = "/System/Library/PrivateFrameworks/NotesShared.framework/Resources/Localizable.loctable"
        guard FileManager.default.fileExists(atPath: table) else { return }
        #expect(NotesTrash.load(table: table, preferences: ["de"]).contains("Zuletzt gelöscht"))
        #expect(NotesTrash.load(table: table, preferences: ["en"]) == ["Recently Deleted"])
    }
}
