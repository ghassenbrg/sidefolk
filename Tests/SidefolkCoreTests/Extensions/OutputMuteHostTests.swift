import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// The fixture's guardian writes files instead of touching the Mac's sound device.
struct OutputMuteHostTests {
    static let fixture = #"""
    import json, os, sys
    reply = None
    sequence = 0
    def send(o):
        print(json.dumps(o), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        method = m.get('method', '')
        if method == 'sidefolk/output_mute.result':
            reply = m.get('params')
            continue
        if 'id' not in m: continue
        if method == 'initialize':
            r = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'probe', 'version': '1'}}
        elif method == 'tools/list':
            r = {'tools': [{'name': 'route', 'description': 'Request audio routing.', 'inputSchema': {'type': 'object'}},
                           {'name': 'status', 'description': 'Read response.', 'inputSchema': {'type': 'object'}},
                           {'name': 'crash', 'description': 'Exit abruptly.', 'inputSchema': {'type': 'object'}}]}
        elif method == 'tools/call':
            name = m['params']['name']
            if name == 'crash': os._exit(3)
            if name == 'route':
                sequence += 1
                reply = None
                send({'jsonrpc': '2.0', 'method': 'sidefolk/output_mute', 'params': {'request': '9bda16b9-3696-4c9a-afb3-634aa9ff865d', 'enabled': True, 'sequence': sequence}})
                text = 'sent'
            else:
                text = json.dumps(reply)
            r = {'content': [{'type': 'text', 'text': text}]}
        else: r = {}
        send({'jsonrpc': '2.0', 'id': m['id'], 'result': r})
    """#

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func permissionIsRequiredAndDisablingRestoresTheLease() async throws {
        let root = try ExtFixtures.tempDir("audio-host")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("guardian")
        let started = root.appendingPathComponent("started")
        let restored = root.appendingPathComponent("restored")
        // These paths are generated temporary names and contain no shell metacharacters.
        let script = "#!/bin/sh\nprintf started > '\(started.path)'\nprintf 'ok\\n'\ncat >/dev/null\nprintf restored > '\(restored.path)'\n"
        try Data(script.utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        for (allowed, hostAllows) in [(false, true), (true, false), (true, true)] {
            try? FileManager.default.removeItem(at: started)
            try? FileManager.default.removeItem(at: restored)
            let h = try HostEnv { $0.outputMuteHelper = helper; $0.allowOutputMute = hostAllows }
            try await h.env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
            let id = "dev.test.audio"
            let manifest = ExtFixtures.manifest(id: id, tools: ["route": ["risk": "medium"], "status": ["risk": "low"], "crash": ["risk": "low"]],
                permissions: ["output_mute": .bool(allowed)], extra: ["background": true])
            let folder = try h.source("audio", manifest: manifest, files: ["server.py": Self.fixture])
            _ = try await h.host.install(from: folder)
            #expect((await h.call("ext.audio.route")).okText == "sent")
            if allowed && hostAllows {
                var response = ""
                for _ in 0..<100 {
                    response = (await h.call("ext.audio.status")).okText ?? ""
                    if response.contains("true") { break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                #expect(response.contains("true"), "the host confirmed the guardian")
                #expect(FileManager.default.fileExists(atPath: started.path))
                try await h.host.setEnabled(false, id: id)
                #expect(FileManager.default.fileExists(atPath: restored.path), "disable waited for recovery")
                try FileManager.default.removeItem(at: restored)
                try await h.host.setEnabled(true, id: id)
                #expect((await h.call("ext.audio.route")).okText == "sent")
                for _ in 0..<100 {
                    if (await h.call("ext.audio.status")).okText?.contains("true") == true { break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                _ = await h.call("ext.audio.crash")
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: restored.path) { break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                #expect(FileManager.default.fileExists(atPath: restored.path), "a crashed extension releases its guardian")
                await h.host.shutdown()
            } else {
                try await Task.sleep(for: .milliseconds(250))
                #expect(!FileManager.default.fileExists(atPath: started.path), "undeclared requests and validation trials never start the helper")
                await h.host.shutdown()
            }
        }
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func repeatedRequestsAreLimitedWithoutBlockingRelease() async throws {
        let root = try ExtFixtures.tempDir("audio-rate")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("guardian")
        let restored = root.appendingPathComponent("restored")
        let script = "#!/bin/sh\nprintf 'ok\\n'\ncat >/dev/null\nprintf restored > '\(restored.path)'\n"
        try Data(script.utf8).write(to: helper)
        #expect(chmod(helper.path, 0o700) == 0)
        let h = try HostEnv { $0.outputMuteHelper = helper }
        try await h.env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let id = "dev.test.audio"
        let manifest = ExtFixtures.manifest(id: id, tools: ["route": ["risk": "medium"], "status": ["risk": "low"], "crash": ["risk": "low"]],
            permissions: ["output_mute": true], extra: ["background": true])
        let folder = try h.source("audio", manifest: manifest, files: ["server.py": Self.fixture])
        _ = try await h.host.install(from: folder)
        for index in 0..<6 {
            #expect((await h.call("ext.audio.route")).okText == "sent")
            var response = ""
            for _ in 0..<100 {
                response = (await h.call("ext.audio.status")).okText ?? ""
                if response != "null" && !response.isEmpty { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(response.contains(index < 5 ? "true" : "Too many"), "request \(index + 1): \(response)")
        }
        try await h.host.setEnabled(false, id: id)
        #expect(FileManager.default.fileExists(atPath: restored.path), "rate limiting never blocks restoration")
        await h.host.shutdown()
    }
}
