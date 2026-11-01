import AppKit
import SwiftUI

// The toy feel shared by the games' parts: raised faces with a lip and a gloss, and a squash when pressed. Motion
// follows Reduce Motion. (The end card's confetti and rays went with the reward card's review: its mark appears once.)

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
