import SidefolkCore
import SwiftUI

// The parts that move on their own time, Sidefolk's: Copy Me's pads, Which Cup?'s shuffle, Quick Paws' button.

/// Coloured pads with a shape and a key cap each; during the playback they light one by one and take no presses.
struct PadsView: View {
    var pads: GameBoard.Pads
    var model: PlayModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(pads.pads.enumerated()), id: \.offset) { i, pad in
                let lit = model.parts.lit == i
                Button { model.pressPad(i) } label: {
                    VStack(spacing: 6) {
                        // White on the pad's colour; the pad's colour on white while it is lit.
                        PadShape(shape: pad.shape).fill(lit ? Self.color(pad.hue) : .white.opacity(0.9))
                            .frame(width: 30, height: 30)
                        Text(verbatim: pad.label).font(Theme.Font.captionStrong).foregroundStyle(lit ? Self.color(pad.hue) : .white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        GameKeyCap(text: "\(i + 1)", light: !lit)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(lit ? Color.white : Self.color(pad.hue)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Self.color(pad.hue), lineWidth: lit ? 3 : 0))
                    .scaleEffect(lit ? 1.06 : 1)
                    .shadow(color: Self.color(pad.hue).opacity(lit ? 0.6 : 0.15), radius: lit ? 10 : 3, y: 2)
                    .animation(.easeOut(duration: 0.12), value: lit)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!model.parts.playing && !pads.locked)
                .accessibilityLabel(Text(verbatim: "\(i + 1), \(pad.label)"))
            }
        }
        .opacity(pads.locked ? 0.6 : 1)
        .overlay(alignment: .top) {
            if model.parts.playing {
                // While the companion dances the sequence: watch, don't press.
                Label(String(localized: "Watch…", comment: "Copy Me: the companion shows the sequence to copy"), systemImage: "eye.fill")
                    .font(Theme.Font.captionStrong).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface)).offset(y: -12)
            }
        }
    }

    /// The pads' colours, soft enough that red reads as a colour of the game, not an alarm.
    static func color(_ hue: GameBoard.Pads.Hue) -> Color {
        switch hue {
        case .blue: Color(light: 0x3E7BFA, dark: 0x5B8FFF)
        case .green: Color(light: 0x2FA36B, dark: 0x3DBE7E)
        case .yellow: Color(light: 0xE6A817, dark: 0xF2BE3A)
        case .red: Theme.coral
        case .purple: Color(light: 0x8B5CF6, dark: 0xA27BFF)
        }
    }
}

nonisolated struct PadShape: Shape {
    var shape: GameBoard.Pads.Shape

    func path(in r: CGRect) -> Path {
        switch shape {
        case .circle: return Path(ellipseIn: r)
        case .square: return Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 4)
        case .triangle:
            return Path { p in
                p.move(to: CGPoint(x: r.midX, y: r.minY + 1))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2))
                p.closeSubpath()
            }
        case .diamond:
            return Path { p in
                p.move(to: CGPoint(x: r.midX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
                p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.midY))
                p.closeSubpath()
            }
        case .star:
            return Path { p in
                for i in 0..<10 {
                    let angle = Double(i) * .pi / 5 - .pi / 2
                    let radius = (i.isMultiple(of: 2) ? 0.5 : 0.22) * min(r.width, r.height)
                    let point = CGPoint(x: r.midX + cos(angle) * radius, y: r.midY + sin(angle) * radius)
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                p.closeSubpath()
            }
        }
    }
}

/// A small key cap, so every part says which key works it.
struct GameKeyCap: View {
    var text: String
    var light = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(light ? .white.opacity(0.9) : Theme.inkMuted)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(light ? .white.opacity(0.6) : Theme.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Cups and a gem: the gem under its cup, the cups lowered and swapped (by position) at the game's pace, then picked;
/// lifted once picked to show where the gem was.
struct CupsView: View {
    var cups: GameBoard.Cups
    var model: PlayModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !model.parts.shuffling)) { t in
            let elapsed = model.parts.shuffling ? t.date.timeIntervalSince(model.parts.shuffleStart) : .infinity
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(cups.count)
                let layout = Self.layout(cups, elapsed)
                ZStack(alignment: .topLeading) {
                    if let gem = layout.gemAt {
                        Image(systemName: "suit.diamond.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                            .position(x: slot * (CGFloat(gem) + 0.5), y: 88)
                            .accessibilityHidden(true)
                    }
                    ForEach(0..<cups.count, id: \.self) { cup in
                        let x = layout.x[cup], lift = layout.lift[cup]
                        cupView(position: Int(x.rounded()), lifted: lift)
                            .frame(width: min(slot - 10, 70), height: 74)
                            .position(x: slot * (CGFloat(x) + 0.5), y: 80 - lift * 40 - layout.hop[cup] * 12)
                            .zIndex(layout.hop[cup])
                    }
                }
            }
        }
        .frame(height: 130)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func cupView(position: Int, lifted: CGFloat) -> some View {
        let picked = cups.picked == position
        let pointed = model.parts.cursor == position && !cups.locked
        Button { model.send(.cell(row: 0, column: position)) } label: {
            VStack(spacing: 4) {
                CupShape().fill(LinearGradient(colors: [Theme.coral.opacity(0.85), Theme.coral], startPoint: .top, endPoint: .bottom))
                    .overlay(CupShape().stroke(picked || pointed ? Theme.ink : .clear, lineWidth: 2.5))
                    .frame(height: 54)
                GameKeyCap(text: "\(position + 1)")
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!cups.locked && !cups.revealed && !model.parts.shuffling)
        .accessibilityLabel(String(localized: "Cup \(position + 1)", comment: "Which Cup?: a cup, read by VoiceOver"))
    }

    /// Where each cup is at `elapsed` seconds: its position (fractional mid-swap), how far it is lifted, and the gem.
    static func layout(_ c: GameBoard.Cups, _ elapsed: TimeInterval) -> (x: [Double], lift: [CGFloat], hop: [Double], gemAt: Int?) {
        var at = Array(0..<c.count)
        var x = at.map(Double.init)
        var lift = [CGFloat](repeating: 0, count: c.count)
        var hop = [Double](repeating: 0, count: c.count)
        if c.revealed {
            // Every cup up: the gem where it lay, or nowhere.
            return (x, lift.map { _ in 1 }, hop, c.gem)
        }
        guard !c.swaps.isEmpty, elapsed.isFinite else { return (x, lift, hop, nil) }
        if elapsed < 1.4, let hide = c.hide {
            // The gem shown under its cup, then the cup lowered over it.
            lift[hide] = elapsed < 1.0 ? 1 : CGFloat(max(0, 1 - (elapsed - 1.0) / 0.4))
            return (x, lift, hop, hide)
        }
        let step = (elapsed - 1.4) / c.swapSeconds
        for (k, swap) in c.swaps.enumerated() where Double(k) < step {
            let a = swap[0], b = swap[1]
            guard let ca = at.firstIndex(of: a), let cb = at.firstIndex(of: b) else { continue }
            let p = min(1, step - Double(k))
            let eased = p < 1 ? (1 - cos(p * .pi)) / 2 : 1
            x[ca] = Double(a) + Double(b - a) * eased
            x[cb] = Double(b) + Double(a - b) * eased
            hop[ca] = sin(p * .pi)
            if p >= 1 {
                at[ca] = b
                at[cb] = a
                hop[ca] = 0
            }
        }
        return (x, lift, hop, nil)
    }
}

nonisolated struct CupShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// The reflex duel's big button: calm while it waits, bright at the signal, "Too soon!" at once for an early press,
/// and the game's result words once played.
struct ReflexView: View {
    var reflex: GameBoard.Reflex
    var model: PlayModel

    var body: some View {
        let go = model.parts.signal != nil
        let early = model.parts.early
        let words = early ? reflex.early : reflex.shows ?? (go ? reflex.go : reflex.armed ? reflex.wait : "…")
        Button { model.boop() } label: {
            ZStack {
                Circle().fill(go ? Theme.accent : early ? GameColors.lostSoft : Theme.surfaceSunken)
                Circle().strokeBorder(go ? Theme.accent.opacity(0.4) : Theme.line, lineWidth: go ? 10 : 2)
                VStack(spacing: 4) {
                    if early { Image(systemName: "xmark.circle.fill").foregroundStyle(GameColors.lost) }
                    Text(verbatim: words)
                        // The times once played are a sentence: smaller than the signal.
                        .font(.system(size: go ? 30 : reflex.shows != nil && !early ? 16 : 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(go ? Theme.onAccent : Theme.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    if reflex.armed && !early { GameKeyCap(text: "Space", light: go) }
                }
                .padding(12)
            }
            .frame(width: 160, height: 160)
            .scaleEffect(go ? 1.06 : 1)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.18, bounce: 0.5), value: go)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(reflex.armed && !early)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: words))
    }
}
