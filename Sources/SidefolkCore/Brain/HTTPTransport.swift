import Foundation

public struct HTTPRequest: Sendable, CustomStringConvertible {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// Idle timeout for the connection; the loop enforces the run's total deadline separately.
    public var timeout: TimeInterval

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 60) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// Never the headers (API keys) or the body (the user's words).
    public var description: String { "\(method) \(url.absoluteString)" }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    /// Lower-cased names.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// How model adapters reach the network; tests substitute a fake so they never touch it.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The real transport: an ephemeral session (no cookies, no cache, no stored credentials) that
/// refuses redirects, so a key header is never replayed to another host.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var r = URLRequest(url: request.url)
        r.httpMethod = request.method
        r.timeoutInterval = request.timeout
        r.httpBody = request.body
        for (name, value) in request.headers { r.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: r, delegate: NoRedirects.shared)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k.lowercased()] = v }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// Retries for transient provider failures: 429, 529 and other 5xx, at most twice by default.
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(maxRetries: Int = 2, baseDelay: TimeInterval = 0.8, maxDelay: TimeInterval = 10,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    public static let standard = RetryPolicy()

    static func isRetryable(_ status: Int) -> Bool { status == 408 || status == 429 || status >= 500 }

    /// Honours `retry-after` (seconds) when the server sends it; otherwise doubles from `baseDelay`.
    func delay(attempt: Int, retryAfter: String?) -> TimeInterval {
        if let s = retryAfter, let seconds = Double(s.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            return min(seconds, maxDelay)
        }
        return min(baseDelay * pow(2, Double(attempt)), maxDelay)
    }
}

/// The HTTP plumbing both adapters share: retries within the time budget, cancellation, and
/// turning transport failures into friendly errors.
struct ProviderHTTP: Sendable {
    let transport: any HTTPTransport
    let retry: RetryPolicy
    let provider: String
    /// The service runs on this Mac (Ollama, LM Studio): connection errors mean "not running".
    let local: Bool

    func send(_ request: HTTPRequest, timeBudget: TimeInterval) async throws -> HTTPResponse {
        let started = ContinuousClock.now
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                throw Self.networkError(error, provider: provider, local: local)
            }
            guard RetryPolicy.isRetryable(response.status), attempt < retry.maxRetries else { return response }
            let wait = retry.delay(attempt: attempt, retryAfter: response.header("retry-after"))
            let spent = (ContinuousClock.now - started).components
            let elapsed = Double(spent.seconds) + Double(spent.attoseconds) / 1e18
            guard elapsed + wait < timeBudget else { return response }
            Log.shared.info("brain", "\(provider) answered \(response.status); retrying", ["attempt": String(attempt + 1)])
            try await retry.sleep(wait)
            attempt += 1
        }
    }

    static func networkError(_ error: Error, provider: String, local: Bool) -> UserFacingError {
        let detail = String(describing: error)
        let offline = UserFacingError("I couldn't reach \(provider). Nothing was changed.",
                                      recovery: "Check your internet connection, or switch provider in Settings › AI.", detail: detail)
        guard let code = (error as? URLError)?.code else { return offline }
        switch code {
        case .timedOut:
            return UserFacingError("\(provider) took too long to answer. Nothing was changed.", recovery: "Try again in a moment.",
                                   detail: detail)
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            guard local else { return offline }
            return UserFacingError("I couldn't reach \(provider) on this Mac. Nothing was changed.",
                                   recovery: "Make sure \(provider) is running, and check the address in Settings › AI.", detail: detail)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return UserFacingError("I couldn't make a secure connection to \(provider). Nothing was changed.",
                                   recovery: "Check the address in Settings › AI, or try another network.", detail: detail)
        default:
            return offline
        }
    }

    /// The provider's error message from a JSON error body, in any of the usual shapes, including
    /// Gemini's, which wraps the error in an array (`[{"error": {…}}]`).
    static func errorMessage(_ body: Data) -> (type: String?, message: String?) {
        guard var json = try? JSONValue.parse(body) else {
            let text = String(decoding: body.prefix(300), as: UTF8.self)
            return (nil, text.isEmpty ? nil : text)
        }
        if let first = json.arrayValue?.first { json = first }
        if let message = json["error"]?.stringValue { return (nil, message) }
        let error = json["error"] ?? json
        let type = error["type"]?.stringValue ?? error["status"]?.stringValue ?? error["code"]?.stringValue
        return (type, error["message"]?.stringValue)
    }

    /// A structured error from the provider, rather than a web server's error page.
    static func isJSONError(_ body: Data) -> Bool {
        guard let json = try? JSONValue.parse(body) else { return false }
        return (json.arrayValue?.first ?? json)["error"] != nil
    }

    /// What goes into `UserFacingError.detail` for diagnostics: status, type and a short, redacted message.
    static func detail(_ response: HTTPResponse) -> String {
        let (type, message) = errorMessage(response.body)
        return Redactor.redact(["HTTP \(response.status)", type, message].compactMap { $0 }.joined(separator: " ")).clipped(300)
    }
}
