import SidefolkCore
import SwiftUI

/// The approval mode, in view wherever requests start (D37). Full access is filled with the danger
/// colour so it can't be missed; the others stay quiet. Clicking it opens where the mode is chosen.
struct ModeChip: View {
    var mode: GuardMode
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: mode.symbol).imageScale(.small)
                Text(verbatim: mode.chipTitle).lineLimit(1)
            }
            .font(Theme.Font.captionStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(Text(verbatim: mode.explanation))
        .accessibilityLabel(Text("Approval mode: \(mode.title)"))
        .accessibilityHint(Text(verbatim: mode.explanation))
    }

    private var foreground: Color {
        switch mode {
        case .fullAccess: Theme.onDanger
        case .auto: Theme.ink
        case .askEveryTime, .askOncePerKind: Theme.inkMuted
        }
    }

    private var background: Color {
        switch mode {
        case .fullAccess: Theme.danger
        case .auto: Theme.accentSoft
        case .askEveryTime, .askOncePerKind: Theme.surfaceSunken
        }
    }
}
