import Foundation

/// Sortable unique identifiers: 10 chars of millisecond time + 12 random base32 chars.
public enum Identifier {
    private static let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")

    public static func make(now: Date = Date()) -> String {
        var ms = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        var time = [Character](repeating: "0", count: 10)
        for i in stride(from: 9, through: 0, by: -1) {
            time[i] = alphabet[Int(ms % 32)]
            ms /= 32
        }
        var rng = SystemRandomNumberGenerator()
        let random = (0..<12).map { _ in alphabet[Int(rng.next() % 32)] }
        return String(time + random)
    }
}

/// Injectable time source so scheduling logic is testable.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock tests can move by hand.
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    public init(_ start: Date) { current = start }
    public var now: Date { lock.withLock { current } }
    public func set(_ date: Date) { lock.withLock { current = date } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// An error whose message is written for people, with optional detail kept for diagnostics.
public struct UserFacingError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public var recovery: String?
    public var changedNothing: Bool
    public var detail: String?

    public init(_ message: String, recovery: String? = nil, changedNothing: Bool = true, detail: String? = nil) {
        self.message = message
        self.recovery = recovery
        self.changedNothing = changedNothing
        self.detail = detail
    }

    public var description: String {
        [message, recovery].compactMap { $0 }.joined(separator: " ")
    }
}

extension String {
    /// Trims and caps text that goes into logs, prompts or UI.
    public func clipped(_ limit: Int) -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(max(0, limit - 1))) + "…"
    }
}
