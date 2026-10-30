import AppKit
import SidefolkCharacter
import WebKit

/// A 3D companion (D51): a transparent WebGL view laid over the companion's 2D rig, which still
/// runs, undrawn, underneath. The rig keeps Sidefolk's states, idle life, clicks, petting and
/// bubble anchors; every cue it hears (`CharacterView.onCue`) is replayed here, where the 3D
/// character acts it out. The page and models live in `Resources/Companions3D`; companions from the add-on
/// gallery (D55) or added from a folder (D59) bring their own character, model and pictures, served beside them.
final class Companion3DStage: NSView {
    private let web: WKWebView
    private var ready = false
    private var pending: [String] = []
    /// Which character the page shows (its file in `characters/`): a species' name, or a companion's added from a
    /// folder.
    private(set) var character: String
    /// Called each time the page has a character loaded and can take cues: at first, and after
    /// `show(_:)` swaps in another.
    var onReady: (() -> Void)?
    /// Called when the page never answered (three tries): show the 2D rig instead.
    var onFailed: (() -> Void)?
    /// The page asks for an effect (zZz, hearts, notes…) around the companion for a few seconds:
    /// the 2D view draws them over the 3D character.
    var onEffect: ((CharacterView.Flash, TimeInterval) -> Void)?

    /// `Resources/Companions3D`, bundled by scripts/build-app.sh.
    static var folder: URL? {
        guard let folder = ResourceLocator.resources?.appendingPathComponent("Companions3D", isDirectory: true),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("companion.html").path) else { return nil }
        return folder
    }

    /// The still Settings shows for a companion drawn in 3D.
    static func portrait(_ character: String) -> NSImage? {
        file("portraits/\(character).png").flatMap(NSImage.init(contentsOf:))
    }

    /// Its profile picture: head and shoulders on its own colour, round (companions-3d/references/avatars).
    static func avatar(_ character: String) -> NSImage? {
        file("avatars/\(character).png").flatMap(NSImage.init(contentsOf:))
    }

    /// Whether this Mac has `species`' 3D character: in the app, or installed from the gallery.
    static func has(_ species: CharacterSpecies) -> Bool { species.has3D && has(species.rawValue) }

    /// Whether this Mac has the 3D character `character`: in the app, or installed beside it.
    static func has(_ character: String) -> Bool {
        folder != nil && file("characters/\(character).js") != nil
    }

    /// One of the page's files: the app's own, else an installed companion's (`characters/<name>.js`…).
    static func file(_ path: String, root: URL? = folder) -> URL? {
        if let root {
            let own = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: own.path) { return own }
        }
        return CompanionAddons.file(path)
    }

    /// Nil when the app has no 3D resources or this Mac doesn't have that 3D character.
    init?(_ character: String, folder: URL? = Companion3DStage.folder) {
        guard let folder, Self.file("characters/\(character).js", root: folder) != nil else { return nil }
        self.character = character
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let config = WKWebViewConfiguration()
        // Served from a private scheme: one origin for the page, its modules and the model, and no
        // file-access exceptions.
        config.setURLSchemeHandler(FolderSchemeHandler(root: folder), forURLScheme: "companion3d")
        let bridge = Bridge()
        config.userContentController.add(bridge, name: "companion")
        config.suppressesIncrementalRendering = true
        web = PassThroughWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        super.init(frame: frame)
        bridge.stage = self
        web.navigationDelegate = bridge
        addSubview(web)
        loadPage()
    }

    private var attempts = 0

    /// Loads the page, and again if it hasn't said it is ready in 8 s (seen once at launch: the
    /// page never answered). After three tries it gives up (`onFailed`).
    private func loadPage() {
        attempts += 1
        web.load(URLRequest(url: URL(string: "companion3d://app/companion.html?c=\(character)")!))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !self.ready else { return }
            if self.attempts < 3 {
                NSLog("companion3d: no answer from the page; loading it again")
                self.loadPage()
            } else {
                NSLog("companion3d: the page never answered")
                self.onFailed?()
            }
        }
    }

    /// Swaps the character inside the running page: the one shown stays until the next one has
    /// drawn, so switching between 3D companions never shows an empty or 2D window.
    func show(_ next: String) {
        guard next != character, Self.has(next) else { return }
        character = next
        send(["kind": "character", "id": next])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Purely visual: clicks go to the companion window's own hit testing (the 2D rig's outline).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func handle(_ cue: CharacterView.Cue) {
        switch cue {
        case .state(let state): send(["kind": "state", "name": Self.name(of: state)])
        case .gesture(let gesture): send(["kind": "gesture", "name": "\(gesture)"])
        case .speak(let level): send(["kind": "speak", "level": level ?? 0])
        case .gaze(let v): send(v.map { ["kind": "gaze", "x": $0.dx, "y": $0.dy] } ?? ["kind": "gaze"])
        case .posture(let posture): send(["kind": "posture", "name": posture.rawValue])
        case .antic(let antic): send(["kind": "antic", "name": antic.rawValue])
        case .liveliness(let level): send(["kind": "liveliness", "level": level])
        }
    }

    /// Stops drawing while the companion can't be seen (WebGL would keep a GPU frame going).
    func setVisible(_ on: Bool) { send(["kind": "visible", "on": on]) }

    private static func name(of state: CharacterState) -> String {
        if case .working = state { return "working" }
        return state.name
    }

    private func send(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.sidefolk && window.sidefolk.handle(\(json))"
        if ready { web.evaluateJavaScript(script) } else { pending.append(script) }
    }

    fileprivate func pageReady() {
        NSLog("companion3d: ready")
        ready = true
        pending.forEach { web.evaluateJavaScript($0) }
        pending = []
        onReady?()
    }

    private final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var stage: Companion3DStage?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch body["kind"] as? String {
            case "ready": stage?.pageReady()
            case "effect":
                // Only names and a duration cross over, bounded: the page can't draw anything else.
                guard let name = body["name"] as? String, let effect = CharacterView.Flash(rawValue: name) else { return }
                let seconds = min(6, max(0.5, (body["seconds"] as? Double) ?? 1.8))
                stage?.onEffect?(effect, seconds)
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { NSLog("companion3d: page loaded") }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            NSLog("companion3d: load failed: \(error)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            NSLog("companion3d: load failed: \(error)")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The page's process died (memory pressure, a GPU reset): load it again.
            NSLog("companion3d: web content process ended; reloading")
            webView.reload()
        }
    }
}

/// A web view that never takes the pointer.
private final class PassThroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

/// Serves files under `root` for `companion3d://app/<path>`, and an installed companion's own files
/// (`CompanionAddons.file`); nothing else.
private final class FolderSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) { self.root = root.standardizedFileURL }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = String(url.path.drop { $0 == "/" })
        var file = root.appendingPathComponent(path).standardizedFileURL
        if !FileManager.default.fileExists(atPath: file.path), let addon = CompanionAddons.file(path) { file = addon }
        guard file.path.hasPrefix(root.path + "/") || CompanionAddons.file(path) == file,
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": Self.type(file.pathExtension), "Content-Length": "\(data.count)"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private static func type(_ ext: String) -> String {
        switch ext {
        case "html": "text/html; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "glb": "model/gltf-binary"
        case "json": "application/json"
        case "png": "image/png"
        default: "application/octet-stream"
        }
    }
}
