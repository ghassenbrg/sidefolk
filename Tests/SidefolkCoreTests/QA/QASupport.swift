import Foundation
@testable import SidefolkCore

// QA review (adversarial): the misparses found by feeding the local parser ~900 phrasings, kept as regression tests.
// The contract is "exactly right, or nil (the AI takes over)"; the "Expected:" comment above each test says what correct looks like.
// Run: `swift test --no-parallel --filter QA`.

/// Shared helpers for the QA suites. "Now" is Wednesday 22 October 2025, 10:00 UTC unless a test says otherwise.
enum QA {
    static let cal = TimeTest.utc
    static let wed10 = TimeTest.wednesday10
    static let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date { TimeTest.date(y, m, d, h, min) }

    static func parse(_ text: String, now: Date = wed10, known: [String] = ["Sidefolk", "Work"]) -> LocalIntent? {
        parser.parse(text, now: now, knownCollections: known)?.intent
    }

    /// Readable description of an intent for failure messages.
    static func describe(_ intent: LocalIntent?) -> String {
        guard let intent else { return "nil (left to the AI)" }
        switch intent {
        case .remind(let title, let when, let rec, let important, _):
            return "remind “\(title)” at \(TimeTest.show(when))" + (important ? " (important)" : "") + (rec.map { " repeating \($0.frequency) x\($0.interval) \($0.weekdays)" } ?? "")
        case .needsTime(let title, let reason, _): return "needsTime “\(title)” (\(reason ?? "no reason"))"
        case .needsTarget(let kind, let becomes): return "needsTarget \(kind) \(becomes ?? "-")"
        case .needsPlace(let quantity): return "needsPlace \(quantity.rawValue)"
        case .note(let kind, let text, let collection, _): return "note(\(kind)) “\(text)” in \(collection ?? "Inbox")"
        case .taskWithReminder(let text, let collection, _, let at): return "task “\(text)” in \(collection ?? "Inbox") reminded \(at)"
        case .aboutMe(let fact): return "aboutMe “\(fact)”"
        case .watch(let w): return "watch \(w.kind) \(w.target) contains=\(w.contains ?? "-")"
        case .report(let r): return "report \(r.source) every \(r.everySeconds) s until \(r.until ?? (r.untilStopped ? "stopped" : "-"))"
        case .stopWatch(let ids, let words): return "stop \(ids) “\(words)”"
        case .quiet(let until): return "quiet until \(until.map { TimeTest.show($0) } ?? "off")"
        case .quietOff: return "quietOff"
        case .find(let q, let kind, let collection): return "find “\(q)” kind=\(kind.map { "\($0)" } ?? "-") in \(collection ?? "-")"
        case .companion(let act): return "companion \(act.rawValue)"
        case .read(let source): return "read \(source)"
        case .chance(let c): return "chance \(c.kind.rawValue) x\(c.count) d\(c.sides)\(c.modifier) \(c.hand?.rawValue ?? "-")"
        case .newConversation: return "newConversation"
        }
    }

    /// The contract for a phrase the local parser may not understand: it either returns exactly `expected`
    /// or nil (the AI takes over). Anything else is a misparse.
    static func isCorrectOrNil(_ actual: LocalIntent?, _ expected: LocalIntent) -> Bool { actual == nil || actual == expected }
}
