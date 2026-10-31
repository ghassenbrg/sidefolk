import AppKit
import SidefolkCore
import SwiftUI

/// The Play panel beside the companion (D75). It takes the keyboard when the person opened it (their words, the Play
/// menu, Home), like the Ask panel, and waits for a click when the AI did. Esc or ✕ puts it away; a game put away is
/// kept ten minutes and comes back as it was if opened again. Only one of the Ask and Play panels shows at a time.
@MainActor
final class PlayPanelController {
    private let holder = PlayHolder()
    private lazy var hosted: HostedPanel<PlayRoot> = {
        let hosted = HostedPanel(rootView: PlayRoot(holder: holder), allowsKey: true)
        hosted.panel.onCancel = { [weak self] in self?.hide() }
        return hosted
    }()
    private var keyMonitor: Any?
    private var expiry: Task<Void, Never>?
    /// How long a game put away is kept.
    static let keptFor: TimeInterval = 600

    var model: PlayModel? { holder.model }
    var isVisible: Bool { hosted.panel.isVisible }
    var frame: NSRect { hosted.panel.frame }
    var onVisibilityChange: ((Bool) -> Void)?
    /// The game was kept ten minutes untouched: it ends now.
    var onExpired: ((PlayModel) -> Void)?
    var onSpeaker: (() -> Void)? {
        get { holder.onSpeaker }
        set { holder.onSpeaker = newValue }
    }

    /// The game kept, if it is `info` and was put away less than ten minutes ago.
    func kept(_ info: GameInfo) -> PlayModel? {
        guard let model = holder.model, model.info == info, model.failure == nil,
              Date().timeIntervalSince(model.lastActive) < Self.keptFor else { return nil }
        return model
    }

    func show(_ model: PlayModel, beside anchor: NSRect, on screen: NSScreen, focus: Bool) {
        expiry?.cancel()
        holder.model = model
        hosted.place(beside: anchor, on: screen)
        hosted.panel.orderFrontRegardless()
        if focus { hosted.panel.makeKey() }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.hosted.panel, let model = self.holder.model else { return event }
                // A text field being typed in (an idiom through the input method, an animal's name) keeps its keys.
                if self.hosted.panel.firstResponder is NSTextView { return event }
                guard !event.modifierFlags.contains(.command), let key = Self.key(event) else { return event }
                // Return and Space are the board's alone: never a press of whichever header button has the focus.
                return model.press(key, at: event.timestamp) || key == "return" || key == "space" ? nil : event
            }
        }
        onVisibilityChange?(true)
    }

    func reposition(beside anchor: NSRect, on screen: NSScreen) {
        guard isVisible else { return }
        hosted.place(beside: anchor, on: screen)
    }

    /// Puts the panel away, keeping the game ten minutes.
    func hide() {
        guard isVisible else { return }
        hosted.panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onVisibilityChange?(false)
        guard let model = holder.model else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.keptFor))
            guard !Task.isCancelled, let self, self.holder.model === model, !self.isVisible else { return }
            self.holder.model = nil
            self.onExpired?(model)
        }
    }

    /// Forgets the game kept (another one is opening, or it ended).
    func drop() {
        expiry?.cancel()
        holder.model = nil
    }

    /// The board's name for a key: a letter or digit, `return` or `space`.
    static func key(_ event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76: return "return"
        case 49: return "space"
        case 51: return "delete"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default:
            // The character the key types in the person's layout (é, ñ, an Arabic letter), not the one printed on it.
            guard let c = (event.characters ?? event.charactersIgnoringModifiers)?.lowercased(), c.count == 1,
                  c.first!.isLetter || c.first!.isNumber || c == "?" else { return nil }
            return c
        }
    }
}

@MainActor @Observable
final class PlayHolder {
    var model: PlayModel?
    var onSpeaker: (() -> Void)?
}

struct PlayRoot: View {
    var holder: PlayHolder

    var body: some View {
        if let model = holder.model {
            PlayView(model: model) { holder.onSpeaker?() }
        } else {
            Color.clear.frame(width: PlayView.width, height: 10)
        }
    }
}
