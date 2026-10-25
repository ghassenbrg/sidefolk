import CryptoKit
import Foundation

// MARK: Shared web plumbing

enum WebTarget {
    /// A web address typed by a person: "example.com/pricing" means https.
    static func normalise(_ text: String?, allowLocal: Bool) throws -> URL {
        guard var s = text?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            throw WatchError.invalid("Tell me which web address to watch.")
        }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { throw WatchError.invalid(URLPolicyError.noHost.description) }
        do { try URLPolicy.checkSyntax(url, allowLocal: allowLocal) } catch { throw WatchError.invalid(String(describing: error)) }
        return url
    }

    static func url(in config: JSONValue) -> URL? { config.string("url").flatMap(URL.init(string:)) }

    /// "example.com/pricing": what a person would call the page.
    static func displayName(_ url: URL) -> String {
        var name = URLPolicy.hostName(of: url) ?? url.absoluteString
        if let port = url.port { name += ":\(port)" }
        let path = url.path
        if path.count > 1 { name += path.hasSuffix("/") ? String(path.dropLast()) : path }
        if url.query != nil { name += "?…" }
        return name.clipped(70)
    }
}

/// What a fetch came back with, separating "the site did not answer" from "we must not ask".
enum FetchOutcome {
    case response(FetchResponse)
    case unreachable(String)
}

/// Fetching with the politeness rules: one request a minute per host, friendly errors.
struct WebFetching: Sendable {
    let fetcher: any WatchFetcher
    let throttle: HostThrottle

    func fetch(_ request: FetchRequest, now: Date, throttled: Bool = true) async throws -> FetchOutcome {
        if throttled, !WatchContext.isManualCheck, let host = URLPolicy.hostName(of: request.url),
           let later = throttle.reserve(host: host, now: now) {
            throw ProbeError.deferred(until: later)
        }
        do {
            return .response(try await fetcher.fetch(request))
        } catch let error as URLPolicyError {
            throw ProbeError.failed(error.description)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: throw ProbeError.offline
            case .cancelled: throw CancellationError()
            case .timedOut: return .unreachable("The site didn't answer in time.")
            case .cannotFindHost, .dnsLookupFailed: return .unreachable("I couldn't find that website.")
            case .cannotConnectToHost: return .unreachable("The site refused the connection.")
            case .networkConnectionLost: return .unreachable("The connection dropped.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
                return .unreachable("The site's security certificate isn't valid.")
            default: return .unreachable("I couldn't reach the site.")
            }
        }
    }

    static func httpWords(_ status: Int) -> String {
        "“\(HTTPURLResponse.localizedString(forStatusCode: status))” (\(status))"
    }
}

// MARK: url_change

/// What a page watcher is waiting for.
struct PageCondition: Equatable {
    var changed: Bool
    var contains: String?
    var notContains: String?

    init(_ json: JSONValue) {
        contains = json.string("contains")
        notContains = json.string("not_contains")
        changed = json["changed"]?.boolValue ?? (contains == nil && notContains == nil)
    }

    var hasText: Bool { contains != nil || notContains != nil }

    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let contains { o["contains"] = .string(contains) }
        if let notContains { o["not_contains"] = .string(notContains) }
        if !hasText { o["changed"] = .bool(true) }
        return .object(o)
    }
}

public struct UrlChangeProbe: WatcherProbe {
    public let kind = WatchKind.urlChange
    public var defaultInterval: TimeInterval { 30 * 60 }
    public var minimumInterval: TimeInterval { 5 * 60 }

    let web: WebFetching

    public init(fetcher: any WatchFetcher, throttle: HostThrottle = HostThrottle()) {
        web = WebFetching(fetcher: fetcher, throttle: throttle)
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        if !WatchSource.mayTargetLocal(w.source) { w.config = w.config.setting("allow_local", nil) }
        let url = try WebTarget.normalise(w.config.string("url"), allowLocal: w.allowsLocal)
        w.config = w.config.setting("url", .string(url.absoluteString))
        let condition = PageCondition(w.condition)
        if !condition.changed && !condition.hasText { throw WatchError.invalid("Tell me what to look for on the page, or to watch for any change.") }
        for text in [condition.contains, condition.notContains].compactMap({ $0 }) where text.count > 200 {
            throw WatchError.invalid("The words to look for are too long (200 characters at most).")
        }
        w.condition = condition.json
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        guard let url = WebTarget.url(in: w.config) else { throw ProbeError.failed("This watcher has no web address.") }
        let condition = PageCondition(w.condition)
        let previous = w.lastState
        let request = FetchRequest(url: url, ifNoneMatch: previous?.string("etag"), ifModifiedSince: previous?.string("last_modified"),
                                   allowLocal: w.allowsLocal)
        let response: FetchResponse
        switch try await web.fetch(request, now: now) {
        case .unreachable(let why): throw ProbeError.failed(why)
        case .response(let r): response = r
        }
        if response.status == 304, let previous { return ProbeResult(state: previous) }
        guard (200..<300).contains(response.status) else {
            throw ProbeError.failed("The page said \(WebFetching.httpWords(response.status)).")
        }

        let text = PageText.normalise(response.body, contentType: response.contentType)
        let name = WebTarget.displayName(url)
        if text.isEmpty, previous?["text"]?.stringValue?.isEmpty == false {
            throw ProbeError.failed("The page came back empty.")
        }

        var state: [String: JSONValue] = [
            "text": .string(text),
            "hash": .string(Self.hash(text)),
        ]
        if let tag = response.headers["etag"] { state["etag"] = .string(tag) }
        if let modified = response.headers["last-modified"] { state["last_modified"] = .string(modified) }
        let open = url.absoluteString

        if condition.hasText {
            let hasContains = condition.contains.map { TextDiff.contains(text, $0) } ?? true
            let hasNot = condition.notContains.map { !TextDiff.contains(text, $0) } ?? true
            let matched = hasContains && hasNot
            state["matched"] = .bool(matched)
            let wasMatched = previous?["matched"]?.boolValue ?? false
            guard matched, !wasMatched else { return ProbeResult(state: .object(state)) }
            let summary: String
            if let want = condition.contains, condition.notContains == nil {
                summary = "\(name) now says “\(want.clipped(60))”"
            } else if let gone = condition.notContains, condition.contains == nil {
                summary = "“\(gone.clipped(60))” is gone from \(name)"
            } else {
                summary = "\(name) now matches what you were waiting for"
            }
            let line = condition.contains.flatMap { want in text.components(separatedBy: "\n").first { TextDiff.contains($0, want) } }
            return ProbeResult(state: .object(state), triggered: true, summary: summary, detail: line?.clipped(160), openTarget: open)
        }

        guard let before = previous?["text"]?.stringValue else {
            return ProbeResult(state: .object(state)) // first look: this is what "unchanged" means from now on
        }
        let change = TextDiff.compare(old: before, new: text)
        guard change.isSignificant else { return ProbeResult(state: .object(state)) }
        return ProbeResult(state: .object(state), triggered: true, summary: "\(name) changed", detail: change.snippet, openTarget: open)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: site_status

public struct SiteStatusProbe: WatcherProbe {
    public let kind = WatchKind.siteStatus
    public var defaultInterval: TimeInterval { 60 }
    public var minimumInterval: TimeInterval { 60 }
    /// A site that flaps should not ring every few minutes; two confirmations already filter blips.
    public var repeatCooldown: TimeInterval { 5 * 60 }

    let web: WebFetching

    public init(fetcher: any WatchFetcher, throttle: HostThrottle = HostThrottle()) {
        web = WebFetching(fetcher: fetcher, throttle: throttle)
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        if !WatchSource.mayTargetLocal(w.source) { w.config = w.config.setting("allow_local", nil) }
        let url = try WebTarget.normalise(w.config.string("url"), allowLocal: w.allowsLocal)
        w.config = w.config.setting("url", .string(url.absoluteString))
        let becomes = w.condition.string("becomes")?.lowercased() ?? "any"
        guard ["up", "down", "any"].contains(becomes) else { throw WatchError.invalid("“becomes” must be up, down or any.") }
        w.condition = ["becomes": .string(becomes)]
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        guard let url = WebTarget.url(in: w.config) else { throw ProbeError.failed("This watcher has no web address.") }
        let becomes = w.condition.string("becomes") ?? "any"
        let method = w.config.string("method")?.uppercased() == "GET" ? "GET" : "HEAD"

        // A second look to confirm is the point; one request per check keeps us polite.
        let observed: (up: Bool, why: String)
        switch try await web.fetch(FetchRequest(url: url, method: method, allowLocal: w.allowsLocal, headersOnly: true), now: now) {
        case .unreachable(let why): observed = (false, why)
        case .response(var r):
            if method == "HEAD", r.status == 405 || r.status == 501 {
                // Some servers refuse HEAD; ask the same question with GET.
                if case .response(let again) = try await web.fetch(FetchRequest(url: url, allowLocal: w.allowsLocal, headersOnly: true), now: now, throttled: false) {
                    r = again
                }
            }
            observed = r.status < 400 ? (true, "") : (false, "It answered \(WebFetching.httpWords(r.status)).")
        }

        let observation = observed.up ? "up" : "down"
        let previous = w.lastState
        let confirmed = previous?.string("confirmed")
        var pending = previous?.string("pending")
        var count = previous?["pending_count"]?.intValue ?? 0

        var state: [String: JSONValue] = [:]
        var flipped = false
        var nowConfirmed = confirmed
        if observation == confirmed {
            pending = nil
            count = 0
        } else {
            count = pending == observation ? count + 1 : 1
            pending = observation
            if count >= 2 { // two in a row: believe it
                flipped = confirmed != nil // the very first confirmation is a baseline, not news
                nowConfirmed = observation
                pending = nil
                count = 0
            }
        }
        if let nowConfirmed { state["confirmed"] = .string(nowConfirmed) }
        if let pending { state["pending"] = .string(pending); state["pending_count"] = .number(Double(count)) }
        if !observed.why.isEmpty { state["why"] = .string(observed.why) }

        guard flipped, becomes == "any" || becomes == observation else { return ProbeResult(state: .object(state)) }

        let name = WebTarget.displayName(url)
        return observed.up
            ? ProbeResult(state: .object(state), triggered: true, summary: "\(name) is back up", openTarget: url.absoluteString)
            : ProbeResult(state: .object(state), triggered: true, summary: "\(name) is down", detail: observed.why, openTarget: url.absoluteString)
    }
}
