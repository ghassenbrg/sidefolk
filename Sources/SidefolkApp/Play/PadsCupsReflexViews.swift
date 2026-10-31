import SidefolkCore
import SwiftUI

// The parts that move on their own time, Sidefolk's: Copy Me's pads, Which Cup?'s shuffle, Quick Paws' button.

/// Clay tiles on the table, each picturing its move (a waving hand, a hopping bunny, arrows spinning, a bow): its
/// colour, its picture (or its shape where Sidefolk has no picture for it), its name and key cap on the cream base.
/// During the playback they light one by one (pressed down, glowing, the picture popping) and take no presses.
struct PadsView: View {
    var pads: GameBoard.Pads
    var model: PlayModel

    var body: some View {
        HStack(spacing: pads.pads.count > 4 ? 6 : 9) {
            ForEach(Array(pads.pads.enumerated()), id: \.offset) { i, pad in
                let lit = model.parts.lit == i
                Button { model.pressPad(i) } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            GameBevel(color: Self.color(pad.hue), corner: 14, pressed: lit, glow: lit, depth: 4)
                            Group {
                                if let art = GameArt.pad(pad.art), art.image != nil {
                                    art.view(fitting: pads.pads.count > 4 ? 40 : 46)
                                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                                } else {
                                    PadShape(shape: pad.shape).fill(.white.opacity(0.92)).frame(width: 30, height: 30)
                                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                                }
                            }
                            .scaleEffect(lit ? 1.18 : 1)
                            .offset(y: lit ? 3 : 0)
                        }
                        .frame(height: pads.pads.count > 4 ? 60 : 66)
                        .overlay(alignment: .topTrailing) { GameKeyCap(text: "\(i + 1)", light: true).padding(5) }
                        .padding(.bottom, 4)
                        // The name has the base's whole width (the key cap sits on the tile), so a long one fits.
                        Text(verbatim: pad.label).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0x4A3B2E))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    // The cream clay base each tile sits in.
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF6EBDD))
                        .shadow(color: Color(hex: 0x6B4A2B).opacity(0.35), radius: 0, y: 3)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 3))
                    .animation(.spring(duration: 0.18, bounce: 0.5), value: lit)
                }
                .buttonStyle(GamePressStyle())
                .allowsHitTesting(!model.parts.playing && !pads.locked)
                .accessibilityLabel(Text(verbatim: "\(i + 1), \(pad.label)"))
            }
        }
        .padding(.vertical, 6)
        .opacity(pads.locked ? 0.7 : 1)
    }

    /// The pads' colours, soft clay, so red reads as a colour of the game, not an alarm.
    static func color(_ hue: GameBoard.Pads.Hue) -> Color {
        switch hue {
        case .blue: Color(light: 0x5A8DF0, dark: 0x6B9BFF)
        case .green: Color(light: 0x56B58A, dark: 0x5FC496)
        case .yellow: Color(light: 0xF0B43C, dark: 0xF5C255)
        case .red: Color(light: 0xF07A68, dark: 0xF4897A)
        case .purple: Color(light: 0x9A7BE8, dark: 0xA98BF2)
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
    /// Its own ink, on a surface of a fixed colour (the pads' cream base).
    var ink: Color?

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(ink ?? (light ? .white.opacity(0.9) : Theme.inkMuted))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ink?.opacity(0.5) ?? (light ? .white.opacity(0.6) : Theme.line), lineWidth: 1))
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
    private static let floor: CGFloat = 124
    private static let cupHeight: CGFloat = 76

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !model.parts.shuffling)) { t in
            let elapsed = model.parts.shuffling ? t.date.timeIntervalSince(model.parts.shuffleStart) : .infinity
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(cups.count)
                let layout = Self.layout(cups, elapsed)
                ZStack(alignment: .topLeading) {
                    if let spot = cups.picked ?? (cups.locked ? nil : model.parts.cursor) {
                        // The pick or the arrow keys' pointer: a ring on the table at that place, the app's accent.
                        Ellipse().strokeBorder(Theme.accent, lineWidth: 3).frame(width: min(slot - 10, 64), height: 18)
                            .position(x: slot * (CGFloat(spot) + 0.5), y: Self.floor + 1)
                    }
                    ForEach(0..<cups.count, id: \.self) { cup in
                        // Each cup's shadow on the table under it: smaller and lighter as it rises, nearer as it comes forward.
                        let rise = layout.lift[cup], depth = CGFloat(layout.depth[cup])
                        Ellipse().fill(.black.opacity(0.16 * (1 - rise * 0.6)))
                            .frame(width: min(slot - 14, 58) * (1 - rise * 0.3) * (1 + depth * 0.1), height: 9)
                            .position(x: slot * (CGFloat(layout.x[cup]) + 0.5), y: Self.floor + 1 + depth * 9)
                    }
                    if let gem = layout.gemAt {
                        gemView.position(x: slot * (CGFloat(gem) + 0.5), y: Self.floor - 14)
                    }
                    ForEach(0..<cups.count, id: \.self) { cup in
                        // A swap slides the two cups along the table, one passing in front of the other (lower and a
                        // little larger, as nearer), never through it.
                        let x = layout.x[cup], lift = layout.lift[cup], depth = CGFloat(layout.depth[cup])
                        cupView(position: Int(x.rounded()))
                            .frame(width: min(slot - 8, 72), height: Self.cupHeight)
                            .scaleEffect(1 + depth * 0.1, anchor: .bottom)
                            .position(x: slot * (CGFloat(x) + 0.5), y: Self.floor - Self.cupHeight / 2 + 2 - lift * 46 + depth * 9)
                            .zIndex(Double(depth))
                    }
                    ForEach(0..<cups.count, id: \.self) { position in
                        Text(verbatim: "\(position + 1)").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0x6B4A2B))
                            .frame(width: 26, height: 22)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0xFFF6EA))
                                .shadow(color: Color(hex: 0x6B4A2B).opacity(0.35), radius: 0, y: 2))
                            .position(x: slot * (CGFloat(position) + 0.5), y: Self.floor + 26)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(height: 162)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var gemView: some View {
        if GameArt.gem.image != nil {
            GameArt.gem.view(height: 30).shadow(color: Theme.sun.opacity(0.7), radius: 8)
        } else {
            Image(systemName: "suit.diamond.fill").font(.system(size: 22)).foregroundStyle(Theme.accent).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func cupView(position: Int) -> some View {
        let picked = cups.picked == position
        Button { model.send(.cell(row: 0, column: position)) } label: {
            ZStack(alignment: .bottom) {
                if GameArt.cup.image != nil {
                    GameArt.cup.view(height: Self.cupHeight - 4).shadow(color: .black.opacity(0.12), radius: 2, y: 2)
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

    /// Where each cup is at `elapsed` seconds: its position (fractional mid-swap), how far it is lifted, how far toward
    /// the viewer (+1) or away (−1) it is passing, and the gem.
    static func layout(_ c: GameBoard.Cups, _ elapsed: TimeInterval) -> (x: [Double], lift: [CGFloat], depth: [Double], gemAt: Int?) {
        var at = Array(0..<c.count)
        var x = at.map(Double.init)
        var lift = [CGFloat](repeating: 0, count: c.count)
        var depth = [Double](repeating: 0, count: c.count)
        if c.revealed {
            // Every cup up: the gem where it lay, or nowhere.
            return (x, lift.map { _ in 1 }, depth, c.gem)
        }
        guard !c.swaps.isEmpty, elapsed.isFinite else { return (x, lift, depth, nil) }
        if elapsed < 1.4, let hide = c.hide {
            // The gem shown under its cup, then the cup lowered over it, easing onto the table.
            let down = max(0, min(1, (elapsed - 1.0) / 0.4))
            lift[hide] = elapsed < 1.0 ? 1 : CGFloat(1 - down * down * (3 - 2 * down))
            return (x, lift, depth, hide)
        }
        let step = (elapsed - 1.4) / c.swapSeconds
        for (k, swap) in c.swaps.enumerated() where Double(k) < step {
            let a = swap[0], b = swap[1]
            guard let ca = at.firstIndex(of: a), let cb = at.firstIndex(of: b) else { continue }
            let p = min(1, step - Double(k))
            let eased = p < 1 ? (1 - cos(p * .pi)) / 2 : 1
            x[ca] = Double(a) + Double(b - a) * eased
            x[cb] = Double(b) + Double(a - b) * eased
            depth[ca] = p < 1 ? sin(p * .pi) : 0
            depth[cb] = p < 1 ? -sin(p * .pi) : 0
            if p >= 1 {
                at[ca] = b
                at[cb] = a
            }
        }
        return (x, lift, depth, nil)
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

/// The reflex duel's big button: Sidefolk's glossy Boop button with its paw, calm and dimmed while it waits, lit with
/// rings of light at the signal, "Too soon!" at once for an early press, and the game's words on a plate under it.
struct ReflexView: View {
    var reflex: GameBoard.Reflex
    var model: PlayModel
    var style: GameStyle = .of(nil)

    var body: some View {
        let go = model.parts.signal != nil
        let early = model.parts.early
        let words = early ? reflex.early : reflex.shows ?? (go ? reflex.go : reflex.armed ? reflex.wait : "…")
        Button { model.boop() } label: {
            VStack(spacing: 10) {
                ZStack {
                    if go {
                        Circle().strokeBorder(Color(hex: 0xFF5FC8).opacity(0.45), lineWidth: 7).frame(width: 196, height: 196)
                        Circle().strokeBorder(Color(hex: 0xFF5FC8).opacity(0.2), lineWidth: 6).frame(width: 226, height: 226)
                    }
                    if GameArt.boop.image != nil {
                        GameArt.boop.view(fitting: 170)
                            .saturation(go ? 1.15 : reflex.armed ? 0.55 : 0.8)
                            .brightness(go ? 0.06 : reflex.armed ? -0.08 : 0)
                            .shadow(color: go ? Color(hex: 0xFF5FC8).opacity(0.8) : .black.opacity(0.25), radius: go ? 22 : 6, y: go ? 0 : 4)
                    } else {
                        Circle().fill(go ? Theme.accent : Theme.surfaceRaised).frame(width: 150, height: 150)
                    }
                    if go {
                        Text(verbatim: words).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .shadow(color: Color(hex: 0x9A1F6E), radius: 0, y: 3)
                            .rotationEffect(.degrees(-6))
                            .offset(y: -78)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 190)
                .scaleEffect(go ? 1.06 : 1)
                // What it says now: steady, too soon, or the times once played, on a dark plate.
                if !go {
                    HStack(spacing: 6) {
                        if early { Image(systemName: "xmark.circle.fill").foregroundStyle(GameColors.lost) }
                        Text(verbatim: words).font(.system(size: reflex.shows != nil && !early ? 16 : 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                        if reflex.armed && !early { GameKeyCap(text: "Space", light: true) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x15103A).opacity(0.88))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: 0x7A5CFF).opacity(0.5), lineWidth: 1)))
                }
            }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.18, bounce: 0.5), value: go)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(reflex.armed && !early)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: words))
    }
}
