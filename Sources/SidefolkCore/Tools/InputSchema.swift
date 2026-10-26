import Foundation

/// Checks a tool input against the tool's JSON Schema before Guard sees it (SECURITY T1): unknown
/// keys where the schema says `additionalProperties: false`, wrong types, values outside an enum,
/// numbers outside their bounds, and sizes past a cap. Messages are written for the model, which
/// reads them and can fix its call.
///
/// Scalars are read the way the tools read them (`JSONValue.intValue` accepts "5", `textList`
/// accepts a comma-separated string), so only inputs no tool could use are refused. Schema keywords
/// it doesn't know (`oneOf`, `$ref` …) are left alone: an extension's schema can't make Sidefolk
/// stricter than it understands.
public enum InputSchema {
    /// Any one string, unless the schema sets a lower `maxLength`.
    public static let maxStringLength = 100_000
    /// Any one array, unless the schema sets a lower `maxItems`.
    public static let maxItems = 500
    /// The whole input as JSON.
    public static let maxInputBytes = 1_048_576

    /// Nil when `input` fits `schema`; otherwise one sentence saying what is wrong.
    /// - Parameter unknownKeys: accept keys the schema doesn't list. Only for the user's own calls,
    ///   which Sidefolk's UI builds and which may carry options kept out of model-facing schemas
    ///   (a watcher's `allow_local`); every other check still applies.
    public static func problem(_ schema: JSONValue, _ input: JSONValue, unknownKeys: Bool = false) -> String? {
        if input.jsonString.utf8.count > maxInputBytes { return String(localized: "The request is too large.") }
        return check(schema, input, path: "", depth: 0, unknownKeys: unknownKeys)
    }

    private static func check(_ schema: JSONValue, _ value: JSONValue, path: String, depth: Int, unknownKeys: Bool) -> String? {
        guard depth <= JSONValue.maxDepth else { return String(localized: "The request is nested too deeply.") }
        guard schema.objectValue != nil else { return nil }
        let name = path.isEmpty ? String(localized: "the input") : "“\(path)”"
        if value.isNull { return nil }   // absent; `required` is checked separately

        if let types = typeNames(schema), !types.contains(where: { matches(value, type: $0, schema: schema) }) {
            return String(localized: "\(name) should be \(types.map(article).formatted(.list(type: .or))).")
        }
        if let allowed = schema["enum"]?.arrayValue, !allowed.isEmpty, !allowed.contains(where: { same(value, $0) }) {
            let shown = allowed.prefix(12).map { $0.stringValue ?? $0.jsonString }.joined(separator: ", ")
            return String(localized: "\(name) must be one of: \(shown).")
        }

        switch value {
        case .string(let s):
            let limit = min(schema["maxLength"]?.intValue ?? maxStringLength, maxStringLength)
            if s.count > limit { return String(localized: "\(name) is too long (at most \(limit) characters).") }
            if let min = schema["minLength"]?.intValue, s.count < min { return String(localized: "\(name) is too short.") }
            if isNumeric(schema) { return bounds(schema, value, name: name) }
        case .number:
            return bounds(schema, value, name: name)
        case .array(let items):
            let limit = min(schema["maxItems"]?.intValue ?? maxItems, maxItems)
            if items.count > limit { return String(localized: "\(name) has too many entries (at most \(limit)).") }
            if let itemSchema = schema["items"], itemSchema.objectValue != nil {
                for (i, item) in items.enumerated() {
                    if let why = check(itemSchema, item, path: "\(path.isEmpty ? "item" : path)[\(i)]", depth: depth + 1, unknownKeys: unknownKeys) { return why }
                }
            }
        case .object(let fields):
            let properties = schema["properties"]?.objectValue ?? [:]
            if !unknownKeys, schema["additionalProperties"] == .bool(false) {
                if let extra = fields.keys.sorted().first(where: { properties[$0] == nil }) {
                    let known = properties.keys.sorted().joined(separator: ", ")
                    let field = join(path, extra).clipped(64)
                    return known.isEmpty ? String(localized: "“\(field)” isn't something this tool takes.")
                        : String(localized: "“\(field)” isn't something this tool takes (it takes: \(known)).")
                }
            }
            for key in fields.keys.sorted() {
                guard let sub = properties[key], let v = fields[key] else { continue }
                if let why = check(sub, v, path: join(path, key), depth: depth + 1, unknownKeys: unknownKeys) { return why }
            }
        default:
            break
        }
        return nil
    }

    private static func typeNames(_ schema: JSONValue) -> [String]? {
        switch schema["type"] {
        case .string(let t)?: [t]
        case .array(let list)?: list.compactMap(\.stringValue).nilIfEmpty
        default: nil
        }
    }

    private static func matches(_ value: JSONValue, type: String, schema: JSONValue) -> Bool {
        switch type {
        case "string": value.stringValue != nil
        case "integer": value.intValue != nil
        case "number": value.doubleValue?.isFinite == true
        case "boolean": value.boolValue != nil
        case "object": value.objectValue != nil
        // Tools read a comma-separated string of text as a list (`textList`).
        case "array": value.arrayValue != nil || (value.stringValue != nil && schema["items"]?["type"]?.stringValue == "string")
        case "null": value.isNull
        default: true
        }
    }

    private static func isNumeric(_ schema: JSONValue) -> Bool {
        typeNames(schema)?.contains { $0 == "integer" || $0 == "number" } ?? false
    }

    private static func bounds(_ schema: JSONValue, _ value: JSONValue, name: String) -> String? {
        guard let n = value.doubleValue else { return nil }
        if let min = schema["minimum"]?.doubleValue, n < min { return String(localized: "\(name) must be at least \(format(min)).") }
        if let max = schema["maximum"]?.doubleValue, n > max { return String(localized: "\(name) must be at most \(format(max)).") }
        return nil
    }

    /// Enum matching tolerates letter case and surrounding spaces, as the tools do.
    private static func same(_ value: JSONValue, _ allowed: JSONValue) -> Bool {
        if let a = value.stringValue, let b = allowed.stringValue {
            return a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b) == .orderedSame
        }
        return value == allowed
    }

    private static func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    private static func article(_ type: String) -> String {
        switch type {
        case "integer": String(localized: "a whole number")
        case "number": String(localized: "a number")
        case "boolean": String(localized: "true or false")
        case "array": String(localized: "a list")
        case "object": String(localized: "an object")
        case "string": String(localized: "text")
        default: type
        }
    }

    /// Bounds come from extension schemas too, so a giant one must not reach `Int(_:)`, which traps past Int.max.
    private static func format(_ n: Double) -> String { n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n) }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
