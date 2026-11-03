import Foundation

/// A read Sidefolk can answer by itself, without the AI: its own reminders, watchers, today's plan and what's due.
public enum Listing: Sendable, Equatable {
    case reminders(ListingDay?)
    case watchers
    case agenda(ListingDay?)
    case due(ListingDay?)
}

/// The words that say when: "today", "tomorrow", "this week".
public enum ListingDay: String, Sendable, Equatable {
    case today, tomorrow
    case thisWeek = "this week"
}

extension IntentParser {
    private static let day = #"(?:\s+(?<day>today|tomorrow|this\s+week))?"#
    private static let listingPatterns: [(IntentPattern, @Sendable (ListingDay?) -> Listing)] = [
        (IntentPattern(#"(?:(?:show|list|get|see|display)\s+(?:me\s+)?(?:all\s+)?(?:(?:of\s+)?my\s+|the\s+)?|what\s+are\s+my\s+)(?:upcoming\s+)?reminders"# + day), { .reminders($0) }),
        (IntentPattern(#"what\s+reminders\s+do\s+i\s+have"# + day), { .reminders($0) }),
        (IntentPattern(#"(?:(?:show|list|get|see|display)\s+(?:me\s+)?(?:all\s+)?(?:(?:of\s+)?my\s+|the\s+)?|what\s+are\s+my\s+)(?:watchers|watches)"#), { _ in .watchers }),
        (IntentPattern(#"what\s+(?:am\s+i|are\s+you)\s+watching|what(?:'s|\s+is)\s+being\s+watched"#), { _ in .watchers }),
        (IntentPattern(#"what(?:'s|\s+is)\s+on\s+my\s+plate"# + day), { .agenda($0) }),
        (IntentPattern(#"what(?:'s|\s+is)\s+on"# + #"(?:\s+(?<day>today|tomorrow))"#), { .agenda($0) }),
        (IntentPattern(#"what\s+do\s+i\s+have"# + #"(?:\s+(?<day>today|tomorrow))"#), { .agenda($0) }),
        (IntentPattern(#"(?:show\s+(?:me\s+)?)?my\s+agenda"# + day), { .agenda($0) }),
        (IntentPattern(#"what(?:'s|\s+is)\s+due"# + day), { .due($0) }),
        (IntentPattern(#"(?:what|which)\s+tasks\s+are\s+due"# + day), { .due($0) }),
        (IntentPattern(#"(?:(?:show|list)\s+(?:me\s+)?(?:my\s+)?)?tasks\s+due"# + day), { .due($0) }),
    ]

    func listing(_ command: String) -> ParsedIntent? {
        for (pattern, listing) in Self.listingPatterns {
            guard let c = pattern.match(command) else { continue }
            let day = c["day"].map { $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }.flatMap(ListingDay.init(rawValue:))
            let found = listing(day)
            let what = switch found {
            case .reminders: String(localized: "Your reminders")
            case .watchers: String(localized: "What's being watched")
            case .agenda: String(localized: "What's on your plate")
            case .due: String(localized: "What's due")
            }
            return ParsedIntent(intent: .listing(found), hint: ParsedIntent.hint(what))
        }
        return nil
    }
}
