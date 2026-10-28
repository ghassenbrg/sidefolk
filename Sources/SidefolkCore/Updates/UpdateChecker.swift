import Foundation

/// What the last look at the releases found, kept between launches (the "updates" key of the database).
public struct UpdateState: Codable, Sendable, Equatable {
    public var lastCheck: Date?
    /// GitHub's ETag for the list: an unchanged list costs a 304 and nothing more.
    public var etag: String?
    public var offers: [UpdateOffer] = []
    /// The version last offered on the desktop, and when, so the same one isn't brought up every day.
    public var asked: ReleaseVersion?
    public var askedAt: Date?

    public init() {}
}

/// Asks GitHub for Sidefolk's releases (D46). The request carries Sidefolk's version in its User-Agent, as GitHub
/// asks of every client, and nothing about the person; no account, no key. Unauthenticated, so GitHub allows
/// 60 an hour from one address: a look a day and the odd "Check Now" stay far below it.
public actor UpdateChecker {
    /// Automatic looks come this far apart.
    public static let interval: TimeInterval = 86_400
    /// A version the person let pass ("Later", or the bubble faded) is brought up again after this.
    public static let askAgainAfter: TimeInterval = 3 * 86_400
    static let key = "updates"

    private let transport: any HTTPTransport
    private let kv: KVStore?
    private let clock: any Clock
    private let source: URL
    private var cached: UpdateState?

    public init(transport: any HTTPTransport = URLSessionTransport(), kv: KVStore?, clock: any Clock = SystemClock(),
                source: URL = ReleaseFeed.source) {
        self.transport = transport
        self.kv = kv
        self.clock = clock
        self.source = source
    }

    public func state() async -> UpdateState {
        if let cached { return cached }
        let loaded = (try? await kv?.get(Self.key, as: UpdateState.self)) ?? UpdateState()
        cached = loaded
        return loaded
    }

    /// An automatic look is due: never looked, or the last one is `gap` old (or in the future: the clock moved).
    /// At launch the gap is an hour, so restarting a few times doesn't mean looking a few times.
    public func isDue(after gap: TimeInterval = interval) async -> Bool {
        guard let last = await state().lastCheck else { return true }
        let since = clock.now.timeIntervalSince(last)
        return since >= gap || since < 0
    }

    /// Reads the list of releases, newest first. A list unchanged since the last look comes from the last look.
    public func check() async throws -> [UpdateOffer] {
        var current = await state()
        var headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                       "User-Agent": "Sidefolk/\(SidefolkVersion.current)"]
        if let etag = current.etag, !current.offers.isEmpty { headers["If-None-Match"] = etag }
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(method: "GET", url: source, headers: headers, timeout: 15))
        } catch {
            throw UserFacingError("Sidefolk couldn't reach GitHub to look for updates.", recovery: "Check the connection and try again.",
                                  detail: String(describing: error))
        }
        switch response.status {
        case 200:
            guard let offers = try? ReleaseFeed.offers(from: response.body) else {
                throw UserFacingError("GitHub's list of releases came back in a form Sidefolk doesn't read.")
            }
            current.offers = offers
            current.etag = response.header("etag")
        case 304:
            break
        case 403, 429:
            throw UserFacingError("GitHub asked Sidefolk to wait before looking again.", recovery: "Try again in an hour.")
        default:
            throw UserFacingError("GitHub didn't answer (status \(response.status)).", recovery: "Try again later.")
        }
        current.lastCheck = clock.now
        await save(current)
        return current.offers
    }

    /// Whether to bring `offer` up on the desktop now: not if it was offered in the last few days.
    public func shouldAsk(about offer: UpdateOffer) async -> Bool {
        let s = await state()
        guard s.asked == offer.version, let at = s.askedAt else { return true }
        let since = clock.now.timeIntervalSince(at)
        return since >= Self.askAgainAfter || since < 0
    }

    public func markAsked(_ offer: UpdateOffer) async {
        var s = await state()
        s.asked = offer.version
        s.askedAt = clock.now
        await save(s)
    }

    private func save(_ s: UpdateState) async {
        cached = s
        try? await kv?.set(Self.key, s)
    }
}
