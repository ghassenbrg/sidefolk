import SidefolkCore
import SwiftUI

@MainActor @Observable
final class BubbleModel {
    var item: AttentionItem?
    var expanded = true
    var waitingCount = 0
    var hovering = false
    var respond: ((AttentionItem, String?) -> Void)?
}

/// A speech bubble from the companion: the thing first, a short line, up to three verbs.
struct BubbleView: View {
    @Bindable var model: BubbleModel

    var body: some View {
        if let item = model.item {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    // The companion's own voice needs no icon; notices from things it watches get one.
                    if item.source != "onboarding" {
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
                    HStack(spacing: 6) {
                        ForEach(item.actions.prefix(3), id: \.id) { action in
                            Button(action.title) { model.respond?(item, action.id) }
                                .buttonStyle(.sf(action.isPrimary ? .primary : .secondary))
                        }
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
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(10)
            .onHover { model.hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.title)
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
