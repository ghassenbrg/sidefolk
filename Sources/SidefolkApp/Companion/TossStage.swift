import SidefolkCore
import SwiftUI

/// What the companion drew, in the air above it (D44, amended): coins spinning, dice tumbling, or two hands for rock,
/// paper, scissors. Everything is drawn here in code and lands on the result core already drew.
struct TossShow: Equatable {
    var toss: Toss
    /// When the objects leave the companion's paws (for hands: when the fists start pumping), and how long until they land.
    var start: Date
    var flight: TimeInterval
    /// Reduce Motion: the result at once, nothing spinning.
    var still: Bool
    /// Landed: the frame no longer changes, so the timeline stops and the room it flew in folds away, bringing the
    /// words down onto the result.
    var landed = false

    var resting: Bool { landed || still }

    /// 0 at the throw, 1 at the landing; below 0 the objects are still in its paws.
    func progress(at date: Date) -> Double {
        guard !landed, !still else { return 1 }
        return min(date.timeIntervalSince(start) / flight, 1)
    }
}

struct TossStage: View {
    var show: TossShow
    /// The companion's own name, under its hand.
    var companionLabel: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: show.resting)) { timeline in
            let t = show.progress(at: timeline.date)
            Group {
                switch show.toss {
                case .coins(let flips): coins(flips, t)
                case .dice(let sides, let rolls, _): dice(sides, rolls, t)
                case .hands(let person, let companion): hands(person, companion, t)
                }
            }
        }
    }

    // MARK: Coins

    private func coins(_ flips: [Bool], _ t: Double) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(flips.enumerated()), id: \.offset) { i, heads in
                // Each coin turns a different number of times, so several don't spin as one.
                let turns = Double(4 + i % 3)
                let eased = 1 - pow(1 - max(t, 0), 2)
                let angle = Double.pi * (2 * turns * eased + (heads ? 0 : eased))
                let lift = 4 * max(t, 0) * (1 - max(t, 0)) * 74
                CoinFace(heads: cos(angle) >= 0)
                    .frame(width: 34, height: 34)
                    .scaleEffect(x: 1, y: max(abs(cos(angle)), 0.08))
                    .offset(y: -lift)
                    .opacity(t < 0 ? 0 : 1)
            }
        }
        .frame(height: show.resting ? 36 : 112, alignment: .bottom)
    }

    // MARK: Dice

    private func dice(_ sides: Int, _ rolls: [Int], _ t: Double) -> some View {
        let size: CGFloat = rolls.count > 5 ? 26 : 30
        let rows = stride(from: 0, to: rolls.count, by: 5).map { Array(rolls.indices)[$0..<min($0 + 5, rolls.count)] }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row), id: \.self) { i in
                        let p = max(t, 0)
                        let eased = 1 - pow(1 - p, 3)
                        // Until it lands a die shows a face a moment at a time, as a tumbling one does.
                        let face = p < 1 ? Self.tumbling(i, p, sides) : rolls[i]
                        Group {
                            if sides == 6 { DieFace(value: face) } else { NumberToken(value: face) }
                        }
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees((1 - eased) * 540 * (i.isMultiple(of: 2) ? 1 : -1)))
                        .offset(y: -4 * p * (1 - p) * 46)
                        .opacity(t < 0 ? 0 : 1)
                    }
                }
            }
        }
        .frame(height: show.resting ? CGFloat(rows.count) * (size + 6) : rows.count > 1 ? 110 : 80, alignment: .bottom)
    }

    /// A face for die `i` at this moment of its tumble: changes about every 70 ms, the same on every redraw.
    private static func tumbling(_ i: Int, _ t: Double, _ sides: Int) -> Int {
        let frame = Int(t * 15)
        return (frame &* 7919 &+ i &* 104_729) % sides + 1
    }

    // MARK: Hands

    private func hands(_ person: Hand, _ companion: Hand, _ t: Double) -> some View {
        let shown = t >= 1
        // Three pumps on the way: the fists bounce, then the hands open.
        let bounce = shown ? 0 : abs(sin(max(t, 0) * 3 * .pi)) * 10
        let personWins = person.beats == companion, companionWins = companion.beats == person
        return HStack(alignment: .bottom, spacing: 26) {
            hand(shown ? person : .rock, label: String(localized: "You", comment: "Under the person's hand in rock, paper, scissors"),
                 won: shown && personWins, lost: shown && companionWins, bounce: bounce)
            hand(shown ? companion : .rock, label: companionLabel, won: shown && companionWins, lost: shown && personWins, bounce: bounce)
        }
        .frame(height: 78, alignment: .bottom)
    }

    private func hand(_ hand: Hand, label: String, won: Bool, lost: Bool, bounce: Double) -> some View {
        VStack(spacing: 3) {
            HandShape(hand: hand)
                .frame(width: 42, height: 42)
                .background { if won { Circle().fill(Theme.folkColor("play").opacity(0.18)).frame(width: 54, height: 54) } }
                .scaleEffect(won ? 1.12 : 1)
                .offset(y: -bounce)
            Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .opacity(lost ? 0.55 : 1)
    }
}

// MARK: The objects

/// A gold coin: a little face on heads, a curled tail on tails.
struct CoinFace: View {
    var heads: Bool
    private static let gold = Color(hex: 0xFFC93C), rim = Color(hex: 0xE0A21E), ink = Color(hex: 0x8A5A00)

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Self.gold, Self.rim], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Self.rim, lineWidth: 2.5)
            Circle().inset(by: 5).strokeBorder(Self.ink.opacity(0.25), lineWidth: 1)
            Canvas { context, size in
                let s = size.width
                if heads {
                    for x in [0.38, 0.62] {
                        context.fill(Path(ellipseIn: CGRect(x: s * x - s * 0.045, y: s * 0.38, width: s * 0.09, height: s * 0.11)), with: .color(Self.ink))
                    }
                    var smile = Path()
                    smile.addArc(center: CGPoint(x: s / 2, y: s * 0.52), radius: s * 0.14, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                    context.stroke(smile, with: .color(Self.ink), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
                } else {
                    var tail = Path()
                    tail.move(to: CGPoint(x: s * 0.3, y: s * 0.68))
                    tail.addCurve(to: CGPoint(x: s * 0.62, y: s * 0.3), control1: CGPoint(x: s * 0.62, y: s * 0.72), control2: CGPoint(x: s * 0.74, y: s * 0.42))
                    tail.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.48), control1: CGPoint(x: s * 0.5, y: s * 0.2), control2: CGPoint(x: s * 0.4, y: s * 0.4))
                    context.stroke(tail, with: .color(Self.ink), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

/// A six-sided die with its pips.
struct DieFace: View {
    var value: Int
    private static let face = Color(light: 0xFFFFFF, dark: 0xF4F7FB), pip = Color(hex: 0x0F2D5B)

    /// Where the pips sit, on a 3 × 3 grid (0...2).
    private static let pips: [Int: [(Int, Int)]] = [
        1: [(1, 1)], 2: [(0, 0), (2, 2)], 3: [(0, 0), (1, 1), (2, 2)], 4: [(0, 0), (2, 0), (0, 2), (2, 2)],
        5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)], 6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.face)
            RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(hex: 0x0F2D5B).opacity(0.18), lineWidth: 1)
            Canvas { context, size in
                let step = size.width * 0.27, dot = size.width * 0.17
                for (x, y) in Self.pips[value] ?? [] {
                    let c = CGPoint(x: size.width / 2 + CGFloat(x - 1) * step, y: size.height / 2 + CGFloat(y - 1) * step)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)), with: .color(Self.pip))
                }
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// A die with other than six sides: a gem with its number.
struct NumberToken: View {
    var value: Int

    var body: some View {
        ZStack {
            Hexagon().fill(Theme.folkColor("play"))
            Hexagon().stroke(Color.black.opacity(0.15), lineWidth: 1)
            Text(verbatim: Toss.number(value)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1).padding(4)
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

nonisolated struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            for i in 0..<6 {
                let a = Double(i) * .pi / 3 - .pi / 2
                let point = CGPoint(x: rect.midX + rect.width / 2 * cos(a), y: rect.midY + rect.height / 2 * sin(a))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        }
    }
}

/// Rock, paper or scissors, as the things themselves.
struct HandShape: View {
    var hand: Hand

    var body: some View {
        Canvas { context, size in
            let s = size.width
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: s * x, y: s * y) }
            switch hand {
            case .rock:
                var stone = Path()
                stone.move(to: at(0.18, 0.62))
                stone.addCurve(to: at(0.42, 0.2), control1: at(0.12, 0.38), control2: at(0.24, 0.2))
                stone.addCurve(to: at(0.84, 0.46), control1: at(0.62, 0.18), control2: at(0.84, 0.28))
                stone.addCurve(to: at(0.56, 0.84), control1: at(0.86, 0.68), control2: at(0.74, 0.84))
                stone.addCurve(to: at(0.18, 0.62), control1: at(0.36, 0.86), control2: at(0.2, 0.78))
                context.fill(stone, with: .color(Color(hex: 0x98A2B3)))
                context.stroke(stone, with: .color(Color(hex: 0x6B7588)), lineWidth: 1.2)
                var shine = Path()
                shine.addArc(center: at(0.42, 0.42), radius: s * 0.12, startAngle: .degrees(190), endAngle: .degrees(260), clockwise: false)
                context.stroke(shine, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
            case .paper:
                var sheet = Path()
                sheet.move(to: at(0.24, 0.12))
                sheet.addLine(to: at(0.62, 0.12))
                sheet.addLine(to: at(0.78, 0.28))
                sheet.addLine(to: at(0.78, 0.88))
                sheet.addLine(to: at(0.24, 0.88))
                sheet.closeSubpath()
                context.fill(sheet, with: .color(.white))
                context.stroke(sheet, with: .color(Color(hex: 0x0F2D5B).opacity(0.35)), lineWidth: 1.2)
                var fold = Path()
                fold.move(to: at(0.62, 0.12))
                fold.addLine(to: at(0.62, 0.28))
                fold.addLine(to: at(0.78, 0.28))
                context.stroke(fold, with: .color(Color(hex: 0x0F2D5B).opacity(0.35)), lineWidth: 1.2)
                for y in [0.44, 0.56, 0.68, 0.8] {
                    var line = Path()
                    line.move(to: at(0.34, y))
                    line.addLine(to: at(y == 0.8 ? 0.54 : 0.68, y))
                    context.stroke(line, with: .color(Color(hex: 0x93C5FD)), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
                }
            case .scissors:
                let steel = Color(hex: 0x9AA8BF), handle = Color(hex: 0xFF7B6B)
                for (from, to) in [(at(0.34, 0.6), at(0.8, 0.12)), (at(0.66, 0.6), at(0.2, 0.12))] {
                    var blade = Path()
                    blade.move(to: from)
                    blade.addLine(to: to)
                    context.stroke(blade, with: .color(steel), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
                }
                for center in [at(0.3, 0.76), at(0.7, 0.76)] {
                    let ring = Path(ellipseIn: CGRect(x: center.x - s * 0.13, y: center.y - s * 0.13, width: s * 0.26, height: s * 0.26))
                    context.stroke(ring, with: .color(handle), lineWidth: s * 0.07)
                }
                context.fill(Path(ellipseIn: CGRect(x: s * 0.46, y: s * 0.4, width: s * 0.08, height: s * 0.08)), with: .color(Color(hex: 0x5B6B85)))
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
    }
}
