import Foundation
import SidefolkExtensionKit

/// Arithmetic worked out exactly, so an answer never rests on a model's mental maths: + − × ÷, powers (^),
/// percentages ("15% of 80", "200 + 10%"), parentheses, and a few functions. Angles are in degrees.
struct Arithmetic {
    private let tokens: [Token]
    private var at = 0

    enum Token: Equatable {
        case number(Double)
        case word(String)
        case symbol(Character)
    }

    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": { cbrt($0) }, "abs": { abs($0) }, "round": { $0.rounded() }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
        "sin": { sin($0 * .pi / 180) }, "cos": { cos($0 * .pi / 180) }, "tan": { tan($0 * .pi / 180) },
        "asin": { asin($0) * 180 / .pi }, "acos": { acos($0) * 180 / .pi }, "atan": { atan($0) * 180 / .pi },
    ]
    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E]

    static func evaluate(_ text: String) throws -> Double {
        var parser = Arithmetic(tokens: try tokenize(text))
        let value = try parser.sum()
        guard parser.at == parser.tokens.count else { throw Problem("I couldn't read “\(text)” as a calculation.") }
        guard value.isFinite else { throw Problem("That has no finite answer (dividing by zero, or a number too big).") }
        return value
    }

    static func tokenize(_ text: String) throws -> [Token] {
        let chars = Array(text.lowercased().replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "**", with: "^"))
        func digits(from i: Int) -> Int { var j = i; while j < chars.count, chars[j].isNumber { j += 1 }; return j - i }
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isNumber || c == "." {
                var j = i
                // "1,000,000.5": a comma is a thousands separator only before exactly three digits.
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "," && digits(from: j + 1) == 3 { j += 1 }
                let number = String(chars[i..<j]).replacingOccurrences(of: ",", with: "")
                guard let value = Double(number) else { throw Problem("“\(number)” isn't a number.") }
                tokens.append(.number(value))
                i = j
            } else if c == "x", i + 1 == chars.count || !chars[i + 1].isLetter {
                // "3x4", "3 x 4": an x on its own multiplies.
                tokens.append(.symbol("*"))
                i += 1
            } else if c.isLetter || c == "π" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
                tokens.append(.word(String(chars[i..<j])))
                i = j
            } else if "+-*/^%()".contains(c) {
                tokens.append(.symbol(c))
                i += 1
            } else {
                throw Problem(c == "," ? "Write decimals with a dot, like 1.5." : "I can't use “\(c)” in a calculation.")
            }
        }
        return tokens
    }

    private var next: Token? { at < tokens.count ? tokens[at] : nil }

    /// a + b, a − b; "200 + 10%" is 220 (the percentage of what it is added to).
    private mutating func sum() throws -> Double {
        var value = try product()
        while let token = next, token == .symbol("+") || token == .symbol("-") {
            at += 1
            let (right, percent) = try percentTerm()
            let amount = percent ? value * right / 100 : right
            value = token == .symbol("+") ? value + amount : value - amount
        }
        return value
    }

    /// A term that may be a bare percentage ("10%") right before the end or a closing parenthesis.
    private mutating func percentTerm() throws -> (Double, Bool) {
        let start = at
        if case .number(let n)? = next, at + 1 < tokens.count, tokens[at + 1] == .symbol("%"),
           at + 2 == tokens.count || tokens[at + 2] == .symbol(")") || tokens[at + 2] == .symbol("+") || tokens[at + 2] == .symbol("-") {
            at += 2
            return (n, true)
        }
        at = start
        return (try product(), false)
    }

    private mutating func product() throws -> Double {
        var value = try unary()
        while let token = next {
            if token == .symbol("*") || token == .word("of") {
                at += 1
                value *= try unary()
            } else if token == .symbol("/") {
                at += 1
                value /= try unary()
            } else if token == .word("mod") {
                at += 1
                value = value.truncatingRemainder(dividingBy: try unary())
            } else {
                break
            }
        }
        return value
    }

    /// A sign applies to the power after it: -2^2 is -4, as in maths.
    private mutating func unary() throws -> Double {
        if next == .symbol("-") { at += 1; return -(try unary()) }
        if next == .symbol("+") { at += 1; return try unary() }
        return try power()
    }

    /// Powers group from the right: 2^3^2 is 2^9. The exponent may have a sign: 2^-1.
    private mutating func power() throws -> Double {
        let base = try percent()
        guard next == .symbol("^") else { return base }
        at += 1
        return pow(base, try unary())
    }

    /// "15%" is 0.15; "15% of 80" is 12.
    private mutating func percent() throws -> Double {
        var value = try atom()
        while next == .symbol("%") {
            at += 1
            value /= 100
        }
        return value
    }

    private mutating func atom() throws -> Double {
        switch next {
        case .number(let n)?:
            at += 1
            return n
        case .symbol("(")?:
            at += 1
            let value = try sum()
            guard next == .symbol(")") else { throw Problem("A parenthesis isn't closed.") }
            at += 1
            return value
        case .word(let w)?:
            at += 1
            if let constant = Self.constants[w] { return constant }
            guard let function = Self.functions[w] else { throw Problem("I don't know “\(w)”. I know \(Self.functions.keys.sorted().joined(separator: ", ")), pi and e.") }
            return function(try percent())
        default:
            throw Problem("The calculation ends too early or has an operator in the wrong place.")
        }
    }

    /// Up to 12 significant digits, without trailing zeros: 0.1 + 0.2 shows as 0.3.
    static func show(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(format: "%.0f", value) : String(format: "%.12g", value)
    }
}
