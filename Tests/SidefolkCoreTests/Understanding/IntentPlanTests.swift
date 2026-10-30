import Foundation
import Testing
@testable import SidefolkCore

/// The one bar's "Will do" (D64): what Return would do, in parts, and the tool that runs it, from the same parse.
@Suite struct IntentPlanTests {
    let now = TimeTest.wednesday10
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func plan(_ text: String) -> IntentPlan? {
        parser.parse(text, now: now, knownCollections: ["Groceries"])?.plan(now: now, calendar: TimeTest.calendar())
    }

    @Test func aReminderShowsItsDayAndTime() {
        #expect(plan("remind me tomorrow at 5 to call the bank")
                == IntentPlan(kind: "Reminder", title: "Call the bank", chips: ["Tomorrow", "17:00"], tool: "reminders.create"))
    }

    @Test func aNoteShowsWhereItGoes() {
        let note = plan("add milk to groceries")
        #expect(note?.tool == "notes.save" && note?.chips == ["Groceries"])
        #expect(plan("note: folks could have their own voice")?.chips == ["Inbox"])
    }

    @Test func aWatchNamesWhatItWatches() {
        let watch = plan("tell me when example.com/pricing changes")
        #expect(watch?.tool == "watch.create" && watch?.title.contains("example.com/pricing") == true)
    }

    @Test func whatRunsNothingYetNamesNoTool() {
        #expect(plan("quiet for an hour")?.tool == nil)
    }
}
