import Foundation
import Testing
@testable import SidefolkCore

struct ExtensionKitProtocolTests {
    @Test func noticesAreDeliveredWhileARequestIsAwaiting() throws {
        let dir = try ExtFixtures.tempDir("kit-notices")
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = dir.appendingPathComponent("main.swift")
        let binary = dir.appendingPathComponent("probe")
        let source = #"""
        import Foundation
        let ext = Extension(name: "probe")
        var sawNotice = false
        ext.on("probe/notice") { _ in sawNotice = true }
        ext.tool("wait", "Wait", "Waits briefly.") { _ in
            ext.send("probe/started")
            try await Task.sleep(for: .milliseconds(300))
            return sawNotice ? "notice arrived" : "notice was late"
        }
        await ext.serve()
        """#
        try Data(source.utf8).write(to: main)
        let kit = ExtFixtures.repoRoot.appendingPathComponent("extensions/Kit")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        // The whole Kit, as an extension's package builds it: its files depend on each other.
        let kitFiles = try FileManager.default.contentsOfDirectory(at: kit, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
        compiler.arguments = kitFiles + [main.path, "-o", binary.path]
        compiler.standardOutput = FileHandle.nullDevice
        compiler.standardError = FileHandle.nullDevice
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        guard compiler.terminationStatus == 0 else { return }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = binary
        process.standardInput = input; process.standardOutput = output
        try process.run()
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wait","arguments":{}}}"# + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(call.utf8))
        let started = output.fileHandleForReading.availableData
        #expect(String(decoding: started, as: UTF8.self).contains("probe/started"))
        let notice = #"{"jsonrpc":"2.0","method":"probe/notice","params":{}}"# + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(notice.utf8))
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: result, as: UTF8.self).contains("notice arrived"))
    }
}
