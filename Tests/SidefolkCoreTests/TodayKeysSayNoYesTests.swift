import Foundation
import Testing

/// On Today no key says yes (D130): a click puts the keyboard on a row just brought forward, and another agent's question
/// has Yes as its main answer. Nothing can press SwiftUI's keys from the core tests, so this keeps the key handlers free of
/// anything that answers, as `ButtonHitAreaTests` does for buttons.
@Suite struct TodayKeysSayNoYesTests {
    private let source: String

    init() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        source = try String(contentsOf: root.appendingPathComponent("Sources/SidefolkApp/Home/TodayRows.swift"), encoding: .utf8)
    }

    /// The text from `start` up to the next `end`.
    private func part(_ start: String, _ end: String) throws -> String {
        let from = try #require(source.range(of: start), "\(start) is gone: point this test at the keys")
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex), "\(end) is gone")
        return String(source[from.lowerBound..<to.lowerBound])
    }

    @Test func noKeyHandlerAnswersYes() throws {
        let handlers = try [
            part("private func handle(_ press: KeyPress)", "/// Shared row padding"),
            part(".onKeyPress(keys: Self.keys, phases: .down) { press in\n            switch press.key {", ".task {"),
        ]
        for handler in handlers {
            for yes in ["allowOnce", "allowAlways", "isPrimary", "runSkipped", "mayApprove", "action: primary"] {
                #expect(!handler.contains(yes), "a key must not say yes: \(yes)")
            }
        }
    }

    /// Delete's way of saying no, and S's, stay what they say.
    @Test func noAndLaterStaySafe() throws {
        let no = try part("func notNow(_ model: NowModel)", "/// S: later")
        #expect(no.contains(".deny"))
        #expect(!no.contains("allowOnce") && !no.contains("isPrimary") && !no.contains("runSkipped"))
        let later = try part("func snoozed(_ model: NowModel)", "/// Who's asking")
        #expect(later.contains("hasPrefix(\"snooze\")"))
        #expect(!later.contains("isPrimary"))
    }

    @Test func deleteWaitsForTheRowToBeInView() throws {
        #expect(try part("private func no() -> KeyPress.Result", "private func snooze()").contains("guard armed"))
        #expect(try part("case .delete, .deleteForward, KeyEquivalent(\"\\u{7F}\"):\n                guard", "case \"s\":").contains("guard armed"))
    }
}
