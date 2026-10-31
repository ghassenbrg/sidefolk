import AppKit
import SidefolkCore

/// Tells an extension with the clipboard permission which app was in front when the clipboard last changed (D68), so
/// Clipboard can say where a copy came from and leave out the apps the person ignores. The sandboxed extension can't
/// ask macOS (Launch Services would also let it open apps and links, D63), so Sidefolk answers, once per change of the
/// clipboard: asking again before the next copy gets nothing, so it can't follow which apps the person uses.
@MainActor
final class ClipboardSource {
    private var answered: [String: Int] = [:]

    func answer(_ id: String, host: ExtensionHost) {
        let change = NSPasteboard.general.changeCount
        guard answered[id] != change else { return }
        answered[id] = change
        var params: [String: JSONValue] = ["change": .number(Double(change))]
        if let app = NSWorkspace.shared.frontmostApplication {
            if let bundle = app.bundleIdentifier { params["app"] = .string(bundle) }
            if let name = app.localizedName { params["name"] = .string(name) }
        }
        Task { await host.tell(extensionId: id, "sidefolk/clipboard.source", .object(params)) }
    }
}
