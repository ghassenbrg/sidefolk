import Foundation

/// JSON that keeps key order and number spelling, so editing one key of another tool's config
/// (`~/.claude.json`, `settings.json`) leaves every other byte as that tool wrote it.
/// Output matches JavaScript's `JSON.stringify(value, null, 2)`, which Claude Code uses.
indirect enum OrderedJSON: Equatable {
    case null
    case bool(Bool)
    /// The number as written in the file.
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([Member])

    struct Member: Equatable {
        var key: String
        var value: OrderedJSON
    }

    subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let i = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[i].value = newValue } else { members.remove(at: i) }
            } else if let newValue {
                members.append(Member(key: key, value: newValue))
            }
            self = .object(members)
        }
    }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    var arrayValue: [OrderedJSON]? { if case .array(let a) = self { a } else { nil } }
    var isObject: Bool { if case .object = self { true } else { false } }

    // MARK: Parsing

    struct ParseError: Error, CustomStringConvertible {
        var offset: Int
        var description: String { "invalid JSON near byte \(offset)" }
    }

    static func parse(_ text: String) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipSpace()
        let value = try parser.value(depth: 0)
        parser.skipSpace()
        guard parser.at == parser.bytes.count else { throw ParseError(offset: parser.at) }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var at = 0

        mutating func skipSpace() {
            while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < 512, at < bytes.count else { throw ParseError(offset: at) }
            switch bytes[at] {
            case UInt8(ascii: "{"):
                at += 1
                var members: [Member] = []
                skipSpace()
                if peek(UInt8(ascii: "}")) { at += 1; return .object(members) }
                while true {
                    skipSpace()
                    let key = try string()
                    skipSpace()
                    try expect(UInt8(ascii: ":"))
                    skipSpace()
                    members.append(Member(key: key, value: try value(depth: depth + 1)))
                    skipSpace()
                    if peek(UInt8(ascii: ",")) { at += 1; continue }
                    try expect(UInt8(ascii: "}"))
                    return .object(members)
                }
            case UInt8(ascii: "["):
                at += 1
                var items: [OrderedJSON] = []
                skipSpace()
                if peek(UInt8(ascii: "]")) { at += 1; return .array(items) }
                while true {
                    skipSpace()
                    items.append(try value(depth: depth + 1))
                    skipSpace()
                    if peek(UInt8(ascii: ",")) { at += 1; continue }
                    try expect(UInt8(ascii: "]"))
                    return .array(items)
                }
            case UInt8(ascii: "\""):
                return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default:
                return .number(try number())
            }
        }

        func peek(_ byte: UInt8) -> Bool { at < bytes.count && bytes[at] == byte }

        mutating func expect(_ byte: UInt8) throws {
            guard peek(byte) else { throw ParseError(offset: at) }
            at += 1
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard at + w.count <= bytes.count, Array(bytes[at..<at + w.count]) == w else { throw ParseError(offset: at) }
            at += w.count
        }

        mutating func number() throws -> String {
            let start = at
            while at < bytes.count, "+-0123456789.eE".utf8.contains(bytes[at]) { at += 1 }
            let text = String(decoding: bytes[start..<at], as: UTF8.self)
            guard !text.isEmpty, Double(text) != nil else { throw ParseError(offset: start) }
            return text
        }

        mutating func string() throws -> String {
            try expect(UInt8(ascii: "\""))
            var out: [UInt8] = []
            while at < bytes.count {
                let b = bytes[at]
                at += 1
                switch b {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard at < bytes.count else { throw ParseError(offset: at) }
                    let e = bytes[at]
                    at += 1
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var scalar = try hex4()
                        if (0xD800..<0xDC00).contains(scalar), peek(UInt8(ascii: "\\")), at + 1 < bytes.count, bytes[at + 1] == UInt8(ascii: "u") {
                            at += 2
                            let low = try hex4()
                            if (0xDC00..<0xE000).contains(low) { scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00) }
                        }
                        out += Array(String(Unicode.Scalar(scalar).map(Character.init) ?? "\u{FFFD}").utf8)
                    default: throw ParseError(offset: at)
                    }
                default:
                    guard b >= 0x20 else { throw ParseError(offset: at) }
                    out.append(b)
                }
            }
            throw ParseError(offset: at)
        }

        mutating func hex4() throws -> UInt32 {
            guard at + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[at..<at + 4], as: UTF8.self), radix: 16) else {
                throw ParseError(offset: at)
            }
            at += 4
            return v
        }
    }

    // MARK: Writing

    /// Two-space indentation like `JSON.stringify(value, null, 2)`.
    func serialized(indent: String = "") -> String {
        let inner = indent + "  "
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return Self.quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[\n" + items.map { inner + $0.serialized(indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            return "{\n" + members.map { inner + Self.quote($0.key) + ": " + $0.value.serialized(indent: inner) }.joined(separator: ",\n")
                + "\n" + indent + "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
