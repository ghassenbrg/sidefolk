import Foundation
import Testing
@testable import SidefolkCore

/// A Mac without Apple's developer tools has no python3 and no git, only the /usr/bin shims, and running a shim
/// (or `xcrun`) there pops Apple's "install the command line developer tools" dialog. Before the 0.1.0 review
/// Sidefolk ran `xcrun --find python3` at every launch. Now nothing is run to find a program, and the seed packs (D98)
/// are programs of their own: every one runs there.
@Suite struct NoDeveloperToolsTests {
    /// Resolvers for a clean Mac: nothing in any developer folder, Homebrew or python.org.
    static func cleanMac(_ config: inout ExtensionHost.Configuration) {
        config.resolver = InterpreterResolver { name in InterpreterResolver.candidates(name, developer: []).filter { $0 == "/bin/sh" } }
        config.programs = ProgramResolver { _ in [] }
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func onACleanMacEverySeedRuns() async throws {
        let h = try HostEnv(configure: Self.cleanMac)
        let seeds = ["world-clock", "system-vitals", "weather", "calculator"]
        for seed in seeds { try await h.host.install(from: ExtFixtures.builtIn(seed), origin: .official) }
        #expect(Set(await h.host.extensions().map(\.id)) == Set(seeds.map { "dev.sidefolk.\($0)" }))
        // And they work there: the time answers with nothing found on the Mac.
        #expect(await h.call("ext.world-clock.current_time", ["places": ["UTC"]]).okText?.contains("in UTC (UTC+0)") == true)
        await h.host.shutdown()
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
