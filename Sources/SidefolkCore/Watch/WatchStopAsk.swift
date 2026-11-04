import Foundation

/// "Stop watching" asks first wherever it is pressed: a stop deletes the watch's checks and the text it kept, and has no
/// undo. The watch's own page asked, while Today's tile and On duty's rows stopped at once; they all hand the watch to
/// this, and only `confirm()` gives back what to stop.
public struct WatchStopAsk: Sendable, Equatable {
    public struct Pending: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
    }

    public private(set) var pending: Pending?

    public init() {}

    /// The question for this watch, replacing one still open.
    public mutating func ask(id: String, title: String) {
        pending = Pending(id: id, title: title)
    }

    /// The yes: the watch to stop, once. Nil when nothing is being asked.
    public mutating func confirm() -> String? {
        defer { pending = nil }
        return pending?.id
    }

    public mutating func cancel() { pending = nil }

    /// What the question says: the same words on every screen.
    public static func question(_ title: String) -> String {
        String(localized: "Stop watching “\(title)”?", comment: "The question before a watch is stopped")
    }
}
