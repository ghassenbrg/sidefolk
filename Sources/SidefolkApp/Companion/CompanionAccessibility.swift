import AppKit
import SidefolkCore

/// One thing in the companion's corner as VoiceOver reaches it (D88): the pins, agent faces and the count are drawn
/// as one picture that takes no clicks of its own, so each gets an element here, with its words and what pressing
/// it does (the same as a click).
nonisolated final class FloorElement: NSAccessibilityElement {
    // Set and read on the main thread only: VoiceOver's calls arrive there.
    nonisolated(unsafe) var press: (@MainActor () -> Void)?
    nonisolated(unsafe) var menu: (@MainActor () -> NSMenu?)?
    nonisolated(unsafe) weak var view: NSView?

    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        MainActor.assumeIsolated { press() }
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu else { return false }
        nonisolated(unsafe) let view = view
        let frame = accessibilityFrame()
        return MainActor.assumeIsolated {
            guard let menu = menu(), let view, let window = view.window else { return false }
            let local = view.convert(window.convertFromScreen(frame), from: nil)
            menu.popUp(positioning: nil, at: NSPoint(x: local.midX, y: local.midY), in: view)
            return true
        }
    }
}

extension CompanionWindowController {
    /// The corner in VoiceOver's order: the companion, what it is saying now (the card, stack or slip), the count on
    /// its shoulder, the pins, the agents' faces, then the folks. Kept by id, so VoiceOver's cursor stays put as
    /// values change.
    func accessibleParts(of container: NSView) -> [Any] {
        var parts: [FloorElement] = []
        func element(_ key: String, _ rect: NSRect, label: String, value: String? = nil, help: String? = nil,
                     press: (@MainActor () -> Void)?, menu: (@MainActor () -> NSMenu?)? = nil) {
            let e = axElements[key] ?? FloorElement()
            axElements[key] = e
            e.view = container
            e.setAccessibilityParent(container)
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(label)
            e.setAccessibilityValue(value)
            e.setAccessibilityHelp(help)
            e.setAccessibilityFrame(panel.convertToScreen(container.convert(rect, to: nil)))
            e.press = press
            e.menu = menu
            parts.append(e)
        }
        let body = character.convert(character.characterFrame, to: container)
        element("companion", body, label: character.displayName, value: container.accessibilityValue() as? String,
                help: String(localized: "Press to talk to \(character.displayName)."), press: { [weak self] in self?.delegate?.companionClicked() })
        if let card = delegate?.companionSays() {
            // Above the head: pressing it gives the card the keyboard, as the card shortcut does.
            let above = NSRect(x: body.minX, y: body.maxY - 8, width: body.width, height: 8)
            element("card", above, label: card, help: String(localized: "Answers it from the keyboard.", comment: "VoiceOver: the card beside the companion"),
                    press: { [weak self] in self?.delegate?.companionFocusCard() })
        }
        if floor.count > 0 {
            let center = NSPoint(x: floor.badgeCenter.x, y: container.bounds.height - floor.badgeCenter.y)
            let side = Theme.Size.stackBadge
            element("count", NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                    label: String(localized: "\(floor.count) waiting", comment: "A count of things waiting on the person, read by VoiceOver"),
                    help: String(localized: "Opens what waits.", comment: "VoiceOver: the count on the companion's shoulder"),
                    press: { [weak self] in self?.delegate?.companionBadgeClicked() })
        }
        // Pins top to bottom as they stand, then the agents' faces in their row.
        let shown = extras.filter { if case .pin = $0.item { true } else { false } }.sorted { $0.rect.maxY > $1.rect.maxY }
            + extras.filter { if case .agent = $0.item { true } else { false } }
        for (item, rect) in shown {
            switch item {
            case .pin(let id):
                guard let pin = floor.pins.first(where: { $0.id == id }) else { continue }
                element("pin." + id, rect, label: pin.label, value: pin.value, help: PinTip.meta(pin, now: Date()),
                        press: { [weak self] in self?.delegate?.companionReadoutClicked(id) },
                        menu: { [weak self] in self?.delegate?.companionReadoutMenu(id) })
            case .agent(let id):
                guard let chip = floor.agents.first(where: { $0.id == id }) else { continue }
                element("agent." + id, rect, label: AgentTip.line(chip, now: Date()),
                        help: String(localized: "Opens the session.", comment: "VoiceOver: an agent's face beside the companion"),
                        press: { [weak self] in self?.delegate?.companionAgentClicked(id) })
            case .folk:
                continue
            }
        }
        for folk in folksShown {
            guard let rect = folkFrame(folk) else { continue }
            element("folk." + folk.rawValue, rect, label: Self.folkLabel(folk),
                    help: String(localized: "Opens Sidefolk.", comment: "VoiceOver: a folk on duty beside the companion"),
                    press: { [weak self] in self?.delegate?.companionFolkClicked(folk) })
        }
        let keys = Set(parts.compactMap { e in axElements.first { $0.value === e }?.key })
        axElements = axElements.filter { keys.contains($0.key) }
        return parts
    }
}
