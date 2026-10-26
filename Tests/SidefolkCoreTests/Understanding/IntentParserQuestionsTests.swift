import Foundation
import Testing
@testable import SidefolkCore

/// Watches without an address, local addresses, times that cannot be used, urgency and lists:
/// the parser either understands all of it or asks, and never lets a time word into a title.
/// "Now" is Wednesday 22 October 2025, 10:00 UTC.
@Suite struct IntentParserQuestionsTests {
    let now = TimeTest.wednesday10
    let known = ["Sidefolk", "Work"]
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func parse(_ text: String, known: [String]? = nil) -> ParsedIntent? { parser.parse(text, now: now, knownCollections: known ?? self.known) }
    func intent(_ text: String) -> LocalIntent? { parse(text)?.intent }
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date { TimeTest.date(y, m, d, h, min) }

    // MARK: Watches without an address

    @Test func aServerWithoutAnAddressAsksWhich() {
        let p = parse("tell me when the server is back up")
        #expect(p?.intent == .needsTarget(kind: "site_status", becomes: "up"))
        #expect(p?.hint == "Watch · which address? · no AI")
        #expect(intent("tell me when the api is up again") == .needsTarget(kind: "site_status", becomes: "up"))
        #expect(intent("let me know when my site goes down") == .needsTarget(kind: "site_status", becomes: "down"))
        #expect(intent("tell me if the server is down") == .needsTarget(kind: "site_status", becomes: "down"))
        #expect(intent("notify me when my dev server comes back online") == .needsTarget(kind: "site_status", becomes: "up"))
        #expect(intent("tell me when the staging api is back") == .needsTarget(kind: "site_status", becomes: "up"))
        #expect(intent("remind me when the website is live") == .needsTarget(kind: "site_status", becomes: "up"))
    }

    @Test func aPageWithoutAnAddressAsksWhich() {
        #expect(intent("tell me when my site changes") == .needsTarget(kind: "url_change", becomes: nil))
        #expect(intent("let me know when the pricing page updates") == .needsTarget(kind: "url_change", becomes: nil))
    }

    @Test func anAddressStillWinsOverAsking() {
        #expect(intent("tell me when localhost:3000 is back up") == .watch(WatchIntent(kind: "site_status", target: "http://localhost:3000")))
        #expect(intent("tell me when example.com goes down") == .watch(WatchIntent(kind: "site_status", target: "https://example.com", contains: "down")))
    }

    @Test func otherVagueWatchesStillGoToTheAI() {
        for text in ["tell me when the build finishes", "tell me when it finishes", "tell me when my friend's website is down",
                     "tell me when the file changes", "tell me when the weather is nice", "tell me when it's up"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func theAnswerFinishesTheWatch() {
        let up = parser.watch(address: "localhost:3000", kind: "site_status", becomes: "up")
        #expect(up?.intent == .watch(WatchIntent(kind: "site_status", target: "http://localhost:3000")))
        #expect(up?.hint == "Watch localhost:3000 is up · no AI")
        #expect(parser.watch(address: "3000", kind: "site_status", becomes: "up")?.intent == up?.intent, "a bare port means this Mac")
        #expect(parser.watch(address: " 127.0.0.1:8080 ", kind: "site_status", becomes: "down")?.intent
            == .watch(WatchIntent(kind: "site_status", target: "http://127.0.0.1:8080", contains: "down")))
        #expect(parser.watch(address: "example.com/status", kind: "url_change", becomes: nil)?.intent
            == .watch(WatchIntent(kind: "url_change", target: "https://example.com/status")))
        for nonsense in ["", "nope", "the server", "99999", "1"] {
            #expect(parser.watch(address: nonsense, kind: "site_status", becomes: "up") == nil, "“\(nonsense)”")
        }
    }

    // MARK: Addresses on this Mac and the home network

    @Test func localAddressesTypedWithoutASchemeAreHttp() {
        for (text, url) in [("localhost:3000", "http://localhost:3000"), ("127.0.0.1:8080", "http://127.0.0.1:8080"),
                            ("myhost.local:5000", "http://myhost.local:5000"), ("192.168.1.5/status", "http://192.168.1.5/status"),
                            ("app.localhost:8000", "http://app.localhost:8000")] {
            #expect(intent("tell me when \(text) is up") == .watch(WatchIntent(kind: "site_status", target: url)), "\(text)")
        }
        #expect(intent("watch myhost.local:5000/health") == .watch(WatchIntent(kind: "url_change", target: "http://myhost.local:5000/health")))
    }

    @Test func aParenthesisThatClosesAnAddressIsKept() {
        let url = "https://en.wikipedia.org/wiki/Swift_(programming_language)"
        #expect(intent("watch \(url)") == .watch(WatchIntent(kind: "url_change", target: url)))
        #expect(intent("watch (example.com/a)") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/a")))
    }

    // MARK: Times that cannot be used

    @Test func wordsForATimeThatCannotBeUsedAreAskedAboutWithACleanTitle() {
        #expect(intent("remind me yesterday to call mom") == .needsTime(title: "Call mom", reason: "Yesterday has passed."))
        #expect(intent("remind me to call mom yesterday") == .needsTime(title: "Call mom", reason: "Yesterday has passed."))
        #expect(intent("remind me later to water plants") == .needsTime(title: "Water plants", reason: "Later isn't a time."))
        #expect(intent("remind me to water plants sometime") == .needsTime(title: "Water plants", reason: "Sometime isn't a time."))
        #expect(intent("remind me at 25:00 to test") == .needsTime(title: "Test", reason: "25:00 isn't a time."))
        #expect(intent("remind me to test at 99:99") == .needsTime(title: "Test", reason: "99:99 isn't a time."))
        #expect(intent("remind me last friday to pay rent") == .needsTime(title: "Pay rent", reason: "Last friday has passed."))
        #expect(intent("remind me to call mom 2 days ago") == .needsTime(title: "Call mom", reason: "That time has passed."))
        #expect(parse("remind me yesterday to call mom")?.hint == "Reminder · I'll ask when · no AI")
    }

    @Test func aTimeThatPassedSaysSo() {
        #expect(intent("remind me this morning to stretch") == .needsTime(title: "Stretch", reason: "This morning has passed."))
        #expect(intent("remind me 2020-01-01 to time travel") == .needsTime(title: "Time travel", reason: "2020-01-01 has passed."))
    }

    @Test func aReminderWithNoTimeAtAllHasNoReason() {
        #expect(intent("remind me to call mom") == .needsTime(title: "Call mom"))
        #expect(intent("remind me to read the later chapters") == .needsTime(title: "Read the later chapters"), "a word inside the title is just a word")
    }

    @Test func twoStatementsAboutWhenAreNotGuessed() {
        #expect(parse("remind me yesterday to call mom at 5") == nil)
        #expect(parse("remind me later to call mom tomorrow") == nil)
    }

    @Test func usableTimesStillWorkNextToTheNewRules() {
        #expect(intent("remind me tomorrow at 14:30 to call mom") == .remind(title: "Call mom", when: at(2025, 10, 23, 14, 30), recurrence: nil))
        #expect(intent("remind me at 5:30pm to call mom") == .remind(title: "Call mom", when: at(2025, 10, 22, 17, 30), recurrence: nil))
        #expect(intent("remind me tomorrow to say thank you") == .remind(title: "Say thank you", when: at(2025, 10, 23), recurrence: nil))
        #expect(intent("remind me in 2 hours to check the oven, thanks") == .remind(title: "Check the oven", when: at(2025, 10, 22, 12), recurrence: nil))
    }

    @Test func theAnswerToWhenReadsTheSameSpellings() {
        for (text, date) in [("half past 3", at(2025, 10, 22, 15, 30)), ("in about 5 minutes", at(2025, 10, 22, 10, 5)), ("tomorrow 9h30", at(2025, 10, 23, 9, 30)),
                             ("at 5.30pm", at(2025, 10, 22, 17, 30)), ("tomorrow at 9ish", at(2025, 10, 23, 9))] {
            let found = parser.parseTime(text, now: now)
            #expect(found?.date == date && found?.remaining == "", "\(text) → \(found.map { TimeTest.show($0.date) } ?? "nil")")
        }
        #expect(parser.parseTime("never mind", now: now) == nil)
        #expect(parser.parseTime("tomorrow at 10 dentist", now: now)?.remaining == "dentist", "more than a time: the caller can tell")
    }

    // MARK: Urgency

    @Test(arguments: [
        "remind me urgently to call the bank tomorrow", "urgent: remind me to call the bank tomorrow",
        "important: remind me to call the bank tomorrow", "remind me to call the bank tomorrow (important)",
        "remind me to call the bank tomorrow, it's urgent", "remind me important: call the bank tomorrow",
        "set an urgent reminder to call the bank tomorrow", "important reminder: call the bank tomorrow",
        "urgently remind me to call the bank tomorrow", "remind me to call the bank tomorrow urgently",
        "remind me (urgent) to call the bank tomorrow",
    ])
    func urgencyMakesAReminderImportant(text: String) {
        let p = parse(text)
        #expect(p?.intent == .remind(title: "Call the bank", when: at(2025, 10, 23), recurrence: nil, important: true), "\(text)")
        #expect(p?.hint == "Reminder · Tomorrow 09:00 · important · no AI")
    }

    @Test func importantWordsInsideATitleAreJustWords() {
        #expect(intent("remind me tomorrow to read the important email") == .remind(title: "Read the important email", when: at(2025, 10, 23), recurrence: nil))
        #expect(intent("remind me to review the urgent list tomorrow") == .remind(title: "Review the urgent list", when: at(2025, 10, 23), recurrence: nil))
        #expect(parse("important: buy milk") == nil, "not a reminder")
    }

    @Test func urgencyTravelsWithAQuestionAboutWhen() {
        #expect(intent("urgent: remind me to call the bank") == .needsTime(title: "Call the bank", reason: nil, important: true))
        #expect(intent("remind me urgently yesterday to call the bank") == .needsTime(title: "Call the bank", reason: "Yesterday has passed.", important: true))
    }

    // MARK: Lists

    @Test func aListThatDoesNotExistIsMadeAsAListWithACapitalName() {
        let p = parse("add milk to my groceries list")
        #expect(p?.intent == .note(kind: .task, text: "milk", collection: "Groceries", collectionKind: .list))
        #expect(p?.hint == "Task → Groceries · no AI")
        #expect(intent("add milk to my reading list") == .note(kind: .task, text: "milk", collection: "Reading", collectionKind: .list))
        // The words as typed: the capital letter on the note's title comes when it is saved.
        #expect(intent("add milk to my Groceries list") == .note(kind: .task, text: "milk", collection: "Groceries", collectionKind: .list))
    }

    @Test func aKnownListKeepsItsOwnSpelling() {
        #expect(intent("add milk to my shopping list") == .note(kind: .task, text: "milk", collection: "Shopping", collectionKind: .list))
        let p = parser.parse("add milk to my shopping list", now: now, knownCollections: ["Shopping run"])
        #expect(p?.intent == .note(kind: .task, text: "milk", collection: "Shopping", collectionKind: .list))
        let known = parser.parse("add milk to my groceries list", now: now, knownCollections: ["GROCERIES"])
        #expect(known?.intent == .note(kind: .task, text: "milk", collection: "GROCERIES", collectionKind: .list))
    }

    @Test func aPhraseThatSaysItIsAListInAnotherFormIsAlsoAList() {
        #expect(intent("save this idea to my packing list: a hat") == .note(kind: .idea, text: "a hat", collection: "Packing", collectionKind: .list))
        #expect(intent("save this idea to Sidefolk: dark mode") == .note(kind: .idea, text: "dark mode", collection: "Sidefolk"))
    }

    // MARK: Notes keep what was typed

    @Test func theTextOfANoteIsNotAltered() {
        #expect(intent("note: say thank you") == .note(kind: .note, text: "say thank you", collection: nil))
        #expect(intent("note: should we use pnpm?") == .note(kind: .note, text: "should we use pnpm?", collection: nil))
        #expect(intent("note: groceries\n- milk\n- eggs") == .note(kind: .note, text: "groceries\n- milk\n- eggs", collection: nil))
        #expect(intent("note: a\r\nb") == .note(kind: .note, text: "a\nb", collection: nil), "Windows line breaks")
        #expect(intent("please note: wow!") == .note(kind: .note, text: "wow!", collection: nil), "the lead-in is not part of the note")
    }

    @Test func aTimeOrALinkIsNotACollectionButNothingIsLost() {
        #expect(intent("task for tomorrow: call the dentist") == .note(kind: .task, text: "for tomorrow: call the dentist", collection: nil))
        #expect(intent("idea for https://example.com: foo") == .note(kind: .idea, text: "for https://example.com: foo", collection: nil))
        #expect(intent("note about 3:30 meeting: prep slides") == .note(kind: .note, text: "about 3:30 meeting: prep slides", collection: nil))
        #expect(intent("task for Work: send invoice") == .note(kind: .task, text: "send invoice", collection: "Work"))
    }
}
