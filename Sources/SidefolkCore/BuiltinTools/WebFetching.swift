import Foundation
import Synchronization

public struct WebFetchOptions: Sendable {
    public var maxBytes = 2 * 1024 * 1024
    public var timeout: TimeInterval = 15
    public var maxRedirects = 5
    /// Refuse anything that isn't text, HTML, JSON or XML.
    public var textOnly = true
    public init() {}
}

public struct WebResponse: Sendable {
    public var requestedURL: URL
    /// Where the page really came from, after redirects.
    public var url: URL
    public var statusCode: Int
    public var contentType: String?
    public var body: Data
    /// The body was cut at `maxBytes`.
    public var truncated: Bool

    public init(requestedURL: URL, url: URL, statusCode: Int, contentType: String?, body: Data, truncated: Bool = false) {
        self.requestedURL = requestedURL
        self.url = url
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.truncated = truncated
    }
}

public enum WebFetchError: Error, Equatable, Sendable {
    case blocked(URLPolicy.Violation)
    case unsupportedType(String)
    case timedOut
    case network(String)

    public var userFacing: UserFacingError {
        switch self {
        case .blocked(let v): v.userFacing
        case .unsupportedType(let type):
            UserFacingError("That address is a \(type) file, not a web page or text I can read.")
        case .timedOut:
            UserFacingError("The site took too long to answer.", recovery: "Try again in a moment.")
        case .network(let why):
            UserFacingError("I couldn't reach that site.", recovery: "Check your connection and the address.", detail: why)
        }
    }
}

/// Fetches a web page. Implementations must refuse destinations on this computer or the local network at
/// every hop, including redirects (see `URLSessionFetcher`). Tests use a fake.
public protocol WebFetching: Sendable {
    func get(_ url: URL, options: WebFetchOptions) async throws -> WebResponse
}

/// Plain HTTP GET with the guard rails of docs/SECURITY.md T11: ephemeral session without cookies,
/// credentials or cache, every hop checked by `URLPolicy`, no https-to-http redirects, at most 5
/// redirects, a streamed size cap and text-like content types only.
public struct URLSessionFetcher: WebFetching {
    private let policy: URLPolicy
    private let protocolClasses: [AnyClass]

    public init(policy: URLPolicy = URLPolicy()) {
        self.policy = policy
        protocolClasses = []
    }

    /// Test seam: route requests through stub `URLProtocol`s instead of the network.
    init(policy: URLPolicy, protocolClasses: [AnyClass]) {
        self.policy = policy
        self.protocolClasses = protocolClasses
    }

    public func get(_ url: URL, options: WebFetchOptions = WebFetchOptions()) async throws -> WebResponse {
        do { try await policy.validate(url) } catch let v as URLPolicy.Violation { throw WebFetchError.blocked(v) }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = options.timeout
        config.timeoutIntervalForResource = options.timeout
        config.waitsForConnectivity = false
        if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses + (config.protocolClasses ?? []) }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: options.timeout)
        request.setValue("Sidefolk/\(SidefolkVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        let operation = FetchOperation(policy: policy, options: options, requestedURL: url)
        return try await operation.run(configuration: config, request: request)
    }
}

/// One download. The delegate checks each redirect and the connection's real address, caps the body and
/// reports the outcome exactly once.
private final class FetchOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<WebResponse, Error>?
        var task: URLSessionDataTask?
        var response: HTTPURLResponse?
        var finalURL: URL
        var body = Data()
        var redirects = 0
        var failure: WebFetchError?
        var cappedByUs = false
    }

    private let policy: URLPolicy
    private let options: WebFetchOptions
    private let requestedURL: URL
    private let state: Mutex<State>

    init(policy: URLPolicy, options: WebFetchOptions, requestedURL: URL) {
        self.policy = policy
        self.options = options
        self.requestedURL = requestedURL
        state = Mutex(State(finalURL: requestedURL))
    }

    func run(configuration: URLSessionConfiguration, request: URLRequest) async throws -> WebResponse {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WebResponse, Error>) in
                let task = session.dataTask(with: request)
                state.withLock { $0.continuation = continuation; $0.task = task }
                task.resume()
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            state.withLock { $0.task }?.cancel()
        }
    }

    private func fail(_ error: WebFetchError) {
        state.withLock { if $0.failure == nil { $0.failure = error } }
    }

    // MARK: Delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // Certificates are checked normally; any request for a name and password is refused.
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let target = request.url else { return nil }
        let count = state.withLock { s -> Int in s.redirects += 1; return s.redirects }
        // A refused redirect stops the download right away instead of reading the redirect response.
        func refuse(_ error: WebFetchError) -> URLRequest? {
            fail(error)
            task.cancel()
            return nil
        }
        if count > options.maxRedirects { return refuse(.blocked(.tooManyRedirects)) }
        if response.url?.scheme?.lowercased() == "https", target.scheme?.lowercased() == "http" { return refuse(.blocked(.insecureRedirect)) }
        do { try await policy.validate(target) } catch let v as URLPolicy.Violation {
            return refuse(.blocked(v))
        } catch {
            return refuse(.network(String(describing: error)))
        }
        state.withLock { $0.finalURL = target }
        return request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if state.withLock({ $0.failure != nil }) { return .cancel }
        guard let http = response as? HTTPURLResponse else {
            fail(.network("not an HTTP response"))
            return .cancel
        }
        if options.textOnly, (200..<300).contains(http.statusCode) {
            let type = http.value(forHTTPHeaderField: "Content-Type")
            if case .other(let name) = WebContent.kind(contentType: type, sniffing: Data()) {
                fail(.unsupportedType(name))
                return .cancel
            }
        }
        state.withLock { $0.response = http; $0.finalURL = http.url ?? $0.finalURL }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let shouldCancel = state.withLock { s -> Bool in
            let room = options.maxBytes - s.body.count
            if data.count >= room {
                s.body.append(data.prefix(max(room, 0)))
                s.cappedByUs = true
                return true
            }
            s.body.append(data)
            return false
        }
        if shouldCancel { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // The connection may have gone somewhere our DNS check didn't see (rebinding). Behind a proxy the
        // address is the proxy's, which is the user's own network setting, so it isn't judged.
        guard let last = metrics.transactionMetrics.last(where: { $0.resourceFetchType == .networkLoad }),
              !last.isProxyConnection, let address = last.remoteAddress else { return }
        do { try policy.checkRemoteAddress(address) } catch let v as URLPolicy.Violation { fail(.blocked(v)) } catch {}
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, outcome): (CheckedContinuation<WebResponse, Error>?, Result<WebResponse, Error>) = state.withLock { s in
            let continuation = s.continuation
            s.continuation = nil
            if let failure = s.failure { return (continuation, .failure(failure)) }
            if let error, !(s.cappedByUs && (error as? URLError)?.code == .cancelled) {
                let code = (error as? URLError)?.code
                if code == .timedOut { return (continuation, .failure(WebFetchError.timedOut)) }
                if code == .cancelled { return (continuation, .failure(CancellationError())) }
                return (continuation, .failure(WebFetchError.network(error.localizedDescription)))
            }
            guard let http = s.response else { return (continuation, .failure(WebFetchError.network("no response"))) }
            return (continuation, .success(WebResponse(
                requestedURL: requestedURL, url: s.finalURL, statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type"), body: s.body, truncated: s.cappedByUs)))
        }
        continuation?.resume(with: outcome)
    }
}

/// What a response body is, and how to read it as text.
public enum WebContent {
    public enum Kind: Equatable, Sendable {
        case html, text, json, xml
        /// Something that isn't readable text, named for the error message ("image/png", "binary").
        case other(String)
    }

    /// Classifies by the Content-Type header; when it is missing or generic, by looking at the bytes.
    public static func kind(contentType: String?, sniffing data: Data) -> Kind {
        let mime = contentType?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        switch mime {
        case "text/html", "application/xhtml+xml": return .html
        case "text/xml", "application/xml", "application/rss+xml", "application/atom+xml": return .xml
        case "application/json", "application/ld+json", "application/feed+json": return .json
        case "", "application/octet-stream", "binary/octet-stream": return sniff(data, fallback: mime)
        default:
            if mime.hasPrefix("text/") { return .text }
            if mime.hasSuffix("+json") { return .json }
            if mime.hasSuffix("+xml") { return .xml }
            return .other(mime)
        }
    }

    private static func sniff(_ data: Data, fallback: String) -> Kind {
        // With no body yet (the header check) a missing type is given the benefit of the doubt.
        guard !data.isEmpty else { return fallback.isEmpty ? .text : .other(fallback) }
        let head = data.prefix(1_024)
        if head.contains(0) { return .other("binary") }
        let text = String(decoding: head, as: UTF8.self).lowercased()
        let start = text.drop(while: \.isWhitespace)
        if start.hasPrefix("<!doctype html") || start.hasPrefix("<html") { return .html }
        if start.hasPrefix("{") || start.hasPrefix("[") { return .json }
        if start.hasPrefix("<?xml") { return .xml }
        return .text
    }

    /// Decodes using the charset in the header, then a byte-order mark or `<meta charset>`, then UTF-8,
    /// then Windows-1252 (which accepts any bytes).
    public static func decode(_ data: Data, contentType: String?) -> String {
        if let name = charset(in: contentType), let encoding = encoding(named: name), let s = String(data: data, encoding: encoding) { return s }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16BigEndian) { return s }
        let head = String(decoding: data.prefix(2_048), as: UTF8.self).lowercased()
        if let range = head.range(of: "charset="), data.prefix(2_048).count > 0 {
            let name = head[range.upperBound...].drop { $0 == "\"" || $0 == "'" }.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            if let encoding = encoding(named: String(name)), let s = String(data: data, encoding: encoding) { return s }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    private static func charset(in contentType: String?) -> String? {
        guard let parts = contentType?.split(separator: ";").dropFirst() else { return nil }
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        return nil
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }
}
