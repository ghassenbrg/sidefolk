import SidefolkCore
import SwiftUI

@MainActor @Observable
final class BubbleModel {
    var item: AttentionItem?
    var expanded = true
    var waitingCount = 0
    var hovering = false
    var respond: ((AttentionItem, String?) -> Void)?
    /// Where the tail meets the bubble, from its left edge; on the top edge when the bubble sits below.
    var tail: Tail?

    struct Tail: Equatable {
        var onTop: Bool
        var x: CGFloat
    }
}

/// A speech bubble from the companion: the thing first, a short line, up to three verbs.
struct BubbleView: View {
    @Bindable var model: BubbleModel

    var body: some View {
        if let item = model.item {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // The very first hello introduces the whole family, not just the one on the desktop.
                if item.refKind == Onboarding.welcome, model.expanded, let family = BrandAsset.familyColor.image {
                    Image(nsImage: family).resizable().scaledToFit().frame(height: 84)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    // The companion's own voice needs no icon; notices from things it watches get one.
                    if item.source != Onboarding.source, item.source != AppCoordinator.ownVoice {
                        Image(systemName: symbol(for: item)).foregroundStyle(accent(for: item)).font(.system(size: 14, weight: .semibold))
                            .padding(.top, 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(Theme.Font.bubbleTitle).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.expanded, let body = item.body, !body.isEmpty {
                            Text(body).font(Theme.Font.bubble).foregroundStyle(Theme.inkMuted)
                                .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Button { model.respond?(item, nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                // Buttons stay when the bubble shrinks: a collapsed reminder can still be answered.
                if !item.actions.isEmpty {
                    // One row when the verbs fit; stacked, never cut off, when a language makes them longer.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { actions(item) }
                        VStack(alignment: .leading, spacing: 6) { actions(item) }
                    }
                }
                if model.waitingCount > 1 {
                    Text("+\(model.waitingCount - 1) more waiting").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(Theme.Space.m)
            .frame(width: 300, alignment: .leading)
            .background(Theme.surface)
            .contentShape(Rectangle())
            .onTapGesture { model.expanded = true }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous).strokeBorder(accent(for: item).opacity(0.45), lineWidth: 1))
            .overlay {
                if let tail = model.tail {
                    // `tail.x` is measured on screen from the left edge, toward the companion, so the
                    // tail is placed left to right even when the text reads right to left.
                    BubbleTail(border: accent(for: item).opacity(0.45), pointsUp: tail.onTop)
                        .frame(width: BubbleTail.width, height: BubbleTail.height)
                        .offset(x: tail.x - BubbleTail.width / 2, y: tail.onTop ? 1 - BubbleTail.height : BubbleTail.height - 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tail.onTop ? .topLeading : .bottomLeading)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(Self.margin)
            .onHover { model.hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.title)
        }
    }

    /// Room around the card for its shadow and tail.
    static let margin: CGFloat = 10

    private func actions(_ item: AttentionItem) -> some View {
        ForEach(item.actions.prefix(3), id: \.id) { action in
            Button { model.respond?(item, action.id) } label: { Text(verbatim: action.title) }
                .buttonStyle(.sf(action.isPrimary ? .primary : .secondary))
        }
    }

    private func symbol(for item: AttentionItem) -> String {
        switch item.refKind ?? item.source {
        case "reminder": "alarm.fill"
        case "watcher": "binoculars.fill"
        case "job": "terminal.fill"
        case "session": "sparkles"
        case "summary": "tray.full.fill"
        case "brief": "sun.max.fill"
        default: item.level == .critical ? "exclamationmark.circle.fill" : "bubble.left.fill"
        }
    }

    private func accent(for item: AttentionItem) -> Color {
        switch item.refKind ?? item.source {
        case "reminder", "brief": Theme.folkColor("tempo")
        case "watcher": Theme.folkColor("scout")
        case "job", "session": Theme.folkColor("byte")
        default: item.level == .critical ? Theme.coral : Theme.aqua
        }
    }
}

/// The little point that makes a bubble the companion's speech. Its base overlaps the card's border
/// by a point so the border looks open where the tail joins.
struct BubbleTail: View {
    static let width: CGFloat = 16
    static let height: CGFloat = 9
    var border: Color
    var pointsUp: Bool

    var body: some View {
        ZStack {
            outline(closed: true).fill(Theme.surface)
            outline(closed: false).stroke(border, lineWidth: 1)
        }
        .scaleEffect(x: 1, y: pointsUp ? -1 : 1)
    }

    private func outline(closed: Bool) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: Self.width / 2, y: Self.height))
            p.addLine(to: CGPoint(x: Self.width, y: 0))
            if closed { p.closeSubpath() }
        }
    }
}
