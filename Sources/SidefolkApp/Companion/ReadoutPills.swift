import AppKit
import SidefolkCore
import SwiftUI

/// A report's latest value as it stands beside the companion.
struct Readout: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var paused = false
}

@MainActor @Observable
final class ReadoutPillsModel {
    var items: [Readout] = []
    /// The pills line up on the side nearest the companion.
    var alignment: HorizontalAlignment = .leading
}

/// Live values above the on-duty folks: one small pill per report, updated in place (D35). A pill rather than a
/// folk holding the value: a number with its name needs room to be read at a glance, it must not move the rig
/// (no animation, no settling, nothing redrawn but its text), and several can stack.
struct ReadoutPills: View {
    var model: ReadoutPillsModel

    var body: some View {
        VStack(alignment: model.alignment, spacing: ReadoutPills.gap) {
            ForEach(model.items) { pill($0) }
        }
        .fixedSize()
    }

    static let height: CGFloat = 20
    static let gap: CGFloat = 3
    static let maxWidth: CGFloat = 180

    private func pill(_ r: Readout) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: r.label).foregroundStyle(Theme.inkMuted).lineLimit(1)
            Text(verbatim: r.value).foregroundStyle(Theme.ink).fontWeight(.semibold).monospacedDigit().lineLimit(1)
                .truncationMode(.tail)
            if r.paused { Image(systemName: "pause.fill").imageScale(.small).foregroundStyle(Theme.inkFaint) }
        }
        .font(.system(size: 11, design: .rounded))
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: Self.maxWidth)
        // Each pill as wide as its words (up to the cap), not as wide as the widest one.
        .fixedSize()
        .background(Capsule().fill(Theme.surface.opacity(0.95)))
        .overlay(Capsule().strokeBorder(Theme.folkColor("scout").opacity(0.8), lineWidth: 1))
        .opacity(r.paused ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The pills inside the companion's window. Clicks fall through to the window's own view, which knows how to
/// drag the companion and what a click on a pill means.
final class ReadoutHostView: NSHostingView<ReadoutPills> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
