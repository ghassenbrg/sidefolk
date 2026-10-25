import AppKit
import SidefolkCore
import SwiftUI

/// Presents attention items as bubbles beside the companion, one at a time, with timing from
/// the attention policy: gentle ones fade (paused on hover), attention ones collapse then wait.
final class BubbleController {
    let model = BubbleModel()
    private let hosted: HostedPanel<BubbleView>
    private var queue: [(AttentionItem, AttentionPresentation)] = []
    private var timer: Task<Void, Never>?
    var anchorProvider: (() -> (NSRect, NSScreen)?)?
    var onRespond: ((AttentionItem, String?) -> Void)?

    init() {
        hosted = HostedPanel(rootView: BubbleView(model: model), allowsKey: false)
        hosted.panel.level = .floating
        model.respond = { [weak self] item, action in
            self?.dismiss(id: item.id)
            self?.onRespond?(item, action)
        }
    }

    var currentId: String? { model.item?.id }

    func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        if model.item?.id == item.id { return }
        if model.item != nil, model.item!.level >= item.level, case .gentle = presentation {
            queue.append((item, presentation))
            updateCount()
            return
        }
        if let current = model.item { queue.insert((current, .attention(expandFor: AttentionPolicy.expandSeconds)), at: 0) }
        show(item, presentation)
    }

    func withdraw(id: String) {
        queue.removeAll { $0.0.id == id }
        if model.item?.id == id { dismiss(id: id) }
        updateCount()
    }

    func setBacklog(_ count: Int) {
        model.waitingCount = max(count, queue.count + (model.item == nil ? 0 : 1))
    }

    func reposition() {
        guard hosted.panel.isVisible, let (anchor, screen) = anchorProvider?() else { return }
        hosted.place(beside: anchor, on: screen, gap: 6, preferAbove: true)
    }

    private func show(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        model.item = item
        model.expanded = true
        updateCount()
        guard let (anchor, screen) = anchorProvider?() else { return }
        hosted.place(beside: anchor, on: screen, gap: 6, preferAbove: true)
        hosted.panel.alphaValue = 0
        hosted.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            hosted.panel.animator().alphaValue = 1
        }
        timer?.cancel()
        switch presentation {
        case .gentle(let seconds):
            schedule(after: seconds) { [weak self] in self?.autoDismiss(id: item.id) }
        case .attention(let expandFor):
            schedule(after: expandFor) { [weak self] in self?.collapse(id: item.id) }
        case .system(_, alsoOnDesktop: true):
            schedule(after: AttentionPolicy.expandSeconds) { [weak self] in self?.collapse(id: item.id) }
        default:
            break
        }
    }

    private func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            // Hovering keeps it open; look again shortly.
            if self.model.hovering { self.schedule(after: 2, action) } else { action() }
        }
    }

    private func autoDismiss(id: String) {
        guard model.item?.id == id else { return }
        dismiss(id: id)
    }

    /// Attention items shrink to their title and stay until answered.
    private func collapse(id: String) {
        guard model.item?.id == id else { return }
        model.expanded = false
        reposition()
    }

    private func dismiss(id: String) {
        guard model.item?.id == id else { return }
        timer?.cancel()
        model.item = nil
        hosted.panel.orderOut(nil)
        if !queue.isEmpty {
            let (next, presentation) = queue.removeFirst()
            show(next, presentation)
        }
        updateCount()
    }

    private func updateCount() {
        model.waitingCount = queue.count + (model.item == nil ? 0 : 1)
    }
}
