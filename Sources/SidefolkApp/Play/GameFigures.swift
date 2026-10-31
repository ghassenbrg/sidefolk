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

    /// The Mac account's picture, read once from the local directory; nil when it has none.
    @MainActor static let accountPicture: NSImage? = {
        guard let identity = CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.local()) as? CBUserIdentity else { return nil }
        return identity.image
    }()
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

/// The companion in the scene, peeking over what stands in front of it: drawn `width` across from the top, `share`
/// of its height showing (its head and shoulders, whatever its shape), the rest left to the table drawn after it.
struct CompanionPeek: View {
    var picture: NSImage?
    var width: CGFloat
    var share: CGFloat = 0.62
    @State private var bob = false

    var body: some View {
        if let picture = GameFigures.trim(picture) {
            let height = width * picture.size.height / max(picture.size.width, 1)
            Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
                .offset(y: bob ? -2 : 1)
                .frame(width: width, height: height * share, alignment: .top)
                .onAppear {
                    guard !GameMotion.reduced else { return }
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
                }
                .accessibilityHidden(true)
        }
    }
}
