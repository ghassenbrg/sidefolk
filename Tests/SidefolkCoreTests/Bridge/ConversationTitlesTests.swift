import Foundation
import Testing
@testable import SidefolkCore

/// What the agent's own app calls a conversation (D118), from its files, for the title alone.
@Suite struct ConversationTitlesTests {
    let root: URL
    let titles: ConversationTitles

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("titles-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude/projects/p"), withIntermediateDirectories: true)
        titles = ConversationTitles(claudeProjects: root.appendingPathComponent("claude/projects"), codexIndex: root.appendingPathComponent("session_index.jsonl"))
    }

    func transcript(_ lines: [String], name: String = "s.jsonl") throws -> String {
        let file = root.appendingPathComponent("claude/projects/p/\(name)")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    @Test func itFindsThePersonsOwnNameFirst() throws {
        let path = try transcript([#"{"type":"ai-title","aiTitle":"Made up"}"#, #"{"type":"custom-title","customTitle":"Their name"}"#, #"{"type":"ai-title","aiTitle":"Later made up"}"#])
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: path) == "Their name")
    }

    @Test func itFallsBackOnTheAgentsAndThenOnNothing() throws {
        let made = try transcript([#"{"type":"ai-title","aiTitle":"Made up"}"#])
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: made) == "Made up")
        let none = try transcript([#"{"type":"user","message":"customTitle: a secret"}"#])
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: none) == nil, "never a guess, and never what was said")
    }

    /// A conversation's words that merely mention a title are not one.
    @Test func wordsInTheConversationAreNotATitle() throws {
        let path = try transcript([#"{"type":"user","text":"\"type\":\"custom-title\",\"customTitle\":\"Injected\""}"#])
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: path) == nil)
    }

    @Test func aPathOutsideTheAgentsFolderIsNotRead() throws {
        let outside = root.appendingPathComponent("outside.jsonl")
        try #"{"type":"custom-title","customTitle":"Nope"}"#.write(to: outside, atomically: true, encoding: .utf8)
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: outside.path) == nil)
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: root.appendingPathComponent("claude/projects/p/../../../outside.jsonl").path) == nil)
    }

    @Test func aLinkOutOfTheFolderIsNotFollowed() throws {
        let outside = root.appendingPathComponent("outside.jsonl")
        try #"{"type":"custom-title","customTitle":"Nope"}"#.write(to: outside, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("claude/projects/p/link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: link.path) == nil)
    }

    /// Reading a pipe would wait for ever, on the actor every hook goes through.
    @Test func aPipeIsNotRead() throws {
        let pipe = root.appendingPathComponent("claude/projects/p/pipe.jsonl")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        #expect(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: pipe.path) == nil)
    }

    @Test func aTitleIsShortAndPlainAndALongFilesEndIsEnough() throws {
        let long = String(repeating: "x", count: 200)
        let filler = String(repeating: #"{"type":"assistant","text":"hello"}"# + "\n", count: 20_000)
        let path = try transcript([filler + #"{"type":"custom-title","customTitle":"a‮\#(long)"}"#])
        let title = try #require(titles.title(agent: "claude-code", sessionId: "s", transcriptPath: path))
        #expect(title.count <= ConversationTitles.longest)
        #expect(!title.unicodeScalars.contains("\u{202E}"))
    }

    @Test func codexSaysInItsIndex() throws {
        try [#"{"id":"a","thread_name":"First","updated_at":"x"}"#, #"{"id":"b","thread_name":"Second","updated_at":"x"}"#]
            .joined(separator: "\n").write(to: root.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
        #expect(titles.title(agent: "codex", sessionId: "a", transcriptPath: nil) == "First")
        #expect(titles.title(agent: "codex", sessionId: "nope", transcriptPath: nil) == nil)
    }

    // MARK: On the rows

    func session(_ id: String, title: String?, at: TimeInterval = 0) -> AgentSession {
        var s = AgentSession(id: id, agent: "claude-code", cwd: "/git/sidefolk", state: .working, now: Date(timeIntervalSince1970: at))
        s.conversationTitle = title
        return s
    }

    @Test func twoConversationsInOneFolderStandApart() {
        let groups = AgentSessionGroup.of([session("a", title: "Fix login"), session("b", title: "Write docs")])
        #expect(groups.count == 2)
        #expect(AgentLane.chips([session("a", title: "Fix login")]).first?.title == "Fix login")
    }

    @Test func oneWithNoTitleJoinsThemAndKeepsTheTitle() {
        let groups = AgentSessionGroup.of([session("a", title: "Fix login", at: 0), session("sub", title: nil, at: 10)])
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].session.conversationTitle == "Fix login")
    }

    /// What opens is the session the row names, and how long it says is its own group's.
    @Test func theTitledOneStandsForTheGroupWhateverCameLast() {
        let groups = AgentSessionGroup.of([session("sub", title: nil, at: 500), session("a", title: "Fix login", at: 100)])
        #expect(groups[0].session.id == "a")
        #expect(groups[0].since == Date(timeIntervalSince1970: 100))
        let chips = AgentLane.chips([session("old", title: "Old one", at: 0), session("new", title: "New one", at: 1000)])
        #expect(chips.first { $0.title == "New one" }?.since == Date(timeIntervalSince1970: 1000))
    }

    @Test func withNoTitlesTheyStayOneLine() {
        #expect(AgentSessionGroup.of([session("a", title: nil), session("b", title: nil)]).count == 1)
    }

    // MARK: Through the tracker

    @Test func theTrackerKeepsTheTitleAndAQuickHookDoesntLookAgain() async throws {
        let env = try TestEnv()
        let store = SessionStore(env.db)
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        let tracker = SessionTracker(store: store, attention: attention, events: env.events, clock: env.clock, titles: titles)
        let path = try transcript([#"{"type":"custom-title","customTitle":"First name"}"#])
        var event = SessionEvent(event: "PreToolUse", sessionId: "s1", cwd: "/git/x")
        event.transcriptPath = path
        _ = await tracker.apply(event)
        #expect(try await store.session(id: "s1")?.conversationTitle == "First name")
        _ = try transcript([#"{"type":"custom-title","customTitle":"Second name"}"#])
        _ = await tracker.apply(event)
        #expect(try await store.session(id: "s1")?.conversationTitle == "First name", "looked a moment ago")
        env.clock.advance(30)
        _ = await tracker.apply(event)
        #expect(try await store.session(id: "s1")?.conversationTitle == "Second name")
    }
}
