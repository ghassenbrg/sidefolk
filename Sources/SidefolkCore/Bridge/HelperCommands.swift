import Darwin
import Foundation

/// What the `sidefolk` helper binary does for each subcommand. Lives in Core so it is testable;
/// `Sources/sidefolk/main.swift` only parses argv and exits.
public enum HelperCommands {
    public static let usage = """
        Usage:
          sidefolk mcp                              MCP server on stdio for Claude Code, Codex or any MCP client
          sidefolk run [--title "..."] -- <cmd> …   run a command; Sidefolk tells you when it ends
          sidefolk hook <EventName>                 for Claude Code command hooks (reads the payload on stdin)
          sidefolk status                           is Sidefolk running, and what it keeps track of
          sidefolk ext validate <folder>            check an extension before installing it
          sidefolk --version
        """

    /// `sidefolk mcp`. A brain run's token is read from `$SIDEFOLK_RUN_DIR/token` when set.
    public static func mcp(paths: SidefolkPaths, environment: [String: String] = ProcessInfo.processInfo.environment) async -> Int32 {
        let token: String?
        do {
            token = try SocketConnector.brainToken(environment: environment)
        } catch {
            FileHandle.standardError.write(Data("sidefolk mcp: \(error)\n".utf8))
            return 1
        }
        await MCPStdioBridge(connector: SocketConnector(socketPath: paths.socket.path, token: token)).run()
        return 0
    }

    /// `sidefolk run`: starts the command first (the app is never in its way), reports start and
    /// end to the app if it is running, and returns how the command ended.
    public static func run(_ request: RunRequest, paths: SidefolkPaths) async throws -> ChildExit {
        let started = ContinuousClock.now
        let cwd = FileManager.default.currentDirectoryPath
        let report = JobReport(title: request.displayTitle, command: CommandRunner.display(request.command).clipped(500), cwd: cwd)
        let socket = paths.socket.path
        let tee = StderrTee.make()
        let running: CommandRunner.Running
        do {
            running = try CommandRunner.start(request.command, stderr: tee?.childEnd)
        } catch {
            tee?.childStarted()
            _ = tee?.finish(within: 0)
            throw error
        }
        tee?.childStarted()
        var start = report
        start.pid = Int(running.pid)
        let startJSON = start.json
        let reported = Task<String?, Never> {
            do {
                return try await send(.jobStart, startJSON, socket: socket, timeout: 1.5).string("id")
            } catch {
                FileHandle.standardError.write(Data("sidefolk: Sidefolk isn't running, so you won't get a notice when this ends.\n".utf8))
                return nil
            }
        }
        let termination = await running.wait()
        let id = await reported.value
        var finish = start
        finish.id = id
        let elapsed = ContinuousClock.now - started
        finish.durationSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let errorOutput = tee?.finish() ?? ""
        switch termination {
        case .exited(let code):
            finish.exitCode = Int(code)
            // Only a failure says what it printed: that is what the notice needs, and nothing more leaves the terminal.
            let lines = StderrTee.lastLines(errorOutput)
            if code != 0, !lines.isEmpty { finish.errorTail = lines.joined(separator: "\n") }
        case .signaled(let signal): finish.signal = Int(signal)
        }
        // The app may have started while the command ran; a finish without an id still counts.
        _ = try? await send(.jobFinish, finish.json, socket: socket, timeout: 1.5)
        return termination
    }

    /// `sidefolk status`: one line for people, and whether the app is running.
    public static func status(paths: SidefolkPaths) async -> (text: String, running: Bool) {
        do {
            let reply = try await send(.status, .object([:]), socket: paths.socket.path, timeout: 3)
            let s = StatusSnapshot(json: reply)
            return ("Sidefolk \(s.appVersion) is running: \(s.sentence).", true)
        } catch BridgeError.notRunning {
            return ("Sidefolk isn't running.", false)
        } catch {
            return ("Sidefolk isn't reachable: \(error)", false)
        }
    }

    /// One request on a fresh connection.
    static func send(_ method: BridgeProtocol.Method, _ params: JSONValue, socket: String, timeout: TimeInterval) async throws -> JSONValue {
        let client = try await BridgeClient.connect(socketPath: socket, client: "sidefolk-cli", timeout: timeout)
        defer { client.close() }
        return try await client.call(method.rawValue, params, timeout: timeout)
    }
}
