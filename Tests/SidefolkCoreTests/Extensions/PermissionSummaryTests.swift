import Foundation
import Testing
@testable import SidefolkCore

@Suite struct PermissionSummaryTests {
    let home = FolderAccess.canonical(NSHomeDirectory())!

    @Test func nothingGranted() {
        let s = PermissionSummary.forExtension(ExtensionPermissions())
        #expect(s.texts == ["No access to your files or the internet"])
        #expect(s.warnings.isEmpty)
        #expect(s.sandboxed)
    }

    @Test func plainLanguageLines() {
        let p = ExtensionPermissions(network: true, read: [home + "/Documents"], write: [home + "/Notes"], exec: ["/usr/bin/pmset"])
        let s = PermissionSummary.forExtension(p)
        #expect(s.texts == ["Can use the internet", "Can read ~/Documents", "Can read and change files in ~/Notes", "Can run /usr/bin/pmset"])
        #expect(s.lines.first?.caution == true)
    }

    @Test func dangerousCombinationsAreNamed() {
        let upload = PermissionSummary.forExtension(ExtensionPermissions(network: true, read: [home + "/Documents"]))
        #expect(upload.warnings == ["It can read ~/Documents and use the internet, so it could upload those files."])

        let shell = PermissionSummary.forExtension(ExtensionPermissions(exec: ["/bin/sh"]))
        #expect(shell.texts.first == "Can run /bin/sh, which can run anything")
        #expect(shell.warnings == ["It can run /bin/sh, which can run any code its sandbox allows."])

        let fetchAndRun = PermissionSummary.forExtension(ExtensionPermissions(network: true, exec: ["/usr/bin/python3"]))
        #expect(fetchAndRun.warnings.contains("It can use the internet and run /usr/bin/python3, so it could download and run other code."))

        let save = PermissionSummary.forExtension(ExtensionPermissions(network: true, write: [home + "/Inbox"]))
        #expect(save.warnings.contains("It can save what it downloads into ~/Inbox."))
    }

    @Test func dangerousExecList() {
        let p = ExtensionPermissions(exec: ["/bin/zsh", "/usr/bin/osascript", "/usr/bin/curl", "/opt/homebrew/bin/python3.12",
                                            "/usr/bin/pmset", "/usr/bin/vm_stat"])
        #expect(p.dangerousExec == ["/bin/zsh", "/usr/bin/osascript", "/usr/bin/curl", "/opt/homebrew/bin/python3.12"])
        #expect(p.raisesRiskFloor)
        #expect(!ExtensionPermissions(exec: ["/usr/bin/pmset"]).raisesRiskFloor)
    }

    @Test func mcpServersAreLabelledUnsandboxed() {
        let s = PermissionSummary.forMCPServer(command: "/opt/homebrew/bin/github-mcp", arguments: [])
        #expect(!s.sandboxed)
        #expect(s.lines.map(\.kind) == [.unsandboxed])
        #expect(s.texts.first?.hasPrefix("Runs with your full permissions") == true)
        #expect(s.warnings.isEmpty)
    }

    @Test func unpinnedLaunchersWarn() {
        func warn(_ cmd: String, _ args: [String]) -> String? { PermissionSummary.unpinnedLauncherWarning(command: cmd, arguments: args) }
        #expect(warn("/usr/local/bin/npx", ["-y", "@modelcontextprotocol/server-github"])?.contains("Pin a version") == true)
        #expect(warn("npx", ["-y", "@modelcontextprotocol/server-github@1.2.0"]) == nil)
        #expect(warn("npx", ["some-server"]) != nil)
        #expect(warn("npx", ["some-server@2"]) == nil)
        #expect(warn("uvx", ["mcp-server-time"])?.contains("==1.2.3") == true)
        #expect(warn("uvx", ["mcp-server-time==0.6.2"]) == nil)
        #expect(warn("/usr/bin/node", ["server.js"]) == nil)
    }
}
