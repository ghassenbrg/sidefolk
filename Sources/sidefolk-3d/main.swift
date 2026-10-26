import AppKit
import SceneKit

// Spike, not product: a Mochi built from primitives in SceneKit, in a transparent always-on-top
// window, to judge what a 3D companion feels like and costs (docs/research/lively-companions.md).
//
//   sidefolk-3d --snap <file.png>        one offscreen frame (no window)
//   sidefolk-3d --live <secs> [--still]  a 200 pt window: breathing, ear sway, blinks, eyes on the
//                                        pointer; click it to hop. --still holds it (no actions) for
//                                        the idle-cost baseline. Check CPU with top -pid.

MainActor.assumeIsolated {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "--snap" where args.count == 2:
        let mochi = Mochi3D()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = mochi.scene
        renderer.pointOfView = mochi.camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 600, height: 600), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("snapshot failed")
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: args[1]))
        print("wrote \(args[1])")
    case "--live" where args.count >= 2:
        Window3D.run(seconds: Double(args[1]) ?? 20, still: args.contains("--still"))
    default:
        print("usage: sidefolk-3d --snap <file.png> | --live <seconds> [--still]")
        exit(2)
    }
}

/// Mochi from spheres and capsules, in the brand's colours, lit softly from the upper left.
@MainActor
final class Mochi3D {
    let scene = SCNScene()
    let camera = SCNNode()
    let root = SCNNode()
    let body = SCNNode()
    let head = SCNNode()
    private(set) var ears: [SCNNode] = []
    private(set) var eyes: [SCNNode] = []

    static let white = NSColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1)
    static let navy = NSColor(srgbRed: 0.13, green: 0.21, blue: 0.37, alpha: 1)
    static let ink = NSColor(srgbRed: 0.08, green: 0.15, blue: 0.31, alpha: 1)
    static let aqua = NSColor(srgbRed: 0.42, green: 0.86, blue: 0.80, alpha: 1)

    init() {
        scene.background.contents = NSColor.clear
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 24
        camera.position = SCNVector3(0, 1.45, 9.2)
        camera.look(at: SCNVector3(0, 1.45, 0))
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 520
        fill.light?.color = NSColor(srgbRed: 0.86, green: 0.89, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(fill)

        scene.rootNode.addChildNode(root)
        root.addChildNode(body)
        body.addChildNode(head)

        // Body: a soft round bun; feet; little arms.
        body.addChildNode(Self.blob(radius: 0.62, scale: SCNVector3(1, 0.72, 0.85), at: SCNVector3(0, 0.55, 0), color: Self.white))
        for side: Float in [-1, 1] {
            body.addChildNode(Self.blob(radius: 0.22, scale: SCNVector3(1.15, 0.6, 1.2), at: SCNVector3(side * 0.28, 0.12, 0.25), color: Self.white))
            let arm = Self.blob(radius: 0.13, scale: SCNVector3(0.8, 1.5, 0.8), at: SCNVector3(side * 0.62, 0.62, 0.15), color: Self.white)
            arm.eulerAngles.z = CGFloat(side * 0.35)
            body.addChildNode(arm)
        }
        // Scarf: a torus around the neck and a hanging end.
        let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.5, pipeRadius: 0.13))
        scarf.geometry?.firstMaterial = Self.material(Self.aqua, roughness: 0.9)
        scarf.position = SCNVector3(0, 0.98, 0)
        scarf.scale = SCNVector3(1, 0.8, 0.85)
        body.addChildNode(scarf)
        let end = SCNNode(geometry: SCNBox(width: 0.24, height: 0.42, length: 0.1, chamferRadius: 0.05))
        end.geometry?.firstMaterial = Self.material(Self.aqua, roughness: 0.9)
        end.position = SCNVector3(0.22, 0.72, 0.5)
        end.eulerAngles.z = 0.25
        body.addChildNode(end)

        // Head: wide and round; eyes with a catchlight; a tiny nose; tall ears dipped in navy.
        head.position = SCNVector3(0, 1.48, 0)
        head.addChildNode(Self.blob(radius: 0.78, scale: SCNVector3(1.12, 0.86, 0.92), at: SCNVector3(0, 0, 0), color: Self.white))
        for side: Float in [-1, 1] {
            let eye = Self.blob(radius: 0.105, scale: SCNVector3(0.85, 1.05, 0.5), at: SCNVector3(side * 0.36, -0.08, 0.68), color: Self.ink,
                                roughness: 0.2)
            eye.addChildNode(Self.blob(radius: 0.035, scale: SCNVector3(1, 1, 1), at: SCNVector3(0.04, 0.05, 0.08), color: .white))
            head.addChildNode(eye)
            eyes.append(eye)
            let ear = SCNNode()
            ear.position = SCNVector3(side * 0.3, 0.42, -0.1)
            ear.eulerAngles.z = CGFloat(-side * 0.22)
            ear.addChildNode(Self.capsule(height: 1.05, radius: 0.19, at: SCNVector3(0, 0.45, 0), color: Self.white))
            ear.addChildNode(Self.capsule(height: 0.46, radius: 0.196, at: SCNVector3(0, 0.75, 0), color: Self.navy))
            head.addChildNode(ear)
            ears.append(ear)
        }
        head.addChildNode(Self.blob(radius: 0.04, scale: SCNVector3(1.4, 0.9, 0.8), at: SCNVector3(0, -0.02, 0.74), color: Self.ink))
    }

    static func material(_ color: NSColor, roughness: CGFloat = 0.55) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0
        return m
    }

    static func blob(radius: CGFloat, scale: SCNVector3, at position: SCNVector3, color: NSColor, roughness: CGFloat = 0.6) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 48
        sphere.firstMaterial = material(color, roughness: roughness)
        let node = SCNNode(geometry: sphere)
        node.scale = scale
        node.position = position
        return node
    }

    static func capsule(height: CGFloat, radius: CGFloat, at position: SCNVector3, color: NSColor) -> SCNNode {
        let capsule = SCNCapsule(capRadius: radius, height: height)
        capsule.firstMaterial = material(color)
        let node = SCNNode(geometry: capsule)
        node.position = position
        return node
    }

    // MARK: Motion (SceneKit actions: evaluated by SceneKit every frame while any run)

    func breathe() {
        let inhale = SCNAction.scale(to: 1.02, duration: 1.4)
        inhale.timingMode = .easeInEaseOut
        let exhale = SCNAction.scale(to: 1, duration: 1.4)
        exhale.timingMode = .easeInEaseOut
        body.runAction(.repeatForever(.sequence([inhale, exhale])), forKey: "breath")
        for (i, ear) in ears.enumerated() {
            let base = ear.eulerAngles.z
            let out = SCNAction.rotateTo(x: 0, y: 0, z: base + 0.06, duration: 1.3 + Double(i) * 0.2)
            out.timingMode = .easeInEaseOut
            let back = SCNAction.rotateTo(x: 0, y: 0, z: base - 0.04, duration: 1.3 + Double(i) * 0.2)
            back.timingMode = .easeInEaseOut
            ear.runAction(.repeatForever(.sequence([out, back])), forKey: "sway")
        }
    }

    func blink() {
        for eye in eyes {
            let close = SCNAction.customAction(duration: 0.16) { node, t in
                let k = 1 - 0.9 * sin(Double(t) / 0.16 * .pi)
                node.scale = SCNVector3(0.85, 1.05 * CGFloat(k), 0.5)
            }
            eye.runAction(close)
        }
    }

    func hop() {
        let crouch = SCNAction.scale(to: 0.94, duration: 0.1)
        let up = SCNAction.moveBy(x: 0, y: 0.45, z: 0, duration: 0.22)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.45, z: 0, duration: 0.2)
        down.timingMode = .easeIn
        root.runAction(.sequence([crouch, .group([up, .scale(to: 1, duration: 0.15)]), down]))
        for ear in ears {
            let base = ear.eulerAngles.z
            ear.runAction(.sequence([.wait(duration: 0.3), .rotateTo(x: -0.3, y: 0, z: base, duration: 0.15),
                                     .rotateTo(x: 0, y: 0, z: base, duration: 0.35)]))
        }
    }

    /// The head turns toward the pointer: -1...1 each way.
    func look(_ dx: CGFloat, _ dy: CGFloat) {
        head.runAction(.rotateTo(x: -dy * 0.25, y: dx * 0.45, z: 0, duration: 0.3, usesShortestUnitArc: true), forKey: "look")
    }
}

/// The spike's window: transparent, floating, with the same kind of loops the 2D rig runs.
@MainActor
enum Window3D {
    static var blinkTimer: Timer?

    static func run(seconds: Double, still: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 260, y: 40, width: 200, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        let mochi = Mochi3D()
        let view = ClickView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), options: nil)
        view.scene = mochi.scene
        view.pointOfView = mochi.camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false
        view.onClick = { mochi.hop() }
        window.contentView = view
        window.orderFrontRegardless()
        view.isPlaying = !still
        if !still {
            mochi.breathe()
            scheduleBlink(mochi)
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
                MainActor.assumeIsolated {
                    let p = NSEvent.mouseLocation, c = window.frame
                    mochi.look(max(-1, min(1, (p.x - c.midX) / 300)), max(-1, min(1, (p.y - c.midY) / 300)))
                }
            }
        }
        print("[3d] pid \(ProcessInfo.processInfo.processIdentifier) window \(window.windowNumber) \(still ? "still" : "alive") for \(seconds)s")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            NSApp.terminate(nil)
        }
        app.run()
    }

    static func scheduleBlink(_ mochi: Mochi3D) {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 3...7), repeats: false) { _ in
            MainActor.assumeIsolated {
                mochi.blink()
                scheduleBlink(mochi)
            }
        }
    }
}

final class ClickView: SCNView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
}
