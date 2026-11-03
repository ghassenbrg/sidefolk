import AppKit
import CoreImage
import QuickLookThumbnailing
import SidefolkCore
import SwiftUI

/// What a file brings to the card made for it (D150): a frost from its picture, or from the extension's icon when the picture has no
/// colour or there is none. The picture is the person's: it comes from the system's own thumbnail service, out of process, stays
/// in memory for the card's life, and never reaches the extension.
nonisolated struct FileFrost: @unchecked Sendable {
    var frost: NSImage
    var scrim: Double
    /// Shown on the small sheet, only when it's colourful. Otherwise the extension's mark says what kind of file this is.
    var picture: NSImage?

    /// No picture and no icon, or still on the way: quiet, and readable.
    static let plain = FileFrost(frost: NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
        NSColor(white: 0.16, alpha: 1).setFill()
        rect.fill()
        return true
    }, scrim: 0, picture: nil)

    /// What snapshots show, since a contact sheet can't wait for the thumbnail service.
    @MainActor static var preset: [String: FileFrost] = [:]

    private static let side = 256
    /// A file the service can't draw soon enough gets the fallback, and the card still works.
    private static let patience: Duration = .seconds(2)

    static func load(path: String, icon: String?) async -> FileFrost {
        if let preset = await MainActor.run(body: { Self.preset[path] }) { return preset }
        let picture = await thumbnail(of: URL(fileURLWithPath: path))
        return await Task.detached(priority: .userInitiated) { make(picture: picture, icon: icon) }.value
    }

    static func make(picture: NSImage?, icon: String?) -> FileFrost {
        if let picture, let frosted = blurred(picture, saturation: 1.15), let pixels = samples(frosted), FrostMeasure.hasColour(pixels) {
            return FileFrost(frost: frosted, scrim: FrostMeasure.scrim(pixels), picture: picture)
        }
        guard let icon, let image = NSImage(contentsOfFile: icon), let frosted = blurred(image, saturation: 0.55), let pixels = samples(frosted) else { return plain }
        return FileFrost(frost: frosted, scrim: FrostMeasure.scrim(pixels), picture: nil)
    }

    private static func thumbnail(of url: URL) async -> NSImage? {
        let asked = Asked(request: QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail))
        let clock = Task {
            try? await Task.sleep(for: patience)
            QLThumbnailGenerator.shared.cancel(asked.request)
        }
        defer { clock.cancel() }
        guard let drawn = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: asked.request) else { return nil }
        return NSImage(cgImage: drawn.cgImage, size: NSSize(width: drawn.cgImage.width, height: drawn.cgImage.height))
    }

    private struct Asked: @unchecked Sendable { var request: QLThumbnailGenerator.Request }

    /// A real blur, once, into a small image that's cheap to draw large. It keeps only the broad shapes, and what is measured is what is shown.
    private static func blurred(_ image: NSImage, saturation: Double) -> NSImage? {
        let size = CGSize(width: side, height: side)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cg)
        input = input.transformed(by: CGAffineTransform(scaleX: size.width / input.extent.width, y: size.height / input.extent.height))
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 44)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation]).cropped(to: CGRect(origin: .zero, size: size))
        guard let done = CIContext().createCGImage(output, from: CGRect(origin: .zero, size: size)) else { return nil }
        return NSImage(cgImage: done, size: size)
    }

    private static func samples(_ image: NSImage) -> [FrostMeasure.Pixel]? {
        let count = 28
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: count, height: count, bitsPerComponent: 8, bytesPerRow: count * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: count, height: count))
        guard let data = context.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: count * count * 4)
        return (0..<count * count).map { (Double(p[$0 * 4]) / 255, Double(p[$0 * 4 + 1]) / 255, Double(p[$0 * 4 + 2]) / 255) }
    }
}

/// White and neutrals only on a frost: bars, tags, lines and labels are never sampled from the picture (D150's rule of restraint).
enum FrostInk {
    static let text = Color.white
    static let muted = Color.white.opacity(0.92)
    static let line = Color.white.opacity(0.12)
}

/// The frost behind a card, loaded for its file. Sidefolk draws it; the extension gets nothing from it.
struct FrostGround: View {
    var frost: FileFrost
    var radius: CGFloat = Theme.Radius.card

    var body: some View {
        Rectangle().fill(.black)
            .overlay { Image(nsImage: frost.frost).resizable().interpolation(.high).scaledToFill() }
            .overlay { Color.black.opacity(frost.scrim) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Loads a file's frost and gives it to `content`, the plain one until it's there.
struct FrostLoader<Content: View>: View {
    var path: String?
    var icon: String?
    @ViewBuilder var content: (FileFrost) -> Content
    @State private var frost = FileFrost.plain

    var body: some View {
        content(frost).task(id: path) {
            guard let path else { return }
            frost = await FileFrost.load(path: path, icon: icon)
        }
    }
}

/// A sheet with a folded corner.
nonisolated struct SheetShape: Shape {
    var fold: CGFloat = 0.3

    func path(in r: CGRect) -> Path {
        let c = min(r.width, r.height) * 0.14, f = min(r.width, r.height) * fold
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + f))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private nonisolated struct FoldShape: Shape {
    var fold: CGFloat = 0.3

    func path(in r: CGRect) -> Path {
        let f = min(r.width, r.height) * fold
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - f, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY + f))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + f))
        p.closeSubpath()
        return p
    }
}

/// A file as a small sheet: its own picture, or the extension's mark for its kind, or an empty sheet.
struct FileSheet: View {
    var frost: FileFrost
    var mark: NSImage?
    var side: CGFloat

    var body: some View {
        Group {
            if let picture = frost.picture {
                Image(nsImage: picture).resizable().scaledToFill().frame(width: side, height: side * 1.22).clipped()
                    .clipShape(SheetShape())
                    .overlay { FoldShape().fill(.white.opacity(0.92)) }
                    .overlay { SheetShape().stroke(.white.opacity(0.5), lineWidth: 0.5) }
            } else if let mark {
                Image(nsImage: mark).resizable().scaledToFit().frame(width: side * 1.3, height: side * 1.3)
            } else {
                SheetShape().fill(.white.opacity(0.14)).frame(width: side, height: side * 1.22)
                    .overlay { SheetShape().stroke(.white.opacity(0.35), lineWidth: 0.5) }
            }
        }
        .accessibilityHidden(true)
    }
}
