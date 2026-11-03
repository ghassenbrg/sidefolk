import AppKit
import CoreImage
import QuickLookThumbnailing
import SidefolkCore
import SwiftUI

/// What a file brings to the card made for it (D150): a frost from its picture, or from the extension's mark when the picture has no
/// colour or there is none. The picture is the person's: it comes from the system's own thumbnail service, out of process, stays
/// in Sidefolk's memory for the card's life (the service keeps its own cache, as it does for Finder), and never reaches the extension.
nonisolated struct FileFrost: @unchecked Sendable {
    var frost: NSImage
    var scrim: Double
    /// Shown on the small sheet, only when it's colourful. Otherwise the extension's mark says what kind of file this is.
    var picture: NSImage?

    /// No picture and no mark, or still on the way: quiet, and readable.
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

    /// `path` nil: no picture at all, for files another app sent with no click behind them (D151). `mark` is the extension's picture from
    /// its pack, already checked and capped. Never its icon: a PDF can take minutes to draw, whoever draws it.
    static func load(path: String?, mark: NSImage?) async -> FileFrost {
        if let path, let preset = await MainActor.run(body: { Self.preset[path] }) { return preset }
        var picture: NSImage?
        if let real = path.flatMap(showable) { picture = await shared(real) }
        let shown = picture
        return await Task.detached(priority: .userInitiated) { make(picture: shown, mark: mark) }.value
    }

    /// A plain file Guard wouldn't keep from anyone: never a picture of what's behind a link, or of a private place.
    private static func showable(_ path: String) -> String? {
        var info = stat()
        guard let real = FolderAccess.canonical(path), FolderAccess.forbiddenReason([real]) == nil,
              lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return real
    }

    /// Two questions: is there a picture worth showing on the sheet, and is its colour enough to frost a card with? A dull photo answers
    /// yes and no: it keeps its place on the sheet, on a frost from the mark.
    static func make(picture: NSImage?, mark: NSImage?) -> FileFrost {
        // Sharp, not averaged: small type blurred together reads as mid-grey, like a photo.
        let shown = picture.flatMap { samples($0, smooth: false) }.map(FrostMeasure.isPicture) == true ? picture : nil
        if let shown, let frosted = blurred(shown, saturation: 1.15), let pixels = samples(frosted), FrostMeasure.hasColour(pixels) {
            return FileFrost(frost: frosted, scrim: FrostMeasure.scrim(pixels), picture: shown)
        }
        guard let mark, let frosted = blurred(onDark(mark), saturation: 0.8), let pixels = samples(frosted), FrostMeasure.hasColour(pixels) else {
            return FileFrost(frost: plain.frost, scrim: plain.scrim, picture: shown)
        }
        return FileFrost(frost: frosted, scrim: FrostMeasure.scrim(pixels), picture: shown)
    }

    /// A mark has clear parts and is small: large on a dark ground, its colours reach the card's edges.
    private static func onDark(_ mark: NSImage) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor(white: 0.1, alpha: 1).setFill()
            rect.fill()
            mark.draw(in: rect.insetBy(dx: -CGFloat(side) * 0.15, dy: -CGFloat(side) * 0.15))
            return true
        }
    }

    /// One card holds several loaders for one file, and they share one request.
    @MainActor private static var asking: [String: Task<ImageBox, Never>] = [:]
    private struct ImageBox: @unchecked Sendable { var image: NSImage? }

    private static func shared(_ path: String) async -> NSImage? {
        let task = await MainActor.run { () -> Task<ImageBox, Never> in
            if let task = asking[path] { return task }
            let task = Task { () -> ImageBox in
                let image = await thumbnail(of: URL(fileURLWithPath: path))
                await MainActor.run { asking[path] = nil }
                return ImageBox(image: image)
            }
            asking[path] = task
            return task
        }
        return await task.value.image
    }

    /// First of the picture and the clock: a crafted file can keep the service drawing long after it's asked to stop, and the card
    /// doesn't wait for that.
    private static func thumbnail(of url: URL) async -> NSImage? {
        let asked = Asked(request: QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail))
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            let once = Once(continuation)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: asked.request) { drawn, _ in
                once.finish(drawn.map { NSImage(cgImage: $0.cgImage, size: NSSize(width: $0.cgImage.width, height: $0.cgImage.height)) })
            }
            Task {
                try? await Task.sleep(for: patience)
                QLThumbnailGenerator.shared.cancel(asked.request)
                once.finish(nil)
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<NSImage?, Never>?
        init(_ continuation: CheckedContinuation<NSImage?, Never>) { self.continuation = continuation }
        func finish(_ image: NSImage?) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: image)
        }
    }

    private struct Asked: @unchecked Sendable { var request: QLThumbnailGenerator.Request }

    /// A real blur, once, into a small image that's cheap to draw large. It keeps only the broad shapes, and what is measured is what is shown.
    private static func blurred(_ image: NSImage, saturation: Double) -> NSImage? {
        let size = CGSize(width: side, height: side)
        // Asked for at this size, not its own.
        var rect = CGRect(origin: .zero, size: size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cg)
        input = input.transformed(by: CGAffineTransform(scaleX: size.width / input.extent.width, y: size.height / input.extent.height))
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 44)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation]).cropped(to: CGRect(origin: .zero, size: size))
        guard let done = CIContext().createCGImage(output, from: CGRect(origin: .zero, size: size)) else { return nil }
        return NSImage(cgImage: done, size: size)
    }

    private static func samples(_ image: NSImage, smooth: Bool = true) -> [FrostMeasure.Pixel]? {
        let count = 28
        var rect = CGRect(x: 0, y: 0, width: count, height: count)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(data: nil, width: count, height: count, bitsPerComponent: 8, bytesPerRow: count * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = smooth ? .high : .none
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
    /// The extension's mark, from its pack, for when the file has no picture with colour.
    var mark: (() async -> NSImage?)?
    /// What the mark is, so a different one loads anew on the same file.
    var markKey: String?
    @ViewBuilder var content: (FileFrost) -> Content
    @State private var frost = FileFrost.plain

    var body: some View {
        content(frost).task(id: "\(path ?? "")|\(markKey ?? "")") {
            // Never another file's picture on this one's card, even for a moment.
            frost = .plain
            let image = await mark?()
            let loaded = await FileFrost.load(path: path, mark: image)
            if !Task.isCancelled { frost = loaded }
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
                Image(nsImage: mark).resizable().scaledToFit().frame(width: min(side * 1.3, 44), height: min(side * 1.3, 44))
            } else {
                SheetShape().fill(.white.opacity(0.14)).frame(width: side, height: side * 1.22)
                    .overlay { SheetShape().stroke(.white.opacity(0.35), lineWidth: 0.5) }
            }
        }
        .accessibilityHidden(true)
    }
}
