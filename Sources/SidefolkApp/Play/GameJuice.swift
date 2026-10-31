import AppKit
import SwiftUI

// The toy feel shared by the games' parts: raised faces with a lip and a gloss, a squash when pressed, and the
// celebrations of an end card (a burst of confetti and stars for a win). Motion follows Reduce Motion.

enum GameMotion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// A raised game face in `color`: a darker lip under it, a soft light from above and a gloss; pressed, the face sinks
/// onto its lip; `glow` lights it up (a pad playing its note).
struct GameBevel: View {
    var color: Color
    var corner: CGFloat = 16
    var pressed = false
    var glow = false
    var depth: CGFloat = 5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(color).brightness(-0.16).offset(y: depth)
            shape.fill(color)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(glow ? 0.45 : 0.22), .clear], startPoint: .top, endPoint: .center)))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.14)).frame(height: 4).padding(.horizontal, corner * 1.2).padding(.top, 3)
                }
                .overlay(shape.strokeBorder(.white.opacity(glow ? 0.9 : 0.12), lineWidth: glow ? 3 : 1))
                .offset(y: pressed ? depth - 1 : 0)
        }
        .shadow(color: color.opacity(glow ? 0.7 : 0.18), radius: glow ? 14 : 3, y: glow ? 0 : 3)
    }
}

/// A press squashes the button a little, as a toy key would.
struct GamePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !GameMotion.reduced ? 0.95 : 1)
            .animation(.spring(duration: 0.15, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Confetti and stars bursting from the middle once, for the person's win: shown only with its verdict (D75), never
/// with Reduce Motion, and in the snapshots drawn mid-flight.
struct Celebration: View {
    var seed: Int = 7
    @State private var start = Date()
    @Environment(\.revealProgress) private var fixed

    private static let colors: [Color] = [Theme.sun, Theme.coral, Color(hex: 0x3E7BFA), Color(hex: 0x2FA36B), Color(hex: 0x8B5CF6), Color(hex: 0x5AC8D8)]

    var body: some View {
        if GameMotion.reduced {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: fixed != nil)) { t in
                let elapsed = fixed != nil ? 0.45 : t.date.timeIntervalSince(start)
                Canvas { context, size in
                    guard elapsed < 1.8 else { return }
                    var rng = SplitMix(seed: UInt64(seed))
                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.35)
                    for i in 0..<36 {
                        let angle = Double(rng.next() % 360) * .pi / 180
                        let speed = 120 + Double(rng.next() % 160)
                        let spin = Double(rng.next() % 720) - 360
                        let x = origin.x + cos(angle) * speed * elapsed
                        let y = origin.y + sin(angle) * speed * elapsed * 0.8 + 260 * elapsed * elapsed
                        let fade = max(0, 1 - elapsed / 1.8)
                        var piece = context
                        piece.opacity = fade
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .degrees(spin * elapsed))
                        let color = Self.colors[i % Self.colors.count]
                        if i % 5 == 0 {
                            piece.fill(StarShape().path(in: CGRect(x: -6, y: -6, width: 12, height: 12)), with: .color(Theme.sun))
                        } else {
                            piece.fill(Path(roundedRect: CGRect(x: -4, y: -2, width: 8, height: 4.5), cornerRadius: 1), with: .color(color))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Five points, for the confetti's stars and the stickers.
nonisolated struct StarShape: Shape {
    var inner: CGFloat = 0.45

    func path(in r: CGRect) -> Path {
        Path { p in
            for i in 0..<10 {
                let angle = Double(i) * .pi / 5 - .pi / 2
                let radius = (i.isMultiple(of: 2) ? 0.5 : 0.5 * inner) * min(r.width, r.height)
                let point = CGPoint(x: r.midX + cos(angle) * radius, y: r.midY + sin(angle) * radius)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        }
    }
}

/// A small fixed sequence for the confetti, the same burst every time.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
