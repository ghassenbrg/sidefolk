import Darwin
import Foundation
import SidefolkCore

// The `sidefolk` helper: an MCP bridge for other agents, `run` for long commands, `hook` for
// Claude Code, `status`. The logic lives in SidefolkCore (HelperCommands) where it is tested.

let arguments = Array(CommandLine.arguments.dropFirst())
let paths = SidefolkPaths.standard()

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("sidefolk: \(message)\n\n\(HelperCommands.usage)\n".utf8))
    exit(code)
}

switch arguments.first {
case "mcp":
    // A client that goes away must end us quietly, not with SIGPIPE.
    signal(SIGPIPE, SIG_IGN)
    exit(await HelperCommands.mcp(paths: paths))

case "run":
    // No SIGPIPE change here: the child would inherit an ignored SIGPIPE.
    switch RunRequest.parse(Array(arguments.dropFirst())) {
    case .failure(let usage):
        fail(usage.message)
    case .success(let request):
        do {
            CommandRunner.exitLike(try await HelperCommands.run(request, paths: paths))
        } catch {
            FileHandle.standardError.write(Data("sidefolk: \(error)\n".utf8))
            exit(127)
        }
    }

case "hook":
    // Fail open: whatever happens, Claude Code gets exit 0 and no output within the budget.
    signal(SIGPIPE, SIG_IGN)
    DispatchQueue.global().asyncAfter(deadline: .now() + HookForwarder.budget) { exit(0) }
    if arguments.count >= 2 {
        await HookForwarder.run(event: arguments[1], socketPath: paths.socket.path)
    }
    exit(0)

case "status":
    signal(SIGPIPE, SIG_IGN)
    let (text, running) = await HelperCommands.status(paths: paths)
    print(text)
    exit(running ? 0 : 1)

case "ext":
    guard arguments.count == 3, arguments[1] == "validate" else { fail("usage: sidefolk ext validate <folder>") }
    let folder = URL(fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath, isDirectory: true)
    let report = ExtensionValidator.validate(at: folder, paths: paths)
    print(report.text)
    exit(report.isValid ? 0 : 1)

case "--version", "version":
    print("sidefolk \(SidefolkVersion.current)")

case "help", "--help", "-h":
    print(HelperCommands.usage)

case nil:
    fail("say what to do.")

case let other?:
    fail("unknown command \(other).")
}
