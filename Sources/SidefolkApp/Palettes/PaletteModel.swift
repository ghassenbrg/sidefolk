import AppKit
import Observation
import SidefolkCore

/// One extension palette while it is open (D63): what it lists for what the person types, which row is picked, and
/// what choosing does. The extension does the work; the app pastes when it says so.
@MainActor @Observable
final class PaletteModel {
    let info: ExtensionPaletteInfo
    private let host: ExtensionHost
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    private(set) var items: [ExtensionPaletteList.Item] = []
    private(set) var note: String?
    private(set) var message: String?
    var selected = 0
    /// Called when choosing should close the palette, with whether to paste into the app in front.
    var onClose: ((_ paste: Bool) -> Void)?
    private var searchTask: Task<Void, Never>?

    init(info: ExtensionPaletteInfo, host: ExtensionHost) {
        self.info = info
        self.host = host
    }

    /// A palette with nothing behind it, for UI snapshots.
    init(info: ExtensionPaletteInfo, host: ExtensionHost, items: [ExtensionPaletteList.Item], note: String?) {
        self.info = info
        self.host = host
        self.items = items
        self.note = note
    }

    func reload() async {
        do {
            let list = try await host.queryPalette(extensionId: info.extensionId, palette: info.palette, query: query)
            items = list.items
            note = list.note
            message = nil
            selected = min(selected, max(0, items.count - 1))
        } catch {
            message = (error as? UserFacingError)?.message ?? String(localized: "The list couldn't be read.")
        }
    }

    private func schedule() {
        searchTask?.cancel()
        selected = 0
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func move(_ by: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + by + items.count) % items.count
    }

    /// `choose` (Return), `plain` (Shift-Return), `pin` (⌘P) or `delete` (⌘⌫), on the picked row or the one given.
    func act(_ action: String, on index: Int? = nil) async {
        let i = index ?? selected
        guard items.indices.contains(i) else { return }
        let item = items[i]
        guard action == "choose" || item.actions.contains(action) else { return }
        do {
            let choice = try await host.choosePalette(extensionId: info.extensionId, palette: info.palette, item: item.id, action: action)
            message = choice.message
            if choice.close { onClose?(choice.paste) } else { await reload() }
        } catch {
            message = (error as? UserFacingError)?.message ?? String(localized: "That didn't work.")
        }
    }
}
