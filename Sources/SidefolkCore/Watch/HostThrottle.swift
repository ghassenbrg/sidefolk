import Foundation
import Synchronization

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
