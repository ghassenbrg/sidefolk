import Foundation
import Testing
@testable import SidefolkCore

/// A Mac without Apple's developer tools has no python3 and no git, only the /usr/bin shims, and running a shim
/// (or `xcrun`) there pops Apple's "install the command line developer tools" dialog. Before the 0.1.0 review
/// Sidefolk ran `xcrun --find python3` at every launch. Now nothing is run to find a program; the built-ins are
/// programs of their own, so on such a Mac only Git is missing something, and it says what and how to get it.
@Suite struct NoDeveloperToolsTests {
    /// Resolvers for a clean Mac: nothing in any developer folder, Homebrew or python.org.
    static func cleanMac(_ config: inout ExtensionHost.Configuration) {
        config.resolver = InterpreterResolver { name in InterpreterResolver.candidates(name, developer: []).filter { $0 == "/bin/sh" } }
        config.programs = ProgramResolver { _ in [] }
    }

    @Test func onACleanMacOnlyGitWaitsForSomething() async throws {
        let h = try HostEnv(configure: Self.cleanMac)
        let bundled = BundledExtensions(directory: ExtFixtures.builtIns)
        let shipped = bundled.entries()
        #expect(shipped.count >= 13)
        await bundled.install(into: h.host)

        #expect(bundled.unavailable.map(\.id) == ["dev.sidefolk.git"], "the founder's \"Git needs Python\" is gone")
        #expect(bundled.unavailable.first?.message == "Git needs Git, which isn't on this Mac. Apple's Command Line Tools include it: "
            + "open Terminal, type xcode-select --install, then restart Sidefolk.")
        let installed = await h.host.extensions()
        #expect(Set(installed.map(\.id)) == Set(shipped.map(\.id)).subtracting(["dev.sidefolk.git"]))
        // And they work there: World Clock answers with nothing found on the Mac.
        #expect(await h.call("ext.world-clock.current_time", ["places": ["UTC"]]).okText?.contains("in UTC (UTC+0)") == true)
        await h.host.shutdown()
    }

    @Test func gitAloneMissingIsNamed() {
        #expect(BundledExtensions.missing("git", for: "Git").hasPrefix("Git needs Git, which isn't on this Mac."))
    }

    /// The candidates are fixed paths read with `realpath`; the shim is never one of them.
    @Test func findingPythonRunsNothing() {
        let candidates = InterpreterResolver.candidates("python3", developer: ["/Library/Developer/CommandLineTools"])
        #expect(candidates.first == "/Library/Developer/CommandLineTools/usr/bin/python3")
        #expect(!candidates.contains("/usr/bin/python3"))
        #expect(!ProgramResolver.developerFolders().contains("/usr"))
    }

    /// Apple's Python is found in the selected developer folder, as git is.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func pythonInADeveloperFolderIsFound() throws {
        let real = try #require(ExtFixtures.python?.path)
        let developer = try ExtFixtures.tempDir("devtools")
        defer { try? FileManager.default.removeItem(at: developer) }
        try FileManager.default.createDirectory(at: developer.appendingPathComponent("usr/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: developer.appendingPathComponent("usr/bin/python3").path, withDestinationPath: real)
        let resolver = InterpreterResolver { InterpreterResolver.candidates($0, developer: [developer.path]) }
        #expect(resolver.resolve("python3")?.path == real)
    }
}
