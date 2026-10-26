import Foundation

/// Reports one value from a web page or an API at every check: a number or a few words found by a JSON path, a
/// simple selector or a pattern. The value is someone else's text, so it is marked as coming from outside.
public struct WebValueProbe: WatcherProbe {
    public let kind = WatchKind.webValue
    public var defaultInterval: TimeInterval { 5 * 60 }
    public var minimumInterval: TimeInterval { ReportFloors.web }

    let web: ProbeFetching

    public init(fetcher: any WatchFetcher, throttle: HostThrottle = HostThrottle()) {
        web = ProbeFetching(fetcher: fetcher, throttle: throttle)
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        if !WatchSource.mayTargetLocal(w.source) { w.config = w.config.setting("allow_local", nil) }
        let url = try WebTarget.normalise(w.config.string("url"), allowLocal: w.allowsLocal)
        _ = try ValueExtractor.rule(from: w.config)
        var config = Report.options(of: w.config).setting("url", .string(url.absoluteString))
        for key in ["json_path", "selector", "regex", "allow_local"] { config = config.setting(key, w.config[key]) }
        w.mode = .report
        w.config = config
        w.condition = .object([:])
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        guard let url = WebTarget.url(in: w.config) else { throw ProbeError.invalid(String(localized: "This report has no web address.")) }
        let rule: ValueExtractor.Rule
        do { rule = try ValueExtractor.rule(from: w.config) } catch { throw ProbeError.invalid(WatcherEngine.reason(for: error)) }
        let previous = w.lastState
        let request = FetchRequest(url: url, ifNoneMatch: previous?.string("etag"), ifModifiedSince: previous?.string("last_modified"),
                                   allowLocal: w.allowsLocal)
        let response: FetchResponse
        switch try await web.fetch(request, now: now) {
        case .unreachable(let why): throw ProbeError.failed(why)
        case .response(let r): response = r
        }
        // Unchanged since last time: the same value, for the price of the headers.
        if response.status == 304, let shown = previous?["reading"]?.string("shown"), let state = previous?.setting("reading", nil) {
            return ProbeResult(state: state, reading: ReadingText(shown: shown, forModel: shown, fromOutside: true))
        }
        guard (200..<300).contains(response.status) else {
            throw ProbeError.failed(String(localized: "The page said \(ProbeFetching.httpWords(response.status))."))
        }
        guard let value = ValueExtractor.value(in: response.body, contentType: response.contentType, rule: rule) else {
            let place = (w.config.string("json_path") ?? w.config.string("selector") ?? w.config.string("regex") ?? "").clipped(60)
            let why = String(localized: "I found no value at “\(place)” on \(WebTarget.displayName(url)).")
            // Never found at all: the place to look is wrong, and asking again won't fix it. Once found, a miss is a hiccup.
            throw previous?["reading"] == nil ? ProbeError.invalid(why) : ProbeError.failed(why)
        }
        var state: [String: JSONValue] = [:]
        if let tag = response.headers["etag"] { state["etag"] = .string(tag) }
        if let modified = response.headers["last-modified"] { state["last_modified"] = .string(modified) }
        return ProbeResult(state: .object(state), reading: ReadingText(shown: value, forModel: value, fromOutside: true))
    }
}
