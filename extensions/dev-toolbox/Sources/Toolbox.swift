import CryptoKit
import Foundation
import Security
import SidefolkExtensionKit

/// The small conversions developers reach for many times a day, done exactly instead of by a model.
enum Toolbox {
    static let operations = ["json_pretty", "json_minify", "base64_encode", "base64_decode", "url_encode", "url_decode", "hex_encode",
                             "hex_decode", "jwt_decode", "sha256", "sha1", "md5", "count"]

    static func transform(_ operation: String, _ text: String) throws -> String {
        switch operation {
        case "json_pretty", "json_minify":
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
                throw Problem("That isn't valid JSON\(jsonError(text)).")
            }
            if let at = trailingComma(text) { throw Problem("That isn't valid JSON: a comma before a closing bracket, at character \(at).") }
            let options: JSONSerialization.WritingOptions = operation == "json_pretty"
                ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed] : [.withoutEscapingSlashes, .fragmentsAllowed]
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: options), as: UTF8.self)
        case "base64_encode":
            return Data(text.utf8).base64EncodedString()
        case "base64_decode":
            return try decoded(base64(text), what: "base64")
        case "url_encode":
            return text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
        case "url_decode":
            guard let plain = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { throw Problem("That isn't valid URL encoding.") }
            return plain
        case "hex_encode":
            return Data(text.utf8).map { String(format: "%02x", $0) }.joined()
        case "hex_decode":
            let digits = text.filter { !$0.isWhitespace }.lowercased().replacingOccurrences(of: "0x", with: "")
            guard digits.count.isMultiple(of: 2), digits.allSatisfy(\.isHexDigit) else { throw Problem("That isn't hexadecimal.") }
            let bytes = stride(from: 0, to: digits.count, by: 2).map { i -> UInt8 in
                let start = digits.index(digits.startIndex, offsetBy: i)
                return UInt8(digits[start...digits.index(after: start)], radix: 16)!
            }
            return try decoded(Data(bytes), what: "hexadecimal")
        case "jwt_decode":
            return try jwt(text)
        case "sha256": return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        case "sha1": return Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        case "md5": return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        case "count":
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(text.count) characters, \(words) words, \(lines) lines, \(text.utf8.count) bytes in UTF-8."
        default:
            throw Problem("Operations: \(operations.joined(separator: ", ")).")
        }
    }

    /// Foundation's parser accepts `[1, 2,]`; JSON doesn't. The position of such a comma, outside strings.
    static func trailingComma(_ text: String) -> Int? {
        var inString = false, escaped = false, comma: Int?
        for (i, c) in text.enumerated() {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                comma = nil
            } else if c == "," {
                comma = i + 1
            } else if c == "}" || c == "]" {
                if let comma { return comma }
            } else if !c.isWhitespace {
                comma = nil
            }
        }
        return nil
    }

    /// Where JSONSerialization says the problem is, when it says.
    static func jsonError(_ text: String) -> String {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            return ""
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            return detail.map { ": \($0)" } ?? ""
        }
    }

    /// Standard or URL-safe base64, with or without padding.
    static func base64(_ text: String) throws -> Data {
        var plain = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !plain.count.isMultiple(of: 4) { plain += "=" }
        guard let data = Data(base64Encoded: plain) else { throw Problem("That isn't base64.") }
        return data
    }

    static func decoded(_ data: Data, what: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "Not text: \(data.count) bytes (\(data.prefix(32).map { String(format: "%02x", $0) }.joined())\(data.count > 32 ? "…" : ""))."
        }
        return text
    }

    /// A JWT's header and claims, readable, with its dates in words. The signature is not checked.
    static func jwt(_ token: String) throws -> String {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Problem("A JWT has three parts separated by dots.") }
        var lines: [String] = []
        for (label, part) in [("Header", parts[0]), ("Claims", parts[1])] {
            let json = try decoded(try base64(String(part)), what: "base64")
            lines.append("\(label):\n" + ((try? transform("json_pretty", json)) ?? json))
        }
        if let claims = try? JSONSerialization.jsonObject(with: try base64(String(parts[1]))) as? [String: Any] {
            for (key, word) in [("iat", "Issued"), ("nbf", "Valid from"), ("exp", "Expires")] {
                guard let seconds = (claims[key] as? NSNumber)?.doubleValue else { continue }
                let date = Date(timeIntervalSince1970: seconds)
                lines.append("\(word): \(iso(date))\(key == "exp" ? (date < Date() ? " (expired)" : " (still valid)") : "")")
            }
        }
        lines.append("The signature is not checked.")
        return lines.joined(separator: "\n")
    }

    static func iso(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: date)
    }

    /// Unix seconds or milliseconds to dates, and a date to Unix time.
    static func timestamp(_ raw: String?) throws -> String {
        let text = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        let date: Date
        if text.isEmpty || text == "now" {
            date = Date()
        } else if let number = Double(text) {
            // Past the year 2286 in seconds means it was milliseconds.
            date = Date(timeIntervalSince1970: abs(number) > 1e10 ? number / 1000 : number)
        } else {
            let format = ISO8601DateFormatter()
            let dateOnly = ISO8601DateFormatter()
            dateOnly.formatOptions = [.withFullDate]
            guard let parsed = format.date(from: text) ?? dateOnly.date(from: text) else {
                throw Problem("Give Unix time (1730000000 or milliseconds) or an ISO 8601 date (2026-10-28T09:30:00Z).")
            }
            date = parsed
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "EEEE d MMMM yyyy, HH:mm:ss zzz"
        return "Unix time \(Int(date.timeIntervalSince1970)) (milliseconds \(Int64(date.timeIntervalSince1970 * 1000)))\n"
            + "UTC: \(iso(date))\nHere: \(local.string(from: date))"
    }

    static func generate(_ kind: String, count: Int) throws -> String {
        let items: [String]
        switch kind {
        case "uuid": items = (0..<count).map { _ in UUID().uuidString.lowercased() }
        case "token":
            items = (0..<count).map { _ in
                var bytes = [UInt8](repeating: 0, count: 32)
                _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                return bytes.map { String(format: "%02x", $0) }.joined()
            }
        default: throw Problem("Generate a uuid or a token.")
        }
        return items.joined(separator: "\n")
    }

    static func checksum(_ raw: String, algorithm: String) throws -> String {
        let path = try Paths.full(raw)
        guard let handle = FileHandle(forReadingAtPath: path) else { throw Problem("\(Paths.show(path)) can't be read.") }
        defer { try? handle.close() }
        var sha256 = SHA256(), sha1 = Insecure.SHA1(), md5 = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            switch algorithm {
            case "sha1": sha1.update(data: chunk)
            case "md5": md5.update(data: chunk)
            default: sha256.update(data: chunk)
            }
        }
        let digest: [UInt8] = switch algorithm {
        case "sha1": Array(sha1.finalize())
        case "md5": Array(md5.finalize())
        default: Array(sha256.finalize())
        }
        return "\(algorithm == "sha1" || algorithm == "md5" ? algorithm.uppercased() : "SHA-256") of \(Paths.show(path)): "
            + digest.map { String(format: "%02x", $0) }.joined()
    }
}
