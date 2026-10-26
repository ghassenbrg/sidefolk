import Darwin
import Foundation
import Synchronization

/// Runs automation programs with `/usr/bin/osascript -l JavaScript`, one process per call.
///
/// A child process rather than `NSAppleScript` in the app: Apple Events block until the other app
/// answers (or until the person answers macOS's permission prompt), and a stuck Notes must never
/// freeze Sidefolk's main thread. A child also has a hard deadline: the whole process group goes.
/// macOS attributes the child's Apple Events to Sidefolk, the responsible app, so the permission is
/// Sidefolk's and appears under Sidefolk in Privacy & Security › Automation.
///
/// The script goes over stdin and the parameters inside it, never in argv (other local users can read
/// every process's arguments). The environment is a fixed allow-list, fds 0–2 are the only ones
/// inherited (`PipedChild`).
public struct OsascriptRunner: AppleEventsRunner {
    static let executable = "/usr/bin/osascript"
    /// One JSON line; a note body is capped inside the program, so this only stops a runaway.
    static let outputLimit = 16 << 20

    /// JavaScript defining a stand-in for the app, and the expression that makes one: tests only.
    private let standIn: (definition: String, expression: String)?

    public init() { standIn = nil }

    /// Runs the programs against `definition`'s object model instead of the real app: no Apple Event
    /// is sent, so nothing asks for permission and no one's notes are read.
    init(standIn definition: String, expression: String) { standIn = (definition, expression) }

    public func run(_ program: String, name: String, params: JSONValue, app: MacApp, timeout: TimeInterval) async throws -> JSONValue {
        let source = standIn.map { AutomationScript.source(program: program, params: params, appExpression: $0.expression) + "\n" + $0.definition }
            ?? AutomationScript.source(program: program, params: params, app: app)
        let child: PipedChild
        do {
            child = try PipedChild.spawn(Self.executable, arguments: ["-l", "JavaScript", "-"], environment: Self.environment(),
                                         cwd: NSTemporaryDirectory())
        } catch {
            throw AppleEventsError.failed(app, code: 0, message: "osascript didn't start: \(error)")
        }
        let timedOut = Atomic<Bool>(false)
        let timer = Task {
            try await Task.sleep(for: .seconds(timeout))
            timedOut.store(true, ordering: .relaxed)
            child.signalGroup(SIGKILL)
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            child.write(source)
            child.closeInput()
            let reader = DescriptorLineReader(fd: child.output, limit: Self.outputLimit)
            var lines: [String] = []
            var tooLong = false
            while let item = await reader.next() {
                switch item {
                case .line(let bytes): lines.append(String(decoding: bytes, as: UTF8.self))
                case .tooLong: tooLong = true
                }
            }
            let status = await child.wait()
            Log.shared.debug("macapps", "osascript finished", ["program": name, "status": String(describing: status)])
            if timedOut.load(ordering: .relaxed) { throw AppleEventsError.noAnswer(app) }
            if tooLong { throw AppleEventsError.failed(app, code: 0, message: "output over \(Self.outputLimit) bytes") }
            let printed = lines.joined(separator: "\n")
            if case .exited(0) = status { return try AutomationScript.result(printed, app: app) }
            // The wrapper catches script errors itself; reaching here means osascript failed to run it.
            let errors = await child.stderr()
            throw AppleEventsError.from(code: Self.errorNumber(in: errors) ?? 0, message: errors.clipped(300), app: app)
        } onCancel: {
            child.signalGroup(SIGKILL)
        }
    }

    /// The trailing "(-1743)" osascript puts after a failure.
    static func errorNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return nil }
        return Int(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
    }

    static func environment() -> [String: String] {
        let user = NSUserName()
        return ["HOME": NSHomeDirectory(), "USER": user, "LOGNAME": user, "LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin",
                "TMPDIR": NSTemporaryDirectory()]
    }
}
