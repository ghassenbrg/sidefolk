import Foundation
import Testing
@testable import SidefolkCore

/// The runner carries out what the parser understood, through the real tools, the way the Ask panel does.
@Suite struct LocalIntentRunnerTests {
    let runtime: SidefolkRuntime
    let runner: LocalIntentRunner

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-runner-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                        clock: ManualClock(TestEnv.referenceDate))
        runner = LocalIntentRunner(runtime: runtime)
    }

    func card(_ outcome: LocalOutcome) throws -> ResultCard {
        guard case .card(let card, _, _) = outcome else {
            Issue.record("expected a card, got \(outcome)")
            throw CancellationError()
        }
        return card
    }

    func run(_ text: String) async throws -> LocalOutcome {
        let parsed = try #require(await runner.parse(text), "“\(text)” should be understood locally")
        return await runner.run(parsed.intent)
    }

    // MARK: A value now, and chance

    @Test func aPlainQuestionAboutTheMacIsAnsweredOnTheSpot() async throws {
        let read = try card(try await run("what's my memory usage"))
        #expect(read.kind == .reading && read.title.hasPrefix("Memory: "), "\(read.title)")
        #expect(await runtime.watchers.list().isEmpty, "nothing to stop afterwards")
    }

    @Test func chanceIsPlayedAndRockPaperScissorsIsAMatchUntilYouNameAHand() async throws {
        let coin = try card(try await run("flip a coin"))
        #expect(coin.kind == .chance && ["Heads!", "Tails!"].contains(coin.title))
        // Without a hand, the best of three opens in the Play panel (D75).
        let match = try card(try await run("let's play rock paper scissors"))
        #expect(match.title == "Play Rock, Paper, Scissors", "\(match)")
        let round = try card(try await run("paper"))
        #expect(round.kind == .chance && round.subtitle?.hasPrefix("You ") == true, "\(round)")
    }

    // MARK: Lists

    @Test func addToAListMakesTheListWithACapitalName() async throws {
        let saved = try card(try await run("add milk to my groceries list"))
        #expect(saved.title == "Saved to Groceries › Tasks")
        #expect(saved.subtitle == "Milk", "titles start with a capital letter, like reminders")
        let list = try #require(try await runtime.notebook.findCollection(named: "Groceries"))
        #expect(list.kind == .list)
        #expect(list.name == "Groceries")

        // The second one finds it again, whatever the spelling.
        _ = try card(try await run("add eggs to the groceries list"))
        #expect(try await runtime.notebook.collections().filter { $0.name.lowercased() == "groceries" }.count == 1)
        #expect(try await runtime.notebook.items(collectionId: list.id).map(\.title).sorted() == ["Eggs", "Milk"])
    }

    @Test func otherNotesKeepWhatWasTypedExceptTheFirstLetter() async throws {
        _ = try card(try await run("note: should we use pnpm?"))
        _ = try card(try await run("idea: iPhone widget\nsecond line"))
        _ = try card(try await run("link: https://example.com/post"))
        let items = try await runtime.notebook.items()
        let titles = Set(items.map(\.title))
        #expect(titles.contains("Should we use pnpm?"))
        #expect(titles.contains("iPhone widget"), "a capital inside the first word is left alone")
        #expect(items.first { $0.title == "iPhone widget" }?.body == "second line")
        #expect(items.contains { $0.kind == .link && $0.url == "https://example.com/post" })
        #expect(IntentParser.capitalizedNote("milk") == "Milk")
        #expect(IntentParser.capitalizedNote("https://example.com") == "https://example.com")
        #expect(IntentParser.capitalizedNote("~/notes") == "~/notes")
    }

    // MARK: Important reminders

    @Test func anUrgentReminderInterruptsQuietMode() async throws {
        _ = try card(try await run("urgent: remind me to call the bank in 1 hour"))
        _ = try card(try await run("remind me in 2 hours to stretch"))
        let pending = try await runtime.reminderStore.pending()
        #expect(pending.first { $0.title == "Call the bank" }?.level == .critical)
        #expect(pending.first { $0.title == "Stretch" }?.level == .attention)
    }

    // MARK: Asking again

    @Test func aReminderWithoutAUsableTimeComesBackAsAQuestionWithItsReason() async throws {
        guard case .needsTime(let title, let reason, let important) = try await run("remind me yesterday to call mom") else {
            Issue.record("expected a question"); return
        }
        #expect(title == "Call mom" && reason == "Yesterday has passed." && important == false)
        guard case .needsTime(_, nil, true) = try await run("remind me urgently to water plants") else {
            Issue.record("the urgency travels with the question"); return
        }
    }

    @Test func aWatchWithoutAnAddressComesBackAsAQuestionAndIsFinishedByTheAnswer() async throws {
        guard case .needsTarget(let kind, let becomes) = try await run("tell me when the server is back up") else {
            Issue.record("expected a question"); return
        }
        #expect(kind == "site_status" && becomes == "up")

        // Nothing listens on port 1: the watcher is made, and the card says so at once.
        let answer = try #require(runtime.intentParser.watch(address: "localhost:1", kind: kind, becomes: becomes))
        let started = try card(await runner.run(answer.intent))
        #expect(started.title == "I can't reach localhost:1 right now")
        #expect(started.subtitle?.hasSuffix("tell you when it's back up.") == true)
        let watcher = try #require(await runtime.watchers.list().first)
        #expect(watcher.config.string("url") == "http://localhost:1")
        #expect(watcher.allowsLocal, "the user asked for it themselves")
    }

    // MARK: Slash shortcuts

    @Test func slashQuietReadsLikeTheSentence() {
        #expect(LocalIntentRunner.expandSlash("/quiet for 1h") == "quiet for 1h")
        #expect(LocalIntentRunner.expandSlash("/quiet 1h") == "quiet for 1h")
        #expect(LocalIntentRunner.expandSlash("/quiet till 5") == "quiet till 5")
        #expect(LocalIntentRunner.expandSlash("/q until 5pm") == "quiet until 5pm")
        #expect(LocalIntentRunner.expandSlash("/quiet") == "be quiet")
        #expect(LocalIntentRunner.expandSlash("/quiet off") == "quiet off")
    }
}
