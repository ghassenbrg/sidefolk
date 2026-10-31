import AppKit
import SidefolkCore
import SwiftUI

/// A live value beside the companion, as a pin (D35, D84): its name, number, symbol and what it read lately.
struct Readout: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var symbol = "gauge.with.dots.needle.33percent"
    /// The numbers it read since Sidefolk started, oldest first, for the small line (kept in memory only).
    var spark: [Double] = []
    var paused = false
    /// When it last read, and how often it reads: a value much older than that is stale and says so.
    var at: Date?
    var interval: TimeInterval = 60

    /// Old enough that the number may no longer be true: three readings missed, and at least two minutes.
    func stale(at now: Date) -> Bool {
        guard let at, !paused else { return false }
        return now.timeIntervalSince(at) > max(interval * 3, 120)
    }
}

/// Everything on the floor around the companion that isn't the companion or its folks (D84): the light pool at its
/// feet, the count or Focus/Quiet mark on its shoulder, the pins, and the agents lane. The window lays them out (in
/// its own coordinates, origin at the bottom); these views only draw them where they are told.
@MainActor @Observable
final class FloorModel {
    var light: LightPoolState = .idle
    /// How many wait, for the shoulder (alert and Focus carry it; waiting carries its own).
    var count = 0
    var pins: [Readout] = []
    var agents: [AgentChip] = []
    /// Pins and agent chips line up on the side nearest the companion.
    var inward: HorizontalAlignment = .leading

    /// Where things stand, in the floor's top-left coordinates: the pool's centre and width, the badge's centre, and
    /// the frames of the pins' and the agents' columns.
    var poolCenter = CGPoint.zero
    var poolWidth: CGFloat = 140
    var badgeCenter = CGPoint.zero
    var pinsFrame = CGRect.zero
    var agentsFrame = CGRect.zero

    static let pinGap: CGFloat = 6
    static let chipHeight: CGFloat = 30
    static let chipGap: CGFloat = 6
}

/// Under the companion: the pool of light.
struct FloorUnderlay: View {
    var model: FloorModel

    var body: some View {
        LightPool(state: model.light, width: model.poolWidth)
            .position(model.poolCenter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

/// Over the companion: the shoulder's mark, the pins and the agents lane.
struct FloorOverlay: View {
    var model: FloorModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShoulderBadge(state: model.light, count: model.count)
                .position(model.badgeCenter)
            if !model.pins.isEmpty {
                PinsColumn(pins: model.pins, alignment: model.inward)
                    .frame(width: model.pinsFrame.width, height: model.pinsFrame.height, alignment: Alignment(horizontal: model.inward, vertical: .bottom))
                    .position(x: model.pinsFrame.midX, y: model.pinsFrame.midY)
            }
            if !model.agents.isEmpty {
                AgentsColumn(chips: model.agents, alignment: model.inward)
                    .frame(width: model.agentsFrame.width, height: model.agentsFrame.height, alignment: Alignment(horizontal: model.inward, vertical: .bottom))
                    .position(x: model.agentsFrame.midX, y: model.agentsFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The pins, newest at the bottom, nearest the folks. Stale values grey their number and say how old they are, paused
/// ones say so: a pin never pretends to be live (b12).
struct PinsColumn: View {
    var pins: [Readout]
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        // Looked at again every half minute, so a value that stopped coming turns stale without a new reading.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: alignment, spacing: FloorModel.pinGap) {
                ForEach(pins) { pin in
                    PinCapsule(symbol: pin.paused ? "pause" : pin.symbol, label: Text(verbatim: pin.label),
                               value: Text(verbatim: pin.value), spark: pin.spark, note: note(pin, now: context.date))
                        .frame(maxWidth: Self.maxWidth)
                        .fixedSize()
                }
            }
        }
    }

    /// Room for the longest value Sidefolk reports itself ("Network ↓ 1.2 MB/s ↑ 40 kB/s").
    static let maxWidth: CGFloat = 280

    private func note(_ pin: Readout, now: Date) -> Text? {
        if pin.paused { return Text("paused", comment: "On a live value beside the companion: it isn't updating") }
        guard pin.stale(at: now), let at = pin.at else { return nil }
        return Text("\(TimeText.span(now.timeIntervalSince(at))) ago", comment: "On a live value beside the companion that stopped updating: how old it is (“12 min ago”)")
    }
}

/// The agents lane (D84): a chip per live Claude Code or Codex session, on the floor line beside the folks.
struct AgentsColumn: View {
    var chips: [AgentChip]
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: alignment, spacing: FloorModel.chipGap) {
                ForEach(chips) { AgentChipView(chip: $0, now: context.date) }
            }
        }
    }
}

struct AgentChipView: View {
    var chip: AgentChip
    var now: Date

    var body: some View {
        HStack(spacing: Theme.Space.xs + 2) {
            Circle().fill(chip.needsYou ? Theme.waitGlow : Theme.glow).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            (Text(verbatim: chip.agent).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                + Text(verbatim: detail).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Theme.Space.m)
        .frame(height: FloorModel.chipHeight)
        .background(Theme.surfaceRaised.opacity(0.94), in: Capsule())
        .elevation(.e2, radius: FloorModel.chipHeight / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(chip.agent) \(detail)"))
    }

    /// "· pockito · 14 min", or "· sidefolk · needs you".
    private var detail: String {
        let state = chip.needsYou ? String(localized: "needs you", comment: "A chip on an agent waiting for an answer")
            : TimeText.span(now.timeIntervalSince(chip.since))
        return ([""] + [chip.project, state].compactMap { $0 }).joined(separator: "  ·  ")
    }
}

/// The floor's layers inside the companion's window. Clicks fall through to the window's own view, which knows what a
/// click on a pin or a chip means.
final class FloorHostView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
