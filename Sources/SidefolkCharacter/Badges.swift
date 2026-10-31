import QuartzCore

/// Ambient markers: small white chips stacked by the left ear, and an amber count by the right: what waits on you
/// is a question, not an error, so it is the app's warning amber (its sun), never red.
/// They stay still while the body moves, like labels pinned beside it.
@MainActor
final class Badges {
    private let parent: CALayer
    private var chips: [CharacterBadge: CALayer] = [:]
    private var spinner: CALayer?

    init(parent: CALayer) {
        self.parent = parent
    }

    func update(_ badges: Set<CharacterBadge>, moving: Bool, animated: Bool) {
        if animated {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.2
            parent.add(transition, forKey: "fade")
        }
        chips.values.forEach { $0.removeFromSuperlayer() }
        chips = [:]
        spinner = nil

        var slot = 0
        for badge in [CharacterBadge.watching, .busy] where badges.contains(badge) {
            let center = pt(22, 146 - CGFloat(slot) * 27)
            let chip = Badges.chip(at: center)
            chip.addSublayer(badge == .watching ? Badges.binoculars(at: center) : makeSpinner(at: center))
            parent.addSublayer(chip)
            chips[badge] = chip
            slot += 1
        }
        if let count = badges.compactMap({ if case .count(let n) = $0 { n } else { nil } }).max(), count > 0 {
            let chip = Badges.count(count)
            parent.addSublayer(chip)
            chips[.count(count)] = chip
        }
        if moving, let spinner {
            spinner.add(Motion.loop("transform.rotation.z", from: 0, to: -2 * Double.pi, duration: 1.1,
                                    reverses: false, timing: .linear), forKey: "spin")
        }
    }

    private static func chip(at center: CGPoint) -> CALayer {
        let chip = Layers.shape(Paths.circle(center, 12), fill: RGB.white.cg(), stroke: Palette.shellEdge.cg(0.6), lineWidth: 0.8)
        Layers.dropShadow(chip, path: chip.path, radius: 2.5, opacity: 0.2, offset: CGSize(width: 0, height: -1))
        // Sublayers are placed in canvas units, so give them a canvas-aligned container.
        let holder = Layers.canvas()
        holder.addSublayer(chip)
        return holder
    }

    private static func binoculars(at c: CGPoint) -> CALayer {
        let glyph = Layers.canvas()
        for dx in [-4.2, 4.2] {
            glyph.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: c.x + dx - 2.6, y: c.y - 1, width: 5.2, height: 7), 2),
                                           fill: Palette.navy.cg()))
            glyph.addSublayer(Layers.shape(Paths.circle(c + pt(dx, -2.5), 3.9), fill: Palette.navy.cg()))
            glyph.addSublayer(Layers.shape(Paths.circle(c + pt(dx, -2.5), 2), fill: Palette.aqua.cg()))
        }
        glyph.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: c.x - 2, y: c.y - 1, width: 4, height: 4), 1),
                                       fill: Palette.navy.cg()))
        return glyph
    }

    private func makeSpinner(at c: CGPoint) -> CALayer {
        let spin = Layers.canvas(anchor: c)
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: 6, startAngle: 0.3, endAngle: 0.3 + .pi * 1.4, clockwise: false)
        spin.addSublayer(Layers.shape(Paths.circle(c, 6), stroke: Palette.aqua.cg(0.22), lineWidth: 2.6))
        spin.addSublayer(Layers.shape(arc, stroke: Palette.aqua.cg(), lineWidth: 2.6))
        spinner = spin
        return spin
    }

    private static func count(_ n: Int) -> CALayer {
        let label = n > 9 ? "9+" : "\(n)"
        let center = pt(178, 146)
        let width: CGFloat = label.count > 1 ? 30 : 24
        let holder = Layers.canvas()
        let pill = Layers.shape(Paths.roundedRect(CGRect(x: center.x - width / 2, y: center.y - 12, width: width, height: 24), 12),
                                fill: Palette.yellow.cg(), stroke: RGB.white.cg(), lineWidth: 2)
        Layers.dropShadow(pill, path: nil, radius: 2.5, opacity: 0.22, offset: CGSize(width: 0, height: -1))
        holder.addSublayer(pill)
        let text = Layers.text(label, size: 15, weight: .heavy, color: Palette.navy)
        text.frame = CGRect(x: center.x - 20, y: center.y - 10, width: 40, height: 20)
        holder.addSublayer(text)
        return holder
    }
}
