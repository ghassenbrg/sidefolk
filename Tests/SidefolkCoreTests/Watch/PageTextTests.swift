import Foundation
import Testing
@testable import SidefolkCore

@Suite struct PageTextTests {
    func normalise(_ html: String, type: String = "text/html") -> String {
        PageText.normalise(Data(html.utf8), contentType: type)
    }

    @Test func dropsScriptsStylesAndTagsAndDecodesEntities() {
        let html = """
        <html><head><title>Pricing</title><style>.a { color: red }</style><script>var secret = "x";</script></head>
        <body><h1>Plans</h1><p>Pro &amp; Team: &pound;19&nbsp;a month</p><noscript>Turn on JavaScript</noscript>
        <!-- hidden comment --><p>Euro &#8364; and &#x20AC;</p></body></html>
        """
        #expect(normalise(html) == "Pricing\nPlans\nPro & Team: £19 a month\nEuro € and €")
    }

    @Test func collapsesWhitespaceAndKeepsLinesApart() {
        let html = "<div>  Hello \n\t   world  </div><div></div><div>Second<br>line</div>"
        #expect(normalise(html) == "Hello world\nSecond\nline")
    }

    @Test func timestampsDatesAndCountersAreNotContent() {
        let html = """
        <p>Last updated: Oct 22, 2025 10:30 AM</p><p>Posted 3 hours ago</p><p>12,345 views</p><p>2025-10-22T10:30:00Z</p>
        <p>© 2025 Acme Inc. All rights reserved.</p><p>Price: $19.99</p><p>In stock: 3 left</p><p>Up to 100 downloads per month on Pro</p>
        """
        #expect(normalise(html) == "Price: $19.99\nIn stock: 3 left\nUp to 100 downloads per month on Pro")
    }

    @Test func jsonIsPrettyPrintedSoChangesAreOneLine() {
        let text = normalise(#"{"b":2,"a":{"price":19}}"#, type: "application/json")
        #expect(text.contains("\"price\" : 19"))
        #expect(text.components(separatedBy: "\n").count > 3)
    }

    @Test func plainTextIsKeptAsLines() {
        #expect(normalise("one\n\n  two  \nthree", type: "text/plain") == "one\ntwo\nthree")
    }

    @Test func hiddenCharactersAreStripped() {
        let sneaky = "Hello\u{200B} \u{202E}world"
        #expect(normalise("<p>\(sneaky)</p>") == "Hello world")
    }

    @Test func honoursDeclaredCharset() {
        let data = Data("<p>café</p>".utf8)
        #expect(PageText.normalise(data, contentType: "text/html; charset=utf-8") == "café")
        let latin = "<p>café</p>".data(using: .isoLatin1)!
        #expect(PageText.normalise(latin, contentType: "text/html; charset=iso-8859-1") == "café")
        #expect(PageText.normalise(latin, contentType: "text/html") == "café") // falls back to Latin-1
    }

    @Test func hugePagesAreCapped() {
        let line = String(repeating: "word ", count: 20)
        let html = (0..<5000).map { "<p>\(line)\($0)</p>" }.joined()
        let text = normalise(html)
        #expect(text.count <= PageText.maxCharacters + 10)
        #expect(text.hasSuffix("…"))
    }
}

@Suite struct TextDiffTests {
    @Test func identicalTextIsNoChange() {
        let c = TextDiff.compare(old: "a\nb\nc", new: "a\nb\nc")
        #expect(c.isEmpty)
        #expect(!c.isSignificant)
    }

    @Test func aPriceChangeIsSignificantAndShowsBeforeAndAfter() {
        let old = (["Header", "Price: $19", "Footer"] + (0..<200).map { "Filler line number \($0)" }).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "Price: $19", with: "Price: $29")
        let c = TextDiff.compare(old: old, new: new)
        #expect(c.isSignificant)
        #expect(c.removed == ["Price: $19"])
        #expect(c.added == ["Price: $29"])
        #expect(c.ratio < 0.01) // tiny share of the page, but a line a person would read
        #expect(c.snippet == "“Price: $19” → “Price: $29”")
    }

    @Test func dateOnlyAndCounterOnlyChangesAreIgnored() {
        let old = "Sale ends Oct 30, 2025\nNext release 14:30 UTC\nSupport since 2019-01-01"
        let new = "Sale ends Nov 5, 2025\nNext release 09:15 UTC\nSupport since 2020-02-02"
        let c = TextDiff.compare(old: old, new: new)
        #expect(c.isEmpty)
        #expect(!c.isSignificant)
    }

    @Test func addedAndRemovedLinesAreReportedInReadingOrder() {
        let c = TextDiff.compare(old: "keep\nold one\nkeep too\nold two", new: "keep\nkeep too\nnew one")
        #expect(c.removed == ["old one", "old two"])
        #expect(c.added == ["new one"])
        #expect(c.snippet.contains("“old one” → “new one”"))
        #expect(c.snippet.contains("Removed: “old two”"))
    }

    @Test func manyChangesAreSummarised() {
        let old = (0..<10).map { "old \($0)" }.joined(separator: "\n")
        let new = (0..<10).map { "new \($0)" }.joined(separator: "\n")
        let c = TextDiff.compare(old: old, new: new)
        #expect(c.snippet.contains("and 15 more changes"))
    }

    @Test func aLargeShareOfCharactersIsSignificant() {
        let c = TextDiff.compare(old: "x", new: String(repeating: "y", count: 100))
        #expect(c.ratio >= 1)
        #expect(c.isSignificant)
    }

    @Test func containsIgnoresCaseAndWhitespace() {
        #expect(TextDiff.contains("Item is\nIN  stock now", "in stock"))
        #expect(!TextDiff.contains("sold out", "in stock"))
        #expect(!TextDiff.contains("anything", "  "))
    }
}
