import Foundation

/// Picks one number or a few words out of a web reply: a path into JSON ("current.temperature_2m",
/// "data[0].price"), a simple selector into HTML ("span.price", "#total", "td"), or a regular expression (its first
/// group, else the whole match). Deliberately small: no scripts run, nothing else is loaded.
enum ValueExtractor {
    enum Rule: Equatable {
        case jsonPath([PathStep])
        case selector(Selector)
        case regex(NSRegularExpression)
    }

    enum PathStep: Equatable {
        case key(String)
        case index(Int)
    }

    struct Selector: Equatable {
        var tag: String?
        var className: String?
        var id: String?
    }

    /// The most text a value may have before it is no longer a value.
    static let maxValue = 80
    /// Pages are searched only this far, so a pattern can't spend long on a huge reply.
    static let maxScan = 200_000

    // MARK: Reading the rule

    /// From the tool's or the watcher's config: exactly one of `json_path`, `selector`, `regex`.
    static func rule(from config: JSONValue) throws -> Rule {
        let given = [("json_path", config.string("json_path")), ("selector", config.string("selector")), ("regex", config.string("regex"))]
            .filter { $0.1 != nil }
        guard given.count == 1, let (key, text) = given.first, let text, text.count <= 200 else {
            throw WatchError.invalid(String(localized: "Tell me where the value is: one JSON path, selector or pattern."))
        }
        switch key {
        case "json_path":
            guard let steps = path(text) else { throw WatchError.invalid(String(localized: "I can't read “\(text)” as a JSON path, like current.temperature_2m or data[0].price.")) }
            return .jsonPath(steps)
        case "selector":
            guard let selector = selector(text) else { throw WatchError.invalid(String(localized: "I can only use simple selectors, like span.price, #total or td.")) }
            return .selector(selector)
        default:
            guard let regex = try? NSRegularExpression(pattern: text, options: [.caseInsensitive]) else {
                throw WatchError.invalid(String(localized: "That pattern isn't a regular expression I can use."))
            }
            return .regex(regex)
        }
    }

    /// "$.data[0].price" → key data, index 0, key price.
    static func path(_ text: String) -> [PathStep]? {
        var s = Substring(text)
        if s.hasPrefix("$.") { s = s.dropFirst(2) } else if s.hasPrefix("$") { s = s.dropFirst() }
        var steps: [PathStep] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            let open = part.firstIndex(of: "[") ?? part.endIndex
            let key = part[..<open]
            if !key.isEmpty { steps.append(.key(String(key))) }
            var rest = part[open...]
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]"), let n = Int(rest[rest.index(after: rest.startIndex)..<close]), n >= 0 else { return nil }
                steps.append(.index(n))
                rest = rest[rest.index(after: close)...]
            }
            guard rest.isEmpty, !(key.isEmpty && part.first != "[") else { return nil }
        }
        return steps.isEmpty ? nil : steps
    }

    /// "span.price", ".price", "#total", "td": one tag, class or id (or a tag with one of them).
    static func selector(_ text: String) -> Selector? {
        let name = #"[A-Za-z][\w-]*"#
        let pattern = "^(\(name))?(?:\\.(\(name))|#(\(name)))?$"
        guard let groups = Scan(pattern).groups(in: text), !text.isEmpty else { return nil }
        func part(_ i: Int) -> String? { groups[i].isEmpty ? nil : groups[i] }
        return Selector(tag: part(1)?.lowercased(), className: part(2), id: part(3))
    }

    // MARK: Finding the value

    static func value(in body: Data, contentType: String?, rule: Rule) -> String? {
        let text = String(decoding: body.prefix(maxScan), as: UTF8.self)
        let found: String?
        switch rule {
        case .jsonPath(let steps):
            found = (try? JSONValue.parse(body)).flatMap { follow(steps, in: $0) }
        case .selector(let selector):
            found = element(selector, in: text)
        case .regex(let regex):
            found = match(regex, in: text) ?? match(regex, in: PageText.normalise(body, contentType: contentType))
        }
        let clean = found?.displaySafe ?? ""
        return clean.isEmpty || clean.count > maxValue ? nil : clean
    }

    static func follow(_ steps: [PathStep], in json: JSONValue) -> String? {
        var node = json
        for step in steps {
            switch step {
            case .key(let k): guard let next = node[k] else { return nil }; node = next
            case .index(let i): guard let a = node.arrayValue, a.indices.contains(i) else { return nil }; node = a[i]
            }
        }
        switch node {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    static func match(_ regex: NSRegularExpression, in text: String) -> String? {
        let scanned = String(text.prefix(maxScan))
        guard let m = regex.firstMatch(in: scanned, range: NSRange(scanned.startIndex..., in: scanned)) else { return nil }
        let range = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range
        return Range(range, in: scanned).map { String(scanned[$0]) }
    }

    /// The text inside the first element that fits the selector, with its own tags taken out.
    static func element(_ selector: Selector, in html: String) -> String? {
        let tag = selector.tag.map(NSRegularExpression.escapedPattern(for:)) ?? #"[A-Za-z][\w-]*"#
        guard let open = try? NSRegularExpression(pattern: "<(\(tag))\\b([^>]*)>", options: [.caseInsensitive]) else { return nil }
        let whole = NSRange(html.startIndex..., in: html)
        for m in open.matches(in: html, range: whole) {
            guard let nameRange = Range(m.range(at: 1), in: html), let attrRange = Range(m.range(at: 2), in: html),
                  let after = Range(m.range, in: html)?.upperBound else { continue }
            let attributes = String(html[attrRange])
            if let id = selector.id, attribute("id", in: attributes) != id { continue }
            if let cls = selector.className, !(attribute("class", in: attributes)?.split(separator: " ").contains(Substring(cls)) ?? false) { continue }
            let name = html[nameRange].lowercased()
            let end = html.range(of: "</\(name)", options: [.caseInsensitive], range: after..<html.endIndex)?.lowerBound ?? html.endIndex
            let inner = String(html[after..<end]).replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
            return HTMLEntities.decode(inner).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return nil
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        Scan("\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))").groups(in: attributes).map { g in
            g.dropFirst().first { !$0.isEmpty } ?? ""
        }
    }
}
