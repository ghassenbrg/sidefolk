#if DEBUG
import AppKit
import SidefolkCore

/// The dev channel's Calendar commands (D95), so the page's gestures can be tried and filmed without hands:
///   calendar:swipe:-160[:film]      two fingers sideways (the events the trackpad sends, fed to the page's handler)
///   calendar:scroll:300[:film]      two fingers down the month (positive is later), with momentum and settling
///   calendar:drag:x1,y1:x2,y2[:film] a mouse drag in Home's window (points from its top left), queued as the mouse's
///   calendar:type:<words> (into the field that has the keyboard) | calendar:dclick:x,y | calendar:click:x,y | calendar:key:left|right|up|down|return|delete|escape|cmdleft|cmdright|cmdt
///   calendar:select:<entry id> | calendar:inspect:<entry id> | calendar:hide:<calendar id> | calendar:show:<calendar id>
///   calendar:hour:<points>          the hour's height, as a pinch leaves it
/// A film is the Home window, 30 frames a second, in $SIDEFOLK_HOME/snapshots/film-<stamp>/.
extension AppCoordinator {
    func devCalendar(_ command: String) -> Bool {
        let parts = command.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts[0] == "calendar" else { return false }
        let model = home.devCalendar
        let film = parts.last == "film"
        switch parts[1] {
        case "swipe":
            guard parts.count > 2, let dx = Double(parts[2]) else { return true }
            filming(film) { await self.feedScroll(dx: dx, dy: 0) }
        case "scroll":
            guard parts.count > 2, let dy = Double(parts[2]) else { return true }
            filming(film) { await self.feedScroll(dx: 0, dy: -dy) }
        case "drag":
            guard parts.count > 3, let from = point(parts[2]), let to = point(parts[3]) else { return true }
            filming(film) { await self.mouseDrag(from: from, to: to) }
        case "click", "dclick":
            guard parts.count > 2, let at = point(parts[2]) else { return true }
            Task { await self.mouseClick(at: at, count: parts[1] == "dclick" ? 2 : 1) }
        case "key":
            guard parts.count > 2 else { return true }
            key(parts[2])
        case "type":
            // Into whatever field has the keyboard (the editor's title, in its popover).
            front()
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.insertText(parts.dropFirst(2).joined(separator: ":"),
                                                                         replacementRange: NSRange(location: NSNotFound, length: 0))
        case "select": model.selection = parts.dropFirst(2).joined(separator: ":")
        case "inspect": model.inspecting = parts.dropFirst(2).joined(separator: ":")
        case "hide", "show": if parts.count > 2 { model.setHidden(parts[2], parts[1] == "hide") }
        case "hour": if parts.count > 2, let h = Double(parts[2]) { model.setHourHeight(h); model.keepHourHeight() }
        default: return false
        }
        return true
    }

    private func point(_ text: String) -> CGPoint? {
        let n = text.split(separator: ",").compactMap { Double($0) }
        return n.count == 2 ? CGPoint(x: n[0], y: n[1]) : nil
    }

    /// A gesture as the trackpad sends it: began, a stream of changes about a frame apart, ended, then momentum.
    private func feedScroll(dx: Double, dy: Double) async {
        guard let catcher = CalendarScrollCatcher.dev else { return }
        func send(_ phase: CGScrollPhase?, momentum: CGMomentumScrollPhase? = nil, _ x: Double, _ y: Double) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(y.rounded()),
                                   wheel2: Int32(x.rounded()), wheel3: 0) else { return }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            if let phase { cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
            if let momentum { cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue)) }
            if let event = NSEvent(cgEvent: cg) { _ = catcher.scroll(event) }
        }
        // Slower than fingers (about a second), so a film at 30 frames a second sees the page follow them.
        let steps = 36
        send(.began, 0, 0)
        for _ in 0..<steps {
            send(.changed, dx / Double(steps), dy / Double(steps))
            try? await Task.sleep(for: .milliseconds(30))
        }
        send(.ended, 0, 0)
        // Momentum, slowing down.
        var vx = dx / Double(steps) * 0.6, vy = dy / Double(steps) * 0.6
        send(nil, momentum: .begin, vx, vy)
        for _ in 0..<12 {
            vx *= 0.8
            vy *= 0.8
            send(nil, momentum: .continuous, vx, vy)
            try? await Task.sleep(for: .milliseconds(16))
        }
        send(nil, momentum: .end, 0, 0)
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// What the person would be typing into: a popover or sheet in front of Home, else Home.
    private func front() {
        let window = NSApp.windows.first { $0.isVisible && ($0.className.contains("Popover") || $0.sheetParent != nil) } ?? home.devWindow
        NSApp.activate(ignoringOtherApps: true)  // the dev channel only: a synthetic click needs the app in front
        window?.makeKey()
    }

    /// A point of Home's window from its top left, in the window's own coordinates (from its bottom left).
    private func local(_ p: CGPoint) -> CGPoint? {
        guard let window = home.devWindow else { return nil }
        return CGPoint(x: p.x, y: window.frame.height - p.y)
    }

    /// A mouse event in Home's window, queued as the window server's are, so gestures and tracking loops see it.
    private func post(_ type: NSEvent.EventType, _ at: CGPoint, clicks: Int = 1) {
        guard let window = home.devWindow,
              let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                             pressure: type == .leftMouseUp ? 0 : 1) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private func mouseDrag(from: CGPoint, to: CGPoint) async {
        guard let a = local(from), let b = local(to) else { return }
        NSApp.activate(ignoringOtherApps: true)  // the dev channel only: a synthetic click needs the app in front
        home.devWindow?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseDown, a)
        let steps = 24
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseUp, b)
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func mouseClick(at p: CGPoint, count: Int) async {
        guard let at = local(p) else { return }
        NSApp.activate(ignoringOtherApps: true)  // the dev channel only: a synthetic click needs the app in front
        home.devWindow?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(150))
        for click in 1...count {
            post(.leftMouseDown, at, clicks: click)
            post(.leftMouseUp, at, clicks: click)
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    private func key(_ name: String) {
        let codes: [String: (CGKeyCode, CGEventFlags)] = [
            "left": (123, []), "right": (124, []), "down": (125, []), "up": (126, []), "return": (36, []), "delete": (51, []),
            "escape": (53, []), "cmdleft": (123, .maskCommand), "cmdright": (124, .maskCommand), "cmdt": (17, .maskCommand), "cmdz": (6, .maskCommand),
        ]
        // The key window: Home's, or a popover or sheet in front of it.
        front()
        guard let (code, flags) = codes[name], let window = NSApp.keyWindow ?? home.devWindow else { return }
        for down in [true, false] {
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            cg.flags = flags
            if let event = NSEvent(cgEvent: cg), let keyed = NSEvent.keyEvent(
                with: event.type, location: .zero, modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                windowNumber: window.windowNumber, context: nil, characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "", isARepeat: false, keyCode: code) {
                NSApp.postEvent(keyed, atStart: false)
            }
        }
    }

    /// Runs a gesture while writing Home's window 30 times a second, when asked to film it.
    private func filming(_ film: Bool, _ gesture: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            guard film, let window = home.devWindow else { return await gesture() }
            let dir = runtime.paths.home.appendingPathComponent("snapshots/film-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var frame = 0
            let recorder = Task { @MainActor in
                while !Task.isCancelled {
                    if let view = window.contentView?.superview ?? window.contentView,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "frame-%04d.png", frame)))
                        frame += 1
                    }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
            await gesture()
            try? await Task.sleep(for: .milliseconds(500))
            recorder.cancel()
            Log.shared.info("dev", "film written", ["dir": dir.path, "frames": "\(frame)"])
        }
    }
}
#endif
