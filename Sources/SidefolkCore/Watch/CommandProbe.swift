import CryptoKit
import Foundation

/// What a command watcher is waiting for.
struct CommandCondition: Equatable {
    var exitCode: Int?
    var outputContains: String?
    var changed: Bool

    init(_ json: JSONValue) {
        exitCode = json["exit_code"]?.intValue
        outputContains = json.string("output_contains")
        changed = json["changed"]?.boolValue ?? (exitCode == nil && outputContains == nil)
    }

    var json: JSONValue {
        if let exitCode { return ["exit_code": .number(Double(exitCode))] }
        if let outputContains { return ["output_contains": .string(outputContains)] }
        return ["changed": true]
    }
}

/// Runs a shell command on a schedule. Only the user, or Sidefolk's own agent after the user approved
/// the exact command, can create one (docs/SECURITY.md T9); the command's output is never trusted.
public struct CommandProbe: WatcherProbe {
    public let kind = WatchKind.command
    public var defaultInterval: TimeInterval { 5 * 60 }
    public var minimumInterval: TimeInterval { 60 }

    /// Reporting its output may go faster than waiting for a change: the person asked to see it.
    public func minimumInterval(for watcher: Watcher) -> TimeInterval {
        watcher.mode == .report ? ReportFloors.command : minimumInterval
    }

    let timeout: TimeInterval
    let grace: TimeInterval

    public init(timeout: TimeInterval = ShellRunner.timeout, grace: TimeInterval = ShellRunner.grace) {
        self.timeout = timeout
        self.grace = grace
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        guard WatchSource.mayRunCommands(w.source) else {
            throw WatchError.notAllowed(String(localized: "Only you, or Sidefolk after you approve the exact command, can set up a command watcher."))
        }
        guard let command = w.config.string("command") else { throw WatchError.invalid(String(localized: "Tell me which command to run.")) }
        guard command.count <= 2000, !command.contains("\0") else { throw WatchError.invalid(String(localized: "That command is too long to watch.")) }
        var config = (w.mode == .report ? Report.options(of: w.config) : .object([:])).objectValue ?? [:]
        config["command"] = .string(command)
        if let cwd = w.config.string("cwd") {
            let expanded = (cwd as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/"), let canonical = FolderAccess.canonical(expanded) else {
                throw WatchError.invalid(String(localized: "The folder to run in needs a full path without “..”."))
            }
            if let why = FolderAccess.forbiddenReason([canonical]) { throw WatchError.invalid(why) }
            guard FileFacts.read(canonical)?.isDirectory == true else { throw WatchError.invalid(String(localized: "I can't find the folder to run in.")) }
            config["cwd"] = .string(canonical)
        }
        w.config = .object(config)
        if w.mode == .report {
            w.condition = .object([:])
            return w
        }

        let condition = CommandCondition(w.condition)
        if let code = condition.exitCode, !(0...255).contains(code) { throw WatchError.invalid(String(localized: "An exit code is a number from 0 to 255.")) }
        if let text = condition.outputContains, text.count > 200 { throw WatchError.invalid(String(localized: "The text to look for is too long (200 characters at most).")) }
        w.condition = condition.json
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        // The row could have been written by anything; the rule is enforced again where the code runs.
        guard WatchSource.mayRunCommands(w.source) else { throw ProbeError.failed(String(localized: "This command watcher wasn't made by you, so I won't run it.")) }
        guard let command = w.config.string("command") else { throw ProbeError.failed(String(localized: "This watcher has no command.")) }
        let condition = CommandCondition(w.condition)

        // No folder given: run in a fresh empty one, removed afterwards.
        var scratch: URL?
        defer { scratch.map { try? FileManager.default.removeItem(at: $0) } }
        var cwd = w.config.string("cwd")
        if let folder = cwd {
            guard FolderAccess.canonical(folder) == folder, FileFacts.read(folder)?.isDirectory == true else {
                throw ProbeError.failed(String(localized: "The folder this command runs in has changed or is gone."))
            }
        } else {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-cmd-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            scratch = dir
            cwd = FolderAccess.canonical(dir.path) ?? dir.path
        }

        let result: ShellResult
        do { result = try await ShellRunner.run(command, cwd: cwd ?? "/", timeout: timeout, grace: grace) } catch {
            throw ProbeError.failed(String(localized: "I couldn't start the command."))
        }
        if result.timedOut { throw ProbeError.failed(String(localized: "The command took longer than \(Int(timeout.rounded(.up))) seconds, so I stopped it.")) }

        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if w.mode == .report { return try Self.report(output, exitCode: result.exitCode) }
        let hash = SHA256.hash(data: Data(output.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let tail = String(output.suffix(400))
        let previous = w.lastState
        var state: [String: JSONValue] = ["exit": .number(Double(result.exitCode)), "hash": .string(hash), "tail": .string(tail)]
        let label = w.title.displaySafe.clipped(60)
        let shown = output.displaySafe.suffix(180)
        let detail = shown.isEmpty ? nil : String(localized: "Output: \(String(shown))")

        if let code = condition.exitCode {
            let matched = Int(result.exitCode) == code
            state["matched"] = .bool(matched)
            guard matched, previous?["matched"]?.boolValue != true else { return ProbeResult(state: .object(state)) }
            let summary = code == 0 ? String(localized: "\(label) succeeded") : String(localized: "\(label) exited with code \(code)")
            return ProbeResult(state: .object(state), triggered: true, summary: summary, detail: detail)
        }
        if let text = condition.outputContains {
            let matched = result.output.range(of: text, options: .caseInsensitive) != nil
            state["matched"] = .bool(matched)
            guard matched, previous?["matched"]?.boolValue != true else { return ProbeResult(state: .object(state)) }
            return ProbeResult(state: .object(state), triggered: true, summary: String(localized: "\(label): found “\(text.displaySafe.clipped(60))”"),
                               detail: detail)
        }
        guard let before = previous?["hash"]?.stringValue else { return ProbeResult(state: .object(state)) } // first run is the baseline
        guard before != hash else { return ProbeResult(state: .object(state)) }
        let was = previous?["tail"]?.stringValue?.displaySafe.suffix(90) ?? ""
        let change = was.isEmpty ? detail : "“\(was)” → “\(output.displaySafe.suffix(90))”"
        return ProbeResult(state: .object(state), triggered: true, summary: String(localized: "\(label): the output changed"), detail: change)
    }

    /// A report shows the output's last line, as it is: someone else's text, marked so.
    static func report(_ output: String, exitCode: Int32) throws -> ProbeResult {
        let line = output.components(separatedBy: .newlines).map(\.displaySafe).last { !$0.isEmpty } ?? ""
        guard !line.isEmpty else {
            throw ProbeError.failed(exitCode == 0 ? String(localized: "The command printed nothing.")
                : String(localized: "The command printed nothing and exited with code \(exitCode)."))
        }
        let shown = line.clipped(WatchLimits.readingLimit)
        return ProbeResult(state: ["exit": .number(Double(exitCode))], reading: ReadingText(shown: shown, forModel: shown, fromOutside: true))
    }
}
