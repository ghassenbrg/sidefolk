import Foundation
import SidefolkExtensionKit

/// RSS and Atom: the latest posts of a blog, a news site or a podcast, found from the site's own address when
/// it names its feed.
@MainActor
enum Feeds {
    struct Item {
        var title = ""
        var link = ""
        var date = ""
        var id: String { link.isEmpty ? title : link }
    }

    static func load(_ raw: String) async throws -> (title: String, address: URL, items: [Item]) {
        guard var address = URL(string: raw.trimmingCharacters(in: .whitespaces).hasPrefix("http") ? raw : "https://" + raw),
              ["http", "https"].contains(address.scheme ?? "") else {
            throw Problem("Give the feed's or the site's web address, like https://example.com/blog.")
        }
        var data = try await Web.data(address)
        var parsed = Parser.parse(data)
        if parsed.items.isEmpty, let feed = discover(String(decoding: data.prefix(200_000), as: UTF8.self), base: address) {
            address = feed
            data = try await Web.data(feed)
            parsed = Parser.parse(data)
        }
        guard parsed.isFeed else { throw Problem("I couldn't find an RSS or Atom feed at \(address.absoluteString).") }
        return (parsed.title.isEmpty ? address.host ?? "The feed" : parsed.title, address, parsed.items)
    }

    /// `<link rel="alternate" type="application/rss+xml" href="…">` in a web page.
    nonisolated static func discover(_ html: String, base: URL) -> URL? {
        for tag in html.matches(of: /<link\b[^>]*>/.ignoresCase()) {
            let text = String(tag.0)
            guard text.range(of: #"type=["']application/(rss|atom)\+xml["']"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = text.firstMatch(of: /href=["']([^"']+)["']/.ignoresCase())?.1 else { continue }
            return URL(string: String(href).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
        }
        return nil
    }

    static func latest(_ raw: String, count: Int) async throws -> String {
        let feed = try await load(raw)
        guard !feed.items.isEmpty else { return "\(feed.title) has no posts yet." }
        let lines = feed.items.prefix(count).map { item in
            "- \(item.title.isEmpty ? "(untitled)" : item.title)" + (item.date.isEmpty ? "" : " (\(item.date))") + (item.link.isEmpty ? "" : ": \(item.link)")
        }
        return "\(feed.title), latest \(lines.count):\n" + lines.joined(separator: "\n")
    }

    /// Tells about posts it hasn't seen; the first check only remembers what is there.
    static func newPosts(_ settings: Arguments, state: [String: Any]) async throws -> Check {
        let feed = try await load(try settings.required("url"))
        let seen = Set(state["seen"] as? [String] ?? [])
        let ids = feed.items.prefix(50).map(\.id)
        let fresh = state["seen"] == nil ? [] : feed.items.prefix(50).filter { !seen.contains($0.id) }
        let summary = fresh.isEmpty ? "No new posts on \(feed.title)."
            : "New on \(feed.title): " + fresh.prefix(3).map { $0.title.isEmpty ? "(untitled)" : "“\($0.title)”" }.joined(separator: ", ")
                + (fresh.count > 3 ? " and \(fresh.count - 3) more." : ".")
        return Check(triggered: !fresh.isEmpty, state: ["seen": Array(ids)], summary: summary)
    }
}

/// Just enough of RSS 2.0, RSS 1.0 and Atom: the feed's title, and each item's title, link and date.
final class Parser: NSObject, XMLParserDelegate {
    private(set) var title = ""
    private(set) var items: [Feeds.Item] = []
    private(set) var isFeed = false
    private var current: Feeds.Item?
    private var text = ""

    static func parse(_ data: Data) -> Parser {
        let parser = Parser()
        let xml = XMLParser(data: data)
        xml.shouldResolveExternalEntities = false
        xml.delegate = parser
        xml.parse()
        return parser
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        switch name {
        case "rss", "feed", "rdf:RDF": isFeed = true
        case "item", "entry": current = Feeds.Item()
        case "link" where current != nil && attributes["href"] != nil && (attributes["rel"] ?? "alternate") == "alternate":
            current?.link = attributes["href"]!
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil {
            switch name {
            case "title": current?.title = String(value.prefix(200))
            case "link" where !value.isEmpty: current?.link = value
            case "pubDate", "published", "updated", "dc:date": if current?.date.isEmpty == true { current?.date = String(value.prefix(40)) }
            case "item", "entry": items.append(current!); current = nil
            default: break
            }
        } else if name == "title", title.isEmpty {
            title = String(value.prefix(120))
        }
        text = ""
    }
}
