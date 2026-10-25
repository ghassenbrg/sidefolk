import Darwin
import Foundation

/// An IP address, parsed strictly. `isPublic` is false for everything that is not a normal internet
/// destination: loopback, private, link-local, CGNAT, multicast, reserved and documentation ranges,
/// and IPv6 forms that embed an IPv4 address (checked as that IPv4 address).
public enum IPAddress: Sendable, Hashable, CustomStringConvertible {
    case v4(UInt32)
    case v6([UInt8])

    /// Parses `a.b.c.d` (no leading zeros) or an IPv6 literal. Never accepts shorthand like `127.1`.
    public static func parse(_ text: String) -> IPAddress? {
        var host = text
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if let percent = host.firstIndex(of: "%") { host = String(host[..<percent]) } // zone id
        if host.contains(":") {
            var addr = in6_addr()
            guard inet_pton(AF_INET6, host, &addr) == 1 else { return nil }
            return .v6(withUnsafeBytes(of: addr) { Array($0) })
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  part == "0" || !part.hasPrefix("0"), let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        return .v4(value)
    }

    public var description: String {
        switch self {
        case .v4(let v): "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
        case .v6(let bytes):
            bytes.enumerated().reduce(into: [String]()) { out, pair in
                if pair.offset % 2 == 0 { out.append(String(format: "%02x", pair.element)) } else { out[out.count - 1] += String(format: "%02x", pair.element) }
            }.joined(separator: ":")
        }
    }

    public var isPublic: Bool {
        switch self {
        case .v4(let v): Self.isPublicV4(v)
        case .v6(let b): Self.isPublicV6(b)
        }
    }

    private static func v4(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> UInt32 { a << 24 | b << 16 | c << 8 | d }

    private static func isPublicV4(_ v: UInt32) -> Bool {
        let blocked: [(UInt32, Int)] = [
            (v4(0, 0, 0, 0), 8), (v4(10, 0, 0, 0), 8), (v4(100, 64, 0, 0), 10), (v4(127, 0, 0, 0), 8),
            (v4(169, 254, 0, 0), 16), (v4(172, 16, 0, 0), 12), (v4(192, 0, 0, 0), 24), (v4(192, 0, 2, 0), 24),
            (v4(192, 168, 0, 0), 16), (v4(198, 18, 0, 0), 15), (v4(198, 51, 100, 0), 24), (v4(203, 0, 113, 0), 24),
            (v4(224, 0, 0, 0), 4), (v4(240, 0, 0, 0), 4),
        ]
        return !blocked.contains { base, prefix in (v ^ base) >> UInt32(32 - prefix) == 0 }
    }

    private static func isPublicV6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        func embedded(_ range: Range<Int>) -> Bool {
            isPublicV4(b[range].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        let zeroPrefix96 = b[0..<12].allSatisfy { $0 == 0 }
        if zeroPrefix96 { return false }                                                     // ::, ::1, ::/96 (v4-compatible)
        if b[0] & 0xFE == 0xFC { return false }                                              // fc00::/7 unique local
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 || b[1] & 0xC0 == 0xC0 { return false }        // fe80::/10 link-local, fec0::/10
        if b[0] == 0xFF { return false }                                                     // multicast
        if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF { return embedded(12..<16) } // ::ffff:0:0/96
        if b[0] == 0x00, b[1] == 0x64, b[2] == 0xFF, b[3] == 0x9B {                          // 64:ff9b::/96 NAT64, 64:ff9b:1::/48 local use
            return b[4..<12].allSatisfy { $0 == 0 } ? embedded(12..<16) : false
        }
        if b[0] == 0x20, b[1] == 0x02 { return embedded(2..<6) }                              // 2002::/16 6to4
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x00, b[3] == 0x00 { return false }           // 2001::/32 Teredo
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x0D, b[3] == 0xB8 { return false }           // 2001:db8::/32 documentation
        if b[0] == 0x01, b[1] == 0x00, b[2..<8].allSatisfy({ $0 == 0 }) { return false }     // 100::/64 discard
        return true
    }
}

/// Turns a host name into addresses. Injectable so tests never touch DNS.
public protocol HostResolving: Sendable {
    func addresses(for host: String) async throws -> [IPAddress]
}

/// `getaddrinfo`, run off the cooperative pool because it blocks.
public struct SystemHostResolver: HostResolving {
    public init() {}

    public func addresses(for host: String) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let code = getaddrinfo(host, nil, &hints, &result)
                guard code == 0, let first = result else {
                    continuation.resume(throwing: URLPolicy.Violation.cannotResolve(host))
                    return
                }
                defer { freeaddrinfo(first) }
                var found: [IPAddress] = []
                var cursor: UnsafeMutablePointer<addrinfo>? = first
                while let info = cursor {
                    if let sa = info.pointee.ai_addr {
                        if info.pointee.ai_family == AF_INET {
                            sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { found.append(.v4(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))) }
                        } else if info.pointee.ai_family == AF_INET6 {
                            sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                                found.append(.v6(withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }))
                            }
                        }
                    }
                    cursor = info.pointee.ai_next
                }
                continuation.resume(returning: found)
            }
        }
    }
}

/// One policy for every URL Sidefolk follows on its own: web fetch, URL watchers, open URL
/// (docs/SECURITY.md T11). The static parts need no network; `validate` also resolves the host and
/// refuses anything that points at this computer or the local network.
///
/// `allowPrivate` exists only for destinations the user typed into the UI themselves (a localhost
/// watcher); it must never be reachable from a tool schema.
public struct URLPolicy: Sendable {
    public static let maxLength = 2_048

    public enum Violation: Error, Equatable, Sendable, CustomStringConvertible {
        case notAWebAddress
        case unsupportedScheme(String)
        case hasCredentials
        case tooLong
        case missingHost
        case oddIPNotation(String)
        case privateDestination(String)
        case cannotResolve(String)
        case tooManyRedirects
        case insecureRedirect

        public var message: String {
            switch self {
            case .notAWebAddress:
                "That isn't a valid web address. It should look like https://example.com/page, with no spaces."
            case .unsupportedScheme(let scheme):
                "I only handle web addresses (http and https), not “\(scheme):” links."
            case .hasCredentials:
                "Web addresses with a name and password in them aren't allowed."
            case .tooLong:
                "That web address is too long."
            case .missingHost:
                "That web address has no site name in it."
            case .oddIPNotation(let host):
                "“\(host)” is an unusual way to write an IP address. Write it as four plain numbers, like 93.184.216.34."
            case .privateDestination(let host):
                "“\(host)” points at this computer or your local network, so I won't fetch it."
            case .cannotResolve(let host):
                "I couldn't find a site called “\(host)”."
            case .tooManyRedirects:
                "That address sent me around in circles (too many redirects)."
            case .insecureRedirect:
                "That secure (https) address tried to send me to an insecure (http) one, so I stopped."
            }
        }

        public var description: String { message }
        public var userFacing: UserFacingError { UserFacingError(message) }
    }

    private let resolver: any HostResolving
    private let allowPrivate: Bool

    public init(resolver: any HostResolving = SystemHostResolver(), allowPrivate: Bool = false) {
        self.resolver = resolver
        self.allowPrivate = allowPrivate
    }

    // MARK: Syntax (no network)

    /// An http or https URL with a host, no credentials, no whitespace and a sane length.
    public static func parseWebURL(_ text: String) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= maxLength else { throw Violation.tooLong }
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              let url = URL(string: text) else { throw Violation.notAWebAddress }
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { throw Violation.notAWebAddress }
        guard scheme == "http" || scheme == "https" else { throw Violation.unsupportedScheme(scheme) }
        if url.user != nil || url.password != nil { throw Violation.hasCredentials }
        guard let host = url.host, !host.isEmpty else { throw Violation.missingHost }
        return url
    }

    /// Host rules that need no DNS: names that mean "this machine or network" and literal IP addresses.
    /// Unusual IP spellings (`127.1`, `2130706433`, `0x7f.1`, `0177.0.0.1`) are refused outright, because
    /// different parts of the system read them differently.
    public static func checkHost(_ url: URL, allowPrivate: Bool = false) throws {
        guard let raw = url.host else { throw Violation.missingHost }
        var host = raw.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains("%") || host.contains(":") else { throw Violation.notAWebAddress }

        if host.contains(":") {   // IPv6 literal
            guard let ip = IPAddress.parse(host) else { throw Violation.notAWebAddress }
            if !allowPrivate, !ip.isPublic { throw Violation.privateDestination(raw) }
            return
        }
        var sloppy = in_addr()
        if inet_aton(host, &sloppy) != 0 {   // anything that can be read as an IPv4 address
            guard let ip = IPAddress.parse(host) else { throw Violation.oddIPNotation(raw) }
            if !allowPrivate, !ip.isPublic { throw Violation.privateDestination(raw) }
            return
        }
        guard !allowPrivate else { return }
        let privateSuffixes = [".localhost", ".local", ".internal", ".home.arpa"]
        if host == "localhost" || !host.contains(".") || privateSuffixes.contains(where: { host.hasSuffix($0) }) {
            throw Violation.privateDestination(raw)
        }
    }

    // MARK: Destination (DNS)

    /// Full check for one hop: syntax, host rules, then every address the host resolves to.
    @discardableResult
    public func validate(_ text: String) async throws -> URL {
        let url = try Self.parseWebURL(text)
        try await validate(url)
        return url
    }

    public func validate(_ url: URL) async throws {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { throw Violation.unsupportedScheme(scheme) }
        try Self.checkHost(url, allowPrivate: allowPrivate)
        guard !allowPrivate else { return }
        let host = url.host ?? ""
        if host.contains(":") || IPAddress.parse(host) != nil { return }   // literal, already checked
        let resolver = self.resolver
        let addresses = try await withTimeout(10) { try await resolver.addresses(for: host) }
        guard !addresses.isEmpty else { throw Violation.cannotResolve(host) }
        // One private answer is enough to refuse: the connection could use any of them.
        if addresses.contains(where: { !$0.isPublic }) { throw Violation.privateDestination(host) }
    }

    /// The address a connection really went to (`URLSessionTaskTransactionMetrics.remoteAddress`).
    /// Catches DNS answers that changed between our check and the connection.
    public func checkRemoteAddress(_ text: String) throws {
        guard !allowPrivate else { return }
        guard let ip = IPAddress.parse(text), ip.isPublic else { throw Violation.privateDestination(text) }
    }
}
