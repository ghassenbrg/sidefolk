import Foundation
import Testing
@testable import SidefolkCore

/// Formatted notes (D53): the small Markdown a note's text carries, read line by line.
struct NoteMarksTests {
    @Test func linesKnowTheirBlock() {
        #expect(NoteMarks.line("## Plan").block == .heading(2))
        #expect(NoteMarks.line("## Plan").marker == 3)
        #expect(NoteMarks.line("- milk").block == .bullet)
        #expect(NoteMarks.line("  * eggs").indent == 2)
        #expect(NoteMarks.line("12. twelve").block == .numbered(12))
        #expect(NoteMarks.line("- [x] done").block == .check(done: true))
        #expect(NoteMarks.line("- [ ] open").box == NSRange(location: 2, length: 3))
        #expect(NoteMarks.line("> quoted").block == .quote)
        #expect(NoteMarks.line("#hashtag").block == .paragraph)
        #expect(NoteMarks.line("-not a list").block == .paragraph)
    }

    @Test func returnContinuesALineOrEndsIt() {
        #expect(NoteMarks.continuation(of: "- milk") == "- ")
        #expect(NoteMarks.continuation(of: "3. three") == "4. ")
        #expect(NoteMarks.continuation(of: "  - [x] done") == "  - [ ] ")
        #expect(NoteMarks.continuation(of: "- ") == "")
        #expect(NoteMarks.continuation(of: "Just words") == nil)
    }

    @Test func aBoxTicksAndUnticks() {
        let text = "Shopping\n- [ ] milk\n- [x] eggs"
        #expect(NoteMarks.toggledCheck(text, lineStart: 9) == "Shopping\n- [x] milk\n- [x] eggs")
        #expect(NoteMarks.toggledCheck(text, lineStart: 20) == "Shopping\n- [ ] milk\n- [ ] eggs")
        #expect(NoteMarks.toggledCheck(text, lineStart: 0) == nil)
    }

    @Test func formattingButtonsSetAndClearABlock() {
        #expect(NoteMarks.setting(.check(done: false), on: "milk") == "- [ ] milk")
        #expect(NoteMarks.setting(.check(done: false), on: "- [x] milk") == "milk")
        #expect(NoteMarks.setting(.bullet, on: "- [ ] milk") == "- milk")
        #expect(NoteMarks.setting(.heading(1), on: "## Title") == "# Title")
        #expect(NoteMarks.setting(.heading(2), on: "## Title") == "Title")
    }

    @Test func inlineSpansAndTheirMarks() {
        let spans = NoteMarks.spans(in: "a **bold** and *it* or ~~gone~~, `x*y*z` [site](https://example.com)")
        #expect(spans.map(\.kind) == [.bold, .italic, .strike, .code, .link])
        #expect(spans[0].markers == [NSRange(location: 2, length: 2), NSRange(location: 8, length: 2)])
        #expect(NoteMarks.url(of: spans[4], in: "a **bold** and *it* or ~~gone~~, `x*y*z` [site](https://example.com)")
            == URL(string: "https://example.com"))
        #expect(NoteMarks.spans(in: "2 * 3 * 4").isEmpty)
        #expect(NoteMarks.spans(in: "snake_case_name").isEmpty)
    }

    @Test func plainLinesReadWithoutMarks() {
        #expect(NoteMarks.plain("- [ ] **Oat** milk") == "Oat milk")
        #expect(NoteMarks.plain("## A [link](https://a.b) here") == "A link here")
        #expect(NoteMarks.plain("Nothing special") == "Nothing special")
    }
}
