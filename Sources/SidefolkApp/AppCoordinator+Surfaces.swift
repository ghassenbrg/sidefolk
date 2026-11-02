import AppKit
import SidefolkCore

/// Extensions' surfaces beside the companion (D99): opening one (from words, a menu or the AI, all through
/// `surfaces.open`), its reactions and sounds under the same limits as cues, one Activity row, and away it goes with the extension.
extension AppCoordinator {
    func makeSurfacePanel(_ presentation: SurfaceInfo.Presentation) -> SurfacePanelController {
        let panel = SurfacePanelController(presentation: presentation)
        panel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            if presentation == .panel { self.companion.keepRaised(visible) }
            if !visible { self.cues.reset() }
        }
        panel.onExpired = { [weak self] model, reason in self?.finish(model, reason: reason) }
        panel.onBack = { model in model.send(.back) }
        panel.onSpeaker = { [weak self] model in self?.toggleSurfaceSounds(model) }
        panel.onCloseButton = { [weak panel] _ in panel?.hide() }
        return panel
    }

    func surfaceController(_ info: SurfaceInfo) -> SurfacePanelController { info.presentation == .panel ? surfacePanel : surfaceOverlay }

    func openSurface(_ request: SurfaceRequest) {
        let info = request.info
        if info.presentation == .panel {
            // One panel at a time: what else was out is kept and comes back as it was.
            askPanel.hide()
            playPanel.hide()
        }
        let wasHidden = !companion.isVisible
        if wasHidden { showCompanion(true) }
        guard let (frame, screen) = anchor() else { return }
        let controller = surfaceController(info)
        if request.arguments.isEmpty, let kept = controller.kept(info) {
            controller.show(kept, beside: frame, on: screen, cards: { [weak self] in self?.surfaceCards() ?? [] }, focus: request.takesKeyboard)
            kept.resume()
            return
        }
        if let previous = controller.model { finish(previous, reason: .closed) }
        let s = runtime.settings.current
        let host = runtime.extensions
        let session = SurfaceSession(info: info, host: host, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let model = SurfaceModel(info: info, session: session, soundsOn: false)
        // An overlay is a moment: a companion that came out for it goes again with it.
        surfaceRevealedCompanion = wasHidden && info.presentation == .overlay ? ObjectIdentifier(model) : nil
        model.readSpeaker = { [weak host] key in
            // A declared switch can change from a page or the program, and the frame follows; the plain choice is only the frame's.
            guard let key, host != nil else { return nil }
            return host?.shelf.settings.first { $0.extensionId == info.extensionId && $0.key == key }?.value.boolValue
        }
        model.view.figures = SceneFigures.live(settings: s)
        model.takesInput = mood.approvals.isEmpty
        model.fitScreen = { screen.visibleFrame }
        model.onFinished = { [weak self, weak model] in
            guard let self, let model else { return }
            self.finish(model, reason: .finished)
        }
        model.onOver = { [weak self, weak model] scene in
            guard let self, let model else { return }
            self.recordSurface(model, last: scene)
        }
        // Reactions act only while this surface is on screen, paced as cues are, and never carry words.
        model.onReact = { [weak self, weak controller, weak model] reaction in
            guard let self, let controller, let model, controller.model === model, controller.isVisible else { return }
            self.cues.react(reaction)
        }
        Task { @MainActor in
            let reader = await host.assetReader(extensionId: info.extensionId)
            model.soundsOn = await host.surfaceSpeaker(info, key: info.speakerSetting)
            model.reader = reader
            model.view.assets = SceneImages(reader: reader)
            model.onSound = { [weak self] path in
                guard let self, let reader, self.cues.soundsAllowed() else { return }
                SurfaceSounds.shared.play(path, from: reader)
            }
            controller.show(model, beside: frame, on: screen, cards: { [weak self] in self?.surfaceCards() ?? [] }, focus: request.takesKeyboard)
            await model.open(language: AppLanguage.current, arguments: request.arguments)
        }
    }

    /// Where Sidefolk's own cards stand, which a surface keeps clear of.
    private func surfaceCards() -> [NSRect] {
        var out: [NSRect] = []
        if askPanel.isVisible { out.append(askPanel.frame) }
        if let card = sidecard.visibleFrame { out.append(card) }
        return out
    }

    /// It ends for good: the extension hears why, and a surface that was used and never said it was over still gets its row.
    func finish(_ model: SurfaceModel, reason: SurfaceCloseReason) {
        // Hiding an overlay ends it, and comes back here: once is enough, with the reason this call has.
        guard !model.finished else { return }
        model.finished = true
        model.stop()
        if model.rowAtEnd() { recordSurface(model, last: model.scene) }
        let controller = surfaceController(model.info)
        if controller.model === model {
            controller.hide()
            controller.drop()
        }
        release(model)
        if surfaceRevealedCompanion == ObjectIdentifier(model) {
            surfaceRevealedCompanion = nil
            showCompanion(false)
        }
        let session = model.session
        Task { await session.close(reason) }
    }

    /// What it held in memory goes with it.
    private func release(_ model: SurfaceModel) {
        model.view.assets.emptied()
        if let reader = model.reader { SurfaceSounds.shared.forget(reader) }
    }

    private func recordSurface(_ model: SurfaceModel, last: SurfaceScene?) {
        guard model.writesRows else { return }
        let entry = model.activityEntry(companionName: runtime.settings.current.companionName, last: last)
        let activity = runtime.activity, events = runtime.events
        Task {
            _ = try? await activity.log(entry)
            events.changed(.activity)
        }
    }

    private func toggleSurfaceSounds(_ model: SurfaceModel) {
        model.soundsOn.toggle()
        let info = model.info, key = model.speakerKey, on = model.soundsOn, host = runtime.extensions
        Task { await host.setSurfaceSpeaker(info, key: key, on: on) }
    }

    /// A tool's reply asked to put its surface away: kept, as ✕ keeps it.
    func putSurfaceAway(of extensionId: String, surface: String?) {
        for controller in [surfacePanel, surfaceOverlay] {
            guard let model = controller.model, model.info.extensionId == extensionId, surface == nil || model.info.surface == surface else { continue }
            controller.hide()
        }
    }

    /// The extension was turned off or removed: its surface, kept or on screen, is gone at once.
    func dropSurfaces(of extensionId: String) {
        for controller in [surfacePanel, surfaceOverlay] {
            guard let model = controller.model, model.info.extensionId == extensionId else { continue }
            model.finished = true
            model.stop()
            controller.hide()
            controller.drop()
            release(model)
        }
    }

    /// An approval is waiting: every surface stops taking input until it is answered (T40).
    func holdSurfacesForApprovals() {
        let free = mood.approvals.isEmpty
        for controller in [surfacePanel, surfaceOverlay] {
            guard let model = controller.model, model.takesInput != free else { continue }
            model.takesInput = free
        }
    }

    #if DEBUG
    /// `surface:<extension>/<surface>` opens one as the AI would, waiting for a click; `surfaceFocus:…` as the person would.
    /// `surfaceClick:x,y` and `surfaceDrag:x,y:x,y` act on the panel's canvas (`overlay:` first for the overlay) through
    /// AppKit; `surfaceKey:<k>` presses a key; `surfaceMove:<area>[=value]` clicks an area by name (only if offered);
    /// `surfaceClose`, `surfaceFilm:<seconds>[:overlay]` writes frames, animations included, to `snapshots/film-…`,
    /// `surfaceStats` logs layers and sizes, `surfaceExportSounds:<dir>` writes the app's sounds as WAV files.
    func devSurface(_ command: String) -> Bool {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        guard let verb = parts.first, verb.hasPrefix("surface") else { return false }
        let rest = parts.count > 1 ? parts[1] : ""
        let overlay = rest.hasPrefix("overlay:") || rest == "overlay"
        let controller = overlay ? surfaceOverlay : surfacePanel
        let argument = overlay ? String(rest.dropFirst(8)) : rest
        func point(_ s: String) -> CGPoint? {
            let n = s.split(separator: ",").compactMap { Double($0) }
            return n.count == 2 ? CGPoint(x: n[0], y: n[1]) : nil
        }
        switch verb {
        case "surface", "surfaceFocus":
            Task { _ = await runtime.executor.execute(name: "surfaces.open", input: ["surface": .string(argument)], caller: verb == "surface" ? .agent(runId: "dev") : .user) }
        case "surfaceClick":
            guard let p = point(argument) else { return true }
            Task { await controller.devMouse([p]) }
        case "surfaceDrag":
            let points = argument.split(separator: ":").compactMap { point(String($0)) }
            Task { await controller.devMouse(points) }
        case "surfaceKey":
            _ = controller.model?.press(argument, seat: nil, timestamp: ProcessInfo.processInfo.systemUptime)
        case "surfaceMove":
            let bits = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if let area = bits.first { controller.model?.send(.click(area: area, value: bits.count > 1 ? bits[1] : nil, ms: nil)) }
        case "surfaceClose":
            controller.hide()
        case "surfaceFilm":
            let seconds = Double(argument) ?? 3
            guard let view = controller.model?.view else { return true }
            let dir = runtime.paths.home.appendingPathComponent("snapshots/film-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                var frame = 0
                let end = Date().addingTimeInterval(seconds)
                while Date() < end {
                    if let image = view.frameImage() {
                        let rep = NSBitmapImageRep(cgImage: image)
                        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "%04d.png", frame)))
                        frame += 1
                    }
                    try? await Task.sleep(for: .milliseconds(33))
                }
                Log.shared.info("dev", "film written", ["dir": dir.path, "frames": "\(frame)"])
            }
        case "surfaceExportSounds":
            // The app's synthesized sounds as files, for a pack moving off their names (D101).
            GameSounds.shared.export(to: URL(fileURLWithPath: argument))
        case "surfaceStats":
            Log.shared.info("dev", "surface", ["layers": "\(controller.model?.view.layerCount ?? 0)", "frame": "\(controller.frame)", "visible": "\(controller.isVisible)"])
        default: return false
        }
        return true
    }
    #endif
}
