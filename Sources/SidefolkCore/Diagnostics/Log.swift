import Foundation
import os
import Synchronization

/// Structured local diagnostics: os.Logger for Console.app plus a JSONL file (7 days) for export.
/// Messages pass through `Redactor` so secrets never reach disk.
public final class Log: Sendable {
    public enum Level: String, Sendable { case debug, info, warning, error }

    public static let shared = Log()

    private let subsystem = "app.sidefolk"
    private let state = Mutex<(dir: URL?, handle: FileHandle?, day: String, debug: Bool)>((nil, nil, "", false))

    public func configure(directory: URL, debug: Bool) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state.withLock {
            try? $0.handle?.close()
            $0 = (directory, nil, "", debug)
        }
        prune(directory: directory, keepDays: 7)
    }

    public func setDebug(_ on: Bool) { state.withLock { $0.debug = on } }

    public func debug(_ category: String, _ message: @autoclosure () -> String, _ fields: [String: String] = [:]) {
        guard state.withLock({ $0.debug }) else { return }
        write(.debug, category, message(), fields)
    }

    public func info(_ category: String, _ message: String, _ fields: [String: String] = [:]) { write(.info, category, message, fields) }
    public func warning(_ category: String, _ message: String, _ fields: [String: String] = [:]) { write(.warning, category, message, fields) }
    public func error(_ category: String, _ message: String, _ fields: [String: String] = [:]) { write(.error, category, message, fields) }

    private func write(_ level: Level, _ category: String, _ message: String, _ fields: [String: String]) {
        let clean = Redactor.redact(message)
        let cleanFields = fields.mapValues { Redactor.redact($0).clipped(2000) }
        let logger = Logger(subsystem: subsystem, category: category)
        // Field values may hold personal content: Console shows them only when private data is enabled.
        let detail = cleanFields.isEmpty ? "" : " " + cleanFields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        switch level {
        case .debug: logger.debug("\(clean, privacy: .public)\(detail, privacy: .private)")
        case .info: logger.info("\(clean, privacy: .public)\(detail, privacy: .private)")
        case .warning: logger.warning("\(clean, privacy: .public)\(detail, privacy: .private)")
        case .error: logger.error("\(clean, privacy: .public)\(detail, privacy: .private)")
        }

        var record: [String: String] = cleanFields
        record["t"] = ISO8601DateFormatter().string(from: Date())
        record["level"] = level.rawValue
        record["cat"] = category
        record["msg"] = clean
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        state.withLock { s in
            guard let dir = s.dir else { return }
            let day = String(record["t"]!.prefix(10))
            if s.handle == nil || s.day != day {
                try? s.handle?.close()
                let url = dir.appendingPathComponent("sidefolk-\(day).jsonl")
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                s.handle = try? FileHandle(forWritingTo: url)
                _ = try? s.handle?.seekToEnd()
                s.day = day
            }
            s.handle?.write(data + Data("\n".utf8))
        }
    }

    private func prune(directory: URL, keepDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files where f.pathExtension == "jsonl" {
            if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < cutoff {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}

/// Removes things that must never be logged or exported.
public enum Redactor {
    private static let patterns: [NSRegularExpression] = [
        #"sk-[A-Za-z0-9_\-]{12,}"#,                       // OpenAI / Anthropic style keys
        #"sk-ant-[A-Za-z0-9_\-]{12,}"#,
        #"(?i)(api[_-]?key|token|secret|password|authorization)(["'\s:=]+)([^\s"',}]{6,})"#,
        #"(?i)bearer\s+[A-Za-z0-9._\-]{10,}"#,
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,
        #"xox[abpr]-[A-Za-z0-9\-]{10,}"#,
        #"AKIA[0-9A-Z]{16}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func redact(_ text: String) -> String {
        var out = text
        for re in patterns {
            let range = NSRange(out.startIndex..., in: out)
            if re.numberOfCaptureGroups >= 3 {
                out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "$1$2[redacted]")
            } else {
                out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "[redacted]")
            }
        }
        return out
    }

    /// Tool arguments as stored in Activity: secrets removed, long text shortened.
    public static func arguments(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let s): return .string(redact(s).clipped(300))
        case .array(let a): return .array(a.prefix(20).map(arguments))
        case .object(let o):
            var result: [String: JSONValue] = [:]
            for (k, v) in o {
                let lower = k.lowercased()
                if ["api_key", "apikey", "token", "password", "secret", "authorization"].contains(where: lower.contains) {
                    result[k] = "[redacted]"
                } else {
                    result[k] = arguments(v)
                }
            }
            return .object(result)
        default: return value
        }
    }
}
