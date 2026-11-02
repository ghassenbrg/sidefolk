import AppKit
import Collaboration
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Who plays: the companion in the scene, in a pose from the board's cue where its look has poses (a 2D companion;
/// a 3D one has its one still), and the person on the score bar, by the Mac account's own picture when there is one.
/// The companion is always the person's own (its portrait or avatar art), never a mascot drawn for the games.
enum GameFigures {
    private static var trimmed: [ObjectIdentifier: NSImage] = [:]

    /// The pose for a board's companion cue: a mood from the fixed list (`GameCue.Move`) read as one of the states every
    /// companion is drawn in.
    static func state(for move: GameCue.Move?, over: Bool, verdict: GameVerdict?) -> CharacterState {
        if over, let verdict { return verdict == .loss ? .celebrating : verdict == .win ? .waiting : .idle }
        switch move {
        case .think, .shuffle: return .thinking
        case .cheer, .celebrate, .giggle, .dance, .hop, .spin, .tease, .accentHop, .accentSpin: return .celebrating
        case .gasp, .wince, .sweat, .dizzy: return .alert
        case .nod, .bow, .wave, .accentWave, .accentBow: return .success
        case .ready: return .listening
        case .sulk, .shrug: return .waiting
        case nil: return .idle
        }
    }

    /// The picture without its empty margins, so it can stand on the table at the size asked.
    static func trim(_ image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        if let done = trimmed[ObjectIdentifier(image)] { return done }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let box = opaqueBox(cg),
              let cut = cg.cropping(to: box) else { return image }
        let out = NSImage(cgImage: cut, size: NSSize(width: CGFloat(cut.width) / 2, height: CGFloat(cut.height) / 2))
        trimmed[ObjectIdentifier(image)] = out
        return out
    }

    private static func opaqueBox(_ cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[y * w + x] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // The bitmap's rows run bottom up in the context; CGImage cropping counts from the top.
        return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The Mac account's picture (`AccountPicture`).
    @MainActor static var accountPicture: NSImage? { AccountPicture.current }
}

/// The person on the score bar: their picture, or a friendly stand-in (a smiling face on a soft disc).
struct PlayerAvatar: View {
    var picture: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let picture {
                Image(nsImage: picture).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xFFD7A8), Color(hex: 0xFFB27A)], startPoint: .top, endPoint: .bottom))
                    Image(systemName: "face.smiling.inverse").font(.system(size: size * 0.6, weight: .regular))
                        .foregroundStyle(.white, Color(hex: 0xE58B4E))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// The companion in the scene, whole: its still (portrait or a 2D pose) fitted in a small box and standing on its
/// bottom edge, on the table or beside its bubble, with a soft shadow under it. Never cut: a tall companion (Spark)
/// fits by height, a wide one (Ember) by width. Still art only, never a live render: when `beat` changes (a new board, a
/// reaction) it hops once, 300 ms, with cheap transforms; nothing loops, so an idle game draws nothing.
struct CompanionFigure: View {
    var picture: NSImage?
    var size: CGSize
    var beat: Int = 0
    @State private var hop: CGFloat = 0

    var body: some View {
        if let picture = GameFigures.trim(picture) {
            let aspect = picture.size.width / max(picture.size.height, 1)
            let height = min(size.height, size.width / aspect), width = height * aspect
            ZStack(alignment: .bottom) {
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: width * 0.42))
                    .frame(width: width * 0.9, height: max(8, height * 0.1))
                    .offset(y: max(4, height * 0.05))
                Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
                    .scaleEffect(x: 1 - hop * 0.03, y: 1 + hop * 0.04, anchor: .bottom)
                    .offset(y: -hop * 6)
            }
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .onChange(of: beat) { _, _ in
                guard !GameMotion.reduced else { return }
                withAnimation(.easeOut(duration: 0.14)) { hop = 1 }
                withAnimation(.easeIn(duration: 0.16).delay(0.14)) { hop = 0 }
            }
            .accessibilityHidden(true)
        }
    }
}
