import Foundation
import Testing
@testable import SidefolkCore

/// Misparses found by feeding the local intent parser ~900 realistic phrasings. The contract used throughout:
/// the parser returns either exactly the right intent or nil (the AI takes over); a confident wrong answer is the bug.
/// "Now" is Wednesday 22 October 2025, 10:00 UTC (see QASupport).
@Suite struct QAIntentParserReminders {
    private func check(_ text: String, _ expected: LocalIntent, now: Date = QA.wed10, sourceLocation: SourceLocation = #_sourceLocation) {
        let got = QA.parse(text, now: now)
        #expect(QA.isCorrectOrNil(got, expected), "“\(text)” → \(QA.describe(got)); expected \(QA.describe(expected)) or nil", sourceLocation: sourceLocation)
    }

    // Expected: "on 2025-12-01" is all time words, so the title is "Renew" (today it is "On to renew").
    @Test func isoDateAfterOnLeavesNoDanglingWord() {
        check("remind me on 2025-12-01 to renew", .remind(title: "Renew", when: QA.at(2025, 12, 1), recurrence: nil))
        check("remind me on 2025-12-01 at 5pm to renew", .remind(title: "Renew", when: QA.at(2025, 12, 1, 17), recurrence: nil))
    }

    // Expected: "the 1st / 15th of every month" is a monthly series on that day (today: a one-off, titled "Every month to pay rent").
    @Test(arguments: [
        ("remind me on the 1st of every month to pay rent", 1, 11),
        ("remind me on the 15th of every month to pay rent", 15, 11),
        ("remind me on the 3rd of each month to pay rent", 3, 11),
    ]) func theNthOfEveryMonthRepeats(text: String, day: Int, month: Int) {
        check(text, .remind(title: "Pay rent", when: QA.at(2025, month, day), recurrence: Recurrence(frequency: .monthly)))
    }

    // Expected: "first" is understood (or the phrase goes to the AI); today it makes a monthly series on the 22nd (today's date).
    @Test func onTheFirstOfEveryMonthIsNotTodaysDayOfMonth() {
        check("remind me on the first of every month to pay rent", .remind(title: "Pay rent", when: QA.at(2025, 11, 1), recurrence: Recurrence(frequency: .monthly)))
    }

    // Expected: the part of day after a weekly repeat is used (18:00), not dropped into the title ("Evening to plan" at 09:00).
    @Test func everySundayEveningUsesTheEvening() {
        check("remind me every sunday evening to plan", .remind(title: "Plan", when: QA.at(2025, 10, 26, 18), recurrence: Recurrence(frequency: .weekly, weekdays: [7])))
    }

    // Expected: all three weekdays (today only "mon" is read and "Wed fri at 7 to run" lands in the title).
    @Test func everyMonWedFriWithoutCommas() {
        check("remind me every mon wed fri at 8am to run",
              .remind(title: "Run", when: QA.at(2025, 10, 24, 8), recurrence: Recurrence(frequency: .weekly, weekdays: [1, 3, 5])))
    }

    // Expected: "thursday the 6th" is 6 November (today: tomorrow, Thursday 23 Oct, with "the 6th" left in the title).
    @Test func weekdayTheNthIsTheNthNotTheWeekday() {
        check("remind me on thursday the 6th to call mom", .remind(title: "Call mom", when: QA.at(2025, 11, 6), recurrence: nil))
    }

    // Expected: "the 28th of next month" is 28 November (today: 28 October, with "Next month" in the title).
    @Test func nthOfNextMonthIsNextMonth() {
        check("remind me on the 28th of next month to call", .remind(title: "Call", when: QA.at(2025, 11, 28), recurrence: nil))
    }

    // Expected: "tonight at 12" is midnight at the end of today (Thu 00:00); today it is 12:00 noon, two hours from now.
    @Test(arguments: ["remind me tonight at 12 to sleep", "remind me at 12 tonight to sleep"])
    func tonightAtTwelveIsMidnight(text: String) {
        check(text, .remind(title: "Sleep", when: QA.at(2025, 10, 23, 0), recurrence: nil))
    }

    // Expected: French-style "9h30" is 09:30 (today: 09:00 with "H30 to call" in the title, or 21:00 today).
    @Test(arguments: [
        ("remind me tomorrow at 9h30 to call mom", QA.at(2025, 10, 23, 9, 30)),
        ("remind me tomorrow at 9h to call mom", QA.at(2025, 10, 23, 9)),
        ("remind me at 17h30 to call mom", QA.at(2025, 10, 22, 17, 30)),
    ]) func hourSeparatedByTheLetterH(text: String, when: Date) {
        check(text, .remind(title: "Call mom", when: when, recurrence: nil))
    }

    // Expected: nil. "tell me X at <time>" is a question for the AI, not a reminder titled "A joke" / "What you think".
    @Test(arguments: [
        "tell me a joke in 5 minutes", "tell me about quantum computing tomorrow", "tell me what you think at 5",
        "tell me a story tonight", "tell me when it's 5pm",
    ]) func tellMeIsNotRemindMe(text: String) {
        #expect(QA.parse(text) == nil, "“\(text)” → \(QA.describe(QA.parse(text)))")
    }

    // Expected: time words the parser does not know are never left inside the reminder's title (or the phrase goes to the AI).
    // Today: .needsTime(title: "In about 5 minutes to call mom") and friends, or a reminder titled "At about 9 to call mom".
    @Test(arguments: [
        ("remind me in about 5 minutes to call mom", QA.at(2025, 10, 22, 10, 5)),
        ("remind me in a fortnight to call mom", QA.at(2025, 11, 5)),
        ("remind me in forty five minutes to call mom", QA.at(2025, 10, 22, 10, 45)),
        ("remind me at half past 3 to call mom", QA.at(2025, 10, 22, 15, 30)),
        ("remind me at a quarter to 6 to call mom", QA.at(2025, 10, 22, 17, 45)),
        ("remind me at 5.30pm to call mom", QA.at(2025, 10, 22, 17, 30)),
        ("remind me tomorrow at about 9 to call mom", QA.at(2025, 10, 23, 9)),
        ("remind me tomorrow at 9ish to call mom", QA.at(2025, 10, 23, 9)),
        ("remind me to call mom at 12 noon", QA.at(2025, 10, 22, 12)),
        ("remind me in 5 minutes' time to call mom", QA.at(2025, 10, 22, 10, 5)),
    ]) func unknownTimeWordsDoNotEndUpInTheTitle(text: String, when: Date) {
        check(text, .remind(title: "Call mom", when: when, recurrence: nil))
    }

    // Expected: nil. Two different times cannot be one reminder; today it fires at the last one and keeps "at 8am and" in the title.
    @Test(arguments: [
        "remind me to take pills at 8am and 8pm", "remind me to take pills every day at 8am and 8pm",
        "remind me to call mom at 5 or 6", "remind me to call mom on monday or tuesday",
    ]) func twoTimesAreNotGuessed(text: String) {
        #expect(QA.parse(text) == nil, "“\(text)” → \(QA.describe(QA.parse(text)))")
    }

    // Expected: schedule words ("every", "except", "last") never survive in a title, and "every …" never becomes a one-off.
    @Test(arguments: [
        "remind me every day except sunday to run", "remind me every last friday of the month to review",
        "remind me to water the plants every first monday",
    ]) func scheduleWordsNeverLeakIntoTheTitle(text: String) {
        let got = QA.parse(text)
        if case .remind(let title, _, let recurrence, _)? = got {
            let lower = title.lowercased()
            #expect(!["every", "except", "last", "first"].contains { lower.contains($0) } && recurrence != nil,
                    "“\(text)” → \(QA.describe(got))")
        }
    }

    // Expected: "this weekend" on Saturday morning is today or tomorrow (today it jumps to next Saturday, 7 days away).
    @Test func thisWeekendOnASaturdayIsNotNextWeek() {
        let saturday = QA.at(2025, 10, 25, 10)
        let got = QA.parse("remind me this weekend to call", now: saturday)
        if case .remind(_, let when, _, _)? = got {
            #expect(when < QA.at(2025, 10, 27, 0), "→ \(QA.describe(got))")
        }
    }

    // Expected: "N units from/after <day>" offsets that day (today the offset is silently dropped and "1 week" stays in the title).
    @Test(arguments: [
        ("remind me to call mom 1 week from tomorrow", QA.at(2025, 10, 30)),
        ("remind me to call mom 3 days after tomorrow", QA.at(2025, 10, 26)),
        ("remind me to call mom 3 weeks from monday", QA.at(2025, 11, 17)),
    ]) func offsetsFromADayAreApplied(text: String, when: Date) {
        check(text, .remind(title: "Call mom", when: when, recurrence: nil))
    }

    // Expected: "tomorrow, thank you" style closers are removed but "say thank you" keeps its words.
    @Test func reminderTitleKeepsThankYouWhenItIsTheTask() {
        check("remind me tomorrow to say thank you", .remind(title: "Say thank you", when: QA.at(2025, 10, 23), recurrence: nil))
    }
}

@Suite struct QAIntentParserNotesAndSearch {
    private func note(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> (kind: NotebookItem.Kind, text: String, collection: String?)? {
        if case .note(let kind, let body, let collection, _)? = QA.parse(text) { return (kind, body, collection) }
        return nil
    }

    // Expected: text typed after "note:" is saved as typed. Today the trailing "thank you", "?" , "!" , "." and every newline are removed.
    @Test(arguments: [
        ("note: say thank you", "say thank you"),
        ("note: should we use pnpm?", "should we use pnpm?"),
        ("idea: what if folks had hats?", "what if folks had hats?"),
        ("note: wow!", "wow!"),
        ("note: shopping list\n- milk\n- eggs", "shopping list\n- milk\n- eggs"),
        ("note: line one\n\n    indented code\nline three", "line one\n\n    indented code\nline three"),
    ]) func noteTextIsSavedAsTyped(text: String, expected: String) {
        let got = note(text)
        #expect(got == nil || got?.text == expected, "“\(text.replacingOccurrences(of: "\n", with: "⏎"))” → “\((got?.text ?? "nil").replacingOccurrences(of: "\n", with: "⏎"))”")
    }

    // Expected: a time word after "for" is not a project; nothing is filed in a notebook collection called "tomorrow".
    @Test(arguments: [
        "task for tomorrow: call the dentist", "todo for friday: send invoice", "idea for today: a new thing",
        "note for later: check this", "task for next week: plan sprint",
    ]) func timeWordIsNotACollection(text: String) {
        let got = QA.parse(text)
        if case .note(_, _, let collection, _)? = got { #expect(collection == nil, "“\(text)” → \(QA.describe(got))") }
    }

    // Expected: "3:30" is not split at the colon (today: text "30 meeting: prep slides" in a new collection called "3").
    @Test func clockTimeInsideTheCollectionPhraseSurvives() {
        let got = QA.parse("note about 3:30 meeting: prep slides")
        if case .note(_, let text, let collection, _)? = got {
            #expect(collection == nil && text.contains("3:30"), "→ \(QA.describe(got))")
        }
    }

    // Expected: a URL is never cut at its colon (today: collection "https", text "//example.com: foo").
    @Test(arguments: ["idea for https://example.com: foo", "note about http://example.com/a: b"])
    func urlBeforeTheColonIsNotACollection(text: String) {
        let got = QA.parse(text)
        if case .note(_, let body, let collection, _)? = got {
            #expect(collection == nil && body.contains("example.com"), "“\(text)” → \(QA.describe(got))")
        }
    }

    // Expected: filler words are not project names (today "add milk to my list" creates a collection named "my").
    @Test(arguments: ["add milk to my list", "put milk on the list", "add milk to the list"])
    func fillerWordsAreNotCollections(text: String) {
        let got = QA.parse(text)
        if case .note(_, _, let collection, _)? = got { #expect(collection == nil, "“\(text)” → \(QA.describe(got))") }
    }

    // Expected: "todo list" alone is not a task called "list" (it is asking for the list); "todo list: x" saves "x".
    @Test func todoListIsNotATaskCalledList() {
        #expect(QA.parse("todo list") == nil, "→ \(QA.describe(QA.parse("todo list")))")
        let got = note("todo list: call dentist")
        #expect(got == nil || got?.text == "call dentist", "→ \(got?.text ?? "nil")")
    }

    // Expected: "jot down: buy milk" saves "buy milk" (today: "down: buy milk").
    @Test func jotDownWithAColon() {
        let got = note("jot down: buy milk")
        #expect(got == nil || got?.text == "buy milk", "→ \(got?.text ?? "nil")")
    }

    // Expected: "remember this" / "remember that" alone save nothing (today: a note whose whole text is "this" / "that").
    @Test(arguments: ["remember this", "remember that"])
    func rememberWithNothingToRemember(text: String) {
        #expect(QA.parse(text) == nil, "“\(text)” → \(QA.describe(QA.parse(text)))")
    }

    // Expected: the URL is watched as written (today the closing ")" is trimmed: …/Swift_(programming_language).
    @Test(arguments: [
        "watch https://en.wikipedia.org/wiki/Swift_(programming_language)",
        "tell me when https://en.wikipedia.org/wiki/Swift_(programming_language) changes",
    ]) func parenthesisInsideAnAddressIsKept(text: String) {
        let url = "https://en.wikipedia.org/wiki/Swift_(programming_language)"
        let got = QA.parse(text)
        #expect(QA.isCorrectOrNil(got, .watch(WatchIntent(kind: "url_change", target: url))), "“\(text)” → \(QA.describe(got))")
    }

    // Expected: a preposition on its own is not a search term (today: search for “for” / “about”).
    @Test(arguments: ["search for", "find ideas for", "find notes about"])
    func prepositionAloneIsNotASearchQuery(text: String) {
        if case .find(let query, _, _)? = QA.parse(text) { #expect(!["for", "about"].contains(query), "“\(text)” searches for “\(query)”") }
    }
}

@Suite struct QAIntentParserSlashAndQuiet {
    // Expected: the slash shortcut accepts the same words as the plain sentence. Today "/quiet for 1h" becomes
    // "quiet for for 1h" and "/quiet till 5" becomes "quiet for till 5"; neither is understood (they fall through to the AI).
    @Test(arguments: [
        ("/quiet until 5pm", QA.at(2025, 10, 22, 17)), ("/q until 5pm", QA.at(2025, 10, 22, 17)),
        ("/quiet for 1h", QA.at(2025, 10, 22, 11)), ("/quiet for 1 hour", QA.at(2025, 10, 22, 11)),
        ("/quiet 1h", QA.at(2025, 10, 22, 11)), ("/quiet till 5", QA.at(2025, 10, 22, 17)),
    ]) func slashQuietTakesTheSameWordsAsTheSentence(text: String, until: Date) {
        let expanded = LocalIntentRunner.expandSlash(text)
        let got = QA.parse(expanded)
        #expect(got == .quiet(until: until), "“\(text)” → “\(expanded)” → \(QA.describe(got))")
    }
}
