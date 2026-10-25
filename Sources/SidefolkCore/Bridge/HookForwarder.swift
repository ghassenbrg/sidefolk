import Darwin
import Foundation

/// `sidefolk hook <EventName>`, run by Claude Code as a command hook. It reads the hook payload
/// (untrusted, capped), adds which app hosts the session, forwards a small subset to the app and
/// returns. It never prints, never fails and stays within a 2 s budget: a hook must never block
/// or slow the user's session (T4).
public enum HookForwarder {
    public static let payloadLimit = 256 * 1024
    public static let budget: TimeInterval = 2

    public static func run(event: String, socketPath: String, input: Int32 = STDIN_FILENO,
                           environment: [String: String] = ProcessInfo.processInfo.environment) async {
        let started = Date()
        guard isEventName(event) else { return }
        let bytes = readInput(input, limit: payloadLimit, deadline: started.addingTimeInterval(budget / 2))
        guard let e = sessionEvent(name: event, payload: bytes, host: ProcessAncestry.host(environment: environment),
                                   tty: ProcessAncestry.controllingTTY()) else { return }
        let remaining = budget - Date().timeIntervalSince(started) - 0.1
        guard remaining > 0.1 else { return }
        guard let client = try? await BridgeClient.connect(socketPath: socketPath, client: "sidefolk-hook", timeout: remaining) else { return }
        defer { client.close() }
        _ = try? await client.call(BridgeProtocol.Method.sessionEvent.rawValue, e.json,
                                   timeout: max(0.1, budget - Date().timeIntervalSince(started) - 0.1))
    }

    static func isEventName(_ name: String) -> Bool {
        (1...40).contains(name.count) && name.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// The event Sidefolk needs from a Claude Code hook payload. A payload cut at the size cap
    /// isn't valid JSON, so the leading fields are then picked out of the text.
    static func sessionEvent(name: String, payload: [UInt8], host: HostApp?, tty: String?) -> SessionEvent? {
        let text = String(decoding: payload, as: UTF8.self)
        let json = (try? JSONValue.parse(text)) ?? .object(leadingFields(text))
        guard let session = json.string("session_id") else { return nil }
        var e = SessionEvent(event: name, sessionId: String(session.prefix(128)))
        e.cwd = json.string("cwd")
        e.message = json.string("message").map { SessionEvent.oneLine($0, 300) }
        e.notificationType = json.string("notification_type")
        e.toolName = json.string("tool_name").map { String($0.prefix(128)) }
        e.prompt = json.string("prompt").map { SessionEvent.oneLine($0, 120) }
        e.hostBundleId = host?.bundleId
        e.hostPid = host?.pid
        e.tty = tty
        return e
    }

    private static func leadingFields(_ text: String) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        for key in ["session_id", "cwd", "tool_name", "hook_event_name"] {
            let pattern = "\"\(key)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")"
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text),
                  let value = try? JSONValue.parse(String(text[r])) else { continue }
            fields[key] = value
        }
        return fields
    }

    /// Reads at most `limit` bytes, giving up at `deadline` (Claude Code writes the payload and
    /// closes stdin right away; anything slower is not worth waiting for).
    static func readInput(_ fd: Int32, limit: Int, deadline: Date) -> [UInt8] {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let n = read(fd, &chunk, min(chunk.count, limit - data.count))
            if n > 0 { data += chunk[0..<n]; continue }
            if n == 0 { break }
            if errno == EINTR { continue }
            guard errno == EAGAIN, UnixSocket.waitReadable(fd, until: deadline) else { break }
        }
        return data
    }
}

/// The app hosting an agent session, so "Open" can bring it to the front.
public struct HostApp: Sendable, Equatable {
    public var bundleId: String?
    public var pid: Int?
}

/// Finds the hosting app by walking up the parent process chain with libproc.
public enum ProcessAncestry {
    /// The outermost `.app` above us (Terminal, iTerm2, VS Code, Ghostty, Warp, Cursor…) and the pid
    /// of its main process. When no ancestor lives in an app bundle (iTerm2's server process,
    /// tmux), the bundle id macOS leaves in `__CFBundleIdentifier` is used without a pid.
    public static func host(startingAt pid: pid_t = getppid(), environment: [String: String] = [:]) -> HostApp? {
        var current = pid
        var found: (bundle: String, pid: pid_t)?
        for _ in 0..<64 where current > 1 {
            let bundle = executablePath(of: current).flatMap(topLevelBundle)
            if let bundle {
                // Keep climbing while still inside the same app: helpers sit below its main process.
                guard found == nil || found?.bundle == bundle else { break }
                found = (bundle, current)
            } else if found != nil {
                break
            }
            guard let parent = parent(of: current), parent != current else { break }
            current = parent
        }
        if let found, let id = Bundle(path: found.bundle)?.bundleIdentifier {
            return HostApp(bundleId: id, pid: Int(found.pid))
        }
        if let id = environment["__CFBundleIdentifier"], !id.isEmpty, id.count <= 155,
           id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) {
            return HostApp(bundleId: id, pid: nil)
        }
        return nil
    }

    /// "/Applications/Visual Studio Code.app" from any path inside it, nested helper apps included.
    public static func topLevelBundle(_ executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }

    /// "/dev/ttys004" for this process's controlling terminal, if it has one.
    public static func controllingTTY(of pid: pid_t = getpid()) -> String? {
        guard let info = bsdInfo(pid), info.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) else {
            return nil
        }
        let tty = String(cString: name)
        return tty == "??" ? nil : "/dev/" + tty
    }

    static func parent(of pid: pid_t) -> pid_t? { bsdInfo(pid).map { pid_t($0.pbi_ppid) } }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[0..<Int(length)], as: UTF8.self)
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }
}
