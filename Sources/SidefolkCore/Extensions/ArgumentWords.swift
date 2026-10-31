import Foundation

/// A tool call's arguments as words for its approval card and Activity (D71): `tv: “living room”, volume: 40`, never
/// JSON, whose braces and escapes read as code. Every value is the call's own (T1), cleaned of hidden characters and
/// put on one line; a long one is clipped, and the card keeps the exact request one click away (`ApprovalRequest.input`).
public enum ArgumentWords {
    /// Characters one value may take before it's clipped.
    static let valueLimit = 60

    public static func line(_ input: JSONValue, schema: JSONValue) -> String {
        guard let fields = input.objectValue, !fields.isEmpty else { return "" }
        let properties = schema["properties"]?.objectValue ?? [:]
        // The schema's required arguments first, as the tool names them; then the rest alphabetically, so the same
        // call always reads the same.
        let required = (schema["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        let keys = required.filter { fields[$0] != nil } + fields.keys.filter { !required.contains($0) }.sorted()
        return keys.compactMap { key -> String? in
            guard let value = fields[key], let said = words(value) else { return nil }
            return "\(label(key, properties[key])): \(said)"
        }
        .joined(separator: ", ")
    }

    /// The schema's `title` for an argument when it has one, else its name with spaces for underscores.
    static func label(_ key: String, _ property: JSONValue?) -> String {
        if let title = property?["title"]?.stringValue.map(clean), !title.isEmpty { return title.clipped(30) }
        return clean(key.replacingOccurrences(of: "_", with: " ")).clipped(30)
    }

    static func words(_ value: JSONValue) -> String? {
        switch value {
        case .null: return nil
        case .bool(let b): return b ? String(localized: "yes", comment: "An approval card: an argument that is on")
            : String(localized: "no", comment: "An approval card: an argument that is off")
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .string(let s):
            // A full path reads as the person knows it (~/Documents/…), as the card's paths do.
            let text = s.hasPrefix("/") ? FolderAccess.displayPath(s) : s
            return "“\(clean(text).clipped(valueLimit))”"
        case .array(let items):
            let said = items.prefix(3).compactMap(words)
            guard !said.isEmpty else { return nil }
            let more = items.count - 3
            return more > 0 ? said.joined(separator: ", ") + " " + String(localized: "and \(more) more") : said.joined(separator: ", ")
        case .object(let o):
            // Nested values stay behind "Exact request".
            return o.isEmpty ? nil : "…"
        }
    }

    private static func clean(_ text: String) -> String { ToolFormat.oneLine(ExtensionText.clean(text), 10_000) }
}
