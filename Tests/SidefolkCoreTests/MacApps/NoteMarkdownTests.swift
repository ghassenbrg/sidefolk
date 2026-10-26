import Foundation
import Testing
@testable import SidefolkCore

@Suite struct NoteMarkdownTests {
    @Test func notesHTMLBecomesMarkdown() {
        let html = """
            <div><h1>Weekend</h1></div>
            <div>Plan for <b>Saturday</b> and <i>Sunday</i>, <strike>not Friday</strike>.</div>
            <div><br></div>
            <ul><li>Market</li><li>Bike<ul><li>Pump tyres</li></ul></li></ul>
            <ol><li>First</li><li>Second</li></ol>
            <div>See <a href="https://example.com/a?b=1&amp;c=2">the map</a> and <a href="javascript:alert(1)">this</a>.</div>
            <div><tt>npm test</tt></div>
            """
        #expect(NoteMarkdown.convert(html) == """
            # Weekend
            Plan for **Saturday** and *Sunday*, ~~not Friday~~.

            - Market
            - Bike
              - Pump tyres
            1. First
            2. Second
            See [the map](https://example.com/a?b=1&c=2) and this.
            `npm test`
            """)
    }

    @Test func tablesKeepTheirCellsOnOneLine() {
        let html = "<object><table><tbody><tr><td><div>Day</div></td><td><div>Train</div></td></tr>"
            + "<tr><td><div>Mon</div></td><td><div>9:12</div></td></tr></tbody></table></object>"
        #expect(NoteMarkdown.convert(html) == "| Day | Train |\n| --- | --- |\n| Mon | 9:12 |")
    }

    @Test func imagesAndAttachmentsAreNamedNotLoaded() {
        let html = "<div>Receipt</div><div><img src=\"cid:abc\"><img src=\"https://tracker.example/p.gif\"></div>"
        #expect(NoteMarkdown.convert(html, attachments: ["abc": "receipt.jpg"]) == "Receipt\n[image: receipt.jpg] [image]")
    }

    @Test func blankLinesCollapseAndScriptsAreDropped() {
        let html = "<div>a</div><div><br></div><div><br></div><div><br></div><script>alert(1)</script><style>x{}</style><div>b&nbsp;&amp;&lt;c&gt;</div>"
        #expect(NoteMarkdown.convert(html) == "a\n\nb &<c>")
    }

    @Test func emptyHeadingsAndItemsLeaveNoStrayMarkers() {
        #expect(NoteMarkdown.convert("<h1></h1><div>text</div><ul><li></li></ul><div>after</div>") == "text\nafter")
        #expect(NoteMarkdown.convert("<div><b><br></b></div><div>x</div>") == "x")
    }

    @Test func titleLineIsDroppedOnlyWhenItIsTheTitle() {
        #expect(NoteMarkdown.droppingTitle("Weekend", from: "# Weekend\nPlan") == "Plan")
        #expect(NoteMarkdown.droppingTitle("Weekend", from: "**Weekend**\n\nPlan") == "Plan")
        #expect(NoteMarkdown.droppingTitle("Weekend", from: "Something else\nPlan") == "Something else\nPlan")
        #expect(NoteMarkdown.droppingTitle("Weekend", from: "Weekend") == "")
    }

    @Test func brokenMarkupNeverCrashes() {
        var generator = SystemRandomNumberGenerator()
        let pieces = ["<div>", "</div>", "<b>", "</b", "<a href=\"", "<ul><li>", "</li>", "<table><tr><td>", "<", ">", "&amp", "&#x1F600;",
                      "text", " ", "\n", "<img src=", "<pre>", "</pre>", "<script>", "<h2>", "</h3>", "<blockquote>", "é"]
        for _ in 0..<2_000 {
            let html = (0..<Int.random(in: 0...40, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
            _ = NoteMarkdown.convert(html)
        }
        #expect(NoteMarkdown.convert("") == "")
    }
}
