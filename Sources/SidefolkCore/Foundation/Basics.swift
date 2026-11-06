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
/// `message` and `recovery` are in the app's language: a literal passed to `init(_:)` is a key in the
/// string catalog and is looked up when the error is made. `detail` stays technical and English.
public struct UserFacingError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public var recovery: String?
    public var changedNothing: Bool
    public var detail: String?
    /// What it named isn't there. A caller can tell that from a failure that may have done something.
    public var notFound = false

    public init(_ message: String.LocalizationValue, recovery: String.LocalizationValue? = nil, changedNothing: Bool = true,
                detail: String? = nil) {
        self.init(verbatim: String(localized: message), recovery: recovery.map { String(localized: $0) },
                  changedNothing: changedNothing, detail: detail)
    }

    /// For text that is already final: worded (and localized) elsewhere, built at runtime, or a
    /// service's own message. It is shown exactly as given.
    public init(verbatim message: String, recovery: String? = nil, changedNothing: Bool = true, detail: String? = nil) {
        self.message = message
        self.recovery = recovery
        self.changedNothing = changedNothing
        self.detail = detail
    }

    public var description: String {
        Wording.sentences([message, recovery].compactMap { $0 })
    }
}

extension String {
    /// Trims and caps text that goes into logs, prompts or UI.
    public func clipped(_ limit: Int) -> String {
        let t = ExtensionText.withoutStacks(trimmingCharacters(in: .whitespacesAndNewlines))
        guard t.count > limit else { return t }
        var head = String(t.prefix(max(0, limit - 1)))
        // A marker for a hidden character (`hiddenShown`) is shown whole or not at all: whatever of one is left at the cut goes.
        if let partial = head.range(of: "⟨(U(\\+[0-9A-F]{0,6})?)?$", options: .regularExpression) { head = String(head[..<partial.lowerBound]) }
        return head + "…"
    }

    /// The text with every character that draws nothing, or changes how the rest is drawn (direction controls, zero-width characters, separators, controls,
    /// tags, variation selectors, fillers, whatever Unicode says is ignorable, unassigned), written out as `⟨U+202E⟩`: a name or a path can't pass for another, and
    /// the person sees that something is odd. The joiners and selectors that make up an emoji, and the joiners between letters that need them (Arabic, Indic,
    /// Khmer, Myanmar), stay where they sit between what they join.
    public var hiddenShown: String {
        let scalars = Array(unicodeScalars)
        guard scalars.indices.contains(where: { String.isHidden(scalars, at: $0) }) else { return self }
        var out = ""
        for index in scalars.indices {
            if String.isHidden(scalars, at: index) { out += String(format: "⟨U+%04X⟩", scalars[index].value) } else { out.unicodeScalars.append(scalars[index]) }
        }
        return out
    }

    private static func isHidden(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let scalar = scalars[index]
        let previous = index > 0 ? scalars[index - 1] : nil, next = index + 1 < scalars.count ? scalars[index + 1] : nil
        let hidden: Bool
        switch scalar.properties.generalCategory {
        case .format, .control, .lineSeparator, .paragraphSeparator, .unassigned, .surrogate: hidden = true
        default: hidden = scalar.properties.isDefaultIgnorableCodePoint
        }
        guard hidden else { return false }
        func emoji(_ s: Unicode.Scalar?) -> Bool { s.map { $0.properties.isEmoji && $0.value >= 0x80 } ?? false }
        func joins(_ s: Unicode.Scalar?) -> Bool {
            guard let s else { return false }
            switch s.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFC, 0x0900...0x0DFF, 0x1000...0x109F, 0x1780...0x17FF: return true
            default: return false
            }
        }
        switch scalar.value {
        // An emoji presentation selector after an emoji (or after a digit, # or * of a keycap), once.
        case 0xFE0E, 0xFE0F:
            if let previous, previous.properties.isEmoji, ![0xFE0E, 0xFE0F].contains(previous.value) { return false }
        // A joiner between two emoji (a family, a person with a job), after a selector too.
        case 0x200D:
            if (emoji(previous) || previous?.value == 0xFE0F) && emoji(next) { return false }
            if joins(previous) && joins(next) { return false }
        case 0x200C:
            if joins(previous) && joins(next) { return false }
        default: break
        }
        return true
    }
}
