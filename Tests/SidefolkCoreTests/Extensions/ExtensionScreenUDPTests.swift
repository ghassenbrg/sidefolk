import Foundation
import Testing
@testable import SidefolkCore

/// The screen and UDP permissions (D69), for an extension that mirrors the Mac to a TV: what the manifest says, what
/// the install sheet says, and that the sandbox opens exactly that. Nothing here records the screen: that asks
/// macOS, for Sidefolk, and is checked by hand in the debug app.
struct ExtensionScreenUDPTests {
    @Test func theManifestAndTheSheetSayIt() throws {
        let m = try ExtensionManifest.decode(Data("""
            {"id": "dev.example.tv", "name": "TV", "version": "1.0", "run": {"command": "bin/x"},
             "permissions": {"network": true, "screen": true, "udp": true, "media": true}}
            """.utf8))
        #expect(m.permissions.screen && m.permissions.udp)

        let summary = PermissionSummary.forExtension(ExtensionPermissions(network: true, media: true, screen: true, udp: true))
        let kinds = summary.lines.map(\.kind)
        #expect(kinds.contains(.screen) && kinds.contains(.udp))
        #expect(summary.lines.filter { $0.kind == .screen || $0.kind == .udp }.allSatisfy { $0.caution })
        #expect(summary.lines.first { $0.kind == .screen }?.text.contains("Screen Recording") == true, "macOS asks too, and says so")
        #expect(summary.warnings.contains { $0.contains("what's on your screen") }, "the screen and the internet together")
        #expect(ExtensionPermissions(screen: true).raisesRiskFloor, "what's on screen is the person's alone")
    }

    /// The sandbox can't keep a network extension to the local network (measured: an address in a rule must be `*` or
    /// localhost), so a purpose never replaces "the internet": it's added, as the extension's own words.
    @Test func aNetworkPurposeAddsToTheLineAndNeverHidesTheInternet() throws {
        let m = try ExtensionManifest.decode(Data("""
            {"id": "dev.example.tv", "name": "TV", "version": "1.0", "run": {"command": "bin/x"},
             "permissions": {"network": true, "network_purpose": "to find TVs on your local network and stream to them"}}
            """.utf8))
        var issues: [ValidationIssue] = []
        var warnings: [String] = []
        let validator = ManifestValidator(paths: SidefolkPaths(home: try ExtFixtures.tempDir("np-home")))
        let granted = validator.checkPermissions(m.permissions, folder: try ExtFixtures.tempDir("np-ext").path, issues: &issues, warnings: &warnings)
        #expect(issues.isEmpty)
        let line = try #require(PermissionSummary.forExtension(granted).lines.first { $0.kind == .network })
        #expect(line.text == "Can use the network, the internet included. It says it uses it to find TVs on your local network and stream to them.")
        #expect(line.caution)

        for bad in [#"{"network_purpose": "to stream"}"#, #"{"network": true, "network_purpose": "Only local!"}"#,
                     #"{"network": true, "network_purpose": "to a\nb"}"#] {
            let p = try ExtensionManifest.decode(Data(#"{"id": "dev.example.tv", "name": "TV", "version": "1.0", "run": {"command": "bin/x"}, "permissions": "#
                                                      .utf8) + Data(bad.utf8) + Data("}".utf8)).permissions
            var found: [ValidationIssue] = []
            let g = validator.checkPermissions(p, folder: try ExtFixtures.tempDir("np-ext").path, issues: &found, warnings: &warnings)
            #expect(found.map(\.field).contains("permissions.network_purpose") && g.networkPurpose == nil, "\(bad)")
        }
    }

    /// Why the sheet can't say "local network only": macOS's sandbox refuses a rule naming any host but `*` or localhost,
    /// so a private range can't be allowed alone. If that ever changes, this fails, and a local-only permission can follow.
    @Test func theSandboxCantFenceOffTheInternet() async throws {
        let root = try ExtFixtures.tempDir("sb-lan")
        defer { ExtensionFiles.removeTree(root.path) }
        let file = root.appendingPathComponent("p.sb")
        try Data("(version 1)\n(allow default)\n(deny network-outbound)\n(allow network-outbound (remote ip \"192.168.0.0/16:*\"))\n".utf8).write(to: file)
        let process = try ExtensionProcess(spec: ExtensionProcessSpec(executable: "/usr/bin/sandbox-exec", arguments: ["-f", file.path, "/usr/bin/true"],
                                                                      environment: ["PATH": "/usr/bin:/bin"]))
        try process.start(onOutput: { _ in }, onExit: { _ in })
        let exit = await process.waitForExit()
        #expect(exit.cause != .exited(0), "a private range compiled: a local-network-only permission may now be possible")
        #expect(process.stderrTail.contains("host must be * or localhost"), "\(process.stderrTail)")
    }

    @Test func udpNeedsTheNetwork() throws {
        let m = try ExtensionManifest.decode(Data("""
            {"id": "dev.example.tv", "name": "TV", "version": "1.0", "run": {"command": "bin/x"}, "permissions": {"udp": true}}
            """.utf8))
        var issues: [ValidationIssue] = []
        var warnings: [String] = []
        let validator = ManifestValidator(paths: SidefolkPaths(home: try ExtFixtures.tempDir("udp-home")))
        let granted = validator.checkPermissions(m.permissions, folder: try ExtFixtures.tempDir("udp-ext").path, issues: &issues,
                                                 warnings: &warnings)
        #expect(issues.map(\.field) == ["permissions.udp"])
        #expect(!granted.udp, "never granted alone, even if the sheet were skipped")
    }

    @Test func theSandboxOpensOnlyWhatWasGranted() throws {
        let dir = try ExtFixtures.tempDir("scr-sb")
        func profile(_ p: ExtensionPermissions) throws -> String {
            try SandboxProfile.make(.init(extensionDir: dir.path, dataDir: dir.path, executable: "/usr/bin/true", permissions: p)).text
        }
        let none = try profile(ExtensionPermissions(network: true))
        for absent in ["replayd", "windowserver", "videoencoder", "network-bind", "network-inbound"] {
            #expect(!none.contains(absent), "\(absent)")
        }
        let screen = try profile(ExtensionPermissions(screen: true))
        #expect(screen.contains("com.apple.replayd") && screen.contains("com.apple.windowserver.active")
                && screen.contains("com.apple.coremedia.videoencoder"))
        for never in ["launchservicesd", "pasteboard", "com.apple.dock", "tccd"] {
            #expect(!screen.contains(never), "screen never opens \(never)")
        }
        let udp = try profile(ExtensionPermissions(network: true, udp: true))
        #expect(udp.contains(#"(allow network-bind (local udp "*:*"))"#) && udp.contains(#"(allow network-inbound (local udp "*:*"))"#))
        #expect(!udp.contains("(local tcp"), "no listening server")
        #expect(!(try profile(ExtensionPermissions(udp: true))).contains("network-bind"), "UDP only comes with the network")
    }

    /// Measured, not assumed: `network` alone refuses a UDP port of one's own; `udp` lets a packet come back to it.
    @Test func aUDPPortOpensOnlyWithTheUDPPermission() async throws {
        let root = try ExtFixtures.tempDir("sb-udp")
        defer { ExtensionFiles.removeTree(root.path) }
        let ext = root.appendingPathComponent("ext")
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: ext.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let program = ext.appendingPathComponent("bin/udp").path
        let source = root.appendingPathComponent("udp.c")
        try Data(Self.echo.utf8).write(to: source)
        let cc = Process()
        cc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        cc.arguments = ["clang", "-o", program, source.path]
        try SpawnLock.withLock { try cc.run() }
        cc.waitUntilExit()
        try #require(cc.terminationStatus == 0, "clang isn't available")

        func run(_ permissions: ExtensionPermissions) async throws -> String {
            let profile = try SandboxProfile.make(.init(extensionDir: ext.path, dataDir: data.path, executable: program, permissions: permissions))
            let file = root.appendingPathComponent("p.sb")
            try Data(profile.text.utf8).write(to: file)
            let process = try ExtensionProcess(spec: ExtensionProcessSpec(
                executable: "/usr/bin/sandbox-exec", arguments: ["-f", file.path] + profile.arguments + [program],
                environment: ["PATH": "/usr/bin:/bin"], workingDirectory: data.path))
            let out = OutputCollector()
            try process.start(onOutput: { out.add($0) }, onExit: { _ in })
            let watchdog = Task {
                try await Task.sleep(for: .seconds(20))
                await process.terminate()
            }
            _ = await process.waitForExit()
            watchdog.cancel()
            return out.text
        }
        #expect(try await run(ExtensionPermissions(network: true)) == "bind refused")
        #expect(try await run(ExtensionPermissions(network: true, udp: true)) == "udp ok")
    }

    /// Binds a UDP port on loopback, sends itself a packet, and says what happened.
    static let echo = """
    #include <stdio.h>
    #include <string.h>
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <sys/time.h>
    int main(void) {
        int s = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_len = sizeof a;
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof a) != 0) { puts("bind refused"); return 1; }
        socklen_t n = sizeof a; getsockname(s, (struct sockaddr *)&a, &n);
        struct timeval t = {2, 0}; setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
        if (sendto(s, "hi", 2, 0, (struct sockaddr *)&a, sizeof a) != 2) { puts("send refused"); return 1; }
        char b[8]; puts(recv(s, b, sizeof b, 0) == 2 ? "udp ok" : "receive refused");
        return 0;
    }
    """

    /// The gallery's Miraya in this host's sandbox, with no TV around: WebRTC loads from its lib/, it starts and keeps
    /// running, its page says only what is true, and a link that isn't HTTPS is refused before anything is sent.
    @Test(.enabled(if: ExtFixtures.addonFolders.contains("miraya"), ExtFixtures.noAddons))
    func mirayaStartsInItsSandbox() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("miraya"))
        #expect(info.tools.allSatisfy { $0.risk != .low }, "the network raises every tool to medium")
        let page = try await h.host.renderPage(extensionId: info.id, page: "miraya")
        #expect(page.summary?.title.hasPrefix("Miraya") == true, "\(String(describing: page.summary))")
        let status = try #require(await h.call("ext.miraya.tv_status").okText)
        #expect(status.hasPrefix("Miraya"), "\(status)")
        let plain = await h.call("ext.miraya.play_on_tv", ["url": "http://example.com/film.mp4"])
        guard case .ok(let refused) = plain.status else { Issue.record("\(plain.status)"); return }
        #expect(refused.isError && refused.text.contains("https://"), "\(refused.text)")
        let stop = await h.call("ext.miraya.stop")
        #expect(stop.okText == "Nothing is on the TV from this Mac.", "\(stop.status)")
        await h.host.shutdown()
    }
}
