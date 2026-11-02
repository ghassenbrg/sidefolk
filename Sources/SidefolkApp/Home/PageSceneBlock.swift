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
                .overlay(alignment: .topLeading) { PageSceneInlays(block: block, width: geometry.size.width, model: model) }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .clipped()
    }

    private struct Shown: Hashable {
        var scene: SurfaceScene
        var width: CGFloat
    }

    #if DEBUG
    /// Every page scene on screen, for the debug app's keys.
    @MainActor static var shown: [SceneView] { allViews.allObjects }
    @MainActor private static let allViews = NSHashTable<SceneView>.weakObjects()
    #endif

    private func show(width: CGFloat) async {
        #if DEBUG
        Self.allViews.add(view)
        #endif
        guard width > 0 else { return }
        let scene = block.scene, scale = min(width / scene.size.width, 1)
        let services = model.services, id = model.info.extensionId
        let reader = await services?.runtime.extensions.assetReader(extensionId: id)
        view.tabsThroughAreas = true
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

struct PageSceneCanvas: NSViewRepresentable {
    var view: SceneView
    func makeNSView(context: Context) -> SceneView { view }
    func updateNSView(_ view: SceneView, context: Context) {}
}

/// The native controls a scene holds (D109), each where the scene says, scaled with it. A scene laid out for right to left mirrors its
/// own places, so these follow.
private struct PageSceneInlays: View {
    var block: PageScene
    var width: CGFloat
    var model: ExtensionPageModel
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let scene = block.scene.size, scale = width > 0 ? min(width / scene.width, 1) : 1
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: scene.width * scale, height: scene.height * scale).allowsHitTesting(false)
            ForEach(Array(block.inlays.enumerated()), id: \.offset) { _, inlay in
                PageInlayView(part: inlay.part, model: model)
                    .environment(\.layoutDirection, direction)
                    .frame(width: inlay.w * scale, height: inlay.h * scale)
                    .offset(x: (direction == .rightToLeft ? scene.width - inlay.x - inlay.w : inlay.x) * scale, y: inlay.y * scale)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct PageInlayView: View {
    var part: ExtensionPage.Block
    var model: ExtensionPageModel

    var body: some View {
        switch part {
        case .field(let field): PageInlaidField(field: field, model: model)
        case .choice(let choice): PageInlaidMenu(choice: choice, model: model)
        case .control(let control):
            PageTableCell(cell: .control(control), spoken: control.label, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default: EmptyView()
        }
    }
}

/// Only the words: the scene draws its well, its glass and its symbol.
private struct PageInlaidField: View {
    var field: ExtensionPage.Field
    var model: ExtensionPageModel
    @State private var text = ""
    @State private var began = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField(text: $text) { Text(ext: field.placeholder ?? field.label) }
                .textFieldStyle(.plain)
                .accessibilityLabel(Text(ext: field.label))
                .onSubmit(send)
                .task(id: text) { await follow() }
                .onAppear { if let value = field.value, text.isEmpty { text = value } }
                .onChange(of: field.value) { old, new in
                    if new == nil, old != nil, !text.isEmpty { text = "" }
                }
            if field.live, !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.sfIcon).accessibilityLabel(Text(ext: field.button))
            }
        }
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            if let go = field.go(typing: text) { await model.go(go) } else { await model.run(tool: field.tool, input: field.input(typing: text)) }
        }
    }

    private func follow() async {
        guard field.live else { return }
        guard began else { began = true; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, text != (field.value ?? ""), let go = field.go(typing: text) else { return }
        await model.go(go)
    }
}

/// A menu with nothing of its own to show: the scene draws the pill and its words, this opens over them.
private struct PageInlaidMenu: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel

    var body: some View {
        Menu {
            ForEach(choice.options, id: \.value) { option in
                Button { pick(option.value) } label: {
                    if option.value == choice.selected { Label { Text(ext: option.label) } icon: { Image(systemName: "checkmark") } } else { Text(ext: option.label) }
                }
            }
        } label: {
            Rectangle().fill(Color.white.opacity(0.001)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.sfBare)
        .menuIndicator(.hidden)
        .disabled(choice.disabled)
        .accessibilityLabel(Text(ext: choice.label))
        .accessibilityValue(Text(ext: choice.options.first { $0.value == choice.selected }?.label ?? ""))
    }

    private func pick(_ value: String) {
        guard value != choice.selected else { return }
        Task {
            if let go = choice.go(picking: value) { await model.go(go) } else { await model.run(tool: choice.tool, input: choice.input(picking: value)) }
        }
    }
}
