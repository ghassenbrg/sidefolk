import AppKit
import Observation
import SidefolkCore

/// One extension palette while it is open (D63): what it lists for what the person types, which row is picked, the
/// picked row in full when the extension offers it (D68), and what choosing does. The extension does the work; the app
/// pastes when it says so.
@MainActor @Observable
final class PaletteModel {
    let info: ExtensionPaletteInfo
    private let host: ExtensionHost?
    /// Where the extension's pictures are (`ExtensionDataFile`).
    let folder: URL
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    private(set) var items: [ExtensionPaletteList.Item] = []
    private(set) var note: String?
    private(set) var message: String?
    /// The extension offers a preview: the panel is wider, the picked row shown beside the list.
    private(set) var hasPreview = false {
        didSet { if hasPreview != oldValue { onPreviewChange?(hasPreview) } }
    }
    var onPreviewChange: ((Bool) -> Void)?
    private(set) var listActions: [String] = []
    private(set) var preview: ExtensionPalettePreview?
    var selected = 0 {
        didSet { if selected != oldValue { schedulePreview() } }
    }
    /// A list action asked for once (⌥⌘⌫): asked again within a few seconds, it runs.
    private var armed: (action: String, at: Date)?
    /// Called when choosing should close the palette, with whether to paste into the app in front.
    var onClose: ((_ paste: Bool) -> Void)?
    private var searchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    init(info: ExtensionPaletteInfo, host: ExtensionHost) {
        self.info = info
        self.host = host
        folder = host.dataFolder(extensionId: info.extensionId)
    }

    /// A palette with nothing behind it, for UI snapshots.
    init(info: ExtensionPaletteInfo, folder: URL, list: ExtensionPaletteList, preview: ExtensionPalettePreview? = nil) {
        self.info = info
        host = nil
        self.folder = folder
        items = list.items
        note = list.note
        hasPreview = list.preview
        listActions = list.actions
        self.preview = preview
    }

    var picked: ExtensionPaletteList.Item? { items.indices.contains(selected) ? items[selected] : nil }

    func reload() async {
        guard let host else { return }
        do {
            let list = try await host.queryPalette(extensionId: info.extensionId, palette: info.palette, query: query)
            let before = picked?.id
            items = list.items
            note = list.note
            hasPreview = list.preview
            listActions = list.actions
            message = nil
            selected = min(selected, max(0, items.count - 1))
            if picked?.id != before || preview == nil { schedulePreview(after: .zero) }
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

    /// The picked row in full, a moment after the pick settles, so holding ↓ doesn't ask for every row on the way.
    private func schedulePreview(after delay: Duration = .milliseconds(90)) {
        previewTask?.cancel()
        guard hasPreview, let host, let item = picked else {
            preview = nil
            return
        }
        previewTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let shown = try? await host.previewPalette(extensionId: info.extensionId, palette: info.palette, item: item.id)
            guard !Task.isCancelled, picked?.id == item.id else { return }
            preview = shown ?? nil
        }
    }

    func move(_ by: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + by + items.count) % items.count
    }

    /// `choose` (Return), `alternate` (⌥Return), `plain` (⇧Return), `pin` or `delete`, on the picked row or the one given.
    func act(_ action: String, on index: Int? = nil) async {
        let i = index ?? selected
        guard items.indices.contains(i) else { return }
        let item = items[i]
        guard action == "choose" || item.actions.contains(action) else { return }
        if index != nil { selected = i }
        await send(item: item.id, action: action)
    }

    /// A list action (`clear`, `clear_all`): it forgets things, so it runs only when asked twice.
    func actOnList(_ action: String, now: Date = Date()) async {
        guard listActions.contains(action) else { return }
        if let armed, armed.action == action, now.timeIntervalSince(armed.at) < 4 {
            self.armed = nil
            await send(item: "", action: action)
        } else {
            armed = (action, now)
            message = action == "clear_all"
                ? String(localized: "Press ⇧⌥⌘⌫ again to clear everything, pinned items too.", comment: "A palette asks before clearing all of it")
                : String(localized: "Press ⌥⌘⌫ again to clear everything but pinned items.", comment: "A palette asks before clearing it")
        }
    }

    private func send(item: String, action: String) async {
        guard let host else { return }
        do {
            let choice = try await host.choosePalette(extensionId: info.extensionId, palette: info.palette, item: item, action: action)
            message = choice.message
            if choice.close { onClose?(choice.paste) } else { await reload() }
        } catch {
            message = (error as? UserFacingError)?.message ?? String(localized: "That didn't work.")
        }
    }

    func handle(_ command: PaletteKeys.Command) {
        switch command {
        case .item(let action, let index): Task { await act(action, on: index) }
        case .list(let action): Task { await actOnList(action) }
        }
    }
}
