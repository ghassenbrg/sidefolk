import Foundation

/// When an update Sidefolk installs by itself may restart it (D70). Never in the middle of something the person
/// would lose or have to start again; and only once they have been away a few minutes, so the companion doesn't
/// vanish while they look at it. Otherwise it waits, and installs at the next quit at the latest.
public enum InstallMoment {
    /// What the app sees around it, read each time it considers installing.
    public struct Signals: Sendable, Equatable {
        /// A request to Sidefolk's AI is running.
        public var conversation = false
        /// An approval card is waiting for an answer.
        public var approval = false
        /// The person is talking to the companion, or it is speaking.
        public var voice = false
        /// The Ask panel is open: they may be typing.
        public var asking = false
        /// Other agents' work or a `sidefolk run` job is under way through Sidefolk.
        public var work = false
        /// Seconds since the last keyboard or mouse input anywhere.
        public var secondsSinceInput: TimeInterval = 0

        public init(conversation: Bool = false, approval: Bool = false, voice: Bool = false, asking: Bool = false,
                    work: Bool = false, secondsSinceInput: TimeInterval = 0) {
            self.conversation = conversation
            self.approval = approval
            self.voice = voice
            self.asking = asking
            self.work = work
            self.secondsSinceInput = secondsSinceInput
        }
    }

    public enum Decision: Sendable, Equatable {
        case now
        case wait(Reason)
    }

    public enum Reason: String, Sendable, Equatable {
        case conversation, approval, voice, asking, work
        /// Nothing is running, but the person is at the Mac.
        case present
    }

    /// How long without input counts as away.
    public static let away: TimeInterval = 5 * 60

    public static func decide(_ s: Signals) -> Decision {
        // What would be cut off comes first: it holds even when the person is away (an approval card waits for them).
        if s.conversation { return .wait(.conversation) }
        if s.approval { return .wait(.approval) }
        if s.voice { return .wait(.voice) }
        if s.asking { return .wait(.asking) }
        if s.work { return .wait(.work) }
        return s.secondsSinceInput >= away ? .now : .wait(.present)
    }
}
