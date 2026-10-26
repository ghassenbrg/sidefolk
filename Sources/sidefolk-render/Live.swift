import AppKit
import ImageIO
import SidefolkCharacter
import UniformTypeIdentifiers

/// `--live <state|cycle|demo> <seconds> [<id>] [options]`: the companion in a real window, for CPU
/// checks, recordings and trying it by hand. It answers like the app's: click it, stroke it with
/// the pointer, drag it, throw it.
struct LiveOptions {
    var liveliness = Liveliness.minimal
    /// Runs the idle scheduler's clock faster, to watch it choose (demos only).
    var pace: Double = 1
    /// An opaque paper window, so a screen recording of its rectangle holds nothing else.
    var backdrop = false
    /// Captures what Core Animation shows, 25 frames a second, into this folder (and a film.mp4).
    var film: URL?
    var reducedMotion = false

    static let usage = "--liveliness minimal|balanced|lively  --pace <n>  --backdrop  --film <dir>  --reduced-motion"

    init?(_ args: [String]) {
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--liveliness":
                guard let value = rest.popFirst().flatMap(Liveliness.init(rawValue:)) else { return nil }
                liveliness = value
            case "--pace":
                guard let value = rest.popFirst().flatMap(Double.init), value > 0 else { return nil }
                pace = value
            case "--backdrop": backdrop = true
            case "--reduced-motion": reducedMotion = true
            case "--film":
                guard let value = rest.popFirst() else { return nil }
                film = URL(fileURLWithPath: value)
            default: return nil
            }
        }
    }
}

@MainActor
enum Live {
    static func run(state name: String, seconds: Double, look: CharacterLook, options: LiveOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = options.backdrop
        window.backgroundColor = options.backdrop ? Sheets.paper : .clear
        window.level = .floating
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = look
        view.reducedMotion = options.reducedMotion
        view.liveliness = options.liveliness
        view.lifePace = options.pace
        let stage = Stage(character: view)
        window.contentView = stage
        window.orderFrontRegardless()
        stage.startPointer()

        let states = CharacterState.gallery
        if name == "cycle" {
            Task { @MainActor in
                for state in states {
                    view.state = state
                    try? await Task.sleep(for: .seconds(1.5))
                    print("[live] \(state.name): \(animations(in: view.layer)) animations running")
                }
            }
        } else if name == "demo" {
            Demo.play(view, stage: stage)
        } else if let state = states.first(where: { $0.name == name }) {
            view.state = state
            // Calm states should drop to zero running animations once they settle (D20).
            Task { @MainActor in
                for t in stride(from: 5, to: Int(seconds), by: 5) {
                    try? await Task.sleep(for: .seconds(5))
                    // Finished one-shots stay attached until the next commit; only "∞" ones keep drawing.
                    let keys = animationKeys(in: view.layer)
                    let doing = view.performing.map { " · \($0.rawValue)" } ?? ""
                    print("[live] \(t)s: \(keys.filter { $0.hasSuffix("∞") }.count) looping, posture \(view.posture.rawValue)\(doing)")
                }
            }
        } else {
            print("no state called \(name)")
            exit(2)
        }
        let film = options.film.map { Film(view: view, into: $0) }
        print("[live] pid \(ProcessInfo.processInfo.processIdentifier) window \(window.windowNumber) showing \(name) for \(seconds)s, "
              + "liveliness \(options.liveliness.rawValue)")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            film?.finish()
            NSApp.terminate(nil)
        }
        app.run()
    }

    /// Animations attached anywhere in the tree: loops should come and go with their state.
    static func animations(in layer: CALayer?) -> Int { animationKeys(in: layer).count }

    /// Keys of every attached animation, "∞" marking the repeating ones.
    static func animationKeys(in layer: CALayer?) -> [String] {
        guard let layer else { return [] }
        let own = (layer.animationKeys() ?? []).map { key in
            layer.animation(forKey: key)?.repeatCount == .infinity ? key + "∞" : key
        }
        return own + (layer.sublayers ?? []).flatMap { animationKeys(in: $0) }
    }
}

/// The window's content: hands clicks, drags and throws to the companion the way the app does.
@MainActor
final class Stage: NSView {
    let character: CharacterView
    private var downAt: NSPoint?
    private var originAtDown: NSPoint?
    private var dragging = false
    private var samples: [(time: TimeInterval, point: NSPoint)] = []
    private var flight: Timer?
    private var monitors: [Any] = []

    init(character: CharacterView) {
        self.character = character
        super.init(frame: character.frame)
        addSubview(character)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func startPointer() {
        let handler: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved(NSEvent.mouseLocation) } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { handler($0); return $0 }) {
            monitors.append(local)
        }
    }

    /// Like the app: eyes follow the pointer nearby (anywhere when lively); stroking pets it.
    private func pointerMoved(_ p: NSPoint) {
        guard let window, !dragging, flight == nil else { return }
        character.pointerMoved(toScreen: p)
        guard !character.reducedMotion else { return }
        let c = window.convertToScreen(character.convert(character.characterFrame, to: nil))
        let dx = p.x - c.midX, dy = p.y - c.midY, distance = hypot(dx, dy)
        if distance < 260, distance > 6 {
            character.setGaze(CGVector(dx: dx / 160, dy: dy / 160))
            character.noteInteraction()
        } else if character.liveliness == .lively {
            character.setGaze(CGVector(dx: dx / max(distance, 1) * min(1, distance / 400), dy: dy / max(distance, 1) * min(1, distance / 400)))
        } else {
            character.setGaze(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        dragging = false
        samples = [(event.timestamp, NSEvent.mouseLocation)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let origin = originAtDown, let window else { return }
        let p = NSEvent.mouseLocation
        samples.append((event.timestamp, p))
        samples.removeAll { event.timestamp - $0.time > 0.1 }
        if !dragging, hypot(p.x - start.x, p.y - start.y) > 4 {
            dragging = true
            character.state = .dragging
        }
        guard dragging else { return }
        window.setFrameOrigin(NSPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard dragging, let window else {
            character.perform(.boop)
            return
        }
        dragging = false
        character.state = .idle
        let velocity = Self.velocity(samples)
        guard Fling.isToss(velocity), let screen = window.screen else {
            character.perform(.land)
            return
        }
        // Thrown: it tumbles through the air, lands on the bottom of the screen and is dizzy.
        let floor = screen.visibleFrame.minY - 20
        let fling = Fling(from: window.frame.origin, velocity: velocity, floor: floor,
                          span: screen.visibleFrame.minX...(screen.visibleFrame.maxX - window.frame.width))
        character.perform(.spin)
        let start = CACurrentMediaTime()
        flight = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                let t = CACurrentMediaTime() - start
                window.setFrameOrigin(fling.position(at: t))
                guard t >= fling.duration else { return }
                self.flight?.invalidate()
                self.flight = nil
                self.character.perform(.land)
                if fling.impact > 0.35 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.55))
                        self.character.perform(.dizzy)
                    }
                }
            }
        }
    }

    /// Points per second over the last tenth of a second of the drag.
    static func velocity(_ samples: [(time: TimeInterval, point: NSPoint)]) -> CGVector {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.01 else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}

/// Every moment in turn, then the postures: for recordings and a quick look.
@MainActor
enum Demo {
    static func play(_ view: CharacterView, stage: Stage) {
        let right = { NSPoint(x: (stage.window?.frame.maxX ?? 0) + 300, y: (stage.window?.frame.midY ?? 0) - 40) }
        let left = { NSPoint(x: (stage.window?.frame.minX ?? 0) - 300, y: (stage.window?.frame.midY ?? 0)) }
        let script: [(TimeInterval, String, () -> Void)] = [
            (1.0, "earTwitch", { view.perform(.earTwitch) }),
            (2.2, "stretch", { view.perform(.stretch) }),
            (5.2, "yawn", { view.perform(.yawn) }),
            (8.4, "scratch", { view.perform(.scratch) }),
            (11.0, "hop", { view.perform(.hop) }),
            (12.4, "wiggle", { view.perform(.wiggle) }),
            (14.2, "peek →", { view.perform(.peek, toward: right()) }),
            (18.0, "glance ←", { view.perform(.glance, toward: left()) }),
            (21.0, "sneeze", { view.perform(.sneeze) }),
            (23.4, "double take", { view.perform(.doubleTake) }),
            (25.8, "boop", { view.perform(.boop) }),
            (27.0, "pet", { view.perform(.pet) }),
            (29.4, "startle", { view.perform(.startle) }),
            (31.0, "cheer", { view.perform(.cheer) }),
            (33.2, "spin", { view.perform(.spin) }),
            (33.9, "land", { view.perform(.land) }),
            (34.5, "dizzy", { view.perform(.dizzy) }),
            (37.6, "sit", { view.setPosture(.sit, animated: true) }),
            (40.0, "lie down", { view.setPosture(.lie, animated: true) }),
            (43.0, "gets up", { view.noteInteraction() }),
        ]
        let start = Date()
        for (at, name, action) in script {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(at - Date().timeIntervalSince(start)))
                print(String(format: "[demo] %5.1fs %@", Date().timeIntervalSince(start), name))
                action()
            }
        }
    }
}

/// Records what Core Animation shows (the presentation tree, so springs, loops and moments are all
/// in it) without screen capture: frames on paper, 25 a second, then film.mp4 with ffmpeg if present.
@MainActor
final class Film {
    private let view: CharacterView
    private let dir: URL
    private var timer: Timer?
    private var count = 0
    static let fps = 25.0

    init(view: CharacterView, into dir: URL) {
        self.view = view
        self.dir = dir
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let timer = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func capture() {
        guard let layer = view.layer?.presentation() ?? view.layer else { return }
        let size = view.bounds.size
        let image = Sheets.draw(size) { context in
            Sheets.paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            layer.render(in: context)
        }
        save(image, dir.appendingPathComponent(String(format: "frame-%05d.png", count)))
        count += 1
    }

    func finish() {
        timer?.invalidate()
        print("[film] \(count) frames in \(dir.path)")
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let ffmpeg else { return print("[film] no ffmpeg: stitch the frames yourself") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-loglevel", "error", "-y", "-framerate", "\(Int(Self.fps))", "-i", dir.appendingPathComponent("frame-%05d.png").path,
                             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", dir.appendingPathComponent("film.mp4").path]
        try? process.run()
        process.waitUntilExit()
        print("[film] wrote \(dir.appendingPathComponent("film.mp4").path)")
    }
}
