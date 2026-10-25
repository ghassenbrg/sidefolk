import Foundation
import Synchronization

public struct FetchRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var ifNoneMatch: String?
    public var ifModifiedSince: String?
    /// Set only for watchers the user made; lets the request reach this Mac or the local network.
    public var allowLocal: Bool
    /// Stop after the status line and headers (an up/down check does not need the page).
    public var headersOnly: Bool

    public init(url: URL, method: String = "GET", ifNoneMatch: String? = nil, ifModifiedSince: String? = nil,
                allowLocal: Bool = false, headersOnly: Bool = false) {
        self.url = url
        self.method = method
        self.ifNoneMatch = ifNoneMatch
        self.ifModifiedSince = ifModifiedSince
        self.allowLocal = allowLocal
        self.headersOnly = headersOnly
    }
}

public struct FetchResponse: Sendable, Equatable {
    public var status: Int
    /// Header names are lower-cased.
    public var headers: [String: String]
    public var body: Data
    public var finalURL: URL
    /// The body was longer than the cap and was cut.
    public var truncated: Bool

    public init(status: Int, headers: [String: String] = [:], body: Data = Data(), finalURL: URL, truncated: Bool = false) {
        self.status = status
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
        self.truncated = truncated
    }

    public var contentType: String? { headers["content-type"] }
}

/// How watcher probes reach the web. Tests use a fake; the app uses `WatchSessionFetcher`.
///
/// Watchers need more than `WebFetching` (the built-in web tool's fetcher) offers: conditional requests
/// so unchanged pages cost almost nothing, HEAD and headers-only checks for up/down, and the response
/// headers. Both share `URLPolicy`, so the rules about where Sidefolk may connect live in one place.
public protocol WatchFetcher: Sendable {
    /// Network trouble throws `URLError`; addresses we refuse throw `URLPolicy.Violation`.
    func fetch(_ request: FetchRequest) async throws -> FetchResponse
}

/// A locked-down fetch (docs/SECURITY.md T11): http(s) only, every redirect and every connected address
/// checked, no cookies, no credentials, 20 s, 2 MB, text-like content only.
public final class WatchSessionFetcher: WatchFetcher {
    public static let userAgent = "Sidefolk/1.0"
    public static let maxBytes = 2 * 1024 * 1024
    public static let timeout: TimeInterval = 20
    public static let maxRedirects = 5

    private let resolver: any HostResolving
    private let timeout: TimeInterval
    private let maxBytes: Int

    public init(resolver: any HostResolving = SystemHostResolver(), timeout: TimeInterval = WatchSessionFetcher.timeout,
                maxBytes: Int = WatchSessionFetcher.maxBytes) {
        self.resolver = resolver
        self.timeout = timeout
        self.maxBytes = maxBytes
    }

    public func fetch(_ request: FetchRequest) async throws -> FetchResponse {
        // Local targets are possible only for a watcher the user made (`allowLocal`), never by default.
        let policy = URLPolicy(resolver: resolver, allowPrivate: request.allowLocal)
        try await policy.validate(request.url)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false

        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("text/html,application/xhtml+xml,application/json,text/*;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        if let tag = request.ifNoneMatch { urlRequest.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        if let since = request.ifModifiedSince { urlRequest.setValue(since, forHTTPHeaderField: "If-Modified-Since") }

        let job = FetchJob(policy: policy, maxBytes: maxBytes, startURL: request.url,
                           headersOnly: request.headersOnly || request.method == "HEAD")
        let session = URLSession(configuration: configuration, delegate: job, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: urlRequest)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.begin(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// One request's delegate: enforces the rules while the bytes arrive and resumes exactly once.
final class FetchJob: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<FetchResponse, any Error>?
        var response: HTTPURLResponse?
        var body = Data()
        var truncated = false
        var stoppedEarly = false
        var failure: (any Error)?
        var hops = 0
        var finalURL: URL
    }

    private let policy: URLPolicy
    private let maxBytes: Int
    private let headersOnly: Bool
    private let state: Mutex<State>

    init(policy: URLPolicy, maxBytes: Int, startURL: URL, headersOnly: Bool) {
        self.policy = policy
        self.maxBytes = maxBytes
        self.headersOnly = headersOnly
        state = Mutex(State(finalURL: startURL))
    }

    func begin(_ continuation: CheckedContinuation<FetchResponse, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    private func fail(_ error: any Error) {
        state.withLock { if $0.failure == nil { $0.failure = error } }
    }

    // Redirects: every hop goes through the same policy as the first request.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let target = request.url else { return nil }
        let hop = state.withLock { s -> Int in
            s.hops += 1
            return s.hops
        }
        // A refused redirect stops the download instead of reading the redirect response.
        func refuse(_ error: any Error) -> URLRequest? {
            fail(error)
            task.cancel()
            return nil
        }
        if hop > WatchSessionFetcher.maxRedirects { return refuse(URLPolicy.Violation.tooManyRedirects) }
        if response.url?.scheme?.lowercased() == "https", target.scheme?.lowercased() == "http" { return refuse(URLPolicy.Violation.insecureRedirect) }
        do { try await policy.validate(target) } catch { return refuse(error) }
        state.withLock { $0.finalURL = target }
        var next = request
        next.httpShouldHandleCookies = false
        return next
    }

    // Logins are never answered; only the TLS server check (which is not a login) proceeds.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { return (.performDefaultHandling, nil) }
        return (.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if state.withLock({ $0.failure != nil }) { return .cancel }
        guard let http = response as? HTTPURLResponse else { return .cancel }
        state.withLock { $0.response = http }
        if headersOnly {
            state.withLock { $0.stoppedEarly = true }
            return .cancel
        }
        if (200..<300).contains(http.statusCode), case .other(let name) = WebContent.kind(contentType: http.value(forHTTPHeaderField: "Content-Type"), sniffing: Data()) {
            fail(ProbeError.failed("That address isn't a web page or text (it sent “\(name)”)."))
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = state.withLock { s -> Bool in
            let room = maxBytes - s.body.count
            if data.count > room {
                s.body.append(data.prefix(max(0, room)))
                s.truncated = true
                return true
            }
            s.body.append(data)
            return false
        }
        if overflow { dataTask.cancel() }
    }

    // DNS rebinding: whatever name we resolved earlier, refuse a response that came from a private address.
    // Behind a proxy the address is the proxy's, which is the user's own network setting, so it isn't judged.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let last = metrics.transactionMetrics.last(where: { $0.resourceFetchType == .networkLoad }),
              !last.isProxyConnection, let address = last.remoteAddress else { return }
        do { try policy.checkRemoteAddress(address) } catch { fail(error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let outcome = state.withLock { s -> (CheckedContinuation<FetchResponse, any Error>?, Result<FetchResponse, any Error>) in
            let c = s.continuation
            s.continuation = nil
            if let failure = s.failure { return (c, .failure(failure)) }
            if let http = s.response, error == nil || s.truncated || s.stoppedEarly {
                var headers: [String: String] = [:]
                for (k, v) in http.allHeaderFields { headers[String(describing: k).lowercased()] = String(describing: v) }
                return (c, .success(FetchResponse(status: http.statusCode, headers: headers, body: s.body, finalURL: s.finalURL, truncated: s.truncated)))
            }
            return (c, .failure(error ?? URLError(.badServerResponse)))
        }
        outcome.0?.resume(with: outcome.1)
    }
}
