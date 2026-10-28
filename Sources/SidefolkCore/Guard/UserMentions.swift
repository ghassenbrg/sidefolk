import Foundation

/// The web addresses the user typed in the request a run answers (docs/SECURITY.md T1, T2). A
/// network call or an opened link to anything else was built by the model, and its path or query
/// could carry whatever is in the context (About you, notes, live state) to someone else's server,
/// so Guard asks before it leaves the Mac.
public struct UserMentions: Sendable, Hashable {
    /// Normalized addresses: host (no "www."), non-default port, path, query and fragment; no scheme.
    public private(set) var urls: Set<String> = []
    /// Lowercased hosts without a leading "www.".
    public private(set) var hosts: Set<String> = []

    public static let none = UserMentions()

    public init() {}

    /// Every http(s) link in `text`, also bare ones like "example.com/pricing".
    public init(text: String) {
        guard !text.isEmpty else { return }
        var found: [URL] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            found += detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
        }
        // Addresses the detector doesn't know as links (`http://localhost:3000`), written out in full.
        let edges = CharacterSet(charactersIn: "<>()[]{}\"'`,;.!?")
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: edges)
            if word.lowercased().hasPrefix("http://") || word.lowercased().hasPrefix("https://"), let url = URL(string: word) {
                found.append(url)
            }
        }
        for url in found {
            guard let key = Self.key(url), let host = Self.host(url) else { continue }
            urls.insert(key)
            hosts.insert(host)
        }
    }

    /// A well-formed web address on a public-looking host (what web and open tools accept from
    /// anyone but the user). Anything else is refused by those tools themselves, so it needs no card.
    public static func isWebAddress(_ text: String) -> Bool {
        guard let url = try? URLPolicy.parseWebURL(text) else { return false }
        return (try? URLPolicy.checkHost(url)) != nil
    }

    /// The exact address appears in what the user typed (http and https count as the same).
    public func contains(url text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let key = Self.key(url) else { return false }
        return urls.contains(key)
    }

    /// The address's site appears in what the user typed and the address carries no query or fragment
    /// the model could have filled in. Used for opening links, never for fetching.
    public func containsSite(of text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = Self.host(url),
              Self.isWeb(url), url.query == nil, url.fragment == nil else { return false }
        return hosts.contains(host)
    }

    static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    static func host(_ url: URL) -> String? {
        url.host.flatMap(site)
    }

    /// A host name as a site: lower case, without "www." or a final dot, which name the same site.
    static func site(_ host: String) -> String? {
        var host = host.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    static func key(_ url: URL) -> String? {
        guard isWeb(url), url.user == nil, url.password == nil, let host = host(url) else { return nil }
        var key = host
        if let port = url.port, port != 80, port != 443 { key += ":\(port)" }
        var path = url.path(percentEncoded: true)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        key += path.isEmpty ? "/" : path
        if let query = url.query(percentEncoded: true) { key += "?" + query }
        if let fragment = url.fragment(percentEncoded: true) { key += "#" + fragment }
        return key
    }
}
