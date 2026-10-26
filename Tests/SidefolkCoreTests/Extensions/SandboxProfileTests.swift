import Foundation
import Testing
@testable import SidefolkCore

/// SECURITY §3 and §4.7: snapshot of the generated SBPL and its `-D` list.
@Suite struct SandboxProfileTests {
    @Test func snapshotWithEveryKindOfRule() throws {
        let root = try ExtFixtures.tempDir("sbpl")
        defer { ExtensionFiles.removeTree(root.path) }
        let ext = root.appendingPathComponent("ext").path
        let data = root.appendingPathComponent("data").path
        let docs = root.appendingPathComponent("docs").path
        let notes = root.appendingPathComponent("notes").path
        for dir in [ext, data, docs, notes] { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        let profile = try SandboxProfile.make(.init(
            extensionDir: ext, dataDir: data, executable: "/bin/sh", reexec: "/bin/bash", runtime: ["/usr/lib"],
            permissions: ExtensionPermissions(network: true, read: [docs], write: [notes], exec: ["/usr/bin/pmset", "/usr/bin/true"])))

        #expect(profile.text == SandboxProfile.baseRules + """

        ;; interpreter runtime (read-only)
        (allow file-read* file-map-executable
          (subpath (param "RT_0")))

        ;; the extension (read-only) and its data folder (read-write)
        (allow file-read* (subpath (param "EXT_DIR")))
        (allow file-read* file-write* (subpath (param "DATA_DIR")))

        ;; files.read
        (allow file-read*
          (subpath (param "READ_0")))

        ;; files.write
        (allow file-read* file-write*
          (subpath (param "WRITE_0")))

        ;; exec allow-list: the program (+ the binary it re-executes) and the manifest's exec entries
        (allow process-exec
          (literal (param "RUN_EXEC"))
          (literal (param "RUN_EXEC_2"))
          (literal (param "EXEC_0"))
          (literal (param "EXEC_1")))

        ;; new processes (it runs programs; children inherit this sandbox)
        (allow process-fork)

        ;; services the listed programs need
        (allow mach-lookup
          (global-name (param "MACH_0")))

        """ + SandboxProfile.networkRules)

        #expect(profile.arguments == [
            "-D", "RT_0=/usr/lib", "-D", "EXT_DIR=\(ext)", "-D", "DATA_DIR=\(data)", "-D", "READ_0=\(docs)",
            "-D", "WRITE_0=\(notes)", "-D", "RUN_EXEC=/bin/sh", "-D", "RUN_EXEC_2=/bin/bash",
            "-D", "EXEC_0=/usr/bin/pmset", "-D", "EXEC_1=/usr/bin/true", "-D", "MACH_0=com.apple.PowerManagement.control",
        ])
    }

    @Test func minimalProfileHasNoOptionalRules() throws {
        let root = try ExtFixtures.tempDir("sbpl-min")
        defer { ExtensionFiles.removeTree(root.path) }
        let profile = try SandboxProfile.make(.init(extensionDir: root.path, dataDir: root.path, executable: "/bin/sh",
                                                    permissions: ExtensionPermissions()))
        for absent in ["RT_", "READ_", "WRITE_", "EXEC_0", "RUN_EXEC_2", "MACH_", "network-outbound", "system-socket", "process-fork"] {
            #expect(!profile.text.contains(absent), "\(absent)")
        }
        #expect(profile.parameters.map(\.key) == ["EXT_DIR", "DATA_DIR", "RUN_EXEC"])
        // A shell may be allowed to fork for pipelines without listing any program.
        let shell = try SandboxProfile.make(.init(extensionDir: root.path, dataDir: root.path, executable: "/bin/sh",
                                                  permissions: ExtensionPermissions(), allowFork: true))
        #expect(shell.text.contains("(allow process-fork)"))
    }

    @Test func valuesAreRealPathsAndNeverSpliced() throws {
        let root = try ExtFixtures.tempDir("sbpl-real")
        defer { ExtensionFiles.removeTree(root.path) }
        let viaVar = root.path.replacingOccurrences(of: "/private/var/", with: "/var/")
        let hostile = root.appendingPathComponent(#"x") (allow default) (""#).path
        try FileManager.default.createDirectory(atPath: hostile, withIntermediateDirectories: true)
        let profile = try SandboxProfile.make(.init(extensionDir: viaVar, dataDir: hostile, executable: "/bin/sh",
                                                    permissions: ExtensionPermissions()))
        #expect(profile.parameters.first { $0.key == "EXT_DIR" }?.value == root.path)
        #expect(!profile.text.contains("allow default"))
        #expect(!profile.text.contains(root.path))
    }

    /// The hostile value stays inert when sandbox-exec compiles and runs the profile.
    @Test func hostileValueIsInertUnderSandboxExec() async throws {
        let root = try ExtFixtures.tempDir("sbpl-run")
        defer { ExtensionFiles.removeTree(root.path) }
        let hostile = root.appendingPathComponent(#"d") (allow default) (""#)
        try FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
        let profile = try SandboxProfile.make(.init(extensionDir: root.path, dataDir: hostile.path, executable: "/bin/cat",
                                                    permissions: ExtensionPermissions()))
        let file = root.appendingPathComponent("p.sb")
        try Data(profile.text.utf8).write(to: file)
        let secretDir = try ExtFixtures.tempDir("sbpl-secret")
        defer { ExtensionFiles.removeTree(secretDir.path) }
        let secret = secretDir.appendingPathComponent("s.txt")
        try Data("secret".utf8).write(to: secret)
        let process = try ExtensionProcess(spec: ExtensionProcessSpec(
            executable: "/usr/bin/sandbox-exec", arguments: ["-f", file.path] + profile.arguments + ["/bin/cat", secret.path],
            environment: ["PATH": "/usr/bin:/bin"]))
        let lines = OutputCollector()
        try process.start(onOutput: { lines.add($0) }, onExit: { _ in })
        let exit = await process.waitForExit()
        #expect(exit.cause != .exited(0))
        #expect(!lines.text.contains("secret"))
        #expect(process.stderrTail.contains("Operation not permitted"))
    }
}

extension SandboxProfileTests {
    /// `run.command` may be a compiled program inside the extension folder; it must start in its sandbox.
    @Test func compiledProgramInsideTheFolderStarts() async throws {
        let root = try ExtFixtures.tempDir("sbpl-native")
        defer { ExtensionFiles.removeTree(root.path) }
        let ext = root.appendingPathComponent("ext")
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: ext.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        // Copied Apple binaries trip launch constraints, so build a tiny program of our own.
        let program = ext.appendingPathComponent("bin/tool").path
        let source = root.appendingPathComponent("tool.c")
        try Data("#include <stdio.h>\nint main(int c, char **v) { puts(v[1]); return 0; }\n".utf8).write(to: source)
        let cc = Process()
        cc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        cc.arguments = ["clang", "-o", program, source.path]
        try SpawnLock.withLock { try cc.run() }
        cc.waitUntilExit()
        try #require(cc.terminationStatus == 0, "clang isn't available")
        let profile = try SandboxProfile.make(.init(extensionDir: ext.path, dataDir: data.path, executable: program,
                                                    permissions: ExtensionPermissions()))
        let file = root.appendingPathComponent("p.sb")
        try Data(profile.text.utf8).write(to: file)
        let process = try ExtensionProcess(spec: ExtensionProcessSpec(
            executable: "/usr/bin/sandbox-exec", arguments: ["-f", file.path] + profile.arguments + [program, "native ok"],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: data.path))
        let out = OutputCollector()
        try process.start(onOutput: { out.add($0) }, onExit: { _ in })
        // A just-built binary can stall at launch while macOS assesses it; never hang the suite on that.
        let watchdog = Task {
            try await Task.sleep(for: .seconds(20))
            await process.terminate()
        }
        let exit = await process.waitForExit()
        watchdog.cancel()
        #expect(exit.cause == .exited(0), "\(process.stderrTail)")
        #expect(out.lines == ["native ok"])
    }
}

/// Collects process output lines across threads.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ExtensionProcessOutput] = []

    func add(_ o: ExtensionProcessOutput) { lock.withLock { items.append(o) } }
    var outputs: [ExtensionProcessOutput] { lock.withLock { items } }
    var lines: [String] {
        outputs.compactMap { if case .line(let d) = $0 { return String(decoding: d, as: UTF8.self) } else { return nil } }
    }
    var text: String { lines.joined(separator: "\n") }
}
