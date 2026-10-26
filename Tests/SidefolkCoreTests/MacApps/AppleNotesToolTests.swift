import Foundation
import Testing
@testable import SidefolkCore

/// The Apple Notes tools on a fake Notes: what they read, what Guard asks, taint, paging, copying,
/// and the checks before anything leaves Notes (DECISIONS D38).
@Suite struct AppleNotesToolTests {
    static func handle(_ n: Int) -> String { AppleNotes.handle(for: NotesFixture.id(n)) }

    // MARK: Listing

    @Test func listShowsFoldersAndOnePageAndIsUntrusted() async throws {
        let h = try MacAppsEnv()
        let (out, card) = await h.approved("applenotes.list")

        let request = try #require(card)
        #expect(request.risk == .medium && request.readsOnly && request.canAlways)
        #expect(request.summary == "Read the titles, folders and dates of up to 50 of your Apple Notes")
        let result = try #require(out.result)
        #expect(result.untrusted)
        let text = result.text
        #expect(text.contains("Apple Notes on this Mac: 5 notes in 4 folders (Recently Deleted, with 1 note, is left out)."))
        #expect(text.contains("iCloud › Recipes › Weeknight (1)"))
        #expect(text.contains("On My Mac › Notes (1)"))
        #expect(!text.contains("Old list"), "notes in Recently Deleted are never listed")
        #expect(text.contains("- \(Self.handle(1)) “Pasta carbonara” · iCloud › Recipes › Weeknight · modified"))
        #expect(text.contains("Guanciale, eggs, **pecorino**."))
        #expect(text.contains("“Bank codes”") && text.contains("locked (can't be read or copied)"))
        #expect(text.contains("1 attachment"))
        // Newest first: Pasta (1 day ago) before Trip (2) before Sourdough (4).
        let order = ["Pasta carbonara", "Trip to Lyon", "Bank codes", "Sourdough"].map { text.range(of: $0)!.lowerBound }
        #expect(order == order.sorted())
        // The page's snippets come in one call, and locked notes' text is never asked for.
        let snippetIds = h.fake.params(of: "notes.snippets").first?["ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(snippetIds.count == 4 && !snippetIds.contains(NotesFixture.id(3)))
        // The model reads it as untrusted content.
        #expect(out.modelText.hasPrefix("<untrusted_content source=\"applenotes.list\">"))
    }

    @Test func readingAsksUntilAlwaysAllowedAndAlwaysWhileTainted() async throws {
        let h = try MacAppsEnv()
        let (_, first) = await h.approved("applenotes.list", [:], .allowAlways)
        #expect(first != nil)

        // Clean turn: the grant covers it.
        let clean = await h.run("applenotes.list")
        #expect(clean.result != nil)
        #expect(try await ActivityStore(h.env.db).recent().first?.decision == .always)

        // A turn that read outside content asks again, grant or not (SECURITY T2).
        let (_, again) = await h.approved("applenotes.list", tainted: true)
        let request = try #require(again)
        #expect(request.tainted && !request.canAlways)
    }

    @Test func theUserCanSwitchItOff() async throws {
        let h = try MacAppsEnv()
        try await h.env.permissions.setPolicy(GuardPolicy(disabled: [.macApps]))
        let out = await h.run("applenotes.list")
        #expect(out.wasDenied)
        #expect(out.text == "Using Apple Notes and Reminders is turned off in Sidefolk's Permissions settings.")
        #expect(h.fake.calls.isEmpty, "nothing reached Notes")
    }

    @Test func otherAgentsNeverGetTheseTools() async throws {
        let h = try MacAppsEnv()
        let mine = h.env.registry.specs.filter { $0.capabilities.contains(.macApps) }
        #expect(mine.map(\.name).sorted() == ["applenotes.copy", "applenotes.list", "applenotes.read", "applenotes.remove", "applereminders.list"])
        #expect(mine.allSatisfy { !$0.external && !ExternalToolPolicy.isExposed($0.name) })
        #expect(mine.allSatisfy { $0.risk >= .medium })
    }

    @Test func pagesThroughABigLibraryWithACapPerStep() async throws {
        let h = try MacAppsEnv(FakeAppleEvents(.large(120)))
        let (first, _) = await h.approved("applenotes.list")
        let text = try #require(first.result?.text)
        #expect(text.contains("Notes 1–50 of 120 (all folders), newest first:"))
        #expect(text.contains("More: call again with offset 50."))
        #expect(text.contains("“Note 120”") && !text.contains("“Note 70”"))
        #expect(text.count < UntrustedText.maxBytes, "a page fits in one untrusted result")

        let (last, _) = await h.approved("applenotes.list", ["offset": 100])
        let lastText = try #require(last.result?.text)
        #expect(lastText.contains("Notes 101–120 of 120"))
        #expect(!lastText.contains("More:"))
        // Later pages reuse the list Notes gave for the first, so pages line up.
        #expect(h.fake.calls.filter { $0 == "notes.index" }.count == 1)
        #expect(h.fake.params(of: "notes.snippets").allSatisfy { ($0["ids"]?.arrayValue?.count ?? 0) <= 50 })

        // Asking for more than a page is refused before anything runs.
        let tooMany = await h.run("applenotes.list", ["limit": 80])
        #expect(tooMany.failure?.message == "That request didn't fit the tool: “limit” must be at most 50.")
    }

    @Test func narrowsByFolderOrTitle() async throws {
        let h = try MacAppsEnv()
        let (recipes, _) = await h.approved("applenotes.list", ["folder": "Recipes"])
        let r = try #require(recipes.result?.text)
        #expect(r.contains("“Sourdough”") && !r.contains("“Pasta carbonara”"))

        let (weeknight, _) = await h.approved("applenotes.list", ["folder": "icloud/recipes/weeknight"])
        #expect(weeknight.result?.text.contains("“Pasta carbonara”") == true)

        let (query, card) = await h.approved("applenotes.list", ["query": "TRIP"])
        #expect(card?.summary == "Read the titles, folders and dates of up to 50 Apple Notes whose title has “TRIP”")
        #expect(query.result?.text.contains("Notes 1–1 of 1 (all folders, title has “TRIP”)") == true)

        let (none, _) = await h.approved("applenotes.list", ["folder": "Taxes"])
        #expect(none.result?.text.contains("No folder matches “Taxes”. Use one of the folders above.") == true)
    }

    // MARK: Reading

    @Test func readGivesMarkdownAndNamesAttachments() async throws {
        let h = try MacAppsEnv()
        _ = await h.approved("applenotes.list")
        let (out, card) = await h.approved("applenotes.read", ["ids": [.string(Self.handle(2)), .string(Self.handle(3))]], tainted: true)
        #expect(card?.summary == "Read 2 notes from Apple Notes in “Notes”")
        let result = try #require(out.result)
        #expect(result.untrusted)
        #expect(result.text.contains("Note \(Self.handle(2)) “Trip to Lyon”\niCloud › Notes · created"))
        #expect(result.text.contains("Attachments (not read): ticket.pdf"))
        #expect(result.text.contains("Train at 9:12, [hotel](https://example.com/hotel)."))
        #expect(result.text.contains("[image: ticket.pdf]"))
        #expect(!result.text.contains("Trip to Lyon\nTrip to Lyon"), "the title isn't repeated as the first line")
        #expect(result.text.contains("It is locked: the user has to unlock it in Notes before it can be read."))
    }

    @Test func readCapsEachStep() async throws {
        let h = try MacAppsEnv()
        let ids: [JSONValue] = (1...6).map { .string(Self.handle($0)) }
        let out = await h.run("applenotes.read", ["ids": .array(ids)])
        #expect(out.failure?.message == "That request didn't fit the tool: “ids” has too many entries (at most 5).")
        #expect(h.fake.calls.isEmpty)
    }

    @Test func unknownIdsSayToListAgain() async throws {
        let h = try MacAppsEnv()
        let (out, _) = await h.approved("applenotes.read", ["ids": ["n00000000"]])
        #expect(out.result?.text.contains("Not found (deleted, or list the notes again): n00000000") == true)
        // An id it hadn't seen made it ask Notes for a fresh list once.
        #expect(h.fake.calls.filter { $0 == "notes.index" }.count == 2)
    }

    // MARK: Permission and failures

    @Test func refusedByMacOSShowsTheWayToSystemSettings() async throws {
        let h = try MacAppsEnv()
        h.fake.deny()
        let (out, _) = await h.approved("applenotes.list")
        #expect(!out.isOK)
        let result = try #require(out.result)
        #expect(result.isError && !result.untrusted)
        #expect(out.activity.card?.url == PrivacyPane.automation.rawValue)
        #expect(PrivacyPane.isKnown(out.activity.card?.url))
        #expect(out.activity.card?.title == "Sidefolk needs your OK to use Notes")
        #expect(out.modelText.contains("System Settings › Privacy & Security › Automation by switching on Notes under Sidefolk"))
        #expect(out.modelText.contains("don't try again until they say they have"))
    }

    @Test func aNotesThatDoesntAnswerIsAClearMessage() async throws {
        let h = try MacAppsEnv()
        h.fake.hang()
        let (out, _) = await h.approved("applenotes.list")
        #expect(out.failure?.message == "Notes didn't answer in time. Nothing was changed.")
        #expect(out.failure?.recovery == "If macOS is asking whether Sidefolk may use Notes, answer it, then try again.")
    }

    @Test func onlyBuiltInReadsAreLabelledAsReading() async throws {
        let h = try MacAppsEnv()
        h.env.registry.register([ProbeTool(name: "ext.probe.read", risk: .medium, capabilities: [.extensions], mutates: false),
                                 ProbeTool(name: "test.read", risk: .medium, mutates: false)])
        let (_, ext) = await h.approved("ext.probe.read")
        let (_, own) = await h.approved("test.read")
        #expect(ext?.readsOnly == false, "an extension's word that it changes nothing isn't enough")
        #expect(own?.readsOnly == true)
    }

    @Test func onlyThePrivacyPaneIsAKnownLink() {
        #expect(PrivacyPane.isKnown("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"))
        #expect(!PrivacyPane.isKnown("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"))
        #expect(!PrivacyPane.isKnown("https://example.com"))
        #expect(!PrivacyPane.isKnown(nil))
    }
}
