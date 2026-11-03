import Foundation
import Testing
@testable import SidefolkCore

/// Reads Sidefolk answers by itself, with no AI set up.
@Suite struct IntentListingTests {
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func listing(_ text: String) -> Listing? {
        if case .listing(let found)? = parser.parse(text, now: TimeTest.wednesday10)?.intent { return found }
        return nil
    }

    @Test func plainWords() {
        let cases: [(String, Listing)] = [
            ("list my reminders", .reminders(nil)), ("show me all my reminders", .reminders(nil)), ("what are my reminders?", .reminders(nil)),
            ("what reminders do I have tomorrow", .reminders(.tomorrow)), ("show my upcoming reminders this week", .reminders(.thisWeek)),
            ("list my watchers", .watchers), ("show the watches", .watchers), ("what am I watching?", .watchers), ("what are you watching", .watchers),
            ("what's on my plate", .agenda(nil)), ("what's on my plate today", .agenda(.today)), ("what's on today", .agenda(.today)),
            ("what do I have tomorrow", .agenda(.tomorrow)), ("my agenda", .agenda(nil)),
            ("what's due", .due(nil)), ("which tasks are due this week", .due(.thisWeek)), ("what is due tomorrow?", .due(.tomorrow)), ("tasks due today", .due(.today)),
        ]
        for (text, expected) in cases { #expect(listing(text) == expected, "\(text)") }
        #expect(parser.parse("list my watchers", now: TimeTest.wednesday10)?.hint.hasSuffix("no AI") == true)
    }

    @Test func otherSentencesAreLeftAlone() {
        for text in ["what's on my mind about the reminders", "list my reasons for leaving", "what's due diligence", "remind me to list my reminders tomorrow at 9",
                     "what am I watching on Netflix tonight", "what do I have to do to renew a passport"] {
            #expect(listing(text) == nil, "\(text)")
        }
        // Reminding and watching keep their meaning.
        if case .remind? = parser.parse("remind me tomorrow at 9 to stretch", now: TimeTest.wednesday10)?.intent {} else { Issue.record("a reminder stays one") }
    }

    @Test func eachRunsItsToolThroughTheExecutorWithoutAI() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-listing-\(UUID().uuidString)", isDirectory: true)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: ManualClock(TestEnv.referenceDate))
        let runner = LocalIntentRunner(runtime: runtime)
        _ = try await runtime.scheduler.create(title: "Stretch", at: TestEnv.referenceDate.addingTimeInterval(3600), source: "user")
        let saved = await runtime.executor.execute(name: "notes.save", input: ["text": "Send the invoice", "kind": "task", "due": "in 2 days"], caller: .user)
        #expect(saved.isOK)

        func card(_ listing: Listing) async throws -> ResultCard {
            guard case .card(let card, _, _) = await runner.run(.listing(listing)) else {
                Issue.record("\(listing) should give a card")
                throw CancellationError()
            }
            return card
        }
        #expect(try await card(.reminders(nil)).detail?.contains("Stretch") == true)
        #expect(try await card(.reminders(.thisWeek)).detail?.contains("Stretch") == true)
        #expect(try await card(.watchers).title == "Nothing is being watched")
        #expect(try await card(.agenda(nil)).subtitle?.isEmpty == false)
        #expect(try await card(.due(nil)).detail?.contains("Send the invoice") == true)
        #expect(try await card(.due(.thisWeek)).detail?.contains("Send the invoice") == true)
        #expect(try await card(.due(.today)).title != "1 items")
    }
}
