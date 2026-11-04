#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// `SidefolkApp --page-json <page.json> <out.png> [--width 1320] [--height 860] [--dark]`: a page as a program answered it, drawn off every screen with Sidefolk's own parts:
/// no window on the person's screen, no focus taken. For looking at a page's states from a test's output.
enum PageJSONRender {
    @MainActor static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--page-json"), at + 2 < args.count else { return false }
        func number(_ flag: String, _ otherwise: CGFloat) -> CGFloat {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil }.map { CGFloat($0) } ?? otherwise
        }
        let (input, output) = (URL(fileURLWithPath: args[at + 1]), URL(fileURLWithPath: args[at + 2]))
        let size = CGSize(width: number("--width", 1320), height: number("--height", 860))
        let dark = args.contains("--dark")
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: input))
                let page = try ExtensionPage.parse(json)
                let info = SampleExtensionPage.info
                let model = ExtensionPageModel(info: info, page: page, history: [:], alerts: [], updated: Date())
                let host = NSHostingView(rootView: PageWorkspaceFrame(model: model).frame(width: size.width, height: size.height).background(Theme.surface))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(500))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: output)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("page-json: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApplication.shared.run()
        return true
    }
}

/// The page itself, without the task that would read it from a program.
private struct PageWorkspaceFrame: View {
    var model: ExtensionPageModel

    var body: some View {
        if let page = model.page, page.workspace { PageWorkspace(page: page, model: model).environment(\.pageSelected, page.accent.last.flatMap { Color(extensionHex: $0) }) } else { Text(verbatim: "Not a workspace page") }
    }
}
#endif
