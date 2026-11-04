import AppKit
import SidefolkCore
import SwiftUI

/// What the ring is showing (D152).
@MainActor @Observable final class FileRingModel {
    var files: [String] = []
    var choices: [RingChoice] = []
    var set = 0
    var hovered: Int?
    /// Opened by the shortcut, so a click chooses. During a drag, letting go does.
    var byClick = false
    /// Only a line, no slices.
    var note: Note?
    /// The pointer's over the middle, so the line lists every name.
    var overMiddle = false

    enum Note { case nothing, tooMany }

    /// Measured larger than it's drawn and in less room than it has, so a denser theme still fits.
    static func namesFit(_ paths: [String]) -> Bool {
        let font = NSFont.systemFont(ofSize: 13.5)
        return DropChoices.namesFit(paths.map(DropChoices.shownName), within: Double(RingLayout.side) - 60) {
            Double(($0 as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    var shown: [RingChoice] { Array(choices.dropFirst(set * DropChoices.ringSet).prefix(DropChoices.ringSet)) }
    var hasMore: Bool { choices.count > DropChoices.ringSet }
    var hoveredChoice: RingChoice? { hovered.flatMap { shown.indices.contains($0) ? shown[$0] : nil } }

    func turn() {
        guard hasMore else { return }
        set = (set + 1) % 2
        hovered = nil
    }
}

nonisolated enum RingLayout {
    static let side: CGFloat = 460
    static let outer: CGFloat = 214
    static let inner: CGFloat = 76
    /// Room under the ring for Sidefolk's line.
    static let below: CGFloat = 124
    static let size = NSSize(width: side, height: side + below)
    static let gap: Double = 1.6
}

/// One slice: a ring's sector with a small gap on both sides.
private nonisolated struct SliceShape: Shape {
    var index: Int
    var count: Int

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY), step = 360 / Double(max(count, 1)), middle = Double(index) * step - 90
        let gap = count > 1 ? RingLayout.gap : 0
        // The inner edge's gap is wider in degrees, so the gap between slices keeps its width all the way in.
        let spread = count > 1 ? step / 2 : 180
        var path = Path()
        path.addArc(center: centre, radius: RingLayout.outer, startAngle: .degrees(middle - spread + gap), endAngle: .degrees(middle + spread - gap), clockwise: false)
        let inward = gap * Double(RingLayout.outer / RingLayout.inner)
        path.addArc(center: centre, radius: RingLayout.inner, startAngle: .degrees(middle + spread - inward), endAngle: .degrees(middle - spread + inward), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Dark glass, behind the window: it stays dark on any desktop, in light and dark mode alike.
private struct RingGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = RingLayout.outer
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct FileRingView: View {
    var model: FileRingModel
    var packPicture: (String, String) async -> NSImage?

    private var first: ExtensionDropAction? { model.hoveredChoice?.offer ?? model.choices.first?.offer }
    private var picture: ExtensionDropAction? { model.choices.first?.offer }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            if let note = model.note {
                Spacer(minLength: 0)
                line { noteWords(note) }
                Spacer(minLength: 0)
            } else {
                // The first extension's mark throughout, so the glass doesn't change as the pointer crosses the ring.
                FrostLoader(path: model.files.first, mark: picture?.mark.map { mark in { await packPicture(mark, picture?.extensionId ?? "") } },
                            markKey: picture?.mark.map { (picture?.extensionId ?? "") + "|" + $0 }) { frost in
                    ring(frost: frost)
                }
                .frame(width: RingLayout.side, height: RingLayout.side)
                if model.overMiddle, model.hovered == nil {
                    line {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(model.files, id: \.self) { Text(verbatim: DropChoices.shownName($0)).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                } else if let first {
                    line { trust(first) }
                }
            }
        }
        .frame(width: RingLayout.size.width, height: RingLayout.size.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private func ring(frost: FileFrost) -> some View {
        let vivid = frost.vividColour()
        let disc = RingLayout.outer * 2
        return ZStack {
            RingGlass().frame(width: disc, height: disc)
            // The file sets the colour, only as a tint under the glass (D150): everything on it stays white and neutral, but the slice under the pointer.
            Image(nsImage: frost.frost).resizable().scaledToFill().frame(width: disc, height: disc).clipShape(Circle()).opacity(0.5)
            Circle().fill(.black.opacity(0.66)).frame(width: disc, height: disc)
            ForEach(Array(model.shown.enumerated()), id: \.element.id) { index, choice in
                let on = model.hovered == index
                SliceShape(index: index, count: model.shown.count)
                    .fill(on ? vivid : Color.white.opacity(0.07))
                SliceShape(index: index, count: model.shown.count)
                    .stroke(.white.opacity(on ? 0.75 : 0.14), lineWidth: 1)
                words(choice, index: index)
            }
            middle
        }
        .frame(width: RingLayout.side, height: RingLayout.side)
        // Always clockwise from the top, as `RingGeometry` finds slices: mirrored, the slice you see wouldn't be the slice that runs.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    private func words(_ choice: RingChoice, index: Int) -> some View {
        let at = RingGeometry.centre(of: index, count: model.shown.count, radius: Double(RingLayout.inner + RingLayout.outer) / 2)
        return VStack(spacing: 2) {
            if let tag = choice.tag {
                Text(verbatim: tag).font(.system(size: 12, weight: .bold, design: .rounded)).environment(\.layoutDirection, .leftToRight)
            }
            Text(ext: choice.title).font(.system(size: 12.5, weight: .semibold))
            if let detail = choice.detail, choice.tag == nil, choice.item != nil {
                Text(ext: detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(width: model.shown.count > 6 ? 96 : 116)
        .position(x: RingLayout.side / 2 + at.dx, y: RingLayout.side / 2 - at.dy)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var middle: some View {
        VStack(spacing: 3) {
            FrostLoader(path: model.files.first) { frost in
                FileSheetPlain(frost: frost, path: model.files.first ?? "", side: 44)
            }
            Text(verbatim: DropChoices.shownName(model.files.first ?? "")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            if model.files.count > 1 {
                Text("and \(model.files.count - 1) more", comment: "The ring's middle: under the first of several files' names")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
            }
            if model.hasMore {
                Text(model.byClick ? "Tab for more" : "⇧ for more", comment: "The ring's middle: the key that shows its second set of choices")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: RingLayout.inner * 1.7)
        .allowsHitTesting(false)
    }

    private func line<Words: View>(@ViewBuilder _ words: () -> Words) -> some View {
        words()
            .font(Theme.Font.caption).foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: RingLayout.side - 20)
    }

    private func noteWords(_ note: FileRingModel.Note) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "info.circle")
            switch note {
            case .nothing: Text("Nothing you have installed can change this.", comment: "The ring: no extension offers anything for what's being dragged")
            case .tooMany: Text("These need more room to name. Drop them on your companion to see them all.", comment: "The ring: too many files being dragged, or names too long, to name them all under it")
            }
        }
    }

    /// Sidefolk's own line, from the extension's permissions and never its words.
    private func trust(_ offer: ExtensionDropAction) -> some View {
        let many = model.files.count > 1, count = model.files.count, who = offer.extensionName
        return HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: offer.canSendAway ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.system(size: 10, weight: .semibold)).padding(.top, 2)
                .foregroundStyle(offer.canSendAway ? Color.yellow : .white.opacity(0.75))
            Group {
                if offer.canSendAwayWithoutInternet {
                    if many {
                        Text("\(who) reads these \(count) files only if you choose a slice. It has no internet access of its own, but other things it's allowed to use could carry them out.", comment: "The ring's line")
                    } else {
                        Text("\(who) reads this file only if you choose a slice. It has no internet access of its own, but other things it's allowed to use could carry it out.", comment: "The ring's line")
                    }
                } else {
                    switch (many, offer.canSendAway) {
                    case (false, false): Text("\(who) reads this file only if you choose a slice, and only this once. It can't go online by itself.", comment: "The ring's line")
                    case (true, false): Text("\(who) reads these \(count) files only if you choose a slice, and only this once. It can't go online by itself.", comment: "The ring's line")
                    case (false, true): Text("\(who) reads this file only if you choose a slice. It can use the internet, so it could send the file anywhere.", comment: "The ring's line")
                    case (true, true): Text("\(who) reads these \(count) files only if you choose a slice. It can use the internet, so it could send them anywhere.", comment: "The ring's line")
                    }
                }
            }
        }
    }
}
