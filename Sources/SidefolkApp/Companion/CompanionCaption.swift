import AppKit
import SidefolkCore
import SwiftUI

/// The click-through layer above the companion: one line of text, a prop it holds and a short effect (a surface's reaction, D99).
/// It never takes a click: catch-me needs them all.
final class CompanionCaption {
    let model = CaptionModel()
    private lazy var hosted: HostedPanel<CaptionView> = {
        let hosted = HostedPanel(rootView: CaptionView(model: model), allowsKey: false)
        hosted.panel.ignoresMouseEvents = true
        hosted.panel.hasShadow = false
        return hosted
    }()
    private var hiding: Task<Void, Never>?
    private var effectEnd: Task<Void, Never>?
    var anchorProvider: (() -> (NSRect, NSScreen)?)?

    /// Shows `text`, for `seconds` when given (then it goes), otherwise until the next line.
    func show(_ text: String, for seconds: TimeInterval? = nil) {
        hiding?.cancel()
        model.text = text
        if !text.isEmpty {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        present()
        guard let seconds else { return }
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// What the companion holds (balloons, a crown), until the surface closes or it puts it away.
    func hold(_ prop: CompanionCue.Prop?) {
        model.prop = prop == CompanionCue.Prop.none ? nil : prop
        present()
    }

    /// A short mark above it (confetti, a "?"), gone after a moment.
    func flash(_ effect: CompanionCue.Effect) {
        if effect.moves, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        model.effect = (effect, Date())
        present()
        effectEnd?.cancel()
        effectEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CaptionView.effectSeconds))
            guard !Task.isCancelled, let self else { return }
            self.model.effect = nil
            self.settle()
        }
    }

    private func present() {
        reposition()
        if !hosted.panel.isVisible { hosted.panel.orderFrontRegardless() }
    }

    func reposition() {
        guard let (anchor, screen) = anchorProvider?() else { return }
        // Sized to this line first: a visible panel keeps its size when placed, and a longer line would be cut.
        hosted.panel.setContentSize(hosted.fittingSize)
        hosted.place(beside: anchor, on: screen, gap: 2, preferAbove: true)
    }

    /// Hides the panel once nothing is left in it.
    private func settle() {
        if model.isEmpty { hosted.panel.orderOut(nil) } else { reposition() }
    }

    /// The line goes; a held prop stays.
    func hide() {
        hiding?.cancel()
        model.text = ""
        settle()
    }

    /// Everything goes, the prop too.
    func clear() {
        model.prop = nil
        model.effect = nil
        hide()
    }
}

@MainActor @Observable
final class CaptionModel {
    var text = ""
    var prop: CompanionCue.Prop?
    var effect: (CompanionCue.Effect, Date)?

    var isEmpty: Bool { text.isEmpty && prop == nil && effect == nil }
}

struct CaptionView: View {
    var model: CaptionModel
    static let effectSeconds: TimeInterval = 1.6

    var body: some View {
        // The words on top; a held prop right above its head.
        VStack(spacing: 6) {
            if !model.text.isEmpty {
                // A whisper of the Sidecard (D84): the same glass as everything else beside the companion; its tail
                // only when nothing stands between it and the head.
                Whisper(text: Text(verbatim: model.text), tail: model.prop == nil ? SidecardTail(edge: .bottom) : nil)
                    .padding(.horizontal, 12).padding(.bottom, 14)
                    .accessibilityHidden(true)
            }
            if let effect = model.effect { EffectMark(effect: effect.0, start: effect.1).accessibilityHidden(true) }
            if let prop = model.prop { PropView(prop: prop).accessibilityHidden(true) }
        }
        .padding(10)
        .fixedSize()
    }
}

/// A short mark above the companion, drawn in code for every companion, 2D and 3D: confetti falls, sparkles twinkle,
/// a "?" bobs.
struct EffectMark: View {
    var effect: CompanionCue.Effect
    var start: Date

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { t in
            let p = still ? 0.5 : min(1, t.date.timeIntervalSince(start) / CaptionView.effectSeconds)
            ZStack {
                switch effect {
                case .confetti:
                    ForEach(0..<14, id: \.self) { i in
                        let x = (Double((i * 37) % 100) / 100 - 0.5) * 150
                        RoundedRectangle(cornerRadius: 1).fill([Theme.coral, Theme.sun, Theme.aqua, Theme.mint, Theme.lightBlue][i % 5])
                            .frame(width: 5, height: 9)
                            .rotationEffect(.degrees(p * 540 * (i.isMultiple(of: 2) ? 1 : -1)))
                            .offset(x: x, y: -30 + p * 70 + Double(i % 4) * 6)
                    }
                    .opacity(1 - max(0, p - 0.7) / 0.3)
                default:
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { i in
                            Image(systemName: symbol).font(.system(size: i == 1 ? 22 : 15, weight: .bold)).foregroundStyle(color)
                                .offset(y: -sin((p * 2 + Double(i) * 0.3) * .pi) * 6)
                        }
                    }
                    .scaleEffect(0.6 + min(p * 4, 1) * 0.4)
                    .opacity(1 - max(0, p - 0.75) / 0.25)
                }
            }
            .frame(width: 160, height: 44)
        }
    }

    private var count: Int { [.question, .exclaim, .sweat].contains(effect) ? 1 : 3 }

    private var symbol: String {
        switch effect {
        case .confetti, .sparkles: "sparkles"
        case .hearts: "heart.fill"
        case .question: "questionmark"
        case .exclaim: "exclamationmark"
        case .sweat: "drop.fill"
        case .stars: "star.fill"
        case .frost: "snowflake"
        case .flame: "flame.fill"
        }
    }

    private var color: Color {
        switch effect {
        case .hearts: Theme.coral
        case .sweat, .frost: Theme.lightBlue
        case .flame: Color(hex: 0xFF8A3D)
        case .question, .exclaim: Theme.ink
        default: Theme.sun
        }
    }
}

/// A small card face down: it has picked and isn't telling.
private struct SealedCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, Theme.navy.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5).padding(2)
            Circle().fill(Theme.folkColor("play").opacity(0.4)).frame(width: 14, height: 14)
        }
        .frame(width: 22, height: 30)
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

/// What the companion holds above its head: balloons, a hat, a crown, a magnifier, cards, its sealed card,
/// a gem. Overlays drawn in code, so every companion can hold them.
struct PropView: View {
    var prop: CompanionCue.Prop

    var body: some View {
        Group {
            switch prop {
            case .balloons(let n):
                HStack(spacing: -4) {
                    ForEach(0..<n, id: \.self) { i in
                        Image(systemName: "balloon.fill").font(.system(size: 22)).foregroundStyle([Theme.coral, Theme.sun, Theme.aqua, Theme.mint][i % 4])
                            .offset(y: Double(i % 2) * -6)
                    }
                }
            case .crown: Image(systemName: "crown.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.sun)
                .shadow(color: Color(hex: 0x8A5A00).opacity(0.4), radius: 1, y: 1)
            case .hat: Image(systemName: "party.popper.fill").font(.system(size: 24)).foregroundStyle(Theme.coral)
            case .magnifier: Image(systemName: "magnifyingglass").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.navy)
            case .cards: Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill").font(.system(size: 22)).foregroundStyle(Theme.folkColor("play"))
            case .sealedCard: SealedCard().scaleEffect(1.3)
            case .gem: Image(systemName: "diamond.fill").font(.system(size: 22)).foregroundStyle(Theme.aqua)
            case .none: EmptyView()
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}
