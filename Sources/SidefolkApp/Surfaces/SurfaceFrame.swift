import AppKit
import SidefolkCore
import SwiftUI

/// The frame Sidefolk always puts round an extension's surface (D99): its icon and name, a back and a close that are the
/// app's own, the speaker if it has sounds. The extension draws only inside; it can't draw on this, move it or hide it, so
/// what it shows always says whose it is, and can't pass for one of Sidefolk's cards.
struct SurfaceFrame: View {
    var model: SurfaceModel
    var onBack: () -> Void
    var onSpeaker: () -> Void
    var onClose: () -> Void

    var body: some View {
        Group {
            switch model.info.presentation {
            case .panel: panel
            case .overlay: overlay
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.info.extensionName))
    }

    /// Its name, and for anyone but Sidefolk's own, who made it: a name alone isn't proof of whose it is (T40).
    private var whose: String {
        let info = model.info
        if info.firstParty { return info.extensionName }
        if let author = info.author, !author.isEmpty {
            return String(localized: "\(info.extensionName), by \(author)", comment: "The frame of an extension's panel: its name and its author")
        }
        return String(localized: "\(info.extensionName), not from Sidefolk", comment: "The frame of an extension's panel: its name, when it names no author")
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            canvas
        }
        .frame(minWidth: 260)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// The canvas on the desktop with nothing behind it, and a small chip under it saying whose it is.
    private var overlay: some View {
        VStack(spacing: 6) {
            canvas
            HStack(spacing: 6) {
                SurfaceIcon(info: model.info, side: 16)
                Text(verbatim: whose).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                SurfaceButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes an extension's panel"), side: 18, action: onClose)
            }
            .padding(.leading, 8).padding(.trailing, 4)
            .frame(height: SurfacePolicy.chipHeight - 6)
            .background(Capsule().fill(Theme.surface).shadow(color: .black.opacity(0.14), radius: 3, y: 1))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .frame(minWidth: 170)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if model.scene?.back == true {
                SurfaceButton(symbol: "chevron.backward", label: String(localized: "Back", comment: "Goes back in an extension's panel"), side: 26, action: onBack)
            }
            SurfaceIcon(info: model.info, side: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: model.scene?.title.map(model.view.figures.fill) ?? model.info.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: whose).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.info.sounds, model.scene?.hidesSpeaker != true {
                SurfaceButton(symbol: model.soundsOn ? "speaker.wave.2.fill" : "speaker.slash",
                              label: model.soundsOn ? String(localized: "Sound on", comment: "An extension's panel: the speaker")
                                                    : String(localized: "Sound off", comment: "An extension's panel: the speaker"),
                              side: 26, action: onSpeaker)
            }
            SurfaceButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes an extension's panel"), side: 26, action: onClose)
        }
        .padding(.horizontal, 10)
        .frame(height: SurfacePolicy.headerHeight)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var canvas: some View {
        if let failure = model.failure {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble").font(.system(size: 22)).foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                Text(verbatim: failure).font(.system(size: 13)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(width: max(model.canvas.width, 260), height: max(model.canvas.height, 120))
        } else {
            SceneCanvas(view: model.view, themeKey: ThemeStore.shared.style.theme.id)
                .frame(width: model.canvas.width, height: model.canvas.height)
                .clipped()
                .opacity(model.takesInput ? 1 : 0.55)
                .allowsHitTesting(model.takesInput)
        }
    }
}

/// The scene's view in SwiftUI. Theme changes come through here; SwiftUI otherwise leaves it alone.
struct SceneCanvas: NSViewRepresentable {
    var view: SceneView
    var themeKey: String

    final class Coordinator {
        var themeKey = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SceneView {
        context.coordinator.themeKey = themeKey
        return view
    }

    func updateNSView(_ view: SceneView, context: Context) {
        guard context.coordinator.themeKey != themeKey else { return }
        context.coordinator.themeKey = themeKey
        view.restyle()
    }
}

/// The extension's icon, or its surface's symbol.
struct SurfaceIcon: View {
    var info: SurfaceInfo
    var side: CGFloat

    var body: some View {
        Group {
            if let path = info.iconPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: info.symbol ?? "puzzlepiece.extension").font(.system(size: side * 0.6, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

struct SurfaceButton: View {
    var symbol: String
    var label: String
    var side: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: side * 0.45, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .frame(width: side, height: side).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(label)
        .accessibilityLabel(label)
    }
}
