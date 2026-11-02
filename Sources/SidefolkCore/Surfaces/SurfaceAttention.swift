import Foundation

/// What a surface's being looked at decides (T40), pure so it is tested without a window. A person's move is attention; a clock
/// isn't. So a program can't keep an overlay on the desktop, or a scene changing, by setting timers, and a surface put away
/// runs nothing, however late the last reply comes.
public struct SurfaceAttention: Sendable {
    /// `next` and `timer` moves in a row with no one touching it.
    public static let maxIdleMoves = 600
    /// What a scene says aloud through VoiceOver, at most this often.
    public static let announceGap: TimeInterval = 2

    /// The last time the person did anything here: an overlay's minute and a kept panel's ten count from this.
    public private(set) var lastActive: Date
    /// A person's move was made: worth one Activity row.
    public private(set) var used = false
    /// Put away, or ended: no clock runs, no move goes, nothing sounds or is said.
    public private(set) var hidden = false
    /// The row for what is on screen is written.
    public private(set) var recorded = false
    private var movedSinceRow = false
    private var idleMoves = 0
    private var lastAnnounced = Date.distantPast

    public init(now: Date = Date()) {
        lastActive = now
    }

    /// Whether this move goes to the extension. Only the person's count as attention.
    public mutating func admit(_ move: SurfaceMove, now: Date = Date()) -> Bool {
        guard !hidden else { return false }
        switch move {
        case .next, .timer:
            idleMoves += 1
            return idleMoves <= Self.maxIdleMoves
        default:
            lastActive = now
            used = true
            movedSinceRow = true
            idleMoves = 0
            return true
        }
    }

    public mutating func hide() { hidden = true }

    public mutating func show(now: Date = Date()) {
        hidden = false
        lastActive = now
    }

    /// A scene arrived: whether it writes the row now. Each `over` scene's row needs a person's move since the last: a program
    /// flipping `over` by itself can't fill History.
    public mutating func rowForScene(over: Bool) -> Bool {
        if over {
            guard !recorded else { return false }
            recorded = true
            movedSinceRow = false
            return true
        }
        if movedSinceRow { recorded = false }
        return false
    }

    /// It ended: a surface that was used and never said it was over still gets its row, once.
    public mutating func rowAtEnd() -> Bool {
        guard used, !recorded else { return false }
        recorded = true
        return true
    }

    public mutating func mayAnnounce(now: Date = Date()) -> Bool {
        guard !hidden, now.timeIntervalSince(lastAnnounced) >= Self.announceGap else { return false }
        lastAnnounced = now
        return true
    }
}
