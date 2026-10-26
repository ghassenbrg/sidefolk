import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SidefolkCharacter

/// Pose art is measured, not assumed: any pixel size, PNG or WebP, feet on the floor line.
@MainActor @Suite struct SpriteSetTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test(arguments: ["mochi", "spark"])
    func bundledCompanionsLoad(_ name: String) throws {
        let art = try #require(SpriteSet(folder: Self.repo.appendingPathComponent("Resources/Companions/\(name)")))
        #expect(art.name == name)
        #expect(abs(art.restingFrame.height - SpriteSet.height) < 0.01)
        #expect(art.restingFrame.minY == Canvas.floor)
        #expect(abs(art.restingFrame.midX - Canvas.pivot.x) < 6)
        for pose in SpritePose.allCases {
            let image = art.image(pose)
            #expect(image.width == 400 && image.height == 400, "\(pose)")
        }
    }

    @Test func missingPoseMeansNotOffered() throws {
        let folder = try Self.folder { pose in pose == .sad ? nil : Self.figure(width: 300, height: 400, body: CGRect(x: 100, y: 50, width: 100, height: 300)) }
        #expect(SpriteSet(folder: folder) == nil)
    }

    @Test func pngWinsOverWebP() throws {
        let folder = try Self.folder { _ in Self.figure(width: 200, height: 200, body: CGRect(x: 50, y: 20, width: 100, height: 160)) }
        // A WebP-named file that is not even an image: if it were read, idle would fail to load.
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("idle.webp"))
        #expect(SpriteSet(folder: folder) != nil)
    }

    @Test func posesOfAnySizeShareScaleAndBaseline() throws {
        // Idle: 300 px tall in a 400×500 image. Sit: half as tall, drawn in a 1000×800 image with
        // a different margin under the feet. Same pixel scale, so sit shows half as tall.
        let folder = try Self.folder { pose in
            switch pose {
            case .sit: Self.figure(width: 1000, height: 800, body: CGRect(x: 600, y: 500, width: 100, height: 150))
            default: Self.figure(width: 400, height: 500, body: CGRect(x: 150, y: 120, width: 100, height: 300))
            }
        }
        let art = try #require(SpriteSet(folder: folder))
        let idle = art.silhouette(.idle).boundingBoxOfPath
        let sit = art.silhouette(.sit).boundingBoxOfPath
        #expect(abs(idle.minY - Canvas.floor) <= 2)
        #expect(abs(sit.minY - Canvas.floor) <= 2)
        #expect(abs(idle.height - SpriteSet.height) <= 3)
        #expect(abs(sit.height - SpriteSet.height / 2) <= 3)
        #expect(abs(sit.midX - Canvas.pivot.x) <= 2)
        #expect(abs(idle.midX - Canvas.pivot.x) <= 2)
    }

    @Test func faintPixelsDoNotCatchClicks() throws {
        // A solid body with a wide halo at 20% alpha around it: only the body counts.
        let folder = try Self.folder { _ in
            Self.figure(width: 400, height: 400, body: CGRect(x: 150, y: 50, width: 100, height: 300),
                        halo: CGRect(x: 50, y: 50, width: 300, height: 300))
        }
        let art = try #require(SpriteSet(folder: folder))
        let shape = art.silhouette(.idle)
        let frame = art.restingFrame
        #expect(shape.contains(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(!shape.contains(CGPoint(x: frame.minX - 20, y: frame.midY)))
        #expect(abs(frame.width - SpriteSet.height / 3) <= 3)
    }

    // MARK: Fixtures

    /// A temporary companion folder with one PNG per pose (nil leaves the pose out).
    static func folder(_ make: (SpritePose) -> CGImage?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pose in SpritePose.allCases {
            guard let image = make(pose) else { continue }
            let url = dir.appendingPathComponent("\(pose.rawValue).png")
            let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
        return dir
    }

    /// A transparent image with an opaque rectangle `body` (pixels from the top-left) and an optional faint halo.
    static func figure(width: Int, height: Int, body: CGRect, halo: CGRect? = nil) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func flipped(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height) }
        if let halo {
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.8, blue: 0.4, alpha: 0.2))
            context.fill(flipped(halo))
        }
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.8, alpha: 1))
        context.fill(flipped(body))
        return context.makeImage()!
    }
}
