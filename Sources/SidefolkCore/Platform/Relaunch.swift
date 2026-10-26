import Foundation

/// Opens the app at `bundlePath` again once process `pid` has exited: a language change needs a fresh
/// launch, and only one Sidefolk may run at a time. The waiting shell gets nothing but stdio, so it
/// holds none of Sidefolk's files or its socket while it waits.
public enum Relaunch {
    /// - Parameter environment: carried over with `open --env`, so a dev copy keeps its own data folder
    ///   (`SIDEFOLK_HOME`) instead of waking up on the real one.
    public static func after(pid: Int32, open bundlePath: String, environment: [String: String] = [:]) throws {
        let env = environment.sorted { $0.key < $1.key }.flatMap { ["--env", "\($0.key)=\($0.value)"] }
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$@\""
        _ = try PosixSpawn.run("/bin/sh", arguments: ["-c", script, "sh"] + env + [bundlePath], environment: nil, searchPath: false,
                               options: PosixSpawn.Options(newProcessGroup: true, closeOtherDescriptors: true))
    }
}
