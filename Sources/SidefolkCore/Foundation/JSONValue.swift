import Foundation

/// Dynamic JSON used for tool inputs, schemas, configs and protocol messages.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

/// JSON nested deeper than `JSONValue.maxDepth`.
public struct JSONDepthError: Error, Sendable, CustomStringConvertible {
    public init() {}
    public var description: String { "The JSON is nested more than \(JSONValue.maxDepth) levels deep." }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var intValue: Int? { doubleValue.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil } }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return ["true", "yes", "1"].contains(s.lowercased()) ? true : (["false", "no", "0"].contains(s.lowercased()) ? false : nil)
        default: return nil
        }
    }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Non-empty trimmed string for `key`, or nil.
    func string(_ key: String) -> String? {
        guard let s = self[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// Parses JSON that came from outside (extensions, the socket, model replies, files). Nesting is
    /// checked first: a 1 KB message of a few hundred `[` would otherwise recurse deep enough to
    /// overflow a task's stack and take the whole app down.
    static func parse(_ data: Data) throws -> JSONValue {
        try checkDepth(data)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Deepest nesting of arrays and objects Sidefolk accepts.
    static let maxDepth = 64

    /// Throws `JSONDepthError` when arrays and objects nest deeper than `maxDepth` (string contents are skipped).
    static func checkDepth(_ data: Data) throws {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x5B, 0x7B:
                depth += 1
                if depth > maxDepth { throw JSONDepthError() }
            case 0x5D, 0x7D: depth -= 1
            default: break
            }
        }
    }

    /// Compact, key-sorted JSON text.
    var jsonString: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Indented, key-sorted JSON text, for files people read (extension drafts).
    var prettyString: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        guard let data = try? enc.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
