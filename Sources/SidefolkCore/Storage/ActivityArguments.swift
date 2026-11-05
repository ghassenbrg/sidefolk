import Foundation

/// An action's arguments as History shows them, name and value in name order: the home folder shortened, long values cut, and a list of short lines
/// (what a plan's approval row keeps, one entry per line) shown one entry to a line and never cut, so the last entry, "+5 more", is on the screen.
public enum ActivityArguments {
    /// The most entries of a list shown whole, and the longest text of any other value.
    static let listLimit = 30
    static let valueLimit = 600

    public static func rows(_ args: JSONValue?) -> [(name: String, value: String)] {
        guard case .object(let fields)? = args else { return [] }
        return fields.keys.sorted().compactMap { name in
            guard let value = fields[name].flatMap(text), !value.isEmpty else { return nil }
            if case .array(let items)? = fields[name], items.allSatisfy({ $0.stringValue != nil }) { return (name, value) }
            return (name, value.count > valueLimit ? value.prefix(valueLimit) + "…" : value)
        }
    }

    private static func text(_ value: JSONValue) -> String? {
        switch value {
        case .null: return nil
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .string(let s): return s.hasPrefix("/") ? FolderAccess.displayPath(s) : s
        case .array(let items):
            if items.allSatisfy({ $0.stringValue != nil }) {
                // Past the limit, how many more: nothing is cut without a count.
                let more = items.count > listLimit ? ["+\(items.count - listLimit) more"] : []
                return (items.prefix(listLimit).compactMap { $0.stringValue } + more).joined(separator: "\n")
            }
            return items.compactMap(text).joined(separator: ", ")
        // What an object holds is shown, not only its keys: a plan's written values are shown on the card, and History says the same.
        case .object: return value.jsonString
        }
    }
}
