import Foundation
import Testing
@testable import SidefolkCore

/// Opt-in integration against a disposable Android TV emulator. The serial must identify an
/// emulator, never a physical device; the caller starts it and forwards a local port first.
struct MirayaEmulatorTests {
    static let serial = ProcessInfo.processInfo.environment["SIDEFOLK_MIRAYA_EMULATOR_SERIAL"]
    static let port = ProcessInfo.processInfo.environment["SIDEFOLK_MIRAYA_EMULATOR_PORT"].flatMap(Int.init)

    static func adb(_ args: [String]) throws -> String {
        let serial = try #require(serial)
        guard serial.hasPrefix("emulator-") else { throw UserFacingError("This test only runs against an emulator.") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/adb")
        process.arguments = ["-s", serial] + args
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UserFacingError("The Android emulator command failed.") }
        return String(decoding: data, as: UTF8.self)
    }

    static func nodes() throws -> [XMLElement] {
        _ = try adb(["shell", "uiautomator", "dump", "/sdcard/sidefolk-test.xml"])
        let xml = try adb(["exec-out", "cat", "/sdcard/sidefolk-test.xml"])
        let document = try XMLDocument(xmlString: xml)
        return try document.nodes(forXPath: "//node").compactMap { $0 as? XMLElement }
    }

    @Test(.enabled(if: serial != nil && port != nil && ExtFixtures.addonFolders.contains("miraya"), "no disposable Miraya TV emulator specified"))
    func pairsWithMatchingCodesThroughTheSandbox() async throws {
        let port = try #require(Self.port)
        let h = try HostEnv { $0.allowOutputMute = false }
        try await h.env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let info = try await h.host.install(from: ExtFixtures.builtIn("miraya"), origin: .official)
        let address = "127.0.0.1:\(port)"
        let pair = await h.call("ext.miraya.pair_tv", ["tv": .string(address)])
        let answer = try #require(pair.okText, "\(pair.status)")
        let page = try await h.host.renderPage(extensionId: info.id, page: "miraya")
        let hero = try #require(page.sections.flatMap(\.blocks).compactMap { if case .hero(let h) = $0 { h } else { nil } }.first)
        let code = try #require(hero.code).filter(\.isNumber)
        #expect(code.count == 6 && answer.contains(code.prefix(3)))
        let nodes = try Self.nodes()
        let shown = nodes.compactMap { $0.attribute(forName: "text")?.stringValue }
            .map { $0.filter(\.isNumber) }.first { $0.count == 6 }
        #expect(shown == code, "the TV and Sidefolk show the same code")
        guard shown == code else { await h.host.shutdown(); return }
        #expect((await h.call("ext.miraya.confirm_pairing")).okText?.contains("Allow") == true)
        var approved = false
        for _ in 0..<8 {
            let list = try Self.nodes()
            if list.contains(where: { $0.attribute(forName: "focused")?.stringValue == "true" &&
                $0.attribute(forName: "text")?.stringValue?.lowercased() == "allow" }) {
                _ = try Self.adb(["shell", "input", "keyevent", "KEYCODE_DPAD_CENTER"])
                approved = true; break
            }
            _ = try Self.adb(["shell", "input", "keyevent", "KEYCODE_DPAD_RIGHT"])
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(approved, "Allow was selected using the emulator's remote")
        var paired: PairedAnswer?
        for _ in 0..<50 {
            paired = await h.host.pairedCheck(info.id, tool: "share_screen", input: ["tv": .string(address)])
            if paired?.paired == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(paired?.paired == true, "the verified TV is saved and recognized")
        await h.host.shutdown()
    }
}
