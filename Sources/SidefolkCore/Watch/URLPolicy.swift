import Darwin
import Foundation
import Synchronization

/// A network address as the kernel will use it.
public enum IPAddress: Sendable, Hashable, CustomStringConvertible {
    case v4([UInt8])
    case v6([UInt8])

    public var description: String {
        switch self {
        case .v4(let b): b.map(String.init).joined(separator: ".")
        case .v6(let b):
            stride(from: 0, to: 16, by: 2).map { String(Int(b[$0]) << 8 | Int(b[$0 + 1]), radix: 16) }.joined(separator: ":")
        }
    }

    /// Parses an address as text. Legacy IPv4 spellings (`127.1`, `2130706433`, `0x7f.1`, `0177.0.0.1`)
    /// follow `inet_aton`, which is what the system resolver and URLSession would use.
    public static func parse(_ text: String) -> IPAddress? {
        var s = text
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        if let zone = s.firstIndex(of: "%") { s = String(s[..<zone]) }
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace }) else { return nil }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, s, &v6) == 1 {
            return .v6(withUnsafeBytes(of: &v6) { Array($0) })
        }
        var v4 = in_addr()
        if inet_aton(s, &v4) == 1 {
            return .v4(withUnsafeBytes(of: &v4) { Array($0) })
        }
        return nil
    }
}

/// Turns a host name into addresses. Injectable so tests never touch DNS.
public protocol HostResolver: Sendable {
    func resolve(_ host: String) async throws -> [IPAddress]
}

/// `getaddrinfo` on a background thread with a deadline (it cannot be cancelled, so we stop waiting).
public struct SystemResolver: HostResolver {
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 10) { self.timeout = timeout }

    public func resolve(_ host: String) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .utility).async {
                once.resume(with: Result { try Self.lookup(host) })
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                once.resume(with: .failure(URLPolicyError.unresolvable(host)))
            }
        }
    }

    static func lookup(_ host: String) throws -> [IPAddress] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { throw URLPolicyError.unresolvable(host) }
        defer { freeaddrinfo(list) }
        var out: [IPAddress] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cursor {
            if let sa = ai.pointee.ai_addr {
                if ai.pointee.ai_family == AF_INET {
                    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p in
                        var a = p.pointee.sin_addr
                        out.append(.v4(withUnsafeBytes(of: &a) { Array($0) }))
                    }
                } else if ai.pointee.ai_family == AF_INET6 {
                    sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p in
                        var a = p.pointee.sin6_addr
                        out.append(.v6(withUnsafeBytes(of: &a) { Array($0) }))
                    }
                }
            }
            cursor = ai.pointee.ai_next
        }
        guard !out.isEmpty else { throw URLPolicyError.unresolvable(host) }
        return out
    }
}

/// Resumes a continuation exactly once, whichever of two racing callers gets there first.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    init(_ continuation: CheckedContinuation<T, any Error>) { self.continuation = continuation }

    func resume(with result: Result<T, any Error>) {
        let c = lock.withLock { () -> CheckedContinuation<T, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(with: result)
    }
}

public enum URLPolicyError: Error, Sendable, Equatable, CustomStringConvertible {
    case notWeb
    case credentials
    case tooLong
    case noHost
    case localName(String)
    case privateAddress(String)
    case unresolvable(String)
    case redirect(String)

    public var description: String {
        switch self {
        case .notWeb: "I only watch web addresses that start with http:// or https://."
        case .credentials: "I won't use a web address with a username or password inside it."
        case .tooLong: "That web address is too long."
        case .noHost: "That doesn't look like a web address."
        case .localName(let h): "“\(h)” is on your own Mac or network, so I won't reach out to it from here."
        case .privateAddress(let h): "“\(h)” points to your own Mac or network, so I won't reach out to it."
        case .unresolvable(let h): "I couldn't find “\(h)” on the internet."
        case .redirect(let why): why
        }
    }
}

/// Decides which web addresses Sidefolk may fetch for a watcher (docs/SECURITY.md T11).
/// Nothing here trusts the model: the same checks apply to the first request and to every redirect.
public struct URLPolicy: Sendable {
    public static let maxLength = 2048
    public static let maxRedirects = 5

    public var resolver: any HostResolver
    public init(resolver: any HostResolver = SystemResolver()) { self.resolver = resolver }

    /// Checks that need no network: scheme, credentials, length, host, and (unless local targets are
    /// allowed) names and literal addresses that are obviously local. Used when a watcher is created.
    public static func checkSyntax(_ url: URL, allowLocal: Bool) throws {
        let text = url.absoluteString
        guard text.count <= maxLength else { throw URLPolicyError.tooLong }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw URLPolicyError.notWeb }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLPolicyError.noHost }
        if comps.user != nil || comps.password != nil { throw URLPolicyError.credentials }
        guard let host = Self.hostName(of: url) else { throw URLPolicyError.noHost }
        guard !allowLocal else { return }
        if let literal = IPAddress.parse(host) {
            if isBlocked(literal) { throw URLPolicyError.privateAddress(host) }
        } else if isLocalName(host) {
            throw URLPolicyError.localName(host)
        }
    }

    /// Full check before any request: syntax, then every address the name resolves to.
    public func validate(_ url: URL, allowLocal: Bool) async throws {
        try Self.checkSyntax(url, allowLocal: allowLocal)
        guard !allowLocal, let host = Self.hostName(of: url) else { return }
        let addresses: [IPAddress]
        if let literal = IPAddress.parse(host) {
            addresses = [literal]
        } else {
            addresses = try await resolver.resolve(host)
        }
        if addresses.contains(where: Self.isBlocked) { throw URLPolicyError.privateAddress(host) }
    }

    /// Whether a redirect from `from` to `to` may be followed, given how many hops came before.
    public func checkRedirect(from: URL, to: URL, hop: Int, allowLocal: Bool) async throws {
        guard hop <= Self.maxRedirects else { throw URLPolicyError.redirect("That page sends me round in circles.") }
        if from.scheme?.lowercased() == "https", to.scheme?.lowercased() == "http" {
            throw URLPolicyError.redirect("That page tried to move from a secure to an insecure address, so I stopped.")
        }
        try await validate(to, allowLocal: allowLocal)
    }

    // MARK: Pieces

    /// Lower-cased host without brackets or a trailing dot.
    public static func hostName(of url: URL) -> String? {
        guard var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix("."), host.count > 1 { host.removeLast() }
        return host
    }

    /// `localhost`, `*.localhost`, `*.local` and single-label names ("intranet").
    public static func isLocalName(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        return !host.contains(".")
    }

    public static func isBlocked(_ address: IPAddress) -> Bool {
        switch address {
        case .v4(let b): return blockedV4(b)
        case .v6(let b):
            let zeros10 = b[0..<10].allSatisfy { $0 == 0 }
            if zeros10, b[10] == 0xff, b[11] == 0xff { return blockedV4(Array(b[12..<16])) } // ::ffff:a.b.c.d
            if b[0..<12].allSatisfy({ $0 == 0 }) { return true }                              // ::, ::1, ::a.b.c.d
            if b[0] == 0x00, b[1] == 0x64, b[2] == 0xff, b[3] == 0x9b, b[4..<12].allSatisfy({ $0 == 0 }) {
                return blockedV4(Array(b[12..<16]))                                           // 64:ff9b::/96
            }
            if b[0] == 0x20, b[1] == 0x02 { return blockedV4(Array(b[2..<6])) }                // 6to4 2002::/16
            if b[0] & 0xfe == 0xfc { return true }                                            // fc00::/7
            if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return true }                              // fe80::/10
            if b[0] == 0xfe, b[1] & 0xc0 == 0xc0 { return true }                              // fec0::/10 (site local)
            return b[0] == 0xff                                                               // ff00::/8
        }
    }

    private static func blockedV4(_ b: [UInt8]) -> Bool {
        switch (b[0], b[1], b[2]) {
        case (0, _, _), (10, _, _), (127, _, _): true
        case (100, 64...127, _): true                  // 100.64/10 carrier-grade NAT
        case (169, 254, _): true
        case (172, 16...31, _): true
        case (192, 0, 0): true
        case (192, 168, _): true
        case (198, 18...19, _): true
        case (224..., _, _): true                      // 224/4 multicast, 240/4 reserved, broadcast
        default: false
        }
    }
}

// MARK: Per-host politeness

/// At most one request a minute to any one host, however many watchers point at it (docs/SECURITY.md T24).
public final class HostThrottle: Sendable {
    private let last = Mutex<[String: Date]>([:])
    public let gap: TimeInterval
    /// A watcher on a 60 s interval must not be pushed back by scheduling jitter.
    private let slack: TimeInterval = 1.5

    public init(gap: TimeInterval = 60) { self.gap = gap }

    /// Reserves a request slot. Returns nil when the request may go now, or when it may go later.
    public func reserve(host: String, now: Date) -> Date? {
        last.withLock { table in
            if let at = table[host], now < at.addingTimeInterval(gap - slack) { return at.addingTimeInterval(gap) }
            table[host] = now
            return nil
        }
    }
}
