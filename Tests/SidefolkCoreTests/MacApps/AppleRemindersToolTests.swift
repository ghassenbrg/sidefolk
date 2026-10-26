import Foundation
import Testing
@testable import SidefolkCore

@Suite struct AppleRemindersToolTests {
    @Test func listsOpenRemindersSoonestFirst() async throws {
        let h = try MacAppsEnv()
        let (out, card) = await h.approved("applereminders.list")
        let request = try #require(card)
        #expect(request.risk == .medium && request.readsOnly)
        #expect(request.summary == "Read your open reminders in Apple Reminders")
        let result = try #require(out.result)
        #expect(result.untrusted)
        let text = result.text
        #expect(text.hasPrefix("Apple Reminders on this Mac: 3 open reminders in 2 lists: Reminders (1); Groceries (2)"))
        #expect(text.contains("Open reminders 1–3 of 3 (all lists), soonest due first:"))
        #expect(text.contains("- “Call the bank” · Reminders · due ") && text.contains("high priority · flagged\n  Ask about fees"))
        #expect(!text.contains("Done already"), "completed reminders aren't listed")
        let order = ["Call the bank", "Eggs", "Milk"].map { text.range(of: $0)!.lowerBound }
        #expect(order == order.sorted())
        // An all-day reminder shows its day, without a time.
        let eggs = try #require(text.split(separator: "\n").first { $0.contains("“Eggs”") })
        #expect(eggs.hasSuffix("· Groceries · due \(ToolFormat.day(TestEnv.referenceDate.addingTimeInterval(86_400)))"))
    }

    @Test func narrowsToOneList() async throws {
        let h = try MacAppsEnv()
        let (out, card) = await h.approved("applereminders.list", ["list": "groceries"])
        #expect(card?.summary == "Read your open reminders in the list “groceries” in Apple Reminders")
        let text = try #require(out.result?.text)
        #expect(text.contains("Open reminders 1–2 of 2 (list “groceries”)"))
        #expect(!text.contains("“Call the bank”"))
    }

    @Test func refusedByMacOSNamesReminders() async throws {
        let h = try MacAppsEnv()
        h.fake.deny()
        let (out, _) = await h.approved("applereminders.list")
        #expect(out.activity.card?.title == "Sidefolk needs your OK to use Reminders")
        #expect(out.modelText.contains("switching on Reminders under Sidefolk"))
    }
}
