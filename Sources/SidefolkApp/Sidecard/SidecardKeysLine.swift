import SidefolkCore
import SwiftUI

/// What the keys do while a card has the keyboard (D84), in one quiet line above its answers: ↩ (or ⌘↩ on a firm card)
/// answers, ⎋ puts it away, ↑↓ and where it stands among the held cards. A Return that met a firm card makes ⌘↩ flash.
struct SidecardKeysLine: View {
    var keys: CardKeys
    var nudge: Int
    /// Esc closes a card nothing holds (the companion's own lines) rather than putting it back in the stack.
    var closes = false
    @State private var flash = false

    var body: some View {
        ButtonRow(spacing: Theme.Space.s) {
            pair(keys.takesReturn ? "↩" : "⌘↩", Text("answers", comment: "Beside a ↩ key hint on a card that has the keyboard"), lit: flash)
            pair("⎋", closes ? Text("closes", comment: "Beside a ⎋ key hint on a card that has the keyboard and nothing holds")
                                : Text("puts it away", comment: "Beside a ⎋ key hint on a card that has the keyboard: back to the stack"))
            if let position = keys.position {
                pair("↑↓", Text("\(position.index) of \(position.count)", comment: "Beside a ↑↓ key hint on a card: which held card this is"))
            }
        }
        .onChange(of: nudge) {
            withAnimation(Theme.Motion.ease(0.12)) { flash = true } completion: {
                withAnimation(Theme.Motion.ease(0.4)) { flash = false }
            }
        }
    }

    private func pair(_ key: String, _ words: Text, lit: Bool = false) -> some View {
        HStack(spacing: 4) {
            KeyHint(key)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.accent, lineWidth: lit ? 1.5 : 0))
            words.font(Theme.Font.caption).foregroundStyle(lit ? Theme.link : Theme.inkMuted).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
