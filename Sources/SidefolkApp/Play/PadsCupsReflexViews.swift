import SidefolkCore
import SwiftUI

// The parts that move on their own time, Sidefolk's: Copy Me's pads, Which Cup?'s shuffle, Quick Paws' button.

/// Coloured pads with a shape and a key cap each, raised like toy buttons; during the playback they light one by one
/// (pressed down, glowing, the shape popping) and take no presses.
struct PadsView: View {
    var pads: GameBoard.Pads
    var model: PlayModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(pads.pads.enumerated()), id: \.offset) { i, pad in
                let lit = model.parts.lit == i
                Button { model.pressPad(i) } label: {
                    VStack(spacing: 6) {
                        PadShape(shape: pad.shape).fill(.white.opacity(lit ? 1 : 0.92))
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .frame(width: 30, height: 30)
                            .scaleEffect(lit ? 1.25 : 1)
                        Text(verbatim: pad.label).font(Theme.Font.captionStrong).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        GameKeyCap(text: "\(i + 1)", light: true)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(GameBevel(color: Self.color(pad.hue), pressed: lit, glow: lit))
                    .animation(.spring(duration: 0.18, bounce: 0.5), value: lit)
                }
                .buttonStyle(GamePressStyle())
                .allowsHitTesting(!model.parts.playing && !pads.locked)
                .accessibilityLabel(Text(verbatim: "\(i + 1), \(pad.label)"))
            }
        }
        .padding(.bottom, 4)
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

/// Cups and a gem on a little table: the gem under its cup, the cups lowered and swapped (by position) at the game's
/// pace, then picked; lifted once picked to show where the gem was. The cups and the gem are Sidefolk's pictures
/// (GameArt), the table, shadows and key caps drawn here.
struct CupsView: View {
    var cups: GameBoard.Cups
    var model: PlayModel

    /// Where a resting cup's rim meets the table.
    private static let floor: CGFloat = 112
    private static let cupHeight: CGFloat = 64

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !model.parts.shuffling)) { t in
            let elapsed = model.parts.shuffling ? t.date.timeIntervalSince(model.parts.shuffleStart) : .infinity
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(cups.count)
                let layout = Self.layout(cups, elapsed)
                ZStack(alignment: .topLeading) {
                    table(width: geo.size.width)
                    if let spot = cups.picked ?? (cups.locked ? nil : model.parts.cursor) {
                        // The pick or the arrow keys' pointer: a ring on the table at that place, the app's accent.
                        Ellipse().strokeBorder(Theme.accent, lineWidth: 3).frame(width: min(slot - 10, 64), height: 18)
                            .position(x: slot * (CGFloat(spot) + 0.5), y: Self.floor + 1)
                    }
                    ForEach(0..<cups.count, id: \.self) { cup in
                        // Each cup's shadow, smaller and lighter as it rises.
                        let rise = layout.lift[cup] + CGFloat(layout.hop[cup]) * 0.3
                        Ellipse().fill(.black.opacity(0.16 * (1 - rise * 0.6)))
                            .frame(width: min(slot - 14, 58) * (1 - rise * 0.3), height: 9)
                            .position(x: slot * (CGFloat(layout.x[cup]) + 0.5), y: Self.floor + 1)
                    }
                    if let gem = layout.gemAt {
                        gemView.position(x: slot * (CGFloat(gem) + 0.5), y: Self.floor - 14)
                    }
                    ForEach(0..<cups.count, id: \.self) { cup in
                        let x = layout.x[cup], lift = layout.lift[cup]
                        cupView(position: Int(x.rounded()))
                            .frame(width: min(slot - 8, 72), height: Self.cupHeight)
                            .position(x: slot * (CGFloat(x) + 0.5), y: Self.floor - Self.cupHeight / 2 + 2 - lift * 46 - layout.hop[cup] * 14)
                            .zIndex(layout.hop[cup])
                    }
                    ForEach(0..<cups.count, id: \.self) { position in
                        GameKeyCap(text: "\(position + 1)").position(x: slot * (CGFloat(position) + 0.5), y: Self.floor + 22)
                    }
                }
            }
        }
        .frame(height: 146)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    /// A soft felt top for the cups to stand on.
    private func table(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accentSoft.opacity(0.5), Theme.accentSoft], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
            .frame(width: width, height: 34)
            .position(x: width / 2, y: Self.floor + 2)
    }

    @ViewBuilder private var gemView: some View {
        if GameArt.gem.image != nil {
            GameArt.gem.view(height: 26).shadow(color: Theme.sun.opacity(0.6), radius: 6)
        } else {
            Image(systemName: "suit.diamond.fill").font(.system(size: 22)).foregroundStyle(Theme.accent).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func cupView(position: Int) -> some View {
        let picked = cups.picked == position
        Button { model.send(.cell(row: 0, column: position)) } label: {
            ZStack(alignment: .bottom) {
                if GameArt.cup.image != nil {
                    GameArt.cup.view(height: Self.cupHeight - 4)
                } else {
                    CupShape().fill(LinearGradient(colors: [Theme.coral.opacity(0.85), Theme.coral], startPoint: .top, endPoint: .bottom))
                        .frame(height: 54)
                }
            }
            .scaleEffect(picked ? 1.06 : 1, anchor: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
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
                // An arcade button: a rim, a domed face lit from above, rings of light at the signal.
                Circle().fill(Theme.surfaceSunken).overlay(Circle().strokeBorder(Theme.line, lineWidth: 1)).padding(-8)
                if go {
                    Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 6).padding(-18)
                    Circle().strokeBorder(Theme.accent.opacity(0.15), lineWidth: 5).padding(-28)
                }
                Circle().fill(go ? Theme.accent : early ? GameColors.lostSoft : Theme.surfaceRaised).brightness(-0.12).offset(y: 6)
                Circle().fill(go ? Theme.accent : early ? GameColors.lostSoft : Theme.surfaceRaised)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(go ? 0.4 : 0.5), .clear], startPoint: .top, endPoint: .center)))
                    .overlay(Circle().strokeBorder(go ? .white.opacity(0.5) : Theme.line, lineWidth: go ? 3 : 1))
                    .shadow(color: go ? Theme.accent.opacity(0.6) : .black.opacity(0.08), radius: go ? 16 : 3)
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
            .frame(width: 150, height: 150)
            .padding(.vertical, 20)
            .scaleEffect(go ? 1.06 : 1)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.18, bounce: 0.5), value: go)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(reflex.armed && !early)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: words))
    }
}
