import AppKit
import SidefolkCore

/// What extensions add to Sidefolk's own places (D100): items in the companion's menu and the Pocket, a tab in Ask, what they offer
/// for a drop, and their use of the person's AI. Everything is read from the shelf when it is shown, so an extension that is off or
/// gone has nothing left here; everything runs one of its own tools as the person, through Guard, or opens its own page.
extension AppCoordinator {
    /// Reaches the person's AI for an extension that declares `permissions.ai`.
    func installAIHelp() {
        let agent = self.agent!, host = runtime.extensions
        let helper = AIHelper(ask: { system, prompt in try await agent.oneShot(system: system, prompt: prompt, purpose: "extension") })
        runtime.registry.register(AIHelpTool(helper: helper, extensionName: { host.shelf.names[$0] }))
        installSelfTools()
        Task { await host.setAIHelper(helper) }
    }

    /// An entry as a menu item, a submenu when it holds items. Anyone but Sidefolk's own extensions shows its name (`shownTitle`).
    func menuItem(_ entry: ExtensionEntry) -> NSMenuItem {
        let item = ClosureTarget.item(ExtensionCompanionWords.fill(entry.shownTitle)) { [weak self] in self?.run(entry) }
        if let symbol = entry.symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        item.toolTip = String(localized: "From \(entry.extensionName)", comment: "A menu item an extension added: its tooltip names the extension")
        if !entry.items.isEmpty {
            let menu = NSMenu()
            for child in entry.items { menu.addItem(menuItem(child)) }
            item.submenu = menu
            item.action = nil
            item.target = nil
        }
        return item
    }

    func run(_ entry: ExtensionEntry) {
        switch entry.action {
        case .tool(let name, let input):
            askPanel.hide()
            Task {
                // A menu item is written by its author, not chosen by the person from what's on disk: it names no file (D141).
                let remote = String(name.split(separator: ".").last ?? "")
                let paths = await runtime.extensions.pathParameters(extensionId: entry.extensionId, tool: remote)
                let outcome = await runtime.executor.execute(name: name, input: input.removing(paths), caller: .user)
                if let problem = outcome.problem { runtime.events.publish(.notice(problem.message)) }
            }
        case .page(let page, let state):
            askPanel.hide()
            let id = "\(entry.extensionId)/\(page)"
            Task {
                if let state { await runtime.extensions.movePage(id, PageGo(set: state)) }
                home.show(section: .page(id))
                await home.pageMoved(id)
            }
        case .surface(let id, let arguments):
            askPanel.hide()
            Task {
                let outcome = await runtime.executor.execute(name: "surfaces.open", input: ["surface": .string(id), "arguments": arguments], caller: .user)
                if let problem = outcome.problem { runtime.events.publish(.notice(problem.message)) }
            }
        case .menu:
            break
        }
    }

    /// What extensions offer for this dropped thing, in the order of their names.
    func packPicture(_ path: String, extensionId: String) async -> NSImage? {
        guard let reader = await runtime.extensions.assetReader(extensionId: extensionId) else { return nil }
        let cg = await Task.detached { reader.image(path, maxSide: 256) }.value
        return cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    func extensionDrops(for attachment: Attachment) -> [ExtensionDropAction] {
        if attachment.dropKind == .file { return DropChoices.offers(forFiles: attachment.dropFiles, among: runtime.extensions.shelf.drops) }
        return DropChoices.offers(for: attachment.dropKind, value: attachment.dropValue, among: runtime.extensions.shelf.drops)
    }

    func perform(_ action: ExtensionDropAction, choosing item: ExtensionManifest.DropMeta.MenuItem?, with attachment: Attachment, in model: AskModel) {
        model.attachment = nil
        // Dropped files are the person's own act: a read of exactly those, for this one call (D141). The card said so before they chose.
        if attachment.dropKind == .file {
            let files = attachment.dropFiles
            var call = ExtensionCommandCall(tool: action.tool, input: action.input(forFiles: files, choosing: item), extensionId: action.extensionId, said: "")
            call.handedOver = files
            call.fromDrop = true
            call.mark = action.mark
            model.working = files.first.map {
                WorkingFile(path: $0, name: files.count == 1 ? DropChoices.shownName($0) : String(localized: "\(files.count) files", comment: "The drop card: how many files were dropped"),
                            extensionId: action.extensionId, mark: action.mark, showsPicture: !attachment.fromAnotherApp)
            }
            runLocal(.extensionCommand(call), caption: attachment.caption, into: model, returning: attachment)
            return
        }
        // Its own tool, as one of its sentences would run it: Guard asks as it always does, and the address counts as typed.
        var call = ExtensionCommandCall(tool: action.tool, input: action.input(for: attachment.dropValue), extensionId: action.extensionId, said: attachment.dropValue)
        call.fromDrop = true
        runLocal(.extensionCommand(call), caption: attachment.caption, into: model)
    }
}
