import AppKit
import SidefolkCore
import SwiftUI

/// A live value beside the companion, as a pin (D35, D84): its name, number, symbol and what it read lately.
struct Readout: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    /// The value at rest beside the companion, with what is set around it (`WatchReading.atRest`).
    var atRest: String
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

/// Something small beside the companion that says more when the pointer rests on it.
enum FloorItem: Equatable {
    case pin(String)
    case agent(String)
    case folk(DutyFolk)
}

/// Everything on the floor around the companion that isn't the companion or its folks (D84): the light pool at its
/// feet, the count or Focus/Quiet mark on its shoulder, and a small column of extras close to it: pins as their value
/// alone and agents as round faces. Details come only on demand (a tip while the pointer rests on one), and the extras
/// step back while the person works under them. The window lays them out (in its own coordinates, origin at the
/// bottom); these views only draw them where they are told.
@MainActor @Observable
final class FloorModel {
    var light: LightPoolState = .idle
    /// The voice's level while the microphone listens (D84), nil otherwise.
    var voiceLevel: Double?
    /// How many wait, for the shoulder (alert and Focus carry it; waiting carries its own).
    var count = 0
    var pins: [Readout] = []
    var agents: [AgentChip] = []
    /// The extras line up on the side nearest the companion.
    var inward: HorizontalAlignment = .leading
    /// The person works under the companion's corner or passes through it: the extras fade and shrink.
    var receded = false

    /// Where things stand, in the floor's top-left coordinates: the pool's centre and width, the badge's centre, and
    /// the extras' column.
    var poolCenter = CGPoint.zero
    var poolWidth: CGFloat = 140
    var badgeCenter = CGPoint.zero
    var extrasFrame = CGRect.zero

    /// At most this many pins stand by the companion; Home shows them all.
    /// Those beside it, and the moment of one that comes and goes (D116).
    static let pinsShown = WatchLimits.maxBeside + 1
    static let pinHeight: CGFloat = 24
    static let dot: CGFloat = 22
    static let gap: CGFloat = 4
}

/// Under the companion: the pool of light.
struct FloorUnderlay: View {
    var model: FloorModel

    var body: some View {
        LightPool(state: model.light, width: model.poolWidth, level: model.voiceLevel)
            .position(model.poolCenter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

/// Over the companion: the shoulder's mark and the extras.
struct FloorOverlay: View {
    var model: FloorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShoulderBadge(state: model.light, count: model.count)
                .position(model.badgeCenter)
            if !model.pins.isEmpty || !model.agents.isEmpty {
                FloorExtras(pins: model.pins, agents: model.agents, alignment: model.inward)
                    .frame(width: model.extrasFrame.width, height: model.extrasFrame.height,
                           alignment: Alignment(horizontal: model.inward, vertical: .bottom))
                    .opacity(model.receded ? 0.28 : 1)
                    .scaleEffect(model.receded && !reduceMotion ? 0.86 : 1,
                                 anchor: model.inward == .trailing ? .bottomTrailing : .bottomLeading)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.standard, value: model.receded)
                    .position(x: model.extrasFrame.midX, y: model.extrasFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The extras beside the companion, kept small (the founder's rule: it must never sprawl over people's work): pins
/// as an icon and a number, agents as round faces with a status dot, the agents nearest the folks.
struct FloorExtras: View {
    var pins: [Readout]
    var agents: [AgentChip]
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        // Looked at again every half minute, so a value that stopped coming greys without a new reading.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: alignment, spacing: FloorModel.gap) {
                ForEach(pins.prefix(FloorModel.pinsShown)) { MiniPin(pin: $0, now: context.date) }
                if !agents.isEmpty {
                    HStack(spacing: FloorModel.gap) {
                        ForEach(agents) { AgentDot(chip: $0) }
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// A pin at rest: its symbol and its number. Paused or stale, the number greys (b12); the rest is in its tip.
struct MiniPin: View {
    var pin: Readout
    var now: Date

    var body: some View {
        let dim = pin.paused || pin.stale(at: now)
        HStack(spacing: 5) {
            Image(systemName: pin.paused ? "pause.fill" : pin.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            Text(verbatim: pin.atRest).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(dim ? Theme.inkFaint : Theme.ink).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.s + 1)
        .frame(height: FloorModel.pinHeight)
        .frame(maxWidth: 120)
        .fixedSize()
        .lanternGlass(radius: FloorModel.pinHeight / 2, elevation: .e2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(pin.label) \(pin.value)"))
    }
}

/// An agent session at rest: its maker's mark in a small circle, with a dot for how it is (working, or waiting for you).
struct AgentDot: View {
    var chip: AgentChip

    var body: some View {
        Circle().fill(Theme.surfaceRaised)
            .overlay {
                if let logo = Self.logo(chip)?.image {
                    Image(nsImage: logo).resizable().scaledToFit().padding(5).foregroundStyle(Theme.ink)
                } else {
                    Text(verbatim: String(chip.agent.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                }
            }
            .frame(width: FloorModel.dot, height: FloorModel.dot)
            .elevation(.e2, radius: FloorModel.dot / 2)
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(chip.needsYou ? Theme.waitGlow : Theme.glow).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: AgentTip.line(chip, now: Date())))
    }

    static func logo(_ chip: AgentChip) -> ProviderLogo? {
        switch chip.agent {
        case "Claude Code": .claude
        case "Codex": .codex
        default: nil
        }
    }
}

/// What a pin, an agent or a folk says while the pointer rests on it: a short glass card beside it.
struct FloorTip: View {
    enum Content: Equatable {
        case pin(Readout)
        case agent(AgentChip)
        case words(String)
    }

    var content: Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                switch content {
                case .pin(let pin): pinTip(pin, now: context.date)
                case .agent(let chip): agentTip(chip, now: context.date)
                case .words(let words): Text(verbatim: words).font(Theme.Font.callout).foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .lanternGlass(radius: Theme.Radius.card, elevation: .e2)
        }
        .padding(14)
        .fixedSize()
    }

    private func pinTip(_ pin: Readout, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.s) {
                Label { Text(verbatim: pin.label) } icon: { Image(systemName: pin.symbol) }
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
                Text(verbatim: pin.value).font(Theme.Font.headline.monospacedDigit()).foregroundStyle(Theme.ink)
                if pin.spark.count > 1 { Sparkline(values: pin.spark, color: Theme.glow).frame(width: 56, height: 16) }
            }
            Text(verbatim: PinTip.meta(pin, now: now)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
        }
    }

    private func agentTip(_ chip: AgentChip, now: Date) -> some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(chip.needsYou ? Theme.waitGlow : Theme.glow).frame(width: 8, height: 8)
            Text(verbatim: AgentTip.line(chip, now: now)).font(Theme.Font.callout).foregroundStyle(Theme.ink)
        }
    }
}

enum PinTip {
    /// "every 10 s", "paused", "12 min ago · every 5 min": how live the number is.
    static func meta(_ pin: Readout, now: Date) -> String {
        if pin.paused { return String(localized: "paused", comment: "On a live value beside the companion: it isn't updating") }
        let every = Describe.interval(pin.interval)
        guard pin.stale(at: now), let at = pin.at else { return every }
        return String(localized: "\(TimeText.span(now.timeIntervalSince(at))) ago", comment: "On a live value beside the companion that stopped updating: how old it is (“12 min ago”)")
            + " · " + every
    }
}

enum AgentTip {
    /// "Claude Code · sidefolk · needs you", "Codex · pockito · 14 min".
    static func line(_ chip: AgentChip, now: Date) -> String {
        let state = chip.needsYou ? String(localized: "needs you", comment: "A chip on an agent waiting for an answer")
            : TimeText.span(now.timeIntervalSince(chip.since))
        let many = chip.count > 1 ? String(localized: "\(chip.count) sessions", comment: "An agent's face beside the companion standing for several sessions in one folder") : nil
        return ([chip.agent, chip.project, chip.title, many, state].compactMap { $0 }).joined(separator: " · ")
    }
}

/// The floor's layers inside the companion's window. Clicks fall through to the window's own view, which knows what a
/// click on a pin or a chip means.
final class FloorHostView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
