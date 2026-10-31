import AppKit
import SidefolkCore
import SwiftUI

/// What the companion drew, in the air above it (D44, amended; redrawn for D75): a coin with the companion's own face
/// flicked high and wobbling to a stop, dice thrown onto a tray, or two hands that clash. Everything is drawn here in
/// code and lands on the result core already drew; the objects are the heroes, and the result is a chip under them.
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

    /// How long a coin wobbles or dice slide after they touch down.
    static let settle: TimeInterval = 0.6

    var resting: Bool { landed || still }

    /// 0 at the throw, 1 at the landing, up to 1 + settle/flight once it has stopped; below 0 still in its paws.
    func progress(at date: Date) -> Double {
        guard !landed, !still else { return 1 + Self.settle / flight }
        return min(date.timeIntervalSince(start) / flight, 1 + Self.settle / flight)
    }
}

struct TossStage: View {
    var show: TossShow
    /// The companion's own name, under its hand.
    var companionLabel: String
    /// Its face, embossed on the coin's heads.
    var face: NSImage?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: show.resting)) { timeline in
            let t = show.progress(at: timeline.date)
            Group {
                switch show.toss {
                case .coins(let flips, _): coins(flips, t)
                case .dice(let sides, let rolls, _): dice(sides, rolls, t)
                case .hands(let person, let companion):
                    HandsClash(you: person, companion: companion, p: Self.clash(t, show), companionName: companionLabel)
                        .frame(width: 260, height: 118)
                }
            }
        }
    }

    /// The clash's own progress: the pumping and flying in take the flight, the outcome the settling after it.
    static func clash(_ t: Double, _ show: TossShow) -> Double {
        if show.resting { return 1 }
        if t < 1 { return max(0, t) * 0.62 }
        return 0.62 + 0.38 * min(1, (t - 1) * show.flight / TossShow.settle)
    }

    // MARK: Coins

    private func coins(_ flips: [Bool], _ t: Double) -> some View {
        let air = !show.resting && t < 1
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(flips.enumerated()), id: \.offset) { i, heads in
                // Each lands 120 ms after the one before, and turns a different number of times, so several fan out.
                let lag = Double(i) * 0.12 / show.flight
                let p = min(max(t - lag, 0), 1 + TossShow.settle / show.flight)
                let flying = min(p, 1)
                let turns = Double(5 + i % 3)
                let eased = 1 - pow(1 - flying, 2)
                let angle = Double.pi * (2 * turns * eased + (heads ? 0 : eased))
                let lift = 4 * flying * (1 - flying) * 150
                // Touching down: a real coin's wobble, quick then slower, then still.
                let after = max(0, (p - 1) * show.flight / TossShow.settle)
                let wobble = p >= 1 ? 0.28 * exp(-after * 4) * abs(sin(after * 7 * .pi)) : 0
                let squash = p < 1 ? max(abs(cos(angle)), 0.08) : 1 - wobble
                CoinFace(heads: p < 1 ? cos(angle) >= 0 : heads, face: face, edge: 1 - squash)
                    .frame(width: 48, height: 48)
                    .scaleEffect(x: 1, y: squash)
                    .offset(y: -lift)
                    .opacity(t < lag ? 0 : 1)
            }
        }
        .frame(height: air ? 196 : 52, alignment: .bottom)
    }

    // MARK: Dice

    private func dice(_ sides: Int, _ rolls: [Int], _ t: Double) -> some View {
        let size: CGFloat = rolls.count > 5 ? 30 : 36
        let rows = stride(from: 0, to: rolls.count, by: 5).map { Array(rolls.indices)[$0..<min($0 + 5, rolls.count)] }
        let width = max(200, CGFloat(min(rolls.count, 5)) * (size + 12) + 40)
        let trayHeight = CGFloat(rows.count) * (size + 8) + 26
        return ZStack(alignment: .bottom) {
            // The tray they land on: felt green, or the accent on a dark desktop.
            DiceTray().frame(width: width, height: trayHeight)
                .opacity(t < 0 ? 0 : min(1, (t + 0.3) * 3))
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row), id: \.self) { i in die(i, sides: sides, roll: rolls[i], size: size, t: t) }
                    }
                }
            }
            .padding(.bottom, 13)
        }
        // Room on each side for the dice sliding in, so none is cut at the panel's edge.
        .frame(width: width + 130, height: show.resting ? trayHeight + 4 : trayHeight + 84, alignment: .bottom)
    }

    private func die(_ i: Int, sides: Int, roll: Int, size: CGFloat, t: Double) -> some View {
        let p = min(max(t, 0), 1)
        let eased = 1 - pow(1 - p, 3)
        // Two bounces on the felt, then a slide to rest.
        let first = p / 0.55, second = (p - 0.55) / 0.25
        let bounce = p < 0.55 ? 4 * first * (1 - first) * 70 : p < 0.8 ? 4 * second * (1 - second) * 16 : 0
        let slide = (1 - eased) * (i.isMultiple(of: 2) ? -60 : 60)
        let face = p < 1 ? Self.tumbling(i, p, sides) : roll
        return DieView(sides: sides, value: face)
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees((1 - eased) * 720), axis: (x: 1, y: i.isMultiple(of: 2) ? 1 : -1, z: 0.3), perspective: 0.6)
            .offset(x: slide, y: -bounce)
            .opacity(t < 0 ? 0 : 1)
            .overlay(alignment: .topTrailing) {
                // A natural 20 glints gold.
                if show.resting, sides == 20, roll == 20 {
                    Image(systemName: "sparkle").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.sun).offset(x: 7, y: -7)
                }
            }
    }

    /// A face for die `i` at this moment of its tumble: changes about every 70 ms, the same on every redraw.
    private static func tumbling(_ i: Int, _ t: Double, _ sides: Int) -> Int {
        let frame = Int(t * 15)
        return (frame &* 7919 &+ i &* 104_729) % sides + 1
    }
}

/// The result under the objects, large: "Heads!", or a dice total with its sum beside it.
struct TossChip: View {
    var toss: Toss

    /// A hand won or lost, a coin called right or wrong (`GameVerdict`); dice and an uncalled coin mean nothing either way.
    private var verdict: GameVerdict? { GameVerdict(toss) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let verdict {
                Image(systemName: verdict.symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(GameColors.color(verdict))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            switch toss {
            case .dice(_, let rolls, let modifier) where rolls.count > 1 || modifier != 0:
                Text(verbatim: Toss.number(rolls.reduce(0, +) + modifier)).font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(verbatim: Self.parts(rolls, modifier)).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            case .hands:
                Text(verbatim: toss.result).font(.system(size: 15, weight: .bold, design: .rounded))
            default:
                Text(verbatim: toss.result).font(.system(size: 22, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background {
            // As the line above it is drawn, so the two read as one family.
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
                .strokeBorder(verdict.map { GameColors.color($0).opacity(0.7) } ?? Theme.line, lineWidth: verdict == nil ? 1 : 2)
        }
    }

    /// "5 + 3 + 1": the sum without its total.
    static func parts(_ rolls: [Int], _ modifier: Int) -> String {
        let sum = Toss.sum(rolls, modifier, Toss.number)
        return String(sum[..<(sum.range(of: " = ")?.lowerBound ?? sum.endIndex)])
    }
}

/// The felt tray dice land on, a little deeper on a dark desktop.
struct DiceTray: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let felt = scheme == .dark ? Color(hex: 0x23704A) : Color(hex: 0x2F8F5B)
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [felt.opacity(0.85), felt], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: 0x6B4A2B), lineWidth: 5))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1).padding(5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

// MARK: The objects

/// A gold coin: heads is the companion's own face embossed in gold, tails its folk mark (a star). `edge` (0–1) is how
/// edge-on it is turned, which shows the rim's thickness.
struct CoinFace: View {
    var heads: Bool
    var face: NSImage? = nil
    var edge: Double = 0
    private static let gold = Color(hex: 0xFFC93C), rim = Color(hex: 0xE0A21E), ink = Color(hex: 0x8A5A00)

    var body: some View {
        ZStack {
            // The rim's thickness, below the face when it is turned.
            Circle().fill(Self.ink.opacity(0.85)).offset(y: 3 * edge + 1)
            Circle().fill(LinearGradient(colors: [Self.gold, Self.rim], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Self.rim, lineWidth: 3)
            Circle().inset(by: 6).strokeBorder(Self.ink.opacity(0.28), lineWidth: 1)
            if heads, let face {
                Image(nsImage: face).resizable().scaledToFill()
                    .saturation(0).colorMultiply(Self.gold)
                    .clipShape(Circle()).padding(8)
                    .overlay(Circle().inset(by: 8).strokeBorder(Self.ink.opacity(0.4), lineWidth: 1))
            } else {
                Canvas { context, size in Self.mark(heads: heads, in: &context, side: size.width) }
            }
            // A shine that sweeps across the face as it turns.
            Circle().fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.5), .white.opacity(0)],
                                         startPoint: UnitPoint(x: edge - 0.2, y: 0), endPoint: UnitPoint(x: edge + 0.4, y: 1)))
                .blendMode(.plusLighter)
        }
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }

    /// A smile for heads when there is no face to emboss, a star for tails: nothing on it reads as a letter or a number.
    private static func mark(heads: Bool, in context: inout GraphicsContext, side s: CGFloat) {
        if heads {
            for x in [0.38, 0.62] {
                context.fill(Path(ellipseIn: CGRect(x: s * x - s * 0.045, y: s * 0.38, width: s * 0.09, height: s * 0.11)), with: .color(ink))
            }
            var smile = Path()
            smile.addArc(center: CGPoint(x: s / 2, y: s * 0.52), radius: s * 0.14, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
        } else {
            var star = Path()
            for i in 0..<10 {
                let a = Double(i) * .pi / 5 - .pi / 2, r = s * (i.isMultiple(of: 2) ? 0.24 : 0.1)
                let point = CGPoint(x: s / 2 + r * cos(a), y: s * 0.52 + r * sin(a))
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            context.fill(star, with: .color(ink))
        }
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
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.face)
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: 0x0F2D5B).opacity(0.18), lineWidth: 1)
            Canvas { context, size in
                let step = size.width * 0.27, dot = size.width * 0.17
                for (x, y) in Self.pips[value] ?? [] {
                    let c = CGPoint(x: size.width / 2 + CGFloat(x - 1) * step, y: size.height / 2 + CGFloat(y - 1) * step)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)), with: .color(Self.pip))
                }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
    }
}

/// A die with other than six sides, as its real silhouette with the number on top: a triangle for a d4, a diamond for
/// a d8, a kite for a d10, a pentagon for a d12, an icosahedron's outline for a d20, a gem for anything else.
struct Polyhedron: View {
    var sides: Int
    var value: Int

    private var color: Color {
        switch sides {
        case 4: Color(hex: 0x4F7DF3)
        case 8: Color(hex: 0x2BB3A3)
        case 10: Color(hex: 0xA77BF3)
        case 12: Color(hex: 0xFF8A3D)
        case 20: Color(hex: 0x7C5CE0)
        default: Color(hex: 0x5B6B85)
        }
    }

    var body: some View {
        ZStack {
            DieOutline(sides: sides).fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom))
            DieOutline(sides: sides).stroke(.black.opacity(0.2), lineWidth: 1)
            if sides == 20 { DieFacets().stroke(.white.opacity(0.35), lineWidth: 1) }
            Text(verbatim: Toss.number(value)).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.5).lineLimit(1).padding(sides == 4 ? 9 : 6).offset(y: sides == 4 ? 4 : 0)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
    }
}

nonisolated struct DieOutline: Shape {
    var sides: Int

    func path(in rect: CGRect) -> Path {
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        let points: [CGPoint] = switch sides {
        case 4: [at(0.5, 0.04), at(0.97, 0.9), at(0.03, 0.9)]
        case 8: [at(0.5, 0.02), at(0.95, 0.5), at(0.5, 0.98), at(0.05, 0.5)]
        case 10: [at(0.5, 0.02), at(0.96, 0.42), at(0.5, 0.98), at(0.04, 0.42)]
        case 12: (0..<5).map { i in at(0.5 + 0.48 * cos(Double(i) * 2 * .pi / 5 - .pi / 2), 0.54 + 0.48 * sin(Double(i) * 2 * .pi / 5 - .pi / 2)) }
        default: (0..<6).map { i in at(0.5 + 0.49 * cos(Double(i) * .pi / 3 - .pi / 2), 0.5 + 0.49 * sin(Double(i) * .pi / 3 - .pi / 2)) }
        }
        return Path { p in
            p.addLines(points)
            p.closeSubpath()
        }
    }
}

/// The front triangle of an icosahedron inside its hexagon.
nonisolated struct DieFacets: Shape {
    func path(in rect: CGRect) -> Path {
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        return Path { p in
            p.addLines([at(0.5, 0.22), at(0.8, 0.7), at(0.2, 0.7), at(0.5, 0.22)])
            for (from, to) in [(at(0.5, 0.22), at(0.5, 0.01)), (at(0.8, 0.7), at(0.92, 0.75)), (at(0.2, 0.7), at(0.08, 0.75))] {
                p.move(to: from)
                p.addLine(to: to)
            }
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
