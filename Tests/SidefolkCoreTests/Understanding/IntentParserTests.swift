import Foundation
import Testing
@testable import SidefolkCore

/// "Now" is Wednesday 22 October 2025, 10:00 UTC; morning 09, afternoon 14, evening 18.
@Suite struct IntentParserTests {
    let now = TimeTest.wednesday10
    let known = ["Sidefolk", "Work", "Home projects"]
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func parse(_ text: String, known: [String]? = nil) -> ParsedIntent? {
        parser.parse(text, now: now, knownCollections: known ?? self.known)
    }

    func intent(_ text: String) -> LocalIntent? { parse(text)?.intent }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { TimeTest.date(y, m, d, h, min) }

    // MARK: Reminders

    @Test func tomorrowMorning() {
        let p = parse("remind me tomorrow morning to send the document")
        #expect(p?.intent == .remind(title: "Send the document", when: at(2025, 10, 23, 9), recurrence: nil))
        #expect(p?.hint == "Reminder · Tomorrow 09:00 · no AI")
    }

    @Test func inTwentyMinutes() {
        let p = parse("remind me in 20 min to call mom")
        #expect(p?.intent == .remind(title: "Call mom", when: at(2025, 10, 22, 10, 20), recurrence: nil))
        #expect(p?.hint == "Reminder · Today 10:20 · no AI")
    }

    @Test func atFiveAtTheEnd() {
        let p = parse("remind me to call Karim at 5")
        #expect(p?.intent == .remind(title: "Call Karim", when: at(2025, 10, 22, 17), recurrence: nil))
    }

    @Test func everyWeekday() {
        let p = parse("remind me every weekday at 9 to do standup")
        #expect(p?.intent == .remind(title: "Do standup", when: at(2025, 10, 23, 9), recurrence: Recurrence(frequency: .weekdays)))
        #expect(p?.hint == "Reminder · Tomorrow 09:00 · every weekday · no AI")
    }

    @Test func aWeekdayHintShowsTheDay() {
        let p = parse("remind me on friday at 9 to file the report")
        #expect(p?.hint == "Reminder · Fri 09:00 · no AI")
    }

    @Test func noTimeAsksWhen() {
        let p = parse("remind me to call mom")
        #expect(p?.intent == .needsTime(title: "Call mom"))
        #expect(p?.hint == "Reminder · I'll ask when · no AI")
    }

    @Test func aMomentThatPassedAsksWhen() {
        #expect(intent("remind me this morning to stretch") == .needsTime(title: "Stretch"))
        #expect(intent("remind me 2020-01-01 to time travel") == .needsTime(title: "Time travel"))
    }

    @Test func otherReminderForms() {
        let tomorrow9 = at(2025, 10, 23, 9)
        #expect(intent("reminder: buy milk tomorrow") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("Reminder - buy milk tomorrow") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("reminder to buy milk tomorrow") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("set a reminder to buy milk tomorrow") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("set a reminder for tomorrow to buy milk") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("create a reminder tomorrow: buy milk") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("remind myself to buy milk tomorrow") == .remind(title: "Buy milk", when: tomorrow9, recurrence: nil))
        #expect(intent("remind me about the dentist tomorrow") == .remind(title: "The dentist", when: tomorrow9, recurrence: nil))
        #expect(intent("remind me that the rent is due tomorrow") == .remind(title: "The rent is due", when: tomorrow9, recurrence: nil))
        #expect(intent("ping me in an hour to check the oven") == .remind(title: "Check the oven", when: at(2025, 10, 22, 11), recurrence: nil))
        #expect(intent("remember to take the pills tonight") == .remind(title: "Take the pills", when: at(2025, 10, 22, 21), recurrence: nil))
    }

    @Test func repeatsInTheTitleSide() {
        let p = parse("remind me to water the plants every monday at 8")
        #expect(p?.intent == .remind(title: "Water the plants", when: at(2025, 10, 27, 8), recurrence: Recurrence(frequency: .weekly, weekdays: [1])))
        let q = parse("remind me weekly on tue and thu at 8 to take out the bins")
        #expect(q?.intent == .remind(title: "Take out the bins", when: at(2025, 10, 23, 8), recurrence: Recurrence(frequency: .weekly, weekdays: [2, 4])))
    }

    @Test func aTimeInTheMiddleOfTheTitleIsLeftAlone() {
        // "friday" belongs to the title; the real time is at the end.
        let p = parse("remind me to review the friday release notes tomorrow")
        #expect(p?.intent == .remind(title: "Review the friday release notes", when: at(2025, 10, 23, 9), recurrence: nil))
    }

    @Test func aDateAtTheStartJoinsATimeAtTheEnd() {
        #expect(intent("remind me tomorrow to call Karim at 5") == .remind(title: "Call Karim", when: at(2025, 10, 23, 17), recurrence: nil))
    }

    @Test func aTimeFirstThenWhatIsNotAReminder() {
        // Without "remind me" the app asks the AI rather than guessing.
        #expect(parse("tomorrow at 10 dentist") == nil)
        #expect(parse("in 20 min call mom") == nil)
        #expect(parse("dentist tomorrow at 10") == nil)
    }

    @Test func wordsAroundRemindDoNotTrigger() {
        #expect(parse("the reminder app is broken") == nil)
        #expect(parse("reminders are annoying") == nil)
        #expect(parse("what reminders do I have") == nil)
        #expect(parse("don't remind me to call mom") == nil)
        #expect(parse("remind me") == nil)
        #expect(parse("remind me tomorrow") == nil)
        #expect(parse("tell me a joke") == nil)
        #expect(parse("remember the milk") != nil)  // a note, see below
    }

    @Test func schedulesTooFineForARecurrenceAreLeftToTheAI() {
        #expect(parse("remind me every 30 minutes to stretch") == nil)
        #expect(parse("remind me to drink water every 20 min") == nil)
        #expect(intent("remind me every 2 hours to stretch") != nil)
    }

    @Test func typosInTheLeadWord() {
        #expect(intent("remnd me tomorrow to call mom") == .remind(title: "Call mom", when: at(2025, 10, 23, 9), recurrence: nil))
        #expect(intent("remid me in 5 min to stretch") == .remind(title: "Stretch", when: at(2025, 10, 22, 10, 5), recurrence: nil))
    }

    // MARK: Polite words

    @Test func politePrefixesAndSuffixesAreStripped() {
        let expected = LocalIntent.remind(title: "Call mom", when: at(2025, 10, 22, 10, 20), recurrence: nil)
        for text in ["please remind me in 20 min to call mom", "Hey, remind me in 20 min to call mom", "hey pip, remind me in 20 min to call mom",
                     "Can you remind me in 20 min to call mom?", "could you please remind me in 20 min to call mom",
                     "remind me in 20 min to call mom please", "ok remind me in 20 min to call mom, thanks!", "Hey Sidefolk: remind me in 20 min to call mom",
                     "i need you to remind me in 20 min to call mom", "  remind   me in   20 min to call mom  "] {
            #expect(intent(text) == expected, "\(text)")
        }
    }

    // MARK: Notes

    @Test func noteColon() {
        let p = parse("note: buy a new charger")
        #expect(p?.intent == .note(kind: .note, text: "buy a new charger", collection: nil))
        #expect(p?.hint == "Note → Inbox · no AI")
    }

    @Test func ideaColon() {
        let p = parse("idea: folks per extension")
        #expect(p?.intent == .note(kind: .idea, text: "folks per extension", collection: nil))
        #expect(p?.hint == "Idea → Inbox · no AI")
    }

    @Test func saveThisIdeaToACollection() {
        let p = parse("save this idea to Sidefolk: extensions could have their own folk")
        #expect(p?.intent == .note(kind: .idea, text: "extensions could have their own folk", collection: "Sidefolk"))
        #expect(p?.hint == "Idea → Sidefolk · no AI")
        // The user's own spelling of a known collection wins over what was typed.
        #expect(intent("save this idea to sidefolk: x") == .note(kind: .idea, text: "x", collection: "Sidefolk"))
        // Unknown collections are kept as typed (the app creates them).
        #expect(intent("save this idea to Garden: plant tomatoes") == .note(kind: .idea, text: "plant tomatoes", collection: "Garden"))
    }

    @Test func addToAList() {
        let p = parse("add oat milk to my groceries list")
        #expect(p?.intent == .note(kind: .task, text: "oat milk", collection: "groceries"))
        #expect(p?.hint == "Task → groceries · no AI")
        #expect(intent("put eggs on the shopping list") == .note(kind: .task, text: "eggs", collection: "shopping"))
        #expect(intent("add renew passport to my todo list") == .note(kind: .task, text: "renew passport", collection: nil))
    }

    @Test func addToAKnownCollectionWithoutTheWordList() {
        #expect(intent("add fix the build to Work") == .note(kind: .task, text: "fix the build", collection: "Work"))
        // Not a known collection: this is probably a request for the AI.
        #expect(parse("add a button to the page") == nil)
        #expect(parse("add a note to Sidefolk") == nil)
    }

    @Test func todo() {
        #expect(intent("todo: renew passport") == .note(kind: .task, text: "renew passport", collection: nil))
        #expect(intent("todo renew passport") == .note(kind: .task, text: "renew passport", collection: nil))
        #expect(intent("task: file taxes") == .note(kind: .task, text: "file taxes", collection: nil))
        #expect(intent("to-do: file taxes") == .note(kind: .task, text: "file taxes", collection: nil))
        #expect(parse("todo: renew passport")?.hint == "Task → Inbox · no AI")
    }

    @Test func otherNoteForms() {
        #expect(intent("note to self: call the bank") == .note(kind: .note, text: "call the bank", collection: nil))
        #expect(intent("idea for Sidefolk: dark mode") == .note(kind: .idea, text: "dark mode", collection: "Sidefolk"))
        #expect(intent("jot down the wifi is on the fridge") == .note(kind: .note, text: "the wifi is on the fridge", collection: nil))
        #expect(intent("make a note that the deploy key rotates monthly") == .note(kind: .note, text: "the deploy key rotates monthly", collection: nil))
        #expect(intent("note that the staging db needs SSL") == .note(kind: .note, text: "the staging db needs SSL", collection: nil))
        #expect(intent("save a note: call the bank") == .note(kind: .note, text: "call the bank", collection: nil))
        #expect(intent("add a task: call the bank") == .note(kind: .task, text: "call the bank", collection: nil))
        #expect(intent("link: https://example.com/post") == .note(kind: .link, text: "https://example.com/post", collection: nil))
        #expect(intent("Idea - dark mode") == .note(kind: .idea, text: "dark mode", collection: nil))
    }

    @Test func hyphenatedCollectionNamesSurvive() {
        #expect(intent("save this idea to side-project: x") == .note(kind: .idea, text: "x", collection: "side-project"))
    }

    @Test func rememberThatIAmAFactAboutYou() {
        let p = parse("remember that I prefer pnpm")
        #expect(p?.intent == .aboutMe(fact: "I prefer pnpm"))
        #expect(p?.hint == "Remember in About you · no AI")
        #expect(intent("remember my sister's name is Lina") == .aboutMe(fact: "My sister's name is Lina"))
        #expect(intent("remember i'm allergic to peanuts") == .aboutMe(fact: "I'm allergic to peanuts"))
        #expect(intent("keep in mind that I work in UTC+1") == .aboutMe(fact: "I work in UTC+1"))
        #expect(intent("about me: I use a Mac mini") == .aboutMe(fact: "I use a Mac mini"))
    }

    @Test func rememberThatSomethingElseIsANote() {
        let p = parse("remember that the staging db needs SSL")
        #expect(p?.intent == .note(kind: .note, text: "the staging db needs SSL", collection: nil))
        #expect(intent("remember the milk") == .note(kind: .note, text: "the milk", collection: nil))
    }

    @Test func rememberToWithoutATimeIsLeftToTheAI() {
        #expect(parse("remember to call mom") == nil)
    }

    @Test func aBareKindWordIsNotANote() {
        #expect(parse("note:") == nil)
        #expect(parse("idea: idea") == nil)
    }

    // MARK: Watching

    @Test func watchAUrl() {
        let p = parse("watch https://example.com/pricing")
        #expect(p?.intent == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
        #expect(p?.hint == "Watch example.com/pricing · no AI")
        #expect(intent("watch example.com/pricing") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
        #expect(intent("watch example.com/pricing for changes") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
        #expect(intent("monitor the page example.com/jobs") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/jobs")))
        #expect(intent("keep an eye on https://example.com") == .watch(WatchIntent(kind: "url_change", target: "https://example.com")))
    }

    @Test func watchAUrlForAWord() {
        let p = parse("watch example.com/tickets for \"sold out\"")
        #expect(p?.intent == .watch(WatchIntent(kind: "url_change", target: "https://example.com/tickets", contains: "sold out")))
        #expect(intent("tell me when example.com/tickets mentions sold out") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/tickets", contains: "sold out")))
    }

    @Test func tellMeWhenAPageChanges() {
        let p = parse("tell me when example.com/pricing changes")
        #expect(p?.intent == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
        #expect(p?.hint == "Watch example.com/pricing · no AI")
        #expect(intent("let me know when https://example.com/pricing is updated") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
        #expect(intent("notify me if example.com/pricing changes") == .watch(WatchIntent(kind: "url_change", target: "https://example.com/pricing")))
    }

    @Test func tellMeWhenASiteIsBackUp() {
        let p = parse("tell me when https://api.example.com is back up")
        #expect(p?.intent == .watch(WatchIntent(kind: "site_status", target: "https://api.example.com")))
        #expect(p?.hint == "Watch api.example.com is up · no AI")
        #expect(intent("tell me when api.example.com is up again") == .watch(WatchIntent(kind: "site_status", target: "https://api.example.com")))
        #expect(intent("tell me when localhost:3000 comes back online") == .watch(WatchIntent(kind: "site_status", target: "http://localhost:3000")))
        #expect(intent("let me know when 192.168.1.5:8080 is up") == .watch(WatchIntent(kind: "site_status", target: "http://192.168.1.5:8080")))
    }

    @Test func tellMeWhenASiteGoesDown() {
        let p = parse("tell me when example.com goes down")
        #expect(p?.intent == .watch(WatchIntent(kind: "site_status", target: "https://example.com", contains: "down")))
        #expect(p?.hint == "Watch example.com goes down · no AI")
        #expect(intent("tell me if https://example.com is down") == .watch(WatchIntent(kind: "site_status", target: "https://example.com", contains: "down")))
    }

    @Test func tellMeWhenAFileAppears() {
        let p = parse("tell me when report.pdf appears in Downloads")
        #expect(p?.intent == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Downloads/report.pdf")))
        #expect(p?.hint == "Watch ~/Downloads/report.pdf · no AI")
        #expect(intent("tell me when \"my report.pdf\" shows up in my downloads folder") == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Downloads/my report.pdf")))
        #expect(intent("let me know when notes.txt lands on the desktop") == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Desktop/notes.txt")))
        #expect(intent("tell me when ~/Projects/out/build.zip appears") == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Projects/out/build.zip")))
        #expect(intent("tell me when report.pdf appears in ~/Work/inbox") == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Work/inbox/report.pdf")))
        #expect(intent("tell me when Downloads/report.pdf appears") == .watch(WatchIntent(kind: "file_appears", target: "/Users/test/Downloads/report.pdf")))
    }

    @Test func aFileWithoutAFolderIsNotGuessed() {
        #expect(parse("tell me when report.pdf appears") == nil)
    }

    @Test func tellMeWhenTheDownloadFinishes() {
        let p = parse("let me know when the download finishes")
        #expect(p?.intent == .watch(WatchIntent(kind: "folder_new_file", target: "/Users/test/Downloads")))
        #expect(p?.hint == "Watch ~/Downloads for new files · no AI")
        #expect(intent("tell me when my download is done") == .watch(WatchIntent(kind: "folder_new_file", target: "/Users/test/Downloads")))
    }

    @Test func aNewFileInAFolder() {
        #expect(intent("tell me when a new file appears in Downloads") == .watch(WatchIntent(kind: "folder_new_file", target: "/Users/test/Downloads")))
        #expect(intent("watch my downloads folder") == .watch(WatchIntent(kind: "folder_new_file", target: "/Users/test/Downloads")))
    }

    @Test func tellMeWhenAProcessFinishes() {
        let p = parse("tell me when xcodebuild finishes")
        #expect(p?.intent == .watch(WatchIntent(kind: "process_exits", target: "xcodebuild")))
        #expect(p?.hint == "Watch xcodebuild exits · no AI")
        #expect(intent("let me know once ffmpeg is done") == .watch(WatchIntent(kind: "process_exits", target: "ffmpeg")))
        #expect(intent("remind me when the npm process exits") == .watch(WatchIntent(kind: "process_exits", target: "npm")))
    }

    @Test func vagueWatchesAreLeftToTheAI() {
        #expect(parse("tell me when the build finishes") == nil)
        #expect(parse("tell me when it finishes") == nil)
        #expect(parse("tell me when the server is back up") == nil)
        #expect(parse("tell me when pid 4312 exits") == nil)
        #expect(parse("tell me when my mom calls") == nil)
        #expect(parse("watch the game tonight") == nil)
        #expect(parse("watch my back") == nil)
    }

    // MARK: Quiet mode

    @Test func quietForAnHour() {
        let p = parse("quiet for 1 hour")
        #expect(p?.intent == .quiet(until: at(2025, 10, 22, 11)))
        #expect(p?.hint == "Quiet until 11:00 · no AI")
        #expect(intent("be quiet for an hour") == .quiet(until: at(2025, 10, 22, 11)))
        #expect(intent("quiet mode for the next 30 minutes") == .quiet(until: at(2025, 10, 22, 10, 30)))
        #expect(intent("go quiet for 2 hours") == .quiet(until: at(2025, 10, 22, 12)))
    }

    @Test func doNotDisturbUntilThreePM() {
        let p = parse("do not disturb until 3pm")
        #expect(p?.intent == .quiet(until: at(2025, 10, 22, 15)))
        #expect(p?.hint == "Quiet until 15:00 · no AI")
        #expect(intent("don't disturb me until 15:00") == .quiet(until: at(2025, 10, 22, 15)))
        #expect(intent("dnd until 3") == .quiet(until: at(2025, 10, 22, 15)))
        #expect(intent("quiet until tomorrow morning") == .quiet(until: at(2025, 10, 23, 9)))
        #expect(parse("quiet until tomorrow morning")?.hint == "Quiet until Tomorrow 09:00 · no AI")
    }

    @Test func quietWithoutAnEnd() {
        let p = parse("quiet mode")
        #expect(p?.intent == .quiet(until: nil))
        #expect(p?.hint == "Quiet until you turn it off · no AI")
        #expect(intent("be quiet") == .quiet(until: nil))
        #expect(intent("turn on do not disturb") == .quiet(until: nil))
    }

    @Test func quietOff() {
        for text in ["quiet off", "quiet mode off", "turn off quiet mode", "turn quiet mode off", "stop quiet mode", "end quiet", "disable do not disturb"] {
            #expect(intent(text) == .quietOff, "\(text)")
        }
        #expect(parse("quiet off")?.hint == "Quiet off · no AI")
    }

    @Test func quietWithAnUnclearEndIsLeftToTheAI() {
        #expect(parse("quiet until I say so") == nil)
        #expect(parse("quiet for a while") == nil)
        #expect(parse("quiet down the logs") == nil)
        #expect(parse("quiet please") != nil)  // polite word is stripped: plain quiet mode
    }

    // MARK: Searching

    @Test func findAWord() {
        let p = parse("find redis")
        #expect(p?.intent == .find(query: "redis", kind: nil, collection: nil))
        #expect(p?.hint == "Search notebook · no AI")
        #expect(intent("search for redis") == .find(query: "redis", kind: nil, collection: nil))
        #expect(intent("search my notebook for redis caching") == .find(query: "redis caching", kind: nil, collection: nil))
        #expect(intent("find notes about redis") == .find(query: "redis", kind: .note, collection: nil))
    }

    @Test func whatIdeasDidISave() {
        let p = parse("what ideas did I save for Sidefolk?")
        #expect(p?.intent == .find(query: "", kind: .idea, collection: "Sidefolk"))
        #expect(p?.hint == "Search ideas in Sidefolk · no AI")
        // Not a known collection: the word becomes the search.
        #expect(intent("what ideas did I save for pricing?") == .find(query: "pricing", kind: .idea, collection: nil))
        #expect(intent("what ideas did I save for pricing?") == parser.parse("what ideas did I save for pricing?", now: now, knownCollections: [])?.intent)
        #expect(intent("what notes do I have about redis") == .find(query: "redis", kind: .note, collection: nil))
    }

    @Test func listing() {
        #expect(intent("show my tasks") == .find(query: "", kind: .task, collection: nil))
        #expect(intent("list my ideas for Work") == .find(query: "", kind: .idea, collection: "Work"))
        #expect(intent("what are my open tasks?") == .find(query: "", kind: .task, collection: nil))
        #expect(intent("show me all my links") == .find(query: "", kind: .link, collection: nil))
        #expect(parse("show my tasks")?.hint == "Search tasks · no AI")
    }

    @Test func requestsThatNeedReasoningAreNotSearches() {
        for text in ["find out why the build fails", "find me a good restaurant", "find a way to fix this", "search the web for cats",
                     "find the best way to cache redis responses quickly", "find"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    // MARK: Things for the AI

    @Test func questionsAndRequestsReturnNil() {
        for text in ["what's the weather?", "summarize this page", "what is the capital of France", "how do I undo a git commit",
                     "write a poem about cats", "translate this to French", "explain closures in Swift", "who won the game",
                     "can you help me with this?", "hello", "thanks", "/note something", "", "   ", "I need coffee",
                     "why is my build slow", "open Safari", "clean up my downloads folder", "tomorrow", "5 minutes"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func veryLongTextIsNotClaimed() {
        #expect(parse("note: " + String(repeating: "word ", count: 600)) == nil)
    }

    @Test func intentsAreStableAcrossCaseAndSpacing() {
        #expect(intent("NOTE:   Buy   A   Charger") == .note(kind: .note, text: "Buy A Charger", collection: nil))
        #expect(intent("REMIND ME IN 20 MIN TO CALL MOM") == .remind(title: "CALL MOM", when: at(2025, 10, 22, 10, 20), recurrence: nil))
    }
}
