import Darwin
import Foundation
import Synchronization

/// `sidefolk run [--title "..."] -- <cmd> [args…]`, parsed.
public struct RunRequest: Sendable, Equatable {
    public var title: String?
    public var command: [String]

    /// The title Sidefolk shows: the one given, or the command line itself.
    public var displayTitle: String { (title ?? CommandRunner.display(command)).clipped(60) }

    public static func parse(_ args: [String]) -> Result<RunRequest, RunUsageError> {
        var title: String?
        var rest = args[...]
        while let first = rest.first {
            if first == "--" { rest = rest.dropFirst(); break }
            if first == "--title" || first == "-t" {
                guard rest.count >= 2 else { return .failure(RunUsageError(message: "--title needs a value.")) }
                title = rest[rest.startIndex + 1]
                rest = rest.dropFirst(2)
            } else if first.hasPrefix("--title=") {
                title = String(first.dropFirst("--title=".count))
                rest = rest.dropFirst()
            } else if first.hasPrefix("-") {
                return .failure(RunUsageError(message: "Unknown option \(first). Put the command after --."))
            } else {
                break
            }
        }
        guard !rest.isEmpty else { return .failure(RunUsageError(message: "Give the command to run after --.")) }
        let trimmed = title?.trimmingCharacters(in: .whitespaces)
        return .success(RunRequest(title: trimmed?.isEmpty == false ? trimmed : nil, command: Array(rest)))
    }
}

public struct RunUsageError: Error, Equatable {
    public var message: String
}

/// Runs a command for `sidefolk run` in the caller's own process context: inherited stdio,
/// environment, working folder, descriptors and process group, so terminal job control and
/// sandboxes behave exactly as if the user had typed the command (T4). Sidefolk only hears about
/// start and end.
public enum CommandRunner {
    static let handledSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP, SIGQUIT]

    /// A started command; `wait()` returns how it ended and stops forwarding signals.
    public struct Running {
        public let pid: pid_t
        fileprivate let sources: [any DispatchSourceSignal]

        public func wait() async -> ChildExit {
            let termination = await PosixSpawn.waitAsync(pid)
            sources.forEach { $0.cancel() }
            return termination
        }
    }

    /// Starts the command with signal forwarding in place.
    public static func start(_ command: [String]) throws -> Running {
        let child = ChildPID()
        // Ignore first so a signal between spawn and the sources being ready can't kill us; the
        // child gets default handling back through POSIX_SPAWN_SETSIGDEF.
        for s in handledSignals { signal(s, SIG_IGN) }
        let sources = handledSignals.map { sig -> any DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler {
                let pid = child.value.load(ordering: .acquiring)
                if pid > 0, shouldForward(sig, foreground: inForeground()) { kill(pid, sig) }
            }
            source.resume()
            return source
        }
        do {
            let pid = try PosixSpawn.run(command[0], arguments: Array(command.dropFirst()), environment: nil, searchPath: true,
                                    options: PosixSpawn.Options(defaultSignals: handledSignals + [SIGPIPE, SIGCHLD]))
            child.value.store(pid, ordering: .releasing)
            return Running(pid: pid, sources: sources)
        } catch {
            sources.forEach { $0.cancel() }
            throw error
        }
    }

    /// Terminal-generated SIGINT/SIGQUIT already reached the child (same foreground process group),
    /// so only forward them when we are not that group; SIGTERM and SIGHUP are aimed at us and
    /// always passed on.
    static func shouldForward(_ signal: Int32, foreground: Bool) -> Bool {
        switch signal {
        case SIGINT, SIGQUIT: !foreground
        default: true
        }
    }

    static func inForeground() -> Bool {
        for fd in [STDIN_FILENO, STDERR_FILENO, STDOUT_FILENO] where isatty(fd) != 0 {
            return tcgetpgrp(fd) == getpgrp()
        }
        return false
    }

    /// Re-raises a child's fatal signal on ourselves so the caller's shell sees the same status.
    public static func exitLike(_ termination: ChildExit) -> Never {
        if case .signaled(let sig) = termination {
            signal(sig, SIG_DFL)
            var set = sigset_t()
            sigemptyset(&set)
            sigaddset(&set, sig)
            sigprocmask(SIG_UNBLOCK, &set, nil)
            kill(getpid(), sig)
        }
        exit(termination.shellStatus)
    }

    /// The command as a person would type it: arguments with spaces or shell characters quoted.
    public static func display(_ argv: [String]) -> String {
        argv.map { arg in
            let plain = !arg.isEmpty && arg.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || "-_./:=@%+,".unicodeScalars.contains($0)
            }
            return plain ? arg : "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}

/// The running child's pid, readable from signal handlers.
private final class ChildPID: Sendable {
    let value = Atomic<Int32>(0)
}
