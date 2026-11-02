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
        Task { await host.setAIHelper(helper) }
    }

    /// An entry as a menu item, a submenu when it holds items. Anyone but Sidefolk's own extensions shows its name (`shownTitle`).
    func menuItem(_ entry: ExtensionEntry) -> NSMenuItem {
        let item = ClosureTarget.item(entry.shownTitle) { [weak self] in self?.run(entry) }
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
                let outcome = await runtime.executor.execute(name: name, input: input, caller: .user)
                if let problem = outcome.problem { runtime.events.publish(.notice(problem.message)) }
            }
        case .page(let page):
            askPanel.hide()
            home.show(section: .page("\(entry.extensionId)/\(page)"))
        case .menu:
            break
        }
    }

    /// What extensions offer for this dropped thing, in the order of their names.
    func extensionDrops(for attachment: Attachment) -> [ExtensionDropAction] {
        DropChoices.offers(for: attachment.dropKind, value: attachment.dropValue, among: runtime.extensions.shelf.drops)
    }

    func perform(_ action: ExtensionDropAction, with attachment: Attachment, in model: AskModel) {
        model.attachment = nil
        // Its own tool, as one of its sentences would run it: Guard asks as it always does, and the address counts as typed.
        runLocal(.extensionCommand(ExtensionCommandCall(tool: action.tool, input: action.input(for: attachment.dropValue), extensionId: action.extensionId,
                                                        said: attachment.dropValue)),
                 caption: attachment.caption, into: model)
    }
}
