import SidefolkCore
import SwiftUI

// The number games' parts: a thermometer, a number field with its digit pad, a row of sticks and lives.

/// Cold to warm, with its words: a thermometer for how close a guess is. Blue to orange, never a verdict's colours.
struct MeterView: View {
    var meter: GameBoard.Meter
    /// Cold sits at the reading's start: the gradients turn round with the layout in Arabic.
    @Environment(\.layoutDirection) private var direction
    private var start: UnitPoint { direction == .rightToLeft ? .trailing : .leading }
    private var end: UnitPoint { direction == .rightToLeft ? .leading : .trailing }

    var body: some View {
        VStack(spacing: 4) {
            // A thermometer lying down: its bulb in the reading's colour, the tube filling toward Hot, ticks along it.
            HStack(spacing: -6) {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), Self.tint(meter.value)], center: UnitPoint(x: 0.35, y: 0.3),
                                             startRadius: 1, endRadius: 14))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 26, height: 26)
                    .shadow(color: Self.tint(meter.value).opacity(0.5), radius: 4)
                    .zIndex(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [Color(hex: 0x5AA9FF), Color(hex: 0xB8D8FF), Color(hex: 0xFFC46B), Color(hex: 0xFF8A3D)],
                                                      startPoint: start, endPoint: end)).opacity(0.3)
                        Capsule().fill(LinearGradient(colors: [Color(hex: 0x5AA9FF), Self.tint(meter.value)], startPoint: start, endPoint: end))
                            .frame(width: max(14, geo.size.width * meter.value))
                            .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.35)).frame(height: 3).padding(.horizontal, 6).padding(.top, 2) }
                        HStack(spacing: 0) {
                            ForEach(1..<10, id: \.self) { _ in
                                Spacer(minLength: 0)
                                Rectangle().fill(.white.opacity(0.6)).frame(width: 1, height: 6)
                            }
                            Spacer(minLength: 0)
                        }
                        Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                    }
                    .animation(GameMotion.reduced ? nil : .spring(duration: 0.5, bounce: 0.3), value: meter.value)
                }
                .frame(height: 14)
            }
            .frame(height: 26)
            HStack {
                if let low = meter.low { Label(low, systemImage: "snowflake").labelStyle(.titleAndIcon) }
                Spacer()
                if let label = meter.label { Text(verbatim: label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
                Spacer()
                if let high = meter.high { Label(high, systemImage: "flame.fill") }
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: meter.label ?? "\(Int(meter.value * 100))%"))
    }

    static func tint(_ v: Double) -> Color { v < 0.5 ? Color(hex: 0x5AA9FF) : v < 0.8 ? Color(hex: 0xFFC46B) : Color(hex: 0xFF8A3D) }
}

/// A big number with a digit pad, and the guesses so far with where the answer lies (↑ higher, ↓ lower, ✓).
struct NumberFieldView: View {
    var field: GameBoard.NumberField
    var model: PlayModel

    var body: some View {
        VStack(spacing: 10) {
            if !field.history.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(field.history.suffix(8).enumerated()), id: \.offset) { _, g in chip(g) }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            HStack(spacing: 12) {
                Text(verbatim: model.parts.draft.isEmpty ? "?" : model.parts.draft)
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(model.parts.draft.isEmpty ? Theme.inkFaint : Theme.ink)
                    .frame(minWidth: 110, minHeight: 64)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceSunken))
                    .accessibilityLabel(field.label ?? String(localized: "Your guess", comment: "A number game's field, read by VoiceOver"))
                pad
            }
            if let label = field.label { Text(verbatim: label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        // A card behind the field and its pad, so they read on any scene.
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.9)))
        .disabled(field.locked)
    }

    /// 1–9, then ⌫ 0 ↵, laid out left to right in every language, as a phone's pad is.
    private var pad: some View {
        VStack(spacing: 4) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["delete", "0", "return"]], id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { k in
                        Button {
                            switch k {
                            case "delete": model.deleteBack()
                            case "return": model.submitDraft()
                            default: model.typeDigit(k)
                            }
                        } label: {
                            Group {
                                if k == "delete" { Image(systemName: "delete.left") } else if k == "return" { Image(systemName: "return") } else { Text(verbatim: k) }
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(k == "return" ? Theme.onAccent : Theme.ink)
                            .frame(width: 44, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(k == "return" ? Theme.accent : Theme.surfaceSunken))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func chip(_ g: GameBoard.NumberField.Guess) -> some View {
        let symbol = switch g.mark {
        case .higher: "arrow.up"
        case .lower: "arrow.down"
        case .right: "checkmark"
        }
        return HStack(spacing: 2) {
            Text(verbatim: "\(g.value)").monospacedDigit()
            Image(systemName: symbol)
        }
        .font(Theme.Font.captionStrong)
        .foregroundStyle(g.mark == .right ? .white : Theme.ink)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(g.mark == .right ? Theme.success : Theme.surfaceSunken))
    }
}

/// A row of candy sticks: hovering one shows which would go (it and the ones after it), a click takes them.
struct SticksView: View {
    var sticks: GameBoard.Sticks
    var model: PlayModel
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 4) { row }
    }

    @ViewBuilder private var row: some View {
        let groups = Dictionary(sticks.groups.enumerated().flatMap { g, members in members.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<sticks.total, id: \.self) { i in
                let gone = i >= sticks.left
                // The sticks just taken rise and stay faint, to show the move; once none is left (the game decided),
                // they go entirely, so the end leaves an empty row.
                let lifting = gone && i < sticks.left + sticks.taken && sticks.left > 0
                let takes = sticks.left - i
                let would = hovered.map { i >= $0 && !gone } ?? false
                Button { if (1...sticks.take).contains(takes) { model.send(.number(takes)) } } label: {
                    CandyStick(color: stickColor(group: groups[i], hint: sticks.hint.contains(i)))
                        .frame(width: 11, height: 70)
                        .offset(y: would ? -10 : lifting ? -30 : 0)
                        .opacity(gone ? (lifting ? 0.25 : 0) : 1)
                        // Room above for the sticks just taken to rise and fade, inside the part, never over the prompt.
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .bottom)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!gone && !sticks.locked && (1...sticks.take).contains(takes))
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                .accessibilityHidden(gone)
                .accessibilityLabel(String(localized: "Take \(takes)", comment: "Last Stick: a stick, read by VoiceOver (takes it and the ones after it)"))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(duration: 0.3), value: hovered)
        .animation(.spring(duration: 0.45), value: sticks.left)
        .frame(maxWidth: .infinity)
        if !sticks.locked {
            // The takes as big buttons too, each showing its sticks: the same moves as clicking the row.
            HStack(spacing: 8) {
                ForEach(1...max(1, min(sticks.take, sticks.left)), id: \.self) { n in
                    Button { model.send(.number(n)) } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) { ForEach(0..<n, id: \.self) { _ in CandyStick(color: Theme.coral).frame(width: 6, height: 18) } }
                            Text(String(localized: "Take \(n)", comment: "Last Stick: a button that takes that many sticks"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChunkyButtonStyle(kind: .secondary))
                    .disabled(model.pending != nil)
                }
            }
            .padding(.top, 6)
        }
    }

    /// Candy stripes; the companion's lesson tints its groups of four in turn and lights the sticks to take.
    private func stickColor(group: Int?, hint: Bool) -> Color {
        if hint { return Theme.sun }
        if let group { return group.isMultiple(of: 2) ? Theme.accent : PadsView.color(.purple) }
        return Theme.coral
    }
}

/// Balloons or hearts left: balloons are Sidefolk's picture tinted one colour each, bobbing a little; the ones lost
/// shrink to faint grey (a heart's outline), the count beside them.
struct LivesView: View {
    var lives: GameBoard.Lives

    var body: some View {
        HStack(alignment: .bottom, spacing: lives.symbol == .balloon ? 2 : 4) {
            ForEach(0..<lives.total, id: \.self) { i in
                let kept = i < lives.left
                if lives.symbol == .balloon, GameArt.balloon.image != nil {
                    GameArt.balloon.tinted(kept ? Self.hue(i) : Theme.inkFaint, height: 30)
                        .opacity(kept ? 1 : 0.3)
                        .scaleEffect(kept ? 1 : 0.6, anchor: .bottom)
                        .rotationEffect(.degrees(kept ? Double(i % 3 - 1) * 5 : 0), anchor: .bottom)
                } else {
                    Image(systemName: lives.symbol == .balloon ? (kept ? "balloon.fill" : "balloon") : (kept ? "heart.fill" : "heart"))
                        .font(.system(size: 18))
                        .foregroundStyle(kept ? Self.hue(i) : Theme.inkFaint.opacity(0.5))
                        .scaleEffect(kept ? 1 : 0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(duration: 0.35, bounce: 0.5), value: lives.left)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(lives.left) of \(lives.total) left", comment: "A game's lives (balloons), read by VoiceOver"))
    }

    static func hue(_ i: Int) -> Color { [Theme.coral, Theme.sun, PadsView.color(.blue), PadsView.color(.green), PadsView.color(.purple)][i % 5] }
}

/// A candy stick: its colour with white stripes across, lit from the left, a small shadow.
struct CandyStick: View {
    var color: Color

    var body: some View {
        Capsule().fill(color)
            .overlay(CandyStripes().fill(.white.opacity(0.55)).clipShape(Capsule()))
            .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: .black.opacity(0.18), radius: 1.5, x: 1, y: 2)
    }
}

/// Slanted bands every 9 points.
nonisolated struct CandyStripes: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            var y = r.minY - r.width
            while y < r.maxY {
                p.move(to: CGPoint(x: r.minX, y: y + r.width))
                p.addLine(to: CGPoint(x: r.maxX, y: y))
                p.addLine(to: CGPoint(x: r.maxX, y: y + 3.5))
                p.addLine(to: CGPoint(x: r.minX, y: y + r.width + 3.5))
                p.closeSubpath()
                y += 9
            }
        }
    }
}
