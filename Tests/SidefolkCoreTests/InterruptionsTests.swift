import Foundation
import Testing
@testable import SidefolkCore

/// What may interrupt you (D88): each source's ceiling, how a notice's level meets it, then Focus and Quiet.
@Suite struct InterruptionsTests {
    @Test func whereANoticeComesFrom() {
        #expect(InterruptSource.of(source: "reminder", refKind: "reminder", refId: "r1") == [.reminders])
        #expect(InterruptSource.of(source: "watcher", refKind: "watcher", refId: "w1") == [.watch("w1"), .watches])
        #expect(InterruptSource.of(source: "extension:dev.git", refKind: "watcher", refId: "w2")
            == [.watch("w2"), .extension("dev.git"), .watches])
        #expect(InterruptSource.of(source: "extension:dev.git", refKind: "notify", refId: nil) == [.extension("dev.git")])
        #expect(InterruptSource.of(source: "job", refKind: "job", refId: "j1") == [.commands])
        #expect(InterruptSource.of(source: "external:Claude Code", refKind: "notify", refId: nil) == [.agent("claude-code")])
        #expect(InterruptSource.of(source: "external:codex-mcp-client", refKind: "ask", refId: nil) == [.agent("codex")])
        #expect(InterruptSource.of(source: "external:Cursor", refKind: nil, refId: nil) == [.agent("cursor")])
        #expect(InterruptSource.of(source: "session:claude-code:abc-123", refKind: "session", refId: "abc-123") == [.agent("claude-code")])
        #expect(InterruptSource.of(source: "session:abc-123", refKind: "session", refId: "abc-123").isEmpty, "from before D88: no agent named")
        #expect(InterruptSource.of(source: "agent", refKind: "notify", refId: nil) == [.companion])
        #expect(InterruptSource.of(source: "routine:r1", refKind: "notify", refId: nil) == [.companion])
        #expect(InterruptSource.of(source: "summary", refKind: nil, refId: nil).isEmpty)
        #expect(InterruptSource.of(source: "brief", refKind: "brief", refId: nil).isEmpty)
        for source in [InterruptSource.reminders, .watches, .watch("w1"), .commands, .agent("claude-code"), .extension("dev.git"), .companion] {
            #expect(InterruptSource(key: source.key) == source)
        }
    }

    /// Every notice level against every ceiling: the lower of the two, Only in Today and Off taking it off the desktop.
    @Test func theLowerOfTheTwo() {
        let expected: [InterruptLevel: [AttentionLevel: Interruptions.Route]] = [
            .card: [.ambient: .deliver(.ambient), .gentle: .deliver(.gentle), .attention: .deliver(.attention), .critical: .deliver(.critical)],
            .whisper: [.ambient: .deliver(.ambient), .gentle: .deliver(.gentle), .attention: .deliver(.gentle), .critical: .deliver(.gentle)],
            .today: [.ambient: .today, .gentle: .today, .attention: .today, .critical: .today],
            .off: [.ambient: .off, .gentle: .off, .attention: .off, .critical: .off],
        ]
        for (ceiling, rows) in expected {
            let levels = Interruptions([.watches: ceiling])
            for (level, route) in rows {
                #expect(levels.route(level: level, source: "watcher", refKind: "watcher", refId: "w1") == route, "\(ceiling) × \(level)")
            }
        }
    }

    @Test func questionsAndAgentsWaitingAreNeverTurnedDown() {
        let off = Interruptions([.agent("codex"): .off, .agent("claude-code"): .off, .companion: .off])
        #expect(off.route(level: .attention, source: "external:codex", refKind: "ask", refId: nil) == .deliver(.attention))
        #expect(off.route(level: .attention, source: "agent", refKind: "ask", refId: nil) == .deliver(.attention))
        #expect(off.route(level: .attention, source: "session:claude-code:s1", refKind: "session", refId: "s1") == .deliver(.attention),
                "Claude Code waiting for an approval in its own window")
        #expect(off.route(level: .gentle, source: "session:claude-code:s1", refKind: "session", refId: "s1") == .off, "finishing is news")
        #expect(off.route(level: .attention, source: "external:codex", refKind: "notify", refId: nil) == .off)
    }

    @Test func theMostSpecificChoiceWins() {
        var levels = Interruptions([.watches: .today])
        #expect(levels.route(level: .attention, source: "watcher", refKind: "watcher", refId: "w1") == .today)
        levels.set(.card, for: .watch("w1"))
        #expect(levels.route(level: .attention, source: "watcher", refKind: "watcher", refId: "w1") == .deliver(.attention), "set apart")
        #expect(levels.route(level: .attention, source: "watcher", refKind: "watcher", refId: "w2") == .today)
        levels.set(.whisper, for: .extension("dev.git"))
        #expect(levels.route(level: .attention, source: "extension:dev.git", refKind: "watcher", refId: "w3") == .deliver(.gentle))
        #expect(levels.watchOverrides == ["w1": .card])
    }

    @Test func defaultsAreTodaysBehaviour() {
        let levels = Interruptions()
        for source in ["reminder", "watcher", "job", "external:claude-code", "session:codex:s1", "extension:x", "agent"] {
            for level in AttentionLevel.allCases {
                #expect(levels.route(level: level, source: source, refKind: nil, refId: nil) == .deliver(level), "\(source) \(level)")
            }
        }
    }

    @Test func choicesEachSourceOffers() {
        var levels = Interruptions()
        levels.set(.off, for: .reminders)
        #expect(levels.level(for: .reminders) == .card, "a reminder may come quieter, never not at all")
        levels.set(.today, for: .reminders)
        #expect(levels.level(for: .reminders) == .today)
        // Back to the default clears it, so a later default reaches everyone who never chose.
        levels.set(.card, for: .reminders)
        #expect(levels.explicit(.reminders) == nil)
        #expect(InterruptLevel.card.quieter == .whisper && InterruptLevel.off.quieter == nil)
    }

    @Test func settingsFromBeforeAndFromLater() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName":"Mochi","sounds":false}"#.utf8))
        #expect(old.interruptions == Interruptions())
        #expect(old.sounds == false)

        // A level or source a newer Sidefolk wrote is skipped; the rest stays.
        let later = try JSONDecoder().decode(AppSettings.self, from: Data(#"""
            {"interruptions": {"agent:codex": "today", "watches": "loud", "planets:mars": "off", "watch:w1": "whisper"}}
            """#.utf8))
        #expect(later.interruptions.levels == ["agent:codex": .today, "watch:w1": .whisper])

        var s = AppSettings()
        s.interruptions.set(.off, for: .agent("claude-code"))
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.interruptions.level(for: .agent("claude-code")) == .off)
    }
}

/// The attention center applies the ceiling first, then Focus or Quiet (D88).
@Suite struct InterruptionsCenterTests {
    struct Outcome: Equatable {
        var state: AttentionItem.State
        var presentation: AttentionPresentation?
        var held: Bool
    }

    /// Posts one notice under `levels` and the mode, and says what became of it.
    func outcome(_ level: AttentionLevel, source: String = "watcher", refKind: String? = "watcher", actions: Bool = true,
                 levels: Interruptions, focus: Bool = false, quiet: Bool = false) async throws -> Outcome {
        let db = try AppDatabase.inMemory()
        let events = EventBus()
        let store = AttentionStore(db)
        let center = AttentionCenter(store: store, events: events)
        await center.update { env in
            env.interruptions = levels
            env.focus = focus
            env.quiet = quiet
        }
        let stream = events.stream()
        let item = await center.post(AttentionRequest(level: level, source: source, title: "Pricing changed",
                                                      actions: actions ? [AttentionAction(id: "open", title: "Open", isPrimary: true)] : [],
                                                      refKind: refKind, refId: "w1"))
        // Everything is published by the time `post` returns: read up to a marker.
        events.changed(.notebook)
        var shown: AttentionPresentation?
        for await e in stream {
            if case .attention(.present(let p, let presentation)) = e, p.id == item.id { shown = presentation }
            if case .dataChanged(.notebook) = e { break }
        }
        let state = try #require(try await store.item(id: item.id)?.state)
        return Outcome(state: state, presentation: shown, held: await center.isHeld(item.id))
    }

    let card = AttentionPresentation.attention(expandFor: AttentionPolicy.expandSeconds)
    let whisper = AttentionPresentation.gentle(autoDismiss: AttentionPolicy.gentleSeconds)

    @Test func openCombinations() async throws {
        #expect(try await outcome(.attention, levels: Interruptions()) == Outcome(state: .shown, presentation: card, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .whisper])) == Outcome(state: .shown, presentation: whisper, held: false))
        #expect(try await outcome(.gentle, levels: Interruptions([.watches: .whisper])) == Outcome(state: .shown, presentation: whisper, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .today])) == Outcome(state: .kept, presentation: nil, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .off])) == Outcome(state: .acknowledged, presentation: nil, held: false))
    }

    @Test func focusCombinations() async throws {
        #expect(try await outcome(.attention, levels: Interruptions(), focus: true) == Outcome(state: .shown, presentation: card, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .whisper]), focus: true)
            == Outcome(state: .pending, presentation: nil, held: true), "a card turned whisper waits like a whisper")
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .today]), focus: true) == Outcome(state: .kept, presentation: nil, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .off]), focus: true) == Outcome(state: .acknowledged, presentation: nil, held: false))
    }

    @Test func quietCombinations() async throws {
        let silent = AttentionPresentation.system(sound: false, alsoOnDesktop: false)
        #expect(try await outcome(.attention, levels: Interruptions(), quiet: true) == Outcome(state: .shown, presentation: silent, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .whisper]), quiet: true)
            == Outcome(state: .pending, presentation: nil, held: true))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .today]), quiet: true) == Outcome(state: .kept, presentation: nil, held: false))
        #expect(try await outcome(.attention, levels: Interruptions([.watches: .off]), quiet: true) == Outcome(state: .acknowledged, presentation: nil, held: false))
    }

    @Test func aQuestionComesWhateverItsAgentIsSetTo() async throws {
        let off = Interruptions([.agent("codex"): .off])
        #expect(try await outcome(.attention, source: "external:codex", refKind: "ask", levels: off)
            == Outcome(state: .shown, presentation: card, held: false))
        #expect(try await outcome(.gentle, source: "external:codex", refKind: "notify", actions: false, levels: off)
            == Outcome(state: .acknowledged, presentation: nil, held: false))
    }

    @Test func keptNoticesWaitInTodayAndCanBeAnswered() async throws {
        let db = try AppDatabase.inMemory()
        let store = AttentionStore(db)
        let center = AttentionCenter(store: store, events: EventBus())
        await center.update { $0.interruptions = Interruptions([.agent("claude-code"): .today]) }
        let item = await center.post(AttentionRequest(level: .gentle, source: "session:claude-code:s1", title: "Claude finished in sidefolk",
                                                      refKind: "session", refId: "s1"))
        #expect(item.state == .kept)
        #expect(await center.open().isEmpty, "nothing waits on the desktop")
        #expect(await center.kept().map(\.id) == [item.id])
        await center.respond(id: item.id, actionId: nil)
        #expect(await center.kept().isEmpty)
        #expect(try await store.item(id: item.id)?.state == .acknowledged)

        // A repeating reminder's next time retires its kept notice, as it does an open one.
        await center.update { $0.interruptions = Interruptions([.reminders: .today]) }
        _ = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "Stretch", refKind: "reminder", refId: "r1"))
        await center.withdraw(refKind: "reminder", refId: "r1")
        #expect(await center.kept().isEmpty)
    }
}
