import AppKit
import SidefolkCore
import SwiftUI

/// A scene drawn inside an extension's page (D100): the same native layers as a surface, fitted to the page's width, with each
/// area running the extension's own tool. So a center of its own can look however it wants, with no app release. It plays no sounds:
/// a page has no speaker to say so, and anything that plays is a surface.
struct PageSceneBlock: View {
    var block: PageScene
    var model: ExtensionPageModel
    @State private var view = SceneView()

    var body: some View {
        let size = block.scene.size
        GeometryReader { geometry in
            PageSceneCanvas(view: view)
                .task(id: Shown(scene: block.scene, width: geometry.size.width)) { await show(width: geometry.size.width) }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .clipped()
    }

    private struct Shown: Hashable {
        var scene: SurfaceScene
        var width: CGFloat
    }

    private func show(width: CGFloat) async {
        guard width > 0 else { return }
        let scene = block.scene, scale = min(width / scene.size.width, 1)
        let services = model.services, id = model.info.extensionId
        let reader = await services?.runtime.extensions.assetReader(extensionId: id)
        view.assets = SceneImages(reader: reader)
        view.figures = SceneFigures.live(settings: services?.runtime.settings.current ?? AppSettings())
        await view.assets.preload(scene)
        view.frame.size = CGSize(width: scene.size.width * scale, height: scene.size.height * scale)
        let actions = block
        view.onMove = { move in
            guard case .click(let area, let value, _) = move else { return }
            if let act = actions.act(area: area, value: value) {
                Task { await model.perform(act) }
            } else if let action = actions.action(area: area, value: value) {
                Task { await model.run(tool: action.tool, input: action.input) }
            }
        }
        view.show(scene, scale: scale, rtl: Locale.Language(identifier: AppLanguage.current).characterDirection == .rightToLeft,
                  reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

private struct PageSceneCanvas: NSViewRepresentable {
    var view: SceneView
    func makeNSView(context: Context) -> SceneView { view }
    func updateNSView(_ view: SceneView, context: Context) {}
}
