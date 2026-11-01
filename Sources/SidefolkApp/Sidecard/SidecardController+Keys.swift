import AppKit
import SidefolkCore

/// Answering the Sidecard from the keyboard (D84). The panel never takes keys on its own: only the card shortcut
/// (⌃⌥Space unless the person changed it) hands it the keyboard, and it gives it back when the card is answered, put
/// away, or the person clicks elsewhere. Then ↩ presses the answer in focus (⌘↩ on a firm card, D84), ←/→ and Tab move
/// between answers, ⎋ puts the card back in the stack, and ↑/↓ bring the other held cards to the front.
extension SidecardController {
    /// The ⋯ menu as one stop among the answers.
    static let moreAnswers = "sidefolk.more"
    /// Keys count this long after a card comes to the front.
    static let armDelay: TimeInterval = 0.5

    func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.holdsKeys, event.window === self.hosted.panel else { return event }
            return self.handle(event) ? nil : event
        }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: hosted.panel,
                                                             queue: .main) { [weak self] _ in
            // Clicked elsewhere: the keys are the person's again, and the card stays as it was.
            MainActor.assumeIsolated {
                guard let self, !self.passingKeys, !self.devKeys else { return }
                self.releaseKeys(resign: false)
            }
        }
    }

    /// Whether the Sidecard shows something the shortcut can take the keyboard to.
    var showsSomething: Bool { hosted.panel.isVisible }

    /// The shortcut: the card in front takes the keyboard (a whisper grows into a card first); with nothing out, the
    /// held cards fan out with the newest chosen. False when there is nothing to answer.
    func takeKeys() async -> Bool {
        if hosted.panel.isVisible, model.shape == .whisper { growWhisper() }
        if hosted.panel.isVisible, model.shape == .card, let item = model.item {
            holdsKeys = true
            focusKeys(on: item)
            return true
        }
        let items = await waitingItems?() ?? []
        guard !items.isEmpty else { return false }
        holdsKeys = true
        deckItems = items
        model.stack = items
        model.item = nil
        model.shape = .stack
        model.stackFocus = items.last?.id
        appear()
        fanOut()
        makeKey()
        return true
    }

    /// The card in front gets the focus on its main answer, among the held cards for ↑/↓.
    func focusKeys(on item: AttentionItem) {
        let (menu, buttons) = SidecardItemCard.arrange(item.actions)
        // ⋯ holds the other answers and D88's "Fewer like this": one stop when either is there.
        let more = !menu.isEmpty || !SidecardItemCard.fewer(item, model.interruptions).isEmpty
        let answers = (more ? [Self.moreAnswers] : []) + buttons.map(\.id)
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        model.keys = CardKeys(answers: answers, main: buttons.last?.id, takesReturn: item.takesReturn,
                              deck: deckItems.map(\.id), current: item.id, rightToLeft: rtl)
        armedAt = Date().addingTimeInterval(Self.armDelay)
        makeKey()
        // The held cards are read once the card shows; ↑/↓ wait for them.
        Task { [weak self] in
            guard let self, let items = await self.waitingItems?() else { return }
            self.deckItems = items
            if self.model.item?.id == item.id, self.model.keys != nil {
                self.model.keys?.deck = items.map(\.id)
            }
        }
    }

    func releaseKeys(resign: Bool = true) {
        guard holdsKeys else { return }
        holdsKeys = false
        devKeys = false
        model.keys = nil
        model.stackFocus = nil
        hosted.panel.allowsKey = false
        if resign, hosted.panel.isKeyWindow { hosted.panel.resignKey() }
    }

    private func makeKey() {
        hosted.panel.allowsKey = true
        hosted.panel.makeKey()
    }

    // MARK: Keys

    private func handle(_ event: NSEvent) -> Bool {
        guard let key = Self.key(event) else { return false }
        // A key held down repeats: one press answers one card, never the next one too.
        if event.isARepeat, case .enter = key { return true }
        return press(key)
    }

    #if DEBUG
    /// Dev (`cardKey:return|cmdReturn|escape|left|right|tab|backtab|up|down`): a key on the Sidecard, as if typed there.
    func devKey(_ name: String) {
        let keys: [String: CardKeys.Key] = ["return": .enter(command: false), "cmdReturn": .enter(command: true), "escape": .escape,
                                            "left": .left, "right": .right, "tab": .tab(back: false), "backtab": .tab(back: true),
                                            "up": .up, "down": .down]
        guard holdsKeys, let key = keys[name] else { return }
        armedAt = .distantPast
        _ = press(key)
    }
    #endif

    private func press(_ key: CardKeys.Key) -> Bool {
        if model.shape == .stack { return stackKey(key) }
        guard let item = model.item, var keys = model.keys else { return false }
        if case .enter = key, Date() < armedAt { return true }
        let outcome = keys.press(key)
        model.keys = keys
        switch outcome {
        case .press(let id) where id == Self.moreAnswers:
            showMoreAnswers(item)
        case .press(let id):
            answer(item, id)
        case .putAway:
            putAway(item)
        case .show(let id):
            if let next = deckItems.first(where: { $0.id == id }) { present(next, .attention(expandFor: AttentionPolicy.expandSeconds)) }
        case .needsCommand:
            model.keysNudge += 1
        case .moved, .ignored:
            break
        }
        return true
    }

    private static func key(_ event: NSEvent) -> CardKeys.Key? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76: return .enter(command: mods.contains(.command))
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 48: return .tab(back: mods.contains(.shift))
        default: return nil
        }
    }

    /// Answered from the keys: the next held card comes to the front with the keyboard, or the keys go back.
    private func answer(_ item: AttentionItem, _ action: String) {
        let rest = deckItems.filter { $0.id != item.id }
        deckItems = rest
        passingKeys = true
        model.respond?(item, action)
        passingKeys = false
        guard holdsKeys else { return }
        if hosted.panel.isVisible, model.shape == .card, let shown = model.item {
            focusKeys(on: shown)
        } else if let next = rest.last {
            present(next, .attention(expandFor: AttentionPolicy.expandSeconds))
        } else {
            releaseKeys()
        }
    }

    /// Esc: a card that waits goes back into the stack; one that needed nothing goes; the companion's own card closes.
    private func putAway(_ item: AttentionItem) {
        releaseKeys()
        if item.level >= .attention, Self.folds(item) {
            foldCurrent(id: item.id)
        } else if item.level < .attention {
            autoDismiss(id: item.id)
        } else {
            model.respond?(item, nil)
        }
    }

    /// The answers behind ⋯ (and "Fewer like this"), as a menu the arrow keys move through.
    private func showMoreAnswers(_ item: AttentionItem) {
        let (menu, _) = SidecardItemCard.arrange(item.actions)
        let fewer = SidecardItemCard.fewer(item, model.interruptions)
        guard !menu.isEmpty || !fewer.isEmpty, let view = hosted.panel.contentView else { return }
        let popup = NSMenu()
        for action in menu {
            popup.addItem(ClosureTarget.item(action.title) { [weak self] in self?.answer(item, action.id) })
        }
        if !menu.isEmpty, !fewer.isEmpty { popup.addItem(.separator()) }
        for choice in fewer {
            popup.addItem(ClosureTarget.item(choice.title) { [weak self] in self?.model.lowerSource?(item, choice.source, choice.level) })
        }
        let margin = SidecardView.margin
        popup.popUp(positioning: nil, at: NSPoint(x: margin.leading + 16, y: margin.bottom + 40), in: view)
    }

    // MARK: The stack

    private func stackKey(_ key: CardKeys.Key) -> Bool {
        let ids = model.stack.map(\.id)
        let at = model.stackFocus.flatMap { ids.firstIndex(of: $0) } ?? ids.count - 1
        switch key {
        case .up where at > 0: model.stackFocus = ids[at - 1]
        case .down where at < ids.count - 1: model.stackFocus = ids[at + 1]
        case .enter:
            // The chosen card comes out of the stack to be answered.
            guard let item = model.stack.first(where: { $0.id == model.stackFocus }) else { return true }
            model.stack = []
            model.stackFocus = nil
            present(item, .attention(expandFor: AttentionPolicy.expandSeconds))
        case .escape:
            releaseKeys()
            hideStack()
        default:
            break
        }
        return true
    }
}
