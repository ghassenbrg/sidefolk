import AppKit
import ImageIO
import SidefolkCharacter
import UniformTypeIdentifiers

/// `--antics <dir>`: every moment of life as a frame strip (one sheet per companion) and as a GIF
/// (one per moment), rendered offscreen from the same numbers the live animations play.
@MainActor
enum AnticSheets {
    static let strip = 8
    static let fps = 25.0

    static func write(to dir: URL, looks: [(id: String, name: String, look: CharacterLook)]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (id, name, look) in looks {
            let side: CGFloat = 130
            var items: [(String, () -> CGImage)] = []
            for antic in CharacterAntic.allCases {
                let frames = CharacterRenderer.frames(of: antic, count: strip, size: CGSize(width: side, height: side), scale: Sheets.scale,
                                                      look: look)
                for (i, frame) in frames.enumerated() {
                    items.append(("\(antic.rawValue) \(i + 1)/\(strip)", { frame }))
                }
            }
            for posture in CharacterPosture.allCases {
                items.append(("posture: \(posture.rawValue)", {
                    CharacterRenderer.image(state: .idle, size: CGSize(width: side, height: side), scale: Sheets.scale, look: look,
                                            posture: posture)
                }))
            }
            save(Sheets.sheet(title: "\(name): moments of life, \(strip) frames each (left to right), then postures",
                              columns: strip, cell: CGSize(width: 140, height: 150), items: items),
                 dir.appendingPathComponent("antics-\(id).png"))

            let gifs = dir.appendingPathComponent("antics-\(id)", isDirectory: true)
            try? FileManager.default.createDirectory(at: gifs, withIntermediateDirectories: true)
            for antic in CharacterAntic.allCases {
                let count = Int(CharacterRenderer.duration(of: antic) * fps) + 1
                let frames = CharacterRenderer.frames(of: antic, count: count, size: CGSize(width: 160, height: 160), scale: 2, look: look)
                // Hold the rest pose a moment so the loop reads as one moment, not a twitch.
                let held = frames + Array(repeating: frames[frames.count - 1], count: Int(fps * 0.5))
                writeGIF(held.map(onPaper), delay: 1 / fps, to: gifs.appendingPathComponent("\(antic.rawValue).gif"))
            }
            print("wrote \(name)'s moments to \(dir.path)")
        }
    }

    /// GIF has one-bit transparency: put each frame on the sheets' paper.
    static func onPaper(_ image: CGImage) -> CGImage {
        let size = CGSize(width: CGFloat(image.width) / Sheets.scale, height: CGFloat(image.height) / Sheets.scale)
        return Sheets.draw(size) { context in
            Sheets.paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            fatalError("cannot write \(url.path)")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        frames.forEach { CGImageDestinationAddImage(dest, $0, frame) }
        guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
    }
}
