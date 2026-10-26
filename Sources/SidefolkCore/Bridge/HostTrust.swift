import Darwin
import Foundation

/// Which app "Open" on an agent session may bring to the front. `host_pid` and `host_bundle_id` in a
/// session event are self-reported: any local process can send one naming any app (SECURITY T4), and
/// "Open" would then raise whatever it named while the user expects their terminal.
///
/// A pid is kept only when it is a real ancestor of the process on the other end of the socket (the
/// `sidefolk hook` helper runs inside the session's own process tree), and its bundle id is then read
/// from that process, not from the payload. Without such a pid, only the bundle id of a well-known
/// terminal or editor is kept. Anything else means "Open" does nothing.
public enum HostTrust {
    /// Terminals and editors agents commonly run in. Bringing one of these forward is harmless even
    /// when the event was forged: it is the user's own terminal.
    static let knownHosts: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]

    /// How deep to look for the host above the sender; the helper climbs at most as far.
    static let maxDepth = 64

    /// Reads the process table; tests replace it.
    struct Processes: Sendable {
        var parent: @Sendable (pid_t) -> pid_t?
        var bundleId: @Sendable (pid_t) -> String?

        static let live = Processes(parent: ProcessAncestry.parent(of:), bundleId: ProcessAncestry.bundleId(of:))
    }

    /// The event with only the host details that can be trusted. Call it while the sender is still
    /// connected (it is waiting for the reply), so its parent chain is the live one.
    static func verified(_ e: SessionEvent, peer: pid_t?, processes: Processes = .live) -> SessionEvent {
        var e = e
        let claimed = e.hostPid.map(pid_t.init)
        if let claimed, let peer, isAncestor(claimed, of: peer, processes), let bundle = processes.bundleId(claimed) {
            e.hostPid = Int(claimed)
            e.hostBundleId = bundle
        } else {
            e.hostPid = nil
            e.hostBundleId = e.hostBundleId.flatMap { knownHosts.contains($0) ? $0 : nil }
        }
        return e
    }

    /// What to activate for a stored session. A pid is only used while it still runs the app it was
    /// verified as: pids get reused, and the session may have ended long ago.
    public static func target(for session: AgentSession) -> (pid: Int?, bundleId: String?) {
        target(for: session, processes: .live)
    }

    static func target(for session: AgentSession, processes: Processes) -> (pid: Int?, bundleId: String?) {
        guard let pid = session.hostPid, let app = session.hostApp, processes.bundleId(pid_t(pid)) == app else {
            return (nil, session.hostApp)
        }
        return (pid, app)
    }

    /// Whether `candidate` is strictly above `pid` in the process tree (launchd, pid 1, never counts).
    static func isAncestor(_ candidate: pid_t, of pid: pid_t, _ processes: Processes) -> Bool {
        guard candidate > 1, candidate != pid else { return false }
        var current = pid
        for _ in 0..<maxDepth {
            guard let parent = processes.parent(current), parent > 1, parent != current else { return false }
            if parent == candidate { return true }
            current = parent
        }
        return false
    }
}
