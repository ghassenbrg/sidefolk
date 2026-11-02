import Foundation
import Synchronization

/// The surface channel (D99): `sidefolk/surface.open`, `surface.move` and `surface.close`, not tool calls, because a move a second
/// would put a row in History and the Guard in front of every click: a reply within 2 s, at most 64 KB, at most 20 moves a
/// second, only for the one surface open in its place. A move can only change the extension's own state; anything that
/// acts on the world stays a tool, behind Guard.
extension ExtensionHost {
    public static let surfaceReplySeconds: TimeInterval = 2
    public static let surfaceMovesPerSecond = 20

    /// A session id the extension chose: up to 64 letters, digits, `_` and `-`.
    static func sessionId(_ s: String) -> String? {
        s.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? s : nil
    }

    /// Opens a surface, ending what was open in its place: one panel, one overlay.
    public func openSurface(_ info: SurfaceInfo, language: String, arguments: [String: JSONValue] = [:]) async throws -> (session: String, scene: SurfaceScene) {
        let opening = (surfaceOpenings[info.presentation] ?? 0) + 1
        surfaceOpenings[info.presentation] = opening
        if let open = openSurfaces[info.presentation] { await closeSurface(info: open.info, session: open.session, reason: .closed) }
        let (client, name) = try await surfaceClient(info)
        begin(info.extensionId)
        defer { end(info.extensionId) }
        let reply = try await askSurface(client, "sidefolk/surface.open",
                                         ["surface": .string(info.surface), "language": .string(language), "arguments": .object(arguments)], name: name)
        guard let session = reply["session"]?.stringValue.flatMap(Self.sessionId) else { throw UserFacingError(verbatim: Self.surfaceNoAnswer(name)) }
        // Another opening started in this place while the program thought, or the extension went: this one isn't wanted, and
        // the program hears so rather than holding a session nothing will ever close.
        guard surfaceOpenings[info.presentation] == opening else {
            _ = try? await askSurface(client, "sidefolk/surface.close", ["surface": .string(info.surface), "session": .string(session), "reason": .string(SurfaceCloseReason.closed.rawValue)], name: name)
            throw UserFacingError("That has closed.")
        }
        let scene = try scene(reply, info: info, name: name)
        openSurfaces[info.presentation] = OpenSurface(info: info, session: session)
        return (session, scene)
    }

    /// The person's move, sent only while that session is open, at most 20 a second. Past that it is dropped, and nil says so: a
    /// key held down must not end what is on screen.
    public func moveSurface(info: SurfaceInfo, session: String, move: SurfaceMove, now: Date = Date()) async throws -> SurfaceScene? {
        guard var open = openSurfaces[info.presentation], open.info.id == info.id, open.session == session else { throw UserFacingError("That has closed.") }
        guard open.allow(at: now) else { return nil }
        openSurfaces[info.presentation] = open
        let (client, name) = try await surfaceClient(info)
        begin(info.extensionId)
        defer { end(info.extensionId) }
        let reply = try await askSurface(client, "sidefolk/surface.move",
                                         ["surface": .string(info.surface), "session": .string(session), "move": move.json], name: name)
        return try scene(reply, info: info, name: name)
    }

    /// The extension hears it once; nothing comes back.
    public func closeSurface(info: SurfaceInfo, session: String, reason: SurfaceCloseReason) async {
        guard let open = openSurfaces[info.presentation], open.info.id == info.id, open.session == session else { return }
        openSurfaces[info.presentation] = nil
        guard reason != .removed, let (client, name) = try? await surfaceClient(info) else { return }
        begin(info.extensionId)
        defer { end(info.extensionId) }
        _ = try? await askSurface(client, "sidefolk/surface.close",
                                  ["surface": .string(info.surface), "session": .string(session), "reason": .string(reason.rawValue)], name: name)
    }

    /// The extension is going: nothing of it stays open, and it isn't asked anything more.
    func forgetSurfaces(of id: String) async {
        for place in SurfaceInfo.Presentation.allCases {
            // One still being opened counts too.
            surfaceOpenings[place, default: 0] += 1
        }
        // What is kept, or still opening, on the app's side goes as well, whether or not this side has a session.
        for (place, open) in openSurfaces where open.info.extensionId == id { openSurfaces[place] = nil }
        events.publish(.surfaceGone(extensionId: id))
    }

    // MARK: The frame's speaker

    /// Whether this surface's sounds are on. `key` is a switch among its settings (`speaker_setting`, or a scene's `speaker`); without
    /// one the host keeps the choice for the surface. Off until the person says so.
    public func surfaceSpeaker(_ info: SurfaceInfo, key: String?) -> Bool {
        guard let rt = runtimes[info.extensionId] else { return false }
        if let key, let setting = rt.manifest?.settings.first(where: { $0.key == key && $0.type == .switch }), let m = rt.manifest {
            return rt.preferences.resolved(m.settings)[setting.key]?.boolValue ?? false
        }
        return rt.preferences.speakers[info.surface] ?? false
    }

    /// The person's click on the speaker. A declared setting goes through the tool every setting goes through, so History has it
    /// and the program hears it; the plain choice is only the host's.
    public func setSurfaceSpeaker(_ info: SurfaceInfo, key: String?, on: Bool) async {
        if let key, let run = configuration.runTool, runtimes[info.extensionId]?.manifest?.settings.contains(where: { $0.key == key && $0.type == .switch }) == true {
            _ = await run(ExtensionSettingTool.name, ["extension": .string(info.extensionId), "key": .string(key), "value": .bool(on)], .user, 10)
            return
        }
        await updatePreferences(info.extensionId) { $0.speakers[info.surface] = on }
    }

    private func askSurface(_ client: MCPClient, _ method: String, _ params: [String: JSONValue], name: String) async throws -> JSONValue {
        do {
            return try await client.request(method, params: .object(params), timeout: Self.surfaceReplySeconds)
        } catch is MCPError {
            throw UserFacingError(verbatim: Self.surfaceNoAnswer(name))
        }
    }

    private func scene(_ reply: JSONValue, info: SurfaceInfo, name: String) throws -> SurfaceScene {
        guard reply.jsonString.utf8.count <= SurfaceScene.maxBytes + 64, let scene = reply["scene"] else { throw UserFacingError(verbatim: Self.surfaceNoAnswer(name)) }
        return try SurfaceScene.parse(scene, assets: assetReader(extensionId: info.extensionId), within: SceneSize(width: info.width, height: info.height))
    }

    public static func surfaceNoAnswer(_ name: String) -> String {
        String(localized: "\(name) didn't answer, so this closed.", comment: "An extension's surface stopped answering; the name is the extension's")
    }
}

/// What the host keeps of an open surface, and when its last moves came.
struct OpenSurface: Sendable {
    let info: SurfaceInfo
    let session: String
    private var moves: [Date] = []

    init(info: SurfaceInfo, session: String) {
        self.info = info
        self.session = session
    }

    mutating func allow(at now: Date) -> Bool {
        moves = moves.filter { now.timeIntervalSince($0) < 1 }
        guard moves.count < ExtensionHost.surfaceMovesPerSecond else { return false }
        moves.append(now)
        return true
    }
}

/// An open surface's one line to its extension: it hears only moves the scene on screen offered, and the app's code can't
/// send any other, whatever a bug or a timer tries.
public final class SurfaceSession: Sendable {
    public let info: SurfaceInfo
    /// Nil only for a sample with no extension behind it (the UI snapshots).
    private let host: ExtensionHost?
    private struct State {
        var session: String?
        var scene: SurfaceScene?
        var opensAt = Date.distantPast
    }
    private let state = Mutex(State())
    private let reduceMotion: Bool

    public init(info: SurfaceInfo, host: ExtensionHost?, reduceMotion: Bool) {
        self.info = info
        self.host = host
        self.reduceMotion = reduceMotion
    }

    public func open(language: String, arguments: [String: JSONValue] = [:]) async throws -> SurfaceScene {
        guard let host else { throw UserFacingError("That has closed.") }
        let (session, scene) = try await host.openSurface(info, language: language, arguments: arguments)
        state.withLock {
            $0.session = session
            $0.scene = scene
            $0.opensAt = Date().addingTimeInterval(scene.inputOpens(reduceMotion: reduceMotion))
        }
        return scene
    }

    /// Nil when the scene on screen didn't offer the move: nothing is sent.
    public func move(_ move: SurfaceMove, now: Date = Date()) async throws -> SurfaceScene? {
        guard let id = state.withLock({ s -> String? in
            guard let scene = s.scene, move.offered(by: scene, inputOpen: now >= s.opensAt) else { return nil }
            return s.session
        }), let host else { return nil }
        guard let scene = try await host.moveSurface(info: info, session: id, move: move, now: now) else { return nil }
        state.withLock {
            $0.scene = scene
            $0.opensAt = Date().addingTimeInterval(scene.inputOpens(reduceMotion: reduceMotion))
        }
        return scene
    }

    public func close(_ reason: SurfaceCloseReason) async {
        guard let id = state.withLock({ s -> String? in defer { s.session = nil }; return s.session }) else { return }
        await host?.closeSurface(info: info, session: id, reason: reason)
    }

    /// Whether moves are open now, for the panel's own check before it shows a press.
    public func inputOpen(now: Date = Date()) -> Bool { state.withLock { now >= $0.opensAt } }

    /// A run carried on from the last scene holds moves only for what is left of it: told by the panel, which knows.
    public func holdInput(until: Date) { state.withLock { $0.opensAt = until } }
}
