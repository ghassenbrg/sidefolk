import AppKit
import SidefolkCore
import SwiftUI

/// Presents notices above the companion as the Sidecard (D84), one moment at a time, with timing from the attention
/// policy: a gentle one is a whisper for six seconds (it waits while the pointer is on it, and grows into a card when
/// clicked); one that needs attention is a card, and a card nobody answered folds into the count on the companion's
/// shoulder after half a minute. Hovering that count fans out what waits; clicking it opens Ask on top of them.
final class SidecardController {
    let model = SidecardModel()
    let hosted: HostedPanel<SidecardView>
    /// Whispers waiting for the card or whisper in front of them to go.
    private var queue: [(AttentionItem, AttentionPresentation)] = []
    private var timer: Task<Void, Never>?
    private var fanEnd: Task<Void, Never>?
    /// The companion's own card, put aside while Ask is open.
    private var parked: AttentionItem?
    /// Cards that folded into the stack since it was last empty: when the last of them is answered, "All clear".
    private var folded: Set<String> = []
    var anchorProvider: (() -> (NSRect, NSScreen)?)?
    /// The person chose not to have the companion over full-screen apps (D138): a card that needs them still goes there,
    /// while whispers and the count stay with the companion.
    var hidesOverFullScreen = false {
        didSet {
            followSpaces()
            spaceChanged()
        }
    }
    private var hiddenOverFullScreen = false
    /// Right now the person is on a full-screen app it's kept off.
    var overFullScreenNow = false {
        didSet { followSpaces() }
    }
    /// Whether something of this kind waits for now (D138).
    var holds: ((_ whisper: Bool) -> Bool)?
    var onRespond: ((AttentionItem, String?) -> Void)?
    /// A gentle notice faded on its own: it needed no decision, so it is done.
    var onAutoDismiss: ((AttentionItem) -> Void)?
    /// What waits right now, newest last, for the fanned stack.
    var waitingItems: (() async -> [AttentionItem])?
    /// A card went out or came back: the light at the companion's feet follows.
    var onChange: (() -> Void)?
    /// A card folded into the stack: the companion stops looking alarmed; the count says it waits.
    var onFold: ((AttentionItem) -> Void)?
    /// Where the count on the companion's shoulder is on screen, for the stack's arc (D84).
    var badgeProvider: (() -> NSPoint?)?
    /// The stack folding back into the shoulder before it goes.
    var foldBack: Task<Void, Never>?
    /// The keyboard, while its shortcut gave it to the Sidecard (D84): the held cards it moves through, and from when
    /// keys count after a card came to the front (a key held down or meant for the card before can't answer it).
    var holdsKeys = false
    var deckItems: [AttentionItem] = []
    var armedAt = Date.distantPast
    /// Between one card and the next the panel may lose the keyboard for a moment; that isn't the person leaving.
    var passingKeys = false
    /// Dev commands arrive without a key press, and macOS gives the keyboard only after one: the dev path keeps the keys
    /// it was handed (`cardKeys`), so the rest can be checked by hand.
    #if DEBUG
    var devKeys = false
    #else
    var devKeys: Bool { get { false } set {} }
    #endif
    var keyMonitor: Any?
    var keyObserver: NSObjectProtocol?
    /// "Fewer like this" or "Show these as whispers" on a card (D88).
    var onLowerSource: ((AttentionItem, InterruptSource, InterruptLevel) -> Void)?

    init() {
        hosted = HostedPanel(rootView: SidecardView(model: model), allowsKey: false)
        hosted.panel.level = .floating
        // The glass draws its own shadow; a window shadow would be traced from its faint pixels as a grey outline.
        hosted.panel.hasShadow = false
        // VoiceOver's window list names it (D84).
        hosted.panel.setAccessibilityTitle(String(localized: "Sidefolk card", comment: "VoiceOver: the window of the card above the companion"))
        hosted.onPlaced = { [weak self] frame, anchor in self?.aimTail(from: frame, at: anchor) }
        model.respond = { [weak self] item, action in
            // The second click of a double click, on the card that's just come up under it, isn't an answer to it.
            if let self, let shown = self.shownAt, Date().timeIntervalSince(shown) < Self.settling { return }
            self?.close(id: item.id)
            self?.onRespond?(item, action)
        }
        model.grow = { [weak self] in self?.growWhisper() }
        model.lowerSource = { [weak self] item, source, level in
            // The card goes as a whisper would: what needs an answer waits in the stack, news is done.
            self?.autoDismiss(id: item.id)
            self?.onLowerSource?(item, source, level)
        }
        model.openStack = { [weak self] in
            self?.hideStack()
            self?.onOpenStack?()
        }
        installKeys()
    }

    private var shownAt: Date?
    private static let settling: TimeInterval = 0.4

    /// The stack was clicked: what waits comes forward.
    var onOpenStack: (() -> Void)?

    var currentId: String? { model.shape == .stack ? nil : model.item?.id }
    /// A card (not a whisper) is out asking now.
    var cardOut: Bool { hosted.panel.isVisible && model.shape == .card }
    /// Where the card stands, for what must stay clear of it (D99).
    var visibleFrame: NSRect? { hosted.panel.isVisible ? hosted.panel.frame : nil }

    func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        if model.item?.id == item.id, model.shape != .stack { return }
        let card = Self.isCard(item, presentation)
        if holds?(!card) == true {
            if !queue.contains(where: { $0.0.id == item.id }) { queue.append((item, presentation)) }
            return
        }
        if hosted.panel.isVisible, model.shape != .stack, let current = model.item {
            // A whisper never pushes anything aside: it waits its turn.
            guard card else {
                queue.append((item, presentation))
                return
            }
            // A new card: a card in front folds into the stack (it still waits there), a whisper waits its turn.
            // A question doesn't fold, though: someone's waiting on it, so what's new takes its turn after.
            if model.shape == .card, current.refKind == "ask" {
                queue.append((item, presentation))
                return
            }
            if model.shape == .card { fold(current) } else { queue.insert((current, .gentle(autoDismiss: AttentionPolicy.gentleSeconds)), at: 0) }
        }
        show(item, presentation, card: card)
    }

    func withdraw(id: String) {
        queue.removeAll { $0.0.id == id }
        // Answered somewhere else while the held cards are out: it goes from them too.
        if model.stack.contains(where: { $0.id == id }) {
            model.stack.removeAll { $0.id == id }
            if model.stack.isEmpty { hideStack() }
        }
        if model.item?.id == id, model.shape != .stack { close(id: id) }
    }

    /// How many wait now; when the last folded card was answered, the companion says "All clear" once.
    func setWaiting(_ count: Int) {
        model.waiting = count
        if count == 0, !folded.isEmpty {
            folded.removeAll()
            allClear()
        }
        if model.shape == .stack, count == 0 { hideStack() }
    }

    func reposition() {
        guard hosted.panel.isVisible, let (anchor, screen) = anchorProvider?() else { return }
        place(anchor, screen)
    }

    // MARK: Moments

    /// Attention, a card that stays, the morning brief; everything else gentle is a whisper.
    static func isCard(_ item: AttentionItem, _ presentation: AttentionPresentation) -> Bool {
        if item.refKind == "brief" { return true }
        if case .gentle = presentation { return false }
        return true
    }

    private func show(_ item: AttentionItem, _ presentation: AttentionPresentation, card: Bool) {
        fanEnd?.cancel()
        shownAt = Date()
        model.item = item
        model.shape = card ? .card : .whisper
        followSpaces()
        model.pausedLeft = nil
        timer?.cancel()
        switch presentation {
        case .gentle(let seconds) where !card:
            model.whisperSeconds = seconds
            model.deadline = Date().addingTimeInterval(seconds)
            watchWhisper(item)
        case .gentle:
            // A gentle card (the morning brief) needs nothing: it goes after a while, never under the pointer.
            schedule(after: AttentionPolicy.expandSeconds) { [weak self] in self?.autoDismiss(id: item.id) }
        case .attention(let expandFor):
            // Questions never fold: their answers must stay one click away.
            if item.refKind != "ask", Self.folds(item) { schedule(after: expandFor) { [weak self] in self?.foldCurrent(id: item.id) } }
        case .system(_, alsoOnDesktop: true):
            if Self.folds(item) { schedule(after: AttentionPolicy.expandSeconds) { [weak self] in self?.foldCurrent(id: item.id) } }
        default:
            break
        }
        appear()
        // With the keyboard on the Sidecard, it follows whatever card comes to the front; a whisper gives it back.
        if holdsKeys { if card { focusKeys(on: item) } else { releaseKeys() } }
        // The panel takes the keyboard only from its shortcut, so VoiceOver hears a new moment rather than finding it: what it is, and
        // for a card that it waits for an answer.
        let words = card ? String(localized: "\(item.title). It waits for your answer beside \(model.companionName).",
                                  comment: "VoiceOver, when a card appears beside the companion: its title, then that it waits")
                         : item.title
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: (card ? NSAccessibilityPriorityLevel.high : .medium).rawValue])
        onChange?()
    }

    /// Only what the attention center keeps waits in the stack; the companion's own lines (onboarding) stay out.
    static func folds(_ item: AttentionItem) -> Bool {
        item.source != Onboarding.source && item.source != AppCoordinator.ownVoice
    }

    func appear() {
        guard let (anchor, screen) = anchorProvider?() else { return }
        // Sized to this moment first: a visible panel keeps its size when placed.
        hosted.panel.setContentSize(hosted.fittingSize)
        place(anchor, screen)
        // SwiftUI lays the new moment out on its next pass: measured now, a taller card replacing a shorter one is
        // cut at the top (onboarding's last card), so it is measured again then.
        DispatchQueue.main.async { [weak self] in self?.refit() }
        guard !hosted.panel.isVisible else { return }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        hosted.panel.alphaValue = 0
        hosted.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = still ? 0.15 : 0.2
            hosted.panel.animator().alphaValue = 1
        }
    }

    private func refit() {
        guard hosted.panel.isVisible, let (anchor, screen) = anchorProvider?() else { return }
        let size = hosted.fittingSize
        guard size != hosted.panel.frame.size else { return }
        hosted.panel.setContentSize(size)
        place(anchor, screen)
    }

    private func place(_ anchor: NSRect, _ screen: NSScreen) {
        // The tail's tip lands just above the head; the margin under the glass is the shadow's room.
        hosted.place(beside: anchor, on: screen, gap: 4 - SidecardView.margin.bottom, preferAbove: true) { [weak model] in
            // Standing above, it has its tail: a card without one now must fit with it, or it would fit, grow, not fit, and never settle (`CardPlacement`).
            model?.tailAt == nil ? SidecardShape.tailSize.height : 0
        }
    }

    /// The whisper runs out its time unless the pointer holds it; leaving gives it three more seconds (b02).
    private func watchWhisper(_ item: AttentionItem) {
        timer = Task { [weak self] in
            while let self, !Task.isCancelled, self.model.item?.id == item.id, self.model.shape == .whisper {
                // Nobody sees it over a full-screen app: its time doesn't run there (D138).
                if self.model.hovering || (self.hidesOverFullScreen && self.overFullScreenNow) {
                    if self.model.pausedLeft == nil {
                        self.model.pausedLeft = max(0, self.model.deadline?.timeIntervalSinceNow ?? 0)
                        self.model.deadline = nil
                    }
                } else if self.model.pausedLeft != nil {
                    self.model.pausedLeft = nil
                    self.model.deadline = Date().addingTimeInterval(min(3, self.model.whisperSeconds))
                } else if let deadline = self.model.deadline, deadline <= Date() {
                    self.autoDismiss(id: item.id)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func growWhisper() {
        guard let item = model.item, model.shape == .whisper else { return }
        timer?.cancel()
        model.shape = .card
        followSpaces()
        model.pausedLeft = nil
        // Grown on purpose, it stays until answered or closed.
        appear()
        onChange?()
    }

    private func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            // Hovering keeps it open, and so does the keyboard on it; look again shortly.
            if self.model.hovering || self.model.keys != nil { self.schedule(after: 2, action) } else { action() }
        }
    }

    func autoDismiss(id: String) {
        guard let item = model.item, item.id == id else { return }
        // A card its source turned into a whisper (D88) still needs its answer: it folds into the stack, as a card does.
        if item.level >= .attention, Self.folds(item) {
            fold(item)
            close(id: id)
            return
        }
        close(id: id)
        onAutoDismiss?(item)
    }

    /// Nobody answered in time: the card shrinks into the count on the shoulder, where it still waits.
    func foldCurrent(id: String) {
        guard let item = model.item, item.id == id, model.shape == .card else { return }
        fold(item)
        hide()
        next()
    }

    private func fold(_ item: AttentionItem) {
        // The companion's own lines (onboarding) wait nowhere: they give way, and never make an "All clear".
        guard Self.folds(item) else { return }
        flyToShoulder(item)
        folded.insert(item.id)
        onFold?(item)
    }

    private func close(id: String) {
        guard model.item?.id == id else { return }
        timer?.cancel()
        folded.remove(id)
        hide()
        next()
    }

    private func next() {
        guard let first = queue.firstIndex(where: { holds?(!Self.isCard($0.0, $0.1)) != true }) else { return }
        let (item, presentation) = queue.remove(at: first)
        show(item, presentation, card: Self.isCard(item, presentation))
    }

    var isUnderPointer: Bool { hosted.panel.isVisible && hosted.panel.frame.contains(NSEvent.mouseLocation) }

    /// The space or front app changed: what was held may have somewhere to show now.
    func spaceChanged() {
        followSpaces()
        if !hosted.panel.isVisible { next() }
    }

    private func followSpaces() {
        let hide = hidesOverFullScreen && overFullScreenNow && model.shape != .card
        // Only ever undoing its own: the panel's fades are nobody else's business.
        if hide { hosted.panel.alphaValue = 0 } else if hiddenOverFullScreen { hosted.panel.alphaValue = 1 }
        hiddenOverFullScreen = hide
    }

    private func hide() {
        model.item = nil
        model.keys = nil
        hosted.panel.orderOut(nil)
        onChange?()
    }

    /// Ask opened beside the companion: a card folds into the stack (Ask shows it on top, under "Needs you") and a
    /// whisper, which needed nothing, goes; one surface at a time.
    func yieldToAsk() {
        // What's held has yet to be seen, so it still waits (D138).
        if holds?(true) != true { queue.removeAll { !Self.isCard($0.0, $0.1) } }
        guard hosted.panel.isVisible else { return }
        switch model.shape {
        case .card:
            guard let item = model.item else { return }
            if Self.folds(item) {
                foldCurrent(id: item.id)
            } else {
                // The companion's own card (onboarding) waits behind Ask and comes back when it closes.
                timer?.cancel()
                parked = item
                hosted.panel.orderOut(nil)
            }
        case .whisper:
            if let item = model.item { autoDismiss(id: item.id) }
        case .stack:
            hideStack()
        }
    }

    /// Ask closed: a card of the companion's own that waited behind it comes back.
    func askClosed() {
        guard let item = parked else { return }
        parked = nil
        guard !hosted.panel.isVisible || model.item?.id == item.id else { return queue.insert((item, .attention(expandFor: 600)), at: 0) }
        show(item, .attention(expandFor: 600), card: true)
    }

    // MARK: The stack

    /// The pointer is on the count: the top three fan out. Leaving it, they fold back unless the pointer moved onto
    /// them.
    func fanStack(_ show: Bool) {
        fanEnd?.cancel()
        if show {
            guard !hosted.panel.isVisible || model.shape == .stack else { return }
            // Back on the count while the cards fold away: they come out again.
            if foldBack != nil {
                foldBack?.cancel()
                foldBack = nil
                model.stackOut = true
                return
            }
            Task { [weak self] in
                guard let self, let items = await self.waitingItems?(), !items.isEmpty else { return }
                self.model.stack = items
                self.model.item = nil
                self.model.shape = .stack
                self.followSpaces()
                self.appear()
                self.fanOut()
            }
        } else if model.shape == .stack {
            fanEnd = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, !self.model.hovering else { return }
                self.hideStack()
            }
        }
    }

    func hideStack() {
        guard model.shape == .stack else { return }
        model.stackFocus = nil
        // The held cards fold back into the shoulder along their arc, then the panel goes (D84).
        guard model.fanFrom != nil, hosted.panel.isVisible, foldBack == nil else { return putStackAway() }
        model.stackOut = false
        foldBack = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self else { return }
            self.foldBack = nil
            if self.model.shape == .stack, !self.model.stackOut { self.putStackAway() }
        }
    }

    private func putStackAway() {
        foldBack?.cancel()
        foldBack = nil
        model.stack = []
        model.shape = .whisper
        model.stackOut = true
        hosted.panel.orderOut(nil)
        next()
    }

    /// Whether the companion's own remarks may show (Settings › Attention, D88).
    var remarksShown: () -> Bool = { true }

    /// The last held card was answered: said once, the only celebration on the desktop (b06).
    private func allClear() {
        guard remarksShown() else { return }
        let item = AttentionItem(level: .gentle, source: AppCoordinator.ownVoice,
                                 title: String(localized: "All clear. Nothing waits for you.", comment: "A whisper when the last held card was answered"),
                                 refKind: "clear")
        present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
    }

    /// Points the tail at the head, along the card's bottom edge; a card that had to sit below has none.
    private func aimTail(from frame: NSRect, at anchor: NSRect) {
        let margin = SidecardView.margin
        guard frame.minY + margin.bottom >= anchor.midY else {
            model.tailAt = nil
            return
        }
        let width = frame.width - margin.leading - margin.trailing
        let physical = (anchor.midX - frame.minX - margin.leading) / max(width, 1)
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        model.tailAt = min(max(rtl ? 1 - physical : physical, 0), 1)
    }
}
