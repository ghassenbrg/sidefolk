import Foundation

/// A version as Sidefolk's releases are tagged (D46): `0.1.0` for a release, `0.1.0-snapshot.411` for a
/// snapshot of a later commit. Ordered as semantic versioning orders them: numbers by value, so snapshot 9
/// comes before snapshot 411, and any snapshot of 0.1.0 before 0.1.0 itself.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible, Codable {
    /// Major, minor, patch.
    public let numbers: [Int]
    /// The parts after "-" ("snapshot", "411"); empty for a release.
    public let prerelease: [String]

    /// Reads "0.1.0", "v0.1.0" (a tag) or "0.1.0-snapshot.411". Build metadata after "+" is ignored.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.hasPrefix("v") || rest.hasPrefix("V") { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        let parts = rest.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        var pre: [String] = []
        if parts.count == 2 {
            pre = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !pre.isEmpty, pre.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }) else { return nil }
        }
        self.numbers = numbers.compactMap { $0 } + Array(repeating: 0, count: 3 - numbers.count)
        prerelease = pre
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    /// For people: "0.1.0" or "0.1.0 snapshot 411".
    public var shown: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : " " + prerelease.joined(separator: " "))
    }

    public static func < (a: Self, b: Self) -> Bool {
        if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
        // A release outranks every prerelease of the same numbers.
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true    // numbers come before words
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let version = ReleaseVersion(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a version: \(text)"))
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
